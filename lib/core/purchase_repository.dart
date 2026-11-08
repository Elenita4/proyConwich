import '../data/database/app_database.dart';
import 'date_utils.dart';

class CompraLineaInput {
  const CompraLineaInput({
    this.insumoId,
    this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
  });

  final int? insumoId;
  final int? productoId;
  final String nombre;
  final double cantidad;
  final double costoUnitario;

  double get subtotal => cantidad * costoUnitario;
}

class CompraLinea {
  const CompraLinea({
    this.insumoId,
    this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
    required this.subtotal,
    required this.tipo,
  });

  final int? insumoId;
  final int? productoId;
  final String nombre;
  final double cantidad;
  final double costoUnitario;
  final double subtotal;
  final String tipo;
}

class Compra {
  const Compra({
    required this.id,
    required this.fecha,
    required this.metodoPago,
    required this.total,
    this.observacion,
    required this.estado,
    required this.usuarioNombre,
  });

  final int id;
  final String fecha;
  final String metodoPago;
  final double total;
  final String? observacion;
  final String estado;
  final String usuarioNombre;

  bool get anulada => estado == 'ANULADA';
}

class CompraDetalle {
  const CompraDetalle({required this.compra, required this.lineas});

  final Compra compra;
  final List<CompraLinea> lineas;
}

class PurchaseRepository {
  Future<List<Compra>> getCompras({int limite = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, u.nombre AS usuario_nombre
      FROM compras c
      INNER JOIN usuarios u ON u.id = c.usuario_id
      ORDER BY c.fecha DESC
      LIMIT ?
    ''', [limite]);
    return rows.map(_fromRow).toList();
  }

  Future<CompraDetalle> getCompra(int compraId) async {
    final db = await AppDatabase.instance.database;
    final compras = await db.rawQuery('''
      SELECT c.*, u.nombre AS usuario_nombre
      FROM compras c
      INNER JOIN usuarios u ON u.id = c.usuario_id
      WHERE c.id = ?
      LIMIT 1
    ''', [compraId]);
    if (compras.isEmpty) throw StateError('La compra no existe.');
    final rows = await db.rawQuery('''
      SELECT dc.*, i.nombre AS insumo_nombre, p.nombre AS producto_nombre
      FROM detalle_compra dc
      LEFT JOIN insumos i ON i.id = dc.insumo_id
      LEFT JOIN productos p ON p.id = dc.producto_id
      WHERE dc.compra_id = ?
      ORDER BY dc.id
    ''', [compraId]);
    return CompraDetalle(
      compra: _fromRow(compras.first),
      lineas: rows
          .map(
            (row) => CompraLinea(
              insumoId: row['insumo_id'] as int?,
              productoId: row['producto_id'] as int?,
              nombre: (row['insumo_nombre'] ?? row['producto_nombre'])!
                  as String,
              cantidad: (row['cantidad'] as num).toDouble(),
              costoUnitario: (row['costo_unitario'] as num).toDouble(),
              subtotal: (row['subtotal'] as num).toDouble(),
              tipo: row['insumo_id'] != null ? 'INSUMO' : 'PRODUCTO',
            ),
          )
          .toList(),
    );
  }

  Future<int> registrarCompra({
    required int usuarioId,
    int? cajaId,
    required String metodoPago,
    String? observacion,
    required List<CompraLineaInput> lineas,
  }) async {
    if (lineas.isEmpty) {
      throw StateError('Agrega al menos una línea a la compra.');
    }
    final total = lineas.fold<double>(0, (sum, line) => sum + line.subtotal);
    if (total <= 0) {
      throw StateError('El total de la compra debe ser mayor a cero.');
    }
    final db = await AppDatabase.instance.database;
    final ahora = sqlNow();
    return db.transaction((txn) async {
      final costos = <int, double>{};
      final costosProducto = <int, double>{};
      for (final line in lineas) {
        if (line.insumoId != null) {
          final rows = await txn.query(
            'v_stock_insumos',
            columns: ['stock'],
            where: 'insumo_id = ?',
            whereArgs: [line.insumoId],
            limit: 1,
          );
          final insumoRows = await txn.query(
            'insumos',
            columns: ['costo_promedio'],
            where: 'id = ?',
            whereArgs: [line.insumoId],
            limit: 1,
          );
          final stock = rows.isEmpty
              ? 0.0
              : (rows.first['stock'] as num).toDouble();
          final costoActual = insumoRows.isEmpty
              ? 0.0
              : (insumoRows.first['costo_promedio'] as num).toDouble();
          costos[line.insumoId!] = _costoPromedio(
            stock,
            costoActual,
            line.cantidad,
            line.costoUnitario,
          );
        } else if (line.productoId != null) {
          final rows = await txn.query(
            'v_stock_productos',
            columns: ['stock'],
            where: 'producto_id = ?',
            whereArgs: [line.productoId],
            limit: 1,
          );
          final productoRows = await txn.query(
            'productos',
            columns: ['costo_unitario'],
            where: 'id = ?',
            whereArgs: [line.productoId],
            limit: 1,
          );
          final stock = rows.isEmpty
              ? 0.0
              : (rows.first['stock'] as num).toDouble();
          final costoActual = productoRows.isEmpty
              ? 0.0
              : (productoRows.first['costo_unitario'] as num).toDouble();
          costosProducto[line.productoId!] = _costoPromedio(
            stock,
            costoActual,
            line.cantidad,
            line.costoUnitario,
          );
        }
      }

      final compraId = await txn.insert('compras', {
        'usuario_id': usuarioId,
        'fecha': ahora,
        'metodo_pago': metodoPago,
        'caja_id': cajaId,
        'total': total,
        'observacion': _limpiar(observacion),
        'estado': 'REGISTRADA',
      });
      for (final line in lineas) {
        await txn.insert('detalle_compra', {
          'compra_id': compraId,
          'insumo_id': line.insumoId,
          'producto_id': line.productoId,
          'cantidad': line.cantidad,
          'costo_unitario': line.costoUnitario,
          'subtotal': line.subtotal,
        });
      }
      for (final entry in costos.entries) {
        await txn.update(
          'insumos',
          {'costo_promedio': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      for (final entry in costosProducto.entries) {
        await txn.update(
          'productos',
          {'costo_unitario': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      return compraId;
    });
  }

  Future<void> anularCompra(int compraId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'compras',
      {'estado': 'ANULADA'},
      where: 'id = ?',
      whereArgs: [compraId],
    );
  }

  double _costoPromedio(
    double stock,
    double costoActual,
    double cantidad,
    double costoNuevo,
  ) {
    final stockValido = stock < 0 ? 0.0 : stock;
    final total = stockValido + cantidad;
    if (total <= 0) return costoNuevo;
    return (stockValido * costoActual + cantidad * costoNuevo) / total;
  }

  Compra _fromRow(Map<String, Object?> row) => Compra(
    id: row['id']! as int,
    fecha: row['fecha']! as String,
    metodoPago: row['metodo_pago']! as String,
    total: (row['total'] as num).toDouble(),
    observacion: row['observacion'] as String?,
    estado: row['estado']! as String,
    usuarioNombre: (row['usuario_nombre'] as String?) ?? '',
  );

  String? _limpiar(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
