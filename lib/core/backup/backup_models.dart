import 'dart:typed_data';

/// Resultado de inspeccionar un archivo de respaldo antes de restaurarlo.
class InspeccionCopia {
  const InspeccionCopia({
    required this.nombreArchivo,
    required this.bytes,
    required this.sha256,
    required this.schemaVersion,
    required this.integridadOk,
    required this.tieneMetadata,
    required this.conteos,
    this.fechaRespaldo,
    this.fechaArchivo,
    this.appVersion,
    this.motivo,
    this.instalacionId,
    this.integridadDetalle,
  });

  final String nombreArchivo;
  final Uint8List bytes;
  final String sha256;
  final int schemaVersion;
  final bool integridadOk;
  final String? integridadDetalle;

  /// `true` si el archivo trae la tabla `app_meta` (respaldos desde la v6).
  final bool tieneMetadata;
  final DateTime? fechaRespaldo;
  final DateTime? fechaArchivo;
  final String? appVersion;
  final String? motivo;
  final String? instalacionId;
  final Map<String, int> conteos;

  int get tamanoBytes => bytes.length;

  /// Una copia de una versión más nueva no se puede abrir con esta app.
  bool versionCompatible(int actual) => schemaVersion <= actual;

  bool esMismaInstalacion(String? actual) =>
      actual == null || instalacionId == null || instalacionId == actual;
}

/// Copia creada por la app, lista para compartir o guardar.
class CopiaCreada {
  const CopiaCreada({
    required this.nombre,
    required this.ruta,
    required this.bytes,
    required this.fecha,
  });

  final String nombre;
  final String ruta;
  final Uint8List bytes;
  final DateTime fecha;

  int get tamanoBytes => bytes.length;
}

/// Copia automática guardada antes de una restauración.
class CopiaSeguridad {
  const CopiaSeguridad({
    required this.nombre,
    required this.ruta,
    required this.fecha,
    required this.tamanoBytes,
    this.motivo,
  });

  final String nombre;
  final String ruta;
  final DateTime fecha;
  final int tamanoBytes;
  final String? motivo;
}
