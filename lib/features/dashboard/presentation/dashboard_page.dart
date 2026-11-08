import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/report_repository.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardData {
  const _DashboardData({
    required this.resumen,
    required this.caja,
    required this.pedidosAbiertos,
    required this.alertas,
    required this.menu,
    required this.itemsMenu,
  });

  final ResumenFinanciero resumen;
  final Caja? caja;
  final int pedidosAbiertos;
  final List<InventarioReporte> alertas;
  final MenuDia? menu;
  final int itemsMenu;
}

class _DashboardPageState extends State<DashboardPage> {
  final _reportRepository = ReportRepository();
  final _cashRepository = CashRepository();
  final _salesRepository = SalesRepository();
  final _menuRepository = MenuRepository();
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final resumen = await _reportRepository.getResumen(
      today,
      today.add(const Duration(days: 1)),
    );
    final caja = await _cashRepository.getCajaAbierta();
    final abiertos = await _salesRepository.getPedidosAbiertos();
    final alertas = await _reportRepository.getAlertasStock();
    final tipo = caja == null
        ? (now.hour < 12 ? 'DESAYUNO' : 'ALMUERZO')
        : MenuRepository.tipoDesdeTurno(caja.turno);
    final menu = await _menuRepository.getMenu(today, tipo);
    final items = menu == null ? 0 : (await _menuRepository.getItems(menu.id)).length;
    return _DashboardData(
      resumen: resumen,
      caja: caja,
      pedidosAbiertos: abiertos.length,
      alertas: alertas,
      menu: menu,
      itemsMenu: items,
    );
  }

  String get _saludo {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final puedeReportes = widget.usuario.puede(Permiso.reportes);
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: '$_saludo, ${widget.usuario.nombre}',
                subtitle: formatDateShort(DateTime.now()),
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
              else ...[
                _buildBody(context, snapshot.data!, puedeReportes),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    _DashboardData data,
    bool puedeReportes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.caja == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.error),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No hay una caja abierta. Abre la caja para poder registrar ventas.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (puedeReportes)
          StatGrid(
            children: [
              StatCard(
                label: 'Ventas del día',
                value: formatMoney(data.resumen.ventas),
                caption: '${data.resumen.pedidos} pedidos',
                icon: Icons.trending_up,
              ),
              StatCard(
                label: 'Cobros del día',
                value: formatMoney(data.resumen.cobros),
                caption:
                    'Efectivo ${formatMoney(data.resumen.cobrosEfectivo)} · QR ${formatMoney(data.resumen.cobrosQr)}',
                icon: Icons.payments_outlined,
                color: scheme.tertiary,
              ),
              StatCard(
                label: 'Resultado estimado',
                value: formatMoney(data.resumen.resultado),
                caption: 'Ventas − costo de insumos − gastos',
                icon: Icons.insights,
                color: data.resumen.resultado >= 0
                    ? scheme.primary
                    : scheme.error,
              ),
              StatCard(
                label: 'Flujo de caja',
                value: formatMoney(data.resumen.flujoCaja),
                caption: 'Cobros − compras − gastos − sueldos',
                icon: Icons.account_balance_outlined,
                color: scheme.secondary,
              ),
            ],
          )
        else
          StatGrid(
            children: [
              StatCard(
                label: 'Pedidos abiertos',
                value: '${data.pedidosAbiertos}',
                icon: Icons.pending_actions_outlined,
              ),
              StatCard(
                label: 'Caja',
                value: data.caja == null ? 'Cerrada' : 'Abierta',
                caption: data.caja == null
                    ? 'Abre una caja para vender'
                    : 'Turno ${data.caja!.turno}',
                icon: Icons.account_balance_wallet_outlined,
                color: data.caja == null ? scheme.error : scheme.primary,
              ),
              StatCard(
                label: 'Alertas de stock',
                value: '${data.alertas.length}',
                icon: Icons.inventory_2_outlined,
                color: data.alertas.isEmpty ? scheme.primary : scheme.error,
              ),
            ],
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 980;
            final caja = _cajaCard(context, data.caja);
            final alertas = _alertasCard(context, data.alertas);
            final menu = _menuCard(context, data.menu, data.itemsMenu);
            if (horizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: caja),
                  const SizedBox(width: 16),
                  Expanded(child: menu),
                  const SizedBox(width: 16),
                  Expanded(child: alertas),
                ],
              );
            }
            return Column(
              children: [
                caja,
                const SizedBox(height: 12),
                menu,
                const SizedBox(height: 12),
                alertas,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (puedeReportes) _resumenDetallado(context, data.resumen),
      ],
    );
  }

  Widget _cajaCard(BuildContext context, Caja? caja) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Caja',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Chip(
                label: Text(caja == null ? 'Cerrada' : 'Abierta'),
                backgroundColor: caja == null
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (caja == null)
            Text(
              'Sin turno activo. Abre la caja desde la sección Caja.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            LabelValue(label: 'Turno', value: caja.turno),
            LabelValue(
              label: 'Fondo inicial',
              value: formatMoney(caja.fondoInicial),
            ),
            LabelValue(
              label: 'Apertura',
              value: formatDateTimeText(caja.fechaApertura),
            ),
            LabelValue(label: 'Responsable', value: caja.usuarioApertura),
          ],
        ],
      ),
    );
  }

  Widget _menuCard(BuildContext context, MenuDia? menu, int items) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Menú de hoy',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (menu == null)
            Text(
              'Aún no se creó el menú del día.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            LabelValue(label: 'Tipo', value: menu.tipo),
            LabelValue(label: 'Estado', value: menu.estado),
            LabelValue(label: 'Platos', value: '$items'),
            if (menu.observacion != null)
              LabelValue(label: 'Nota', value: menu.observacion!),
          ],
        ],
      ),
    );
  }

  Widget _alertasCard(
    BuildContext context,
    List<InventarioReporte> alertas,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: alertas.isEmpty ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Alertas de stock',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${alertas.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: alertas.isEmpty ? scheme.primary : scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (alertas.isEmpty)
            Text(
              'Todo el inventario está por encima del mínimo.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ...alertas.take(6).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.nombre)),
                    Text(
                      '${formatQty(item.stock)} / ${formatQty(item.stockMinimo)}',
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resumenDetallado(BuildContext context, ResumenFinanciero resumen) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen financiero de hoy',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 3 : 1;
              final items = [
                LabelValue(
                  label: 'Ventas',
                  value: formatMoney(resumen.ventas),
                  strong: true,
                ),
                LabelValue(
                  label: 'Costo de insumos vendidos (COGS)',
                  value: formatMoney(resumen.cogs),
                ),
                LabelValue(
                  label: 'Compras del día',
                  value: formatMoney(resumen.compras),
                ),
                LabelValue(
                  label: 'Gastos',
                  value: formatMoney(resumen.gastos),
                ),
                LabelValue(
                  label: 'Sueldos',
                  value: formatMoney(resumen.sueldos),
                ),
                LabelValue(
                  label: 'Ticket promedio',
                  value: formatMoney(resumen.ticketPromedio),
                ),
              ];
              if (columns == 1) return Column(children: items);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++)
                    Expanded(
                      child: Column(
                        children: [
                          for (var j = i; j < items.length; j += columns)
                            items[j],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Resultado (ventas − COGS − gastos − sueldos)',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                formatMoney(resumen.resultado),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: resumen.resultado >= 0 ? scheme.primary : scheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
