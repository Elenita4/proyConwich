import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_code_02/core/printer/printer_service.dart';
import 'package:test_code_02/core/sales_repository.dart';

void main() {
  testWidgets('el logo de las fichas está en los assets', (tester) async {
    final data = await rootBundle.load('assets/images/logo_ticket.png');
    expect(data.lengthInBytes, greaterThan(0));
  });

  test('la venta se imprime en dos fichas: cliente, corte, vendedor, corte', () {
    final detalle = PedidoDetalle(
      pedido: const Pedido(
        id: 7,
        estadoPago: 'PAGADO',
        estadoEntrega: 'ENTREGADO',
        total: 30,
        pagado: 30,
        fecha: '2026-11-20 14:35:00',
        usuarioNombre: 'María',
        cajaId: 1,
      ),
      lineas: const [
        PedidoLinea(
          id: 1,
          productoId: 10,
          nombre: 'Pollo',
          cantidad: 2,
          precioUnitario: 12.5,
          subtotal: 25,
          modalidadVenta: 'COMPLETO',
          nombreSopa: 'Sopa de maní',
        ),
        PedidoLinea(
          id: 2,
          productoId: 11,
          nombre: 'Coca Cola',
          cantidad: 1,
          precioUnitario: 5,
          subtotal: 5,
        ),
      ],
      pagos: const [],
    );

    final bytes = PrinterService().construirBytesNotaVenta(
      detalle: detalle,
      cajero: 'María',
    );
    final texto = latin1.decode(bytes, allowInvalid: true);
    final cortes = _indicesDe(bytes, const [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x01]);

    // Dos cortes: uno tras la ficha del cliente y otro al final.
    expect(cortes.length, 2);
    expect(bytes.sublist(bytes.length - 6), [
      0x1B,
      0x64,
      0x03,
      0x1D,
      0x56,
      0x01,
    ]);

    // El pedido aparece en las dos fichas.
    expect('PEDIDO #7'.allMatches(texto).length, 2);
    expect(texto.contains('Fecha: 20/11/2026'), isTrue);
    expect(texto.contains('Hora: 14:35'), isTrue);

    // La segunda ficha (vendedor) empieza después del primer corte.
    final segundoPedido = texto.indexOf('PEDIDO #7', cortes.first + 6);
    expect(segundoPedido, greaterThan(cortes.first));
    expect(texto.indexOf('Cajero: María'), greaterThan(cortes.first));
    expect(texto.indexOf('incluye Sopa de maní'), greaterThan(cortes.first));

    // Sin total, sin turno y sin despedida.
    expect(texto.contains('Bs 25.00'), isTrue);
    expect(texto.contains('TOTAL'), isFalse);
    expect(texto.contains('Turno'), isFalse);
    expect(texto.contains('Gracias'), isFalse);
    expect(texto.contains('NOTA DE VENTA'), isFalse);
  });
}

List<int> _indicesDe(List<int> datos, List<int> secuencia) {
  final indices = <int>[];
  for (var i = 0; i <= datos.length - secuencia.length; i++) {
    var coincide = true;
    for (var j = 0; j < secuencia.length; j++) {
      if (datos[i + j] != secuencia[j]) {
        coincide = false;
        break;
      }
    }
    if (coincide) indices.add(i);
  }
  return indices;
}
