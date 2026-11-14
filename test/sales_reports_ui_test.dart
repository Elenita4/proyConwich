import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/cash_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/menu_repository.dart';
import 'package:test_code_02/core/sales_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';
import 'package:test_code_02/features/reports/presentation/reports_page.dart';
import 'package:test_code_02/features/sales/presentation/sales_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Usuario admin;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
    admin = (await AuthRepository().login('admin', '1234'))!;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<(CatalogoPrueba, int)> sembrarCatalogo() async {
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'PLATOS',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    final categoria = (await catalog.getCategorias()).firstWhere(
      (item) => item.nombre == 'PLATOS',
    );
    final uno = await catalog.saveProducto(
      Producto(
        nombre: 'Plato uno',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final dos = await catalog.saveProducto(
      Producto(
        nombre: 'Bebida dos',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final caja = await CashRepository().abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 0,
      usuarioId: admin.id,
    );
    return ((uno, dos), caja.id);
  }

  testWidgets('Ventas oculta los productos fuera del menú y los despliega', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoUno, _), _) = catalogo;
    final menuRepository = MenuRepository();
    await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      await menuRepository.agregarProducto(menu.id, platoUno);
      await menuRepository.habilitar(menu.id);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    expect(find.text('Plato uno'), findsWidgets);
    expect(find.text('Bebida dos'), findsNothing);
    expect(find.text('Productos fuera del menú de hoy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Productos fuera del menú de hoy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Productos fuera del menú de hoy'));
    await tester.pumpAndSettle();
    expect(find.text('Bebida dos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reportes muestra los gráficos de ingresos y de cantidades', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoUno, bebidaDos), cajaId) = catalogo;
    await tester.runAsync(
      () => SalesRepository().crearPedido(
        usuarioId: admin.id,
        cajaId: cajaId,
        lineas: [
          CartLine(
            productoId: platoUno,
            nombre: 'Plato uno',
            precio: 10,
            cantidad: 3,
          ),
          CartLine(
            productoId: bebidaDos,
            nombre: 'Bebida dos',
            precio: 10,
            cantidad: 6,
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 90)],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReportsPage(refreshToken: 0))),
    );
    await asentar(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Productos'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresos por producto'), findsOneWidget);
    expect(find.text('Productos más vendidos'), findsOneWidget);
    expect(find.text('Bebida dos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

typedef CatalogoPrueba = (int platoUno, int bebidaDos);
