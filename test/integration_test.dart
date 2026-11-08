import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/cash_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/count_repository.dart';
import 'package:test_code_02/core/expense_repository.dart';
import 'package:test_code_02/core/menu_repository.dart';
import 'package:test_code_02/core/purchase_repository.dart';
import 'package:test_code_02/core/report_repository.dart';
import 'package:test_code_02/core/sales_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  test('flujo completo de caja, ventas, compras y reportes', () async {
    final auth = AuthRepository();
    expect(await auth.hayUsuarios(), isFalse);

    final admin = await auth.crearAdminInicial(
      nombre: 'Administradora',
      usuario: 'admin',
      password: 'clave123',
    );
    expect(admin.esAdmin, isTrue);
    expect(await auth.hayUsuarios(), isTrue);
    expect(await auth.login('admin', 'incorrecta'), isNull);
    expect((await auth.login('admin', 'clave123'))?.id, admin.id);

    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'Bebidas',
        color: 0xFF2563EB,
        siempreDisponible: true,
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

    await catalog.saveInsumo(
      Insumo(
        nombre: 'Papa',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        modoControl: 'UNIDAD',
        disponible: true,
        stockMinimo: 5,
        costoPromedio: 3,
        factorCompra: 1,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.saveInsumo(
      Insumo(
        nombre: 'Aceite',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        modoControl: 'DISPONIBILIDAD',
        disponible: true,
        stockMinimo: 0,
        costoPromedio: 0,
        factorCompra: 1,
        activo: true,
        stock: 0,
      ),
    );
    final papa = (await catalog.getInsumos())
        .firstWhere((i) => i.nombre == 'Papa');
    final aceite = (await catalog.getInsumos())
        .firstWhere((i) => i.nombre == 'Aceite');

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
    await catalog.saveRecetaCantidades(almuerzoId, {
      papa.id!: 0.5,
      aceite.id!: 1,
    });

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

    final purchases = PurchaseRepository();
    await purchases.registrarCompra(
      usuarioId: admin.id,
      cajaId: caja.id,
      metodoPago: 'EFECTIVO',
      lineas: [
        CompraLineaInput(
          insumoId: papa.id,
          nombre: 'Papa',
          cantidad: 10,
          costoUnitario: 3,
        ),
        CompraLineaInput(
          productoId: cocaId,
          nombre: 'Coca Cola',
          cantidad: 5,
          costoUnitario: 3,
        ),
      ],
    );
    expect((await catalog.getStockInsumo(papa.id!)), 10);
    expect((await catalog.getStockProducto(cocaId)), 5);

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
    expect(await catalog.getStockInsumo(papa.id!), 9);
    expect(await catalog.getStockProducto(cocaId), 4);

    final resumenCaja = await cash.getResumen(caja.id);
    expect(resumenCaja.ventasEfectivo, 5);
    expect(resumenCaja.ventasQr, 30);
    expect(resumenCaja.esperadoEfectivo, 60);

    final reports = ReportRepository();
    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final fin = inicio.add(const Duration(days: 1));
    final resumen = await reports.getResumen(inicio, fin);
    expect(resumen.ventas, 35);
    expect(resumen.cobros, 35);
    expect(resumen.cogs, 6);
    expect(resumen.compras, 45);
    expect(resumen.resultado, 29);
    expect(resumen.flujoCaja, -10);
    final productos = await reports.getProductos(inicio, fin);
    expect(productos.length, 2);
    final comprasReporte = await reports.getComprasPorItem(inicio, fin);
    expect(comprasReporte.length, 2);
    final inventarioReporte = await reports.getInventario();
    expect(inventarioReporte.length, 3);

    final expenses = ExpenseRepository();
    await expenses.saveCategoriaGasto(nombre: 'Servicios');
    final categoriaGasto = (await expenses.getCategoriasGasto()).first;
    await expenses.registrarGasto(
      categoriaGastoId: categoriaGasto.id!,
      usuarioId: admin.id,
      cajaId: caja.id,
      monto: 10,
      metodoPago: 'EFECTIVO',
      descripcion: 'Luz',
    );

    final count = CountRepository();
    final conteo = await count.crearConteo(DateTime.now(), admin.id);
    final conteoDetalle = await count.getDetalle(conteo.id);
    final lineaPapa = conteoDetalle.lineas.firstWhere(
      (linea) => linea.insumoId == papa.id,
    );
    expect(lineaPapa.stockSistema, 9);
    await count.cerrarConteo(conteo.id, {papa.id!: 8});
    expect(await catalog.getStockInsumo(papa.id!), 8);

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
      efectivoContado: 45,
      qrVerificado: 0,
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
    expect(usuarios.length, 1);
    expect(usuarios.first.permisos.contains(Permiso.reportes), isTrue);
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });
}
