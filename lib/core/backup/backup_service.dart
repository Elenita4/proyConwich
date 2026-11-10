// Punto de entrada del respaldo. En la app instalada usa `dart:io`; en web
// carga una implementación que solo informa que la función no está disponible.
export 'backup_models.dart';
export 'backup_service_web.dart' if (dart.library.io) 'backup_service_io.dart';
