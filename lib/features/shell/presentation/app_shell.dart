import 'package:flutter/material.dart';

import '../../../core/session.dart';
import '../../cash/presentation/cash_page.dart';
import '../../categories/presentation/categories_page.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../expenses/presentation/expenses_page.dart';
import '../../inventory/presentation/count_page.dart';
import '../../inventory/presentation/inventory_page.dart';
import '../../menu/presentation/menu_page.dart';
import '../../products/presentation/products_page.dart';
import '../../purchases/presentation/purchases_page.dart';
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

  List<_Destination> _destinations() {
    final usuario = widget.usuario;
    final destinations = <_Destination>[
      _Destination(
        label: 'Tablero',
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard,
        page: DashboardPage(usuario: usuario),
      ),
    ];
    if (usuario.puede(Permiso.ventas)) {
      destinations.add(
        _Destination(
          label: 'Ventas',
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          page: SalesPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.caja)) {
      destinations.add(
        _Destination(
          label: 'Caja',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          page: CashPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.menu) || usuario.puede(Permiso.agotamiento)) {
      destinations.add(
        _Destination(
          label: 'Menú del día',
          icon: Icons.restaurant_menu_outlined,
          selectedIcon: Icons.restaurant_menu,
          page: MenuPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.productos)) {
      destinations.add(
        _Destination(
          label: 'Productos',
          icon: Icons.lunch_dining_outlined,
          selectedIcon: Icons.lunch_dining,
          page: const ProductsPage(),
        ),
      );
    }
    if (usuario.puede(Permiso.categorias)) {
      destinations.add(
        _Destination(
          label: 'Categorías',
          icon: Icons.category_outlined,
          selectedIcon: Icons.category,
          page: const CategoriesPage(),
        ),
      );
    }
    if (usuario.puede(Permiso.insumos)) {
      destinations.add(
        _Destination(
          label: 'Insumos',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          page: const InventoryPage(),
        ),
      );
    }
    if (usuario.puede(Permiso.compras)) {
      destinations.add(
        _Destination(
          label: 'Compras',
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart,
          page: PurchasesPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.conteo)) {
      destinations.add(
        _Destination(
          label: 'Conteo',
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check,
          page: CountPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.gastos) || usuario.puede(Permiso.sueldos)) {
      destinations.add(
        _Destination(
          label: 'Gastos',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          page: ExpensesPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.usuarios)) {
      destinations.add(
        _Destination(
          label: 'Usuarios',
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts,
          page: UsersPage(usuario: usuario),
        ),
      );
    }
    if (usuario.puede(Permiso.reportes)) {
      destinations.add(
        _Destination(
          label: 'Reportes',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          page: const ReportsPage(),
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
        final body = IndexedStack(
          index: index,
          children: destinations.map((item) => item.page).toList(),
        );
        final userMenu = PopupMenuButton<String>(
          tooltip: 'Sesión',
          onSelected: (value) {
            if (value == 'logout') widget.onLogout();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.usuario.nombre,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.usuario.esAdmin ? 'Administrador' : 'Cajero',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                              setState(() => _index = i);
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
                          setState(() => _index = value),
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
