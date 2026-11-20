import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/database/app_database.dart';
import 'cash_repository.dart';
import 'date_utils.dart';
import 'sales_repository.dart';

/// Genera las dos fichas de la venta en un PDF de 80 mm y las envía al diálogo
/// de impresión del sistema (útil para impresoras térmicas). Usa una fuente
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

    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateShort(fecha);
    final horaTexto = fecha == null ? '' : formatTimeShort(fecha);
    final fechaHora = horaTexto.isEmpty
        ? 'Fecha: $fechaTexto'
        : 'Fecha: $fechaTexto   Hora: $horaTexto';

    final lineas = detalle.lineas.where((linea) => !linea.esComponente).toList();

    Uint8List? logoBytes;
    try {
      logoBytes = (await rootBundle.load(
        'assets/images/logo_ticket.png',
      )).buffer.asUint8List();
    } catch (_) {
      // El logo es opcional: si falta el asset, el PDF se genera igual.
    }

    final doc = pw.Document();
    final pequeno = pw.TextStyle(font: regular, fontSize: 8);
    final negrita = pw.TextStyle(font: bold, fontSize: 8);

    // Ficha 1: copia corta para el cliente.
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          55 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoBytes != null) ...[
              pw.Image(
                pw.MemoryImage(logoBytes),
                width: 18 * PdfPageFormat.mm,
              ),
              pw.SizedBox(height: 3),
            ],
            pw.Text(
              'PEDIDO #${pedido.id}',
              style: pw.TextStyle(
                font: bold,
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(fechaHora, style: pequeno),
          ],
        ),
      ),
    );

    // Ficha 2: copia del vendedor con el detalle.
    final altoMm = (80 + lineas.length * 8.0).clamp(100.0, 500.0);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          altoMm * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => [
          if (logoBytes != null) ...[
            pw.Center(
              child: pw.Image(
                pw.MemoryImage(logoBytes),
                width: 18 * PdfPageFormat.mm,
              ),
            ),
            pw.SizedBox(height: 4),
          ],
          pw.Center(
            child: pw.Text(
              'PEDIDO #${pedido.id}',
              style: pw.TextStyle(
                font: bold,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Center(child: pw.Text(fechaHora, style: pequeno)),
          pw.Divider(),
          ...lineas.expand(
            (linea) => [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${_cantidad(linea.cantidad)} x '
                      '${linea.modalidadVenta == 'COMPLETO' ? '${linea.nombre} completo' : linea.nombre}',
                      style: pequeno,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(formatMoney(linea.subtotal), style: pequeno),
                ],
              ),
              if (linea.modalidadVenta == 'COMPLETO' &&
                  (linea.nombreSopa ?? '').isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                  child: pw.Text(
                    'incluye ${linea.nombreSopa}',
                    style: pequeno,
                  ),
                ),
            ],
          ),
          pw.Divider(),
          pw.Text('Cajero: $cajero', style: negrita),
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

  Future<Uint8List> generarMovimientoTurno({
    required Caja caja,
    required CajaResumen resumen,
    required double sobrante,
    required String cajero,
  }) async {
    await _cargarFuentes();
    final regular = _regular!;
    final bold = _bold!;
    final meta = await AppDatabase.instance.leerAppMeta();
    final negocio = (meta?['nombre_negocio'] as String?) ?? 'Conwich';
    final pequeno = pw.TextStyle(font: regular, fontSize: 8);
    final negrita = pw.TextStyle(font: bold, fontSize: 8);

    pw.Widget fila(String etiqueta, String valor, {bool fuerte = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(etiqueta, style: fuerte ? negrita : pequeno),
              ),
              pw.Text(valor, style: fuerte ? negrita : pequeno),
            ],
          ),
        );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          140 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
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
              'MOVIMIENTO DE TURNO',
              style: pw.TextStyle(
                font: bold,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(),
          fila('Turno', caja.turnoLabel),
          fila('Fecha', formatDateShort(parseSqlDate(caja.fecha))),
          fila('Cajero', cajero),
          pw.Divider(),
          fila('Ventas efectivo', formatSignedMoney(resumen.ventasEfectivo)),
          fila('Ventas QR', formatSignedMoney(resumen.ventasQr)),
          fila(
            'Salidas de caja',
            '-${formatMoney(resumen.salidasEfectivo + resumen.salidasQr)}',
          ),
          fila('Sobrante del turno', formatSignedMoney(sobrante)),
          pw.Divider(),
          fila('TOTAL ESPERADO', formatMoney(resumen.totalEsperado), fuerte: true),
          fila(
            'TOTAL EN CAJA',
            formatMoney(resumen.totalEsperado + sobrante),
            fuerte: true,
          ),
          pw.Divider(),
          pw.Center(child: pw.Text('Gracias por su trabajo', style: negrita)),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> imprimirMovimientoTurno({
    required Caja caja,
    required CajaResumen resumen,
    required double sobrante,
    required String cajero,
  }) async {
    final bytes = await generarMovimientoTurno(
      caja: caja,
      resumen: resumen,
      sobrante: sobrante,
      cajero: cajero,
    );
    await Printing.layoutPdf(
      name: 'movimiento_turno_${caja.id}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  String _cantidad(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
