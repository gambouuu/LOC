import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localizador_app/services/api_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
//import 'estado_screen.dart';
import 'home_shell.dart';
import 'registro_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController nombreController = TextEditingController();
  final TextEditingController contrasenaController = TextEditingController();
  final ApiService api = ApiService();
  bool cargando = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final estaLogueado = prefs.getBool('logueado') ?? false;
    final loginTimestamp = prefs.getInt('loginTimestamp') ?? 0;

    if (estaLogueado) {
      final ahora = DateTime.now().millisecondsSinceEpoch;
      const diasPermitidos = 90; 
      final tiempoPermitidoMs = diasPermitidos * 24 * 60 * 60 * 1000;

      if ((ahora - loginTimestamp) < tiempoPermitidoMs) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeShell()),
        );
      } else {
        //borra flags
        await prefs.remove('logueado');
        await prefs.remove('loginTimestamp');
      }
    }
  }

  void login() async {
    setState(() {
      cargando = true;
      error = null;
    });

    print("Paso 1: Empezando login con usuario: ${nombreController.text}");

    final exito = await api.login(nombreController.text, contrasenaController.text);

    print("Paso 2: Resultado del login: $exito");

    if (exito) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logueado', true);
      await prefs.setInt('loginTimestamp', DateTime.now().millisecondsSinceEpoch);

      print("Paso 3: Login exitoso, guardada sesión local.");

      // REGISTRAR EL TOKEN FCM TRAS LOGIN EXITOSO
      try {
        print("Paso 4: Solicitando permiso y obteniendo token FCM...");
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        NotificationSettings settings = await messaging.requestPermission();
        print('Permisos concedidos: ${settings.authorizationStatus}');
        String? fcmToken = await messaging.getToken();
        print('Paso 5: Token FCM obtenido: $fcmToken');

        if (fcmToken != null) {
          print("Paso 6: Enviando token FCM a API...");
          await api.registrarFcmToken(fcmToken);
          print("Paso 7: Token FCM registrado correctamente en el servidor.");
        } else {
          print("Paso 6: Token FCM es null, no se envía nada.");
        }
      } catch (e) {
        print('Paso 8: Error registrando token FCM: $e');
      }

      if (!mounted) return;
      print("Paso 9: Navegando a EstadoScreen...");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } else {
      if (!mounted) return;
      print("Paso 2b: Login fallido, mostrando error.");
      setState(() {
        error = 'Credenciales inválidas o error de conexión';
        cargando = false;
      });
    }
  }


  void irARegistro() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistroScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset("assets/fondo.png", fit: BoxFit.cover),
          Center(
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white.withOpacity(0.9),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Usuario"),
                    TextField(
                      controller: nombreController,
                      decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: contrasenaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: cargando ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: cargando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text("Entrar", style: TextStyle(fontSize: 16)),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: irARegistro,
                      child: const Text(
                        "¿No tienes cuenta? Regístrate",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 8,
            left: 8,
            child: Text(
              "Por Marc Gamboa",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
