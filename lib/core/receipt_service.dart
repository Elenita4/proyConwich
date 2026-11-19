import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';
import 'sales_repository.dart';

/// Genera la nota de venta en un PDF de 80 mm y la envía al diálogo de
/// impresión del sistema (útil para impresoras térmicas). Usa una fuente
/// Unicode (Roboto) embebida para que acentos y ñ se impriman bien.
class ReceiptService {
  pw.Font? _regular;
  pw.Font? _bold;

  Future<void> _cargarFuentes() async {
    if (_regular != null && _bold != null) return;
    _regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    _bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
  }

  Future<Uint8List> generarNotaVenta({
    required PedidoDetalle detalle,
    required String turno,
    required String cajero,
  }) async {
    await _cargarFuentes();
    final regular = _regular!;
    final bold = _bold!;

    final meta = await AppDatabase.instance.leerAppMeta();
    final negocio = (meta?['nombre_negocio'] as String?) ?? 'Conwich';
    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateTimeShort(fecha);

    double sumar(String metodo) => detalle.pagos
        .where((pago) => pago.metodo == metodo && pago.estado == 'CONFIRMADO')
        .fold<double>(0, (suma, pago) => suma + pago.monto);
    final efectivo = sumar('EFECTIVO');
    final qr = sumar('QR');

    final lineas = detalle.lineas.where((linea) => !linea.esComponente).toList();

    final doc = pw.Document();
    final pequeno = pw.TextStyle(font: regular, fontSize: 8);
    final negrita = pw.TextStyle(font: bold, fontSize: 8);

    pw.Widget fila(String etiqueta, String valor, {bool fuerte = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(etiqueta, style: fuerte ? negrita : pequeno),
              ),
              pw.Text(valor, style: fuerte ? negrita : pequeno),
            ],
          ),
        );

    // Alto compacto según la cantidad de líneas (mínimo 100 mm).
    final altoMm = (90 + lineas.length * 7.0).clamp(100.0, 500.0);
    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      altoMm * PdfPageFormat.mm,
      marginAll: 4 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              negocio,
              style: pw.TextStyle(
                font: bold,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'NOTA DE VENTA',
              style: pw.TextStyle(
                font: bold,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(),
          fila('Pedido', '#${pedido.id}'),
          fila('Fecha', fechaTexto),
          if (turno.isNotEmpty) fila('Turno', turno),
          fila('Cajero', cajero),
          if (pedido.referencia != null && pedido.referencia!.isNotEmpty)
            fila('Referencia', pedido.referencia!),
          pw.Divider(),
          ...lineas.map(
            (linea) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${_cantidad(linea.cantidad)} x ${linea.nombreParaMostrar}',
                      style: pequeno,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(formatMoney(linea.subtotal), style: pequeno),
                ],
              ),
            ),
          ),
          pw.Divider(),
          fila('TOTAL', formatMoney(pedido.total), fuerte: true),
          pw.SizedBox(height: 3),
          if (efectivo > 0) fila('Efectivo', formatMoney(efectivo)),
          if (qr > 0) fila('QR', formatMoney(qr)),
          pw.Divider(),
          pw.Center(child: pw.Text('Gracias por su compra', style: negrita)),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> imprimirNotaVenta({
    required PedidoDetalle detalle,
    required String turno,
    required String cajero,
  }) async {
    final bytes = await generarNotaVenta(
      detalle: detalle,
      turno: turno,
      cajero: cajero,
    );
    await Printing.layoutPdf(
      name: 'nota_venta_${detalle.pedido.id}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  String _cantidad(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
