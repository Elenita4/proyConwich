import 'package:flutter/material.dart';

import 'features/sales/presentation/sales_page.dart';
import 'features/products/presentation/products_page.dart';
import 'features/inventory/presentation/inventory_page.dart';

void main() {
  runApp(const RestaurantApp());
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sazón Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0F766E), width: 2),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    final valid =
        _userController.text.trim() == 'admin' &&
        _passwordController.text == '1234';
    if (!valid) {
      setState(() => _errorMessage = 'Usuario o contraseña incorrectos.');
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          return Row(
            children: [
              if (wide)
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F766E),
                    padding: const EdgeInsets.all(48),
                    child: const _WelcomePanel(),
                  ),
                ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 410),
                      child: _LoginForm(
                        userController: _userController,
                        passwordController: _passwordController,
                        obscurePassword: _obscurePassword,
                        errorMessage: _errorMessage,
                        onTogglePassword: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onLogin: _login,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.restaurant_rounded, color: Colors.white, size: 62),
        const SizedBox(height: 28),
        Text(
          'Sazón',
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Todo tu restaurante,\norganizado en un solo lugar.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white.withValues(alpha: .92),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Gestiona ventas, inventario, caja y pedidos de forma simple.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.white.withValues(alpha: .78)),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.userController,
    required this.passwordController,
    required this.obscurePassword,
    required this.errorMessage,
    required this.onTogglePassword,
    required this.onLogin,
  });

  final TextEditingController userController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final String? errorMessage;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.restaurant_rounded,
          color: Color(0xFF0F766E),
          size: 42,
        ),
        const SizedBox(height: 24),
        Text(
          'Bienvenido',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Ingresa a tu panel de administración.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 30),
        Text('Usuario', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: userController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.person_outline),
            hintText: 'Escribe tu usuario',
          ),
        ),
        const SizedBox(height: 18),
        Text('Contraseña', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: passwordController,
          obscureText: obscurePassword,
          onSubmitted: (_) => onLogin(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline),
            hintText: 'Escribe tu contraseña',
            suffixIcon: IconButton(
              onPressed: onTogglePassword,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login),
            label: const Text('Ingresar'),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Acceso administrador',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.black45),
          ),
        ),
      ],
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  final _sections = const [
    'Resumen',
    'Ventas y pedidos',
    'Inventario',
    'Productos',
    'Caja y turnos',
    'Reportes',
  ];
  final _orders = <Order>[
    Order('#1048', 'María López', 'Completo + jugo', 42, OrderStatus.preparing),
    Order('#1047', 'Carlos Rojas', '2 frappés', 28, OrderStatus.ready),
    Order('#1046', 'Ana Pérez', 'Sopa suelta', 18, OrderStatus.pending),
  ];

  void _showQuickSale() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _QuickSaleSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = _selectedIndex == 0
            ? _Overview(
                orders: _orders,
                onQuickSale: _showQuickSale,
                onOrderChanged: (order, status) {
                  setState(() => order.status = status);
                },
              )
            : _selectedIndex == 2
            ? const InventoryPage()
            : _selectedIndex == 3
            ? const ProductsPage()
            : _selectedIndex == 1
            ? const SalesPage()
            : _ModulePlaceholder(
                title: _sections[_selectedIndex],
                index: _selectedIndex,
              );
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _sections[_selectedIndex],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                onPressed: () {},
                tooltip: 'Notificaciones',
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: PopupMenuButton<String>(
                  tooltip: 'Cuenta',
                  onSelected: (value) {
                    if (value == 'logout') {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'profile', child: Text('Mi perfil')),
                    PopupMenuItem(
                      value: 'logout',
                      child: Text('Cerrar sesión'),
                    ),
                  ],
                  child: const CircleAvatar(child: Text('A')),
                ),
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    _NavigationRail(
                      selectedIndex: _selectedIndex,
                      onSelected: (value) =>
                          setState(() => _selectedIndex = value),
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex > 3 ? 0 : _selectedIndex,
                  onDestinationSelected: (value) =>
                      setState(() => _selectedIndex = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Inicio',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: 'Ventas',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: 'Stock',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'Más',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.selectedIndex,
    required this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const destinations = [
      (Icons.dashboard_outlined, Icons.dashboard, 'Resumen'),
      (Icons.receipt_long_outlined, Icons.receipt_long, 'Ventas y pedidos'),
      (Icons.inventory_2_outlined, Icons.inventory_2, 'Inventario'),
      (Icons.restaurant_menu_outlined, Icons.restaurant_menu, 'Productos'),
      (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Caja y turnos'),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
    ];
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Icon(
          Icons.restaurant_rounded,
          color: Color(0xFF0F766E),
          size: 32,
        ),
      ),
      destinations: [
        for (final destination in destinations)
          NavigationRailDestination(
            icon: Icon(destination.$1),
            selectedIcon: Icon(destination.$2),
            label: Text(destination.$3),
          ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.orders,
    required this.onQuickSale,
    required this.onOrderChanged,
  });
  final List<Order> orders;
  final VoidCallback onQuickSale;
  final void Function(Order, OrderStatus) onOrderChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buenos días, administrador',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Aquí tienes el resumen de tu restaurante hoy.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: const [
                  KpiCard(
                    title: 'Ventas del día',
                    value: 'Bs 1.248',
                    caption: '+12,5% vs. ayer',
                    icon: Icons.trending_up,
                    color: Color(0xFF0F766E),
                  ),
                  KpiCard(
                    title: 'Efectivo esperado',
                    value: 'Bs 786',
                    caption: 'Después de movimientos',
                    icon: Icons.payments_outlined,
                    color: Color(0xFF2563EB),
                  ),
                  KpiCard(
                    title: 'Pagos QR',
                    value: 'Bs 462',
                    caption: '18 cobros registrados',
                    icon: Icons.qr_code_2,
                    color: Color(0xFF7C3AED),
                  ),
                  KpiCard(
                    title: 'Resultado del período',
                    value: 'Bs 534',
                    caption: 'Ingresos menos gastos',
                    icon: Icons.account_balance_wallet_outlined,
                    color: Color(0xFFEA580C),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 850;
                  final ordersCard = _OrdersCard(
                    orders: orders,
                    onOrderChanged: onOrderChanged,
                  );
                  final actions = _ActionsCard(onQuickSale: onQuickSale);
                  return stacked
                      ? Column(
                          children: [
                            ordersCard,
                            const SizedBox(height: 18),
                            actions,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: ordersCard),
                            const SizedBox(width: 18),
                            Expanded(child: actions),
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: .12),
                    child: Icon(icon, color: color, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                caption,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersCard extends StatelessWidget {
  const _OrdersCard({required this.orders, required this.onOrderChanged});
  final List<Order> orders;
  final void Function(Order, OrderStatus) onOrderChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pedidos recientes',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton(onPressed: () {}, child: const Text('Ver todos')),
              ],
            ),
            const Divider(height: 24),
            for (final order in orders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text(order.number.substring(1)),
                ),
                title: Text(
                  '${order.customer} · ${order.items}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Pedido ${order.number} · Bs ${order.total}'),
                trailing: SizedBox(
                  width: 132,
                  child: DropdownButton<OrderStatus>(
                    value: order.status,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: OrderStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: StatusChip(status: status),
                          ),
                        )
                        .toList(),
                    onChanged: (status) {
                      if (status != null) onOrderChanged(order, status);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.onQuickSale});
  final VoidCallback onQuickSale;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acciones rápidas',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _ActionButton(
              icon: Icons.add_shopping_cart,
              label: 'Registrar venta',
              onPressed: onQuickSale,
            ),
            _ActionButton(
              icon: Icons.inventory_2_outlined,
              label: 'Agregar insumo',
              onPressed: () {},
            ),
            _ActionButton(
              icon: Icons.point_of_sale,
              label: 'Abrir caja',
              onPressed: () {},
            ),
            _ActionButton(
              icon: Icons.bar_chart,
              label: 'Generar reporte',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Align(alignment: Alignment.centerLeft, child: Text(label)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({required this.title, required this.index});
  final String title;
  final int index;

  @override
  Widget build(BuildContext context) {
    final icons = [
      Icons.dashboard,
      Icons.receipt_long,
      Icons.inventory_2,
      Icons.restaurant_menu,
      Icons.point_of_sale,
      Icons.bar_chart,
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icons[index],
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este módulo está listo para conectarse con tus operaciones diarias.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSaleSheet extends StatefulWidget {
  const _QuickSaleSheet();
  @override
  State<_QuickSaleSheet> createState() => _QuickSaleSheetState();
}

class _QuickSaleSheetState extends State<_QuickSaleSheet> {
  String category = 'Todos';
  final products = const {
    'Completo': 25.0,
    'Sopa suelta': 18.0,
    'Té': 8.0,
    'Jugo natural': 12.0,
    'Frappé': 16.0,
  };
  final selected = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final total = selected.entries.fold<double>(
      0,
      (sum, entry) => sum + products[entry.key]! * entry.value,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Registrar venta',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: ['Todos', 'Desayuno', 'Almuerzo']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => category = value ?? 'Todos'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: products.keys
                    .map(
                      (product) => FilterChip(
                        label: Text(
                          '$product · Bs ${products[product]!.toStringAsFixed(0)}',
                        ),
                        selected: selected.containsKey(product),
                        onSelected: (isSelected) => setState(() {
                          if (isSelected) {
                            selected[product] = 1;
                          } else {
                            selected.remove(product);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    'Bs ${total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('Cobrar y confirmar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum OrderStatus { pending, preparing, ready, delivered }

extension on OrderStatus {
  String get label => switch (this) {
    OrderStatus.pending => 'Pendiente',
    OrderStatus.preparing => 'En preparación',
    OrderStatus.ready => 'Listo',
    OrderStatus.delivered => 'Entregado',
  };

  Color get color => switch (this) {
    OrderStatus.pending => const Color(0xFFB45309),
    OrderStatus.preparing => const Color(0xFF2563EB),
    OrderStatus.ready => const Color(0xFF0F766E),
    OrderStatus.delivered => const Color(0xFF64748B),
  };
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: status.color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class Order {
  Order(this.number, this.customer, this.items, this.total, this.status);
  final String number;
  final String customer;
  final String items;
  final int total;
  OrderStatus status;
}
