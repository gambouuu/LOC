import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localizador_app/services/api_service.dart';
//import 'ubicacion_screen.dart';
//import 'ruta_screen.dart';
import 'login_screen.dart';

class EstadoScreen extends StatefulWidget {
  const EstadoScreen({super.key});

  @override
  State<EstadoScreen> createState() => _EstadoScreenState();
}

class _EstadoScreenState extends State<EstadoScreen> {
  String? estado;
  String? ultimaActualizacion;
  String? ultimaVezMovimiento;
  String? nombreUsuario;
  double? distancia7dias;
  double? distancia30dias;
  bool cargando = true;
  final ApiService api = ApiService();

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    nombreUsuario = prefs.getString('nombre');

    try {
      final data = await api.getEstadoActual();
      final d7 = await api.getDistancia7Dias();
      final d30 = await api.getDistancia30Dias();

      setState(() {
        estado = data['estado'];
        ultimaActualizacion = data['ultima_actualizacion'];
        ultimaVezMovimiento = data['ultima_vez_en_movimiento'];
        distancia7dias = d7;
        distancia30dias = d30;
        cargando = false;
      });
    } catch (e) {
      print("Error al cargar estado actual: $e");
      setState(() {
        cargando = false;
        estado = 'Error';
      });
    }
  }

  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FB),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 50),

                // Título centrado con botón a la derecha en la misma fila
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Stack(
                    children: [
                      // Título centrado
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                            "Estado Actual",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                      ),
                      // Botón cerrar sesión alineado a la derecha
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: cerrarSesion,
                          icon: const Icon(Icons.logout, size: 20),
                          tooltip: 'Cerrar sesión',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Tarjetas separadas
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      infoCard("Estado", estado ?? ""),
                      const SizedBox(height: 16),
                      infoCard("Última Actualización", ultimaActualizacion ?? ""),
                      const SizedBox(height: 16),
                      infoCard("Último Movimiento", ultimaVezMovimiento ?? "Nunca"),
                      const SizedBox(height: 16),
                      if (distancia7dias != null)
                        infoCard("Distancia últimos 7 días", "${distancia7dias!.toStringAsFixed(2)} km"),
                      const SizedBox(height: 16),
                      if (distancia30dias != null)
                        infoCard("Distancia últimos 30 días", "${distancia30dias!.toStringAsFixed(2)} km"),
                    ],
                  ),
                ),

                const Spacer(),

                // Navegación inferior movida al shell global
                /* Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color.fromRGBO(33, 150, 243, 1),
                        child: Icon(Icons.local_shipping, color: Colors.white),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const UbicacionScreen(),
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
                          child: Icon(Icons.location_on, color: Colors.grey),
                        ),
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
                ), */
              ],
            ),
    );
  }

  // Widget para tarjeta individual de información
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
