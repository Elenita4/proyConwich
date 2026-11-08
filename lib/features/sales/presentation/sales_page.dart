import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _SaleProduct {
  const _SaleProduct({
    required this.productoId,
    this.menuDiaItemId,
    required this.nombre,
    required this.precio,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.tipo,
    required this.disponible,
    this.motivo,
    required this.stock,
  });

  final int productoId;
  final int? menuDiaItemId;
  final String nombre;
  final double precio;
  final String categoriaNombre;
  final int categoriaColor;
  final String tipo;
  final bool disponible;
  final String? motivo;
  final double stock;

  bool get esDirecto => tipo == 'DIRECTO';
  bool get vendible => disponible && (!esDirecto || stock > 0);
}

class _SalesData {
  const _SalesData({
    required this.caja,
    required this.menu,
    required this.productos,
    required this.pedidosAbiertos,
  });

  final Caja? caja;
  final MenuDia? menu;
  final List<_SaleProduct> productos;
  final List<Pedido> pedidosAbiertos;
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _cashRepository = CashRepository();
  final _catalogRepository = CatalogRepository();
  final _menuRepository = MenuRepository();
  final _salesRepository = SalesRepository();
  late Future<_SalesData> _future;
  final _cart = <int, CartLine>{};
  final _referencia = TextEditingController();
  final _observacion = TextEditingController();
  String _search = '';
  String? _categoria;
  int? _pedidoEditandoId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _referencia.dispose();
    _observacion.dispose();
    super.dispose();
  }

  void _reload() => _future = _load();

  Future<_SalesData> _load() async {
    final caja = await _cashRepository.getCajaAbierta();
    final now = DateTime.now();
    final tipo = caja == null
        ? (now.hour < 12 ? 'DESAYUNO' : 'ALMUERZO')
        : MenuRepository.tipoDesdeTurno(caja.turno);
    final menu = await _menuRepository.getMenu(now, tipo);
    final menuItems = menu != null && menu.publicado
        ? await _menuRepository.getItems(menu.id)
        : <MenuItem>[];
    final siempre = await _catalogRepository.getProductosSiempreDisponibles();
    final productos = <int, _SaleProduct>{};
    for (final item in menuItems) {
      var stock = 0.0;
      if (item.tipoProducto == 'DIRECTO') {
        final producto = await _catalogRepository.getProducto(item.productoId);
        stock = producto?.stock ?? 0;
      }
      productos[item.productoId] = _SaleProduct(
        productoId: item.productoId,
        menuDiaItemId: item.id,
        nombre: item.nombre,
        precio: item.precio,
        categoriaNombre: item.categoriaNombre,
        categoriaColor: item.categoriaColor,
        tipo: item.tipoProducto,
        disponible: item.disponible,
        motivo: item.motivoAgotado,
        stock: stock,
      );
    }
    for (final producto in siempre) {
      productos.putIfAbsent(
        producto.id!,
        () => _SaleProduct(
          productoId: producto.id!,
          nombre: producto.nombre,
          precio: producto.precio,
          categoriaNombre: producto.categoriaNombre,
          categoriaColor: producto.categoriaColor,
          tipo: producto.tipo,
          disponible: producto.activo,
          stock: producto.stock,
        ),
      );
    }
    final abiertos = await _salesRepository.getPedidosAbiertos();
    return _SalesData(
      caja: caja,
      menu: menu,
      productos: productos.values.toList(),
      pedidosAbiertos: abiertos,
    );
  }

  double get _total =>
      _cart.values.fold<double>(0, (sum, line) => sum + line.subtotal);

  int get _unidades => _cart.values.fold<int>(
    0,
    (sum, line) => sum + line.cantidad.round(),
  );

  void _add(_SaleProduct producto) {
    if (!producto.vendible) {
      showAppMessage(
        context,
        producto.motivo ?? 'El producto no está disponible.',
        error: true,
      );
      return;
    }
    setState(() {
      final line = _cart[producto.productoId];
      if (line == null) {
        _cart[producto.productoId] = CartLine(
          productoId: producto.productoId,
          menuDiaItemId: producto.menuDiaItemId,
          nombre: producto.nombre,
          precio: producto.precio,
          cantidad: 1,
          tipo: producto.tipo,
        );
      } else {
        _cart[producto.productoId] = line.copyWith(
          cantidad: line.cantidad + 1,
        );
      }
    });
  }

  void _changeQty(int productoId, double delta) {
    setState(() {
      final line = _cart[productoId];
      if (line == null) return;
      final nueva = line.cantidad + delta;
      if (nueva <= 0) {
        _cart.remove(productoId);
      } else {
        _cart[productoId] = line.copyWith(cantidad: nueva);
      }
    });
  }

  void _remove(int productoId) {
    setState(() => _cart.remove(productoId));
  }

  void _limpiarCarrito() {
    setState(() {
      _cart.clear();
      _referencia.clear();
      _observacion.clear();
      _pedidoEditandoId = null;
    });
  }

  Future<void> _guardarPendiente(_SalesData data) async {
    final caja = data.caja;
    if (caja == null) return;
    if (_cart.isEmpty) {
      showAppMessage(context, 'Agrega productos al pedido.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_pedidoEditandoId != null) {
        await _salesRepository.agregarLineas(
          _pedidoEditandoId!,
          _cart.values.toList(),
          cajaId: caja.id,
        );
      } else {
        await _salesRepository.crearPedido(
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          menuDiaId: data.menu?.publicado == true ? data.menu!.id : null,
          referencia: _referencia.text,
          observacion: _observacion.text,
          lineas: _cart.values.toList(),
          pagos: const [],
        );
      }
      if (!mounted) return;
      final editando = _pedidoEditandoId;
      _limpiarCarrito();
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        editando == null
            ? 'Pedido guardado como pendiente de pago.'
            : 'Líneas agregadas al pedido.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  Future<void> _cobrar(_SalesData data) async {
    final caja = data.caja;
    if (caja == null) return;
    if (_cart.isEmpty) {
      showAppMessage(context, 'Agrega productos al pedido.', error: true);
      return;
    }
    final pagos = await showDialog<List<PagoInput>>(
      context: context,
      builder: (_) => _PaymentDialog(total: _total),
    );
    if (pagos == null) return;
    setState(() => _saving = true);
    try {
      if (_pedidoEditandoId != null) {
        await _salesRepository.agregarLineas(
          _pedidoEditandoId!,
          _cart.values.toList(),
          cajaId: caja.id,
        );
        await _salesRepository.agregarPagos(
          pedidoId: _pedidoEditandoId!,
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          pagos: pagos,
        );
      } else {
        await _salesRepository.crearPedido(
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          menuDiaId: data.menu?.publicado == true ? data.menu!.id : null,
          referencia: _referencia.text,
          observacion: _observacion.text,
          lineas: _cart.values.toList(),
          pagos: pagos,
        );
      }
      if (!mounted) return;
      final editando = _pedidoEditandoId;
      _limpiarCarrito();
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        editando == null
            ? 'Venta registrada por ${formatMoney(_totalAnterior(pagos))}.'
            : 'Pago agregado al pedido.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  double _totalAnterior(List<PagoInput> pagos) =>
      pagos.fold<double>(0, (sum, pago) => sum + pago.monto);

  Future<void> _cobrarPedido(Pedido pedido, _SalesData data) async {
    final caja = data.caja;
    if (caja == null) {
      showAppMessage(
        context,
        'Abre una caja para cobrar pedidos pendientes.',
        error: true,
      );
      return;
    }
    final pagos = await showDialog<List<PagoInput>>(
      context: context,
      builder: (_) => _PaymentDialog(total: pedido.saldo),
    );
    if (pagos == null) return;
    try {
      await _salesRepository.agregarPagos(
        pedidoId: pedido.id,
        usuarioId: widget.usuario.id,
        cajaId: caja.id,
        pagos: pagos,
      );
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Pago registrado para el pedido #${pedido.id}.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, '$error', error: true);
    }
  }

  Future<void> _anular(Pedido pedido) async {
    final confirmado = await confirmAction(
      context,
      title: 'Anular pedido',
      message:
          'Se anularán el pedido #${pedido.id}, sus pagos y los consumos de insumos asociados.',
      confirmLabel: 'Anular',
      destructive: true,
    );
    if (!confirmado) return;
    try {
      await _salesRepository.anularPedido(pedido.id);
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Pedido anulado.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo anular: $error', error: true);
    }
  }

  Future<void> _verPedido(Pedido pedido) async {
    try {
      final detalle = await _salesRepository.getPedido(pedido.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PedidoDetalleDialog(detalle: detalle),
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo cargar el pedido: $error', error: true);
    }
  }

  Future<void> _agotar(_SaleProduct producto) async {
    final menuItemId = producto.menuDiaItemId;
    if (menuItemId == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Reportar agotamiento',
      message:
          '${producto.nombre} dejará de estar disponible para la venta de hoy.',
      confirmLabel: 'Marcar agotado',
      destructive: true,
    );
    if (!confirmado) return;
    await _menuRepository.setDisponible(
      menuItemId,
      false,
      motivo: 'Agotado',
    );
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, '${producto.nombre} marcado como agotado.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SalesData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Ventas',
                subtitle:
                    'Selecciona platos del menú publicado y bebidas siempre disponibles.',
                actions: [
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
              else if (data.caja == null)
                Column(
                  children: [
                    EmptyState(
                      icon: Icons.lock_outline,
                      title: 'No hay caja abierta',
                      message:
                          'Abre una caja en la sección Caja para registrar ventas.',
                    ),
                    if (data.pedidosAbiertos.isNotEmpty)
                      _pedidosAbiertos(context, data),
                  ],
                )
              else ...[
                _estadoMenu(context, data),
                const SizedBox(height: 14),
                _filtros(context, data),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth >= 1000;
                    final catalogo = _catalogo(context, data);
                    final carrito = _carrito(context, data);
                    if (horizontal) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: catalogo),
                          const SizedBox(width: 16),
                          SizedBox(width: 390, child: carrito),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        catalogo,
                        const SizedBox(height: 16),
                        carrito,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                _pedidosAbiertos(context, data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _estadoMenu(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final publicado = menu?.publicado == true;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            publicado ? Icons.check_circle_outline : Icons.info_outline,
            color: publicado ? scheme.primary : scheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              publicado
                  ? 'Menú de ${menu!.tipo.toLowerCase()} publicado. Turno ${data.caja!.turno}.'
                  : 'No hay menú publicado para este turno. Solo se muestran las bebidas y productos siempre disponibles.',
            ),
          ),
          Chip(
            label: Text('Caja ${data.caja!.turno}'),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _filtros(BuildContext context, _SalesData data) {
    final categorias = data.productos
        .map((producto) => producto.categoriaNombre)
        .toSet()
        .toList()
      ..sort();
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
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
          ChoiceChip(
            label: const Text('Todos'),
            selected: _categoria == null,
            onSelected: (_) => setState(() => _categoria = null),
          ),
          ...categorias.map(
            (categoria) => ChoiceChip(
              label: Text(categoria),
              selected: _categoria == categoria,
              onSelected: (_) => setState(() => _categoria = categoria),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _SalesData data) {
    final filtrados = data.productos.where((producto) {
      if (_categoria != null && producto.categoriaNombre != _categoria) {
        return false;
      }
      final term = _search.trim().toLowerCase();
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList();
    if (filtrados.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No hay productos disponibles',
        message:
            'El administrador debe publicar el menú o crear productos siempre disponibles.',
      );
    }
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
          children: filtrados
              .map(
                (producto) => SizedBox(
                  width: width,
                  child: _ProductoVentaCard(
                    producto: producto,
                    onAdd: producto.vendible ? () => _add(producto) : null,
                    onAgotar:
                        producto.menuDiaItemId != null &&
                            widget.usuario.puede(Permiso.agotamiento)
                        ? () => _agotar(producto)
                        : null,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _carrito(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Pedido',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$_unidades ítem(s)',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (_pedidoEditandoId != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agregando líneas al pedido #$_pedidoEditandoId',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pedidoEditandoId = null),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_cart.isEmpty)
            const EmptyState(
              icon: Icons.add_shopping_cart,
              title: 'Carrito vacío',
              message: 'Toca un producto para agregarlo al pedido.',
            )
          else ...[
            ..._cart.values.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.nombre,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${formatMoney(line.precio)} c/u',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _changeQty(line.productoId, -1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      formatQty(line.cantidad),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _changeQty(line.productoId, 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(
                        formatMoney(line.subtotal),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Quitar',
                      onPressed: () => _remove(line.productoId),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            Row(
              children: [
                Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  formatMoney(_total),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referencia,
              decoration: appInput(
                label: 'Referencia (opcional)',
                hint: 'Ej. mesa 3, nombre o nota',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _observacion,
              maxLines: 2,
              decoration: appInput(label: 'Observación (opcional)'),
            ),
            const SizedBox(height: 14),
            if (_pedidoEditandoId != null)
              FilledButton.icon(
                onPressed: _saving ? null : () => _guardarPendiente(data),
                icon: const Icon(Icons.playlist_add),
                label: Text(_saving ? 'Guardando…' : 'Agregar al pedido'),
              )
            else ...[
              FilledButton.icon(
                onPressed: _saving ? null : () => _cobrar(data),
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Cobrar'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _guardarPendiente(data),
                icon: const Icon(Icons.pending_actions_outlined),
                label: const Text('Guardar pendiente de pago'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pedidosAbiertos(BuildContext context, _SalesData data) {
    if (data.pedidosAbiertos.isEmpty) {
      return const SizedBox.shrink();
    }
    final hayCaja = data.caja != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedidos pendientes de pago',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (!hayCaja) ...[
          const SizedBox(height: 4),
          Text(
            'Abre una caja para cobrar o modificar pedidos pendientes.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        ...data.pedidosAbiertos.map(
          (pedido) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text('${pedido.id}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pedido.referencia == null
                              ? 'Pedido #${pedido.id}'
                              : '${pedido.referencia} · #${pedido.id}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${formatDateTimeText(pedido.fecha)} · ${pedido.usuarioNombre}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Total ${formatMoney(pedido.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Saldo ${formatMoney(pedido.saldo)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ver detalle',
                    onPressed: () => _verPedido(pedido),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                  TextButton(
                    onPressed: hayCaja ? () => _cobrarPedido(pedido, data) : null,
                    child: const Text('Cobrar'),
                  ),
                  TextButton(
                    onPressed: hayCaja
                        ? () {
                            setState(() => _pedidoEditandoId = pedido.id);
                            showAppMessage(
                              context,
                              'Agrega productos y usa “Agregar al pedido”.',
                            );
                          }
                        : null,
                    child: const Text('Agregar'),
                  ),
                  TextButton(
                    onPressed: () => _anular(pedido),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('Anular'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductoVentaCard extends StatelessWidget {
  const _ProductoVentaCard({
    required this.producto,
    required this.onAdd,
    this.onAgotar,
  });

  final _SaleProduct producto;
  final VoidCallback? onAdd;
  final VoidCallback? onAgotar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disponible = producto.vendible;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(producto.categoriaColor),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  producto.categoriaNombre,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onAgotar != null)
                IconButton(
                  tooltip: 'Reportar agotado',
                  visualDensity: VisualDensity.compact,
                  onPressed: onAgotar,
                  icon: const Icon(Icons.block, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            producto.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(producto.precio),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          if (producto.esDirecto)
            Text(
              'Stock: ${formatQty(producto.stock)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: disponible ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: disponible
                ? FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar'),
                  )
                : OutlinedButton(
                    onPressed: null,
                    child: Text(producto.motivo ?? 'Agotado'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PagoRow {
  _PagoRow({required this.metodo, required this.monto});

  String metodo;
  final TextEditingController monto;
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final List<_PagoRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [
      _PagoRow(
        metodo: 'EFECTIVO',
        monto: TextEditingController(text: widget.total.toStringAsFixed(2)),
      ),
    ];
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.monto.dispose();
    }
    super.dispose();
  }

  double get _suma =>
      _rows.fold<double>(0, (sum, row) => sum + parseAmount(row.monto.text));

  double get _restante => widget.total - _suma;

  bool get _valido => _suma > 0 && _suma <= widget.total + 0.05;

  void _agregar() {
    setState(() {
      _rows.add(
        _PagoRow(metodo: 'QR', monto: TextEditingController(text: '0')),
      );
    });
  }

  void _quitar(int index) {
    if (_rows.length == 1) return;
    setState(() {
      _rows[index].monto.dispose();
      _rows.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Cobrar pedido'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Total a cobrar'),
                const Spacer(),
                Text(
                  formatMoney(widget.total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_rows.length, (index) {
              final row = _rows[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: row.metodo,
                        decoration: appInput(label: 'Método'),
                        items: const [
                          DropdownMenuItem(
                            value: 'EFECTIVO',
                            child: Text('Efectivo'),
                          ),
                          DropdownMenuItem(
                            value: 'QR',
                            child: Text('QR'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => row.metodo = value ?? 'EFECTIVO'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: row.monto,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                        decoration: appInput(label: 'Monto (Bs)'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      onPressed: _rows.length == 1
                          ? null
                          : () => _quitar(index),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _agregar,
                icon: const Icon(Icons.add),
                label: const Text('Agregar otro método'),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Text(
                  _restante > 0.004
                      ? 'Restante'
                      : _restante < -0.004
                      ? 'Excede el total'
                      : 'Completo',
                  style: TextStyle(
                    color: _restante.abs() <= 0.004
                        ? scheme.primary
                        : scheme.error,
                  ),
                ),
                const Spacer(),
                Text(
                  formatMoney(_restante.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _restante.abs() <= 0.004
                        ? scheme.primary
                        : scheme.error,
                  ),
                ),
              ],
            ),
            if (_restante < -0.004)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Los pagos no pueden superar el total.',
                  style: TextStyle(color: scheme.error),
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
          onPressed: _valido
              ? () => Navigator.pop(
                  context,
                  _rows
                      .where((row) => parseAmount(row.monto.text) > 0)
                      .map(
                        (row) => PagoInput(
                          metodo: row.metodo,
                          monto: parseAmount(row.monto.text),
                        ),
                      )
                      .toList(),
                )
              : null,
          child: Text(
            _restante > 0.004 ? 'Guardar pago parcial' : 'Confirmar cobro',
          ),
        ),
      ],
    );
  }
}

class _PedidoDetalleDialog extends StatelessWidget {
  const _PedidoDetalleDialog({required this.detalle});

  final PedidoDetalle detalle;

  @override
  Widget build(BuildContext context) {
    final pedido = detalle.pedido;
    return AlertDialog(
      title: Text('Pedido #${pedido.id}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabelValue(
                label: 'Estado de pago',
                value: pedido.estadoPago,
              ),
              LabelValue(
                label: 'Estado de entrega',
                value: pedido.estadoEntrega,
              ),
              if (pedido.referencia != null)
                LabelValue(label: 'Referencia', value: pedido.referencia!),
              LabelValue(
                label: 'Fecha',
                value: formatDateTimeText(pedido.fecha),
              ),
              LabelValue(label: 'Total', value: formatMoney(pedido.total)),
              LabelValue(label: 'Pagado', value: formatMoney(pedido.pagado)),
              LabelValue(label: 'Saldo', value: formatMoney(pedido.saldo)),
              const Divider(height: 22),
              Text(
                'Productos',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...detalle.lineas.map(
                (linea) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatQty(linea.cantidad)} × ${linea.nombre}',
                        ),
                      ),
                      Text(formatMoney(linea.subtotal)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 22),
              Text(
                'Pagos',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (detalle.pagos.isEmpty)
                const Text('Sin pagos registrados.')
              else
                ...detalle.pagos.map(
                  (pago) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${pago.metodo} · ${pago.estado}',
                        ),
                      ),
                      Text(formatMoney(pago.monto)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
