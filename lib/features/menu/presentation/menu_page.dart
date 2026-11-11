import 'package:flutter/material.dart';

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
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<Producto> productos;
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
  late DateTime _fecha;
  late String _tipo;
  late Future<_MenuData> _future;
  String _search = '';

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
    return _MenuData(menu: menu, items: items, productos: productos);
  }

  MenuItem? _itemDe(List<MenuItem> items, int productoId) {
    for (final item in items) {
      if (item.productoId == productoId) return item;
    }
    return null;
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
        final menu =
            data.menu ??
            await _repository.crearMenu(_fecha, _tipo, widget.usuario.id);
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
                _estadoCard(context, data),
                const SizedBox(height: 16),
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: appInput(
                      label: 'Buscar producto',
                      icon: Icons.search,
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(height: 16),
                _catalogo(context, data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _estadoCard(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final estado = menu?.estado ?? 'SIN MENÚ';
    final cerrado = menu?.cerrado == true;
    final borrador = menu?.estado == 'BORRADOR';
    final publicado = menu?.estado == 'PUBLICADO';
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
              Chip(label: Text('Estado: $estado'), side: BorderSide.none),
              Chip(
                label: Text('${data.items.length} plato(s)'),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cerrado ? 'Menú cerrado. Solo consulta.' : 'Toca un plato del menú para quitarlo. Los platos grises muestran “No disponible en el menú de hoy”; toca uno para volver a agregarlo.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (_esAdmin && menu != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (borrador)
                  FilledButton.icon(
                    onPressed: () => _publicar(data),
                    icon: const Icon(Icons.publish),
                    label: const Text('Publicar'),
                  ),
                if (publicado)
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
        .where(
          (producto) =>
              term.isEmpty || producto.nombre.toLowerCase().contains(term),
        )
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
    final editable = _esAdmin && !cerrado && !directo;
    final enMenu = item != null;
    final agotado = item != null && !item.disponible;
    final habilitado = directo || (enMenu && !agotado);
    final mensaje = directo
        ? 'Siempre disponible'
        : item == null
        ? 'No disponible en el menú de hoy · toca para agregar'
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
      habilitado: habilitado,
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
