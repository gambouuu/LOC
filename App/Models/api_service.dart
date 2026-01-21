import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:localizador_app/models/ubicacion.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'IP_SERVER';

  Future<bool> login(String nombre, String contrasena) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/token'),
        body: {
          'nombre': nombre,
          'contraseña': contrasena,
        },
      );

      print('Status code: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data.containsKey('access_token')) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', data['access_token']);
          return true;
        } else {
          print('No se encontró "access_token" en la respuesta');
          return false;
        }
      } else {
        print('Login fallido con status ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Excepción en login: $e');
      return false;
    }
  }


  Future<Map<String, dynamic>> getEstadoActual() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/estado_actual'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Error al obtener estado");
    }
  }

  Future<Ubicacion> getUbicacionActual() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/ubicacion_actual'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return Ubicacion.fromJson(json.decode(response.body));
    } else {
      throw Exception("Error al obtener ubicación");
    }
  }

  Future<List<Ubicacion>> getRuta(int puntos) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/ruta?limite=$puntos'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final List datos = json.decode(response.body);
      return datos.map((e) => Ubicacion.fromJson(e)).toList();
    } else {
      throw Exception("Error al obtener ruta");
    }
  }

  Future<List<Ubicacion>> getRutaPorFechas(DateTime fechaInicio, DateTime fechaFin) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.post(
      Uri.parse('$baseUrl/ruta/fechas'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'fecha_inicio': fechaInicio.toIso8601String(),
        'fecha_fin': fechaFin.toIso8601String(),
      }),
    );

    if (response.statusCode == 200) {
      final List datos = json.decode(response.body);
      return datos.map((e) => Ubicacion.fromJson(e)).toList();
    } else {
      print('Error ${response.statusCode}: ${response.body}');
      throw Exception("Error al obtener ruta por fechas");
    }
  }


  Future<double> getDistancia7Dias() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/distancia_7_dias'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['km_recorridos'] as num).toDouble();
    } else {
      throw Exception("Error al obtener distancia 7 días");
    }
  }

  Future<double> getDistancia30Dias() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/distancia_30_dias'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['km_recorridos'] as num).toDouble();
    } else {
      throw Exception("Error al obtener distancia 30 días");
    }
  }

  Future<bool> registrarUsuario(String correo, String nombre, String contrasena, String codigo) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/registrar'),
        body: {
          'email': correo,
          'nombre': nombre,
          'contraseña': contrasena,
          'codigo': codigo,
        },
      );

      print('Registro status: ${response.statusCode}');
      print('Registro response: ${response.body}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Excepción en registrarUsuario: $e');
      return false;
    }
  }

  Future<void> registrarFcmToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.post(
      Uri.parse('$baseUrl/registrar_token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'fcm_token': fcmToken}),
    );

    if (response.statusCode == 200) {
      print('Token FCM registrado con éxito');
    } else {
      print('Error registrando token FCM: ${response.body}');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

}
