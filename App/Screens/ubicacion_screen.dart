import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:localizador_app/services/api_service.dart';
//import 'estado_screen.dart';
//import 'ruta_screen.dart';

class UbicacionScreen extends StatefulWidget {
  const UbicacionScreen({super.key});

  @override
  State<UbicacionScreen> createState() => _UbicacionScreenState();
}

class _UbicacionScreenState extends State<UbicacionScreen> {
  final ApiService api = ApiService();
  String? hora;
  LatLng? ubicacionRemota;
  LatLng? ubicacionLocal;
  double? altitudRemota;
  bool cargando = true;
  int modoMapa = 0; // 0: claro, 1: colorido, 2: satelite
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    // Mapa satelite por defecto
    modoMapa = 2;
    cargarUbicacion();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => cargarUbicacion());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> cargarUbicacion() async {
    try {
      final data = await api.getUbicacionActual();
      setState(() {
        // Ajuste horario (CET/CEST) 
        hora = sumar2Horas(data.horaUtc, fechaReferencia: data.recibidoEn);
        ubicacionRemota = LatLng(data.latitud, data.longitud);
        altitudRemota = data.altitud;
      });
    } catch (e) {
      print("Error cargando ubicación remota: $e");
    }

    try {
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.whileInUse || permiso == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
        setState(() {
          ubicacionLocal = LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (e) {
      print(" Error obteniendo ubicación local: $e");
    }

    setState(() {
      cargando = false;
    });
  }

  String sumar2Horas(String horaUtc, {String? fechaReferencia}) {
    try {
      final partes = horaUtc.split(":");
      if (partes.length != 3) return "--:--:--";

      final hh = int.parse(partes[0]);
      final mm = int.parse(partes[1]);
      final ss = int.parse(partes[2]);

      DateTime fechaBaseUtc;
      try {
        if (fechaReferencia != null && fechaReferencia.isNotEmpty) {
          final parsed = DateTime.parse(fechaReferencia);
          fechaBaseUtc = DateTime.utc(parsed.year, parsed.month, parsed.day, hh, mm, ss);
        } else {
          final nowUtc = DateTime.now().toUtc();
          fechaBaseUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, hh, mm, ss);
        }
      } catch (_) {
        final nowUtc = DateTime.now().toUtc();
        fechaBaseUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, hh, mm, ss);
      }

      final offsetHoras = _offsetEspanaHoras(fechaBaseUtc);
      final ajustado = fechaBaseUtc.add(Duration(hours: offsetHoras));

      final h = ajustado.hour.toString().padLeft(2, '0');
      final m = ajustado.minute.toString().padLeft(2, '0');
      final s = ajustado.second.toString().padLeft(2, '0');

      return "$h:$m:$s";
    } catch (_) {
      return "--:--:--";
    }
  }

  int _offsetEspanaHoras(DateTime instanteUtc) {
    final inicioVerano = _inicioVeranoUtc(instanteUtc.year);
    final finVerano = _finVeranoUtc(instanteUtc.year);
    final enVerano = !instanteUtc.isBefore(inicioVerano) && instanteUtc.isBefore(finVerano);
    return enVerano ? 2 : 1;
  }

  DateTime _inicioVeranoUtc(int year) {
    final ultimoDomingoMarzo = _ultimoDomingoUtc(year, 3);
    return DateTime.utc(year, 3, ultimoDomingoMarzo.day, 1, 0, 0);
  }

  DateTime _finVeranoUtc(int year) {
    final ultimoDomingoOctubre = _ultimoDomingoUtc(year, 10);
    return DateTime.utc(year, 10, ultimoDomingoOctubre.day, 1, 0, 0);
  }

  DateTime _ultimoDomingoUtc(int year, int month) {
    final ultimoDiaMes = DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1));
    final diasARestar = ultimoDiaMes.weekday % 7;
    return ultimoDiaMes.subtract(Duration(days: diasARestar));
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 60),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              offset: Offset(2, 2),
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: const Text(
                          "Ubicación Actual",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          infoCard("Última Actualización", hora ?? "--:--:--"),
                          const SizedBox(height: 16),
                          if (altitudRemota != null)
                            infoCard("Altitud actual", "${(altitudRemota! - 35).toStringAsFixed(1)} m"),
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
                              options: MapOptions(
                                initialCenter: ubicacionRemota ?? LatLng(0, 0),
                                initialZoom: 16,
                              ),
                              children: [
                                if (modoMapa == 2) ...[
                                  // Capa satelite
                                  TileLayer(
                                    urlTemplate:
                                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                                    userAgentPackageName: 'com.example.localizador_app',
                                  ),
                                  // Capa de etiquetas (calles, ciudades)
                                  TileLayer(
                                    urlTemplate:
                                        'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
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
                                MarkerLayer(
                                  rotate: true,
                                  markers: [
                                    if (ubicacionRemota != null)
                                      Marker(
                                        width: 46,
                                        height: 56,
                                        point: ubicacionRemota!,
                                        rotate: true,
                                        alignment: Alignment.topCenter,
                                        child: TweenAnimationBuilder<double>(
                                          key: ValueKey(
                                            '${0}${ubicacionRemota!.latitude.toStringAsFixed(6)},${ubicacionRemota!.longitude.toStringAsFixed(6)}',
                                          ),
                                          tween: Tween(begin: 0.75, end: 1.0),
                                          duration: const Duration(milliseconds: 450),
                                          curve: Curves.easeOutBack,
                                          builder: (context, value, child) {
                                            return Transform.translate(
                                              offset: Offset(0, (1 - value) * 10),
                                              child: Transform.scale(
                                                scale: value,
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Pin blanco con borde suave y sombra para profundidad
                                              Container(
                                                decoration: const BoxDecoration(boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black26,
                                                    blurRadius: 10,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ]),
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: const [
                                                    Icon(Icons.place, color: Colors.black38, size: 44),
                                                    Icon(Icons.place, color: Colors.white, size: 42),
                                                    Positioned(
                                                      top: 12,
                                                      child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          shape: BoxShape.circle,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors.black12,
                                                              blurRadius: 2,
                                                              offset: Offset(0, 1),
                                                            )
                                                          ],
                                                        ),
                                                        child: SizedBox(width: 10, height: 10),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                width: 18,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: Colors.black26,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (ubicacionLocal != null)
                                      Marker(
                                        width: 30,
                                        height: 30,
                                        point: ubicacionLocal!,
                                        rotate: true,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.green,
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.phone_android, color: Colors.white, size: 20),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            right: 20,
                            child: FloatingActionButton(
                              heroTag: 'mapStyleUbicacion',
                              onPressed: () {
                                setState(() => modoMapa = (modoMapa + 1) % 3);
                              },
                              mini: true,
                              backgroundColor: Colors.black87,
                              child: const Icon(Icons.layers, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
                /* Positioned(
                  bottom: 20,
                  left: 30,
                  right: 30,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const EstadoScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                const begin = Offset(-1.0, 0.0); // desde la derecha
                                const end = Offset.zero;
                                const curve = Curves.ease;

                                final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                final offsetAnimation = animation.drive(tween);

                                return SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                        child: const CircleAvatar(
                          backgroundColor: Color(0xFFD9D9D9),
                          child: Icon(Icons.local_shipping, color: Colors.grey),
                        ),
                      ),
                      const CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.location_on, color: Colors.white),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const RutaScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                const begin = Offset(1.0, 0.0); // desde la derecha
                                const end = Offset.zero;
                                const curve = Curves.ease;

                                final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                final offsetAnimation = animation.drive(tween);

                                return SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                        child: const CircleAvatar(
                          backgroundColor: Color(0xFFD9D9D9),
                          child: Icon(Icons.alt_route, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ) */
              ],
            ),
    );
  }

  Widget infoCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 15, color: Colors.black87)),
        ],
      ),
    );
  }
}
