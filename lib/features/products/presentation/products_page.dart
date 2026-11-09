import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

const _paleta = <int>[
  0xFF0F766E,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFEA580C,
  0xFFCA8A04,
  0xFF16A34A,
  0xFF475569,
];

class _ProductsData {
  const _ProductsData({
    required this.productos,
    required this.categorias,
    required this.insumos,
  });

  final List<Producto> productos;
  final List<CategoriaProducto> categorias;
  final List<Insumo> insumos;
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _repository = CatalogRepository();
  late Future<_ProductsData> _future;
  String _search = '';
  int? _categoriaId;
  bool _soloActivos = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_ProductsData> _load() async {
    final productos = await _repository.getProductos();
    final categorias = await _repository.getCategorias();
    final insumos = await _repository.getInsumos(soloActivos: true);
    return _ProductsData(
      productos: productos,
      categorias: categorias,
      insumos: insumos,
    );
  }

  Future<void> _openForm([Producto? producto]) async {
    final data = await _future;
    if (!mounted) return;
    final saved = await showDialog<int>(
      context: context,
      builder: (_) => _ProductDialog(
        repository: _repository,
        producto: producto,
        categorias: data.categorias,
        usuarioId: widget.usuario.id,
      ),
    );
    if (saved != null && mounted) {
      setState(_reload);
      showAppMessage(context, 'Producto guardado correctamente.');
    }
  }

  Future<void> _openRecipe(Producto producto) async {
    final data = await _future;
    final receta = await _repository.getReceta(producto.id!);
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecipeDialog(
        repository: _repository,
        producto: producto,
        insumos: data.insumos,
        receta: receta,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Receta actualizada.');
    }
  }

  Future<void> _toggle(Producto producto, bool activo) async {
    await _repository.setProductoActivo(producto.id!, activo);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _ajustarStock(Producto producto) async {
    final nuevo = await showDialog<double>(
      context: context,
      builder: (_) => _StockDialog(
        titulo: 'Ajustar stock de ${producto.nombre}',
        stockActual: producto.stock,
      ),
    );
    if (nuevo == null) return;
    try {
      await _repository.ajustarStockProducto(
        productoId: producto.id!,
        nuevoStock: nuevo,
        usuarioId: widget.usuario.id,
        motivo: 'Ajuste manual',
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Stock actualizado.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo ajustar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProductsData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final productos = data?.productos ?? [];
        final categorias = data?.categorias ?? [];
        final filtrados = productos.where((producto) {
          if (_soloActivos && !producto.activo) return false;
          if (_categoriaId != null && producto.categoriaId != _categoriaId) {
            return false;
          }
          final term = _search.trim().toLowerCase();
          if (term.isEmpty) return true;
          return producto.nombre.toLowerCase().contains(term);
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Productos',
                subtitle:
                    'Platos y bebidas. Los precios solo se cambian aquí. Las categorías se crean desde esta misma pantalla.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _openForm() : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo producto'),
                  ),
                ],
              ),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        decoration: appInput(
                          label: 'Buscar producto',
                          icon: Icons.search,
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<int?>(
                        initialValue: _categoriaId,
                        decoration: appInput(label: 'Categoría'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ...categorias.map(
                            (categoria) => DropdownMenuItem<int?>(
                              value: categoria.id,
                              child: Text(categoria.nombre),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoriaId = value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Solo activos'),
                      selected: _soloActivos,
                      onSelected: (value) =>
                          setState(() => _soloActivos = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (filtrados.isEmpty)
                EmptyState(
                  icon: Icons.lunch_dining_outlined,
                  title: 'No hay productos que coincidan',
                  message: 'Crea un producto o ajusta los filtros.',
                  action: FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo producto'),
                  ),
                )
              else
                ...filtrados.map(
                  (producto) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductRow(
                      producto: producto,
                      onEdit: () => _openForm(producto),
                      onRecipe: producto.esDirecto
                          ? null
                          : () => _openRecipe(producto),
                      onAjustarStock: producto.esDirecto
                          ? () => _ajustarStock(producto)
                          : null,
                      onToggle: (value) => _toggle(producto, value),
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

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.producto,
    required this.onEdit,
    required this.onRecipe,
    required this.onAjustarStock,
    required this.onToggle,
  });

  final Producto producto;
  final VoidCallback onEdit;
  final VoidCallback? onRecipe;
  final VoidCallback? onAjustarStock;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Color(producto.categoriaColor).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              image: producto.imagen != null
                  ? DecorationImage(
                      image: MemoryImage(producto.imagen!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: producto.imagen == null
                ? Icon(
                    producto.esDirecto
                        ? Icons.inventory_2_outlined
                        : Icons.restaurant,
                    color: Color(producto.categoriaColor),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto.nombre,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${producto.categoriaNombre} · ${producto.esDirecto ? 'Directo' : 'Preparado'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (producto.descripcion != null)
                  Text(
                    producto.descripcion!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMoney(producto.precio),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  producto.esDirecto
                      ? 'Stock: ${formatQty(producto.stock)}'
                      : 'Con receta',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: producto.esDirecto &&
                            producto.stock <= producto.stockMinimo
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onRecipe != null)
            OutlinedButton.icon(
              onPressed: onRecipe,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Receta'),
            ),
          if (onAjustarStock != null)
            OutlinedButton.icon(
              onPressed: onAjustarStock,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Ajustar stock'),
            ),
          const SizedBox(width: 8),
          Switch(value: producto.activo, onChanged: onToggle),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.repository,
    required this.categorias,
    required this.usuarioId,
    this.producto,
  });

  final CatalogRepository repository;
  final List<CategoriaProducto> categorias;
  final int usuarioId;
  final Producto? producto;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _precio;
  late final TextEditingController _stockMinimo;
  late final TextEditingController _stockActual;
  late final TextEditingController _costo;
  late List<CategoriaProducto> _categorias;
  late int? _categoriaId;
  late String _tipo;
  late bool _activo;
  Uint8List? _imagen;
  bool _saving = false;
  String? _error;

  bool get _hayCamara {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    final producto = widget.producto;
    _nombre = TextEditingController(text: producto?.nombre ?? '');
    _descripcion = TextEditingController(text: producto?.descripcion ?? '');
    _precio = TextEditingController(
      text: producto == null ? '' : producto.precio.toStringAsFixed(2),
    );
    _stockMinimo = TextEditingController(
      text: producto == null ? '0' : formatQty(producto.stockMinimo),
    );
    _stockActual = TextEditingController(
      text: producto == null ? '0' : formatQty(producto.stock),
    );
    _costo = TextEditingController(
      text: producto == null ? '0' : producto.costoUnitario.toStringAsFixed(2),
    );
    _categorias = List.of(widget.categorias);
    final activas = _categorias.where((categoria) => categoria.activo).toList();
    _categoriaId = producto?.categoriaId ??
        (activas.isEmpty ? null : activas.first.id);
    _tipo = producto?.tipo ?? 'PREPARADO';
    _activo = producto?.activo ?? true;
    _imagen = producto?.imagen;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _stockMinimo.dispose();
    _stockActual.dispose();
    _costo.dispose();
    super.dispose();
  }

  Future<void> _crearCategoria() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => const _NuevaCategoriaDialog(),
    );
    if (nombre == null || nombre.trim().isEmpty) return;
    try {
      await widget.repository.saveCategoria(
        CategoriaProducto(
          nombre: nombre.trim(),
          color: _paleta[_categorias.length % _paleta.length],
          siempreDisponible: false,
          orden: _categorias.length,
          activo: true,
        ),
      );
      final categorias = await widget.repository.getCategorias();
      final creada = categorias.firstWhere(
        (categoria) => categoria.nombre == nombre.trim(),
      );
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _categoriaId = creada.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear la categoría: $error');
    }
  }

  Future<void> _cargarImagen(ImageSource source) async {
    try {
      final archivo = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      setState(() => _imagen = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la imagen: $error');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaId == null) {
      setState(() => _error = 'Crea o selecciona una categoría.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final categoria = _categorias.firstWhere(
        (item) => item.id == _categoriaId,
      );
      final id = await widget.repository.saveProducto(
        Producto(
          id: widget.producto?.id,
          nombre: _nombre.text,
          categoriaId: _categoriaId!,
          categoriaNombre: categoria.nombre,
          categoriaColor: categoria.color,
          descripcion: _descripcion.text,
          precio: parseAmount(_precio.text),
          tipo: _tipo,
          imagen: _imagen,
          stockMinimo: _tipo == 'DIRECTO' ? parseAmount(_stockMinimo.text) : 0,
          costoUnitario: _tipo == 'DIRECTO' ? parseAmount(_costo.text) : 0,
          activo: _activo,
          stock: widget.producto?.stock ?? 0,
        ),
      );
      if (_tipo == 'DIRECTO') {
        await widget.repository.ajustarStockProducto(
          productoId: id,
          nuevoStock: parseAmount(_stockActual.text),
          usuarioId: widget.usuarioId,
          motivo: 'Carga inicial',
        );
      }
      if (!mounted) return;
      Navigator.pop(context, id);
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
    final directo = _tipo == 'DIRECTO';
    return AlertDialog(
      title: Text(widget.producto == null ? 'Nuevo producto' : 'Editar producto'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: appInput(label: 'Nombre del producto'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 130,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _imagen == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_outlined,
                                    size: 30,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Sin imagen',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              )
                            : Image.memory(
                                _imagen!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_hayCamara) ...[
                          OutlinedButton.icon(
                            onPressed: () =>
                                _cargarImagen(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tomar foto'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => _cargarImagen(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _hayCamara ? 'Elegir imagen' : 'Buscar imagen',
                          ),
                        ),
                        if (_imagen != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => setState(() => _imagen = null),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Quitar'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(_categorias.length),
                        initialValue: _categoriaId,
                        decoration: appInput(label: 'Categoría'),
                        items: _categorias
                            .map(
                              (categoria) => DropdownMenuItem(
                                value: categoria.id,
                                child: Text(categoria.nombre),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _categoriaId = value),
                        validator: (value) =>
                            value == null ? 'Selecciona una categoría' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _crearCategoria,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nueva'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: appInput(label: 'Tipo de producto'),
                  items: const [
                    DropdownMenuItem(
                      value: 'PREPARADO',
                      child: Text('Preparado (usa receta de insumos)'),
                    ),
                    DropdownMenuItem(
                      value: 'DIRECTO',
                      child: Text('Directo (stock propio en unidades)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _tipo = value ?? 'PREPARADO'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 2,
                  decoration: appInput(
                    label: 'Descripción (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _precio,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: appInput(
                          label: 'Precio de venta (Bs)',
                          icon: Icons.sell_outlined,
                        ),
                        validator: (value) {
                          if (parseAmount(value ?? '') < 0) {
                            return 'Precio inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    if (directo) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stockMinimo,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Stock mínimo',
                            icon: Icons.warning_amber_outlined,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (directo) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockActual,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Stock actual',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _costo,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Costo unitario (Bs)',
                            icon: Icons.price_check,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Producto activo'),
                  subtitle: Text(
                    directo
                        ? 'Los productos inactivos no se venden ni aparecen en el menú.'
                        : 'Configura la receta desde la lista de productos.',
                  ),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
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
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

class _NuevaCategoriaDialog extends StatefulWidget {
  const _NuevaCategoriaDialog();

  @override
  State<_NuevaCategoriaDialog> createState() => _NuevaCategoriaDialogState();
}

class _NuevaCategoriaDialogState extends State<_NuevaCategoriaDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva categoría'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            decoration: appInput(
              label: 'Nombre',
              hint: 'Ej. Masitas, Bebidas, Almuerzos',
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                ? 'Ingresa un nombre'
                : null,
            onFieldSubmitted: (_) {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, _controller.text.trim());
              }
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.titulo, required this.stockActual});

  final String titulo;
  final double stockActual;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatQty(widget.stockActual));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock del sistema: ${formatQty(widget.stockActual)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(
                  label: 'Stock real',
                  icon: Icons.inventory_2_outlined,
                ),
                validator: (value) {
                  if (parseAmount(value ?? '') < 0) return 'Cantidad inválida';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, parseAmount(_controller.text));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({
    required this.repository,
    required this.producto,
    required this.insumos,
    required this.receta,
  });

  final CatalogRepository repository;
  final Producto producto;
  final List<Insumo> insumos;
  final List<RecetaLinea> receta;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cantidades = <int, TextEditingController>{};
  final _seleccionados = <int>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final insumo in widget.insumos) {
      _cantidades[insumo.id!] = TextEditingController();
    }
    for (final linea in widget.receta) {
      if (!_cantidades.containsKey(linea.insumoId)) continue;
      _seleccionados.add(linea.insumoId);
      _cantidades[linea.insumoId]?.text = formatQty(linea.cantidad);
    }
  }

  @override
  void dispose() {
    for (final controller in _cantidades.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_seleccionados.isEmpty) {
      setState(() => _error = 'Selecciona al menos un insumo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveRecetaCantidades(
        widget.producto.id!,
        {
          for (final id in _seleccionados)
            id: parseAmount(_cantidades[id]!.text),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar la receta: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Receta · ${widget.producto.nombre}'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text(
                'Indica cuánto de cada insumo consume una porción vendida.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: widget.insumos.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No hay insumos activos',
                        message:
                            'Crea insumos en la sección Insumos para poder armar la receta.',
                      )
                    : ListView.separated(
                        itemCount: widget.insumos.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final insumo = widget.insumos[index];
                          final id = insumo.id!;
                          final seleccionado = _seleccionados.contains(id);
                          return Row(
                            children: [
                              Checkbox(
                                value: seleccionado,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _seleccionados.add(id);
                                    } else {
                                      _seleccionados.remove(id);
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(insumo.nombre),
                                    Text(
                                      'stock ${formatQty(insumo.stock)} ${insumo.unidadAbreviatura}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextFormField(
                                  controller: _cantidades[id],
                                  enabled: seleccionado,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: appInput(
                                    label: 'Cantidad',
                                    hint: insumo.unidadAbreviatura,
                                  ),
                                  validator: (value) {
                                    if (!seleccionado) return null;
                                    final cantidad = parseAmount(value ?? '');
                                    if (cantidad <= 0) {
                                      return 'Mayor a 0';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar receta'),
        ),
      ],
    );
  }
}
