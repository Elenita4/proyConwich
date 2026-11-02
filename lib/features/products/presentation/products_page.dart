import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';

import '../../inventory/data/inventory_repository.dart';
import '../data/product_repository.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _repository = ProductRepository();
  late Future<List<Product>> _productsFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _productsFuture = _repository.getProducts();

  Future<void> _newProduct() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductFormDialog(repository: _repository),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _message('Producto guardado correctamente.');
    }
  }

  Future<void> _addRecipe(Product product) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RecipeDialog(product: product, repository: _repository),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _message('Receta guardada correctamente.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return RefreshIndicator(
      onRefresh: () async => setState(_reload),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(padding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 12,
                  children: [
                    Text(
                      'Productos',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    FilledButton.icon(
                      onPressed: _newProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Nuevo producto'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Administra los productos que estarán disponibles para futuras ventas.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextField(
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por código o nombre',
                  ),
                ),
                const SizedBox(height: 20),
                FutureBuilder<List<Product>>(
                  future: _productsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Text('No se pudieron cargar los productos.');
                    }
                    final products = (snapshot.data ?? [])
                        .where(
                          (product) =>
                              _search.isEmpty ||
                              product.name.toLowerCase().contains(_search) ||
                              product.code.toLowerCase().contains(_search),
                        )
                        .toList();
                    if (products.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No hay productos registrados.'),
                          ),
                        ),
                      );
                    }
                    return _ProductTable(
                      products: products,
                      onAddRecipe: _addRecipe,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTable extends StatelessWidget {
  const _ProductTable({required this.products, required this.onAddRecipe});
  final List<Product> products;
  final ValueChanged<Product> onAddRecipe;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Producto')),
            DataColumn(label: Text('Categoría')),
            DataColumn(label: Text('Precio')),
            DataColumn(label: Text('Receta')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: products
              .map(
                (product) => DataRow(
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          if (product.photo != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Image.memory(
                                product.photo!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                product.code,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      StatusLabel(
                        text: product.categoryName,
                        color: Color(product.categoryColor),
                      ),
                    ),
                    DataCell(
                      Text('Bs ${product.salePrice.toStringAsFixed(2)}'),
                    ),
                    DataCell(
                      StatusLabel(
                        text: product.recipeId == null
                            ? 'Pendiente'
                            : 'Configurada',
                        color: product.recipeId == null
                            ? Colors.orange
                            : Colors.teal,
                      ),
                    ),
                    DataCell(
                      OutlinedButton.icon(
                        onPressed: () => onAddRecipe(product),
                        icon: Icon(
                          product.recipeId == null
                              ? Icons.menu_book_outlined
                              : Icons.edit_note,
                        ),
                        label: Text(
                          product.recipeId == null
                              ? 'Agregar receta'
                              : 'Ver receta',
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({super.key, required this.repository});
  final ProductRepository repository;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController(text: '0');
  Uint8List? _photo;
  List<ProductCategory> _categories = [];
  int? _categoryId;
  bool _loadingCategories = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await widget.repository.getCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoryId = categories.isEmpty ? null : categories.first.id;
      _loadingCategories = false;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Abrir cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveProduct(
        Product(
          code: _code.text.trim(),
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          salePrice: double.parse(_price.text),
          categoryId: _categoryId!,
          categoryName: '',
          categoryColor: 4280391418,
          photo: _photo,
          active: true,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on DatabaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.isUniqueConstraintError()
            ? 'El código ya está registrado.'
            : 'No se pudo guardar el producto.';
      });
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  String? _priceValidator(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number < 0 ? 'Ingresa un precio válido' : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo producto'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600
            ? MediaQuery.sizeOf(context).width - 64
            : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Código'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingCategories
                      ? null
                      : (value) => setState(() => _categoryId = value),
                  validator: (value) =>
                      value == null ? 'Selecciona una categoría' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta (Bs)',
                  ),
                  validator: _priceValidator,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_outlined),
                    label: Text(
                      _photo == null
                          ? 'Agregar foto (opcional)'
                          : 'Cambiar foto',
                    ),
                  ),
                ),
                if (_photo != null)
                  Image.memory(
                    _photo!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class RecipeDialog extends StatefulWidget {
  const RecipeDialog({
    super.key,
    required this.product,
    required this.repository,
  });
  final Product product;
  final ProductRepository repository;

  @override
  State<RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<RecipeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _instructions = TextEditingController();
  List<InventoryLookup> _ingredients = [];
  final List<RecipeIngredient> _recipeIngredients = [];
  int? _selectedIngredient;
  final _quantity = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    final ingredients = await InventoryRepository().getItems();
    final existing = widget.product.recipeId == null
        ? <RecipeIngredient>[]
        : await widget.repository.getRecipe(widget.product.id!);
    if (!mounted) return;
    setState(() {
      _ingredients = ingredients
          .map(
            (item) => InventoryLookup(
              id: item.id!,
              name: item.name,
              abbreviation: item.unitAbbreviation,
            ),
          )
          .toList();
      _name.text = widget.product.name;
      _recipeIngredients.addAll(existing);
      _loading = false;
    });
  }

  void _addIngredient() {
    final quantity = double.tryParse(_quantity.text);
    if (_selectedIngredient == null || quantity == null || quantity <= 0) {
      setState(
        () => _error = 'Selecciona un insumo e ingresa una cantidad válida.',
      );
      return;
    }
    final ingredient = _ingredients.firstWhere(
      (value) => value.id == _selectedIngredient,
    );
    setState(() {
      _recipeIngredients.removeWhere(
        (value) => value.ingredientId == ingredient.id,
      );
      _recipeIngredients.add(
        RecipeIngredient(
          ingredientId: ingredient.id,
          ingredientName: ingredient.name,
          unitAbbreviation: ingredient.abbreviation ?? '',
          quantity: quantity,
        ),
      );
      _quantity.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _recipeIngredients.isEmpty) {
      setState(() => _error = 'Agrega al menos un insumo a la receta.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveRecipe(
        productId: widget.product.id!,
        name: _name.text.trim(),
        instructions: _instructions.text.trim(),
        ingredients: _recipeIngredients,
      );
      if (mounted) Navigator.pop(context, true);
    } on DatabaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.isUniqueConstraintError()
            ? 'Este producto ya tiene una receta.'
            : 'No se pudo guardar la receta.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Receta de ${widget.product.name}'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600
            ? MediaQuery.sizeOf(context).width - 64
            : 560,
        child: _loading
            ? const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la receta',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Campo obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _instructions,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Preparación (opcional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedIngredient,
                              decoration: const InputDecoration(
                                labelText: 'Insumo',
                              ),
                              items: _ingredients
                                  .map(
                                    (ingredient) => DropdownMenuItem(
                                      value: ingredient.id,
                                      child: Text(ingredient.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _selectedIngredient = value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Agregar insumo',
                            onPressed: _addIngredient,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._recipeIngredients.map(
                        (ingredient) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(ingredient.ingredientName),
                          subtitle: Text(
                            '${ingredient.quantity} ${ingredient.unitAbbreviation}',
                          ),
                          trailing: IconButton(
                            onPressed: () => setState(
                              () => _recipeIngredients.remove(ingredient),
                            ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar receta'),
        ),
      ],
    );
  }
}

class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
