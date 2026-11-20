import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/backup/drive_backup_service.dart';
import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/printer/printer_service.dart';
import '../../../core/receipt_service.dart';
import '../../../core/session.dart';
import '../../../data/database/app_database.dart';
import '../../../ui/common.dart';

class _CashData {
  const _CashData({
    required this.caja,
    required this.resumen,
    required this.historial,
    required this.proximoTurno,
  });

  final Caja? caja;
  final CajaResumen? resumen;
  final List<CajaHistorial> historial;
  final int proximoTurno;
}

class CashPage extends StatefulWidget {
  const CashPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  final _repository = CashRepository();
  late Future<_CashData> _future;
  late final TextEditingController _fondo;
  late final TextEditingController _sobrante;
  late final TextEditingController _observacion;
  late DateTime _fecha;
  int? _resumenCajaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    _fondo = TextEditingController(text: '0');
    _sobrante = TextEditingController(text: '0');
    _observacion = TextEditingController();
    _reload();
  }

  @override
  void didUpdateWidget(CashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  @override
  void dispose() {
    _fondo.dispose();
    _sobrante.dispose();
    _observacion.dispose();
    super.dispose();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_CashData> _load() async {
    final caja = await _repository.getCajaAbierta();
    CajaResumen? resumen;
    if (caja != null) {
      resumen = await _repository.getResumen(caja.id);
      if (_resumenCajaId != caja.id) {
        _resumenCajaId = caja.id;
        _sobrante.text = '0';
      }
    } else {
      _resumenCajaId = null;
    }
    final historial = await _repository.getCajasDelDia(_fecha);
    final proximoTurno = await _repository.proximoTurno(_fecha);
    return _CashData(
      caja: caja,
      resumen: resumen,
      historial: historial,
      proximoTurno: proximoTurno,
    );
  }

  Future<void> _abrir() async {
    final error = validateDecimalAmount(_fondo.text, label: 'El fondo inicial');
    if (error != null) {
      showAppMessage(context, error, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final caja = await _repository.abrirCaja(
        fecha: _fecha,
        fondoInicial: parseAmount(_fondo.text),
        usuarioId: widget.usuario.id,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(context, 'Caja abierta como ${caja.turnoLabel}.');
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
    final error = validateSignedAmount(
      _sobrante.text,
      label: 'El sobrante del turno',
    );
    if (error != null) {
      showAppMessage(context, error, error: true);
      return;
    }
    final sobrante = parseAmount(_sobrante.text);
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar caja',
      message:
          'Se cerrará la caja del ${caja.turnoLabel}. '
          'Total esperado: ${formatMoney(resumen.totalEsperado)} · '
          'Sobrante: ${formatMoney(sobrante)}. '
          'El menú del día seguirá abierto para los próximos turnos. ¿Continuar?',
      confirmLabel: 'Cerrar caja',
      destructive: true,
    );
    if (!confirmado) return;
    setState(() => _saving = true);
    try {
      await _repository.cerrarCaja(
        cajaId: caja.id,
        usuarioId: widget.usuario.id,
        sobrante: sobrante,
        observacion: _observacion.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _observacion.clear();
        _sobrante.text = '0';
        _reload();
      });
      showAppMessage(context, 'Caja cerrada correctamente.');
      _respaldarDriveEnSegundoPlano();
      await _ofrecerImprimirMovimiento(caja, resumen, sobrante);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'No se pudo cerrar la caja: $error', error: true);
    }
  }

  Future<void> _ofrecerImprimirMovimiento(
    Caja caja,
    CajaResumen resumen,
    double sobrante,
  ) async {
    final imprimir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Movimiento del turno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelValue(
              label: 'Ventas efectivo',
              value: formatMoney(resumen.ventasEfectivo),
            ),
            LabelValue(
              label: 'Ventas QR',
              value: formatMoney(resumen.ventasQr),
            ),
            LabelValue(
              label: 'Salida efectivo',
              value: formatMoney(resumen.salidasEfectivo),
            ),
            LabelValue(
              label: 'Sobrante del turno',
              value: formatMoney(sobrante),
            ),
            const Divider(height: 18),
            LabelValue(
              label: 'Total esperado',
              value: formatMoney(resumen.totalEsperado),
              strong: true,
            ),
            const SizedBox(height: 8),
            const Text('¿Deseas imprimir el movimiento del turno?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (imprimir != true) return;
    final meta = await AppDatabase.instance.leerAppMeta();
    final mac = (meta?['impresora_mac'] as String?) ?? '';
    final printer = PrinterService();
    if (mac.isNotEmpty && printer.disponible) {
      try {
        await printer.imprimirMovimientoTurno(
          caja: caja,
          resumen: resumen,
          sobrante: sobrante,
          cajero: widget.usuario.nombre,
          mac: mac,
        );
        return;
      } catch (error) {
        if (!mounted) return;
        showAppMessage(
          context,
          'No se pudo imprimir por Bluetooth: $error. Se abrirá el PDF.',
          error: true,
        );
      }
    }
    try {
      await ReceiptService().imprimirMovimientoTurno(
        caja: caja,
        resumen: resumen,
        sobrante: sobrante,
        cajero: widget.usuario.nombre,
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo generar el movimiento del turno: $error',
        error: true,
      );
    }
  }

  void _respaldarDriveEnSegundoPlano() {
    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await DriveBackupService().respaldarSiCorresponde(
            motivo: 'cierre_caja',
          );
        } catch (error) {
          if (!mounted) return;
          showAppMessage(
            context,
            'No se pudo guardar la copia en Drive: $error',
            error: true,
          );
        }
      }),
    );
  }

  Future<void> _salida(_CashData data) async {
    final caja = data.caja;
    if (caja == null) return;
    final salida = await showDialog<_SalidaInput>(
      context: context,
      builder: (_) => const _SalidaDialog(),
    );
    if (salida == null) return;
    setState(() => _saving = true);
    try {
      await _repository.registrarSalida(
        cajaId: caja.id,
        usuarioId: widget.usuario.id,
        monto: salida.monto,
        metodoPago: salida.metodo,
        descripcion: salida.descripcion,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(context, 'Salida registrada.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'No se pudo registrar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CashData>(
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
                title: 'Caja',
                subtitle: 'Varios turnos por día (Turno 1, 2, 3…). Una caja abierta a la vez. El fondo inicial no es un ingreso.',
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
                  _aperturaCard(context, data)
                else
                  _cajaAbierta(context, data),
                const SizedBox(height: 22),
                Text(
                  'Historial de cajas de hoy (${data.historial.length})',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (data.historial.isEmpty)
                  const Text('Todavía no hay cajas registradas.')
                else
                  ...data.historial.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CajaHistorialRow(item: item),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _aperturaCard(BuildContext context, _CashData data) {
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
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'El turno se asigna automáticamente y puedes abrir varias cajas en el mismo día.',
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
                      setState(() {
                        _fecha = DateTime(
                          elegida.year,
                          elegida.month,
                          elegida.day,
                        );
                        _reload();
                      });
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
                child: InputDecorator(
                  decoration: appInput(label: 'Turno', icon: Icons.numbers),
                  child: Text('Turno ${data.proximoTurno}'),
                ),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _fondo,
                  inputFormatters: [decimalAmountInputFormatter],
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final angosto = esAngosto(constraints.maxWidth, limite: 700);
                  final informacion = Row(
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
                              'Caja abierta · ${caja.turnoLabel}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${formatDateShort(parseSqlDate(caja.fecha))} · apertura ${formatDateTimeText(caja.fechaApertura)}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            Text(
                              'Cajero: ${caja.usuarioApertura}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final acciones = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: const Text('ABIERTA'),
                        backgroundColor: scheme.primaryContainer,
                        side: BorderSide.none,
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _salida(data),
                        icon: const Icon(Icons.outbox),
                        label: const Text('Salida de caja'),
                      ),
                    ],
                  );
                  if (angosto) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        informacion,
                        const SizedBox(height: 10),
                        acciones,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: informacion),
                      const SizedBox(width: 8),
                      acciones,
                    ],
                  );
                },
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
                    label: 'Salidas de caja',
                    value: formatMoney(
                      resumen.salidasEfectivo + resumen.salidasQr,
                    ),
                    caption:
                        'Efectivo ${formatMoney(resumen.salidasEfectivo)} · QR ${formatMoney(resumen.salidasQr)}',
                    icon: Icons.outbox,
                    color: scheme.secondary,
                  ),
                  StatCard(
                    label: 'Total esperado del turno',
                    value: formatMoney(resumen.totalEsperado),
                    caption: 'Efectivo + QR − salidas',
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
                    children: [movimientos, const SizedBox(height: 12), cierre],
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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LabelValue(
            label: 'Ventas efectivo',
            value: formatMoney(resumen.ventasEfectivo),
          ),
          LabelValue(label: 'Ventas QR', value: formatMoney(resumen.ventasQr)),
          LabelValue(
            label: 'Salidas efectivo',
            value: '- ${formatMoney(resumen.salidasEfectivo)}',
          ),
          LabelValue(
            label: 'Salidas QR',
            value: '- ${formatMoney(resumen.salidasQr)}',
          ),
          const Divider(height: 22),
          LabelValue(
            label: 'Total esperado del turno',
            value: formatMoney(resumen.totalEsperado),
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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sobrante,
            inputFormatters: [signedDecimalAmountInputFormatter],
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: appInput(
              label: 'Sobrante del turno (Bs)',
              icon: Icons.payments_outlined,
              hint: 'Positivo si sobra, negativo si falta',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          LabelValue(
            label: 'Total esperado',
            value: formatMoney(resumen.totalEsperado),
            strong: true,
          ),
          LabelValue(
            label: 'Sobrante / faltante',
            value: formatMoney(parseAmount(_sobrante.text)),
          ),
          const Divider(height: 18),
          LabelValue(
            label: 'Total en caja',
            value: formatMoney(
              resumen.totalEsperado + parseAmount(_sobrante.text),
            ),
            strong: true,
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

class _SalidaInput {
  const _SalidaInput({
    required this.monto,
    required this.metodo,
    this.descripcion,
  });

  final double monto;
  final String metodo;
  final String? descripcion;
}

class _SalidaDialog extends StatefulWidget {
  const _SalidaDialog();

  @override
  State<_SalidaDialog> createState() => _SalidaDialogState();
}

class _SalidaDialogState extends State<_SalidaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _monto = TextEditingController();
  final _descripcion = TextEditingController();
  String _metodo = 'EFECTIVO';

  @override
  void dispose() {
    _monto.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Salida de caja'),
      content: DialogSurface(
        maxWidth: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _metodo,
                decoration: appInput(label: 'Método de pago'),
                items: const [
                  DropdownMenuItem(value: 'EFECTIVO', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'QR', child: Text('QR')),
                ],
                onChanged: (value) =>
                    setState(() => _metodo = value ?? 'EFECTIVO'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monto,
                inputFormatters: [decimalAmountInputFormatter],
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(
                  label: 'Monto (Bs)',
                  icon: Icons.money_outlined,
                ),
                validator: (value) => validateDecimalAmount(
                  value,
                  allowZero: false,
                  label: 'El monto',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcion,
                decoration: appInput(
                  label: 'Motivo (opcional)',
                  hint: 'Ej. luz, gas, sueldo',
                ),
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _SalidaInput(
                monto: parseAmount(_monto.text),
                metodo: _metodo,
                descripcion: _descripcion.text,
              ),
            );
          },
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _CajaHistorialRow extends StatelessWidget {
  const _CajaHistorialRow({required this.item});

  final CajaHistorial item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caja = item.caja;
    final resumen = item.resumen;
    final rol = Perfil.nombres[caja.perfilApertura] ?? caja.perfilApertura;
    final cierre = parseSqlDateTime(caja.fechaCierre);
    final icono = Icon(
      caja.abierta ? Icons.lock_open : Icons.check_circle_outline,
      color: caja.abierta ? scheme.tertiary : scheme.primary,
    );
    final detalle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatDateShort(parseSqlDate(caja.fecha))} · ${caja.turnoLabel}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          'Cajero: ${caja.usuarioApertura}${rol.isEmpty ? '' : ' · $rol'}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        Text(
          'Efectivo ${formatMoney(resumen.ventasEfectivo)} · '
          'QR ${formatMoney(resumen.ventasQr)} · '
          'Salida ${formatMoney(resumen.salidasEfectivo + resumen.salidasQr)}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final totales = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Esperado ${formatMoney(resumen.totalEsperado)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (!caja.abierta)
          Text(
            'Sobrante ${formatMoney(caja.sobrante ?? 0)}',
            style: TextStyle(
              color: (caja.sobrante ?? 0) < 0 ? scheme.error : scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (cierre != null)
          Text(
            'Cierre ${formatTimeShort(cierre)}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
      ],
    );
    final estado = Chip(
      label: Text(caja.abierta ? 'ABIERTA' : 'CERRADA'),
      side: BorderSide.none,
      backgroundColor: caja.abierta
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      visualDensity: VisualDensity.compact,
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!esAngosto(constraints.maxWidth, limite: 760)) {
            return Row(
              children: [
                icono,
                const SizedBox(width: 12),
                Expanded(child: detalle),
                const SizedBox(width: 12),
                totales,
                const SizedBox(width: 12),
                estado,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icono,
                  const SizedBox(width: 10),
                  Expanded(child: detalle),
                  estado,
                ],
              ),
              const SizedBox(height: 6),
              totales,
            ],
          );
        },
      ),
    );
  }
}
