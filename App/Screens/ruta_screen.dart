import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:localizador_app/services/api_service.dart';

class RutaScreen extends StatefulWidget {
  const RutaScreen({super.key});

  @override
  State<RutaScreen> createState() => _RutaScreenState();
}

class _RutaScreenState extends State<RutaScreen> with SingleTickerProviderStateMixin {
  final ApiService api = ApiService();
  final MapController mapController = MapController();
  List<LatLng> puntos = [];
  bool cargando = true;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  int modoMapa = 0; // 0: claro, 1: colorido, 2: satélite

  // Animación de la ruta
  late final AnimationController _routeController;
  Timer? _followTimer;
  double _t = 0.0;
  final Distance _dist = const Distance();
  List<double> _acum = [];
  double _total = 0.0;
  List<LatLng> _animados = [];
  bool _playing = false;
  bool _follow = true;
  double _currentZoom = 3.0;
  bool _controlsOpen = false;
  //DateTime _lastFollowMove = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    fechaFin = DateTime(now.year, now.month, now.day, 23, 59, 59);
    fechaInicio = fechaFin!.subtract(const Duration(days: 7));

    _routeController = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..addListener(() {
        setState(() {
          _t = _routeController.value;
          _recalcularAnimados();
          _maybeFollowCamera();
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _onCycleCompleted();
        }
      });

    cargarRuta();
  }

  Future<void> cargarRuta() async {
    setState(() => cargando = true);
    try {
      final datos = await api.getRutaPorFechas(fechaInicio!, fechaFin!);
      final rawPoints = datos.map<LatLng>((p) => LatLng(p.latitud, p.longitud)).toList();
      final rutaSuavizada = suavizarRuta(rawPoints, iteraciones: 2);

      setState(() {
        puntos = rutaSuavizada;
        cargando = false;
      });

      // preparar acumulados para animación
      _acum = [];
      _total = 0.0;
      for (int i = 0; i < puntos.length; i++) {
        if (i == 0) {
          _acum.add(0.0);
        } else {
          _total += _dist.distance(puntos[i - 1], puntos[i]);
          _acum.add(_total);
        }
      }
      _recalcularAnimados();

      // Ajuste de cámara inicial: encuadra toda la ruta automáticamente
      try {
        if (puntos.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(puntos);

          // Ajuste automático al tamaño de la ruta
          mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
          );

          // Guarda la cámara actual tras encuadrar
          final z = mapController.camera.zoom;
          final c = mapController.camera.center;

          // Si la ruta es muy pequeña, apenas se acercará.
          final zoomExtra = z < 12 ? 1.5 : 0.8;
          _currentZoom = z + zoomExtra;

          // Pequeño delay para evitar salto visual
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) mapController.move(c, _currentZoom);
          });
        }
      } catch (e) {
        debugPrint('Error ajustando cámara: $e');
      }


      // Arrancar desde el principio
      if (puntos.length > 1) {
        try { _routeController.stop(); } catch (_) {}
        _routeController.value = 0.0;
        _playing = true;
        _follow = true;
        _routeController.forward();
        _startFollowTicker();
      }
    } catch (e) {
      debugPrint('Error cargando ruta: $e');
      setState(() {
        cargando = false;
        puntos = [];
      });
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '--';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/$y';
  }

  void _recalcularAnimados() {
    if (puntos.length < 2 || _total == 0) {
      _animados = puntos;
      return;
    }
    final objetivo = _t * _total;
    int idx = _acum.indexWhere((d) => d >= objetivo);
    if (idx <= 0) {
      final dSeg0 = _acum[1] - _acum[0];
      final frac0 = dSeg0 == 0 ? 0.0 : (objetivo / dSeg0).clamp(0.0, 1.0);
      final interp0 = _interp(puntos[0], puntos[1], frac0);
      _animados = [puntos.first, interp0];
      return;
    }
    final prevIdx = idx - 1;
    final dPrev = _acum[prevIdx];
    final dSeg = (_acum[idx] - dPrev);
    final frac = dSeg == 0 ? 0.0 : ((objetivo - dPrev) / dSeg).clamp(0.0, 1.0);
    final interp = _interp(puntos[prevIdx], puntos[idx], frac);
    final base = puntos.sublist(0, idx);
    _animados = [...base, interp];
  }

  LatLng _interp(LatLng a, LatLng b, double t) =>
      LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);

  @override
  void dispose() {
    try { _routeController.dispose(); } catch (_) {}
    super.dispose();
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: Colors.black87,
      onPressed: onTap,
      tooltip: '',
    );
  }

  Widget _smallFab({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return FloatingActionButton(
      heroTag: null,
      mini: true,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      onPressed: onTap,
      tooltip: tooltip,
      child: Icon(icon, size: 18),
    );
  }

  void _togglePlay() {
    if (_playing) { _stopFollowTicker(); }
    if (_playing) {
      _routeController.stop();
      setState(() => _playing = false);
    } else {
      if (_routeController.value >= 1.0) {
        _routeController.value = 0.0;
        _recalcularAnimados();
      }
      setState(() {
        _playing = true;
        _follow = true;
      });
      _routeController.forward();
      _startFollowTicker();
    }
  }

  void _startFollowTicker() {
    _followTimer?.cancel();
    _followTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_playing && mounted) _maybeFollowCamera();
    });
  }

  void _stopFollowTicker() {
    _followTimer?.cancel();
    _followTimer = null;
  }

  void _goToStart() {
    _routeController.stop();
    _routeController.value = 0.0;
    setState(() => _playing = false);
    _recalcularAnimados();
  }

  void _goToEnd() {
    _routeController.stop();
    _routeController.value = 1.0;
    _recalcularAnimados();
    _onCycleCompleted();
  }

  int _currentIndex() {
    if (_total == 0 || _acum.isEmpty) return 0;
    final objetivo = _t * _total;
    final idx = _acum.indexWhere((d) => d >= objetivo);
    return idx < 0 ? _acum.length - 1 : idx;
  }

  void _stepBack() {
    if (_acum.isEmpty) return;
    final idx = _currentIndex();
    final prev = (idx - 1).clamp(0, _acum.length - 1);
    _routeController.stop();
    _routeController.value = (_acum[prev] / (_total == 0 ? 1 : _total)).clamp(0.0, 1.0);
    setState(() => _playing = false);
    _recalcularAnimados();
  }

  void _stepForward() {
    if (_acum.isEmpty) return;
    final idx = _currentIndex();
    final next = (idx + 1).clamp(0, _acum.length - 1);
    _routeController.stop();
    _routeController.value = (_acum[next] / (_total == 0 ? 1 : _total)).clamp(0.0, 1.0);
    setState(() => _playing = false);
    _recalcularAnimados();
  }

  void _maybeFollowCamera() {
    if (!_playing || !_follow || _animados.isEmpty) return;

    try {
      final target = _animados.last;
      final current = mapController.camera.center;
      final currentZoom = mapController.camera.zoom;

      final meters = _dist.distance(current, target);

      final smoothFactor = (0.05 + (meters / 5000)).clamp(0.05, 0.25);

      final nextCenter = _interp(current, target, smoothFactor);
      final nextZoom = currentZoom + (_currentZoom - currentZoom) * 0.1;

      mapController.move(nextCenter, nextZoom);
    } catch (_) {}

  }

  Future<void> _onCycleCompleted() async {
    _playing = false;
    _follow = false;
    try {
      if (puntos.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(puntos);
        mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
        );
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    _routeController.value = 0.0;
    _recalcularAnimados();
    _follow = true;
    _playing = true;
    _routeController.forward();
    _startFollowTicker();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FB),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 60),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, offset: Offset(2, 2), blurRadius: 4),
                          ],
                        ),
                        child: const Text('Mis Rutas', style: TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _seleccionarFecha(esInicio: true),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text('Inicio: ' + _fmt(fechaInicio), overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _seleccionarFecha(esInicio: false),
                              icon: const Icon(Icons.calendar_month, size: 16),
                              label: Text('Fin: ' + _fmt(fechaFin), overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Actualizar',
                            onPressed: cargarRuta,
                            icon: const Icon(Icons.refresh),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: FlutterMap(
                              mapController: mapController,
                              options: MapOptions(
                                initialCenter: puntos.isNotEmpty ? puntos.first : const LatLng(0, 0),
                                initialZoom: 3,
                                onMapEvent: (ev) {
                                  try { _currentZoom = ev.camera.zoom; } catch (_) {}
                                },
                              ),
                              children: [
                                if (modoMapa == 2) ...[
                                  TileLayer(
                                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'com.example.localizador_app',
                                  ),
                                  TileLayer(
                                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'com.example.localizador_app',
                                  ),
                                ] else
                                  TileLayer(
                                    urlTemplate: modoMapa == 0
                                        ? 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png'
                                        : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    subdomains: const ['a', 'b', 'c'],
                                    userAgentPackageName: 'com.example.localizador_app',
                                  ),
                                if (puntos.isNotEmpty)
                                  PolylineLayer(polylines: [
                                    Polyline(points: puntos, strokeWidth: 5.0, color: const Color(0x335197F3)),
                                  ]),
                                if (_animados.isNotEmpty)
                                  PolylineLayer(polylines: [
                                    Polyline(points: _animados, strokeWidth: 6.0, color: const Color(0xFF2196F3)),
                                  ]),
                                MarkerLayer(markers: [
                                  if (puntos.isNotEmpty)
                                    Marker(
                                      width: 36,
                                      height: 36,
                                      point: puntos.first,
                                      child: const Icon(Icons.flag, color: Colors.green, size: 30),
                                    ),
                                  if (puntos.length > 1)
                                    Marker(
                                      width: 24,
                                      height: 24,
                                      point: _animados.isNotEmpty ? _animados.last : puntos.first,
                                      child: _AnimatedDot(progress: _t),
                                    ),
                                ]),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            right: 20,
                            child: FloatingActionButton(
                              heroTag: 'mapStyleRuta',
                              onPressed: () => setState(() => modoMapa = (modoMapa + 1) % 3),
                              mini: true,
                              backgroundColor: Colors.black87,
                              child: const Icon(Icons.layers, color: Colors.white),
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            left: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                                  child: _controlsOpen
                                      ? Column(
                                          key: const ValueKey('controls-open'),
                                          children: [
                                            _smallFab(icon: Icons.skip_previous, tooltip: 'Ir al inicio', onTap: _goToStart),
                                            const SizedBox(height: 8),
                                            _smallFab(icon: Icons.chevron_left, tooltip: 'Paso atrás', onTap: _stepBack),
                                            const SizedBox(height: 8),
                                            _smallFab(icon: _playing ? Icons.pause : Icons.play_arrow, tooltip: _playing ? 'Pausar' : 'Reproducir', onTap: _togglePlay),
                                            const SizedBox(height: 8),
                                            _smallFab(icon: Icons.chevron_right, tooltip: 'Paso adelante', onTap: _stepForward),
                                            const SizedBox(height: 8),
                                            _smallFab(icon: Icons.skip_next, tooltip: 'Ir al final', onTap: _goToEnd),
                                            const SizedBox(height: 12),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                // Botón de toggle para abrir/cerrar
                                FloatingActionButton(
                                  heroTag: 'toggleControls',
                                  mini: true,
                                  backgroundColor: Colors.black87,
                                  onPressed: () => setState(() => _controlsOpen = !_controlsOpen),
                                  child: Icon(_controlsOpen ? Icons.close : Icons.playlist_play, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _seleccionarFecha({required bool esInicio}) async {
    final inicial = esInicio ? (fechaInicio ?? DateTime.now().subtract(const Duration(days: 7))) : (fechaFin ?? DateTime.now());
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: esInicio ? 'Selecciona fecha de inicio' : 'Selecciona fecha fin',
    );
    if (seleccionada == null) return;
    setState(() {
      if (esInicio) {
        fechaInicio = DateTime(seleccionada.year, seleccionada.month, seleccionada.day);
        if (fechaFin != null && fechaInicio!.isAfter(fechaFin!)) {
          fechaFin = fechaInicio;
        }
      } else {
        fechaFin = DateTime(seleccionada.year, seleccionada.month, seleccionada.day);
        if (fechaInicio != null && fechaFin!.isBefore(fechaInicio!)) {
          fechaInicio = fechaFin;
        }
      }
    });
    await cargarRuta();
  }
}

List<LatLng> suavizarRuta(List<LatLng> puntos, {int iteraciones = 2}) {
  List<LatLng> resultado = List.from(puntos);
  for (int i = 0; i < iteraciones; i++) {
    resultado = _chaikinUnaIteracion(resultado);
  }
  return resultado;
}

List<LatLng> _chaikinUnaIteracion(List<LatLng> puntos) {
  List<LatLng> nuevos = [];
  for (int i = 0; i < puntos.length - 1; i++) {
    final p0 = puntos[i];
    final p1 = puntos[i + 1];
    final q = LatLng(
      0.75 * p0.latitude + 0.25 * p1.latitude,
      0.75 * p0.longitude + 0.25 * p1.longitude,
    );
    final r = LatLng(
      0.25 * p0.latitude + 0.75 * p1.latitude,
      0.25 * p0.longitude + 0.75 * p1.longitude,
    );
    nuevos.add(q);
    nuevos.add(r);
  }
  return nuevos;
}

class _AnimatedDot extends StatelessWidget {
  final double progress;
  const _AnimatedDot({required this.progress});

  @override
  Widget build(BuildContext context) {
    final scale = 0.85 + 0.3 * (1 - (2 * (progress - 0.5)).abs());
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.3,
          child: Container(
            width: 20 * scale,
            height: 20 * scale,
            decoration: const BoxDecoration(
              color: Color(0x442196F3),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFF2196F3),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x662196F3), blurRadius: 6, offset: Offset(0, 2))],
          ),
        ),
      ],
    );
  }
}




