import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'screens/login_screen.dart';
import 'firebase_options.dart';
//import 'screens/estado_screen.dart';
import 'screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  // Considerar sesión válida si hay token o flag 'logueado'
  final tieneSesion = (prefs.getString('token') != null) || (prefs.getBool('logueado') ?? false);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MyApp(tieneSesion: tieneSesion));
}

class MyApp extends StatelessWidget {
  final bool tieneSesion;
  const MyApp({super.key, required this.tieneSesion});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Localizador App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Arial',
      ),
      home: tieneSesion ? const HomeShell() : const LoginScreen(),
    );
  }
}

