import 'package:flutter/material.dart';

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
  const AppShell({super.key, required this.usuario, required this.onLogout});

  final Usuario usuario;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _refreshToken = 0;

  void _seleccionar(int index) {
    setState(() {
      _index = index;
      _refreshToken++;
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
    final restaurado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BackupPage()),
    );
    if (restaurado == true && mounted) {
      // La base cambió por completo: se cierra la sesión para que el usuario
      // entre con las credenciales del archivo restaurado.
      widget.onLogout();
    }
  }

  List<_Destination> _destinations() {
    final usuario = widget.usuario;
    final token = _refreshToken;
    final destinations = <_Destination>[];
    if (usuario.puede(Permiso.tablero)) {
      destinations.add(
        _Destination(
          label: 'Tablero',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard,
          page: DashboardPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.ventas)) {
      destinations.add(
        _Destination(
          label: 'Ventas',
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          page: SalesPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.caja)) {
      destinations.add(
        _Destination(
          label: 'Caja',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          page: CashPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.menu)) {
      destinations.add(
        _Destination(
          label: 'Menú del día',
          icon: Icons.restaurant_menu_outlined,
          selectedIcon: Icons.restaurant_menu,
          page: MenuPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.productos)) {
      destinations.add(
        _Destination(
          label: 'Productos',
          icon: Icons.lunch_dining_outlined,
          selectedIcon: Icons.lunch_dining,
          page: ProductsPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.insumos)) {
      destinations.add(
        _Destination(
          label: 'Insumos',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          page: InventoryPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.usuarios)) {
      destinations.add(
        _Destination(
          label: 'Usuarios',
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts,
          page: UsersPage(usuario: usuario, refreshToken: token),
        ),
      );
    }
    if (usuario.puede(Permiso.reportes)) {
      destinations.add(
        _Destination(
          label: 'Reportes',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          page: ReportsPage(refreshToken: token),
        ),
      );
    }
    return destinations;
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
          children: destinations.map((item) => item.page).toList(),
        );
        final userMenu = PopupMenuButton<String>(
          tooltip: 'Sesión',
          onSelected: (value) {
            if (value == 'password') _cambiarPassword();
            if (value == 'backup') _abrirRespaldo();
            if (value == 'logout') widget.onLogout();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'password',
              child: Text('Cambiar mi contraseña'),
            ),
            if (widget.usuario.esAdmin)
              const PopupMenuItem(
                value: 'backup',
                child: Text('Respaldo y restauración'),
              ),
            const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                  child: Text(
                    widget.usuario.inicial,
                    style: TextStyle(
                      color: scheme.primary,
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
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.usuario.esAdmin ? 'Administrador' : 'Cajero',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: Row(
              children: [
                if (!wide) ...[
                  Icon(Icons.restaurant_menu, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  'Sazón',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 10),
                  Text(
                    '· ${current.label}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
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
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(
                            'Sazón',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        for (var i = 0; i < destinations.length; i++)
                          ListTile(
                            leading: Icon(
                              i == index
                                  ? destinations[i].selectedIcon
                                  : destinations[i].icon,
                            ),
                            title: Text(destinations[i].label),
                            selected: i == index,
                            onTap: () {
                              _seleccionar(i);
                              Navigator.pop(context);
                            },
                          ),
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
                      selectedIndex: index,
                      onDestinationSelected: (value) =>
                          _seleccionar(value),
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
                              child: const Icon(
                                Icons.restaurant,
                                color: Colors.white,
                              ),
                            ),
                            if (extended) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Sazón',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
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
