import '../../../data/database/app_database.dart';

class SalesReport {
  const SalesReport({
    required this.from,
    required this.to,
    required this.salesCount,
    required this.total,
    required this.lines,
  });

  final DateTime from;
  final DateTime to;
  final int salesCount;
  final double total;
  final List<SalesReportLine> lines;
}

class SalesReportLine {
  const SalesReportLine({
    required this.productName,
    required this.quantity,
    required this.total,
  });

  final String productName;
  final int quantity;
  final double total;
}

class SalesReportRepository {
  Future<SalesReport> getReport(DateTime from, DateTime to) async {
    final db = await AppDatabase.instance.database;
    final sales = await db.query(
      'ventas',
      columns: ['id_venta', 'total'],
      where: "estado = 'REALIZADA' AND fecha_hora >= ? AND fecha_hora < ?",
      whereArgs: [_sqlDate(from), _sqlDate(to)],
    );
    final rows = await db.rawQuery(
      '''
      SELECT p.nombre AS producto, SUM(d.cantidad) AS cantidad,
             SUM(d.subtotal) AS total
      FROM venta_detalle d
      INNER JOIN ventas v ON v.id_venta = d.id_venta
      INNER JOIN productos p ON p.id_producto = d.id_producto
      WHERE v.estado = 'REALIZADA'
        AND v.fecha_hora >= ? AND v.fecha_hora < ?
      GROUP BY d.id_producto, p.nombre
      ORDER BY total DESC, producto COLLATE NOCASE
      ''',
      [_sqlDate(from), _sqlDate(to)],
    );
    return SalesReport(
      from: from,
      to: to,
      salesCount: sales.length,
      total: sales.fold<double>(
        0,
        (sum, sale) => sum + (sale['total'] as num).toDouble(),
      ),
      lines: rows
          .map(
            (row) => SalesReportLine(
              productName: row['producto'] as String,
              quantity: (row['cantidad'] as num).toInt(),
              total: (row['total'] as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  String _sqlDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}
