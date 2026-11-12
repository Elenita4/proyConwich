import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';
import '../../../ui/producto_catalogo_card.dart';

class _MenuData {
  const _MenuData({
    required this.menu,
    required this.items,
    required this.productos,
    required this.categorias,
    required this.cajaAbierta,
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<Producto> productos;
  final List<CategoriaProducto> categorias;
  final bool cajaAbierta;
}

class MenuPage extends StatefulWidget {
  const MenuPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
    this.onAbrirCaja,
    this.flujoInicioActivo = false,
    this.onFinalizarAtajo,
  });

  final Usuario usuario;
  final int refreshToken;

  /// Atajo hacia la pantalla de Caja (flujo "Empezar el día").
  final VoidCallback? onAbrirCaja;

  /// Solo cuando el usuario llegó con el botón "Empezar el día" del tablero.
  final bool flujoInicioActivo;
  final VoidCallback? onFinalizarAtajo;

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
  String _search = '';
  int? _categoriaId;

  bool get _esAdmin => widget.usuario.puede(Permiso.menu);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    _tipo = MenuRepository.tipoMenu;
    _reload();
  }

  @override
  void didUpdateWidget(MenuPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
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
    final productos = await _catalog.getProductos(soloActivos: true);
    final categorias = await _catalog.getCategorias();
    final caja = await _cash.getCajaAbierta();
    return _MenuData(
      menu: menu,
      items: items,
      productos: productos,
      categorias: categorias,
      cajaAbierta: caja != null,
    );
  }

  MenuItem? _itemDe(List<MenuItem> items, int productoId) {
    for (final item in items) {
      if (item.productoId == productoId) return item;
    }
    return null;
  }

  /// Crea el menú del día empezando con los platos del menú anterior para que
  /// solo se ajuste lo que cambie. Si no hay menú anterior queda vacío.
  Future<MenuDia> _crearConAnterior() async {
    final desdeAnterior = await _repository.duplicarAnterior(
      _fecha,
      _tipo,
      widget.usuario.id,
    );
    return desdeAnterior ??
        await _repository.crearMenu(_fecha, _tipo, widget.usuario.id);
  }

  Future<void> _crearMenu() async {
    try {
      final previos = await _repository.getProductosMenuAnterior(
        _fecha,
        _tipo,
      );
      await _crearConAnterior();
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        previos.isEmpty
            ? 'Menú creado vacío. Elige los platos del día.'
            : 'Menú creado con ${previos.length} plato(s) del día anterior. '
                  'Ajusta lo que haga falta o usa "Limpiar".',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo crear el menú: $error', error: true);
    }
  }

  Future<void> _limpiar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Limpiar menú',
      message:
          'Se quitarán todos los platos del menú de hoy y podrás armarlo desde cero.',
      confirmLabel: 'Limpiar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.reemplazarItems(menu.id, []);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú limpiado. Elige los platos del día.');
  }

  Future<void> _toggleProducto(_MenuData data, Producto producto) async {
    if (!_esAdmin || producto.id == null) return;
    if (data.menu?.cerrado == true) {
      showAppMessage(context, 'El menú está cerrado.', error: true);
      return;
    }
    final item = _itemDe(data.items, producto.id!);
    try {
      if (item != null) {
        await _repository.quitarItem(item.id);
        if (!mounted) return;
        setState(_reload);
        showAppMessage(
          context,
          '${producto.nombre} ya no está en el menú de hoy.',
        );
      } else {
        final menu = data.menu ?? await _crearConAnterior();
        await _repository.agregarProducto(menu.id, producto.id!);
        if (!mounted) return;
        setState(_reload);
        showAppMessage(context, '${producto.nombre} agregado al menú de hoy.');
      }
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo actualizar el menú: $error',
        error: true,
      );
    }
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

  Future<void> _habilitar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    if (data.items.isEmpty) {
      showAppMessage(
        context,
        'Agrega al menos un plato antes de habilitar.',
        error: true,
      );
      return;
    }
    await _repository.habilitar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú habilitado. Ya se puede vender.');
  }

  Future<void> _cerrar(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar menú',
      message: 'El menú quedará cerrado y no se podrán registrar más ventas de estos platos.',
      confirmLabel: 'Cerrar menú',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.cerrar(menu.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Menú cerrado.');
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
    final esHoy =
        _fecha.year == hoy.year &&
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
                subtitle: 'Igual que en Ventas: toca un plato para quitarlo o volver a agregarlo.',
                actions: [
                  if (_esAdmin)
                    OutlinedButton.icon(
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        esHoy
                            ? 'Hoy · ${formatDateShort(_fecha)}'
                            : formatDateShort(_fecha),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (data == null)
                const SizedBox.shrink()
              else ...[
                if (widget.flujoInicioActivo && !data.cajaAbierta) ...[
                  _atajoCaja(context),
                  const SizedBox(height: 16),
                ],
                _estadoCard(context, data),
                const SizedBox(height: 16),
                _filtros(context, data),
                const SizedBox(height: 16),
                _catalogo(context, data),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Atajo del flujo "Empezar el día": solo aparece si se usó ese botón y la
  /// caja todavía no está abierta.
  Widget _atajoCaja(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flag_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paso 2: abre la caja para iniciar el día',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Cuando el menú esté listo, sigue a Caja.'),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: widget.onAbrirCaja == null
                ? null
                : () {
                    widget.onFinalizarAtajo?.call();
                    widget.onAbrirCaja!();
                  },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  String _estadoLabel(String? estado) {
    switch (estado) {
      case 'HABILITADO':
        return 'Habilitado';
      case 'CERRADO':
        return 'Cerrado';
      case 'BORRADOR':
        return 'Borrador';
      default:
        return 'Sin menú';
    }
  }

  /// Buscador + chips de categorías (con su color) para filtrar el catálogo.
  Widget _filtros(BuildContext context, _MenuData data) {
    final relevantes = <int>{};
    for (final producto in data.productos) {
      relevantes.add(producto.categoriaId);
      if (producto.categoriaParentId != null) {
        relevantes.add(producto.categoriaParentId!);
      }
    }
    final categorias = data.categorias
        .where(
          (categoria) => categoria.id != null && relevantes.contains(categoria.id),
        )
        .toList()
      ..sort((a, b) {
        if (a.orden != b.orden) return a.orden.compareTo(b.orden);
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: appInput(label: 'Buscar producto', icon: Icons.search),
            onChanged: (value) => setState(() => _search = value),
          ),
          if (categorias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: _categoriaId == null,
                  onSelected: (_) => setState(() => _categoriaId = null),
                ),
                ...categorias.map(
                  (categoria) => ChoiceChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(categoria.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(categoria.nombre),
                    selected: _categoriaId == categoria.id,
                    onSelected: (_) =>
                        setState(() => _categoriaId = categoria.id),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  Widget _estadoCard(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final cerrado = menu?.cerrado == true;
    final borrador = menu?.estado == 'BORRADOR';
    final habilitado = menu?.habilitado == true;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Chip(
                avatar: Icon(Icons.restaurant, size: 18),
                label: Text('MENÚ DE ALMUERZO'),
                side: BorderSide.none,
              ),
              Chip(
                label: Text('Estado: ${_estadoLabel(menu?.estado)}'),
                side: BorderSide.none,
              ),
              Chip(
                label: Text('${data.items.length} plato(s)'),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cerrado
                ? 'Menú cerrado. Solo consulta.'
                : 'Toca un plato para agregarlo o quitarlo. Los platos con check verde están en el menú de hoy; los rojos están agotados y se reactivan con el control de la tarjeta.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (_esAdmin) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (menu == null)
                  FilledButton.icon(
                    onPressed: _crearMenu,
                    icon: const Icon(Icons.history),
                    label: const Text('Crear menú con los platos de ayer'),
                  ),
                if (borrador)
                  FilledButton.icon(
                    onPressed: () => _habilitar(data),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Habilitar'),
                  ),
                if (menu != null && !cerrado && data.items.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _limpiar(data),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
                if (habilitado)
                  OutlinedButton.icon(
                    onPressed: () => _cerrar(data),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Cerrar menú'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _MenuData data) {
    final term = _search.trim().toLowerCase();
    final filtrados = data.productos
        .where((producto) {
          if (_categoriaId != null &&
              producto.categoriaId != _categoriaId &&
              producto.categoriaParentId != _categoriaId) {
            return false;
          }
          return term.isEmpty || producto.nombre.toLowerCase().contains(term);
        })
        .toList();
    if (filtrados.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Sin productos',
        message: 'No hay productos activos que coincidan con la búsqueda.',
      );
    }

    final directos =
        filtrados
            .where(
              (producto) =>
                  producto.categoriaSiempreDisponible ||
                  producto.esVentaDirecta,
            )
            .toList()
          ..sort(_compararProductos);
    final menu = filtrados
        .where(
          (producto) =>
              !producto.categoriaSiempreDisponible && !producto.esVentaDirecta,
        )
        .toList();

    final grupos = <String, Map<String, List<Producto>>>{};
    for (final producto in menu) {
      final padre = (producto.categoriaParentNombre ?? producto.categoriaNombre)
          .toUpperCase();
      final sub = producto.categoriaParentNombre == null
          ? ''
          : producto.categoriaNombre.toUpperCase();
      grupos
          .putIfAbsent(padre, () => {})
          .putIfAbsent(sub, () => [])
          .add(producto);
    }
    final padres = grupos.keys.toList()..sort();

    final children = <Widget>[];
    for (final padre in padres) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            padre,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
      final subcategorias = grupos[padre]!.keys.toList()..sort();
      for (final sub in subcategorias) {
        if (sub.isNotEmpty && sub != padre) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                sub,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        final productos = grupos[padre]![sub]!..sort(_compararProductos);
        children.add(_gridProductos(context, data, productos));
        children.add(const SizedBox(height: 16));
      }
    }

    if (directos.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'SIEMPRE DISPONIBLES',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ),
      );
      children.add(_gridProductos(context, data, directos, directo: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  int _compararProductos(Producto a, Producto b) =>
      a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());

  Widget _gridProductos(
    BuildContext context,
    _MenuData data,
    List<Producto> productos, {
    bool directo = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: productos
              .map(
                (producto) => SizedBox(
                  width: width,
                  child: _tarjeta(context, data, producto, directo: directo),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _tarjeta(
    BuildContext context,
    _MenuData data,
    Producto producto, {
    required bool directo,
  }) {
    final item = _itemDe(data.items, producto.id!);
    final cerrado = data.menu?.cerrado == true;
    final agotado = item != null && !item.disponible;
    final seleccionado = item != null && !agotado;
    // El plato agotado queda bloqueado: se reactiva con el control de la tarjeta.
    final editable = _esAdmin && !cerrado && !directo && !agotado;
    final mensaje = directo
        ? 'Siempre disponible'
        : item == null
        ? 'Toca para agregar'
        : agotado
        ? (item.motivoAgotado ?? 'Agotado')
        : 'En el menú de hoy · toca para quitar';

    return ProductoCatalogoCard(
      nombre: producto.nombre,
      categoria: producto.categoriaEtiqueta,
      precio: producto.precio,
      color: producto.categoriaColor,
      imagen: producto.imagen,
      esDirecto: producto.esDirecto,
      stock: producto.stock,
      habilitado: true,
      seleccionado: seleccionado,
      agotado: agotado,
      mensaje: mensaje,
      onTap: editable ? () => _toggleProducto(data, producto) : null,
      accion: item != null && !directo && _esAdmin && !cerrado
          ? IconButton(
              tooltip: item.disponible ? 'Marcar agotado' : 'Marcar disponible',
              visualDensity: VisualDensity.compact,
              onPressed: () => _toggleDisponible(item, !item.disponible),
              icon: Icon(
                item.disponible ? Icons.block : Icons.check_circle_outline,
                size: 18,
              ),
            )
          : null,
    );
  }
}
