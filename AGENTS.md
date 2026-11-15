# AGENTS.md

Flutter app (POS de restaurante "Conwich"). Paquete Dart: `test_code_02` — los imports usan
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
  salen de `pubspec.yaml` (1.0.0+1). El canal "Beta 1" es solo una etiqueta visual en
  `lib/core/app_info.dart`; no forma parte de la versión para iOS.
- iOS: bundle id `com.example.testCode02`, display name `Conwich`. Web: `<title>` = `Conwich`.

## Arquitectura
- Sin gestor de estado: `setState` + singletons (`Sesion.instance`). Las páginas usan repositorios directamente.
- `lib/features/<feature>/presentation/*.dart` — pantallas (auth, sales, cash, menu, products, inventory, users, reports, dashboard, shell).
- `lib/core/*_repository.dart` — acceso a datos (auth, cash, catalog, menu, report, sales).
- `lib/ui/common.dart` — widgets y helpers compartidos (parseAmount, formatMoney, AppCard, StatCard, showAppMessage, appInput).
- `validateDecimalAmount` y `decimalAmountInputFormatter` validan importes/cantidades numéricas.
  Usarlos en Productos, Caja y cobros; no aplicarlos ni cambiar el formulario de Insumos.
- `lib/main.dart` — tema Material 3 central + `StartupGate` (login vs AppShell según sesión).
- `AppShell` construye cada sección solo al visitarla y refresca solo la sección activa
  (cada pantalla tiene su propio token). El drawer y el `NavigationRail` muestran siempre
  las etiquetas del menú y un pie fijo con cambiar contraseña, cambiar/ver usuario,
  respaldo (admin) y cerrar sesión.

## Base de datos (SQLite / sqflite)
- `lib/data/database/app_database.dart` — singleton `AppDatabase.instance`, schema versionado a mano.
- `version: 16` (`AppDatabase.schemaVersion`); DB file `sazon_restaurante_v2.db`. Las claves
  foráneas se desactivan durante la migración y se activan en `onOpen` (`PRAGMA foreign_keys = ON`).
- Para cambiar schema: subir `version`, añadir `onUpgrade`. Las vistas `v_stock_insumos` y
  `v_stock_productos` se dropean y recrean en cada upgrade (ya se hace en `_createSchema`).
- La v14 agregó índices (`pagos(pedido_id)`, `consumos_insumo(insumo_id)`,
  `detalle_compra(insumo_id/producto_id)`, `detalle_pedido(producto_id)`,
  `detalle_conteo(insumo_id)`, `faltantes_insumo(fecha/pedido_id)`); no modifica datos y
  acelera las vistas de stock y los reportes.
- La v15 agrega a `detalle_pedido` modalidad de venta y snapshots de la sopa incluida en un
  completo; los productos compuestos anteriores quedan inactivos y conservados para historial.
- La v16 restaura la categoría base `PLATOS SUELTOS` sin fusionar ni borrar categorías.
- `unidades_medida.familia`/`factor_base` permiten convertir L↔ml y kg↔g en las recetas.
- La receta es opcional. Al vender, el consumo se limita al stock disponible (nunca deja
  negativos) y el faltante queda registrado en `faltantes_insumo` (se consulta en Reportes).
- `insumos.venta_directa` genera/actualiza un producto vinculado (`producto_id`) con receta de
  1 unidad; su categoría queda `siempre_disponible = 1`. Los productos `DIRECTO` viejos se
  migran automáticamente a insumo + receta al subir a v7 y el stock actual se conserva.
- `_afterOpen` siembra categorías planas: `PLATOS SUELTOS`, `SOPAS`, `BEBIDAS CALIENTES`,
  `REFRESCOS` y `FRAPPES`. No hay categorías padre ni subcategorías (`parent_id` queda en NULL).
  Las categorías se guardan siempre en mayúsculas y se pueden crear nuevas desde Productos.
  Los insumos de venta directa guardan su foto en el producto.
- `cajas` usa `numero_turno` consecutivo por día (`Turno 1, 2, 3…`), no `MAÑANA/TARDE`.
  Cerrar una caja ya no cierra el menú del día.
- Menú del día replica el catálogo de Ventas agrupado por categoría plana, con chips de
  categorías (por color) para filtrar. Se elige como máximo una sopa; cada categoría tiene un
  checkbox binario para seleccionar o quitar todos sus productos y todavía se puede elegir cada
  producto individualmente. SOPAS y siempre disponibles quedan fuera de esos checkboxes. Solo los
  productos de `PLATOS SUELTOS` pueden ser completos. En Ventas se calcula
  `precio_plato + precio_sopa`.
  El reporte general no muestra modalidades para otras categorías; el desglose de almuerzos y sopas
  se muestra en secciones separadas y omite los ceros. Al limpiar o reemplazar un menú, las filas
  referenciadas por ventas se conservan ocultas para proteger el
  historial. Al abrir un día sin menú se copia automáticamente la configuración del menú anterior
  (una sopa y sus platos); los combos viejos no se copian ni venden en el flujo nuevo. "Programar
  días" copia la configuración a los siguientes días. El menú solo se publica (`HABILITADO`); no se
  cierra. La venta directa va en una
  sección SIEMPRE DISPONIBLES. Si no hay caja abierta, Ventas muestra un botón "Ir a Caja".
  En Ventas, los productos activos que no están en el menú del día se agrupan en una sección
  colapsable ("Productos fuera del menú de hoy"), oculta por defecto y no vendible.
- El estado del menú se llama `HABILITADO` (antes `PUBLICADO`) en BD, código y textos; la columna
  es `habilitado_en`. El tablero ofrece "Empezar el día" (lleva al menú y de ahí un atajo a Caja).
- `app_meta` (fila única): `instalacion_id` (UUID estable de la instalación), fecha del último
  respaldo y configuración de respaldo en Drive (`drive_habilitado`, `drive_carpeta_uri`,
  `drive_carpeta_nombre`, `drive_retencion`, `drive_al_cerrar_caja`, `drive_frecuencia`,
  `drive_ultimo_exito`, `drive_ultimo_error`). Se escribe **antes** de copiar el archivo, así la
  fecha viaja dentro del respaldo.
- `detalle_pedido.modalidad_venta` distingue suelto/completo en `PLATOS SUELTOS` y guarda el snapshot de la sopa y su
  precio; una línea hija `es_componente` permite descontar también la sopa sin duplicar el ingreso.
  Los reportes separan los ingresos del plato y de la sopa incluida. La receta de cada componente se
  consume solo si existe. Los combos compuestos antiguos se conservan para el historial/backups.
- Import condicional de factory: `database_factory_web.dart if (dart.library.io) database_factory_io.dart`
  (sqflite vs sqflite_common_ffi_web). No romper este patrón.

## Respaldo
- `lib/core/backup/backup_service.dart` exporta condicionalmente `backup_service_io.dart` o
  `backup_service_web.dart` (en web solo funciona la exportación a Excel).
- Flujo: `AppDatabase.instance.close()` → copiar el `.db` → validar cabecera `SQLite format 3\0`.
  Restaurar reemplaza todo, guarda antes una copia en `<documentos>/respaldos_seguridad/` (máx. 5)
  y revierte si `PRAGMA integrity_check` falla.
- Las copias nuevas se llaman `conwich_respaldo_<fecha>.db` y
  `conwich_seguridad_<fecha>.db`; el formato de fecha no cambia. La compatibilidad al restaurar
  depende de `schemaVersion`, no del nombre del archivo. El `.db` de trabajo sigue siendo
  `sazon_restaurante_v2.db`.
- `excel_exporter.dart` genera una hoja por tabla; excluye `password_hash` y el BLOB `imagen`.
- `report_exporter.dart` genera el reporte del período en PDF tamaño carta (resumen, gráfico de
  ingresos, gráfico por cantidad, productos con precio unitario, salidas detalladas y pedidos) y
  en Excel (hojas Resumen, Productos, Almuerzos, Sopas, Salidas, Pedidos, Gráfico, Gráfico
  cantidades y Faltantes).
  Los gráficos de Excel usan barras de celdas coloreadas porque el paquete `excel` no soporta
  gráficos nativos.
- En Reportes, administradores ven los reportes completos. Usuarios no administradores con acceso
  a Ventas solo ven sus propios pedidos en lectura, filtrados por `pedidos.usuario_id` y el rango
  elegido; no se agregan columnas ni tablas para esto.
- Respaldo en Google Drive: se usa el selector de carpetas de Android (SAF), no Google Cloud ni
  OAuth. `android/.../MainActivity.kt` expone un `MethodChannel` con elegir carpeta, verificar
  permiso, escribir, listar y borrar. La carpeta elegida se guarda en `app_meta`. Las copias se
  suben al cerrar caja (según configuración) y en el inicio si la frecuencia está vencida; se
  conservan las últimas N copias (`drive_retencion`, por defecto 30).

## Convenciones / gotchas
- **Regla: el sistema nunca depende de que los productos tengan receta.** Un `PREPARADO` sin
  receta se vende igual (solo no descuenta insumos); `motivoNoDisponible` no lo bloquea y el
  carrito/pedido se registran sin error.
- Login por defecto sembrado: usuario `admin` / contraseña `1234` (hash SHA-256, `lib/core/password_utils.dart`).
- Dinero en Bolivianos (`Bs`, `formatMoney`); entrada decimal con coma (`parseAmount`). Fechas como texto SQL
  vía `sqlDate`/`sqlDateTime` (`lib/core/date_utils.dart`).
- UI y comentarios en español. Roles/perfiles y permisos en `lib/core/session.dart` (`Permiso`, `Perfil`).
- Test unitario verifica el hash SHA-256 exacto de `1234`; no cambiar el algoritmo sin actualizar `test/widget_test.dart`.
