import '../data/database/app_database.dart';
import 'date_utils.dart';
import 'menu_repository.dart';

class Caja {
  const Caja({
    required this.id,
    required this.fecha,
    required this.turno,
    required this.estado,
    required this.fondoInicial,
    this.efectivoContado,
    this.qrVerificado,
    required this.fechaApertura,
    this.fechaCierre,
    required this.usuarioApertura,
    this.usuarioCierre,
  });

  final int id;
  final String fecha;
  final String turno;
  final String estado;
  final double fondoInicial;
  final double? efectivoContado;
  final double? qrVerificado;
  final String fechaApertura;
  final String? fechaCierre;
  final String usuarioApertura;
  final String? usuarioCierre;

  bool get abierta => estado == 'ABIERTA';
}

class CajaResumen {
  const CajaResumen({
    required this.fondoInicial,
    required this.ventasEfectivo,
    required this.ventasQr,
    required this.comprasEfectivo,
    required this.comprasQr,
    required this.gastosEfectivo,
    required this.gastosQr,
    required this.sueldosEfectivo,
    required this.sueldosQr,
    required this.esperadoEfectivo,
    required this.esperadoQr,
    this.efectivoContado,
    this.qrVerificado,
  });

  final double fondoInicial;
  final double ventasEfectivo;
  final double ventasQr;
  final double comprasEfectivo;
  final double comprasQr;
  final double gastosEfectivo;
  final double gastosQr;
  final double sueldosEfectivo;
  final double sueldosQr;
  final double esperadoEfectivo;
  final double esperadoQr;
  final double? efectivoContado;
  final double? qrVerificado;

  double get totalEsperado => esperadoEfectivo + esperadoQr;
  double get diferenciaEfectivo =>
      (efectivoContado ?? esperadoEfectivo) - esperadoEfectivo;
  double get diferenciaQr => (qrVerificado ?? esperadoQr) - esperadoQr;
}

class CashRepository {
  Future<Caja?> getCajaAbierta() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, ua.nombre AS usuario_apertura,
             uc.nombre AS usuario_cierre
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
    required String turno,
    required double fondoInicial,
    required int usuarioId,
  }) async {
    final abierta = await getCajaAbierta();
    if (abierta != null) {
      throw StateError(
        'Ya hay una caja abierta (${abierta.turno}). Ciérrala antes de abrir otra.',
      );
    }
    final db = await AppDatabase.instance.database;
    final existente = await db.query(
      'cajas',
      where: 'fecha = ? AND turno = ?',
      whereArgs: [sqlDate(fecha), turno],
      limit: 1,
    );
    if (existente.isNotEmpty) {
      throw StateError('Ya existe una caja para ese turno y fecha.');
    }
    final id = await db.insert('cajas', {
      'fecha': sqlDate(fecha),
      'turno': turno,
      'usuario_apertura_id': usuarioId,
      'fecha_apertura': sqlNow(),
      'fondo_inicial': fondoInicial,
      'estado': 'ABIERTA',
    });
    return Caja(
      id: id,
      fecha: sqlDate(fecha),
      turno: turno,
      estado: 'ABIERTA',
      fondoInicial: fondoInicial,
      fechaApertura: sqlNow(),
      usuarioApertura: '',
    );
  }

  Future<void> cerrarCaja({
    required int cajaId,
    required double efectivoContado,
    required double qrVerificado,
    required int usuarioId,
    String? observacion,
  }) async {
    final db = await AppDatabase.instance.database;
    final caja = await _getCaja(cajaId);
    await db.update(
      'cajas',
      {
        'efectivo_contado': efectivoContado,
        'qr_verificado': qrVerificado,
        'usuario_cierre_id': usuarioId,
        'fecha_cierre': sqlNow(),
        'estado': 'CERRADA',
        'observacion': observacion,
      },
      where: 'id = ?',
      whereArgs: [cajaId],
    );
    await MenuRepository().cerrarPorTurno(
      parseSqlDate(caja.fecha),
      caja.turno,
    );
  }

  Future<CajaResumen> getResumen(int cajaId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        c.fondo_inicial,
        c.efectivo_contado,
        c.qr_verificado,
        COALESCE((SELECT SUM(monto) FROM pagos WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'CONFIRMADO'), 0) AS ventas_efectivo,
        COALESCE((SELECT SUM(monto) FROM pagos WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'CONFIRMADO'), 0) AS ventas_qr,
        COALESCE((SELECT SUM(total) FROM compras WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'REGISTRADA'), 0) AS compras_efectivo,
        COALESCE((SELECT SUM(total) FROM compras WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'REGISTRADA'), 0) AS compras_qr,
        COALESCE((SELECT SUM(monto) FROM gastos WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'REGISTRADO'), 0) AS gastos_efectivo,
        COALESCE((SELECT SUM(monto) FROM gastos WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'REGISTRADO'), 0) AS gastos_qr,
        COALESCE((SELECT SUM(monto) FROM sueldos WHERE caja_id = c.id AND metodo_pago = 'EFECTIVO' AND estado = 'REGISTRADO'), 0) AS sueldos_efectivo,
        COALESCE((SELECT SUM(monto) FROM sueldos WHERE caja_id = c.id AND metodo_pago = 'QR' AND estado = 'REGISTRADO'), 0) AS sueldos_qr
      FROM cajas c
      WHERE c.id = ?
    ''', [cajaId]);
    if (rows.isEmpty) throw StateError('La caja no existe.');
    final row = rows.first;
    double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
    final fondo = value('fondo_inicial');
    final ventasEfectivo = value('ventas_efectivo');
    final ventasQr = value('ventas_qr');
    final comprasEfectivo = value('compras_efectivo');
    final comprasQr = value('compras_qr');
    final gastosEfectivo = value('gastos_efectivo');
    final gastosQr = value('gastos_qr');
    final sueldosEfectivo = value('sueldos_efectivo');
    final sueldosQr = value('sueldos_qr');
    return CajaResumen(
      fondoInicial: fondo,
      ventasEfectivo: ventasEfectivo,
      ventasQr: ventasQr,
      comprasEfectivo: comprasEfectivo,
      comprasQr: comprasQr,
      gastosEfectivo: gastosEfectivo,
      gastosQr: gastosQr,
      sueldosEfectivo: sueldosEfectivo,
      sueldosQr: sueldosQr,
      esperadoEfectivo:
          fondo + ventasEfectivo - comprasEfectivo - gastosEfectivo - sueldosEfectivo,
      esperadoQr: ventasQr - comprasQr - gastosQr - sueldosQr,
      efectivoContado: row['efectivo_contado'] == null
          ? null
          : (row['efectivo_contado'] as num).toDouble(),
      qrVerificado: row['qr_verificado'] == null
          ? null
          : (row['qr_verificado'] as num).toDouble(),
    );
  }

  Future<List<Caja>> getCajas({int limite = 60}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, ua.nombre AS usuario_apertura,
             uc.nombre AS usuario_cierre
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      ORDER BY c.fecha DESC, c.fecha_apertura DESC
      LIMIT ?
    ''', [limite]);
    return rows.map(_fromRow).toList();
  }

  Future<Caja> _getCaja(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, ua.nombre AS usuario_apertura,
             uc.nombre AS usuario_cierre
      FROM cajas c
      INNER JOIN usuarios ua ON ua.id = c.usuario_apertura_id
      LEFT JOIN usuarios uc ON uc.id = c.usuario_cierre_id
      WHERE c.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) throw StateError('La caja no existe.');
    return _fromRow(rows.first);
  }

  Caja _fromRow(Map<String, Object?> row) => Caja(
    id: row['id']! as int,
    fecha: row['fecha']! as String,
    turno: row['turno']! as String,
    estado: row['estado']! as String,
    fondoInicial: (row['fondo_inicial'] as num).toDouble(),
    efectivoContado: row['efectivo_contado'] == null
        ? null
        : (row['efectivo_contado'] as num).toDouble(),
    qrVerificado: row['qr_verificado'] == null
        ? null
        : (row['qr_verificado'] as num).toDouble(),
    fechaApertura: row['fecha_apertura']! as String,
    fechaCierre: row['fecha_cierre'] as String?,
    usuarioApertura: (row['usuario_apertura'] as String?) ?? '',
    usuarioCierre: row['usuario_cierre'] as String?,
  );
}
