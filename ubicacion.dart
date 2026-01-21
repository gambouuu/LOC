class Ubicacion {
  final String horaUtc;
  final double latitud;
  final double longitud;
  final double? altitud;
  final double? hdop;
  final int enMovimiento;
  final String recibidoEn;

  Ubicacion({
    required this.horaUtc,
    required this.latitud,
    required this.longitud,
    this.altitud,
    this.hdop,
    required this.enMovimiento,
    required this.recibidoEn,
  });

  factory Ubicacion.fromJson(Map<String, dynamic> json) {
    return Ubicacion(
      horaUtc: json['hora_utc'],
      latitud: json['latitud'],
      longitud: json['longitud'],
      altitud: json['altitud'],
      hdop: json['hdop'],
      enMovimiento: json['en_movimiento'],
      recibidoEn: json['recibido_en'],
    );
  }
}
