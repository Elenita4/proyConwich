import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/sales_report_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _repository = SalesReportRepository();
  String _period = 'day';
  late Future<SalesReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DateTimeRange _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_period == 'week') {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 7)),
      );
    }
    if (_period == 'month') {
      final start = DateTime(today.year, today.month);
      return DateTimeRange(
        start: start,
        end: DateTime(today.year, today.month + 1),
      );
    }
    return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
  }

  void _reload() {
    final range = _range();
    _reportFuture = _repository.getReport(range.start, range.end);
  }

  Future<void> _sharePdf(SalesReport report) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Reporte de ventas',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${_formatDate(report.from)} - ${_formatDate(report.to.subtract(const Duration(seconds: 1)))}',
          ),
          pw.SizedBox(height: 16),
          pw.Text('Pedidos realizados: ${report.salesCount}'),
          pw.Text('Total vendido: Bs ${report.total.toStringAsFixed(2)}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Producto', 'Cantidad', 'Total'],
            data: [
              for (final line in report.lines)
                [
                  line.productName,
                  '${line.quantity}',
                  'Bs ${line.total.toStringAsFixed(2)}',
                ],
            ],
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'reporte-ventas-$_period.pdf',
    );
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reportes de ventas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Día')),
              ButtonSegment(value: 'week', label: Text('Semana')),
              ButtonSegment(value: 'month', label: Text('Mes')),
            ],
            selected: {_period},
            onSelectionChanged: (value) {
              setState(() {
                _period = value.first;
                _reload();
              });
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<SalesReport>(
            future: _reportFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Text('No se pudo generar el reporte.');
              }
              final report = snapshot.data!;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pedidos realizados: ${report.salesCount}'),
                      Text(
                        'Total vendido: Bs ${report.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Divider(),
                      if (report.lines.isEmpty)
                        const Text('No hay ventas en este periodo.')
                      else
                        ...report.lines.map(
                          (line) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(line.productName),
                            subtitle: Text(
                              '${line.quantity} unidades vendidas',
                            ),
                            trailing: Text(
                              'Bs ${line.total.toStringAsFixed(2)}',
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _sharePdf(report),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Generar y compartir PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
