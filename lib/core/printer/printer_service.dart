import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/database/app_database.dart';
import '../cash_repository.dart';
import '../date_utils.dart';
import '../sales_repository.dart';

/// Impresora Bluetooth vinculada en el sistema.
class ImpresoraDispositivo {
  const ImpresoraDispositivo({
    required this.nombre,
    required this.mac,
    this.tipo = 0,
  });

  final String nombre;
  final String mac;

  /// Tipo Android: 1 = clásico (SPP), 2 = BLE, 3 = dual. 0 = desconocido.
  final int tipo;

  String get tipoEtiqueta => switch (tipo) {
    2 => 'BLE',
    3 => 'Dual (clásico + BLE)',
    1 => 'Clásico (SPP)',
    _ => 'Desconocido',
  };
}

/// Impresión de las fichas de venta en una térmica de 80 mm por Bluetooth.
///
/// Usa un canal nativo de Android (`MainActivity.kt`) que conecta por **BLE
/// GATT** (Golden Sky GS-FJ80M-UB) o SPP como respaldo, y recibe los bytes
/// ESC/POS generados aquí. 80 mm ≈ 48 caracteres por línea.
class PrinterService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.test_code_02/bluetooth_printer',
  );
  static const int _ancho = 48;
  static const String _logoAsset = 'assets/images/logo_ticket.png';

  /// Raster del logo por ancho. Es estático para reutilizarlo entre ventas.
  static final Map<int, Uint8List> _logoCache = <int, Uint8List>{};

  // Comando exacto verificado en la Golden Sky GS-FJ80M-UB. Se envía en un
  // único buffer para que la impresora procese primero el texto y luego el
  // avance/corte (con dos envíos separados el corte podía adelantarse).
  static const List<int> _testComando = <int>[
    0x1B, 0x40, // ESC @ inicializar
    0x43, 0x4F, 0x4E, 0x57, 0x49, 0x43, 0x48, // CONWICH
    0x0A, 0x0A, // dos líneas
    0x1B, 0x64, 0x03, // avanzar tres líneas
    0x1D, 0x56, 0x01, // corte parcial
  ];

  bool get disponible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> encendido() async {
    if (!disponible) return false;
    try {
      return await _channel.invokeMethod<bool>('isOn') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> abrirAjustesBluetooth() async {
    if (!disponible) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<ImpresoraDispositivo>> vinculados() async {
    if (!disponible) return const [];
    try {
      final lista = await _channel
          .invokeListMethod<Map<Object?, Object?>>('listBondedDevices');
      if (lista == null) return const [];
      return lista
          .map((fila) {
            final mac = (fila['address'] as String?) ?? '';
            final nombre = (fila['name'] as String?) ?? '';
            final tipo = (fila['type'] as num?)?.toInt() ?? 0;
            return ImpresoraDispositivo(
              nombre: nombre.isEmpty ? mac : nombre,
              mac: mac,
              tipo: tipo,
            );
          })
          .where((dispositivo) => dispositivo.mac.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> conectar(String mac) async {
    final ok = await _channel.invokeMethod<bool>('connect', {'address': mac});
    if (ok != true) {
      throw StateError('No se pudo conectar con la impresora.');
    }
  }

  /// Escanea dispositivos BLE cercanos (7 s) y devuelve los encontrados.
  Future<List<ImpresoraDispositivo>> escanearBle() async {
    if (!disponible) return const [];
    try {
      final lista = await _channel
          .invokeListMethod<Map<Object?, Object?>>('scanBleDevices');
      if (lista == null) return const [];
      return lista
          .map((fila) {
            final mac = (fila['address'] as String?) ?? '';
            final nombre = (fila['name'] as String?) ?? '';
            final tipo = (fila['type'] as num?)?.toInt() ?? 0;
            return ImpresoraDispositivo(
              nombre: nombre.isEmpty ? mac : nombre,
              mac: mac,
              tipo: tipo,
            );
          })
          .where((dispositivo) => dispositivo.mac.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> desconectar() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {
      // Si no estaba conectada, no pasa nada.
    }
  }

  /// Envía bytes ESC/POS a la impresora ya conectada (BLE o SPP).
  Future<void> enviarBytes(List<int> bytes) async {
    if (!disponible) {
      throw StateError('La impresión solo está disponible en Android.');
    }
    final ok = await _channel.invokeMethod<bool>('printBytes', {
      'bytes': Uint8List.fromList(bytes),
    });
    if (ok != true) {
      throw StateError('No se pudieron enviar los datos a la impresora.');
    }
  }

  /// Imprime las dos fichas de la venta en un solo envío:
  /// cliente (pedido + fecha) → corte → vendedor (detalle + cajero) → corte.
  Future<void> imprimirNotaVenta({
    required PedidoDetalle detalle,
    required String turno,
    required String cajero,
    required String mac,
  }) async {
    final reloj = Stopwatch()..start();
    final logo = await _logoRaster(120);
    final bytes = construirBytesNotaVenta(
      detalle: detalle,
      cajero: cajero,
      logoCliente: logo,
      logoPedido: logo,
    );
    await _enviar(bytes, mac, mantenerConexion: true);
    reloj.stop();
    debugPrint(
      'Fichas #${detalle.pedido.id}: ${bytes.length} bytes en '
      '${reloj.elapsedMilliseconds} ms',
    );
  }

  /// Bytes de las dos fichas. Se expone para probar el orden de impresión y
  /// corte sin depender de la impresora física.
  @visibleForTesting
  Uint8List construirBytesNotaVenta({
    required PedidoDetalle detalle,
    required String cajero,
    Uint8List? logoCliente,
    Uint8List? logoPedido,
  }) {
    return Uint8List.fromList([
      ..._construirFichaCliente(detalle: detalle, logo: logoCliente),
      ..._construirFichaPedido(
        detalle: detalle,
        cajero: cajero,
        logo: logoPedido,
      ),
    ]);
  }

  /// Imprime el resumen del cierre de caja con la misma térmica que las notas.
  Future<void> imprimirMovimientoTurno({
    required Caja caja,
    required CajaResumen resumen,
    required double sobrante,
    required String cajero,
    required String mac,
  }) async {
    final meta = await AppDatabase.instance.leerAppMeta();
    final negocio = (meta?['nombre_negocio'] as String?) ?? 'Conwich';
    await _enviar(
      _construirMovimiento(
        caja: caja,
        resumen: resumen,
        sobrante: sobrante,
        cajero: cajero,
        negocio: negocio,
      ),
      mac,
    );
  }

  /// Prueba real: imprime "CONWICH" y luego avanza y corta el papel, todo en
  /// un solo envío para conservar el orden.
  Future<void> imprimirPrueba({required String mac}) async {
    await conectar(mac);
    try {
      await enviarBytes(_testComando);
    } finally {
      await desconectar();
    }
  }

  Future<void> _enviar(
    Uint8List bytes,
    String mac, {
    bool mantenerConexion = false,
  }) async {
    await conectar(mac);
    try {
      await enviarBytes(bytes);
    } finally {
      if (!mantenerConexion) await desconectar();
    }
  }

  /// Diagnóstico paso a paso para saber en qué falla la impresora.
  Future<List<String>> diagnosticar({required String mac}) async {
    final pasos = <String>[];
    final on = await encendido();
    pasos.add(on ? 'OK · Bluetooth encendido' : 'FALLA · Bluetooth apagado');
    if (!on) return pasos;
    final lista = await vinculados();
    pasos.add('OK · Dispositivos vinculados: ${lista.length}');
    final encontrados = lista.where((d) => d.mac == mac).toList();
    if (encontrados.isNotEmpty) {
      pasos.add('Info · Tipo: ${encontrados.first.tipoEtiqueta}');
    }
    try {
      await conectar(mac);
      pasos.add('OK · Conexión establecida (BLE/SPP)');
    } catch (error) {
      pasos.add('FALLA · Conexión: ${_mensaje(error)}');
      return pasos;
    }
    try {
      await enviarBytes(_testComando);
      pasos.add('OK · Prueba enviada (verifica el papel y el corte)');
    } catch (error) {
      pasos.add('FALLA · Envío: ${_mensaje(error)}');
    } finally {
      await desconectar();
    }
    return pasos;
  }

  String _mensaje(Object error) {
    if (error is PlatformException) {
      return '${error.code}: ${error.message ?? ''}'.trim();
    }
    return error.toString();
  }

  /// Ficha corta para el cliente: pedido y fecha/hora.
  Uint8List _construirFichaCliente({
    required PedidoDetalle detalle,
    Uint8List? logo,
  }) {
    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateShort(fecha);
    final horaTexto = fecha == null ? '' : formatTimeShort(fecha);

    final b = _Ticket();
    b.init();
    if (logo != null) {
      b.alignCenter();
      b.raster(logo);
      b.feed(1);
    }
    b.alignCenter();
    b.size(3, 3);
    b.bold(true);
    b.line('PEDIDO #${pedido.id}');
    b.size(1, 1);
    b.bold(false);
    b.line(
      horaTexto.isEmpty
          ? 'Fecha: $fechaTexto'
          : 'Fecha: $fechaTexto   Hora: $horaTexto',
    );
    // El corte ya avanza el papel; no se agrega feed extra para ahorrar.
    b.cut();
    return b.toBytes();
  }

  /// Ficha del vendedor: pedido, detalle con subtotales y cajero.
  Uint8List _construirFichaPedido({
    required PedidoDetalle detalle,
    required String cajero,
    Uint8List? logo,
  }) {
    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateShort(fecha);
    final horaTexto = fecha == null ? '' : formatTimeShort(fecha);

    final b = _Ticket();
    b.init();
    if (logo != null) {
      b.alignCenter();
      b.raster(logo);
      b.feed(1);
    }
    b.alignCenter();
    b.size(2, 2);
    b.bold(true);
    b.line('PEDIDO #${pedido.id}');
    b.size(1, 1);
    b.bold(false);
    b.line(
      horaTexto.isEmpty
          ? 'Fecha: $fechaTexto'
          : 'Fecha: $fechaTexto   Hora: $horaTexto',
    );
    b.alignLeft();
    b.line(b.separador(_ancho));
    for (final linea in detalle.lineas.where((l) => !l.esComponente)) {
      final principal = linea.modalidadVenta == 'COMPLETO'
          ? '${linea.nombre} completo'
          : linea.nombre;
      final izquierda = '${_cantidad(linea.cantidad)} x $principal';
      final derecha = formatMoney(linea.subtotal);
      // Si el nombre es muy largo, se imprime en dos líneas para no perderlo.
      if (izquierda.length + derecha.length + 1 <= _ancho) {
        b.line(_fila(izquierda, derecha, _ancho));
      } else {
        b.line(izquierda);
        b.line(_fila('', derecha, _ancho));
      }
      if (linea.modalidadVenta == 'COMPLETO' &&
          (linea.nombreSopa ?? '').isNotEmpty) {
        b.line('   incluye ${linea.nombreSopa}');
      }
    }
    b.line(b.separador(_ancho));
    b.line('Cajero: $cajero');
    b.cut();
    return b.toBytes();
  }

  /// Carga el logo, lo reduce al ancho indicado y lo convierte a raster
  /// ESC/POS de 1 bit. Si falla, la venta se imprime sin logo.
  Future<Uint8List?> _logoRaster(int ancho) async {
    final cache = _logoCache[ancho];
    if (cache != null) return cache;
    try {
      final data = await rootBundle.load(_logoAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: ancho,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      if (byteData == null) return null;
      final raster = _empaquetarRaster(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width,
        height,
      );
      _logoCache[ancho] = raster;
      return raster;
    } catch (_) {
      return null;
    }
  }

  Uint8List _empaquetarRaster(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final bytesPerRow = (width + 7) ~/ 8;
    final data = Uint8List(bytesPerRow * height);
    for (var y = 0; y < height; y++) {
      final fila = y * width * 4;
      final salida = y * bytesPerRow;
      for (var x = 0; x < width; x++) {
        final i = fila + x * 4;
        if (rgba[i + 3] < 40) continue;
        final lum =
            0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        if (lum < 160) {
          data[salida + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    final header = <int>[
      0x1D, 0x76, 0x30, 0x00, // GS v 0
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
    ];
    return Uint8List.fromList([...header, ...data]);
  }

  String _cantidad(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Uint8List _construirMovimiento({
    required Caja caja,
    required CajaResumen resumen,
    required double sobrante,
    required String cajero,
    required String negocio,
  }) {
    final b = _Ticket();
    b.init();
    b.alignCenter();
    b.big(true);
    b.line(_truncar(negocio, 24));
    b.big(false);
    b.bold(true);
    b.line('MOVIMIENTO DE TURNO');
    b.bold(false);
    b.alignLeft();
    b.line(b.separador(_ancho));
    b.line(_fila('Turno', caja.turnoLabel, _ancho));
    b.line(_fila('Fecha', formatDateShort(parseSqlDate(caja.fecha)), _ancho));
    b.line(_fila('Cajero', cajero, _ancho));
    b.line(b.separador(_ancho));
    b.line(
      _fila('Ventas efectivo', formatMoney(resumen.ventasEfectivo), _ancho),
    );
    b.line(_fila('Ventas QR', formatMoney(resumen.ventasQr), _ancho));
    b.line(
      _fila(
        'Salidas de caja',
        formatMoney(resumen.salidasEfectivo + resumen.salidasQr),
        _ancho,
      ),
    );
    b.line(
      _fila('Sobrante del turno', formatMoney(sobrante), _ancho),
    );
    b.line(b.separador(_ancho));
    b.bold(true);
    b.line(
      _fila('TOTAL ESPERADO', formatMoney(resumen.totalEsperado), _ancho),
    );
    b.line(
      _fila(
        'TOTAL EN CAJA',
        formatMoney(resumen.totalEsperado + sobrante),
        _ancho,
      ),
    );
    b.bold(false);
    b.line(b.separador(_ancho));
    b.alignCenter();
    b.line('Gracias por su trabajo');
    b.alignLeft();
    b.feed(2);
    b.cut();
    return b.toBytes();
  }
}

/// Construye los bytes ESC/POS de un ticket de 80 mm.
class _Ticket {
  final List<int> _bytes = <int>[];

  void init() => _bytes.addAll(const [0x1B, 0x40]);
  void alignLeft() => _bytes.addAll(const [0x1B, 0x61, 0x00]);
  void alignCenter() => _bytes.addAll(const [0x1B, 0x61, 0x01]);
  void bold(bool on) => _bytes.addAll([0x1B, 0x45, on ? 1 : 0]);
  void big(bool on) => _bytes.addAll([0x1D, 0x21, on ? 0x11 : 0x00]);
  void size(int ancho, int alto) {
    final w = ancho.clamp(1, 8) - 1;
    final h = alto.clamp(1, 8) - 1;
    _bytes.addAll([0x1D, 0x21, (w << 4) | h]);
  }

  void raster(Uint8List bytes) => _bytes.addAll(bytes);
  void text(String value) => _bytes.addAll(_latin1(value));
  void line(String value) {
    text(value);
    _bytes.add(0x0A);
  }

  void feed(int lineas) => _bytes.addAll([0x1B, 0x64, lineas]);
  void cut() => _bytes.addAll(const [0x1B, 0x64, 0x03, 0x1D, 0x56, 0x01]);
  String separador(int ancho) => '-' * ancho;
  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

String _fila(String izquierda, String derecha, int ancho) {
  final der = derecha;
  final espacio = ancho - der.length;
  var izq = izquierda;
  if (espacio <= 0) return der;
  if (izq.length > espacio - 1) {
    izq = izq.substring(0, espacio - 1);
  }
  return '${izq.padRight(espacio)}$der';
}

String _truncar(String texto, int maximo) =>
    texto.length <= maximo ? texto : texto.substring(0, maximo);

List<int> _latin1(String value) {
  final t = value
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('…', '...')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");
  final buffer = StringBuffer();
  for (final rune in t.runes) {
    buffer.writeCharCode(rune <= 0xFF ? rune : 0x3F);
  }
  return buffer.toString().codeUnits;
}
