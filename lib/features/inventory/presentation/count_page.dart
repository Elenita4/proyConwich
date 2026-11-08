import 'package:flutter/material.dart';

import '../../../core/count_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _CountData {
  const _CountData({
    required this.conteo,
    required this.lineas,
    required this.historial,
  });

  final Conteo? conteo;
  final List<ConteoLinea> lineas;
  final List<Conteo> historial;
}

class CountPage extends StatefulWidget {
  const CountPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  final _repository = CountRepository();
  late Future<_CountData> _future;
  final _valores = <int, double>{};
  String _observacion = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_CountData> _load() async {
    final hoy = DateTime.now();
    final conteo = await _repository.getConteo(hoy);
    final lineas = conteo == null
        ? <ConteoLinea>[]
        : (await _repository.getDetalle(conteo.id)).lineas;
    final historial = await _repository.getHistorial();
    return _CountData(conteo: conteo, lineas: lineas, historial: historial);
  }

  Future<void> _iniciar() async {
    setState(() => _saving = true);
    try {
      await _repository.crearConteo(DateTime.now(), widget.usuario.id);
      _valores.clear();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(context, 'Conteo iniciado. Registra las cantidades.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'No se pudo iniciar el conteo: $error', error: true);
    }
  }

  Future<void> _guardar(_CountData data, {required bool cerrar}) async {
    final conteo = data.conteo;
    if (conteo == null) return;
    if (cerrar) {
      final confirmado = await confirmAction(
        context,
        title: 'Cerrar conteo',
        message:
            'Al cerrar el conteo, las diferencias ajustarán el stock del inventario. Esta acción no se puede deshacer.',
        confirmLabel: 'Cerrar conteo',
        destructive: true,
      );
      if (!confirmado) return;
    }
    final contados = <int, double>{
      for (final linea in data.lineas)
        linea.insumoId: _valores[linea.insumoId] ?? linea.stockContado,
    };
    setState(() => _saving = true);
    try {
      if (cerrar) {
        await _repository.cerrarConteo(
          conteo.id,
          contados,
          observacion: _observacion,
        );
      } else {
        await _repository.guardarBorrador(conteo.id, contados);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        cerrar ? 'Conteo cerrado y stock ajustado.' : 'Borrador guardado.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'No se pudo guardar: $error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CountData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Conteo de inventario',
                subtitle:
                    'Cuenta físicamente los insumos. Las diferencias se aplican al cerrar el conteo.',
                actions: [
                  if (data?.conteo == null)
                    FilledButton.icon(
                      onPressed: snapshot.hasData && !_saving
                          ? _iniciar
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar conteo de hoy'),
                    )
                  else
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
              else if (data == null || data.conteo == null)
                EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'No hay conteo para hoy',
                  message:
                      'Inicia el conteo para comparar el stock del sistema con lo contado físicamente.',
                  action: FilledButton.icon(
                    onPressed: _iniciar,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar conteo'),
                  ),
                )
              else ...[
                _conteoCard(context, data),
                const SizedBox(height: 20),
                Text(
                  'Historial de conteos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (data.historial.isEmpty)
                  const Text('Todavía no hay conteos registrados.')
                else
                  ...data.historial.map(
                    (conteo) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              conteo.cerrado
                                  ? Icons.check_circle_outline
                                  : Icons.edit_note,
                              color: conteo.cerrado
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${conteo.fecha} · ${conteo.usuarioNombre}',
                              ),
                            ),
                            Chip(
                              label: Text(conteo.estado),
                              side: BorderSide.none,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _conteoCard(BuildContext context, _CountData data) {
    final conteo = data.conteo!;
    final scheme = Theme.of(context).colorScheme;
    final editable = !conteo.cerrado;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Conteo del ${conteo.fecha}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Chip(
                label: Text(conteo.estado),
                side: BorderSide.none,
                backgroundColor: editable
                    ? scheme.tertiaryContainer
                    : scheme.primaryContainer,
              ),
              const Spacer(),
              Text(
                'Responsable: ${conteo.usuarioNombre}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (conteo.observacion != null) ...[
            const SizedBox(height: 8),
            Text(
              'Observación: ${conteo.observacion}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          if (data.lineas.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No hay insumos para contar',
              message:
                  'Crea insumos con control de stock para incluirlos en el conteo.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('Insumo')),
                  DataColumn(label: Text('Unidad')),
                  DataColumn(label: Text('Sistema')),
                  DataColumn(label: Text('Contado')),
                  DataColumn(label: Text('Diferencia')),
                ],
                rows: data.lineas.map((linea) {
                  final contado =
                      _valores[linea.insumoId] ?? linea.stockContado;
                  final diferencia = contado - linea.stockSistema;
                  return DataRow(
                    cells: [
                      DataCell(Text(linea.nombre)),
                      DataCell(Text(linea.unidad)),
                      DataCell(Text(formatQty(linea.stockSistema))),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: editable
                              ? TextFormField(
                                  initialValue: formatQty(linea.stockContado),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '0',
                                  ),
                                  onChanged: (value) {
                                    _valores[linea.insumoId] = parseAmount(
                                      value,
                                    );
                                    setState(() {});
                                  },
                                )
                              : Text(formatQty(linea.stockContado)),
                        ),
                      ),
                      DataCell(
                        Text(
                          formatQty(diferencia),
                          style: TextStyle(
                            color: diferencia == 0
                                ? scheme.onSurfaceVariant
                                : diferencia > 0
                                ? scheme.primary
                                : scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          if (editable) ...[
            const SizedBox(height: 16),
            TextFormField(
              maxLines: 2,
              decoration: appInput(
                label: 'Observación del conteo (opcional)',
              ),
              onChanged: (value) => _observacion = value,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _guardar(data, cerrar: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar borrador'),
                ),
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _guardar(data, cerrar: true),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar conteo'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
