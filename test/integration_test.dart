import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/cash_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/menu_repository.dart';
import 'package:test_code_02/core/report_repository.dart';
import 'package:test_code_02/core/sales_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  test('flujo completo de caja, ventas, stock y reportes', () async {
    final auth = AuthRepository();
    expect(await auth.usaCredencialesPorDefecto(), isTrue);

    expect(await auth.login('admin', 'incorrecta'), isNull);
    final admin = (await auth.login('admin', '1234'))!;
    expect(admin.esAdmin, isTrue);
    expect(admin.usuario, 'admin');

    await auth.guardarSesion(admin.id);
    expect((await auth.restaurarSesion())?.id, admin.id);
    await auth.cerrarSesion();
    expect(await auth.restaurarSesion(), isNull);

    await auth.saveUsuario(
      nombre: 'Cajera',
      usuario: 'cajera',
      perfil: Perfil.cajero,
      activo: true,
      permisos: Perfil.vistasPorDefecto[Perfil.cajero]!,
      password: 'caja123',
    );
    final cajera = (await auth.login('cajera', 'caja123'))!;
    expect(cajera.esAdmin, isFalse);
    expect(cajera.perfil, Perfil.cajero);
    expect(cajera.puede(Permiso.ventas), isTrue);
    expect(cajera.puede(Permiso.caja), isTrue);
    expect(cajera.puede(Permiso.agotamiento), isTrue);
    expect(cajera.puede(Permiso.menu), isFalse);
    expect(cajera.puede(Permiso.tablero), isFalse);
    expect(cajera.puede(Permiso.productos), isFalse);
    expect(cajera.puede(Permiso.insumos), isFalse);
    expect(cajera.puede(Permiso.usuarios), isFalse);
    expect(cajera.puede(Permiso.reportes), isFalse);

    await auth.saveUsuario(
      nombre: 'Vendedor',
      usuario: 'vendedor',
      perfil: Perfil.vendedor,
      activo: true,
      permisos: Perfil.vistasPorDefecto[Perfil.vendedor]!,
      password: 'vende123',
    );
    final vendedor = (await auth.login('vendedor', 'vende123'))!;
    expect(vendedor.puede(Permiso.ventas), isTrue);
    expect(vendedor.puede(Permiso.caja), isFalse);
    expect(vendedor.puede(Permiso.reportes), isFalse);
    expect(vendedor.permisos.length, 2);

    expect(await auth.verificarPassword(cajera.id, 'caja123'), isTrue);
    await auth.cambiarPassword(cajera.id, 'nueva123');
    expect(await auth.verificarPassword(cajera.id, 'caja123'), isFalse);
    expect(await auth.login('cajera', 'caja123'), isNull);
    expect((await auth.login('cajera', 'nueva123'))?.id, cajera.id);

    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'Bebidas',
        color: 0xFF2563EB,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'Almuerzos',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 2,
        activo: true,
      ),
    );
    final categorias = await catalog.getCategorias();
    final bebidas = categorias.firstWhere((c) => c.nombre == 'Bebidas');
    final almuerzos = categorias.firstWhere((c) => c.nombre == 'Almuerzos');
    final unidades = await catalog.getUnidades();
    final unidad = unidades.firstWhere((u) => u.abreviatura == 'und');

    final papaId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Papa',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 5,
        costoPromedio: 3,
        activo: true,
        stock: 0,
      ),
    );
    final aceiteId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Aceite',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 0,
        costoPromedio: 0,
        activo: true,
        stock: 0,
      ),
    );

    // El stock se carga con ajustes manuales.
    await catalog.ajustarStockInsumo(
      insumoId: papaId,
      nuevoStock: 10,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    await catalog.ajustarStockInsumo(
      insumoId: aceiteId,
      nuevoStock: 5,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    expect(await catalog.getStockInsumo(papaId), 10);
    expect(await catalog.getStockInsumo(aceiteId), 5);

    final cocaId = await catalog.saveProducto(
      Producto(
        nombre: 'Coca Cola',
        categoriaId: bebidas.id!,
        categoriaNombre: bebidas.nombre,
        categoriaColor: bebidas.color,
        precio: 5,
        tipo: 'DIRECTO',
        stockMinimo: 2,
        costoUnitario: 3,
        activo: true,
        stock: 0,
      ),
    );
    final almuerzoId = await catalog.saveProducto(
      Producto(
        nombre: 'Almuerzo del día',
        categoriaId: almuerzos.id!,
        categoriaNombre: almuerzos.nombre,
        categoriaColor: almuerzos.color,
        precio: 15,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.ajustarStockProducto(
      productoId: cocaId,
      nuevoStock: 5,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    expect(await catalog.getStockProducto(cocaId), 5);

    await catalog.saveRecetaCantidades(almuerzoId, {
      papaId: 0.5,
      aceiteId: 1,
    });

    // Los productos directos activos se venden siempre.
    final directos = await catalog.getProductosDirectosActivos();
    expect(directos.length, 1);
    expect(directos.first.nombre, 'Coca Cola');
    final preparados = await catalog.getProductosPreparadosActivos();
    expect(preparados.length, 1);
    expect(preparados.first.nombre, 'Almuerzo del día');

    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(
      DateTime.now(),
      'ALMUERZO',
      admin.id,
    );
    await menuRepo.agregarProducto(menu.id, almuerzoId);
    await menuRepo.publicar(menu.id);
    expect((await menuRepo.getMenuPublicado(DateTime.now(), 'ALMUERZO')).length, 1);

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      turno: 'TARDE',
      fondoInicial: 100,
      usuarioId: admin.id,
    );
    expect((await cash.getCajaAbierta())?.id, caja.id);

    final sales = SalesRepository();
    final pedidoId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      referencia: 'Mesa 3',
      lineas: [
        CartLine(
          productoId: almuerzoId,
          menuDiaItemId: (await menuRepo.getItems(menu.id)).first.id,
          nombre: 'Almuerzo del día',
          precio: 15,
          cantidad: 2,
          tipo: 'PREPARADO',
        ),
        CartLine(
          productoId: cocaId,
          nombre: 'Coca Cola',
          precio: 5,
          cantidad: 1,
          tipo: 'DIRECTO',
        ),
      ],
      pagos: const [
        PagoInput(metodo: 'QR', monto: 30),
        PagoInput(metodo: 'EFECTIVO', monto: 5),
      ],
    );
    final detalle = await sales.getPedido(pedidoId);
    expect(detalle.pedido.estadoPago, 'PAGADO');
    expect(detalle.pedido.total, 35);
    expect(detalle.pagos.length, 2);
    expect(await catalog.getStockInsumo(papaId), 9);
    expect(await catalog.getStockInsumo(aceiteId), 3);
    expect(await catalog.getStockProducto(cocaId), 4);

    var resumenCaja = await cash.getResumen(caja.id);
    expect(resumenCaja.ventasEfectivo, 5);
    expect(resumenCaja.ventasQr, 30);
    expect(resumenCaja.esperadoEfectivo, 105);
    expect(resumenCaja.esperadoQr, 30);

    // Salida de caja.
    await cash.registrarSalida(
      cajaId: caja.id,
      usuarioId: admin.id,
      monto: 10,
      metodoPago: 'EFECTIVO',
      descripcion: 'Luz',
    );
    resumenCaja = await cash.getResumen(caja.id);
    expect(resumenCaja.salidasEfectivo, 10);
    expect(resumenCaja.esperadoEfectivo, 95);

    final reports = ReportRepository();
    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final fin = inicio.add(const Duration(days: 1));
    var resumen = await reports.getResumen(inicio, fin);
    expect(resumen.ventas, 35);
    expect(resumen.cobros, 35);
    expect(resumen.cogs, 6);
    expect(resumen.salidas, 10);
    expect(resumen.resultado, 19);
    expect(resumen.flujoCaja, 25);
    final productos = await reports.getProductos(inicio, fin);
    expect(productos.length, 2);
    final salidas = await reports.getSalidasPorMotivo(inicio, fin);
    expect(salidas.length, 1);
    expect(salidas.first.nombre, 'Luz');
    final inventarioReporte = await reports.getInventario();
    expect(inventarioReporte.length, 3);

    // Ajuste manual de stock.
    await catalog.ajustarStockInsumo(
      insumoId: papaId,
      nuevoStock: 8,
      usuarioId: admin.id,
      motivo: 'Ajuste manual',
    );
    expect(await catalog.getStockInsumo(papaId), 8);

    await sales.anularPedido(pedidoId);
    expect(await catalog.getStockProducto(cocaId), 5);
    final resumenAnulado = await reports.getResumen(inicio, fin);
    expect(resumenAnulado.ventas, 0);
    expect(resumenAnulado.cobros, 0);
    expect(resumenAnulado.cogs, 0);

    final pendienteId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      referencia: 'Mesa 5',
      lineas: [
        CartLine(
          productoId: cocaId,
          nombre: 'Coca Cola',
          precio: 5,
          cantidad: 1,
          tipo: 'DIRECTO',
        ),
      ],
      pagos: const [],
    );
    expect((await sales.getPedido(pendienteId)).pedido.estadoPago, 'PENDIENTE');
    expect(await catalog.getStockProducto(cocaId), 4);

    await cash.cerrarCaja(
      cajaId: caja.id,
      efectivoContado: 95,
      qrVerificado: 30,
      usuarioId: admin.id,
    );
    expect(await cash.getCajaAbierta(), isNull);
    final menuCerrado = await menuRepo.getMenu(DateTime.now(), 'ALMUERZO');
    expect(menuCerrado?.estado, 'CERRADO');

    final nuevaCaja = await cash.abrirCaja(
      fecha: DateTime.now(),
      turno: 'MAÑANA',
      fondoInicial: 50,
      usuarioId: admin.id,
    );
    await expectLater(
      sales.agregarPagos(
        pedidoId: pendienteId,
        usuarioId: admin.id,
        cajaId: caja.id,
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 5)],
      ),
      throwsA(isA<StateError>()),
    );
    await sales.agregarPagos(
      pedidoId: pendienteId,
      usuarioId: admin.id,
      cajaId: nuevaCaja.id,
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 5)],
    );
    expect((await sales.getPedido(pendienteId)).pedido.estadoPago, 'PAGADO');
    final resumenNuevaCaja = await cash.getResumen(nuevaCaja.id);
    expect(resumenNuevaCaja.ventasEfectivo, 5);
    expect(resumenNuevaCaja.esperadoEfectivo, 55);

    final resumenFinal = await reports.getResumen(inicio, fin);
    expect(resumenFinal.ventas, 5);
    expect(resumenFinal.cobros, 5);
    expect(resumenFinal.cogs, 3);

    final usuarios = await auth.getUsuarios();
    expect(usuarios.length, 3);
    final adminGuardado = usuarios.firstWhere((u) => u.usuario == 'admin');
    expect(adminGuardado.perfil, Perfil.admin);
    expect(adminGuardado.permisos.contains(Permiso.reportes), isTrue);
    expect(adminGuardado.permisos.length, Permiso.todos.length);
    final cajeraGuardada = usuarios.firstWhere((u) => u.usuario == 'cajera');
    expect(cajeraGuardada.perfil, Perfil.cajero);
    expect(cajeraGuardada.permisos.contains(Permiso.reportes), isFalse);
    expect(cajeraGuardada.permisos.contains(Permiso.ventas), isTrue);
    final vendedorGuardado = usuarios.firstWhere((u) => u.usuario == 'vendedor');
    expect(vendedorGuardado.permisos.contains(Permiso.caja), isFalse);
  });

  test('ninguna pantalla devuelve un Future a setState', () {
    // Un setState con un callback que devuelve un Future hace que Flutter
    // lance "setState() callback argument returned a Future" y la pantalla
    // no se refresque. Por eso _reload debe ser void.
    final archivos = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((archivo) => archivo.path.endsWith('.dart'));
    for (final archivo in archivos) {
      final contenido = archivo.readAsStringSync();
      expect(
        contenido.contains('=> _future ='),
        isFalse,
        reason:
            '${archivo.path} usa una función flecha que devuelve el Future; '
            'déjala con llaves para que devuelva void.',
      );
    }
  });

  test('migración desde la versión 2 conserva los datos', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    // Base vieja: mismo esquema sin la tabla de ajustes de stock.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final version = await db.rawQuery('PRAGMA user_version');
    expect((version.first['user_version'] as num).toInt(), 5);
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ajustes_stock'",
    );
    expect(tablas.length, 1);
    final columnas = await db.rawQuery('PRAGMA table_info(usuarios)');
    expect(columnas.any((c) => c['name'] == 'perfil'), isTrue);

    final auth = AuthRepository();
    final admin = await auth.login('admin', '1234');
    expect(admin, isNotNull);
    expect(admin!.esAdmin, isTrue);
    expect(admin.perfil, Perfil.admin);
    expect((await auth.getUsuarios()).length, 1);

    final catalog = CatalogRepository();
    final unidades = await catalog.getUnidades();
    expect(unidades.isNotEmpty, isTrue);
  });
}
