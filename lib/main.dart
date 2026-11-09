import 'dart:async';

import 'package:flutter/material.dart';

import 'core/auth_repository.dart';
import 'core/session.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/shell/presentation/app_shell.dart';

void main() {
  runApp(const RestaurantApp());
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: 'Sazón',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        cardTheme: const CardThemeData(
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFE2E8E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: seed, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          labelType: NavigationRailLabelType.none,
          groupAlignment: -0.9,
        ),
        dividerTheme: const DividerThemeData(space: 1),
      ),
      home: const StartupGate(),
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
      final usuario = await _repository
          .restaurarSesion()
          .timeout(const Duration(seconds: 30));
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
      return AppShell(usuario: _usuario!, onLogout: _logout);
    }
    return LoginPage(onLogin: _login);
  }
}
