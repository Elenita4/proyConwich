import 'package:flutter/material.dart';

import '../../../core/auth_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class FirstRunPage extends StatefulWidget {
  const FirstRunPage({super.key, required this.onCreated});

  final ValueChanged<Usuario> onCreated;

  @override
  State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _repository = AuthRepository();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final usuario = await _repository.crearAdminInicial(
        nombre: _nombre.text,
        usuario: _usuario.text,
        password: _password.text,
      );
      Sesion.instance.iniciar(usuario);
      if (!mounted) return;
      widget.onCreated(usuario);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo crear el administrador: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.12),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: AppCard(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Configuración inicial',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'Crea el primer usuario administrador.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nombre,
                          textInputAction: TextInputAction.next,
                          decoration: appInput(
                            label: 'Nombre completo',
                            icon: Icons.badge_outlined,
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Ingresa el nombre'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usuario,
                          textInputAction: TextInputAction.next,
                          decoration: appInput(
                            label: 'Usuario',
                            hint: 'Sin espacios',
                            icon: Icons.person_outline,
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Ingresa un usuario';
                            if (text.contains(' ')) {
                              return 'El usuario no debe tener espacios';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          decoration: appInput(
                            label: 'Contraseña',
                            icon: Icons.lock_outline,
                          ),
                          validator: (value) => (value == null ||
                                  value.length < 4)
                              ? 'Usa al menos 4 caracteres'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          onFieldSubmitted: (_) => _crear(),
                          decoration: appInput(
                            label: 'Repetir contraseña',
                            icon: Icons.lock_reset_outlined,
                          ),
                          validator: (value) => value != _password.text
                              ? 'Las contraseñas no coinciden'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _loading ? null : _crear,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            _loading ? 'Creando…' : 'Crear administrador',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
