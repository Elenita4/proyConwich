import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';

class Caja {
  const Caja({
    required this.id,
    required this.fecha,
    required this.numeroTurno,
    required this.estado,
    required this.fondoInicial,
    this.efectivoContado,
    this.qrVerificado,
    this.sobrante,
    this.totalEsperado,
    required this.fechaApertura,
    this.fechaCierre,
    required this.usuarioApertura,
    this.usuarioCierre,
    this.perfilApertura = '',
    this.perfilCierre,
  });

  final int id;
  final String fecha;
  final int numeroTurno;
  final String estado;
  final double fondoInicial;
  final double? efectivoContado;
  final double? qrVerificado;

  /// Diferencia ingresada al cerrar: positiva = sobrante, negativa = faltante.
  final double? sobrante;

  /// Total esperado congelado al cerrar la caja.
  final double? totalEsperado;
  final String fechaApertura;
  final String? fechaCierre;
  final String usuarioApertura;
  final String? usuarioCierre;
  final String perfilApertura;
  final String? perfilCierre;

  bool get abierta => estado == 'ABIERTA';
  String get turnoLabel => 'Turno $numeroTurno';
}

class CajaResumen {
  const CajaResumen({
    required this.fondoInicial,
    required this.ventasEfectivo,
    required this.ventasQr,
    required this.salidasEfectivo,
    required this.salidasQr,
    required this.esperadoEfectivo,
    required this.esperadoQr,
    this.efectivoContado,
    this.qrVerificado,
    this.sobrante,
  });

  final double fondoInicial;
  final double ventasEfectivo;
  final double ventasQr;
  final double salidasEfectivo;
  final double salidasQr;
  final double esperadoEfectivo;
  final double esperadoQr;
  final double? efectivoContado;
  final double? qrVerificado;
  final double? sobrante;

  double get totalEsperado => esperadoEfectivo + esperadoQr;

  /// Total que debería quedar en caja sumando el sobrante/faltante informado.
  double get totalActual => totalEsperado + (sobrante ?? 0);
}

/// Caja con sus totales calculados, usada por el historial del día.
class CajaHistorial {
  const CajaHistorial({required this.caja, required this.resumen});

  final Caja caja;
  final CajaResumen resumen;
}

class CashRepository {
  Future<Caja?> getCajaAbierta() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, ua.nombre AS usuario_apertura,
             ua.perfil AS usuario_apertura_perfil,
             uc.nombre AS usuario_cierre,
             uc.perfil AS usuario_cierre_perfil
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      WHERE c.estado = 'ABIERTA'
      ORDER BY c.fecha_apertura DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Caja> abrirCaja({
    required DateTime fecha,
    required double fondoInicial,
    required int usuarioId,
  }) async {
    final abierta = await getCajaAbierta();
    if (abierta != null) {
      throw StateError(
        'Ya hay una caja abierta (${abierta.turnoLabel}). Ciérrala antes de abrir otra.',
      );
    }
    final db = await AppDatabase.instance.database;
    final numeroTurno = await proximoTurno(fecha);
    final id = await db.insert('cajas', {
      'fecha': sqlDate(fecha),
      'numero_turno': numeroTurno,
      'usuario_apertura_id': usuarioId,
      'fecha_apertura': sqlNow(),
      'fondo_inicial': fondoInicial,
      'estado': 'ABIERTA',
    });
    return Caja(
      id: id,
      fecha: sqlDate(fecha),
      numeroTurno: numeroTurno,
      estado: 'ABIERTA',
      fondoInicial: fondoInicial,
      fechaApertura: sqlNow(),
      usuarioApertura: '',
    );
  }

  /// Número que tendrá la próxima caja abierta para la fecha indicada.
  Future<int> proximoTurno(DateTime fecha) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(numero_turno), 0) + 1 AS siguiente '
      'FROM cajas WHERE fecha = ?',
      [sqlDate(fecha)],
    );
    return ((rows.first['siguiente'] as num?)?.toInt()) ?? 1;
  }

  Future<void> cerrarCaja({
    required int cajaId,
    required int usuarioId,
    double? sobrante,
    double? efectivoContado,
    double? qrVerificado,
    required String observacion,
  }) async {
    if (observacion.trim().isEmpty) {
      throw ArgumentError('La observación de caja es obligatoria.');
    }
    final db = await AppDatabase.instance.database;
    final resumen = await getResumen(cajaId);
    await db.update(
      'cajas',
      {
        'efectivo_contado': efectivoContado,
        'qr_verificado': qrVerificado,
        'sobrante': sobrante,
        'total_esperado': resumen.totalEsperado,
        'usuario_cierre_id': usuarioId,
        'fecha_cierre': sqlNow(),
        'estado': 'CERRADA',
        'observacion': observacion.trim(),
      },
      where: 'id = ?',
      whereArgs: [cajaId],
    );
  }

  /// Registra una salida de dinero de la caja (luz, gas, sueldos, etc).
  Future<void> registrarSalida({
    required int cajaId,
    required int usuarioId,
    required double monto,
    String? descripcion,
  }) async {
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    final db = await AppDatabase.instance.database;
    final categoriaId = await _categoriaSalidas(db);
    await db.insert('gastos', {
      'categoria_gasto_id': categoriaId,
      'usuario_id': usuarioId,
      'fecha': sqlNow(),
      'monto': monto,
      'metodo_pago': 'EFECTIVO',
      'caja_id': cajaId,
      'descripcion': descripcion?.trim().isEmpty == true
          ? null
          : descripcion?.trim(),
      'estado': 'REGISTRADO',
    });
  }

  Future<int> _categoriaSalidas(Database db) async {
    final rows = await db.query(
      'categorias_gasto',
      where: 'nombre = ?',
      whereArgs: ['Salidas'],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id']! as int;
    return db.insert('categorias_gasto', {'nombre': 'Salidas', 'activo': 1});
  }

  Future<CajaResumen> getResumen(int cajaId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        c.fondo_inicial,
        c.efectivo_contado,
        c.qr_verificado,
        c.sobrante,
        c.total_esperado,
        COALESCE((SELECT SUM(monto) FROM pagos WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'CONFIRMADO'), 0) AS ventas_efectivo,
        COALESCE((SELECT SUM(monto) FROM pagos WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'CONFIRMADO'), 0) AS ventas_qr,
        COALESCE((SELECT SUM(monto) FROM gastos WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'REGISTRADO'), 0) AS salidas_efectivo,
        COALESCE((SELECT SUM(monto) FROM gastos WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'REGISTRADO'), 0) AS salidas_qr
      FROM cajas c
      WHERE c.id = ?
    ''',
      [cajaId],
    );
    if (rows.isEmpty) throw StateError('La caja no existe.');
    final row = rows.first;
    double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
    final fondo = value('fondo_inicial');
    final ventasEfectivo = value('ventas_efectivo');
    final ventasQr = value('ventas_qr');
    final salidasEfectivo = value('salidas_efectivo');
    final salidasQr = value('salidas_qr');
    return CajaResumen(
      fondoInicial: fondo,
      ventasEfectivo: ventasEfectivo,
      ventasQr: ventasQr,
      salidasEfectivo: salidasEfectivo,
      salidasQr: salidasQr,
      esperadoEfectivo: fondo + ventasEfectivo - salidasEfectivo,
      esperadoQr: ventasQr - salidasQr,
      efectivoContado: row['efectivo_contado'] == null
          ? null
          : (row['efectivo_contado'] as num).toDouble(),
      qrVerificado: row['qr_verificado'] == null
          ? null
          : (row['qr_verificado'] as num).toDouble(),
      sobrante: row['sobrante'] == null
          ? null
          : (row['sobrante'] as num).toDouble(),
    );
  }

  Future<List<Caja>> getCajas({int limite = 60}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.*, ua.nombre AS usuario_apertura,
             ua.perfil AS usuario_apertura_perfil,
             uc.nombre AS usuario_cierre,
             uc.perfil AS usuario_cierre_perfil
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      ORDER BY c.fecha DESC, c.numero_turno DESC, c.fecha_apertura DESC
      LIMIT ?
    ''',
      [limite],
    );
    return rows.map(_fromRow).toList();
  }

  /// Historial del día: solo las cajas de la fecha indicada, con los totales
  /// de cada turno calculados en la misma consulta.
  Future<List<CajaHistorial>> getCajasDelDia(DateTime fecha) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.*, ua.nombre AS usuario_apertura,
             ua.perfil AS usuario_apertura_perfil,
             uc.nombre AS usuario_cierre,
             uc.perfil AS usuario_cierre_perfil,
             COALESCE((SELECT SUM(monto) FROM pagos
               WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO'
                 AND estado = 'CONFIRMADO'), 0) AS ventas_efectivo,
             COALESCE((SELECT SUM(monto) FROM pagos
               WHERE caja_id = c.id AND metodo_pago = 'QR'
                 AND estado = 'CONFIRMADO'), 0) AS ventas_qr,
             COALESCE((SELECT SUM(monto) FROM gastos
               WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO'
                 AND estado = 'REGISTRADO'), 0) AS salidas_efectivo,
             COALESCE((SELECT SUM(monto) FROM gastos
               WHERE caja_id = c.id AND metodo_pago = 'QR'
                 AND estado = 'REGISTRADO'), 0) AS salidas_qr
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      WHERE c.fecha = ?
      ORDER BY c.numero_turno DESC
    ''',
      [sqlDate(fecha)],
    );
    return rows.map((row) {
      double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
      final fondo = value('fondo_inicial');
      final ventasEfectivo = value('ventas_efectivo');
      final ventasQr = value('ventas_qr');
      final salidasEfectivo = value('salidas_efectivo');
      final salidasQr = value('salidas_qr');
      return CajaHistorial(
        caja: _fromRow(row),
        resumen: CajaResumen(
          fondoInicial: fondo,
          ventasEfectivo: ventasEfectivo,
          ventasQr: ventasQr,
          salidasEfectivo: salidasEfectivo,
          salidasQr: salidasQr,
          esperadoEfectivo: fondo + ventasEfectivo - salidasEfectivo,
          esperadoQr: ventasQr - salidasQr,
          sobrante: row['sobrante'] == null
              ? null
              : (row['sobrante'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  /// Cajas de un rango (para el reporte histórico por día/semana/mes/año).
  Future<List<CajaHistorial>> getCajasEntre(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.*, ua.nombre AS usuario_apertura,
             ua.perfil AS usuario_apertura_perfil,
             uc.nombre AS usuario_cierre,
             uc.perfil AS usuario_cierre_perfil,
             COALESCE((SELECT SUM(monto) FROM pagos
               WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO'
                 AND estado = 'CONFIRMADO'), 0) AS ventas_efectivo,
             COALESCE((SELECT SUM(monto) FROM pagos
               WHERE caja_id = c.id AND metodo_pago = 'QR'
                 AND estado = 'CONFIRMADO'), 0) AS ventas_qr,
             COALESCE((SELECT SUM(monto) FROM gastos
               WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO'
                 AND estado = 'REGISTRADO'), 0) AS salidas_efectivo,
             COALESCE((SELECT SUM(monto) FROM gastos
               WHERE caja_id = c.id AND metodo_pago = 'QR'
                 AND estado = 'REGISTRADO'), 0) AS salidas_qr
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      WHERE c.fecha >= ? AND c.fecha < ?
      ORDER BY c.fecha DESC, c.numero_turno DESC
    ''',
      [sqlDate(desde), sqlDate(hasta)],
    );
    return rows.map((row) {
      double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
      final fondo = value('fondo_inicial');
      final ventasEfectivo = value('ventas_efectivo');
      final ventasQr = value('ventas_qr');
      final salidasEfectivo = value('salidas_efectivo');
      final salidasQr = value('salidas_qr');
      return CajaHistorial(
        caja: _fromRow(row),
        resumen: CajaResumen(
          fondoInicial: fondo,
          ventasEfectivo: ventasEfectivo,
          ventasQr: ventasQr,
          salidasEfectivo: salidasEfectivo,
          salidasQr: salidasQr,
          esperadoEfectivo: fondo + ventasEfectivo - salidasEfectivo,
          esperadoQr: ventasQr - salidasQr,
          sobrante: row['sobrante'] == null
              ? null
              : (row['sobrante'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  Caja _fromRow(Map<String, Object?> row) => Caja(
    id: row['id']! as int,
    fecha: row['fecha']! as String,
    numeroTurno: (row['numero_turno'] as num).toInt(),
    estado: row['estado']! as String,
    fondoInicial: (row['fondo_inicial'] as num).toDouble(),
    efectivoContado: row['efectivo_contado'] == null
        ? null
        : (row['efectivo_contado'] as num).toDouble(),
    qrVerificado: row['qr_verificado'] == null
        ? null
        : (row['qr_verificado'] as num).toDouble(),
    sobrante: row['sobrante'] == null
        ? null
        : (row['sobrante'] as num).toDouble(),
    totalEsperado: row['total_esperado'] == null
        ? null
        : (row['total_esperado'] as num).toDouble(),
    fechaApertura: row['fecha_apertura']! as String,
    fechaCierre: row['fecha_cierre'] as String?,
    usuarioApertura: (row['usuario_apertura'] as String?) ?? '',
    usuarioCierre: row['usuario_cierre'] as String?,
    perfilApertura: (row['usuario_apertura_perfil'] as String?) ?? '',
    perfilCierre: row['usuario_cierre_perfil'] as String?,
  );
}
