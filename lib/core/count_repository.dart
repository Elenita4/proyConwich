import '../data/database/app_database.dart';
import 'date_utils.dart';

class Conteo {
  const Conteo({
    required this.id,
    required this.fecha,
    required this.estado,
    this.observacion,
    required this.usuarioNombre,
  });

  final int id;
  final String fecha;
  final String estado;
  final String? observacion;
  final String usuarioNombre;

  bool get cerrado => estado == 'CERRADO';
}

class ConteoLinea {
  const ConteoLinea({
    required this.id,
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.stockSistema,
    required this.stockContado,
    required this.diferencia,
    required this.costoUnitario,
  });

  final int id;
  final int insumoId;
  final String nombre;
  final String unidad;
  final double stockSistema;
  final double stockContado;
  final double diferencia;
  final double costoUnitario;
}

class ConteoDetalle {
  const ConteoDetalle({required this.conteo, required this.lineas});

  final Conteo conteo;
  final List<ConteoLinea> lineas;
}

class CountRepository {
  Future<Conteo?> getConteo(DateTime fecha) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, u.nombre AS usuario_nombre
      FROM conteos_inventario c
      INNER JOIN usuarios u ON u.id = c.usuario_id
      WHERE c.fecha = ?
      LIMIT 1
    ''', [sqlDate(fecha)]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Conteo> crearConteo(DateTime fecha, int usuarioId) async {
    final existente = await getConteo(fecha);
    if (existente != null) return existente;
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final conteoId = await txn.insert('conteos_inventario', {
        'fecha': sqlDate(fecha),
        'usuario_id': usuarioId,
        'estado': 'BORRADOR',
        'creado_en': sqlNow(),
      });
      final insumos = await txn.rawQuery('''
        SELECT i.id, i.costo_promedio, COALESCE(s.stock, 0) AS stock
        FROM insumos i
        LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
        WHERE i.activo = 1 AND i.modo_control <> 'DISPONIBILIDAD'
        ORDER BY i.nombre COLLATE NOCASE
      ''');
      for (final insumo in insumos) {
        final stock = (insumo['stock'] as num).toDouble();
        await txn.insert('detalle_conteo', {
          'conteo_id': conteoId,
          'insumo_id': insumo['id'],
          'stock_sistema': stock,
          'stock_contado': stock,
          'diferencia': 0,
          'costo_unitario': (insumo['costo_promedio'] as num).toDouble(),
        });
      }
      return Conteo(
        id: conteoId,
        fecha: sqlDate(fecha),
        estado: 'BORRADOR',
        usuarioNombre: '',
      );
    });
  }

  Future<ConteoDetalle> getDetalle(int conteoId) async {
    final db = await AppDatabase.instance.database;
    final conteos = await db.rawQuery('''
      SELECT c.*, u.nombre AS usuario_nombre
      FROM conteos_inventario c
      INNER JOIN usuarios u ON u.id = c.usuario_id
      WHERE c.id = ?
      LIMIT 1
    ''', [conteoId]);
    if (conteos.isEmpty) throw StateError('El conteo no existe.');
    final rows = await db.rawQuery('''
      SELECT dc.*, i.nombre AS insumo_nombre, u.abreviatura AS unidad
      FROM detalle_conteo dc
      INNER JOIN insumos i ON i.id = dc.insumo_id
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      WHERE dc.conteo_id = ?
      ORDER BY i.nombre COLLATE NOCASE
    ''', [conteoId]);
    return ConteoDetalle(
      conteo: _fromRow(conteos.first),
      lineas: rows
          .map(
            (row) => ConteoLinea(
              id: row['id']! as int,
              insumoId: row['insumo_id']! as int,
              nombre: row['insumo_nombre']! as String,
              unidad: row['unidad']! as String,
              stockSistema: (row['stock_sistema'] as num).toDouble(),
              stockContado: (row['stock_contado'] as num).toDouble(),
              diferencia: (row['diferencia'] as num).toDouble(),
              costoUnitario: (row['costo_unitario'] as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  Future<void> guardarBorrador(
    int conteoId,
    Map<int, double> contados,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final entry in contados.entries) {
        final stockRows = await txn.query(
          'v_stock_insumos',
          columns: ['stock'],
          where: 'insumo_id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        final stockSistema = stockRows.isEmpty
            ? 0.0
            : (stockRows.first['stock'] as num).toDouble();
        await txn.update(
          'detalle_conteo',
          {
            'stock_sistema': stockSistema,
            'stock_contado': entry.value,
            'diferencia': entry.value - stockSistema,
          },
          where: 'conteo_id = ? AND insumo_id = ?',
          whereArgs: [conteoId, entry.key],
        );
      }
    });
  }

  Future<void> cerrarConteo(
    int conteoId,
    Map<int, double> contados, {
    String? observacion,
  }) async {
    await guardarBorrador(conteoId, contados);
    final db = await AppDatabase.instance.database;
    await db.update(
      'conteos_inventario',
      {
        'estado': 'CERRADO',
        'observacion': observacion?.trim().isEmpty == true
            ? null
            : observacion?.trim(),
      },
      where: 'id = ?',
      whereArgs: [conteoId],
    );
  }

  Future<List<Conteo>> getHistorial({int limite = 60}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, u.nombre AS usuario_nombre
      FROM conteos_inventario c
      INNER JOIN usuarios u ON u.id = c.usuario_id
      ORDER BY c.fecha DESC
      LIMIT ?
    ''', [limite]);
    return rows.map(_fromRow).toList();
  }

  Conteo _fromRow(Map<String, Object?> row) => Conteo(
    id: row['id']! as int,
    fecha: row['fecha']! as String,
    estado: row['estado']! as String,
    observacion: row['observacion'] as String?,
    usuarioNombre: (row['usuario_nombre'] as String?) ?? '',
  );
}
