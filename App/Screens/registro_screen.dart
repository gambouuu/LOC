import 'package:flutter/material.dart';
import 'package:localizador_app/services/api_service.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final correoController = TextEditingController();
  final nombreController = TextEditingController();
  final contrasenaController = TextEditingController();
  final codigoController = TextEditingController();
  final ApiService api = ApiService();

  bool cargando = false;
  String? error;
  String? exito;

  void registrar() async {
    setState(() {
      cargando = true;
      error = null;
      exito = null;
    });

    final ok = await api.registrarUsuario(
      correoController.text.trim(),
      nombreController.text.trim(),
      contrasenaController.text.trim(),
      codigoController.text.trim(),
    );

    setState(() {
      cargando = false;
      if (ok) {
        exito = "Usuario registrado correctamente";
      } else {
        error = "Error al registrar. Verifica el código y los datos";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset("assets/fondo.png", fit: BoxFit.cover),
          //Image.asset("assets/fondo3.jpg", fit: BoxFit.cover),
          Center(
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white.withOpacity(0.9),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Correo electrónico"),
                      TextField(controller: correoController),
                      const SizedBox(height: 16),
                      const Text("Nombre de usuario"),
                      TextField(controller: nombreController),
                      const SizedBox(height: 16),
                      const Text("Contraseña"),
                      TextField(controller: contrasenaController, obscureText: true),
                      const SizedBox(height: 16),
                      const Text("Código de verificación"),
                      TextField(controller: codigoController),
                      const SizedBox(height: 24),
                      /*ElevatedButton(
                        onPressed: cargando ? null : registrar,
                        child: cargando
                            ? const CircularProgressIndicator()
                            : const Text("Crear cuenta"),
                      ),*/
                      ElevatedButton(
                      onPressed: cargando ? null : registrar,
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
                          : const Text("Registrarse", style: TextStyle(fontSize: 16)),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!, style: const TextStyle(color: Colors.red)),
                        ),
                      if (exito != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(exito!, style: const TextStyle(color: Colors.green)),
                        ),
                    ],
                  ),
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
