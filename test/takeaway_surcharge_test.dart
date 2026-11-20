import 'package:flutter_test/flutter_test.dart';

import 'package:test_code_02/core/sales_repository.dart';

void main() {
  const lineas = [
    CartLine(
      productoId: 1,
      nombre: 'Té',
      precio: 5,
      cantidad: 2,
      aplicaRecargoParaLlevar: true,
    ),
    CartLine(
      productoId: 2,
      nombre: 'Jugo',
      precio: 3,
      cantidad: 1,
      aplicaRecargoParaLlevar: true,
    ),
    CartLine(productoId: 3, nombre: 'Sándwich', precio: 4, cantidad: 1),
  ];

  test('aplica el recargo una sola vez por pedido', () {
    expect(calcularTotalPedido(lineas, paraLlevar: true), 17.5);
    expect(calcularTotalPedido(lineas, paraLlevar: false), 17);
  });

  test('solo guarda el recargo en una línea elegible', () {
    final actualizadas = lineasConRecargoParaLlevar(lineas, paraLlevar: true);

    expect(actualizadas[0].subtotal, 10.5);
    expect(actualizadas[0].nombre, 'Té (Para llevar)');
    expect(actualizadas[1].subtotal, 3);
    expect(actualizadas[2].subtotal, 4);
  });

  test('no agrega recargo si el pedido no tiene productos aplicables', () {
    const linea = CartLine(
      productoId: 1,
      nombre: 'Sándwich',
      precio: 4,
      cantidad: 1,
    );

    expect(calcularTotalPedido([linea], paraLlevar: true), 4);
    expect(
      lineasConRecargoParaLlevar([linea], paraLlevar: true).single.subtotal,
      4,
    );
  });
}
