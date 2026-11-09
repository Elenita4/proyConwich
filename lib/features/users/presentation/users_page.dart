import 'package:flutter/material.dart';

import '../../../core/auth_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _repository = AuthRepository();
  late Future<List<Usuario>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _repository.getUsuarios();
  }

  Future<void> _openForm([Usuario? usuario]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserDialog(
        repository: _repository,
        usuario: usuario,
        esUsuarioActual: usuario?.id == widget.usuario.id,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Usuario guardado.');
    }
  }

  Future<void> _toggle(Usuario usuario, bool activo) async {
    if (usuario.id == widget.usuario.id && !activo) {
      showAppMessage(
        context,
        'No puedes desactivar tu propio usuario.',
        error: true,
      );
      return;
    }
    if (usuario.esAdmin && !activo) {
      showAppMessage(
        context,
        'El administrador no se puede desactivar.',
        error: true,
      );
      return;
    }
    await _repository.setActivo(usuario.id, activo);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Usuario>>(
      future: _future,
      builder: (context, snapshot) {
        final usuarios = snapshot.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Usuarios',
                subtitle:
                    'Crea usuarios, cámbiales la contraseña y decide qué vistas ven. Nunca se eliminan.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _openForm() : null,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Nuevo usuario'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (usuarios.isEmpty)
                const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No hay usuarios',
                  message: 'Crea el primer usuario del restaurante.',
                )
              else
                ...usuarios.map(
                  (usuario) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            child: Text(usuario.inicial),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        usuario.nombre,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    if (usuario.id == widget.usuario.id) ...[
                                      const SizedBox(width: 8),
                                      const Chip(
                                        label: Text('Tú'),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '@${usuario.usuario} · ${usuario.nombrePerfil}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              usuario.esAdmin
                                  ? 'Administrador · todas las vistas'
                                  : '${usuario.permisos.length} vista(s)',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),                          Chip(
                            label: Text(usuario.activo ? 'Activo' : 'Inactivo'),
                            side: BorderSide.none,
                            backgroundColor: usuario.activo
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            visualDensity: VisualDensity.compact,
                          ),
                          Switch(
                            value: usuario.activo,
                            onChanged: (value) => _toggle(usuario, value),
                          ),
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => _openForm(usuario),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({
    required this.repository,
    this.usuario,
    required this.esUsuarioActual,
  });

  final AuthRepository repository;
  final Usuario? usuario;
  final bool esUsuarioActual;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _usuario;
  final _password = TextEditingController();
  late bool _activo;
  late String _perfil;
  late Set<String> _permisos;
  bool _saving = false;
  String? _error;

  bool get _esAdmin => _perfil == Perfil.admin;

  @override
  void initState() {
    super.initState();
    final usuario = widget.usuario;
    _nombre = TextEditingController(text: usuario?.nombre ?? '');
    _usuario = TextEditingController(text: usuario?.usuario ?? '');
    _activo = usuario?.activo ?? true;
    _perfil = usuario?.perfil ?? Perfil.cajero;
    _permisos = usuario?.permisos.toSet() ??
        Set<String>.of(Perfil.vistasPorDefecto[_perfil] ?? {});
  }

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  void _cambiarPerfil(String perfil) {
    setState(() {
      _perfil = perfil;
      _permisos = Set<String>.of(
        Perfil.vistasPorDefecto[perfil] ?? <String>{},
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_activo && widget.esUsuarioActual) {
      setState(() => _error = 'No puedes desactivar tu propio usuario.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveUsuario(
        id: widget.usuario?.id,
        nombre: _nombre.text,
        usuario: _usuario.text,
        perfil: _perfil,
        activo: _activo,
        permisos: _permisos,
        password: _password.text.isEmpty ? null : _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.usuario == null ? 'Nuevo usuario' : 'Editar usuario',
      ),
      content: SizedBox(
        width: 600,
        height: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nombre,
                        decoration: appInput(label: 'Nombre completo'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Ingresa el nombre'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _usuario,
                        decoration: appInput(label: 'Usuario de acceso'),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return 'Ingresa un usuario';
                          if (text.contains(' ')) return 'Sin espacios';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _perfil,
                  decoration: appInput(label: 'Rol'),
                  items: Perfil.todos
                      .map(
                        (perfil) => DropdownMenuItem(
                          value: perfil,
                          child: Text(Perfil.nombres[perfil] ?? perfil),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _cambiarPerfil(value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: appInput(
                    label: widget.usuario == null
                        ? 'Contraseña'
                        : 'Nueva contraseña (opcional)',
                    icon: Icons.lock_outline,
                  ),
                  validator: (value) {
                    if (widget.usuario == null) {
                      if (value == null || value.length < 4) {
                        return 'Usa al menos 4 caracteres';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usuario activo'),
                  subtitle: const Text(
                    'Los usuarios inactivos no pueden iniciar sesión.',
                  ),
                  value: _activo,
                  onChanged: _esAdmin
                      ? null
                      : (value) => setState(() => _activo = value),
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Text(
                      'Vistas y permisos',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_esAdmin)
                      const Chip(
                        label: Text('El administrador tiene todas'),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _permisos = Set<String>.of(
                            Perfil.vistasPorDefecto[_perfil] ?? <String>{},
                          );
                        }),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Aplicar vistas del rol'),
                      ),
                  ],
                ),                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: Permiso.todos
                      .map(
                        (permiso) => SizedBox(
                          width: 260,
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(Permiso.etiquetas[permiso] ?? permiso),
                            value: _esAdmin || _permisos.contains(permiso),
                            onChanged: _esAdmin
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        _permisos.add(permiso);
                                      } else {
                                        _permisos.remove(permiso);
                                      }
                                    });
                                  },
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
