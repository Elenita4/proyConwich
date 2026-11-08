import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/purchase_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _PurchasesData {
  const _PurchasesData({
    required this.compras,
    required this.insumos,
    required this.productos,
    required this.caja,
  });

  final List<Compra> compras;
  final List<Insumo> insumos;
  final List<Producto> productos;
  final Caja? caja;
}

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _repository = PurchaseRepository();
  final _catalog = CatalogRepository();
  final _cash = CashRepository();
  late Future<_PurchasesData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_PurchasesData> _load() async {
    final compras = await _repository.getCompras();
    final insumos = await _catalog.getInsumos(soloActivos: true);
    final productos = (await _catalog.getProductos(soloActivos: true))
        .where((producto) => producto.esDirecto)
        .toList();
    final caja = await _cash.getCajaAbierta();
    return _PurchasesData(
      compras: compras,
      insumos: insumos,
      productos: productos,
      caja: caja,
    );
  }

  Future<void> _nueva(_PurchasesData data) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PurchaseDialog(
        repository: _repository,
        insumos: data.insumos,
        productos: data.productos,
        usuario: widget.usuario,
        caja: data.caja,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Compra registrada.');
    }
  }

  Future<void> _anular(Compra compra) async {
    final confirmado = await confirmAction(
      context,
      title: 'Anular compra',
      message:
          'La compra #${compra.id} quedará anulada y dejará de sumar stock y salidas de caja.',
      confirmLabel: 'Anular',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.anularCompra(compra.id);
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, 'Compra anulada.');
  }

  Future<void> _ver(Compra compra) async {
    try {
      final detalle = await _repository.getCompra(compra.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Compra #${compra.id}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabelValue(
                    label: 'Fecha',
                    value: formatDateTimeText(compra.fecha),
                  ),
                  LabelValue(label: 'Usuario', value: compra.usuarioNombre),
                  LabelValue(label: 'Método', value: compra.metodoPago),
                  LabelValue(label: 'Estado', value: compra.estado),
                  if (compra.observacion != null)
                    LabelValue(
                      label: 'Observación',
                      value: compra.observacion!,
                    ),
                  const Divider(height: 22),
                  ...detalle.lineas.map(
                    (linea) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${linea.nombre} · ${formatQty(linea.cantidad)} × ${formatMoney(linea.costoUnitario)}',
                            ),
                          ),
                          Text(formatMoney(linea.subtotal)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  LabelValue(
                    label: 'Total',
                    value: formatMoney(compra.total),
                    strong: true,
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
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo cargar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PurchasesData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Compras',
                subtitle:
                    'Registra compras de insumos y productos directos. Suman stock y salen de caja.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _nueva(data!) : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva compra'),
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
              else if (data == null || data.compras.isEmpty)
                EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Todavía no hay compras',
                  message:
                      'Registra la primera compra para cargar stock de insumos o productos directos.',
                  action: FilledButton.icon(
                    onPressed: () => _nueva(data!),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar compra'),
                  ),
                )
              else
                ...data.compras.map(
                  (compra) => Padding(
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
                            child: Text('${compra.id}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatDateTimeText(compra.fecha),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${compra.usuarioNombre} · ${compra.metodoPago}',
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
                          Expanded(
                            child: Text(
                              formatMoney(compra.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              compra.observacion ?? 'Sin observación',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(compra.estado),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'Ver detalle',
                            onPressed: () => _ver(compra),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                          if (!compra.anulada)
                            TextButton(
                              onPressed: () => _anular(compra),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              child: const Text('Anular'),
                            ),
                        ],
                      ),
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

class _LineaCompraState {
  _LineaCompraState()
    : cantidad = TextEditingController(text: '1'),
      costo = TextEditingController(text: '0');

  String tipo = 'INSUMO';
  int? itemId;
  final TextEditingController cantidad;
  final TextEditingController costo;

  void dispose() {
    cantidad.dispose();
    costo.dispose();
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({
    required this.repository,
    required this.insumos,
    required this.productos,
    required this.usuario,
    required this.caja,
  });

  final PurchaseRepository repository;
  final List<Insumo> insumos;
  final List<Producto> productos;
  final Usuario usuario;
  final Caja? caja;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _observacion = TextEditingController();
  final _lineas = <_LineaCompraState>[_LineaCompraState()];
  String _metodo = 'EFECTIVO';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _observacion.dispose();
    for (final linea in _lineas) {
      linea.dispose();
    }
    super.dispose();
  }

  double get _total => _lineas.fold<double>(0, (sum, linea) {
    return sum + parseAmount(linea.cantidad.text) * parseAmount(linea.costo.text);
  });

  void _agregarLinea() {
    setState(() => _lineas.add(_LineaCompraState()));
  }

  void _quitarLinea(int index) {
    if (_lineas.length == 1) return;
    setState(() {
      _lineas[index].dispose();
      _lineas.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final inputs = <CompraLineaInput>[];
    for (final linea in _lineas) {
      if (linea.itemId == null) {
        setState(() => _error = 'Selecciona el insumo o producto de cada línea.');
        return;
      }
      final cantidad = parseAmount(linea.cantidad.text);
      final costo = parseAmount(linea.costo.text);
      if (cantidad <= 0) {
        setState(() => _error = 'La cantidad debe ser mayor a cero.');
        return;
      }
      if (linea.tipo == 'INSUMO') {
        final insumo = widget.insumos.firstWhere(
          (item) => item.id == linea.itemId,
        );
        inputs.add(
          CompraLineaInput(
            insumoId: insumo.id,
            nombre: insumo.nombre,
            cantidad: cantidad,
            costoUnitario: costo,
          ),
        );
      } else {
        final producto = widget.productos.firstWhere(
          (item) => item.id == linea.itemId,
        );
        inputs.add(
          CompraLineaInput(
            productoId: producto.id,
            nombre: producto.nombre,
            cantidad: cantidad,
            costoUnitario: costo,
          ),
        );
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.registrarCompra(
        usuarioId: widget.usuario.id,
        cajaId: widget.caja?.id,
        metodoPago: _metodo,
        observacion: _observacion.text,
        lineas: inputs,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo registrar: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva compra'),
      content: SizedBox(
        width: 680,
        height: 560,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _metodo,
                      decoration: appInput(label: 'Método de pago'),
                      items: const [
                        DropdownMenuItem(
                          value: 'EFECTIVO',
                          child: Text('Efectivo'),
                        ),
                        DropdownMenuItem(value: 'QR', child: Text('QR')),
                      ],
                      onChanged: (value) =>
                          setState(() => _metodo = value ?? 'EFECTIVO'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _observacion,
                      decoration: appInput(
                        label: 'Observación (opcional)',
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.caja == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No hay caja abierta: la compra no se descontará de una caja.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _lineas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final linea = _lineas[index];
                    final items = linea.tipo == 'INSUMO'
                        ? widget.insumos
                              .map(
                                (item) => DropdownMenuItem<int>(
                                  value: item.id,
                                  child: Text(
                                    '${item.nombre} (${item.unidadAbreviatura})',
                                  ),
                                ),
                              )
                              .toList()
                        : widget.productos
                              .map(
                                (item) => DropdownMenuItem<int>(
                                  value: item.id,
                                  child: Text(item.nombre),
                                ),
                              )
                              .toList();
                    return AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: DropdownButtonFormField<String>(
                              initialValue: linea.tipo,
                              decoration: appInput(label: 'Tipo'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'INSUMO',
                                  child: Text('Insumo'),
                                ),
                                DropdownMenuItem(
                                  value: 'PRODUCTO',
                                  child: Text('Producto'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  linea.tipo = value ?? 'INSUMO';
                                  linea.itemId = null;
                                  linea.costo.text = '0';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('${linea.tipo}-$index-${linea.itemId}'),
                              initialValue: linea.itemId,
                              decoration: appInput(label: 'Ítem'),
                              items: items,
                              onChanged: (value) {
                                setState(() {
                                  linea.itemId = value;
                                  if (linea.tipo == 'INSUMO') {
                                    final insumo = widget.insumos.firstWhere(
                                      (item) => item.id == value,
                                    );
                                    linea.costo.text = insumo.costoPromedio
                                        .toStringAsFixed(2);
                                  } else {
                                    final producto = widget.productos.firstWhere(
                                      (item) => item.id == value,
                                    );
                                    linea.costo.text = producto.costoUnitario
                                        .toStringAsFixed(2);
                                  }
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Selecciona un ítem' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: TextFormField(
                              controller: linea.cantidad,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: appInput(label: 'Cantidad'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: linea.costo,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: appInput(label: 'Costo unit.'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 90,
                            child: Text(
                              formatMoney(
                                parseAmount(linea.cantidad.text) *
                                    parseAmount(linea.costo.text),
                              ),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _lineas.length == 1
                                ? null
                                : () => _quitarLinea(index),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _agregarLinea,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar línea'),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ${formatMoney(_total)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
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
          child: Text(_saving ? 'Guardando…' : 'Registrar compra'),
        ),
      ],
    );
  }
}
