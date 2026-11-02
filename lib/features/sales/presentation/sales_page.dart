import 'package:flutter/material.dart';

import '../../products/data/product_repository.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _repository = ProductRepository();
  late Future<List<Product>> _productsFuture;
  final _cart = <int, CartLine>{};
  String _search = '';
  int? _categoryId;
  List<ProductCategory> _categories = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _productsFuture =
        Future.wait([_repository.getProducts(), _repository.getCategories()])
            .then((values) {
              _categories = values[1] as List<ProductCategory>;
              return values[0] as List<Product>;
            });
  }

  void _add(Product product) {
    setState(() {
      final line = _cart[product.id];
      if (line == null) {
        _cart[product.id!] = CartLine(product: product);
      } else {
        line.quantity++;
      }
    });
  }

  void _remove(Product product) {
    setState(() {
      final line = _cart[product.id];
      if (line == null) return;
      if (line.quantity == 1) {
        _cart.remove(product.id);
      } else {
        line.quantity--;
      }
    });
  }

  Future<void> _reviewAndPay() async {
    if (_cart.isEmpty) return;
    final paymentMethod = await showDialog<String>(
      context: context,
      builder: (context) => _CheckoutDialog(lines: _cart.values.toList()),
    );
    if (paymentMethod == null || !mounted) return;
    try {
      await _repository.completeSale(
        _cart.values.toList(),
        paymentMethod: paymentMethod,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _error = null;
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta registrada correctamente.')),
      );
    } on StateError catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 800;
    return RefreshIndicator(
      onRefresh: () async => setState(_reload),
      child: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: const [
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No se pudieron cargar los productos.'),
                  ),
                ),
              ],
            );
          }
          final products = (snapshot.data ?? []).where((product) {
            final matchesSearch =
                _search.isEmpty ||
                product.name.toLowerCase().contains(_search) ||
                product.code.toLowerCase().contains(_search);
            return matchesSearch &&
                (_categoryId == null || product.categoryId == _categoryId);
          }).toList();
          final catalog = _Catalog(
            products: products,
            categories: _categories,
            selectedCategory: _categoryId,
            onCategoryChanged: (value) => setState(() => _categoryId = value),
            search: _search,
            onSearch: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
            onAdd: _add,
          );
          final cart = _Cart(
            lines: _cart.values.toList(),
            onAdd: _add,
            onRemove: _remove,
            onComplete: _reviewAndPay,
            error: _error,
          );
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (mobile) ...[
                catalog,
                const SizedBox(height: 12),
                cart,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: catalog),
                    const SizedBox(width: 16),
                    SizedBox(width: 360, child: cart),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.products,
    required this.categories,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.search,
    required this.onSearch,
    required this.onAdd,
  });
  final List<Product> products;
  final List<ProductCategory> categories;
  final int? selectedCategory;
  final ValueChanged<int?> onCategoryChanged;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<Product> onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ventas y pedidos',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar producto',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Todos'),
                    selected: selectedCategory == null,
                    onSelected: (_) => onCategoryChanged(null),
                  ),
                  ...categories.map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text(category.name),
                        selected: selectedCategory == category.id,
                        selectedColor: Color(category.color)
                            .withValues(alpha: .25),
                        onSelected: (_) => onCategoryChanged(category.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay productos para esta categoría.'),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 150,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return InkWell(
                    onTap: () => onAdd(product),
                    borderRadius: BorderRadius.circular(12),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: Color(product.categoryColor).withValues(alpha: .1),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (product.photo != null)
                                    Image.memory(
                                      product.photo!,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                    ),
                                  const Spacer(),
                                  Icon(
                                    Icons.add_circle,
                                    color: Color(product.categoryColor),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text('Bs ${product.salePrice.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Cart extends StatelessWidget {
  const _Cart({
    required this.lines,
    required this.onAdd,
    required this.onRemove,
    required this.onComplete,
    required this.error,
  });
  final List<CartLine> lines;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onRemove;
  final VoidCallback onComplete;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final total = lines.fold<double>(
      0,
      (sum, line) => sum + line.product.salePrice * line.quantity,
    );
    return Card(
      elevation: 0,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Venta actual (${lines.length})'),
        subtitle: Text('Total: Bs ${total.toStringAsFixed(2)}'),
        children: [
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Selecciona productos para agregarlos a la venta.'),
            )
          else
            ...lines.map(
              (line) => ListTile(
                title: Text(line.product.name),
                subtitle: Text(
                  'Bs ${line.product.salePrice.toStringAsFixed(2)} c/u',
                ),
                leading: CircleAvatar(child: Text('${line.quantity}')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => onRemove(line.product),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: () => onAdd(line.product),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: lines.isEmpty ? null : onComplete,
                icon: const Icon(Icons.check),
                label: const Text('Ver pedido y cobrar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.lines});
  final List<CartLine> lines;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  String _method = 'EFECTIVO';

  @override
  Widget build(BuildContext context) {
    final total = widget.lines.fold<double>(
      0,
      (sum, line) => sum + line.product.salePrice * line.quantity,
    );
    return AlertDialog(
      title: const Text('Ver pedido y cobrar'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...widget.lines.map(
              (line) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line.quantity} x ${line.product.name}'),
                trailing: Text(
                  'Bs ${(line.product.salePrice * line.quantity).toStringAsFixed(2)}',
                ),
              ),
            ),
            const Divider(),
            Text(
              'Total: Bs ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: const [
                DropdownMenuItem(value: 'EFECTIVO', child: Text('Efectivo')),
                DropdownMenuItem(value: 'QR', child: Text('QR')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _method),
          child: const Text('Confirmar cobro'),
        ),
      ],
    );
  }
}
