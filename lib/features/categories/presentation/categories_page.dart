import 'package:flutter/material.dart';

import '../../../core/catalog_repository.dart';
import '../../../ui/common.dart';

const _palette = <int>[
  0xFF0F766E,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFEA580C,
  0xFFCA8A04,
  0xFF16A34A,
  0xFF475569,
];

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _repository = CatalogRepository();
  late Future<List<CategoriaProducto>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.getCategorias();

  Future<void> _openForm([CategoriaProducto? categoria]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(
        repository: _repository,
        categoria: categoria,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Categoría guardada.');
    }
  }

  Future<void> _toggle(CategoriaProducto categoria, bool activo) async {
    await _repository.setCategoriaActiva(categoria.id!, activo);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Categorías',
            subtitle:
                'Agrupa productos y define cuáles están siempre disponibles (por ejemplo, bebidas).',
            actions: [
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva categoría'),
              ),
            ],
          ),
          FutureBuilder<List<CategoriaProducto>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                );
              }
              final categorias = snapshot.data ?? [];
              if (categorias.isEmpty) {
                return EmptyState(
                  icon: Icons.category_outlined,
                  title: 'Aún no hay categorías',
                  message:
                      'Crea la primera categoría para organizar los productos del restaurante.',
                  action: FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear categoría'),
                  ),
                );
              }
              return Column(
                children: categorias
                    .map(
                      (categoria) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Color(categoria.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            categoria.nombre,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        if (categoria.siempreDisponible) ...[
                                          const SizedBox(width: 8),
                                          const Chip(
                                            label: Text('Siempre visible'),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      'Orden ${categoria.orden} · ${categoria.activo ? 'Activa' : 'Inactiva'}',
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
                              Switch(
                                value: categoria.activo,
                                onChanged: (value) =>
                                    _toggle(categoria, value),
                              ),
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _openForm(categoria),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.repository, this.categoria});

  final CatalogRepository repository;
  final CategoriaProducto? categoria;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _orden;
  late int _color;
  late bool _siempreDisponible;
  late bool _activo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final categoria = widget.categoria;
    _nombre = TextEditingController(text: categoria?.nombre ?? '');
    _orden = TextEditingController(text: '${categoria?.orden ?? 0}');
    _color = categoria?.color ?? _palette.first;
    _siempreDisponible = categoria?.siempreDisponible ?? false;
    _activo = categoria?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCategoria(
        CategoriaProducto(
          id: widget.categoria?.id,
          nombre: _nombre.text,
          color: _color,
          siempreDisponible: _siempreDisponible,
          orden: int.tryParse(_orden.text.trim()) ?? 0,
          activo: _activo,
        ),
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
        widget.categoria == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: appInput(
                    label: 'Nombre',
                    hint: 'Ej. Masitas, Bebidas, Almuerzos',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _orden,
                  keyboardType: TextInputType.number,
                  decoration: appInput(
                    label: 'Orden',
                    hint: '0 aparece primero',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Color',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _palette
                      .map(
                        (color) => InkWell(
                          onTap: () => setState(() => _color = color),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == color
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Siempre disponible'),
                  subtitle: const Text(
                    'Se muestra aparte del menú del día. Ideal para bebidas.',
                  ),
                  value: _siempreDisponible,
                  onChanged: (value) =>
                      setState(() => _siempreDisponible = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Categoría activa'),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
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
