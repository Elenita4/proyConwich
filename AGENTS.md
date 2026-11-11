# AGENTS.md

Flutter app (POS de restaurante "Sazón"). Paquete Dart: `test_code_02` — los imports usan
`package:test_code_02/...`, NO el nombre de la app.

## Comandos
- `flutter pub get`
- `flutter analyze` — `analysis_options.yaml` excluye build/ y todas las carpetas de plataforma
- `flutter test` — corre unit + "integración" de BD (usa sqflite_common_ffi, no requiere dispositivo).
  `dart_test.yaml` fija `concurrency: 1` porque todos los archivos comparten la misma BD SQLite.
- `flutter run` (o `flutter run -d chrome` para web)
- `flutter build apk` / `flutter build web` — build de release

## Build / plataformas
- Android: `applicationId`/namespace `com.example.test_code_02`, Java/Kotlin 17,
  minSdk/targetSdk/compileSdk toman los defaults de Flutter. Gradle wrapper 9.3.1, AGP 9.1.0,
  Kotlin 2.4.0. El release firma con las debug keys (sin keystore propio). versionName/versionCode
  salen de `pubspec.yaml` (1.0.0+1).
- iOS: bundle id `com.example.testCode02`. Web: `<title>` = `test_code_02`.

## Arquitectura
- Sin gestor de estado: `setState` + singletons (`Sesion.instance`). Las páginas usan repositorios directamente.
- `lib/features/<feature>/presentation/*.dart` — pantallas (auth, sales, cash, menu, products, inventory, users, reports, dashboard, shell).
- `lib/core/*_repository.dart` — acceso a datos (auth, cash, catalog, menu, report, sales).
- `lib/ui/common.dart` — widgets y helpers compartidos (parseAmount, formatMoney, AppCard, StatCard, showAppMessage, appInput).
- `lib/main.dart` — tema Material 3 central + `StartupGate` (login vs AppShell según sesión).

## Base de datos (SQLite / sqflite)
- `lib/data/database/app_database.dart` — singleton `AppDatabase.instance`, schema versionado a mano.
- `version: 7` (`AppDatabase.schemaVersion`); DB file `sazon_restaurante_v2.db`. `PRAGMA foreign_keys = ON`.
- Para cambiar schema: subir `version`, añadir `onUpgrade`. Las vistas `v_stock_insumos` y
  `v_stock_productos` se dropean y recrean en cada upgrade (ya se hace en `_createSchema`).
- `unidades_medida.familia`/`factor_base` permiten convertir L↔ml y kg↔g en las recetas.
- `insumos.venta_directa` genera/actualiza un producto vinculado (`producto_id`) con receta de
  1 unidad; su categoría queda `siempre_disponible = 1`. Los productos `DIRECTO` viejos se
  migran automáticamente a insumo + receta al subir a v7 y el stock actual se conserva.
- `_afterOpen` siembra las categorías base `Desayuno` y `Almuerzo` (el formulario de producto
  usa `Almuerzo` por defecto). Los insumos de venta directa guardan su foto en el producto.
- `app_meta` (fila única): `instalacion_id` (UUID estable de la instalación) y fecha del último
  respaldo. Se escribe **antes** de copiar el archivo, así la fecha viaja dentro del respaldo.
- Import condicional de factory: `database_factory_web.dart if (dart.library.io) database_factory_io.dart`
  (sqflite vs sqflite_common_ffi_web). No romper este patrón.

## Respaldo
- `lib/core/backup/backup_service.dart` exporta condicionalmente `backup_service_io.dart` o
  `backup_service_web.dart` (en web solo funciona la exportación a Excel).
- Flujo: `AppDatabase.instance.close()` → copiar el `.db` → validar cabecera `SQLite format 3\0`.
  Restaurar reemplaza todo, guarda antes una copia en `<documentos>/respaldos_seguridad/` (máx. 5)
  y revierte si `PRAGMA integrity_check` falla.
- `excel_exporter.dart` genera una hoja por tabla; excluye `password_hash` y el BLOB `imagen`.

## Convenciones / gotchas
- Login por defecto sembrado: usuario `admin` / contraseña `1234` (hash SHA-256, `lib/core/password_utils.dart`).
- Dinero en Bolivianos (`Bs`, `formatMoney`); entrada decimal con coma (`parseAmount`). Fechas como texto SQL
  vía `sqlDate`/`sqlDateTime` (`lib/core/date_utils.dart`).
- UI y comentarios en español. Roles/perfiles y permisos en `lib/core/session.dart` (`Permiso`, `Perfil`).
- Test unitario verifica el hash SHA-256 exacto de `1234`; no cambiar el algoritmo sin actualizar `test/widget_test.dart`.
