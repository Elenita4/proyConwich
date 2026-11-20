import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/receipt_service.dart';
import '../../../core/report_exporter.dart';
import '../../../core/report_repository.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

/// Paleta con más variedad para los gráficos del reporte.
const _chartPalette = <Color>[
  Color(0xFFEA580C),
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
  Color(0xFFCA8A04),
  Color(0xFFDC2626),
  Color(0xFF4F46E5),
  Color(0xFF059669),
];

class _ReportData {
  const _ReportData({
    required this.resumen,
    required this.productos,
    required this.salidas,
    required this.salidasDetalle,
    required this.inventario,
    required this.pedidos,
    required this.faltantes,
    required this.compras,
    required this.cajas,
    required this.devoluciones,
  });

  final ResumenFinanciero resumen;
  final List<ProductoReporte> productos;
  final List<GastoReporte> salidas;
  final List<SalidaReporte> salidasDetalle;
  final List<InventarioReporte> inventario;
  final List<PedidoReporte> pedidos;
  final List<FaltanteInsumoReporte> faltantes;
  final List<CompraReporte> compras;
  final List<CajaHistorial> cajas;
  final List<DevolucionReporte> devoluciones;
}

/// Porción del pastel de ingresos. Permite agrupar los productos con menos
/// ventas en una sola porción "Otros" para que la leyenda no se sature.
class _ProductoSlice {
  const _ProductoSlice({
    required this.nombre,
    required this.valor,
    required this.color,
  });

  final String nombre;
  final double valor;
  final Color color;
}

class _CajaGrupo {
  _CajaGrupo({required this.etiqueta});

  final String etiqueta;
  int turnos = 0;
  double efectivo = 0;
  double qr = 0;
  double salidas = 0;
  double esperado = 0;
  double sobrante = 0;
  final Set<String> cajeros = <String>{};
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.refreshToken, this.usuario});

  final int refreshToken;
  final Usuario? usuario;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _periodos = ['DIA', 'SEMANA', 'MES', 'TRIMESTRE', 'ANIO'];
  String _agrupacionCajas = 'DIA';
  final _repository = ReportRepository();
  late Future<_ReportData> _future;
  late Future<List<PedidoReporte>> _misPedidosFuture;
  String _periodo = 'DIA';
  DateTime _anchor = DateTime.now();
  DateTimeRange? _rangoPersonalizado;
  bool _exportando = false;

  bool get _soloMisPedidos =>
      widget.usuario != null && !widget.usuario!.esAdmin;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.usuario?.id != widget.usuario?.id ||
        oldWidget.usuario?.esAdmin != widget.usuario?.esAdmin) {
      _reload();
    }
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    if (_soloMisPedidos) {
      final range = _range;
      _misPedidosFuture = _repository.getPedidos(
        range.start,
        range.end,
        usuarioId: widget.usuario!.id,
        incluirAnulados: true,
      );
      return;
    }
    _future = _load();
  }

  String _labelPeriodo(String value) => switch (value) {
    'DIA' => 'Día',
    'SEMANA' => 'Semana',
    'MES' => 'Mes',
    'TRIMESTRE' => 'Trimestre',
    'RANGO' => 'Personalizado',
    _ => 'Año',
  };

  DateTimeRange get _range {
    final anchor = _anchor;
    switch (_periodo) {
      case 'SEMANA':
        final start = DateTime(
          anchor.year,
          anchor.month,
          anchor.day,
        ).subtract(Duration(days: anchor.weekday - 1));
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      case 'MES':
        return DateTimeRange(
          start: DateTime(anchor.year, anchor.month, 1),
          end: DateTime(anchor.year, anchor.month + 1, 1),
        );
      case 'TRIMESTRE':
        final startMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
          start: DateTime(anchor.year, startMonth, 1),
          end: DateTime(anchor.year, startMonth + 3, 1),
        );
      case 'ANIO':
        return DateTimeRange(
          start: DateTime(anchor.year, 1, 1),
          end: DateTime(anchor.year + 1, 1, 1),
        );
      case 'RANGO':
        return _rangoPersonalizado ??
            DateTimeRange(
              start: DateTime(
                anchor.year,
                anchor.month,
                anchor.day,
              ).subtract(const Duration(days: 6)),
              end: DateTime(anchor.year, anchor.month, anchor.day + 1),
            );
      default:
        final start = DateTime(anchor.year, anchor.month, anchor.day);
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 1)),
        );
    }
  }

  void _mover(int delta) {
    setState(() {
      switch (_periodo) {
        case 'SEMANA':
          _anchor = _anchor.add(Duration(days: 7 * delta));
          break;
        case 'MES':
          _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
          break;
        case 'TRIMESTRE':
          _anchor = DateTime(_anchor.year, _anchor.month + 3 * delta, 1);
          break;
        case 'ANIO':
          _anchor = DateTime(_anchor.year + delta, 1, 1);
          break;
        case 'RANGO':
          final rango = _range;
          final duracion = rango.end.difference(rango.start);
          _rangoPersonalizado = DateTimeRange(
            start: rango.start.add(Duration(days: duracion.inDays * delta)),
            end: rango.end.add(Duration(days: duracion.inDays * delta)),
          );
          _anchor = _rangoPersonalizado!.end.subtract(const Duration(days: 1));
          break;
        default:
          _anchor = _anchor.add(Duration(days: delta));
      }
      _reload();
    });
  }

  Future<void> _seleccionarRango() async {
    final actual = _range;
    final elegido = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: actual.start,
        end: actual.end.subtract(const Duration(days: 1)),
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (elegido == null || !mounted) return;
    setState(() {
      _periodo = 'RANGO';
      _rangoPersonalizado = DateTimeRange(
        start: DateTime(
          elegido.start.year,
          elegido.start.month,
          elegido.start.day,
        ),
        end: DateTime(elegido.end.year, elegido.end.month, elegido.end.day + 1),
      );
      _anchor = elegido.end;
      _reload();
    });
  }

  Future<_ReportData> _load() async {
    final range = _range;
    final resumen = await _repository.getResumen(range.start, range.end);
    final productos = await _repository.getProductos(range.start, range.end);
    final salidas = await _repository.getSalidasPorMotivo(
      range.start,
      range.end,
    );
    final salidasDetalle = await _repository.getSalidasDetalladas(
      range.start,
      range.end,
    );
    final inventario = await _repository.getInventario();
    final pedidos = await _repository.getPedidos(range.start, range.end);
    final faltantes = await _repository.getFaltantes(range.start, range.end);
    final compras = await _repository.getCompras(range.start, range.end);
    final cajas = await CashRepository().getCajasEntre(
      range.start,
      range.end,
    );
    final devoluciones = await _repository.getDevoluciones(
      range.start,
      range.end,
    );
    return _ReportData(
      resumen: resumen,
      productos: productos,
      salidas: salidas,
      salidasDetalle: salidasDetalle,
      inventario: inventario,
      pedidos: pedidos,
      faltantes: faltantes,
      compras: compras,
      cajas: cajas,
      devoluciones: devoluciones,
    );
  }

  ReportExportData _exportData(_ReportData data, DateTimeRange range) =>
      ReportExportData(
        desde: range.start,
        hasta: range.end,
        resumen: data.resumen,
        productos: data.productos,
        salidas: data.salidasDetalle,
        pedidos: data.pedidos,
        faltantes: data.faltantes,
        compras: data.compras,
        cajas: data.cajas,
        devoluciones: data.devoluciones,
      );

  Widget _misPedidosPage(BuildContext context) {
    return FutureBuilder<List<PedidoReporte>>(
      future: _misPedidosFuture,
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
        final pedidos = snapshot.data ?? const <PedidoReporte>[];
        final range = _range;
        final finMostrar = range.end.subtract(const Duration(days: 1));
        return ListView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          children: [
            PageHeader(
              title: 'Mis pedidos',
              subtitle: 'Historial de tus pedidos. Solo lectura.',
              actions: [
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
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChipRow<String>(
                    values: [..._periodos, 'RANGO'],
                    labelBuilder: _labelPeriodo,
                    selected: _periodo,
                    onSelected: (value) {
                      if (value == 'RANGO' && _rangoPersonalizado == null) {
                        _seleccionarRango();
                        return;
                      }
                      setState(() {
                        _periodo = value;
                        if (value != 'RANGO') _anchor = DateTime.now();
                        _reload();
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Período anterior',
                    onPressed: () => _mover(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${formatDateShort(range.start)} — ${formatDateShort(finMostrar)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: 'Período siguiente',
                    onPressed: () => _mover(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  OutlinedButton.icon(
                    onPressed: _seleccionarRango,
                    icon: const Icon(Icons.date_range_outlined),
                    label: const Text('Elegir fechas'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (pedidos.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Sin pedidos en el período',
                message: 'No registraste pedidos en estas fechas.',
              )
            else
              ...pedidos.map(
                (pedido) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${pedido.id}')),
                      title: Text(
                        pedido.referencia == null
                            ? 'Pedido #${pedido.id}'
                            : '${pedido.referencia} · #${pedido.id}',
                      ),
                      subtitle: Text(
                        '${formatDateTimeText(pedido.fecha)} · '
                        '${pedido.estadoPago} · ${pedido.estadoEntrega}',
                      ),
                      trailing: Text(
                        formatMoney(pedido.total),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => _verPedidoPropio(pedido),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _verPedidoPropio(PedidoReporte pedido) async {
    try {
      final detalle = await SalesRepository().getPedido(pedido.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PedidoSoloLecturaDialog(detalle: detalle),
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo abrir el pedido: $error',
        error: true,
      );
    }
  }

  Future<void> _exportar({required bool pdf, required bool compartir}) async {
    if (_exportando) return;
    setState(() => _exportando = true);
    final exporter = ReportExporter();
    try {
      final data = await _future;
      final exportData = _exportData(data, _range);
      final nombre = exporter.nombreArchivo(
        exportData,
        extension: pdf ? 'pdf' : 'xlsx',
      );
      if (pdf) {
        final bytes = await exporter.generarPdf(exportData);
        if (!mounted) return;
        if (compartir) {
          await exporter.compartirPdf(bytes, nombre: nombre);
        } else {
          final guardado = await exporter.guardarPdf(bytes, nombre: nombre);
          if (guardado && mounted) {
            showAppMessage(context, 'PDF guardado como $nombre.');
          }
        }
      } else {
        final bytes = await exporter.generarExcel(exportData);
        if (!mounted) return;
        if (compartir) {
          await exporter.compartirExcel(bytes, nombre: nombre);
        } else {
          final guardado = await exporter.guardarExcel(bytes, nombre: nombre);
          if (guardado && mounted) {
            showAppMessage(context, 'Excel guardado como $nombre.');
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo generar el reporte: $error',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_soloMisPedidos) return _misPedidosPage(context);
    final range = _range;
    final finMostrar = range.end.subtract(const Duration(days: 1));
    return DefaultTabController(
      length: 8,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
                12,
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Reportes',
                    subtitle: 'Ventas, cobros en efectivo/QR y salidas de emergencia del período.',
                    actions: [
                      PopupMenuButton<String>(
                        tooltip: 'Reporte PDF',
                        enabled: !_exportando,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onSelected: (value) => _exportar(
                          pdf: true,
                          compartir: value == 'compartir',
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'compartir',
                            child: Text('Compartir PDF'),
                          ),
                          PopupMenuItem(
                            value: 'guardar',
                            child: Text('Guardar PDF'),
                          ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Reporte Excel',
                        enabled: !_exportando,
                        icon: const Icon(Icons.table_view_outlined),
                        onSelected: (value) => _exportar(
                          pdf: false,
                          compartir: value == 'compartir',
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'compartir',
                            child: Text('Compartir Excel'),
                          ),
                          PopupMenuItem(
                            value: 'guardar',
                            child: Text('Guardar Excel'),
                          ),
                        ],
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
                        ChoiceChipRow<String>(
                          values: _periodos,
                          labelBuilder: _labelPeriodo,
                          selected: _periodo,
                          onSelected: (value) => setState(() {
                            _periodo = value;
                            _anchor = DateTime.now();
                            _reload();
                          }),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Período anterior',
                          onPressed: () => _mover(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${formatDateShort(range.start)} — ${formatDateShort(finMostrar)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          tooltip: 'Período siguiente',
                          onPressed: () => _mover(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              tabBar: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(icon: Icon(Icons.summarize_outlined), text: 'Resumen'),
                  Tab(
                    icon: Icon(Icons.lunch_dining_outlined),
                    text: 'Productos',
                  ),
                  Tab(
                    icon: Icon(Icons.point_of_sale_outlined),
                    text: 'Cajas',
                  ),
                  Tab(
                    icon: Icon(Icons.assignment_return_outlined),
                    text: 'Anulados',
                  ),
                  Tab(
                    icon: Icon(Icons.inventory_2_outlined),
                    text: 'Inventario',
                  ),
                  Tab(
                    icon: Icon(Icons.shopping_basket_outlined),
                    text: 'Compras',
                  ),
                  Tab(
                    icon: Icon(Icons.warning_amber_rounded),
                    text: 'Faltantes',
                  ),
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Pedidos'),
                ],
              ),
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ],
        body: FutureBuilder<_ReportData>(
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
            final data = snapshot.data!;
            return TabBarView(
              children: [
                _resumenTab(context, data),
                _productosTab(context, data),
                _cajasTab(context, data),
                _anuladosTab(context, data),
                _inventarioTab(context, data),
                _comprasTab(context, data),
                _faltantesTab(context, data),
                _pedidosTab(context, data),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _resumenTab(BuildContext context, _ReportData data) {
    final resumen = data.resumen;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        _ventasCard(context, resumen),
        const SizedBox(height: 16),
        StatGrid(
          children: [
            StatCard(
              label: 'Cobros en efectivo',
              value: formatMoney(resumen.cobrosEfectivo),
              caption: 'Pagos confirmados del período',
              icon: Icons.payments_outlined,
              color: scheme.primary,
            ),
            StatCard(
              label: 'Cobros QR',
              value: formatMoney(resumen.cobrosQr),
              caption: 'Pagos confirmados del período',
              icon: Icons.qr_code_2,
              color: scheme.secondary,
            ),
            StatCard(
              label: 'Salidas de emergencia',
              value: formatMoney(resumen.salidas),
              caption:
                  'Efectivo ${formatMoney(resumen.salidasEfectivo)} · QR ${formatMoney(resumen.salidasQr)}',
              icon: Icons.outbox,
              color: scheme.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Indicadores',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LabelValue(
                label: 'Ticket promedio',
                value: formatMoney(resumen.ticketPromedio),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salidas registradas',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (data.salidasDetalle.isEmpty)
                const Text('No hay salidas registradas en el período.')
              else
                ...data.salidasDetalle.map(
                  (salida) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 118,
                          child: Text(
                            formatDateTimeShort(salida.fecha),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(salida.detalle),
                              Text(
                                '${salida.metodoPago} · ${salida.usuario} · ${salida.turnoLabel}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatMoney(salida.monto),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Tarjeta grande de ventas con los cobros Efectivo / QR bien visibles
  /// (pensada para el cierre del día).
  Widget _ventasCard(BuildContext context, ResumenFinanciero resumen) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'VENTAS',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(resumen.ventas),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
          ),
          Text(
            '${resumen.pedidos} pedido(s) · ticket promedio ${formatMoney(resumen.ticketPromedio)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final efectivo = _bloquePago(
                context,
                'Efectivo',
                resumen.cobrosEfectivo,
                Icons.payments_outlined,
              );
              final qr = _bloquePago(
                context,
                'QR',
                resumen.cobrosQr,
                Icons.qr_code_2,
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [efectivo, const SizedBox(height: 10), qr],
                );
              }
              return Row(
                children: [
                  Expanded(child: efectivo),
                  const SizedBox(width: 12),
                  Expanded(child: qr),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bloquePago(
    BuildContext context,
    String label,
    double monto,
    IconData icono,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icono, size: 30, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(monto),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productosTab(BuildContext context, _ReportData data) {
    if (data.productos.isEmpty) {
      return const EmptyState(
        icon: Icons.lunch_dining_outlined,
        title: 'Sin ventas en el período',
        message: 'No hay productos vendidos para mostrar.',
      );
    }
    final total = data.productos.fold<double>(
      0,
      (suma, producto) => suma + producto.ventas,
    );
    final slices = _slicesIngresos(data.productos);
    final porCantidad = [...data.productos.where((p) => p.cantidad > 0)]
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        AppCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final torta = SizedBox(
                width: 190,
                height: 190,
                child: CustomPaint(
                  painter: _TortaPainter(
                    valores: slices.map((slice) => slice.valor).toList(),
                    colores: slices.map((slice) => slice.color).toList(),
                  ),
                ),
              );
              final leyenda = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ingresos por producto',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Participación en las ventas del período (Bs).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final slice in slices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: slice.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              slice.nombre,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            total <= 0
                                ? ''
                                : formatPercent(slice.valor / total),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: torta),
                    const SizedBox(height: 16),
                    leyenda,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  torta,
                  const SizedBox(width: 24),
                  Expanded(child: leyenda),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _graficoCantidades(context, porCantidad),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Cantidad'), numeric: true),
                DataColumn(label: Text('Precio unit.'), numeric: true),
                DataColumn(label: Text('Ventas'), numeric: true),
                DataColumn(label: Text('Costo'), numeric: true),
                DataColumn(label: Text('Ganancia'), numeric: true),
              ],
              rows: data.productos
                  .map(
                    (producto) => DataRow(
                      cells: [
                        DataCell(Text(producto.nombre)),
                        DataCell(Text(formatQty(producto.cantidad))),
                        DataCell(Text(formatMoney(producto.precioUnitario))),
                        DataCell(Text(formatMoney(producto.ventas))),
                        DataCell(Text(formatMoney(producto.costo))),
                        DataCell(
                          Text(
                            formatMoney(producto.ganancia),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: producto.ganancia >= 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _desgloseModalidades(context, data.productos),
      ],
    );
  }

  Widget _desgloseModalidades(
    BuildContext context,
    List<ProductoReporte> productos,
  ) {
    final platos = productos
        .where(
          (producto) =>
              producto.categoriaNombre.trim().toUpperCase() == 'PLATOS SUELTOS',
        )
        .toList();
    final sopas = productos
        .where(
          (producto) =>
              producto.categoriaNombre.trim().toUpperCase() == 'SOPAS',
        )
        .toList();
    if (platos.isEmpty && sopas.isEmpty) return const SizedBox.shrink();

    String cantidad(double valor) => valor <= 0 ? '—' : formatQty(valor);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Desglose del menú de almuerzo',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (platos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Platos sueltos y completos',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Plato')),
                  DataColumn(label: Text('Cantidad'), numeric: true),
                  DataColumn(label: Text('Ventas'), numeric: true),
                ],
                rows: platos
                    .map(
                      (producto) => DataRow(
                        cells: [
                          DataCell(Text(producto.nombre)),
                          DataCell(Text(cantidad(producto.cantidad))),
                          DataCell(Text(formatMoney(producto.ventas))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (sopas.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Sopas', style: Theme.of(context).textTheme.titleSmall),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Sopa')),
                  DataColumn(label: Text('Cantidad'), numeric: true),
                  DataColumn(label: Text('Ventas'), numeric: true),
                ],
                rows: sopas
                    .map(
                      (producto) => DataRow(
                        cells: [
                          DataCell(Text(producto.nombre)),
                          DataCell(Text(cantidad(producto.cantidad))),
                          DataCell(Text(formatMoney(producto.ventas))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Agrupa los productos por ingresos para que el pastel y su leyenda se
  /// mantengan legibles. Si hay más de 8, el resto se muestra como "Otros".
  List<_ProductoSlice> _slicesIngresos(List<ProductoReporte> productos) {
    final ordenados = [...productos.where((producto) => producto.ventas > 0)]
      ..sort((a, b) => b.ventas.compareTo(a.ventas));
    if (ordenados.length <= 8) {
      var indice = 0;
      return ordenados
          .map(
            (producto) => _ProductoSlice(
              nombre: producto.nombre,
              valor: producto.ventas,
              color: _chartPalette[indice++ % _chartPalette.length],
            ),
          )
          .toList();
    }
    final top = ordenados.take(7).toList();
    final resto = ordenados
        .skip(7)
        .fold<double>(0, (suma, producto) => suma + producto.ventas);
    var indice = 0;
    return [
      ...top.map(
        (producto) => _ProductoSlice(
          nombre: producto.nombre,
          valor: producto.ventas,
          color: _chartPalette[indice++ % _chartPalette.length],
        ),
      ),
      _ProductoSlice(
        nombre: 'Otros',
        valor: resto,
        color: const Color(0xFF9E8C7A),
      ),
    ];
  }

  /// Gráfico de barras horizontales con los productos más vendidos por
  /// cantidad de unidades (no por dinero).
  Widget _graficoCantidades(
    BuildContext context,
    List<ProductoReporte> productos,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final top = productos.take(10).toList();
    final maximo = top.isEmpty ? 1.0 : top.first.cantidad;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Productos más vendidos',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Por cantidad de unidades vendidas en el período.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (top.isEmpty)
            const Text('Sin cantidades para mostrar.')
          else
            ...top.map((producto) => _barraCantidad(context, producto, maximo)),
        ],
      ),
    );
  }

  Widget _barraCantidad(
    BuildContext context,
    ProductoReporte producto,
    double maximo,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final proporcion = maximo <= 0
        ? 0.0
        : (producto.cantidad / maximo).clamp(0.0, 1.0).toDouble();
    final color = Color(producto.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final angosto = constraints.maxWidth < 480;
          final nombre = Text(
            producto.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
          final valor = Text(
            formatQty(producto.cantidad),
            style: const TextStyle(fontWeight: FontWeight.w700),
          );
          final barra = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 16,
              color: scheme.surfaceContainerLow,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: proporcion <= 0
                    ? 0
                    : proporcion.clamp(0.03, 1.0).toDouble(),
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          );
          if (angosto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: nombre),
                    const SizedBox(width: 8),
                    valor,
                  ],
                ),
                const SizedBox(height: 4),
                barra,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 170, child: nombre),
              const SizedBox(width: 8),
              Expanded(child: barra),
              const SizedBox(width: 12),
              SizedBox(width: 52, child: valor),
            ],
          );
        },
      ),
    );
  }

  Widget _cajasTab(BuildContext context, _ReportData data) {
    final scheme = Theme.of(context).colorScheme;
    if (data.cajas.isEmpty) {
      return const EmptyState(
        icon: Icons.point_of_sale_outlined,
        title: 'Sin cajas en el período',
        message: 'No hay turnos de caja registrados para estas fechas.',
      );
    }
    final grupos = <String, _CajaGrupo>{};
    for (final item in data.cajas) {
      final fecha = parseSqlDate(item.caja.fecha);
      final etiqueta = switch (_agrupacionCajas) {
        'SEMANA' =>
          'Semana del ${formatDateShort(fecha.subtract(Duration(days: fecha.weekday - 1)))}',
        'MES' => '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}',
        'ANIO' => '${fecha.year}',
        _ => formatDateShort(fecha),
      };
      final grupo = grupos.putIfAbsent(
        etiqueta,
        () => _CajaGrupo(etiqueta: etiqueta),
      );
      grupo.turnos++;
      grupo.efectivo += item.resumen.ventasEfectivo;
      grupo.qr += item.resumen.ventasQr;
      grupo.salidas +=
          item.resumen.salidasEfectivo + item.resumen.salidasQr;
      grupo.esperado += item.resumen.totalEsperado;
      grupo.sobrante += item.caja.sobrante ?? 0;
      final rol = Perfil.nombres[item.caja.perfilApertura] ??
          item.caja.perfilApertura;
      grupo.cajeros.add(
        '${item.caja.usuarioApertura}${rol.isEmpty ? '' : ' ($rol)'}',
      );
    }
    final filas = grupos.values.toList();
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reporte de cajas',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Ventas en efectivo/QR, salidas y total esperado por turno.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opcion in const [
                    ('DIA', 'Día'),
                    ('SEMANA', 'Semana'),
                    ('MES', 'Mes'),
                    ('ANIO', 'Año'),
                  ])
                    ChoiceChip(
                      label: Text(opcion.$2),
                      selected: _agrupacionCajas == opcion.$1,
                      onSelected: (_) =>
                          setState(() => _agrupacionCajas = opcion.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Período')),
                    DataColumn(label: Text('Turnos'), numeric: true),
                    DataColumn(label: Text('Efectivo'), numeric: true),
                    DataColumn(label: Text('QR'), numeric: true),
                    DataColumn(label: Text('Salidas'), numeric: true),
                    DataColumn(label: Text('Esperado'), numeric: true),
                    DataColumn(label: Text('Sobrante'), numeric: true),
                    DataColumn(label: Text('Cajero(s)')),
                  ],
                  rows: filas
                      .map(
                        (grupo) => DataRow(
                          cells: [
                            DataCell(Text(grupo.etiqueta)),
                            DataCell(Text('${grupo.turnos}')),
                            DataCell(Text(formatMoney(grupo.efectivo))),
                            DataCell(Text(formatMoney(grupo.qr))),
                            DataCell(Text(formatMoney(grupo.salidas))),
                            DataCell(Text(formatMoney(grupo.esperado))),
                            DataCell(Text(formatMoney(grupo.sobrante))),
                            DataCell(
                              Text(
                                grupo.cajeros.join(', '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Detalle por turno',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...data.cajas.map((item) {
          final caja = item.caja;
          final rol = Perfil.nombres[caja.perfilApertura] ??
              caja.perfilApertura;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        caja.abierta
                            ? Icons.lock_open
                            : Icons.check_circle_outline,
                        color: caja.abierta
                            ? scheme.tertiary
                            : scheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${formatDateShort(parseSqlDate(caja.fecha))} · '
                          '${caja.turnoLabel} · '
                          '${caja.usuarioApertura}'
                          '${rol.isEmpty ? '' : ' ($rol)'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(caja.abierta ? 'ABIERTA' : 'CERRADA'),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Efectivo ${formatMoney(item.resumen.ventasEfectivo)} · '
                    'QR ${formatMoney(item.resumen.ventasQr)} · '
                    'Salidas ${formatMoney(item.resumen.salidasEfectivo + item.resumen.salidasQr)} · '
                    'Esperado ${formatMoney(item.resumen.totalEsperado)}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _anuladosTab(BuildContext context, _ReportData data) {
    final scheme = Theme.of(context).colorScheme;
    final total = data.devoluciones.fold<double>(
      0,
      (suma, devolucion) => suma + devolucion.monto,
    );
    final pedidosAnulados = data.devoluciones
        .map((devolucion) => devolucion.pedidoId)
        .toSet()
        .length;
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Ventas anuladas',
              value: '$pedidosAnulados',
              icon: Icons.assignment_return_outlined,
              color: scheme.error,
            ),
            StatCard(
              label: 'Total devuelto',
              value: formatMoney(total),
              icon: Icons.payments_outlined,
              color: scheme.error,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.devoluciones.isEmpty)
          const EmptyState(
            icon: Icons.assignment_return_outlined,
            title: 'Sin anulaciones',
            message: 'No hay ventas anuladas ni devueltas en el período.',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Pedido')),
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Usuario')),
                  DataColumn(label: Text('Método')),
                  DataColumn(label: Text('Monto'), numeric: true),
                  DataColumn(label: Text('Motivo')),
                ],
                rows: data.devoluciones
                    .map(
                      (devolucion) => DataRow(
                        cells: [
                          DataCell(Text('#${devolucion.pedidoId}')),
                          DataCell(
                            Text(
                              formatDateTimeShort(
                                parseSqlDateTime(devolucion.fecha) ??
                                    DateTime.now(),
                              ),
                            ),
                          ),
                          DataCell(Text(devolucion.usuarioNombre)),
                          DataCell(
                            Text(
                              devolucion.metodo == 'EFECTIVO'
                                  ? 'Efectivo'
                                  : 'QR',
                            ),
                          ),
                          DataCell(Text(formatMoney(devolucion.monto))),
                          DataCell(
                            Text(
                              (devolucion.motivo ?? '').isEmpty
                                  ? '—'
                                  : devolucion.motivo!,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _inventarioTab(BuildContext context, _ReportData data) {
    final total = data.inventario.fold<double>(
      0,
      (sum, item) => sum + item.valor,
    );
    final alertas = data.inventario.where((item) => item.alerta).length;
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Valor del inventario',
              value: formatMoney(total),
              icon: Icons.inventory_2_outlined,
            ),
            StatCard(
              label: 'Ítems con alerta',
              value: '$alertas',
              icon: Icons.warning_amber_rounded,
              color: alertas == 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            StatCard(
              label: 'Ítems controlados',
              value: '${data.inventario.length}',
              icon: Icons.list_alt_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (data.inventario.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin inventario controlado',
            message:
                'Crea insumos o productos directos para ver su stock y valor.',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Ítem')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Stock'), numeric: true),
                  DataColumn(label: Text('Mínimo'), numeric: true),
                  DataColumn(label: Text('Costo unit.'), numeric: true),
                  DataColumn(label: Text('Valor'), numeric: true),
                  DataColumn(label: Text('Alerta')),
                ],
                rows: data.inventario
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(item.nombre)),
                          DataCell(
                            Text(item.tipo == 'INSUMO' ? 'Insumo' : 'Producto'),
                          ),
                          DataCell(Text(formatQty(item.stock))),
                          DataCell(Text(formatQty(item.stockMinimo))),
                          DataCell(Text(formatMoney(item.costoUnitario))),
                          DataCell(Text(formatMoney(item.valor))),
                          DataCell(
                            item.alerta
                                ? Chip(
                                    label: const Text('Bajo'),
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                  )
                                : const Text('OK'),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _faltantesTab(BuildContext context, _ReportData data) {
    if (data.faltantes.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Sin faltantes en el período',
        message: 'Ninguna venta consumió más insumos de los disponibles.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final total = data.faltantes.fold<double>(
      0,
      (sum, item) => sum + item.costoFaltante,
    );
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Eventos registrados',
              value: '${data.faltantes.length}',
              icon: Icons.warning_amber_rounded,
              color: scheme.error,
            ),
            StatCard(
              label: 'Costo del faltante',
              value: formatMoney(total),
              icon: Icons.price_check,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Pedido')),
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Insumo')),
                DataColumn(label: Text('Requerido'), numeric: true),
                DataColumn(label: Text('Disponible'), numeric: true),
                DataColumn(label: Text('Faltante'), numeric: true),
                DataColumn(label: Text('Costo'), numeric: true),
              ],
              rows: data.faltantes
                  .map(
                    (item) => DataRow(
                      cells: [
                        DataCell(Text(formatDateTimeShort(item.fecha))),
                        DataCell(Text(item.referencia ?? '—')),
                        DataCell(Text(item.producto)),
                        DataCell(Text(item.insumo)),
                        DataCell(
                          Text('${formatQty(item.requerido)} ${item.unidad}'),
                        ),
                        DataCell(
                          Text('${formatQty(item.disponible)} ${item.unidad}'),
                        ),
                        DataCell(
                          Text(
                            '${formatQty(item.faltante)} ${item.unidad}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: scheme.error,
                            ),
                          ),
                        ),
                        DataCell(Text(formatMoney(item.costoFaltante))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _comprasTab(BuildContext context, _ReportData data) {
    if (data.compras.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_basket_outlined,
        title: 'Sin compras en el período',
        message: 'Registra compras desde la sección Insumos para verlas aquí.',
      );
    }
    final total = data.compras.fold<double>(
      0,
      (sum, compra) => sum + compra.subtotal,
    );
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Compras registradas',
              value: '${data.compras.length}',
              icon: Icons.shopping_basket_outlined,
            ),
            StatCard(
              label: 'Total comprado',
              value: formatMoney(total),
              icon: Icons.price_check,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Insumo')),
                DataColumn(label: Text('Cantidad'), numeric: true),
                DataColumn(label: Text('Costo unitario'), numeric: true),
                DataColumn(label: Text('Subtotal'), numeric: true),
              ],
              rows: data.compras
                  .map(
                    (compra) => DataRow(
                      cells: [
                        DataCell(Text(compra.codigo ?? '—')),
                        DataCell(Text(formatDateTimeText(compra.fecha))),
                        DataCell(Text(compra.insumo)),
                        DataCell(
                          Text('${formatQty(compra.cantidad)} ${compra.unidad}'),
                        ),
                        DataCell(Text(formatMoney(compra.costoUnitario))),
                        DataCell(Text(formatMoney(compra.subtotal))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _imprimirPedido(PedidoReporte pedido) async {
    try {
      final detalle = await SalesRepository().getPedido(pedido.id);
      await ReceiptService().imprimirNotaVenta(
        detalle: detalle,
        turno: pedido.turnoLabel,
        cajero: pedido.usuario,
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo generar la nota de venta: $error',
        error: true,
      );
    }
  }

  Widget _pedidosTab(BuildContext context, _ReportData data) {
    if (data.pedidos.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Sin pedidos en el período',
        message: 'No hay pedidos registrados para mostrar.',
      );
    }
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Pedido')),
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Cajero')),
                DataColumn(label: Text('Turno')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Efectivo'), numeric: true),
                DataColumn(label: Text('QR'), numeric: true),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Nota')),
              ],
              rows: data.pedidos
                  .map(
                    (pedido) => DataRow(
                      cells: [
                        DataCell(
                          Text(
                            pedido.referencia == null
                                ? '#${pedido.id}'
                                : '${pedido.referencia} · #${pedido.id}',
                          ),
                        ),
                        DataCell(Text(formatDateTimeText(pedido.fecha))),
                        DataCell(Text(pedido.usuario)),
                        DataCell(Text(pedido.turnoLabel)),
                        DataCell(Text(formatMoney(pedido.total))),
                        DataCell(Text(formatMoney(pedido.efectivo))),
                        DataCell(Text(formatMoney(pedido.qr))),
                        DataCell(Text(pedido.estadoPago)),
                        DataCell(
                          IconButton(
                            tooltip: 'Imprimir nota de venta',
                            onPressed: () => _imprimirPedido(pedido),
                            icon: const Icon(Icons.print_outlined),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  const _TabBarHeader({required this.tabBar, required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.color != color;
}

class _PedidoSoloLecturaDialog extends StatelessWidget {
  const _PedidoSoloLecturaDialog({required this.detalle});

  final PedidoDetalle detalle;

  @override
  Widget build(BuildContext context) {
    final pedido = detalle.pedido;
    final lineas = detalle.lineas.where((linea) => !linea.esComponente);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Pedido #${pedido.id}'),
      content: DialogSurface(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabelValue(
                label: 'Fecha',
                value: formatDateTimeText(pedido.fecha),
              ),
              LabelValue(label: 'Pago', value: pedido.estadoPago),
              LabelValue(label: 'Entrega', value: pedido.estadoEntrega),
              if (pedido.referencia != null)
                LabelValue(label: 'Referencia', value: pedido.referencia!),
              const Divider(height: 22),
              Text(
                'Productos',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final linea in lineas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatQty(linea.cantidad)} × ${linea.nombreParaMostrar}',
                        ),
                      ),
                      Text(formatMoney(linea.subtotal)),
                    ],
                  ),
                ),
              const Divider(height: 22),
              LabelValue(label: 'Total', value: formatMoney(pedido.total)),
              LabelValue(label: 'Pagado', value: formatMoney(pedido.pagado)),
              const Divider(height: 22),
              Text(
                'Pagos',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (detalle.pagos.isEmpty)
                const Text('Sin pagos registrados.')
              else
                for (final pago in detalle.pagos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${pago.metodo} · ${pago.estado}'),
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

/// Gráfico de torta de los productos vendidos (por ventas en Bs).
class _TortaPainter extends CustomPainter {
  const _TortaPainter({required this.valores, required this.colores});

  final List<double> valores;
  final List<Color> colores;

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold<double>(0, (suma, valor) => suma + valor);
    if (total <= 0) return;
    final centro = size.center(Offset.zero);
    final radio = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);
    var angulo = -math.pi / 2;
    for (var i = 0; i < valores.length; i++) {
      if (valores[i] <= 0) continue;
      final barrido = 2 * math.pi * (valores[i] / total);
      final pintura = Paint()
        ..style = PaintingStyle.fill
        ..color = colores[i];
      canvas.drawArc(rect, angulo, barrido, true, pintura);
      angulo += barrido;
    }
  }

  @override
  bool shouldRepaint(_TortaPainter oldDelegate) =>
      oldDelegate.valores != valores || oldDelegate.colores != colores;
}
