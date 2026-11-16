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
    required this.combos,
    required this.hayCombosLegacy,
    required this.productos,
    required this.categorias,
    required this.cajaAbierta,
  });

  final MenuDia? menu;
  final List<MenuItem> items;
  final List<MenuCombo> combos;
  final bool hayCombosLegacy;
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
  bool _editando = false;
  bool _guardando = false;

  // Estado local durante la edición: se aplica a la BD recién al pulsar
  // "Listo", así seleccionar/deseleccionar platos no recarga la página ni
  // pierde el scroll.
  Set<int> _selLocal = {};
  int? _sopaLocal;
  Set<int> _agotadosLocal = {};

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
    var menu = await _repository.getMenu(_fecha, _tipo);
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final esFuturoOHoy = !_fecha.isBefore(inicioHoy);
    if (menu == null && esFuturoOHoy) {
      try {
        menu = await _repository.duplicarAnterior(
          _fecha,
          _tipo,
          widget.usuario.id,
        );
      } catch (_) {
        // Si no se puede copiar el menú anterior, la pantalla sigue vacía.
      }
    }
    // El menú ya no se cierra; si viene cerrado de una versión anterior se
    // vuelve a publicar para conservar la venta del día.
    if (menu != null && menu.cerrado && esFuturoOHoy) {
      await _repository.habilitar(menu.id);
      menu = await _repository.getMenu(_fecha, _tipo);
    }
    final items = menu == null
        ? <MenuItem>[]
        : await _repository.getItems(menu.id);
    // Los combos de versiones anteriores se conservan como historial, pero
    // no forman parte del nuevo flujo del menú.
    const combos = <MenuCombo>[];
    final hayCombosLegacy = menu != null
        ? await _repository.tieneCombosLegacy(menu.id)
        : false;
    final productos = await _catalog.getProductos(soloActivos: true);
    final categorias = await _catalog.getCategorias();
    final caja = await _cash.getCajaAbierta();
    return _MenuData(
      menu: menu,
      items: items,
      combos: combos,
      hayCombosLegacy: hayCombosLegacy,
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

  /// Inicializa el estado local de edición a partir de los items actuales.
  void _initLocalDeItems(List<MenuItem> items) {
    _selLocal = items
        .where((item) => !item.esSopa)
        .map((item) => item.productoId)
        .toSet();
    MenuItem? sopa;
    for (final item in items) {
      if (item.esSopa) {
        sopa = item;
        break;
      }
    }
    _sopaLocal = sopa?.productoId;
    _agotadosLocal = items
        .where((item) => !item.disponible)
        .map((item) => item.productoId)
        .toSet();
  }

  void _iniciarEdicion(_MenuData data) {
    _initLocalDeItems(data.items);
    setState(() => _editando = true);
  }

  /// Aplica los cambios locales a la base y recarga una sola vez.
  Future<void> _finalizarEdicion(_MenuData data) async {
    setState(() => _guardando = true);
    try {
      final menu = data.menu ?? await _crearConAnterior();

      // Sopa del día.
      final sopasActuales = data.items.where((item) => item.esSopa).toList();
      final sopaActualId = sopasActuales.isEmpty
          ? null
          : sopasActuales.first.productoId;
      if (_sopaLocal != sopaActualId) {
        if (_sopaLocal == null) {
          for (final sopa in sopasActuales) {
            await _repository.quitarItem(sopa.id);
          }
        } else {
          await _repository.agregarProducto(menu.id, _sopaLocal!);
        }
      }

      // Platos (no sopa) a agregar o quitar.
      final actualesIds = data.items
          .where((item) => !item.esSopa)
          .map((item) => item.productoId)
          .toSet();
      final paraAgregar = _selLocal.difference(actualesIds);
      final paraQuitar = actualesIds.difference(_selLocal);
      for (final id in paraAgregar) {
        await _repository.agregarProducto(menu.id, id);
      }
      for (final item in data.items) {
        if (item.esSopa) continue;
        if (paraQuitar.contains(item.productoId)) {
          await _repository.quitarItem(item.id);
        }
      }

      // Agotados, contra el estado ya aplicado.
      final itemsAplicados = await _repository.getItems(menu.id);
      for (final item in itemsAplicados) {
        final disponible = !_agotadosLocal.contains(item.productoId);
        if (item.disponible != disponible) {
          await _repository.setDisponible(
            item.id,
            disponible,
            motivo: disponible ? null : 'Agotado',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _guardando = false;
        _editando = false;
        _reload();
      });
      showAppMessage(context, 'Menú actualizado.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      showAppMessage(
        context,
        'No se pudo guardar el menú: $error',
        error: true,
      );
    }
  }

  /// Items efectivos del menú: durante la edición usa el estado local (aún no
  /// guardado); fuera de edición usa lo que está en la base.
  List<MenuItem> _itemsEfectivos(_MenuData data) {
    if (!_editando) return data.items;
    final productosPorId = <int, Producto>{
      for (final producto in data.productos)
        if (producto.id != null) producto.id!: producto,
    };
    final resultado = <MenuItem>[];
    final vistos = <int>{};
    if (_sopaLocal != null) {
      final producto = productosPorId[_sopaLocal];
      if (producto != null) {
        resultado.add(_sintetico(producto));
        vistos.add(producto.id!);
      }
    }
    for (final id in _selLocal) {
      if (vistos.contains(id)) continue;
      final producto = productosPorId[id];
      if (producto != null) {
        resultado.add(_sintetico(producto));
        vistos.add(id);
      }
    }
    return resultado;
  }

  MenuItem _sintetico(Producto producto) => MenuItem(
    id: 0,
    menuDiaId: 0,
    productoId: producto.id!,
    nombre: producto.nombre,
    precio: producto.precio,
    categoriaNombre: producto.categoriaNombre,
    categoriaColor: producto.categoriaColor,
    tipoProducto: producto.tipo,
    disponible: !_agotadosLocal.contains(producto.id),
    motivoAgotado: _agotadosLocal.contains(producto.id) ? 'Agotado' : null,
    orden: 0,
  );

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
      final previos = await _repository.getProductosMenuAnterior(_fecha, _tipo);
      final menu = await _crearConAnterior();
      final items = await _repository.getItems(menu.id);
      if (!mounted) return;
      setState(() {
        _initLocalDeItems(items);
        _editando = true;
        _reload();
      });
      showAppMessage(
        context,
        previos.isEmpty
            ? 'Menú creado vacío. Elige la sopa y los platos del día.'
            : 'Menú creado con ${previos.length} producto(s) del día anterior. '
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
      message: 'Se quitarán la sopa y los productos del menú de hoy. Las ventas anteriores no se borran.',
      confirmLabel: 'Limpiar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.limpiarMenu(menu.id);
    if (!mounted) return;
    setState(() {
      _selLocal.clear();
      _sopaLocal = null;
      _agotadosLocal.clear();
      _reload();
    });
    showAppMessage(context, 'Menú limpiado. Elige la sopa y los productos.');
  }

  void _toggleProducto(_MenuData data, Producto producto) {
    if (!_esAdmin || producto.id == null || _guardando) return;
    setState(() {
      if (!_selLocal.remove(producto.id!)) {
        _selLocal.add(producto.id!);
      } else {
        // Al quitar un plato también se limpia su estado de agotado.
        _agotadosLocal.remove(producto.id!);
      }
    });
  }

  void _seleccionarSopa(_MenuData data, int productoId) {
    if (!_esAdmin || !_editando || _guardando) return;
    setState(() {
      _sopaLocal = productoId == -1 ? null : productoId;
    });
  }

  Future<void> _guardarPrecioAlmuerzo(_MenuData data, String texto) async {
    if (!_esAdmin || !_editando) return;
    final menu = data.menu ?? await _crearConAnterior();
    if (!mounted) return;
    final precio = texto.trim().isEmpty ? null : parseAmount(texto);
    if (precio != null && precio < 0) {
      showAppMessage(context, 'El precio no puede ser negativo.', error: true);
      return;
    }
    await _repository.setPrecioAlmuerzo(menu.id, precio);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(
      context,
      precio == null
          ? 'El almuerzo se venderá como plato + sopa.'
          : 'Precio del almuerzo fijado en ${formatMoney(precio)}.',
    );
  }

  void _toggleCategoria(
    _MenuData data,
    List<Producto> productos, {
    required bool seleccionar,
  }) {
    if (!_esAdmin || !_editando || _guardando || productos.isEmpty) return;
    setState(() {
      if (seleccionar) {
        _selLocal.addAll(productos.map((producto) => producto.id!));
      } else {
        for (final producto in productos) {
          _selLocal.remove(producto.id);
          _agotadosLocal.remove(producto.id);
        }
      }
    });
  }

  Future<void> _toggleDisponible(MenuItem item, bool disponible) async {
    if (_editando) {
      setState(() {
        if (disponible) {
          _agotadosLocal.remove(item.productoId);
        } else {
          _agotadosLocal.add(item.productoId);
        }
      });
      return;
    }
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
        'Agrega al menos una sopa o un plato antes de publicar.',
        error: true,
      );
      return;
    }
    await _repository.habilitar(menu.id);
    if (!mounted) return;
    setState(() {
      _editando = false;
      _reload();
    });
    showAppMessage(context, 'Menú abierto. Ya se puede vender.');
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
      // Al cambiar de día se sale del modo edición para no mezclar estados.
      _editando = false;
      _selLocal.clear();
      _sopaLocal = null;
      _agotadosLocal.clear();
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
                subtitle: 'Pulsa "Editar" para elegir los platos del menú de hoy con un toque.',
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
                _sopaDelDia(context, data),
                const SizedBox(height: 16),
                _filtros(context, data),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final catalogo = _catalogo(context, data);
                    final panel = _menuLateral(context, data);
                    if (constraints.maxWidth >= 1100) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: catalogo),
                          const SizedBox(width: 16),
                          SizedBox(width: 300, child: panel),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [catalogo, const SizedBox(height: 16), panel],
                    );
                  },
                ),
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
    final boton = FilledButton.icon(
      onPressed: widget.onAbrirCaja == null
          ? null
          : () {
              widget.onFinalizarAtajo?.call();
              widget.onAbrirCaja!();
            },
      icon: const Icon(Icons.arrow_forward),
      label: const Text('Abrir caja'),
    );
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icono = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flag_outlined, color: scheme.primary),
          );
          const texto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paso 2: abre la caja para iniciar el día',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Cuando el menú esté listo, sigue a Caja.'),
            ],
          );
          if (esAngosto(constraints.maxWidth, limite: 560)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icono,
                    const SizedBox(width: 14),
                    const Expanded(child: texto),
                  ],
                ),
                const SizedBox(height: 12),
                boton,
              ],
            );
          }
          return Row(
            children: [
              icono,
              const SizedBox(width: 14),
              const Expanded(child: texto),
              const SizedBox(width: 12),
              boton,
            ],
          );
        },
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

  Widget _sopaDelDia(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final sopas =
        data.productos
            .where(
              (producto) =>
                  !producto.esCompuesto &&
                  MenuRepository.esCategoriaSopa(producto.categoriaNombre),
            )
            .toList()
          ..sort(_compararProductos);
    final int? sopaIdEfectivo;
    final bool sopaAgotada;
    if (_editando) {
      sopaIdEfectivo = _sopaLocal;
      sopaAgotada = _sopaLocal != null && _agotadosLocal.contains(_sopaLocal);
    } else {
      final seleccionadas = data.items.where((item) => item.esSopa).toList();
      final sopaActual = seleccionadas.isEmpty ? null : seleccionadas.first;
      sopaIdEfectivo = sopaActual?.productoId;
      sopaAgotada = sopaActual != null && !sopaActual.disponible;
    }
    Producto? sopaProducto;
    for (final producto in sopas) {
      if (producto.id == sopaIdEfectivo) {
        sopaProducto = producto;
        break;
      }
    }
    final sopaActual = sopaProducto == null
        ? null
        : MenuItem(
            id: 0,
            menuDiaId: 0,
            productoId: sopaProducto.id!,
            nombre: sopaProducto.nombre,
            precio: sopaProducto.precio,
            categoriaNombre: sopaProducto.categoriaNombre,
            categoriaColor: sopaProducto.categoriaColor,
            tipoProducto: sopaProducto.tipo,
            disponible: !sopaAgotada,
            motivoAgotado: sopaAgotada ? 'Agotado' : null,
            orden: 0,
          );
    final valorActual =
        sopaIdEfectivo != null && sopas.any((sopa) => sopa.id == sopaIdEfectivo)
        ? sopaIdEfectivo
        : -1;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.soup_kitchen_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sopa del día',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (sopaActual != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_esAdmin && _editando)
                      IconButton(
                        tooltip: sopaActual.disponible
                            ? 'Marcar sopa agotada'
                            : 'Marcar sopa disponible',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleDisponible(
                          sopaActual,
                          !sopaActual.disponible,
                        ),
                        icon: Icon(
                          sopaActual.disponible
                              ? Icons.block
                              : Icons.check_circle_outline,
                          size: 18,
                        ),
                      ),
                    Text(
                      formatMoney(sopaActual.precio),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (sopas.isEmpty)
            Text(
              'No hay sopas activas en Productos.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            DropdownButtonFormField<int>(
              initialValue: valorActual,
              isExpanded: true,
              decoration: appInput(label: 'Elige una sopa (opcional)'),
              items: [
                const DropdownMenuItem<int>(
                  value: -1,
                  child: Text('Hoy no habrá sopa'),
                ),
                for (final sopa in sopas)
                  DropdownMenuItem<int>(
                    value: sopa.id!,
                    child: Text('${sopa.nombre} · ${formatMoney(sopa.precio)}'),
                  ),
              ],
              onChanged: _esAdmin && _editando && !_guardando
                  ? (value) {
                      if (value != null) _seleccionarSopa(data, value);
                    }
                  : null,
            ),
          if (_editando)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Solo se puede elegir una. Los completos usarán esta sopa.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (_esAdmin && _editando && data.menu != null) ...[
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('precio-almuerzo-${data.menu!.precioAlmuerzo}'),
              initialValue: data.menu!.precioAlmuerzo == null
                  ? ''
                  : data.menu!.precioAlmuerzo!.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [decimalAmountInputFormatter],
              decoration: appInput(
                label: 'Precio del almuerzo (completo)',
                hint: 'Vacío = plato + sopa',
                icon: Icons.sell_outlined,
              ),
              onFieldSubmitted: (value) =>
                  _guardarPrecioAlmuerzo(data, value),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Todos los completos se venderán a este precio fijo.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ] else if (data.menu?.precioAlmuerzo != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Almuerzo completo: '
                '${formatMoney(data.menu!.precioAlmuerzo!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Buscador + chips de categorías (con su color) para filtrar el catálogo.
  Widget _filtros(BuildContext context, _MenuData data) {
    final relevantes = <int>{};
    for (final producto in data.productos) {
      if (producto.esCompuesto ||
          MenuRepository.esCategoriaSopa(producto.categoriaNombre) ||
          producto.categoriaSiempreDisponible ||
          producto.esVentaDirecta) {
        continue;
      }
      relevantes.add(producto.categoriaId);
    }
    final categorias =
        data.categorias
            .where(
              (categoria) =>
                  categoria.id != null && relevantes.contains(categoria.id),
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
    final habilitado = menu?.habilitado == true;
    final items = _itemsEfectivos(data);
    final cantidadSopas = items.where((item) => item.esSopa).length;
    final cantidadPlatos = items
        .where(
          (item) => MenuRepository.esCategoriaPlatoSuelto(item.categoriaNombre),
        )
        .length;
    final cantidadOtros = items.length - cantidadSopas - cantidadPlatos;
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
                label: Text(
                  'Sopa $cantidadSopas/1 · $cantidadPlatos almuerzo(s) · '
                  '$cantidadOtros otro(s)',
                ),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _editando
                ? 'Elige una sopa y marca los productos de hoy individualmente o con “Todos” en cada categoría. Solo PLATOS SUELTOS puede ser completo.'
                : 'Pulsa "Editar" para cambiar la sopa y los productos. Los seleccionados están en el menú de hoy; los rojos están agotados.',
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
                    label: const Text('Crear menú con lo de ayer'),
                  ),
                if (menu != null && !_editando)
                  OutlinedButton.icon(
                    onPressed: () => _iniciarEdicion(data),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                if (menu != null && _editando)
                  OutlinedButton.icon(
                    onPressed: () => _finalizarEdicion(data),
                    icon: const Icon(Icons.done_all_outlined),
                    label: const Text('Listo'),
                  ),
                if (_editando &&
                    (_itemsEfectivos(data).isNotEmpty ||
                        data.hayCombosLegacy))
                  OutlinedButton.icon(
                    onPressed: () => _limpiar(data),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpiar'),
                  ),
                if (menu != null && !habilitado && !_editando)
                  FilledButton.icon(
                    onPressed: () => _habilitar(data),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Publicar menú'),
                  ),
                if (menu != null && !_editando)
                  OutlinedButton.icon(
                    onPressed: () => _programarDias(data),
                    icon: const Icon(Icons.event_repeat_outlined),
                    label: const Text('Programar días'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Vista antigua de combos: se conserva solo como referencia al migrar datos,
  // pero el flujo nuevo no la muestra ni crea productos compuestos.
  // ignore: unused_element
  Widget _combosSection(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dinner_dining, color: scheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Almuerzos y combos',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              if (_esAdmin)
                FilledButton.tonalIcon(
                  onPressed: () => _abrirConstructorCombo(data),
                  icon: const Icon(Icons.add),
                  label: const Text('Armar almuerzo'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Selecciona uno o más productos. El precio sugerido baja un 10% desde el segundo producto, pero puedes cambiarlo.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (data.combos.isEmpty)
            Text(
              'Todavía no hay almuerzos armados para este día.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth < 300
                    ? constraints.maxWidth
                    : 300.0;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: data.combos
                      .map(
                        (combo) =>
                            _comboCard(context, data, combo, ancho: ancho),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _comboCard(
    BuildContext context,
    _MenuData data,
    MenuCombo combo, {
    required double ancho,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final disponible = combo.disponible;
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: disponible
            ? Colors.green.shade700.withValues(alpha: 0.08)
            : scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: disponible ? Colors.green.shade700 : scheme.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  combo.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                disponible ? Icons.check_circle : Icons.block,
                size: 18,
                color: disponible ? Colors.green.shade700 : scheme.error,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            combo.componentes
                .map((componente) => componente.nombre)
                .join(' + '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatMoney(combo.precio),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              if (combo.sumaComponentes > combo.precio)
                Flexible(
                  child: Text(
                    'antes ${formatMoney(combo.sumaComponentes)}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
            ],
          ),
          if (_esAdmin)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: disponible ? 'Marcar agotado' : 'Marcar disponible',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleComboDisponible(combo),
                  icon: Icon(
                    disponible ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Editar almuerzo',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _abrirConstructorCombo(data, combo: combo),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Quitar del menú',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _quitarCombo(combo),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _MenuData data) {
    final term = _search.trim().toLowerCase();
    final productosMenu = data.productos.where((producto) {
      return !producto.esCompuesto &&
          !producto.categoriaSiempreDisponible &&
          !producto.esVentaDirecta &&
          !MenuRepository.esCategoriaSopa(producto.categoriaNombre);
    }).toList();
    final filtrados = productosMenu.where((producto) {
      if (_categoriaId != null && producto.categoriaId != _categoriaId) {
        return false;
      }
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList();
    final directos = data.productos.where((producto) {
      if (!producto.categoriaSiempreDisponible && !producto.esVentaDirecta) {
        return false;
      }
      if (_categoriaId != null && producto.categoriaId != _categoriaId) {
        return false;
      }
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList()..sort(_compararProductos);
    if (filtrados.isEmpty && directos.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Sin productos',
        message: 'No hay productos activos que coincidan con la búsqueda.',
      );
    }

    final grupos = <int, List<Producto>>{};
    for (final producto in filtrados) {
      grupos.putIfAbsent(producto.categoriaId, () => []).add(producto);
    }
    final ordenCategorias = {
      for (final categoria in data.categorias)
        if (categoria.id != null) categoria.id!: categoria,
    };
    final categorias = grupos.keys.toList()
      ..sort((a, b) {
        final ordenA = ordenCategorias[a]?.orden ?? 999;
        final ordenB = ordenCategorias[b]?.orden ?? 999;
        if (ordenA != ordenB) return ordenA.compareTo(ordenB);
        return (ordenCategorias[a]?.nombre ?? '').compareTo(
          ordenCategorias[b]?.nombre ?? '',
        );
      });

    final children = <Widget>[];
    final idsEnMenu = _editando
        ? _selLocal
        : data.items.map((item) => item.productoId).toSet();
    for (final categoriaId in categorias) {
      final categoria = ordenCategorias[categoriaId];
      final productosVisibles = grupos[categoriaId]!..sort(_compararProductos);
      final todosCategoria =
          productosMenu
              .where((producto) => producto.categoriaId == categoriaId)
              .toList()
            ..sort(_compararProductos);
      final todoSeleccionado =
          todosCategoria.isNotEmpty &&
          todosCategoria.every((producto) => idsEnMenu.contains(producto.id));
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  categoria?.nombre.toUpperCase() ?? 'PRODUCTOS',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (_esAdmin && _editando)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Todos'),
                    Checkbox(
                      key: ValueKey('seleccionar-categoria-$categoriaId'),
                      value: todoSeleccionado,
                      onChanged: _guardando
                          ? null
                          : (valor) => _toggleCategoria(
                              data,
                              todosCategoria,
                              seleccionar: valor ?? false,
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
      children.add(_gridProductos(context, data, productosVisibles));
      children.add(const SizedBox(height: 16));
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

  /// Lista lateral con los platos elegidos hoy (foto · producto · precio) y el
  /// botón para abrir el menú.
  Widget _menuLateral(BuildContext context, _MenuData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final habilitado = menu?.habilitado == true;
    final items = _itemsEfectivos(data);
    final sopasDelMenu = items.where((item) => item.esSopa).toList();
    final precioSopa = sopasDelMenu.isEmpty ? null : sopasDelMenu.first.precio;
    final productosPorId = {
      for (final producto in data.productos) producto.id: producto,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MENÚ DE HOY',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                '${items.length} producto(s)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty && data.combos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aún no has elegido el menú.\nSelecciona una sopa y los productos de hoy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: _miniatura(productosPorId[item.productoId]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.esSopa
                                ? 'Sopa del día'
                                : MenuRepository.esCategoriaPlatoSuelto(
                                    item.categoriaNombre,
                                  )
                                ? precioSopa == null
                                      ? 'Suelto · ${formatMoney(item.precio)}'
                                      : 'Suelto ${formatMoney(item.precio)} · '
                                            'Completo ${formatMoney(menu?.precioAlmuerzo ?? (item.precio + precioSopa))}'
                                : 'Disponible hoy',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (!item.disponible)
                            Text(
                              item.motivoAgotado ?? 'Agotado',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.error),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(item.precio),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          for (final combo in data.combos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: combo.imagen != null
                          ? Image.memory(
                              combo.imagen!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(
                              color: Color(combo.categoriaColor)
                                  .withValues(alpha: 0.15),
                              child: Icon(
                                Icons.dinner_dining,
                                size: 20,
                                color: Color(combo.categoriaColor),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          combo.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          combo.componentes
                              .map((componente) => componente.nombre)
                              .join(' + '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (!combo.disponible)
                          Text(
                            'Agotado',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.error),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(combo.precio),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (menu == null)
            FilledButton.icon(
              onPressed: () => _crearMenu(),
              icon: const Icon(Icons.history),
              label: const Text('Crear menú con lo de ayer'),
            )
          else if (_editando)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pulsa "Listo" para guardar los cambios del menú.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else if (!habilitado)
            FilledButton.icon(
              onPressed: () => _habilitar(data),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Publicar menú'),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'MENÚ ABIERTO',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniatura(Producto? producto) {
    if (producto == null) {
      return Container(
        color: const Color(0xFFF3E9D9), // Crema
        child: const Icon(Icons.restaurant, size: 20),
      );
    }
    if (producto.imagen != null) {
      return Image.memory(
        producto.imagen!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: Color(producto.categoriaColor).withValues(alpha: 0.15),
      child: Icon(
        producto.esDirecto ? Icons.local_drink_outlined : Icons.restaurant,
        size: 20,
        color: Color(producto.categoriaColor),
      ),
    );
  }

  /// Atajo para elegir el almuerzo del día: una sopa y/o un segundo.
  int? _categoriaParaCombo(_MenuData data) {
    for (final categoria in data.categorias) {
      if (categoria.nombre == 'PLATOS SUELTOS') return categoria.id;
    }
    for (final categoria in data.categorias) {
      if (categoria.id != null) return categoria.id;
    }
    return null;
  }

  Future<void> _abrirConstructorCombo(
    _MenuData data, {
    MenuCombo? combo,
  }) async {
    final categoriaId = _categoriaParaCombo(data);
    if (categoriaId == null) {
      showAppMessage(
        context,
        'Crea al menos una categoría en Productos antes de armar un almuerzo.',
        error: true,
      );
      return;
    }
    final disponibles = data.productos
        .where((producto) => producto.id != combo?.productoId)
        .toList();
    final resultado = await showDialog<_ComboInput>(
      context: context,
      builder: (_) => _ComboBuilderDialog(productos: disponibles, combo: combo),
    );
    if (resultado == null || resultado.componenteIds.isEmpty) return;
    try {
      final menu = data.menu ?? await _crearConAnterior();
      if (combo == null) {
        final productoId = await _catalog.crearProductoCompuesto(
          nombre: resultado.nombre,
          categoriaId: categoriaId,
          precio: resultado.precio,
          componenteIds: resultado.componenteIds,
        );
        await _repository.agregarCombo(
          menuDiaId: menu.id,
          productoId: productoId,
          nombre: resultado.nombre,
          precio: resultado.precio,
        );
      } else {
        await _catalog.actualizarProductoCompuesto(
          productoId: combo.productoId,
          nombre: resultado.nombre,
          precio: resultado.precio,
          componenteIds: resultado.componenteIds,
        );
        await _repository.actualizarCombo(
          combo.id,
          nombre: resultado.nombre,
          precio: resultado.precio,
        );
      }
      if (!mounted) return;
      setState(_reload);
      showAppMessage(
        context,
        combo == null ? 'Almuerzo agregado al menú.' : 'Almuerzo actualizado.',
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo guardar el almuerzo: $error',
        error: true,
      );
    }
  }

  Future<void> _toggleComboDisponible(MenuCombo combo) async {
    await _repository.setComboDisponible(combo.id, !combo.disponible);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _quitarCombo(MenuCombo combo) async {
    final confirmado = await confirmAction(
      context,
      title: 'Quitar almuerzo',
      message: '${combo.nombre} ya no aparecerá en el menú de hoy.',
      confirmLabel: 'Quitar',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.quitarCombo(combo.id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _programarDias(_MenuData data) async {
    final menu = data.menu;
    if (menu == null) return;
    final dias = await showDialog<int>(
      context: context,
      builder: (context) {
        var dias = 3;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Programar menú'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Se copiará esta configuración a los siguientes días que '
                  'todavía no tengan un menú programado.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: dias,
                  decoration: appInput(label: 'Días a programar'),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(value: i, child: Text('$i día(s)')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => dias = value ?? dias),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, dias),
                child: const Text('Programar'),
              ),
            ],
          ),
        );
      },
    );
    if (dias == null || dias <= 0) return;
    var programados = 0;
    for (var i = 1; i <= dias; i++) {
      final fecha = _fecha.add(Duration(days: i));
      final existente = await _repository.getMenu(fecha, _tipo);
      if (existente != null) continue;
      final nuevo = await _repository.duplicarAnterior(
        fecha,
        _tipo,
        widget.usuario.id,
      );
      if (nuevo != null) programados++;
    }
    if (!mounted) return;
    setState(_reload);
    showAppMessage(
      context,
      programados == 0
          ? 'Los días siguientes ya tenían menú programado.'
          : 'Menú programado para $programados día(s).',
    );
  }

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

    final bool enMenu;
    final bool agotado;
    if (_editando && !directo) {
      enMenu = _selLocal.contains(producto.id);
      agotado = _agotadosLocal.contains(producto.id);
    } else {
      enMenu = item != null;
      agotado = item != null && !item.disponible;
    }
    final seleccionado = enMenu && !agotado;

    final String mensaje;
    if (directo) {
      mensaje = 'Siempre disponible';
    } else if (_editando) {
      mensaje = !enMenu
          ? 'Toca para agregar'
          : agotado
          ? 'Agotado · toca para quitar'
          : 'En el menú de hoy · toca para quitar';
    } else {
      mensaje = item == null
          ? 'No está en el menú de hoy'
          : agotado
          ? (item.motivoAgotado ?? 'Agotado')
          : 'En el menú de hoy';
    }

    // Cada toque deja un mensaje claro; fuera de modo edición nada cambia.
    VoidCallback? onTap;
    if (_esAdmin && !directo) {
      if (_editando) {
        onTap = agotado
            ? () => showAppMessage(
                context,
                '${producto.nombre} está agotado. Reactívalo con el control de la tarjeta.',
              )
            : () => _toggleProducto(data, producto);
      } else {
        onTap = () =>
            showAppMessage(context, 'Pulsa "Editar" para modificar el menú.');
      }
    }

    // Durante la edición el producto puede no existir aún en la BD; se usa un
    // item sintético con el productoId correcto para el botón de agotado.
    final itemAccion =
        item ??
        MenuItem(
          id: 0,
          menuDiaId: 0,
          productoId: producto.id!,
          nombre: producto.nombre,
          precio: producto.precio,
          categoriaNombre: producto.categoriaNombre,
          categoriaColor: producto.categoriaColor,
          tipoProducto: producto.tipo,
          disponible: !agotado,
          motivoAgotado: agotado ? 'Agotado' : null,
          orden: 0,
        );
    final mostrarAccion = _esAdmin && !directo && enMenu;

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
      onTap: onTap,
      accion: mostrarAccion
          ? IconButton(
              tooltip: !agotado ? 'Marcar agotado' : 'Marcar disponible',
              visualDensity: VisualDensity.compact,
              onPressed: () => _toggleDisponible(itemAccion, agotado),
              icon: Icon(
                !agotado ? Icons.block : Icons.check_circle_outline,
                size: 18,
              ),
            )
          : null,
    );
  }
}

class _ComboInput {
  const _ComboInput({
    required this.nombre,
    required this.precio,
    required this.componenteIds,
  });

  final String nombre;
  final double precio;
  final List<int> componenteIds;
}

class _ComboBuilderDialog extends StatefulWidget {
  const _ComboBuilderDialog({required this.productos, this.combo});

  final List<Producto> productos;
  final MenuCombo? combo;

  @override
  State<_ComboBuilderDialog> createState() => _ComboBuilderDialogState();
}

class _ComboBuilderDialogState extends State<_ComboBuilderDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _precio;
  final _buscar = TextEditingController();
  final _seleccionados = <int>{};
  bool _precioManual = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final combo = widget.combo;
    _nombre = TextEditingController(text: combo?.nombre ?? '');
    _precio = TextEditingController(
      text: combo == null ? '' : combo.precio.toStringAsFixed(2),
    );
    _precioManual = combo != null;
    if (combo != null) {
      _seleccionados.addAll(
        combo.componentes.map((componente) => componente.componenteId),
      );
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _buscar.dispose();
    super.dispose();
  }

  double get _base => widget.productos
      .where((producto) => _seleccionados.contains(producto.id))
      .fold<double>(0, (suma, producto) => suma + producto.precio);

  double get _sugerido => _seleccionados.length >= 2 ? _base * 0.9 : _base;

  void _alternar(Producto producto) {
    setState(() {
      if (!_seleccionados.remove(producto.id)) {
        _seleccionados.add(producto.id!);
      }
      if (!_precioManual) {
        _precio.text = _sugerido.toStringAsFixed(2);
      }
    });
  }

  void _usarSugerido() {
    setState(() {
      _precioManual = false;
      _precio.text = _sugerido.toStringAsFixed(2);
    });
  }

  void _guardar() {
    final nombre = _nombre.text.trim();
    final precio = parseAmount(_precio.text);
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa un nombre para el almuerzo.');
      return;
    }
    if (_seleccionados.isEmpty) {
      setState(() => _error = 'Selecciona al menos un producto.');
      return;
    }
    if (precio < 0) {
      setState(() => _error = 'El precio no puede ser negativo.');
      return;
    }
    Navigator.pop(
      context,
      _ComboInput(
        nombre: nombre,
        precio: precio,
        componenteIds: _seleccionados.toList(),
      ),
    );
  }

  int _prioridad(Producto producto) {
    switch (producto.categoriaNombre.toUpperCase()) {
      case 'SOPAS':
        return 0;
      case 'PLATOS SUELTOS':
        return 1;
      default:
        return producto.esCompuesto ? 3 : 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final termino = _buscar.text.trim().toLowerCase();
    final productos =
        widget.productos
            .where(
              (producto) =>
                  termino.isEmpty ||
                  producto.nombre.toLowerCase().contains(termino),
            )
            .toList()
          ..sort((a, b) {
            final prioridad = _prioridad(a).compareTo(_prioridad(b));
            if (prioridad != 0) return prioridad;
            return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
          });
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text(
        widget.combo == null ? 'Armar almuerzo o combo' : 'Editar almuerzo',
      ),
      content: DialogSurface(
        maxWidth: 620,
        child: SizedBox(
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: appInput(label: 'Nombre del almuerzo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _precio,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: appInput(
                        label: 'Precio (Bs)',
                        icon: Icons.sell_outlined,
                      ),
                      onChanged: (_) => _precioManual = true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Suma: ${formatMoney(_base)} · '
                      'Sugerido: ${formatMoney(_sugerido)}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: _seleccionados.isEmpty ? null : _usarSugerido,
                    child: const Text('Usar precio sugerido'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _buscar,
                decoration: appInput(
                  label: 'Buscar producto',
                  icon: Icons.search,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: productos.isEmpty
                    ? Center(
                        child: Text(
                          'No hay productos disponibles.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: productos.length,
                        itemBuilder: (context, index) {
                          final producto = productos[index];
                          final seleccionado = _seleccionados.contains(
                            producto.id,
                          );
                          return CheckboxListTile(
                            value: seleccionado,
                            onChanged: (_) => _alternar(producto),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            secondary: Icon(
                              producto.esCompuesto
                                  ? Icons.dinner_dining
                                  : producto.esDirecto
                                  ? Icons.local_drink_outlined
                                  : Icons.restaurant,
                              color: Color(producto.categoriaColor),
                            ),
                            title: Text(producto.nombre),
                            subtitle: Text(
                              '${producto.categoriaNombre} · '
                              '${formatMoney(producto.precio)}',
                            ),
                          );
                        },
                      ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error, style: TextStyle(color: scheme.error)),
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
          onPressed: _guardar,
          child: Text(widget.combo == null ? 'Agregar al menú' : 'Guardar'),
        ),
      ],
    );
  }
}
