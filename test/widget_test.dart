import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/date_utils.dart';
import 'package:test_code_02/features/auth/presentation/login_page.dart';
import 'package:test_code_02/ui/common.dart';

void main() {
  test('password hash is deterministic SHA-256', () {
    expect(
      hashPassword('1234'),
      '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
    );
  });

  test('money and date helpers use local formats', () {
    expect(parseAmount('12,50'), 12.5);
    expect(parseAmount(' 8 '), 8);
    expect(parseAmount('1/4'), 0.25);
    expect(formatMoney(12.5), 'Bs 12.50');
    expect(formatSignedMoney(0), '+Bs 0.00');
    expect(formatSignedMoney(11), '+Bs 11.00');
    expect(formatSignedMoney(-11), '-Bs 11.00');
    expect(sqlDate(DateTime(2026, 11, 8)), '2026-11-08');
    expect(sqlDateTime(DateTime(2026, 11, 8, 9, 5, 3)), '2026-11-08 09:05:03');
    expect(parseSqlDate('2026-11-08'), DateTime(2026, 11, 8));
    expect(formatQty(2), '2');
    expect(formatQty(2.5), '2.50');
    expect(formatQty(0.125), '0.125');
  });

  test('amount validation accepts decimal separators and checks bounds', () {
    expect(validateDecimalAmount('12,50', allowZero: false), isNull);
    expect(validateDecimalAmount('12.50', allowZero: false), isNull);
    expect(validateDecimalAmount('0', allowZero: false), isNotNull);
    expect(validateDecimalAmount('-1,25'), isNotNull);
    expect(validateDecimalAmount('texto'), isNotNull);
    expect(validateDecimalAmount('0'), isNull);
  });

  test('amount validation accepts decimals and rejects invalid ranges', () {
    expect(validateDecimalAmount('12,50', allowZero: false), isNull);
    expect(validateDecimalAmount('12.50', allowZero: false), isNull);
    expect(validateDecimalAmount('0', allowZero: false), isNotNull);
    expect(validateDecimalAmount('-1,25'), isNotNull);
    expect(validateDecimalAmount('abc'), isNotNull);
    expect(validateDecimalAmount('0'), isNull);
  });

  testWidgets('login validates empty fields without touching the database', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: LoginPage(onLogin: (_) {})));
    expect(find.text('Conwich'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Ingresa tu usuario'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });
}
