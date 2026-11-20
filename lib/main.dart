
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/auth_repository.dart';
import 'core/session.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/onboarding_admin_page.dart';
import 'features/shell/presentation/app_shell.dart';

void main() {
  runApp(const RestaurantApp());
}

/// Permite arrastrar el contenido con el dedo, el lápiz o el mouse.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

/// Simulación de tablet de 11 pulgadas con proporción 16:10.
class TabletLayout extends StatelessWidget {
  final Widget child;

  const TabletLayout({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const aspectRatio = 16 / 10;

        double width = constraints.maxWidth;
        double height = width / aspectRatio;

        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }

        return ColoredBox(
          color: const Color(0xFFE0E0E0),
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFC18A55);

    return MaterialApp(
      title: 'Conwich',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),

      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFF70452D),
              onPrimary: const Color(0xFFFFF9F0),
              primaryContainer: const Color(0xFFE8C995),
              onPrimaryContainer: const Color(0xFF2B1A12),
              secondary: const Color(0xFF574537),
              onSecondary: const Color(0xFFFFF9F0),
              secondaryContainer: const Color(0xFFE8C995),
              onSecondaryContainer: const Color(0xFF2B1A12),
              tertiary: const Color(0xFF3D2419),
              onTertiary: const Color(0xFFF3E9D9),
              tertiaryContainer: const Color(0xFFE8C995),
              onTertiaryContainer: const Color(0xFF2B1A12),
              error: const Color(0xFFA9442F),
              onError: const Color(0xFFFFF9F0),
              errorContainer: const Color(0xFFF3DAD3),
              onErrorContainer: const Color(0xFF3B120C),
              surface: const Color(0xFFFFF9F0),
              onSurface: const Color(0xFF2B1A12),
              onSurfaceVariant: const Color(0xFF574537),
              surfaceDim: const Color(0xFFF3E9D9),
              surfaceBright: const Color(0xFFFFF9F0),
              surfaceContainerLowest: const Color(0xFFFFF9F0),
              surfaceContainerLow: const Color(0xFFFFF9F0),
              surfaceContainer: const Color(0xFFF3E9D9),
              surfaceContainerHigh: const Color(0xFFF3E9D9),
              surfaceContainerHighest: const Color(0xFFF3E9D9),
              outline: const Color(0xFF70452D),
              outlineVariant: const Color(0xFFE8C995),
              inverseSurface: const Color(0xFF3D2419),
              onInverseSurface: const Color(0xFFF3E9D9),
              inversePrimary: const Color(0xFFC18A55),
              shadow: const Color(0xFF3D2419),
              scrim: const Color(0xFF3D2419),
              surfaceTint: const Color(0xFFC18A55),
            ),

        scaffoldBackgroundColor: const Color(0xFFFFF9F0),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3D2419),
          surfaceTintColor: Color(0xFF3D2419),
          foregroundColor: Color(0xFFF3E9D9),
          iconTheme: IconThemeData(color: Color(0xFFF3E9D9)),
        ),

        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF3D2419),
          surfaceTintColor: Color(0xFF3D2419),
        ),

        cardTheme: const CardThemeData(
          color: Color(0xFFF3E9D9),
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
        ),

        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFFFFF9F0),
          surfaceTintColor: Colors.transparent,
        ),

        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFFFFF9F0),
          surfaceTintColor: Colors.transparent,
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFF9F0),
          prefixIconColor: const Color(0xFF70452D),
          suffixIconColor: const Color(0xFF70452D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE8C995)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: seed, width: 1.6),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC18A55),
            foregroundColor: const Color(0xFF2B1A12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF70452D),
            side: const BorderSide(color: Color(0xFFE8C995)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF70452D),
          ),
        ),

        navigationRailTheme: const NavigationRailThemeData(
          labelType: NavigationRailLabelType.all,
          groupAlignment: -0.9,
          backgroundColor: Color(0xFF3D2419),
          indicatorColor: Color(0xFFC18A55),
          selectedIconTheme: IconThemeData(color: Color(0xFFF3E9D9)),
          unselectedIconTheme: IconThemeData(color: Color(0xFFE8C995)),
          selectedLabelTextStyle: TextStyle(
            color: Color(0xFFF3E9D9),
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: Color(0xFFE8C995),
            fontWeight: FontWeight.w600,
          ),
        ),

        chipTheme: const ChipThemeData(
          backgroundColor: Color(0x55E8C995),
          selectedColor: Color(0xFFE8C995),
          secondarySelectedColor: Color(0xFFC18A55),
          disabledColor: Color(0x33E8C995),
          side: BorderSide(color: Color(0xFFE8C995)),
          checkmarkColor: Color(0xFF2B1A12),
          deleteIconColor: Color(0xFF70452D),
        ),

        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF70452D),
          unselectedLabelColor: Color(0xFF574537),
          indicatorColor: Color(0xFFC18A55),
          dividerColor: Color(0xFFE8C995),
          overlayColor: WidgetStatePropertyAll(Color(0x1FC18A55)),
        ),

        dataTableTheme: const DataTableThemeData(
          headingRowColor: WidgetStatePropertyAll(Color(0xFFE8C995)),
        ),

        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF70452D),
          textColor: Color(0xFF2B1A12),
          selectedColor: Color(0xFFC18A55),
          selectedTileColor: Color(0x33E8C995),
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFC18A55);
            }
            return const Color(0xFFE8C995);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFE8C995);
            }
            return const Color(0xFFF3E9D9);
          }),
          trackOutlineColor: const WidgetStatePropertyAll(
            Color(0xFFE8C995),
          ),
        ),

        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFFC18A55),
          selectionColor: Color(0x55E8C995),
          selectionHandleColor: Color(0xFFC18A55),
        ),

        scrollbarTheme: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(Color(0x8070452D)),
        ),

        dividerTheme: const DividerThemeData(
          space: 1,
          color: Color(0xFFE8C995),
        ),
      ),

      home: const TabletLayout(
        child: StartupGate(),
      ),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  final _repository = AuthRepository();

  bool _loading = true;
  String? _error;
  Usuario? _usuario;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final usuario = await _repository.restaurarSesion().timeout(
        const Duration(seconds: 30),
      );

      if (!mounted) return;

      setState(() {
        _usuario = usuario;
        if (usuario != null) Sesion.instance.iniciar(usuario);
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _error =
            'La base de datos tardó demasiado en abrir. Cierra la app y vuelve a intentar.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo abrir la base de datos: $error';
        _loading = false;
      });
    }
  }

  Future<void> _login(Usuario usuario) async {
    Sesion.instance.iniciar(usuario);
    await _repository.guardarSesion(usuario.id);

    if (!mounted) return;

    setState(() => _usuario = usuario);
  }

  Future<void> _logout() async {
    await _repository.cerrarSesion();
    Sesion.instance.cerrar();

    if (!mounted) return;

    setState(() => _usuario = null);
  }

  Future<void> _cambiarUsuario(Usuario usuario) async {
    Sesion.instance.iniciar(usuario);
    await _repository.guardarSesion(usuario.id);

    if (!mounted) return;

    setState(() => _usuario = usuario);
  }

  void _completarPrimerAcceso(Usuario usuario) {
    Sesion.instance.iniciar(usuario);
    setState(() => _usuario = usuario);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_usuario != null) {
      final usuario = _usuario!;

      if (usuario.debeCambiarPassword) {
        return OnboardingAdminPage(
          usuario: usuario,
          onCompletado: _completarPrimerAcceso,
          onLogout: _logout,
        );
      }

      return AppShell(
        usuario: usuario,
        onLogout: _logout,
        onUsuarioCambiado: _cambiarUsuario,
      );
    }

    return LoginPage(onLogin: _login);
  }
}
