import 'package:flutter/material.dart';

import '../../../core/auth_repository.dart';
import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/expense_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class _ExpenseData {
  const _ExpenseData({
    required this.categorias,
    required this.gastos,
    required this.sueldos,
    required this.usuarios,
    required this.caja,
  });

  final List<CategoriaGasto> categorias;
  final List<Gasto> gastos;
  final List<Sueldo> sueldos;
  final List<Usuario> usuarios;
  final Caja? caja;
}

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _repository = ExpenseRepository();
  final _auth = AuthRepository();
  final _cash = CashRepository();
  late Future<_ExpenseData> _future;

  bool get _puedeGastos => widget.usuario.puede(Permiso.gastos);
  bool get _puedeSueldos => widget.usuario.puede(Permiso.sueldos);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_ExpenseData> _load() async {
    final categorias = await _repository.getCategoriasGasto();
    final gastos = await _repository.getGastos();
    final sueldos = await _repository.getSueldos();
    final usuarios = await _auth.getUsuarios();
    final caja = await _cash.getCajaAbierta();
    return _ExpenseData(
      categorias: categorias,
      gastos: gastos,
      sueldos: sueldos,
      usuarios: usuarios,
      caja: caja,
    );
  }

  Future<void> _nuevoGasto(_ExpenseData data) async {
    final activas = data.categorias
        .where((categoria) => categoria.activo)
        .toList();
    if (activas.isEmpty) {
      showAppMessage(
        context,
        'Primero crea una categoría de gasto.',
        error: true,
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GastoDialog(
        repository: _repository,
        categorias: activas,
        usuario: widget.usuario,
        caja: data.caja,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Gasto registrado.');
    }
  }

  Future<void> _nuevaCategoria([CategoriaGasto? categoria]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoriaGastoDialog(
        repository: _repository,
        categoria: categoria,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Categoría de gasto guardada.');
    }
  }

  Future<void> _nuevoSueldo(_ExpenseData data) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SueldoDialog(
        repository: _repository,
        usuarios: data.usuarios,
        usuario: widget.usuario,
        caja: data.caja,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      showAppMessage(context, 'Sueldo registrado.');
    }
  }

  Future<void> _anularGasto(Gasto gasto) async {
    final confirmado = await confirmAction(
      context,
      title: 'Anular gasto',
      message:
          'El gasto de ${formatMoney(gasto.monto)} (${gasto.categoriaNombre}) quedará anulado.',
      confirmLabel: 'Anular',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.anularGasto(gasto.id);
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _anularSueldo(Sueldo sueldo) async {
    final confirmado = await confirmAction(
      context,
      title: 'Anular sueldo',
      message:
          'El sueldo de ${formatMoney(sueldo.monto)} para ${sueldo.usuarioNombre} quedará anulado.',
      confirmLabel: 'Anular',
      destructive: true,
    );
    if (!confirmado) return;
    await _repository.anularSueldo(sueldo.id);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExpenseData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final tabs = <_ExpenseTab>[];
        if (_puedeGastos) {
          tabs.add(
            _ExpenseTab(
              label: 'Gastos',
              icon: Icons.receipt_long_outlined,
              child: _gastosTab(context, data),
            ),
          );
          tabs.add(
            _ExpenseTab(
              label: 'Categorías',
              icon: Icons.category_outlined,
              child: _categoriasTab(context, data),
            ),
          );
        }
        if (_puedeSueldos) {
          tabs.add(
            _ExpenseTab(
              label: 'Sueldos',
              icon: Icons.payments_outlined,
              child: _sueldosTab(context, data),
            ),
          );
        }
        return DefaultTabController(
          length: tabs.isEmpty ? 1 : tabs.length,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: PageHeader(
                  title: 'Gastos y sueldos',
                  subtitle:
                      'Los gastos y sueldos salen de caja. Se pueden anular sin borrarse.',
                  actions: [
                    if (_puedeGastos && data != null)
                      FilledButton.icon(
                        onPressed: () => _nuevoGasto(data),
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar gasto'),
                      ),
                    if (_puedeSueldos && data != null)
                      OutlinedButton.icon(
                        onPressed: () => _nuevoSueldo(data),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Registrar sueldo'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
              ),
              if (tabs.length > 1)
                TabBar(
                  tabs: tabs
                      .map(
                        (tab) => Tab(
                          icon: Icon(tab.icon),
                          text: tab.label,
                        ),
                      )
                      .toList(),
                ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const LoadingView()
                    : snapshot.hasError
                    ? ErrorView(
                        message: '${snapshot.error}',
                        onRetry: () => setState(_reload),
                      )
                    : tabs.isEmpty
                    ? const EmptyState(
                        icon: Icons.lock_outline,
                        title: 'Sin permisos',
                        message:
                            'No tienes permisos para ver gastos ni sueldos.',
                      )
                    : TabBarView(
                        children: tabs.map((tab) => tab.child).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gastosTab(BuildContext context, _ExpenseData? data) {
    final gastos = data?.gastos ?? [];
    if (gastos.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Todavía no hay gastos',
        message: 'Registra el primer gasto del restaurante.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: gastos
          .map(
            (gasto) => Padding(
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
                      child: Text(gasto.categoriaNombre.substring(0, 1)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gasto.categoriaNombre,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${formatDateTimeText(gasto.fecha)} · ${gasto.usuarioNombre}',
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
                      flex: 2,
                      child: Text(
                        gasto.descripcion ?? 'Sin descripción',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(gasto.monto),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    Chip(
                      label: Text(gasto.metodoPago),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(gasto.estado),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    if (!gasto.anulado)
                      TextButton(
                        onPressed: () => _anularGasto(gasto),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Anular'),
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _categoriasTab(BuildContext context, _ExpenseData? data) {
    final categorias = data?.categorias ?? [];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _nuevaCategoria(),
            icon: const Icon(Icons.add),
            label: const Text('Nueva categoría de gasto'),
          ),
        ),
        const SizedBox(height: 14),
        if (categorias.isEmpty)
          const EmptyState(
            icon: Icons.category_outlined,
            title: 'Sin categorías de gasto',
            message:
                'Crea categorías como servicios, alquiler o mantenimiento.',
          )
        else
          ...categorias.map(
            (categoria) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoria.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      categoria.activo ? 'Activa' : 'Inactiva',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Switch(
                      value: categoria.activo,
                      onChanged: (value) async {
                        await _repository.setCategoriaGastoActiva(
                          categoria.id!,
                          value,
                        );
                        if (mounted) setState(_reload);
                      },
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _nuevaCategoria(categoria),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sueldosTab(BuildContext context, _ExpenseData? data) {
    final sueldos = data?.sueldos ?? [];
    if (sueldos.isEmpty) {
      return const EmptyState(
        icon: Icons.payments_outlined,
        title: 'Todavía no hay sueldos registrados',
        message: 'Registra el primer pago de sueldo.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: sueldos
          .map(
            (sueldo) => Padding(
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
                      child: Text(sueldo.usuarioNombre.substring(0, 1)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sueldo.usuarioNombre,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${formatDateTimeText(sueldo.fecha)} · ${sueldo.periodo}',
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
                        sueldo.observacion ?? 'Sin observación',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(sueldo.monto),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    Chip(
                      label: Text(sueldo.metodoPago),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(sueldo.estado),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                    if (!sueldo.anulado)
                      TextButton(
                        onPressed: () => _anularSueldo(sueldo),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Anular'),
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ExpenseTab {
  const _ExpenseTab({
    required this.label,
    required this.icon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Widget child;
}

class _GastoDialog extends StatefulWidget {
  const _GastoDialog({
    required this.repository,
    required this.categorias,
    required this.usuario,
    required this.caja,
  });

  final ExpenseRepository repository;
  final List<CategoriaGasto> categorias;
  final Usuario usuario;
  final Caja? caja;

  @override
  State<_GastoDialog> createState() => _GastoDialogState();
}

class _GastoDialogState extends State<_GastoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _monto = TextEditingController();
  final _descripcion = TextEditingController();
  late int _categoriaId;
  String _metodo = 'EFECTIVO';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoriaId = widget.categorias.first.id!;
  }

  @override
  void dispose() {
    _monto.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.registrarGasto(
        categoriaGastoId: _categoriaId,
        usuarioId: widget.usuario.id,
        cajaId: widget.caja?.id,
        monto: parseAmount(_monto.text),
        metodoPago: _metodo,
        descripcion: _descripcion.text,
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
      title: const Text('Registrar gasto'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _categoriaId,
                decoration: appInput(label: 'Categoría de gasto'),
                items: widget.categorias
                    .map(
                      (categoria) => DropdownMenuItem(
                        value: categoria.id,
                        child: Text(categoria.nombre),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _categoriaId = value ?? _categoriaId),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monto,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(
                  label: 'Monto (Bs)',
                  icon: Icons.payments_outlined,
                ),
                validator: (value) => parseAmount(value ?? '') <= 0
                    ? 'Ingresa un monto mayor a 0'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcion,
                maxLines: 2,
                decoration: appInput(label: 'Descripción (opcional)'),
              ),
              if (widget.caja == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No hay caja abierta: el gasto no se descontará de una caja.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
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
          child: Text(_saving ? 'Guardando…' : 'Registrar'),
        ),
      ],
    );
  }
}

class _CategoriaGastoDialog extends StatefulWidget {
  const _CategoriaGastoDialog({
    required this.repository,
    this.categoria,
  });

  final ExpenseRepository repository;
  final CategoriaGasto? categoria;

  @override
  State<_CategoriaGastoDialog> createState() => _CategoriaGastoDialogState();
}

class _CategoriaGastoDialogState extends State<_CategoriaGastoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late bool _activo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.categoria?.nombre ?? '');
    _activo = widget.categoria?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCategoriaGasto(
        id: widget.categoria?.id,
        nombre: _nombre.text,
        activo: _activo,
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
    return AlertDialog(
      title: Text(
        widget.categoria == null
            ? 'Nueva categoría de gasto'
            : 'Editar categoría de gasto',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombre,
                decoration: appInput(label: 'Nombre'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                    ? 'Ingresa un nombre'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Categoría activa'),
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

class _SueldoDialog extends StatefulWidget {
  const _SueldoDialog({
    required this.repository,
    required this.usuarios,
    required this.usuario,
    required this.caja,
  });

  final ExpenseRepository repository;
  final List<Usuario> usuarios;
  final Usuario usuario;
  final Caja? caja;

  @override
  State<_SueldoDialog> createState() => _SueldoDialogState();
}

class _SueldoDialogState extends State<_SueldoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _periodo = TextEditingController();
  final _monto = TextEditingController();
  final _observacion = TextEditingController();
  late int? _usuarioId;
  String _metodo = 'EFECTIVO';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodo.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _usuarioId = widget.usuarios.isEmpty ? null : widget.usuarios.first.id;
  }

  @override
  void dispose() {
    _periodo.dispose();
    _monto.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usuarioId == null) {
      setState(() => _error = 'Selecciona un usuario.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.registrarSueldo(
        usuarioId: _usuarioId!,
        cajaId: widget.caja?.id,
        periodo: _periodo.text,
        monto: parseAmount(_monto.text),
        metodoPago: _metodo,
        observacion: _observacion.text,
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
      title: const Text('Registrar sueldo'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _usuarioId,
                decoration: appInput(label: 'Usuario'),
                items: widget.usuarios
                    .map(
                      (usuario) => DropdownMenuItem(
                        value: usuario.id,
                        child: Text(
                          usuario.activo
                              ? usuario.nombre
                              : '${usuario.nombre} (inactivo)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _usuarioId = value),
                validator: (value) =>
                    value == null ? 'Selecciona un usuario' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _periodo,
                decoration: appInput(
                  label: 'Período',
                  hint: 'Ej. 2026-11 o Noviembre 2026',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                    ? 'Indica el período'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monto,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(
                  label: 'Monto (Bs)',
                  icon: Icons.payments_outlined,
                ),
                validator: (value) => parseAmount(value ?? '') <= 0
                    ? 'Ingresa un monto mayor a 0'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacion,
                maxLines: 2,
                decoration: appInput(label: 'Observación (opcional)'),
              ),
              if (widget.caja == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No hay caja abierta: el sueldo no se descontará de una caja.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
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
          child: Text(_saving ? 'Guardando…' : 'Registrar'),
        ),
      ],
    );
  }
}
