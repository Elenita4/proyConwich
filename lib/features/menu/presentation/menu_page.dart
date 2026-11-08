import 'package:flutter/material.dart';

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
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<Producto> productos;
}

class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _repository = MenuRepository();
  final _catalog = CatalogRepository();
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
  }

  void _reload() => _future = _load();

  Future<_MenuData> _load() async {
    final menu = await _repository.getMenu(_fecha, _tipo);
    final items = menu == null
        ? <MenuItem>[]
        : await _repository.getItems(menu.id);
    final productos = _esAdmin
        ? await _catalog.getProductos(soloActivos: true)
        : <Producto>[];
    return _MenuData(menu: menu, items: items, productos: productos);
  }

  Future<void> _crear({bool duplicar = false}) async {
    try {
      if (duplicar) {
        final menu = await _repository.duplicarAnterior(
          _fecha,
          _tipo,
          widget.usuario.id,
        );
        if (menu == null) {
          if (!mounted) return;
          showAppMessage(
            context,
            'No hay un menú anterior para duplicar.',
            error: true,
          );
          return;
        }
      } else {
        await _repository.crearMenu(_fecha, _tipo, widget.usuario.id);
      }
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Menú creado. Agrega los platos.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo crear el menú: $error', error: true);
    }
  }

  Future<void> _agregarPlatos(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final existentes = data.items.map((item) => item.productoId).toSet();
    final disponibles = data.productos
        .where((producto) => !existentes.contains(producto.id))
        .toList();
    if (disponibles.isEmpty) {
      showAppMessage(
        context,
        'No hay productos activos disponibles para agregar.',
        error: true,
      );
      return;
    }
    final seleccionados = await showDialog<List<int>>(
      context: context,
      builder: (_) => _AddProductsDialog(productos: disponibles),
    );
    if (seleccionados == null || seleccionados.isEmpty) return;
    try {
      for (final id in seleccionados) {
        await _repository.agregarProducto(menu.id, id);
      }
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, '${seleccionados.length} plato(s) agregado(s).');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo agregar: $error', error: true);
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
          padding: const EdgeInsets.all(24),
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
                      ? 'Crea un menú nuevo o duplica el del día anterior.'
                      : 'El administrador debe publicar el menú para poder vender.',
                  action: _esAdmin
                      ? Wrap(
                          spacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _crear(),
                              icon: const Icon(Icons.add),
                              label: const Text('Crear menú'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _crear(duplicar: true),
                              icon: const Icon(Icons.copy_all_outlined),
                              label: const Text('Duplicar anterior'),
                            ),
                          ],
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
          child: Row(
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      cerrado
                          ? 'Cerrado. Solo consulta.'
                          : publicado
                          ? 'Publicado. Los platos se pueden vender.'
                          : 'Borrador. Agrega los platos y publica cuando esté listo.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (puedeEditar)
                OutlinedButton.icon(
                  onPressed: () => _agregarPlatos(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar platos'),
                ),
              if (puedeEditar) const SizedBox(width: 8),
              if (puedeEditar)
                FilledButton.icon(
                  onPressed: () => _publicar(data),
                  icon: const Icon(Icons.publish),
                  label: const Text('Publicar'),
                ),
              if (_esAdmin && publicado) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _cerrar(data),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar menú'),
                ),
              ],
            ],
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
                    onPressed: () => _agregarPlatos(data),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar platos'),
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

class _AddProductsDialog extends StatefulWidget {
  const _AddProductsDialog({required this.productos});

  final List<Producto> productos;

  @override
  State<_AddProductsDialog> createState() => _AddProductsDialogState();
}

class _AddProductsDialogState extends State<_AddProductsDialog> {
  final _seleccionados = <int>{};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.productos.where((producto) {
      final term = _search.trim().toLowerCase();
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList();
    return AlertDialog(
      title: const Text('Agregar platos al menú'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            TextField(
              decoration: appInput(
                label: 'Buscar producto',
                icon: Icons.search,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtrados.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'Sin resultados',
                      message: 'No hay productos activos que coincidan.',
                    )
                  : ListView.separated(
                      itemCount: filtrados.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final producto = filtrados[index];
                        return CheckboxListTile(
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
                            '${producto.categoriaNombre} · ${formatMoney(producto.precio)} · ${producto.tipo == 'DIRECTO' ? 'Directo' : 'Preparado'}',
                          ),
                        );
                      },
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
          onPressed: _seleccionados.isEmpty
              ? null
              : () => Navigator.pop(context, _seleccionados.toList()),
          child: Text('Agregar (${_seleccionados.length})'),
        ),
      ],
    );
  }
}
