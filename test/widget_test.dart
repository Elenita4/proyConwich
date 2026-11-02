import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_code_02/main.dart';

void main() {
  testWidgets('admin can sign in and see the dashboard', (tester) async {
    await tester.pumpWidget(const RestaurantApp());

    expect(find.text('Bienvenido'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Buenos días, administrador'), findsOneWidget);
    expect(find.text('Ventas del día'), findsOneWidget);
  });

  testWidgets('invalid credentials stay on the login screen', (tester) async {
    await tester.pumpWidget(const RestaurantApp());
    await tester.enterText(find.byType(TextField).at(0), 'cajero');
    await tester.enterText(find.byType(TextField).at(1), 'incorrecta');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
  });
}
