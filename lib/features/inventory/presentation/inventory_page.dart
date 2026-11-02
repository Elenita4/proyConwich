import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/inventory_repository.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repository = InventoryRepository();
  late Future<List<InventoryItem>> _itemsFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _itemsFuture = _repository.getItems();

  Future<void> _openForm([InventoryItem? item]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => InventoryFormDialog(item: item, repository: _repository),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _showMessage('Insumo guardado correctamente.');
    }
  }

  Future<void> _delete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar insumo'),
        content: Text('¿Deseas retirar "${item.name}" del inventario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repository.deleteItem(item.id!);
      if (mounted) {
        setState(_reload);
        _showMessage('Insumo eliminado del inventario.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Inventario de insumos',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo insumo'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Administra existencias, costos y niveles mínimos.',
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
              FutureBuilder<List<InventoryItem>>(
                future: _itemsFuture,
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
                    return _ErrorState(onRetry: () => setState(_reload));
                  }
                  final items = (snapshot.data ?? [])
                      .where(
                        (item) =>
                            _search.isEmpty ||
                            item.name.toLowerCase().contains(_search) ||
                            item.code.toLowerCase().contains(_search),
                      )
                      .toList();
                  if (items.isEmpty) return const _EmptyState();
                  return _InventoryTable(
                    items: items,
                    onEdit: _openForm,
                    onDelete: _delete,
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

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onEdit;
  final ValueChanged<InventoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Insumo')),
            DataColumn(label: Text('Categoría')),
            DataColumn(label: Text('Existencia')),
            DataColumn(label: Text('Mínimo')),
            DataColumn(label: Text('Costo promedio')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: items.map((item) {
            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.code,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(item.categoryName)),
                DataCell(
                  Text(
                    '${item.currentStock.toStringAsFixed(2)} ${item.unitAbbreviation}',
                  ),
                ),
                DataCell(
                  Text(
                    '${item.minimumStock.toStringAsFixed(2)} ${item.unitAbbreviation}',
                  ),
                ),
                DataCell(Text('Bs ${item.averageCost.toStringAsFixed(2)}')),
                DataCell(
                  StatusBadge(
                    text: item.lowStock ? 'Stock bajo' : 'Disponible',
                    color: item.lowStock ? Colors.orange : Colors.teal,
                  ),
                ),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        onPressed: () => onEdit(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => onDelete(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class InventoryFormDialog extends StatefulWidget {
  const InventoryFormDialog({
    super.key,
    required this.item,
    required this.repository,
  });
  final InventoryItem? item;
  final InventoryRepository repository;

  @override
  State<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends State<InventoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _stock;
  late final TextEditingController _minimum;
  late final TextEditingController _cost;
  List<InventoryLookup> _categories = [];
  List<InventoryLookup> _units = [];
  int? _categoryId;
  int? _unitId;
  bool _loading = true;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _code = TextEditingController(text: item?.code);
    _name = TextEditingController(text: item?.name);
    _stock = TextEditingController(text: item?.currentStock.toString());
    _minimum = TextEditingController(text: item?.minimumStock.toString());
    _cost = TextEditingController(text: item?.averageCost.toString());
    _categoryId = item?.categoryId;
    _unitId = item?.unitId;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final categories = await widget.repository.getCategories();
    final units = await widget.repository.getUnits();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _units = units;
      _categoryId ??= categories.isEmpty ? null : categories.first.id;
      _unitId ??= units.isEmpty ? null : units.first.id;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _stock.dispose();
    _minimum.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _categoryId == null ||
        _unitId == null) {
      return;
    }
    final category = _categories.firstWhere((value) => value.id == _categoryId);
    final unit = _units.firstWhere((value) => value.id == _unitId);
    try {
      await widget.repository.saveItem(
        InventoryItem(
          id: widget.item?.id,
          code: _code.text.trim(),
          name: _name.text.trim(),
          categoryId: _categoryId!,
          categoryName: category.name,
          unitId: _unitId!,
          unitAbbreviation: unit.abbreviation ?? unit.name,
          currentStock: double.parse(_stock.text),
          minimumStock: double.parse(_minimum.text),
          averageCost: double.parse(_cost.text),
          active: true,
        ),
      );
    } on DatabaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = error.isUniqueConstraintError()
            ? 'El código ya está registrado.'
            : 'No se pudo guardar el insumo. Intenta nuevamente.';
      });
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;
  String? _number(String? value) =>
      double.tryParse(value ?? '') == null || double.parse(value!) < 0
      ? 'Ingresa un número válido'
      : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: SizedBox(
        width: 520,
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
                        controller: _code,
                        decoration: const InputDecoration(labelText: 'Código'),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del insumo',
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _categoryId,
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                              ),
                              items: _categories
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value.id,
                                      child: Text(value.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _categoryId = value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _unitId,
                              decoration: const InputDecoration(
                                labelText: 'Unidad',
                              ),
                              items: _units
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value.id,
                                      child: Text(value.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _unitId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stock,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Stock actual',
                              ),
                              validator: _number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minimum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Stock mínimo',
                              ),
                              validator: _number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Costo promedio (Bs)',
                        ),
                        validator: _number,
                      ),
                      if (_saveError != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _saveError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.text, required this.color});
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Card(
    elevation: 0,
    child: Padding(
      padding: EdgeInsets.all(40),
      child: Center(
        child: Text('No hay insumos que coincidan con la búsqueda.'),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Text('No se pudo consultar el inventario.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
