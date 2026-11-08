import 'package:flutter/material.dart';

import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../ui/common.dart';

class _InsumosData {
  const _InsumosData({required this.insumos, required this.unidades});

  final List<Insumo> insumos;
  final List<UnidadMedida> unidades;
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repository = CatalogRepository();
  late Future<_InsumosData> _future;
  String _search = '';
  bool _soloActivos = false;
  bool _soloAlertas = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_InsumosData> _load() async {
    final insumos = await _repository.getInsumos();
    final unidades = await _repository.getUnidades();
    return _InsumosData(insumos: insumos, unidades: unidades);
  }

  Future<void> _openForm([Insumo? insumo]) async {
    final data = await _future;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _InsumoDialog(
        repository: _repository,
        unidades: data.unidades,
        insumo: insumo,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Insumo guardado correctamente.');
    }
  }

  Future<void> _toggleActivo(Insumo insumo, bool activo) async {
    await _repository.setInsumoActivo(insumo.id!, activo);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _toggleDisponible(Insumo insumo, bool disponible) async {
    await _repository.setInsumoDisponible(insumo.id!, disponible);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InsumosData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final insumos = data?.insumos ?? [];
        final filtrados = insumos.where((insumo) {
          if (_soloActivos && !insumo.activo) return false;
          if (_soloAlertas && !insumo.bajoStock) return false;
          final term = _search.trim().toLowerCase();
          return term.isEmpty || insumo.nombre.toLowerCase().contains(term);
        }).toList();
        final alertas = insumos.where((insumo) => insumo.bajoStock).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Insumos',
                subtitle:
                    'Materias primas y su control de stock. El stock se calcula con compras, consumos y conteos.',
                actions: [
                  FilledButton.icon(
                    onPressed: snapshot.hasData ? () => _openForm() : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo insumo'),
                  ),
                ],
              ),
              if (alertas > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppCard(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.35),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$alertas insumo(s) por debajo o en el stock mínimo.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        decoration: appInput(
                          label: 'Buscar insumo',
                          icon: Icons.search,
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Solo activos'),
                      selected: _soloActivos,
                      onSelected: (value) =>
                          setState(() => _soloActivos = value),
                    ),
                    FilterChip(
                      label: const Text('Solo alertas'),
                      selected: _soloAlertas,
                      onSelected: (value) =>
                          setState(() => _soloAlertas = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else if (filtrados.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No hay insumos que coincidan',
                  message: insumos.isEmpty
                      ? 'Crea el primer insumo para controlar el inventario.'
                      : 'Ajusta la búsqueda o los filtros.',
                  action: insumos.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('Crear insumo'),
                        )
                      : null,
                )
              else
                ...filtrados.map(
                  (insumo) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InsumoRow(
                      insumo: insumo,
                      onEdit: () => _openForm(insumo),
                      onToggleActivo: (value) => _toggleActivo(insumo, value),
                      onToggleDisponible: (value) =>
                          _toggleDisponible(insumo, value),
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

class _InsumoRow extends StatelessWidget {
  const _InsumoRow({
    required this.insumo,
    required this.onEdit,
    required this.onToggleActivo,
    required this.onToggleDisponible,
  });

  final Insumo insumo;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActivo;
  final ValueChanged<bool> onToggleDisponible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alerta = insumo.bajoStock;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (alerta ? scheme.error : scheme.primary).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              insumo.porDisponibilidad
                  ? Icons.check_circle_outline
                  : Icons.inventory_2_outlined,
              color: alerta ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insumo.nombre,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${insumo.modoControl} · ${insumo.unidadAbreviatura} · costo ${formatMoney(insumo.costoPromedio)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insumo.porDisponibilidad
                      ? (insumo.disponible ? 'Disponible' : 'Agotado')
                      : 'Stock: ${formatQty(insumo.stock)} ${insumo.unidadAbreviatura}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: alerta ? scheme.error : null,
                  ),
                ),
                if (!insumo.porDisponibilidad)
                  Text(
                    'Mínimo: ${formatQty(insumo.stockMinimo)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (insumo.porDisponibilidad)
            FilterChip(
              label: Text(insumo.disponible ? 'Disponible' : 'Agotado'),
              selected: insumo.disponible,
              onSelected: onToggleDisponible,
            ),
          const SizedBox(width: 8),
          Switch(value: insumo.activo, onChanged: onToggleActivo),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _InsumoDialog extends StatefulWidget {
  const _InsumoDialog({
    required this.repository,
    required this.unidades,
    this.insumo,
  });

  final CatalogRepository repository;
  final List<UnidadMedida> unidades;
  final Insumo? insumo;

  @override
  State<_InsumoDialog> createState() => _InsumoDialogState();
}

class _InsumoDialogState extends State<_InsumoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _stockMinimo;
  late final TextEditingController _costo;
  late final TextEditingController _presentacion;
  late final TextEditingController _factor;
  late int? _unidadId;
  late String _modo;
  late bool _disponible;
  late bool _activo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final insumo = widget.insumo;
    _nombre = TextEditingController(text: insumo?.nombre ?? '');
    _stockMinimo = TextEditingController(
      text: insumo == null ? '0' : formatQty(insumo.stockMinimo),
    );
    _costo = TextEditingController(
      text: insumo == null ? '0' : insumo.costoPromedio.toStringAsFixed(2),
    );
    _presentacion = TextEditingController(
      text: insumo?.presentacionCompra ?? '',
    );
    _factor = TextEditingController(
      text: insumo == null ? '1' : formatQty(insumo.factorCompra),
    );
    _unidadId = insumo?.unidadId ??
        (widget.unidades.isEmpty ? null : widget.unidades.first.id);
    _modo = insumo?.modoControl ?? 'UNIDAD';
    _disponible = insumo?.disponible ?? true;
    _activo = insumo?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _stockMinimo.dispose();
    _costo.dispose();
    _presentacion.dispose();
    _factor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_unidadId == null) {
      setState(() => _error = 'Selecciona una unidad de medida.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final unidad = widget.unidades.firstWhere(
        (item) => item.id == _unidadId,
      );
      await widget.repository.saveInsumo(
        Insumo(
          id: widget.insumo?.id,
          nombre: _nombre.text,
          unidadId: _unidadId!,
          unidadAbreviatura: unidad.abreviatura,
          modoControl: _modo,
          disponible: _disponible,
          stockMinimo: _modo == 'DISPONIBILIDAD'
              ? 0
              : parseAmount(_stockMinimo.text),
          costoPromedio: _modo == 'DISPONIBILIDAD'
              ? 0
              : parseAmount(_costo.text),
          presentacionCompra: _presentacion.text,
          factorCompra: _modo == 'DISPONIBILIDAD'
              ? 1
              : parseAmount(_factor.text),
          activo: _activo,
          stock: widget.insumo?.stock ?? 0,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar: $error';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final porDisponibilidad = _modo == 'DISPONIBILIDAD';
    return AlertDialog(
      title: Text(widget.insumo == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: appInput(label: 'Nombre del insumo'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _unidadId,
                  decoration: appInput(label: 'Unidad de medida'),
                  items: widget.unidades
                      .map(
                        (unidad) => DropdownMenuItem(
                          value: unidad.id,
                          child: Text(
                            '${unidad.nombre} (${unidad.abreviatura})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _unidadId = value),
                  validator: (value) =>
                      value == null ? 'Selecciona una unidad' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _modo,
                  decoration: appInput(label: 'Modo de control'),
                  items: const [
                    DropdownMenuItem(
                      value: 'UNIDAD',
                      child: Text('UNIDAD · stock en unidades'),
                    ),
                    DropdownMenuItem(
                      value: 'PORCION',
                      child: Text('PORCIÓN · stock por porciones'),
                    ),
                    DropdownMenuItem(
                      value: 'DISPONIBILIDAD',
                      child: Text('DISPONIBILIDAD · solo disponible/agotado'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _modo = value ?? 'UNIDAD'),
                ),
                if (!porDisponibilidad) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockMinimo,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Stock mínimo',
                            icon: Icons.warning_amber_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _costo,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Costo promedio (Bs)',
                            icon: Icons.price_check,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _presentacion,
                          decoration: appInput(
                            label: 'Presentación de compra',
                            hint: 'Ej. bolsa 5 kg',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _factor,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: appInput(
                            label: 'Factor de compra',
                            hint: 'Ej. 5',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponible'),
                  subtitle: const Text(
                    'Si se marca como agotado, los platos que lo usan no se podrán vender.',
                  ),
                  value: _disponible,
                  onChanged: (value) => setState(() => _disponible = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Insumo activo'),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
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
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
