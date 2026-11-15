import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/backup/drive_backup_service.dart';
import '../../../core/auth_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';
import '../../backup/presentation/backup_page.dart';
import '../../cash/presentation/cash_page.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../inventory/presentation/inventory_page.dart';
import '../../menu/presentation/menu_page.dart';
import '../../products/presentation/products_page.dart';
import '../../reports/presentation/reports_page.dart';
import '../../sales/presentation/sales_page.dart';
import '../../users/presentation/users_page.dart';

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.usuario,
    required this.onLogout,
    required this.onUsuarioCambiado,
  });

  final Usuario usuario;
  final VoidCallback onLogout;
  final ValueChanged<Usuario> onUsuarioCambiado;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final Set<int> _visitados = <int>{0};
  final Map<String, int> _tokens = <String, int>{};
  int _generacion = 0;
  bool _flujoInicio = false;

  int _token(String label) => (_tokens[label] ?? 0) + _generacion;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>(() async {
        // Se deja pasar la primera carga de la pantalla antes de intentar el
        // respaldo automático: copiar el archivo cierra la base unos instantes
        // y no debe competir con el inicio de sesión.
        await Future<void>.delayed(const Duration(seconds: 10));
        if (!mounted) return;
        try {
          await DriveBackupService().respaldarSiCorresponde(motivo: 'inicio');
        } catch (_) {
          // El error queda registrado en app_meta por el propio servicio.
        }
      }),
    );
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usuario.id != widget.usuario.id) {
      _index = 0;
      _visitados
        ..clear()
        ..add(0);
      _tokens.clear();
      // Fuerza una recarga de la primera pantalla aunque su token fuera 0.
      _generacion++;
    }
  }

  void _seleccionar(int index) {
    final destinations = _destinations();
    if (index < 0 || index >= destinations.length) return;
    final label = destinations[index].label;
    setState(() {
      _index = index;
      _visitados.add(index);
      _tokens[label] = (_tokens[label] ?? 0) + 1;
    });
  }

  Future<void> _cambiarPassword() async {
    final cambiada = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(usuario: widget.usuario),
    );
    if (cambiada == true && mounted) {
      showAppMessage(context, 'Contraseña actualizada.');
    }
  }

  Future<void> _abrirRespaldo() async {
    final restaurado = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const BackupPage()));
    if (restaurado == true && mounted) {
      // La base cambió por completo: se cierra la sesión para que el usuario
      // entre con las credenciales del archivo restaurado.
      widget.onLogout();
    }
  }

  Future<void> _verComoAdministrador() async {
    final admin = await showDialog<Usuario>(
      context: context,
      builder: (_) => const _AdminPasswordDialog(),
    );
    if (admin != null && mounted) {
      widget.onUsuarioCambiado(admin);
    }
  }

  Future<void> _cambiarUsuario() async {
    final usuario = await showDialog<Usuario>(
      context: context,
      builder: (_) => _CambiarUsuarioDialog(actual: widget.usuario),
    );
    if (usuario != null && mounted) {
      widget.onUsuarioCambiado(usuario);
    }
  }

  void _irACaja() {
    final destinations = _destinations();
    final index = destinations.indexWhere((item) => item.label == 'Caja');
    if (index >= 0) _seleccionar(index);
  }

  /// Flujo "Empezar el día": va al menú y activa el atajo hacia Caja.
  void _empezarDia() {
    setState(() => _flujoInicio = true);
    final destinations = _destinations();
    final index = destinations.indexWhere(
      (item) => item.label == 'Menú del día',
    );
    if (index >= 0) _seleccionar(index);
  }

  void _finalizarAtajo() {
    setState(() => _flujoInicio = false);
  }

  List<_Destination> _destinations() {
    final usuario = widget.usuario;
    final destinations = <_Destination>[];
    if (usuario.puede(Permiso.tablero)) {
      destinations.add(
        _Destination(
          label: 'Tablero',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard,
          page: DashboardPage(
            usuario: usuario,
            refreshToken: _token('Tablero'),
            onEmpezarDia: usuario.puede(Permiso.menu) ? _empezarDia : null,
          ),
        ),
      );
    }
    if (usuario.puede(Permiso.ventas)) {
      destinations.add(
        _Destination(
          label: 'Ventas',
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          page: SalesPage(
            usuario: usuario,
            refreshToken: _token('Ventas'),
            onAbrirCaja: usuario.puede(Permiso.caja) ? _irACaja : null,
          ),
        ),
      );
    }
    if (usuario.puede(Permiso.caja)) {
      destinations.add(
        _Destination(
          label: 'Caja',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          page: CashPage(usuario: usuario, refreshToken: _token('Caja')),
        ),
      );
    }
    if (usuario.puede(Permiso.menu)) {
      destinations.add(
        _Destination(
          label: 'Menú del día',
          icon: Icons.restaurant_menu_outlined,
          selectedIcon: Icons.restaurant_menu,
          page: MenuPage(
            usuario: usuario,
            refreshToken: _token('Menú del día'),
            onAbrirCaja: usuario.puede(Permiso.caja) ? _irACaja : null,
            flujoInicioActivo: _flujoInicio,
            onFinalizarAtajo: _finalizarAtajo,
          ),
        ),
      );
    }
    if (usuario.puede(Permiso.productos)) {
      destinations.add(
        _Destination(
          label: 'Productos',
          icon: Icons.lunch_dining_outlined,
          selectedIcon: Icons.lunch_dining,
          page: ProductsPage(
            usuario: usuario,
            refreshToken: _token('Productos'),
          ),
        ),
      );
    }
    if (usuario.puede(Permiso.insumos)) {
      destinations.add(
        _Destination(
          label: 'Insumos',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          page: InventoryPage(
            usuario: usuario,
            refreshToken: _token('Insumos'),
          ),
        ),
      );
    }
    if (usuario.puede(Permiso.usuarios)) {
      destinations.add(
        _Destination(
          label: 'Usuarios',
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts,
          page: UsersPage(usuario: usuario, refreshToken: _token('Usuarios')),
        ),
      );
    }
    if (usuario.puede(Permiso.reportes) ||
        (usuario.perfil == Perfil.cajero && usuario.puede(Permiso.ventas))) {
      destinations.add(
        _Destination(
          label: 'Reportes',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          page: ReportsPage(usuario: usuario, refreshToken: _token('Reportes')),
        ),
      );
    }
    return destinations;
  }

  /// Accesos de sesión siempre visibles al pie del drawer. Antes quedaban
  /// debajo de todas las secciones y en un teléfono no se veían sin desplazar.
  Widget _drawerSesion(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const dorado = Color(0xFFE8C995);
    const crema = Color(0xFFF3E9D9);

    void cerrarY(VoidCallback accion) {
      Navigator.pop(context);
      accion();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                widget.usuario.inicial,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: Text(
              widget.usuario.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: crema, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              widget.usuario.esAdmin ? 'Administrador' : 'Cajero',
              style: const TextStyle(color: dorado),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Cambiar mi contraseña'),
            iconColor: dorado,
            textColor: crema,
            onTap: () => cerrarY(_cambiarPassword),
          ),
          if (!widget.usuario.esAdmin)
            ListTile(
              dense: true,
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Ver como administrador'),
              iconColor: dorado,
              textColor: crema,
              onTap: () => cerrarY(_verComoAdministrador),
            )
          else
            ListTile(
              dense: true,
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('Cambiar de usuario'),
              iconColor: dorado,
              textColor: crema,
              onTap: () => cerrarY(_cambiarUsuario),
            ),
          if (widget.usuario.esAdmin)
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Respaldo y restauración'),
              iconColor: dorado,
              textColor: crema,
              onTap: () => cerrarY(_abrirRespaldo),
            ),
          ListTile(
            dense: true,
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              widget.onLogout();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations();
    final index = _index.clamp(0, destinations.length - 1);
    final current = destinations[index];
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final extended = constraints.maxWidth >= 1200;
        final muyAngosto = constraints.maxWidth < 560;
        final body = IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < destinations.length; i++)
              // Solo se construye la pantalla cuando se visita por primera vez.
              // Antes se inicializaban todas (y todas consultaban la base) al
              // entrar al sistema, lo que hacía lento el inicio de sesión.
              if (i == index || _visitados.contains(i))
                destinations[i].page
              else
                const SizedBox.shrink(),
          ],
        );
        final userMenu = PopupMenuButton<String>(
          tooltip: 'Sesión',
          onSelected: (value) {
            if (value == 'password') _cambiarPassword();
            if (value == 'backup') _abrirRespaldo();
            if (value == 'ver_admin') _verComoAdministrador();
            if (value == 'cambiar_usuario') _cambiarUsuario();
            if (value == 'logout') widget.onLogout();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'password',
              child: Text('Cambiar mi contraseña'),
            ),
            if (!widget.usuario.esAdmin)
              const PopupMenuItem(
                value: 'ver_admin',
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_outlined),
                    SizedBox(width: 10),
                    Text('Ver como administrador'),
                  ],
                ),
              ),
            if (widget.usuario.esAdmin)
              const PopupMenuItem(
                value: 'cambiar_usuario',
                child: Row(
                  children: [
                    Icon(Icons.switch_account_outlined),
                    SizedBox(width: 10),
                    Text('Cambiar de usuario'),
                  ],
                ),
              ),
            if (widget.usuario.esAdmin)
              const PopupMenuItem(
                value: 'backup',
                child: Text('Respaldo y restauración'),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Cerrar sesión',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    widget.usuario.inicial,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!muyAngosto)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.usuario.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFF3E9D9), // Crema
                              ),
                        ),
                        Text(
                          widget.usuario.esAdmin ? 'Administrador' : 'Cajero',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFE8C995)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF3D2419), // Espresso
            surfaceTintColor: const Color(0xFF3D2419),
            title: Row(
              children: [
                if (!wide) ...[
                  Icon(Icons.restaurant_menu, color: scheme.primaryContainer),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    appNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFF3E9D9), // Crema
                    ),
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '· ${current.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFE8C995), // Dorado
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [userMenu, const SizedBox(width: 8)],
          ),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appNombre,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFF3E9D9), // Crema
                                    ),
                              ),
                              Text(
                                appCanal,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFE8C995), // Dorado
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              for (var i = 0; i < destinations.length; i++)
                                ListTile(
                                  leading: Icon(
                                    i == index
                                        ? destinations[i].selectedIcon
                                        : destinations[i].icon,
                                  ),
                                  title: Text(destinations[i].label),
                                  selected: i == index,
                                  iconColor: const Color(0xFFE8C995), // Dorado
                                  textColor: const Color(0xFFF3E9D9), // Crema
                                  selectedColor: const Color(0xFFE8C995),
                                  onTap: () {
                                    _seleccionar(i);
                                    Navigator.pop(context);
                                  },
                                ),
                            ],
                          ),
                        ),
                        const Divider(),
                        _drawerSesion(context),
                      ],
                    ),
                  ),
                ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      extended: extended,
                      minExtendedWidth: 210,
                      minWidth: 92,
                      selectedIndex: index,
                      onDestinationSelected: (value) => _seleccionar(value),
                      leading: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.restaurant,
                                color: scheme.onPrimary, // Blanco cálido
                              ),
                            ),
                            if (extended) ...[
                              const SizedBox(height: 8),
                              Text(
                                appNombre,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFF3E9D9), // Crema
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      destinations: destinations
                          .map(
                            (item) => NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.selectedIcon),
                              label: Text(item.label),
                            ),
                          )
                          .toList(),
                      // Accesos de sesión al pie del rail, visibles también en
                      // tablet (donde no hay drawer).
                      trailing: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (extended) ...[
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 190,
                                ),
                                child: Text(
                                  widget.usuario.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFF3E9D9),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                widget.usuario.esAdmin
                                    ? 'Administrador'
                                    : 'Cajero',
                                style: const TextStyle(
                                  color: Color(0xFFE8C995),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            IconButton(
                              tooltip: widget.usuario.esAdmin
                                  ? 'Cambiar de usuario'
                                  : 'Ver como administrador',
                              onPressed: widget.usuario.esAdmin
                                  ? _cambiarUsuario
                                  : _verComoAdministrador,
                              icon: Icon(
                                widget.usuario.esAdmin
                                    ? Icons.switch_account_outlined
                                    : Icons.admin_panel_settings_outlined,
                              ),
                              color: const Color(0xFFE8C995),
                            ),
                            IconButton(
                              tooltip: 'Cambiar mi contraseña',
                              onPressed: _cambiarPassword,
                              icon: const Icon(Icons.lock_reset_outlined),
                              color: const Color(0xFFE8C995),
                            ),
                            if (widget.usuario.esAdmin)
                              IconButton(
                                tooltip: 'Respaldo y restauración',
                                onPressed: _abrirRespaldo,
                                icon: const Icon(Icons.cloud_sync_outlined),
                                color: const Color(0xFFE8C995),
                              ),
                            IconButton(
                              tooltip: 'Cerrar sesión',
                              onPressed: widget.onLogout,
                              icon: const Icon(Icons.logout),
                              color: scheme.error,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      },
    );
  }
}

class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog();

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final _repository = AuthRepository();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Ingresa la contraseña de un administrador.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admin = await _repository.loginAdminPorPassword(_password.text);
      if (!mounted) return;
      if (admin == null) {
        setState(() {
          _error = 'Contraseña incorrecta o el usuario no es administrador.';
          _loading = false;
        });
        return;
      }
      Navigator.pop(context, admin);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo validar: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Ver como administrador'),
      content: DialogSurface(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ingresa la contraseña de cualquier administrador activo.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => _ingresar(),
              decoration: appInput(
                label: 'Contraseña de administrador',
                icon: Icons.lock_outline,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _ingresar,
          child: Text(_loading ? 'Validando…' : 'Entrar como admin'),
        ),
      ],
    );
  }
}

class _CambiarUsuarioDialog extends StatefulWidget {
  const _CambiarUsuarioDialog({required this.actual});

  final Usuario actual;

  @override
  State<_CambiarUsuarioDialog> createState() => _CambiarUsuarioDialogState();
}

class _CambiarUsuarioDialogState extends State<_CambiarUsuarioDialog> {
  final _repository = AuthRepository();
  late Future<List<Usuario>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getUsuarios();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Cambiar de usuario'),
      content: DialogSurface(
        maxWidth: 420,
        maxHeightFactor: 0.7,
        child: FutureBuilder<List<Usuario>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView();
            }
            if (snapshot.hasError) {
              return ErrorView(message: '${snapshot.error}');
            }
            final usuarios = (snapshot.data ?? [])
                .where(
                  (usuario) => usuario.activo && usuario.id != widget.actual.id,
                )
                .toList();
            if (usuarios.isEmpty) {
              return const EmptyState(
                icon: Icons.people_outline,
                title: 'No hay otros usuarios activos',
                message: 'Crea usuarios en la sección Usuarios.',
              );
            }
            return ListView.separated(
              itemCount: usuarios.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final usuario = usuarios[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(usuario.inicial)),
                  title: Text(usuario.nombre),
                  subtitle: Text(
                    '@${usuario.usuario} · ${usuario.nombrePerfil}',
                  ),
                  trailing: usuario.esAdmin
                      ? const Icon(Icons.admin_panel_settings_outlined)
                      : null,
                  onTap: () => Navigator.pop(context, usuario),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.usuario});

  final Usuario usuario;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AuthRepository();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final correcta = await _repository.verificarPassword(
        widget.usuario.id,
        _actual.text,
      );
      if (!correcta) {
        if (!mounted) return;
        setState(() {
          _error = 'La contraseña actual no es correcta.';
          _saving = false;
        });
        return;
      }
      await _repository.cambiarPassword(widget.usuario.id, _nueva.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cambiar la contraseña: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Cambiar mi contraseña'),
      content: DialogSurface(
        maxWidth: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _actual,
                obscureText: true,
                decoration: appInput(
                  label: 'Contraseña actual',
                  icon: Icons.lock_outline,
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Ingresa tu contraseña actual'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nueva,
                obscureText: true,
                decoration: appInput(
                  label: 'Nueva contraseña',
                  icon: Icons.lock_reset_outlined,
                ),
                validator: (value) => (value == null || value.length < 8)
                    ? 'Usa al menos 8 caracteres'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmar,
                obscureText: true,
                onFieldSubmitted: (_) => _guardar(),
                decoration: appInput(
                  label: 'Confirmar nueva contraseña',
                  icon: Icons.lock_reset_outlined,
                ),
                validator: (value) => value != _nueva.text
                    ? 'Las contraseñas no coinciden'
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _guardar,
          child: Text(_saving ? 'Guardando…' : 'Cambiar'),
        ),
      ],
    );
  }
}
