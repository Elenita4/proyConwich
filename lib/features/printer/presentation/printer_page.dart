import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/printer/printer_service.dart';
import '../../../core/session.dart';
import '../../../data/database/app_database.dart';
import '../../../ui/common.dart';

class PrinterPage extends StatefulWidget {
  const PrinterPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
  });

  final Usuario usuario;
  final int refreshToken;

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  final _printer = PrinterService();
  List<ImpresoraDispositivo> _dispositivos = const [];
  String? _macActual;
  String? _nombreActual;
  String? _macSeleccionada;
  String? _nombreSeleccionado;
  bool _bluetoothOn = false;
  bool _cargando = true;
  bool _buscando = false;
  bool _guardando = false;
  bool _probando = false;
  bool _diagnosticando = false;
  String? _estadoPrueba;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(PrinterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final meta = await AppDatabase.instance.leerAppMeta();
    final on = await _printer.encendido();
    if (!mounted) return;
    setState(() {
      _macActual = meta?['impresora_mac'] as String?;
      _nombreActual = meta?['impresora_nombre'] as String?;
      _macSeleccionada = _macActual;
      _nombreSeleccionado = _nombreActual;
      _bluetoothOn = on;
      _cargando = false;
    });
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _bluetoothOn = false;
    });
    final on = await _printer.encendido();
    final dispositivos = on
        ? await _printer.vinculados()
        : const <ImpresoraDispositivo>[];
    if (!mounted) return;
    setState(() {
      _bluetoothOn = on;
      _dispositivos = dispositivos;
      _buscando = false;
    });
    if (!on) {
      showAppMessage(
        context,
        'Activa el Bluetooth y vincula la impresora en los ajustes del sistema.',
        error: true,
      );
    } else if (dispositivos.isEmpty) {
      showAppMessage(
        context,
        'No hay dispositivos vinculados. Vincula la impresora en los ajustes Bluetooth.',
        error: true,
      );
    }
  }

  Future<void> _escanearBle() async {
    setState(() {
      _buscando = true;
      _bluetoothOn = false;
    });
    final on = await _printer.encendido();
    final escaneados = on
        ? await _printer.escanearBle()
        : const <ImpresoraDispositivo>[];
    final vinculados = on
        ? await _printer.vinculados()
        : const <ImpresoraDispositivo>[];
    if (!mounted) return;
    final mapa = <String, ImpresoraDispositivo>{};
    for (final dispositivo in [...vinculados, ...escaneados]) {
      mapa[dispositivo.mac] = dispositivo;
    }
    setState(() {
      _bluetoothOn = on;
      _dispositivos = mapa.values.toList();
      _buscando = false;
    });
    if (!on) {
      showAppMessage(
        context,
        'Activa el Bluetooth para escanear.',
        error: true,
      );
    } else if (mapa.isEmpty) {
      showAppMessage(
        context,
        'No se encontraron impresoras BLE cercanas.',
        error: true,
      );
    }
  }

  Future<void> _abrirAjustes() async {
    await _printer.abrirAjustesBluetooth();
  }

  void _seleccionar(ImpresoraDispositivo dispositivo) {
    setState(() {
      _macSeleccionada = dispositivo.mac;
      _nombreSeleccionado = dispositivo.nombre;
    });
  }

  Future<void> _probar() async {
    final mac = _macSeleccionada;
    if (mac == null || mac.isEmpty) {
      showAppMessage(context, 'Selecciona una impresora primero.', error: true);
      return;
    }
    if (_probando) return;
    setState(() {
      _probando = true;
      _estadoPrueba = 'Conectando con la impresora…';
    });
    try {
      await _printer.conectar(mac);
      if (!mounted) return;
      setState(
        () => _estadoPrueba = 'Enviando prueba de impresión y corte…',
      );
      // Un solo buffer: init + "CONWICH" + dos líneas + avance + corte.
      // Así la impresora imprime primero y corta después.
      await _printer.enviarBytes(const <int>[
        0x1B, 0x40,
        0x43, 0x4F, 0x4E, 0x57, 0x49, 0x43, 0x48,
        0x0A, 0x0A,
        0x1B, 0x64, 0x03, 0x1D, 0x56, 0x01,
      ]);
      if (!mounted) return;
      setState(
        () => _estadoPrueba =
            'Prueba enviada. Verifica el papel y el corte.',
      );
      showAppMessage(
        context,
        'Prueba enviada. Verifica que salió "CONWICH" y que se cortó el papel.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _estadoPrueba = 'Error al enviar los datos a la impresora.',
      );
      showAppMessage(
        context,
        'Error al enviar los datos a la impresora: ${_mensajeError(error)}',
        error: true,
      );
    } finally {
      await _printer.desconectar();
      if (mounted) setState(() => _probando = false);
    }
  }

  Future<void> _guardar() async {
    final mac = _macSeleccionada;
    if (mac == null || mac.isEmpty) {
      showAppMessage(context, 'Selecciona una impresora primero.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await AppDatabase.instance.actualizarAppMeta({
        'impresora_mac': mac,
        'impresora_nombre': _nombreSeleccionado,
      });
      if (!mounted) return;
      setState(() {
        _macActual = mac;
        _nombreActual = _nombreSeleccionado;
        _guardando = false;
      });
      showAppMessage(context, 'Impresora guardada.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      showAppMessage(
        context,
        'No se pudo guardar: ${_mensajeError(error)}',
        error: true,
      );
    }
  }

  String _mensajeError(Object error) {
    if (error is PlatformException) {
      return '${error.code}: ${error.message ?? ''}'.trim();
    }
    return error.toString();
  }

  Future<void> _diagnosticar() async {
    final mac = _macSeleccionada;
    if (mac == null || mac.isEmpty) {
      showAppMessage(context, 'Selecciona una impresora primero.', error: true);
      return;
    }
    setState(() => _diagnosticando = true);
    try {
      final pasos = await _printer.diagnosticar(mac: mac);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Diagnóstico de impresora'),
          content: DialogSurface(
            maxWidth: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: pasos
                    .map(
                      (paso) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(paso),
                      ),
                    )
                    .toList(),
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
    } finally {
      if (mounted) setState(() => _diagnosticando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_printer.disponible) {
      return const EmptyState(
        icon: Icons.print_disabled_outlined,
        title: 'Impresión Bluetooth solo en Android',
        message:
            'La conexión con la impresora térmica está disponible en la app de Android.',
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Impresora',
            subtitle:
                'Conecta una impresora térmica de 80 mm por Bluetooth. Primero '
                'vincúlala en los ajustes de Bluetooth del dispositivo.',
          ),
          if (_cargando)
            const LoadingView()
          else ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _bluetoothOn
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: _bluetoothOn ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bluetoothOn
                              ? 'Bluetooth activo'
                              : 'Bluetooth apagado o sin permiso',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (_macActual != null && _macActual!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Impresora configurada: ${_nombreActual ?? _macActual}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _abrirAjustes,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Ajustes Bluetooth'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _buscando ? null : _buscar,
                        icon: const Icon(Icons.link),
                        label: Text(_buscando ? 'Buscando…' : 'Vinculados'),
                      ),
                      FilledButton.icon(
                        onPressed: _buscando ? null : _escanearBle,
                        icon: const Icon(Icons.search),
                        label: Text(
                          _buscando ? 'Escaneando…' : 'Escanear BLE',
                        ),
                      ),
                    ],
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
                    'Dispositivos vinculados',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_dispositivos.isEmpty)
                    Text(
                      'Pulsa "Buscar impresoras" para ver los dispositivos ya '
                      'vinculados en el sistema.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    ..._dispositivos.map((dispositivo) {
                      final seleccionado = dispositivo.mac == _macSeleccionada;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.print_outlined,
                          color: seleccionado ? scheme.primary : null,
                        ),
                        title: Text(dispositivo.nombre),
                        subtitle: Text(
                          '${dispositivo.mac} · ${dispositivo.tipoEtiqueta}',
                        ),
                        trailing: seleccionado
                            ? Icon(Icons.check_circle, color: scheme.primary)
                            : const Icon(Icons.circle_outlined),
                        selected: seleccionado,
                        onTap: () => _seleccionar(dispositivo),
                      );
                    }),
                  const SizedBox(height: 10),
                  Text(
                    'Cierra otras apps que puedan estar conectadas a la '
                    'impresora: solo acepta una conexión a la vez.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _probando ? null : _probar,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_probando ? 'Enviando…' : 'Probar impresora'),
                ),
                OutlinedButton.icon(
                  onPressed: _diagnosticando ? null : _diagnosticar,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(
                    _diagnosticando ? 'Diagnosticando…' : 'Diagnosticar',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar impresora'),
                ),
              ],
            ),
            if (_estadoPrueba != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _estadoPrueba!,
                  style: TextStyle(
                    color: _estadoPrueba!.startsWith('Error')
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
