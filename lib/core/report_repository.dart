import '../data/database/app_database.dart';
import 'date_utils.dart';

class ResumenFinanciero {
  const ResumenFinanciero({
    required this.ventas,
    required this.cobrosEfectivo,
    required this.cobrosQr,
    required this.cogs,
    required this.compras,
    required this.comprasEfectivo,
    required this.comprasQr,
    required this.gastos,
    required this.gastosEfectivo,
    required this.gastosQr,
    required this.sueldos,
    required this.sueldosEfectivo,
    required this.sueldosQr,
    required this.pedidos,
  });

  final double ventas;
  final double cobrosEfectivo;
  final double cobrosQr;
  final double cogs;
  final double compras;
  final double comprasEfectivo;
  final double comprasQr;
  final double gastos;
  final double gastosEfectivo;
  final double gastosQr;
  final double sueldos;
  final double sueldosEfectivo;
  final double sueldosQr;
  final int pedidos;

  double get cobros => cobrosEfectivo + cobrosQr;
  double get resultado => ventas - cogs - gastos - sueldos;
  double get flujoCaja => cobros - compras - gastos - sueldos;
  double get ticketPromedio => pedidos == 0 ? 0 : ventas / pedidos;
  double get margenBruto => ventas == 0 ? 0 : (ventas - cogs) / ventas;
}

class ProductoReporte {
  const ProductoReporte({
    required this.nombre,
    required this.cantidad,
    required this.ventas,
    required this.cogs,
  });

  final String nombre;
  final double cantidad;
  final double ventas;
  final double cogs;

  double get margen => ventas - cogs;
}

class CompraReporte {
  const CompraReporte({
    required this.nombre,
    required this.tipo,
    required this.cantidad,
    required this.total,
  });

  final String nombre;
  final String tipo;
  final double cantidad;
  final double total;
}

class GastoReporte {
  const GastoReporte({required this.nombre, required this.total});

  final String nombre;
  final double total;
}

class InventarioReporte {
  const InventarioReporte({
    required this.nombre,
    required this.tipo,
    required this.modoControl,
    required this.stock,
    required this.stockMinimo,
    required this.costoUnitario,
    required this.alerta,
  });

  final String nombre;
  final String tipo;
  final String? modoControl;
  final double stock;
  final double stockMinimo;
  final double costoUnitario;
  final bool alerta;

  double get valor => stock * costoUnitario;
}

class ReportRepository {
  Future<ResumenFinanciero> getResumen(DateTime desde, DateTime hasta) async {
    final db = await AppDatabase.instance.database;
    final inicio = sqlDateTime(desde);
    final fin = sqlDateTime(hasta);
    final rows = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(total) FROM pedidos
                  WHERE estado_pago <> 'ANULADO' AND estado_entrega <> 'ANULADO'
                    AND fecha >= ? AND fecha < ?), 0) AS ventas,
        COALESCE((SELECT COUNT(*) FROM pedidos
                  WHERE estado_pago <> 'ANULADO' AND estado_entrega <> 'ANULADO'
                    AND fecha >= ? AND fecha < ?), 0) AS pedidos,
        COALESCE((SELECT SUM(monto) FROM pagos
                  WHERE estado = 'CONFIRMADO' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS cobros_efectivo,
        COALESCE((SELECT SUM(monto) FROM pagos
                  WHERE estado = 'CONFIRMADO' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS cobros_qr,
        COALESCE((SELECT SUM(ci.costo_unitario * ci.cantidad)
                  FROM consumos_insumo ci
                  WHERE ci.estado = 'CONFIRMADO'
                    AND ci.fecha >= ? AND ci.fecha < ?), 0)
        + COALESCE((SELECT SUM(dp.costo_unitario * dp.cantidad)
                    FROM detalle_pedido dp
                    INNER JOIN pedidos p ON p.id = dp.pedido_id
                    WHERE dp.costo_unitario > 0
                      AND p.estado_pago <> 'ANULADO'
                      AND p.estado_entrega <> 'ANULADO'
                      AND p.fecha >= ? AND p.fecha < ?), 0) AS cogs,
        COALESCE((SELECT SUM(total) FROM compras
                  WHERE estado = 'REGISTRADA'
                    AND fecha >= ? AND fecha < ?), 0) AS compras,
        COALESCE((SELECT SUM(total) FROM compras
                  WHERE estado = 'REGISTRADA' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS compras_efectivo,
        COALESCE((SELECT SUM(total) FROM compras
                  WHERE estado = 'REGISTRADA' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS compras_qr,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO'
                    AND fecha >= ? AND fecha < ?), 0) AS gastos,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS gastos_efectivo,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS gastos_qr,
        COALESCE((SELECT SUM(monto) FROM sueldos
                  WHERE estado = 'REGISTRADO'
                    AND fecha >= ? AND fecha < ?), 0) AS sueldos,
        COALESCE((SELECT SUM(monto) FROM sueldos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS sueldos_efectivo,
        COALESCE((SELECT SUM(monto) FROM sueldos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS sueldos_qr
    ''', [
      inicio, fin, // ventas
      inicio, fin, // pedidos
      inicio, fin, // cobros efectivo
      inicio, fin, // cobros qr
      inicio, fin, // cogs consumos
      inicio, fin, // cogs productos directos
      inicio, fin, // compras
      inicio, fin, // compras efectivo
      inicio, fin, // compras qr
      inicio, fin, // gastos
      inicio, fin, // gastos efectivo
      inicio, fin, // gastos qr
      inicio, fin, // sueldos
      inicio, fin, // sueldos efectivo
      inicio, fin, // sueldos qr
    ]);
    final row = rows.first;
    double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return ResumenFinanciero(
      ventas: value('ventas'),
      pedidos: value('pedidos').toInt(),
      cobrosEfectivo: value('cobros_efectivo'),
      cobrosQr: value('cobros_qr'),
      cogs: value('cogs'),
      compras: value('compras'),
      comprasEfectivo: value('compras_efectivo'),
      comprasQr: value('compras_qr'),
      gastos: value('gastos'),
      gastosEfectivo: value('gastos_efectivo'),
      gastosQr: value('gastos_qr'),
      sueldos: value('sueldos'),
      sueldosEfectivo: value('sueldos_efectivo'),
      sueldosQr: value('sueldos_qr'),
    );
  }

  Future<List<ProductoReporte>> getProductos(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT dp.nombre_producto AS nombre,
             SUM(dp.cantidad) AS cantidad,
             SUM(dp.subtotal) AS ventas,
             SUM(
               CASE WHEN dp.costo_unitario > 0
                 THEN dp.costo_unitario * dp.cantidad
                 ELSE COALESCE((
                   SELECT SUM(ci.costo_unitario * ci.cantidad)
                   FROM consumos_insumo ci
                   WHERE ci.detalle_pedido_id = dp.id
                     AND ci.estado = 'CONFIRMADO'
                 ), 0)
               END
             ) AS cogs
      FROM detalle_pedido dp
      INNER JOIN pedidos p ON p.id = dp.pedido_id
      WHERE p.estado_pago <> 'ANULADO'
        AND p.estado_entrega <> 'ANULADO'
        AND p.fecha >= ? AND p.fecha < ?
      GROUP BY dp.nombre_producto
      ORDER BY ventas DESC
    ''', [sqlDateTime(desde), sqlDateTime(hasta)]);
    return rows
        .map(
          (row) => ProductoReporte(
            nombre: row['nombre']! as String,
            cantidad: (row['cantidad'] as num).toDouble(),
            ventas: (row['ventas'] as num).toDouble(),
            cogs: (row['cogs'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<CompraReporte>> getComprasPorItem(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT nombre, tipo, SUM(cantidad) AS cantidad, SUM(total) AS total
      FROM (
        SELECT i.nombre AS nombre, 'INSUMO' AS tipo,
               dc.cantidad AS cantidad, dc.subtotal AS total
        FROM detalle_compra dc
        INNER JOIN compras c ON c.id = dc.compra_id
        INNER JOIN insumos i ON i.id = dc.insumo_id
        WHERE c.estado = 'REGISTRADA' AND c.fecha >= ? AND c.fecha < ?
        UNION ALL
        SELECT p.nombre, 'PRODUCTO', dc.cantidad, dc.subtotal
        FROM detalle_compra dc
        INNER JOIN compras c ON c.id = dc.compra_id
        INNER JOIN productos p ON p.id = dc.producto_id
        WHERE c.estado = 'REGISTRADA' AND c.fecha >= ? AND c.fecha < ?
      )
      GROUP BY nombre, tipo
      ORDER BY total DESC
    ''', [
      sqlDateTime(desde),
      sqlDateTime(hasta),
      sqlDateTime(desde),
      sqlDateTime(hasta),
    ]);
    return rows
        .map(
          (row) => CompraReporte(
            nombre: row['nombre']! as String,
            tipo: row['tipo']! as String,
            cantidad: (row['cantidad'] as num).toDouble(),
            total: (row['total'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<GastoReporte>> getGastosPorCategoria(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT cg.nombre AS nombre, SUM(g.monto) AS total
      FROM gastos g
      INNER JOIN categorias_gasto cg ON cg.id = g.categoria_gasto_id
      WHERE g.estado = 'REGISTRADO' AND g.fecha >= ? AND g.fecha < ?
      GROUP BY cg.id
      ORDER BY total DESC
    ''', [sqlDateTime(desde), sqlDateTime(hasta)]);
    return rows
        .map(
          (row) => GastoReporte(
            nombre: row['nombre']! as String,
            total: (row['total'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<GastoReporte>> getSueldosPorUsuario(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT u.nombre AS nombre, SUM(s.monto) AS total
      FROM sueldos s
      INNER JOIN usuarios u ON u.id = s.usuario_id
      WHERE s.estado = 'REGISTRADO' AND s.fecha >= ? AND s.fecha < ?
      GROUP BY u.id
      ORDER BY total DESC
    ''', [sqlDateTime(desde), sqlDateTime(hasta)]);
    return rows
        .map(
          (row) => GastoReporte(
            nombre: row['nombre']! as String,
            total: (row['total'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<InventarioReporte>> getInventario() async {
    final db = await AppDatabase.instance.database;
    final insumos = await db.rawQuery('''
      SELECT i.nombre, i.modo_control, i.stock_minimo, i.costo_promedio,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE i.activo = 1
      ORDER BY i.nombre COLLATE NOCASE
    ''');
    final productos = await db.rawQuery('''
      SELECT p.nombre, p.stock_minimo, p.costo_unitario,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      WHERE p.activo = 1 AND p.tipo = 'DIRECTO'
      ORDER BY p.nombre COLLATE NOCASE
    ''');
    final items = <InventarioReporte>[];
    for (final row in insumos) {
      final modo = row['modo_control'] as String?;
      final stock = (row['stock'] as num).toDouble();
      final minimo = (row['stock_minimo'] as num).toDouble();
      items.add(
        InventarioReporte(
          nombre: row['nombre']! as String,
          tipo: 'INSUMO',
          modoControl: modo,
          stock: stock,
          stockMinimo: minimo,
          costoUnitario: (row['costo_promedio'] as num).toDouble(),
          alerta: modo != 'DISPONIBILIDAD' && stock <= minimo,
        ),
      );
    }
    for (final row in productos) {
      final stock = (row['stock'] as num).toDouble();
      final minimo = (row['stock_minimo'] as num).toDouble();
      items.add(
        InventarioReporte(
          nombre: row['nombre']! as String,
          tipo: 'PRODUCTO',
          modoControl: null,
          stock: stock,
          stockMinimo: minimo,
          costoUnitario: (row['costo_unitario'] as num).toDouble(),
          alerta: stock <= minimo,
        ),
      );
    }
    return items;
  }

  Future<List<InventarioReporte>> getAlertasStock() async {
    final inventario = await getInventario();
    return inventario.where((item) => item.alerta).toList();
  }
}
