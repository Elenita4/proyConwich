import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _CashData {
  const _CashData({
    required this.caja,
    required this.resumen,
    required this.historial,
  });

  final Caja? caja;
  final CajaResumen? resumen;
  final List<Caja> historial;
}

class CashPage extends StatefulWidget {
  const CashPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  final _repository = CashRepository();
  late Future<_CashData> _future;
  late final TextEditingController _fondo;
  late final TextEditingController _efectivo;
  late final TextEditingController _qr;
  late final TextEditingController _observacion;
  late DateTime _fecha;
  late String _turno;
  int? _resumenCajaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    final asignado = widget.usuario.turnoAsignado;
    _turno = asignado == 'MAÑANA' || asignado == 'TARDE'
        ? asignado!
        : (now.hour < 12 ? 'MAÑANA' : 'TARDE');
    _fondo = TextEditingController(text: '0');
    _efectivo = TextEditingController();
    _qr = TextEditingController();
    _observacion = TextEditingController();
    _reload();
  }

  @override
  void dispose() {
    _fondo.dispose();
    _efectivo.dispose();
    _qr.dispose();
    _observacion.dispose();
    super.dispose();
  }

  void _reload() => _future = _load();

  Future<_CashData> _load() async {
    final caja = await _repository.getCajaAbierta();
    CajaResumen? resumen;
    if (caja != null) {
      resumen = await _repository.getResumen(caja.id);
      if (_resumenCajaId != caja.id) {
        _resumenCajaId = caja.id;
        _efectivo.text = resumen.esperadoEfectivo.toStringAsFixed(2);
        _qr.text = resumen.esperadoQr.toStringAsFixed(2);
      }
    } else {
      _resumenCajaId = null;
    }
    final historial = await _repository.getCajas();
    return _CashData(caja: caja, resumen: resumen, historial: historial);
  }

  Future<void> _abrir() async {
    setState(() => _saving = true);
    try {
      await _repository.abrirCaja(
        fecha: _fecha,
        turno: _turno,
        fondoInicial: parseAmount(_fondo.text),
        usuarioId: widget.usuario.id,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(context, 'Caja abierta para el turno $_turno.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  Future<void> _cerrar(_CashData data) async {
    final caja = data.caja;
    final resumen = data.resumen;
    if (caja == null || resumen == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar caja',
      message:
          'Se cerrará la caja del turno ${caja.turno} y el menú publicado del turno quedará cerrado. ¿Continuar?',
      confirmLabel: 'Cerrar caja',
      destructive: true,
    );
    if (!confirmado) return;
    setState(() => _saving = true);
    try {
      await _repository.cerrarCaja(
        cajaId: caja.id,
        efectivoContado: parseAmount(_efectivo.text),
        qrVerificado: parseAmount(_qr.text),
        usuarioId: widget.usuario.id,
        observacion: _observacion.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _observacion.clear();
        _reload();
      });
      showAppMessage(context, 'Caja cerrada correctamente.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'No se pudo cerrar la caja: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CashData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Caja',
                subtitle:
                    'Una caja abierta a la vez. El fondo inicial no es un ingreso.',
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
              else ...[
                if (data.caja == null)
                  _aperturaCard(context)
                else
                  _cajaAbierta(context, data),
                const SizedBox(height: 22),
                Text(
                  'Historial de cajas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (data.historial.isEmpty)
                  const Text('Todavía no hay cajas registradas.')
                else
                  ...data.historial.map(
                    (caja) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CajaHistorialRow(caja: caja),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _aperturaCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Abrir caja',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Registra el turno y el fondo inicial en efectivo.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: InkWell(
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 7),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 7)),
                    );
                    if (elegida != null) {
                      setState(
                        () => _fecha = DateTime(
                          elegida.year,
                          elegida.month,
                          elegida.day,
                        ),
                      );
                    }
                  },
                  child: InputDecorator(
                    decoration: appInput(
                      label: 'Fecha',
                      icon: Icons.calendar_today_outlined,
                    ),
                    child: Text(formatDateShort(_fecha)),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _turno,
                  decoration: appInput(label: 'Turno'),
                  items: const [
                    DropdownMenuItem(value: 'MAÑANA', child: Text('Mañana')),
                    DropdownMenuItem(value: 'TARDE', child: Text('Tarde')),
                  ],
                  onChanged: (value) =>
                      setState(() => _turno = value ?? 'MAÑANA'),
                ),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _fondo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: appInput(
                    label: 'Fondo inicial (Bs)',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _abrir,
            icon: const Icon(Icons.lock_open),
            label: Text(_saving ? 'Abriendo…' : 'Abrir caja'),
          ),
        ],
      ),
    );
  }

  Widget _cajaAbierta(BuildContext context, _CashData data) {
    final caja = data.caja!;
    final resumen = data.resumen!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Caja abierta · Turno ${caja.turno}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${formatDateShort(parseSqlDate(caja.fecha))} · apertura ${formatDateTimeText(caja.fechaApertura)} · ${caja.usuarioApertura}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: const Text('ABIERTA'),
                    backgroundColor: scheme.primaryContainer,
                    side: BorderSide.none,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              StatGrid(
                children: [
                  StatCard(
                    label: 'Fondo inicial',
                    value: formatMoney(resumen.fondoInicial),
                    icon: Icons.savings_outlined,
                  ),
                  StatCard(
                    label: 'Ventas en efectivo',
                    value: formatMoney(resumen.ventasEfectivo),
                    icon: Icons.payments_outlined,
                    color: scheme.primary,
                  ),
                  StatCard(
                    label: 'Ventas por QR',
                    value: formatMoney(resumen.ventasQr),
                    icon: Icons.qr_code_2,
                    color: scheme.tertiary,
                  ),
                  StatCard(
                    label: 'Efectivo esperado',
                    value: formatMoney(resumen.esperadoEfectivo),
                    caption: 'Fondo + ventas − salidas',
                    icon: Icons.calculate_outlined,
                    color: scheme.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 850;
                  final movimientos = _movimientos(context, resumen);
                  final cierre = _cierreForm(context, data);
                  if (horizontal) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: movimientos),
                        const SizedBox(width: 16),
                        Expanded(child: cierre),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      movimientos,
                      const SizedBox(height: 12),
                      cierre,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _movimientos(BuildContext context, CajaResumen resumen) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movimientos del turno',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LabelValue(
            label: 'Ventas efectivo',
            value: formatMoney(resumen.ventasEfectivo),
          ),
          LabelValue(
            label: 'Ventas QR',
            value: formatMoney(resumen.ventasQr),
          ),
          LabelValue(
            label: 'Compras efectivo',
            value: '- ${formatMoney(resumen.comprasEfectivo)}',
          ),
          LabelValue(
            label: 'Compras QR',
            value: '- ${formatMoney(resumen.comprasQr)}',
          ),
          LabelValue(
            label: 'Gastos efectivo',
            value: '- ${formatMoney(resumen.gastosEfectivo)}',
          ),
          LabelValue(
            label: 'Gastos QR',
            value: '- ${formatMoney(resumen.gastosQr)}',
          ),
          LabelValue(
            label: 'Sueldos efectivo',
            value: '- ${formatMoney(resumen.sueldosEfectivo)}',
          ),
          LabelValue(
            label: 'Sueldos QR',
            value: '- ${formatMoney(resumen.sueldosQr)}',
          ),
          const Divider(height: 22),
          LabelValue(
            label: 'Esperado efectivo',
            value: formatMoney(resumen.esperadoEfectivo),
            strong: true,
          ),
          LabelValue(
            label: 'Esperado QR',
            value: formatMoney(resumen.esperadoQr),
            strong: true,
          ),
        ],
      ),
    );
  }

  Widget _cierreForm(BuildContext context, _CashData data) {
    final resumen = data.resumen!;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cerrar caja',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _efectivo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: appInput(
              label: 'Efectivo contado (Bs)',
              icon: Icons.payments_outlined,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _Diferencia(
            diferencia: parseAmount(_efectivo.text) - resumen.esperadoEfectivo,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: appInput(
              label: 'QR verificado (Bs)',
              icon: Icons.qr_code_2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _Diferencia(
            diferencia: parseAmount(_qr.text) - resumen.esperadoQr,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _observacion,
            maxLines: 2,
            decoration: appInput(label: 'Observación (opcional)'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _cerrar(data),
              icon: const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Cerrando…' : 'Cerrar caja'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Diferencia extends StatelessWidget {
  const _Diferencia({required this.diferencia});

  final double diferencia;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = diferencia == 0
        ? scheme.onSurfaceVariant
        : diferencia > 0
        ? scheme.primary
        : scheme.error;
    return Row(
      children: [
        Text(
          diferencia == 0
              ? 'Sin diferencia'
              : diferencia > 0
              ? 'Sobrante'
              : 'Faltante',
          style: TextStyle(color: color),
        ),
        const Spacer(),
        Text(
          formatMoney(diferencia.abs()),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CajaHistorialRow extends StatelessWidget {
  const _CajaHistorialRow({required this.caja});

  final Caja caja;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            caja.abierta
                ? Icons.lock_open
                : Icons.check_circle_outline,
            color: caja.abierta ? scheme.tertiary : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '${formatDateShort(parseSqlDate(caja.fecha))} · ${caja.turno}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Fondo ${formatMoney(caja.fondoInicial)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              caja.fechaCierre == null
                  ? 'Sin cerrar'
                  : 'Cierre ${formatDateTimeText(caja.fechaCierre!)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          if (caja.efectivoContado != null)
            Text(
              'Efectivo contado ${formatMoney(caja.efectivoContado!)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(width: 10),
          Chip(
            label: Text(caja.estado),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
