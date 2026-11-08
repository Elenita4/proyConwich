import '../data/database/app_database.dart';
import 'date_utils.dart';

class CategoriaGasto {
  const CategoriaGasto({
    this.id,
    required this.nombre,
    required this.activo,
  });

  final int? id;
  final String nombre;
  final bool activo;
}

class Gasto {
  const Gasto({
    required this.id,
    required this.fecha,
    required this.monto,
    required this.metodoPago,
    this.descripcion,
    required this.estado,
    required this.categoriaNombre,
    required this.usuarioNombre,
  });

  final int id;
  final String fecha;
  final double monto;
  final String metodoPago;
  final String? descripcion;
  final String estado;
  final String categoriaNombre;
  final String usuarioNombre;

  bool get anulado => estado == 'ANULADO';
}

class Sueldo {
  const Sueldo({
    required this.id,
    required this.fecha,
    required this.periodo,
    required this.monto,
    required this.metodoPago,
    this.observacion,
    required this.estado,
    required this.usuarioNombre,
  });

  final int id;
  final String fecha;
  final String periodo;
  final double monto;
  final String metodoPago;
  final String? observacion;
  final String estado;
  final String usuarioNombre;

  bool get anulado => estado == 'ANULADO';
}

class ExpenseRepository {
  Future<List<CategoriaGasto>> getCategoriasGasto({
    bool soloActivas = false,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categorias_gasto',
      where: soloActivas ? 'activo = 1' : null,
      orderBy: 'activo DESC, nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => CategoriaGasto(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            activo: (row['activo'] as num).toInt() == 1,
          ),
        )
        .toList();
  }

  Future<void> saveCategoriaGasto({
    int? id,
    required String nombre,
    bool activo = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final values = {'nombre': nombre.trim(), 'activo': activo ? 1 : 0};
    if (id == null) {
      await db.insert('categorias_gasto', values);
    } else {
      await db.update(
        'categorias_gasto',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> setCategoriaGastoActiva(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'categorias_gasto',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Gasto>> getGastos({int limite = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT g.*, cg.nombre AS categoria_nombre, u.nombre AS usuario_nombre
      FROM gastos g
      INNER JOIN categorias_gasto cg ON cg.id = g.categoria_gasto_id
      INNER JOIN usuarios u ON u.id = g.usuario_id
      ORDER BY g.fecha DESC
      LIMIT ?
    ''', [limite]);
    return rows
        .map(
          (row) => Gasto(
            id: row['id']! as int,
            fecha: row['fecha']! as String,
            monto: (row['monto'] as num).toDouble(),
            metodoPago: row['metodo_pago']! as String,
            descripcion: row['descripcion'] as String?,
            estado: row['estado']! as String,
            categoriaNombre: row['categoria_nombre']! as String,
            usuarioNombre: row['usuario_nombre']! as String,
          ),
        )
        .toList();
  }

  Future<int> registrarGasto({
    required int categoriaGastoId,
    required int usuarioId,
    int? cajaId,
    required double monto,
    required String metodoPago,
    String? descripcion,
  }) async {
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    final db = await AppDatabase.instance.database;
    return db.insert('gastos', {
      'categoria_gasto_id': categoriaGastoId,
      'usuario_id': usuarioId,
      'fecha': sqlNow(),
      'monto': monto,
      'metodo_pago': metodoPago,
      'caja_id': cajaId,
      'descripcion': _limpiar(descripcion),
      'estado': 'REGISTRADO',
    });
  }

  Future<void> anularGasto(int gastoId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'gastos',
      {'estado': 'ANULADO'},
      where: 'id = ?',
      whereArgs: [gastoId],
    );
  }

  Future<List<Sueldo>> getSueldos({int limite = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*, u.nombre AS usuario_nombre
      FROM sueldos s
      INNER JOIN usuarios u ON u.id = s.usuario_id
      ORDER BY s.fecha DESC
      LIMIT ?
    ''', [limite]);
    return rows
        .map(
          (row) => Sueldo(
            id: row['id']! as int,
            fecha: row['fecha']! as String,
            periodo: row['periodo']! as String,
            monto: (row['monto'] as num).toDouble(),
            metodoPago: row['metodo_pago']! as String,
            observacion: row['observacion'] as String?,
            estado: row['estado']! as String,
            usuarioNombre: row['usuario_nombre']! as String,
          ),
        )
        .toList();
  }

  Future<int> registrarSueldo({
    required int usuarioId,
    int? cajaId,
    required String periodo,
    required double monto,
    required String metodoPago,
    String? observacion,
  }) async {
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    if (periodo.trim().isEmpty) {
      throw StateError('Indica el período del sueldo.');
    }
    final db = await AppDatabase.instance.database;
    return db.insert('sueldos', {
      'usuario_id': usuarioId,
      'fecha': sqlNow(),
      'periodo': periodo.trim(),
      'monto': monto,
      'metodo_pago': metodoPago,
      'caja_id': cajaId,
      'observacion': _limpiar(observacion),
      'estado': 'REGISTRADO',
    });
  }

  Future<void> anularSueldo(int sueldoId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'sueldos',
      {'estado': 'ANULADO'},
      where: 'id = ?',
      whereArgs: [sueldoId],
    );
  }

  String? _limpiar(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
