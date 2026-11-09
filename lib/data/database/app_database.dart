import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/date_utils.dart';
import '../../core/password_utils.dart';
import '../../core/session.dart';
import 'database_factory_web.dart'
    if (dart.library.io) 'database_factory_io.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _openDatabase() async {
    configureDatabaseFactory();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    return openDatabase(
      path,
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db, newVersion);
        await _migrarPerfiles(db);
        await _migrarModosInsumo(db);
      },
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();

    // Las vistas se recrean en cada actualización para reflejar el esquema.
    batch.execute('DROP VIEW IF EXISTS v_stock_insumos');
    batch.execute('DROP VIEW IF EXISTS v_stock_productos');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        usuario TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
        perfil TEXT NOT NULL DEFAULT 'CAJERO',
        turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
        sueldo_base REAL NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS usuario_permisos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        permiso TEXT NOT NULL,
        UNIQUE (usuario_id, permiso),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS sesion_actual (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        usuario_id INTEGER NOT NULL,
        iniciada_en TEXT NOT NULL,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS categorias_producto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL DEFAULT 4280391418,
        siempre_disponible INTEGER NOT NULL DEFAULT 0,
        orden INTEGER NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS unidades_medida (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        abreviatura TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        categoria_id INTEGER NOT NULL,
        descripcion TEXT,
        precio REAL NOT NULL DEFAULT 0,
        imagen BLOB,
        tipo TEXT NOT NULL CHECK (tipo IN ('DIRECTO','PREPARADO')),
        stock_minimo REAL NOT NULL DEFAULT 0,
        costo_unitario REAL NOT NULL DEFAULT 0,
        activo INTEGER NOT NULL DEFAULT 1,
        creado_en TEXT NOT NULL,
        FOREIGN KEY (categoria_id) REFERENCES categorias_producto(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS insumos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        unidad_id INTEGER NOT NULL,
        modo_control TEXT NOT NULL CHECK (modo_control IN ('UNIDAD','PORCION','DISPONIBILIDAD')),
        disponible INTEGER NOT NULL DEFAULT 1,
        stock_minimo REAL NOT NULL DEFAULT 0,
        costo_promedio REAL NOT NULL DEFAULT 0,
        presentacion_compra TEXT,
        factor_compra REAL NOT NULL DEFAULT 1,
        activo INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (unidad_id) REFERENCES unidades_medida(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS receta_insumos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        producto_id INTEGER NOT NULL,
        insumo_id INTEGER NOT NULL,
        cantidad REAL NOT NULL DEFAULT 0,
        UNIQUE (producto_id, insumo_id),
        FOREIGN KEY (producto_id) REFERENCES productos(id),
        FOREIGN KEY (insumo_id) REFERENCES insumos(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS menus_dia (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('DESAYUNO','ALMUERZO')),
        estado TEXT NOT NULL DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','PUBLICADO','CERRADO')),
        usuario_id INTEGER NOT NULL,
        observacion TEXT,
        publicado_en TEXT,
        creado_en TEXT NOT NULL,
        UNIQUE (fecha, tipo),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS menu_dia_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_dia_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        disponible INTEGER NOT NULL DEFAULT 1,
        motivo_agotado TEXT,
        orden INTEGER NOT NULL DEFAULT 0,
        UNIQUE (menu_dia_id, producto_id),
        FOREIGN KEY (menu_dia_id) REFERENCES menus_dia(id),
        FOREIGN KEY (producto_id) REFERENCES productos(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS cajas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        turno TEXT NOT NULL CHECK (turno IN ('MAÑANA','TARDE')),
        usuario_apertura_id INTEGER NOT NULL,
        usuario_cierre_id INTEGER,
        fecha_apertura TEXT NOT NULL,
        fecha_cierre TEXT,
        fondo_inicial REAL NOT NULL DEFAULT 0,
        efectivo_contado REAL,
        qr_verificado REAL,
        estado TEXT NOT NULL DEFAULT 'ABIERTA' CHECK (estado IN ('ABIERTA','CERRADA')),
        observacion TEXT,
        UNIQUE (fecha, turno),
        FOREIGN KEY (usuario_apertura_id) REFERENCES usuarios(id),
        FOREIGN KEY (usuario_cierre_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        referencia TEXT,
        usuario_id INTEGER NOT NULL,
        caja_id INTEGER NOT NULL,
        menu_dia_id INTEGER,
        fecha TEXT NOT NULL,
        estado_pago TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (estado_pago IN ('PENDIENTE','PAGADO','ANULADO')),
        estado_entrega TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (estado_entrega IN ('PENDIENTE','EN_PREPARACION','LISTO','ENTREGADO','ANULADO')),
        total REAL NOT NULL DEFAULT 0,
        observacion TEXT,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
        FOREIGN KEY (caja_id) REFERENCES cajas(id),
        FOREIGN KEY (menu_dia_id) REFERENCES menus_dia(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS detalle_pedido (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        menu_dia_item_id INTEGER,
        nombre_producto TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        costo_unitario REAL NOT NULL DEFAULT 0,
        observacion TEXT,
        FOREIGN KEY (pedido_id) REFERENCES pedidos(id),
        FOREIGN KEY (producto_id) REFERENCES productos(id),
        FOREIGN KEY (menu_dia_item_id) REFERENCES menu_dia_items(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS pagos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id INTEGER NOT NULL,
        caja_id INTEGER NOT NULL,
        usuario_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        monto REAL NOT NULL,
        metodo_pago TEXT NOT NULL CHECK (metodo_pago IN ('EFECTIVO','QR')),
        estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('CONFIRMADO','ANULADO')),
        referencia TEXT,
        FOREIGN KEY (pedido_id) REFERENCES pedidos(id),
        FOREIGN KEY (caja_id) REFERENCES cajas(id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS compras (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        metodo_pago TEXT NOT NULL CHECK (metodo_pago IN ('EFECTIVO','QR')),
        caja_id INTEGER,
        total REAL NOT NULL DEFAULT 0,
        observacion TEXT,
        estado TEXT NOT NULL DEFAULT 'REGISTRADA' CHECK (estado IN ('REGISTRADA','ANULADA')),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
        FOREIGN KEY (caja_id) REFERENCES cajas(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS detalle_compra (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        compra_id INTEGER NOT NULL,
        insumo_id INTEGER,
        producto_id INTEGER,
        cantidad REAL NOT NULL,
        costo_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (compra_id) REFERENCES compras(id),
        FOREIGN KEY (insumo_id) REFERENCES insumos(id),
        FOREIGN KEY (producto_id) REFERENCES productos(id),
        CHECK (
          (insumo_id IS NOT NULL AND producto_id IS NULL) OR
          (insumo_id IS NULL AND producto_id IS NOT NULL)
        )
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS consumos_insumo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        insumo_id INTEGER NOT NULL,
        pedido_id INTEGER,
        detalle_pedido_id INTEGER,
        fecha TEXT NOT NULL,
        cantidad REAL NOT NULL,
        costo_unitario REAL NOT NULL DEFAULT 0,
        estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('CONFIRMADO','ANULADO')),
        FOREIGN KEY (insumo_id) REFERENCES insumos(id),
        FOREIGN KEY (pedido_id) REFERENCES pedidos(id),
        FOREIGN KEY (detalle_pedido_id) REFERENCES detalle_pedido(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS ajustes_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        insumo_id INTEGER,
        producto_id INTEGER,
        cantidad REAL NOT NULL DEFAULT 0,
        motivo TEXT,
        usuario_id INTEGER NOT NULL,
        FOREIGN KEY (insumo_id) REFERENCES insumos(id),
        FOREIGN KEY (producto_id) REFERENCES productos(id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS conteos_inventario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL UNIQUE,
        usuario_id INTEGER NOT NULL,
        estado TEXT NOT NULL DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','CERRADO')),
        observacion TEXT,
        creado_en TEXT NOT NULL,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS detalle_conteo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conteo_id INTEGER NOT NULL,
        insumo_id INTEGER NOT NULL,
        stock_sistema REAL NOT NULL,
        stock_contado REAL NOT NULL,
        diferencia REAL NOT NULL,
        costo_unitario REAL NOT NULL DEFAULT 0,
        UNIQUE (conteo_id, insumo_id),
        FOREIGN KEY (conteo_id) REFERENCES conteos_inventario(id),
        FOREIGN KEY (insumo_id) REFERENCES insumos(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS categorias_gasto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS gastos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        categoria_gasto_id INTEGER NOT NULL,
        usuario_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        monto REAL NOT NULL,
        metodo_pago TEXT NOT NULL CHECK (metodo_pago IN ('EFECTIVO','QR')),
        caja_id INTEGER,
        descripcion TEXT,
        estado TEXT NOT NULL DEFAULT 'REGISTRADO' CHECK (estado IN ('REGISTRADO','ANULADO')),
        FOREIGN KEY (categoria_gasto_id) REFERENCES categorias_gasto(id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
        FOREIGN KEY (caja_id) REFERENCES cajas(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE IF NOT EXISTS sueldos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        periodo TEXT NOT NULL,
        monto REAL NOT NULL,
        metodo_pago TEXT NOT NULL CHECK (metodo_pago IN ('EFECTIVO','QR')),
        caja_id INTEGER,
        observacion TEXT,
        estado TEXT NOT NULL DEFAULT 'REGISTRADO' CHECK (estado IN ('REGISTRADO','ANULADO')),
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
        FOREIGN KEY (caja_id) REFERENCES cajas(id)
      )
    ''');

    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoria_id)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_receta_producto ON receta_insumos(producto_id)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_fecha ON menus_dia(fecha, tipo)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_items ON menu_dia_items(menu_dia_id)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_pedidos_fecha ON pedidos(fecha)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_pedidos_caja ON pedidos(caja_id)',
    );
    batch.execute('CREATE INDEX IF NOT EXISTS idx_pagos_fecha ON pagos(fecha)');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_compras_fecha ON compras(fecha)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_consumos_fecha ON consumos_insumo(fecha)',
    );
    batch.execute('CREATE INDEX IF NOT EXISTS idx_gastos_fecha ON gastos(fecha)');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_sueldos_fecha ON sueldos(fecha)');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ajustes_insumo ON ajustes_stock(insumo_id)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ajustes_producto ON ajustes_stock(producto_id)',
    );

    batch.execute('''
      CREATE VIEW IF NOT EXISTS v_stock_insumos AS
      SELECT
        i.id AS insumo_id,
        COALESCE((
          SELECT SUM(dc.cantidad)
          FROM detalle_compra dc
          INNER JOIN compras c ON c.id = dc.compra_id
          WHERE dc.insumo_id = i.id AND c.estado = 'REGISTRADA'
        ), 0)
        - COALESCE((
          SELECT SUM(ci.cantidad)
          FROM consumos_insumo ci
          WHERE ci.insumo_id = i.id AND ci.estado = 'CONFIRMADO'
        ), 0)
        + COALESCE((
          SELECT SUM(dt.diferencia)
          FROM detalle_conteo dt
          INNER JOIN conteos_inventario ct ON ct.id = dt.conteo_id
          WHERE dt.insumo_id = i.id AND ct.estado = 'CERRADO'
        ), 0)
        + COALESCE((
          SELECT SUM(a.cantidad)
          FROM ajustes_stock a
          WHERE a.insumo_id = i.id
        ), 0) AS stock
      FROM insumos i
    ''');

    batch.execute('''
      CREATE VIEW IF NOT EXISTS v_stock_productos AS
      SELECT
        p.id AS producto_id,
        COALESCE((
          SELECT SUM(dc.cantidad)
          FROM detalle_compra dc
          INNER JOIN compras c ON c.id = dc.compra_id
          WHERE dc.producto_id = p.id AND c.estado = 'REGISTRADA'
        ), 0)
        - COALESCE((
          SELECT SUM(dp.cantidad)
          FROM detalle_pedido dp
          INNER JOIN pedidos pe ON pe.id = dp.pedido_id
          WHERE dp.producto_id = p.id
            AND pe.estado_pago <> 'ANULADO'
            AND pe.estado_entrega <> 'ANULADO'
        ), 0)
        + COALESCE((
          SELECT SUM(a.cantidad)
          FROM ajustes_stock a
          WHERE a.producto_id = p.id
        ), 0) AS stock
      FROM productos p
      WHERE p.tipo = 'DIRECTO'
    ''');

    await batch.commit(noResult: true);

    await _seedUnits(db);
    await _seedDefaultAdmin(db);
  }

  /// Todos los insumos pasan a controlarse por cantidad.
  Future<void> _migrarModosInsumo(Database db) async {
    try {
      final rows = await db.query(
        'insumos',
        columns: ['id', 'disponible'],
        where: "modo_control <> 'UNIDAD'",
      );
      if (rows.isEmpty) return;
      final admin = await db.rawQuery(
        "SELECT id FROM usuarios ORDER BY id LIMIT 1",
      );
      final usuarioId = admin.isEmpty ? null : admin.first['id'] as int?;
      for (final row in rows) {
        final id = row['id']! as int;
        final disponible = (row['disponible'] as num).toInt() == 1;
        if (!disponible || usuarioId == null) continue;
        // Antes no se contaban; se les da una cantidad para que se puedan vender.
        await db.insert('ajustes_stock', {
          'fecha': sqlNow(),
          'insumo_id': id,
          'producto_id': null,
          'cantidad': 100.0,
          'motivo': 'Conversión a control por cantidad',
          'usuario_id': usuarioId,
        });
      }
      await db.execute(
        "UPDATE insumos SET modo_control = 'UNIDAD', disponible = 1",
      );
    } catch (error) {
      debugPrint('No se pudieron migrar los modos de insumo: $error');
    }
  }

  Future<void> _seedDefaultAdmin(Database db) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM usuarios'),
        ) ??
        0;
    if (count > 0) return;
    final id = await db.insert('usuarios', {
      'nombre': 'Administrador',
      'usuario': 'admin',
      'password_hash': hashPassword('1234'),
      'rol': 'ADMIN',
      'perfil': Perfil.admin,
      'turno_asignado': 'AMBOS',
      'sueldo_base': 0,
      'activo': 1,
      'creado_en': sqlNow(),
    });
    for (final permiso in Permiso.todos) {
      await db.insert('usuario_permisos', {
        'usuario_id': id,
        'permiso': permiso,
      });
    }
  }

  /// Agrega la columna `perfil` a usuarios y la deja sincronizada con el rol.
  Future<void> _migrarPerfiles(Database db) async {
    try {
      final columnas = await db.rawQuery('PRAGMA table_info(usuarios)');
      final tienePerfil = columnas.any((c) => c['name'] == 'perfil');
      if (!tienePerfil) {
        await db.execute(
          "ALTER TABLE usuarios ADD COLUMN perfil TEXT NOT NULL DEFAULT 'CAJERO'",
        );
      }
      await db.execute(
        "UPDATE usuarios SET perfil = 'ADMIN' WHERE rol = 'ADMIN'",
      );
      await db.execute(
        "UPDATE usuarios SET perfil = 'CAJERO' WHERE rol <> 'ADMIN'",
      );

      // Los usuarios que no son administrador quedan con las vistas del cajero.
      final usuarios = await db.query(
        'usuarios',
        columns: ['id'],
        where: 'perfil <> ?',
        whereArgs: [Perfil.admin],
      );
      for (final usuario in usuarios) {
        final id = usuario['id']! as int;
        await db.delete(
          'usuario_permisos',
          where: 'usuario_id = ?',
          whereArgs: [id],
        );
        for (final permiso in Perfil.vistasPorDefecto[Perfil.cajero]!) {
          await db.insert('usuario_permisos', {
            'usuario_id': id,
            'permiso': permiso,
          });
        }
      }
    } catch (error) {
      // Si la migración falla la app sigue funcionando con el rol anterior.
      debugPrint('No se pudo migrar el perfil de los usuarios: $error');
    }
  }

  Future<void> _seedUnits(Database db) async {
    const units = [
      {'nombre': 'Unidad', 'abreviatura': 'und'},
      {'nombre': 'Porción', 'abreviatura': 'porc'},
      {'nombre': 'Kilogramo', 'abreviatura': 'kg'},
      {'nombre': 'Gramo', 'abreviatura': 'g'},
      {'nombre': 'Litro', 'abreviatura': 'L'},
      {'nombre': 'Mililitro', 'abreviatura': 'ml'},
    ];
    for (final unit in units) {
      await db.insert(
        'unidades_medida',
        unit,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
