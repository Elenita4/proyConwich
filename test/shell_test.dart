import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';
import 'package:test_code_02/features/shell/presentation/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Usuario admin;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
    admin = (await AuthRepository().login('admin', '1234'))!;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('AppShell móvil muestra sesión fija y no desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          usuario: admin,
          onLogout: () {},
          onUsuarioCambiado: (_) {},
        ),
      ),
    );
    await asentar(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('Cambiar mi contraseña'), findsOneWidget);
    expect(find.text('Cambiar de usuario'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await cerrar(tester);
  });

  testWidgets('AppShell tablet muestra etiquetas y sesión en el rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          usuario: admin,
          onLogout: () {},
          onUsuarioCambiado: (_) {},
        ),
      ),
    );
    await asentar(tester);
    expect(tester.takeException(), isNull);

    final rail = find.byType(NavigationRail);
    expect(
      find.descendant(of: rail, matching: find.text('Ventas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Reportes')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.byIcon(Icons.lock_reset_outlined), findsOneWidget);

    await cerrar(tester);
  });
}
