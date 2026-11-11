import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _MenuData {
  const _MenuData({
    required this.menu,
    required this.items,
    required this.productos,
    required this.categorias,
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<Producto> productos;
  final List<CategoriaProducto> categorias;
}

class MenuPage extends StatefulWidget {
  const MenuPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _repository = MenuRepository();
  final _catalog = CatalogRepository();
  final _cash = CashRepository();
  late DateTime _fecha;
  late String _tipo;
  late Future<_MenuData> _future;

  bool get _esAdmin => widget.usuario.puede(Permiso.menu);
  bool get _puedeAgotar => widget.usuario.puede(Permiso.agotamiento);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    _tipo = now.hour < 12 ? 'DESAYUNO' : 'ALMUERZO';
    _reload();
    _ajustarTurnoCaja();
  }

  @override
  void didUpdateWidget(MenuPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _reload();
      _ajustarTurnoCaja();
    }
  }

  /// El tipo de menú sigue el turno de la caja abierta (no la hora del reloj).
  Future<void> _ajustarTurnoCaja() async {
    try {
      final caja = await _cash.getCajaAbierta();
      if (!mounted || caja == null) return;
      final tipo = MenuRepository.tipoDesdeTurno(caja.turno);
      if (tipo == _tipo) return;
      setState(() {
        _tipo = tipo;
        _reload();
      });
    } catch (_) {
      // Si no se puede leer la caja se mantiene el tipo por hora.
    }
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_MenuData> _load() async {
    final menu = await _repository.getMenu(_fecha, _tipo);
    final items = menu == null
        ? <MenuItem>[]
        : await _repository.getItems(menu.id);
    final productos = _esAdmin
        ? await _catalog.getProductos(soloActivos: true)
        : <Producto>[];
    final categorias = _esAdmin
        ? await _catalog.getCategorias()
        : <CategoriaProducto>[];
    return _MenuData(
      menu: menu,
      items: items,
      productos: productos,
      categorias: categorias,
    );
  }

  bool _esCategoriaDelTipo(CategoriaProducto categoria) {
    final nombre = categoria.nombre
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    return _tipo == 'DESAYUNO'
        ? nombre.contains('desayuno')
        : nombre.contains('almuerzo');
  }

  /// Productos que corresponden al tipo de menú actual. Se descartan los de
  /// venta directa porque se venden siempre.
  List<Producto> _sugeridos(_MenuData data) {
    final base = data.productos
        .where(
          (producto) =>
              !producto.categoriaSiempreDisponible &&
              !producto.esVentaDirecta,
        )
        .toList();
    final categoriasTipo = data.categorias
        .where(_esCategoriaDelTipo)
        .map((categoria) => categoria.id)
        .toSet();
    if (categoriasTipo.isEmpty) return base;
    final filtrados = base
        .where((producto) => categoriasTipo.contains(producto.categoriaId))
        .toList();
    return filtrados.isEmpty ? base : filtrados;
  }

  Future<void> _armarMenu(_MenuData data) async {
    final sugeridos = _sugeridos(data);
    // Conserva los platos que ya están en el borrador aunque su categoría no
    // coincida con el filtro, para no perderlos al volver a guardar.
    final idsSugeridos = sugeridos.map((producto) => producto.id).toSet();
    for (final item in data.items) {
      if (idsSugeridos.contains(item.productoId)) continue;
      for (final producto in data.productos) {
        if (producto.id == item.productoId) {
          sugeridos.add(producto);
          idsSugeridos.add(producto.id);
          break;
        }
      }
    }
    if (sugeridos.isEmpty) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No hay productos activos para este menú. Crea productos en Productos.',
        error: true,
      );
      return;
    }
    final anteriores = await _repository.getProductosMenuAnterior(
      _fecha,
      _tipo,
    );
    if (!mounted) return;
    final seleccionInicial = data.items.isNotEmpty
        ? data.items.map((item) => item.productoId).toList()
        : anteriores;
    final seleccionados = await showDialog<List<int>>(
      context: context,
      builder: (_) => _MenuBuilderDialog(
        productos: sugeridos,
        seleccionInicial: seleccionInicial,
        anteriores: anteriores,
        tipo: _tipo,
      ),
    );
    if (seleccionados == null) return;
    try {
      final menu = data.menu ??
          await _repository.crearMenu(_fecha, _tipo, widget.usuario.id);
      await _repository.reemplazarItems(menu.id, seleccionados);
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        seleccionados.isEmpty
            ? 'El menú quedó vacío.'
            : 'Menú guardado con ${seleccionados.length} producto(s).',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo guardar el menú: $error', error: true);
    }
  }

  Future<void> _quitar(MenuItem item) async {
    final confirmado = await confirmAction(
      context,
      title: 'Quitar del menú',
      message: '¿Quitar ${item.nombre} del menú de hoy?',
      confirmLabel: 'Quitar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.quitarItem(item.id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _publicar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    if (data.items.isEmpty) {
      showAppMessage(
        context,
        'Agrega al menos un plato antes de publicar.',
        error: true,
      );
      return;
    }
    await _repository.publicar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú publicado. Ya se puede vender.');
  }

  Future<void> _cerrar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar menú',
      message:
          'El menú quedará cerrado y no se podrán registrar más ventas de estos platos.',
      confirmLabel: 'Cerrar menú',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.cerrar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú cerrado.');
  }

  Future<void> _toggleDisponible(MenuItem item, bool disponible) async {
    await _repository.setDisponible(
      item.id,
      disponible,
      motivo: disponible ? null : 'Agotado',
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida == null) return;
    setState(() {
      _fecha = DateTime(elegida.year, elegida.month, elegida.day);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final esHoy = _fecha.year == hoy.year &&
        _fecha.month == hoy.month &&
        _fecha.day == hoy.day;
    return FutureBuilder<_MenuData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Menú del día',
                subtitle:
                    'El cajero solo vende el menú publicado de hoy. Las bebidas siempre disponibles se venden aparte.',
                actions: [
                  if (_esAdmin)
                    OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        esHoy ? 'Hoy · ${formatDateShort(_fecha)}' : formatDateShort(_fecha),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Desayuno'),
                      selected: _tipo == 'DESAYUNO',
                      onSelected: (_) => setState(() {
                        _tipo = 'DESAYUNO';
                        _reload();
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Almuerzo'),
                      selected: _tipo == 'ALMUERZO',
                      onSelected: (_) => setState(() {
                        _tipo = 'ALMUERZO';
                        _reload();
                      }),
                    ),
                    const SizedBox(width: 12),
                    if (data?.menu != null) ...[
                      Chip(
                        label: Text('Estado: ${data!.menu!.estado}'),
                        side: BorderSide.none,
                      ),
                      Chip(
                        label: Text('${data.items.length} plato(s)'),
                        side: BorderSide.none,
                      ),
                    ],
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
              else if (data == null || data.menu == null)
                EmptyState(
                  icon: Icons.restaurant_menu_outlined,
                  title: _esAdmin
                      ? 'No hay menú para ${_tipo.toLowerCase()}'
                      : 'El menú de hoy aún no está publicado',
                  message: _esAdmin
                      ? 'Elige los productos de desayuno o almuerzo en un solo paso.'
                      : 'El administrador debe publicar el menú para poder vender.',
                  action: _esAdmin && data != null
                      ? FilledButton.icon(
                          onPressed: () => _armarMenu(data),
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text('Armar menú'),
                        )
                      : null,
                )
              else
                _menuContenido(context, data),
            ],
          ),
        );
      },
    );
  }

  Widget _menuContenido(BuildContext context, _MenuData data) {
    final menu = data.menu!;
    final scheme = Theme.of(context).colorScheme;
    final publicado = menu.estado == 'PUBLICADO';
    final cerrado = menu.estado == 'CERRADO';
    final borrador = menu.estado == 'BORRADOR';
    final puedeEditar = _esAdmin && borrador;
    final puedeAgotar = !cerrado && (publicado || borrador) &&
        (_esAdmin || (_puedeAgotar && publicado));

    if (!publicado && !_esAdmin) {
      return EmptyState(
        icon: Icons.lock_clock_outlined,
        title: 'El menú no está publicado',
        message:
            'El menú de ${_tipo.toLowerCase()} está en estado ${menu.estado.toLowerCase()}. El administrador debe publicarlo.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final angosto = esAngosto(constraints.maxWidth, limite: 760);
              final titulo = Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.restaurant_menu, color: scheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Menú de ${_tipo.toLowerCase()} · ${formatDateShort(parseSqlDate(menu.fecha))}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          cerrado
                              ? 'Cerrado. Solo consulta.'
                              : publicado
                              ? 'Publicado. Los platos se pueden vender.'
                              : 'Borrador. Elige los platos y publica cuando esté listo.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final botones = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (puedeEditar)
                    OutlinedButton.icon(
                      onPressed: () => _armarMenu(data),
                      icon: const Icon(Icons.playlist_add_check),
                      label: const Text('Editar platos'),
                    ),
                  if (puedeEditar)
                    FilledButton.icon(
                      onPressed: () => _publicar(data),
                      icon: const Icon(Icons.publish),
                      label: const Text('Publicar'),
                    ),
                  if (_esAdmin && publicado)
                    OutlinedButton.icon(
                      onPressed: () => _cerrar(data),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Cerrar menú'),
                    ),
                ],
              );
              if (angosto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titulo,
                    if (botones.children.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      botones,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: titulo),
                  if (botones.children.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    botones,
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (data.items.isEmpty)
          EmptyState(
            icon: Icons.restaurant_outlined,
            title: 'El menú está vacío',
            message: _esAdmin
                ? 'Agrega los platos que se venderán hoy.'
                : 'El administrador aún no agregó platos.',
            action: puedeEditar
                ? FilledButton.icon(
                    onPressed: () => _armarMenu(data),
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Elegir platos'),
                  )
                : null,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              final width = (constraints.maxWidth - (columns - 1) * 12) /
                  columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: data.items
                    .map(
                      (item) => SizedBox(
                        width: width,
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Color(item.categoriaColor),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.categoriaNombre,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  if (puedeEditar)
                                    IconButton(
                                      tooltip: 'Quitar',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _quitar(item),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.nombre,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(item.precio),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    item.disponible
                                        ? Icons.check_circle_outline
                                        : Icons.cancel_outlined,
                                    size: 18,
                                    color: item.disponible
                                        ? scheme.primary
                                        : scheme.error,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.disponible
                                          ? 'Disponible'
                                          : (item.motivoAgotado ?? 'Agotado'),
                                      style: TextStyle(
                                        color: item.disponible
                                            ? scheme.onSurfaceVariant
                                            : scheme.error,
                                      ),
                                    ),
                                  ),
                                  if (puedeAgotar)
                                    Switch(
                                      value: item.disponible,
                                      onChanged: (value) =>
                                          _toggleDisponible(item, value),
                                    ),
                                ],
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
    );
  }
}

class _MenuBuilderDialog extends StatefulWidget {
  const _MenuBuilderDialog({
    required this.productos,
    required this.seleccionInicial,
    required this.anteriores,
    required this.tipo,
  });

  final List<Producto> productos;
  final List<int> seleccionInicial;
  final List<int> anteriores;
  final String tipo;

  @override
  State<_MenuBuilderDialog> createState() => _MenuBuilderDialogState();
}

class _MenuBuilderDialogState extends State<_MenuBuilderDialog> {
  late final Set<int> _seleccionados;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final disponibles = widget.productos
        .map((producto) => producto.id!)
        .toSet();
    _seleccionados = widget.seleccionInicial
        .where(disponibles.contains)
        .toSet();
  }

  List<Producto> get _filtrados {
    final term = _search.trim().toLowerCase();
    return widget.productos
        .where(
          (producto) =>
              term.isEmpty || producto.nombre.toLowerCase().contains(term),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final grupos = <String, List<Producto>>{};
    for (final producto in filtrados) {
      grupos.putIfAbsent(producto.categoriaNombre, () => []).add(producto);
    }
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Menú de ${widget.tipo.toLowerCase()}'),
      content: DialogSurface(
        maxWidth: 560,
        maxHeightFactor: 0.85,
        child: Column(
          children: [
            TextField(
              decoration: appInput(
                label: 'Buscar producto',
                icon: Icons.search,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: filtrados.isEmpty
                      ? null
                      : () => setState(
                          () => _seleccionados.addAll(
                            filtrados.map((producto) => producto.id!),
                          ),
                        ),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Seleccionar todos'),
                ),
                TextButton.icon(
                  onPressed: _seleccionados.isEmpty
                      ? null
                      : () => setState(_seleccionados.clear),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Limpiar'),
                ),
                if (widget.anteriores.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _seleccionados
                        ..clear()
                        ..addAll(
                          widget.anteriores.where(
                            (id) => widget.productos.any(
                              (producto) => producto.id == id,
                            ),
                          ),
                        );
                    }),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Copiar día anterior'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: filtrados.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'Sin resultados',
                      message: 'No hay productos activos que coincidan.',
                    )
                  : ListView(
                      children: [
                        for (final grupo in grupos.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                            child: Text(
                              grupo.key,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                            ),
                          ),
                          for (final producto in grupo.value)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: _seleccionados.contains(producto.id),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _seleccionados.add(producto.id!);
                                  } else {
                                    _seleccionados.remove(producto.id);
                                  }
                                });
                              },
                              title: Text(producto.nombre),
                              subtitle: Text(
                                '${formatMoney(producto.precio)} · '
                                '${producto.esVentaDirecta ? 'Venta directa' : 'Con receta'}',
                              ),
                            ),
                        ],
                      ],
                    ),
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
          onPressed: () => Navigator.pop(context, _seleccionados.toList()),
          child: Text('Guardar (${_seleccionados.length})'),
        ),
      ],
    );
  }
}
