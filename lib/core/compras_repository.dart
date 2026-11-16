import '../data/database/app_database.dart';
import 'catalog_repository.dart';
import 'date_utils.dart';

/// Registro de compras y pérdidas de insumos.
///
/// El stock de los insumos se calcula en la vista `v_stock_insumos`: las
/// compras (`compras` + `detalle_compra`) suman y los ajustes negativos
/// (`ajustes_stock`) restan. Aquí solo se escriben esos registros.
class ComprasRepository {
  /// Registra la compra de un único insumo. Aumenta el stock y, si se indica
  /// un costo nuevo mayor a cero, recalcula el costo promedio ponderado del
  /// insumo. Devuelve el id de la compra creada.
  Future<int> registrarCompraInsumo({
    required int insumoId,
    required double cantidad,
    required double costoUnitario,
    required int usuarioId,
    String metodoPago = 'EFECTIVO',
  }) async {
    if (cantidad <= 0) {
      throw StateError('La cantidad debe ser mayor a cero.');
    }
    final catalog = CatalogRepository();
    final insumo = await catalog.getInsumo(insumoId);
    if (insumo == null) throw StateError('El insumo no existe.');

    var nuevoPromedio = insumo.costoPromedio;
    if (costoUnitario > 0) {
      final stockActual = insumo.stock;
      nuevoPromedio =
          (stockActual * insumo.costoPromedio + cantidad * costoUnitario) /
          (stockActual + cantidad);
    }
    final subtotal = cantidad * costoUnitario;

    final db = await AppDatabase.instance.database;
    final codigo = _nuevoCodigo();
    return db.transaction((txn) async {
      final compraId = await txn.insert('compras', {
        'usuario_id': usuarioId,
        'fecha': sqlNow(),
        'codigo': codigo,
        'metodo_pago': metodoPago,
        'total': subtotal,
        'estado': 'REGISTRADA',
      });
      await txn.insert('detalle_compra', {
        'compra_id': compraId,
        'insumo_id': insumoId,
        'producto_id': null,
        'cantidad': cantidad,
        'costo_unitario': costoUnitario,
        'subtotal': subtotal,
      });
      await txn.update(
        'insumos',
        {'costo_promedio': nuevoPromedio},
        where: 'id = ?',
        whereArgs: [insumoId],
      );
      return compraId;
    });
  }

  /// Registra una pérdida/merma: descuenta stock sin tocar precios ni costo
  /// promedio.
  Future<void> registrarPerdida({
    required int insumoId,
    required double cantidad,
    required int usuarioId,
    String? motivo,
  }) async {
    if (cantidad <= 0) {
      throw StateError('La cantidad debe ser mayor a cero.');
    }
    final db = await AppDatabase.instance.database;
    final texto = (motivo ?? '').trim();
    final detalle = texto.isEmpty ? 'Pérdida' : 'Pérdida: $texto';
    await db.insert('ajustes_stock', {
      'fecha': sqlNow(),
      'insumo_id': insumoId,
      'producto_id': null,
      'cantidad': -cantidad,
      'motivo': detalle,
      'usuario_id': usuarioId,
    });
  }

  String _nuevoCodigo() {
    final now = DateTime.now();
    String dos(int value) => value.toString().padLeft(2, '0');
    return 'CMP-${now.year}${dos(now.month)}${dos(now.day)}'
        '-${dos(now.hour)}${dos(now.minute)}${dos(now.second)}';
  }
}
