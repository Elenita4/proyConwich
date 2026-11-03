import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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

  Future<Database> _openDatabase() async {
    configureDatabaseFactory();
    final path = join(await getDatabasesPath(), 'sazon_restaurante.db');
    return openDatabase(
      path,
      version: 6,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && !await _hasColumn(db, 'insumos', 'foto')) {
      await db.execute('ALTER TABLE insumos ADD COLUMN foto BLOB');
    }
    if (oldVersion < 3) {
      await _createProductSchema(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categorias_producto (
          id_categoria_producto INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL UNIQUE,
          color INTEGER NOT NULL DEFAULT 4280391418,
          estado INTEGER NOT NULL DEFAULT 1
        )
      ''');
      if (oldVersion >= 3 &&
          !await _hasColumn(db, 'productos', 'id_categoria_producto')) {
        await db.execute(
          'ALTER TABLE productos ADD COLUMN id_categoria_producto INTEGER',
        );
      }
      await _createSalesSchema(db);
      await _seedProductCategories(db);
    }
    if (oldVersion < 5 && !await _hasColumn(db, 'ventas', 'metodo_pago')) {
      await db.execute(
        "ALTER TABLE ventas ADD COLUMN metodo_pago TEXT NOT NULL DEFAULT 'EFECTIVO'",
      );
      await _seedProductCategories(db);
    }
    if (oldVersion < 6) {
      if (!await _hasColumn(db, 'unidades_medida', 'factor_base')) {
        await db.execute(
          'ALTER TABLE unidades_medida ADD COLUMN factor_base REAL NOT NULL DEFAULT 1',
        );
      }
      if (!await _hasColumn(db, 'receta_detalle', 'id_unidad')) {
        await db.execute(
          'ALTER TABLE receta_detalle ADD COLUMN id_unidad INTEGER',
        );
      }
      await _setUnitFactors(db);
      final items = await db.rawQuery('''
        SELECT i.id_insumo,
               COALESCE(i.stock_actual, 0) AS stock_actual,
               COALESCE(i.stock_minimo, 0) AS stock_minimo,
               COALESCE(i.costo_promedio, 0) AS costo_promedio,
               COALESCE(u.factor_base, 1) AS factor_base
        FROM insumos i
        INNER JOIN unidades_medida u ON u.id_unidad = i.id_unidad
      ''');
      for (final item in items) {
        final factor = (item['factor_base'] as num?)?.toDouble() ?? 1;
        await db.update(
          'insumos',
          {
            'stock_actual':
                ((item['stock_actual'] as num?)?.toDouble() ?? 0) * factor,
            'stock_minimo':
                ((item['stock_minimo'] as num?)?.toDouble() ?? 0) * factor,
            'costo_promedio':
                ((item['costo_promedio'] as num?)?.toDouble() ?? 0) / factor,
          },
          where: 'id_insumo = ?',
          whereArgs: [item['id_insumo']],
        );
      }
    }
  }

  Future<bool> _hasColumn(
    Database db,
    String tableName,
    String columnName,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    return columns.any((column) => column['name'] == columnName);
  }

  Future<void> _createProductSchema(Database db) async {
    await db.execute('''
      CREATE TABLE categorias_producto (
        id_categoria_producto INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL DEFAULT 4280391418,
        estado INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE productos (
        id_producto INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        precio_venta REAL NOT NULL DEFAULT 0,
        id_categoria_producto INTEGER,
        foto BLOB,
        estado INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE recetas (
        id_receta INTEGER PRIMARY KEY AUTOINCREMENT,
        id_producto INTEGER NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        instrucciones TEXT,
        estado INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
      )
    ''');
    await db.execute('''
      CREATE TABLE receta_detalle (
        id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
        id_receta INTEGER NOT NULL,
        id_insumo INTEGER NOT NULL,
        id_unidad INTEGER,
        cantidad REAL NOT NULL,
        FOREIGN KEY (id_receta) REFERENCES recetas(id_receta),
        FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo),
        FOREIGN KEY (id_unidad) REFERENCES unidades_medida(id_unidad),
        UNIQUE (id_receta, id_insumo)
      )
    ''');
    await _createSalesSchema(db);
    await _seedProductCategories(db);
  }

  Future<void> _createSalesSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ventas (
        id_venta INTEGER PRIMARY KEY AUTOINCREMENT,
        total REAL NOT NULL,
        estado TEXT NOT NULL CHECK (estado IN ('PENDIENTE', 'REALIZADA')),
        metodo_pago TEXT NOT NULL DEFAULT 'EFECTIVO',
        fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS venta_detalle (
        id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
        id_venta INTEGER NOT NULL,
        id_producto INTEGER NOT NULL,
        cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta),
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
      )
    ''');
  }

  Future<void> _seedProductCategories(Database db) async {
    for (final category in [
      {'nombre': 'Desayunos', 'color': 4294940672},
      {'nombre': 'Sandwiches', 'color': 4283215696},
      {'nombre': 'Gaseosas', 'color': 4280391418},
      {'nombre': 'Jugos', 'color': 4294924066},
      {'nombre': 'Frappes', 'color': 4283215696},
    ]) {
      await db.insert(
        'categorias_producto',
        category,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categorias_insumo (
        id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        estado INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE unidades_medida (
        id_unidad INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        abreviatura TEXT NOT NULL,
        factor_base REAL NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE insumos (
        id_insumo INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        id_categoria INTEGER NOT NULL,
        id_unidad INTEGER NOT NULL,
        stock_actual REAL NOT NULL DEFAULT 0,
        stock_minimo REAL NOT NULL DEFAULT 0,
        costo_promedio REAL NOT NULL DEFAULT 0,
        estado INTEGER NOT NULL DEFAULT 1,
        foto BLOB,
        FOREIGN KEY (id_categoria) REFERENCES categorias_insumo(id_categoria),
        FOREIGN KEY (id_unidad) REFERENCES unidades_medida(id_unidad)
      )
    ''');
    await db.execute('''
      CREATE TABLE movimientos_inventario (
        id_movimiento INTEGER PRIMARY KEY AUTOINCREMENT,
        id_insumo INTEGER NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('ENTRADA', 'SALIDA', 'AJUSTE')),
        origen TEXT NOT NULL,
        cantidad REAL NOT NULL,
        costo_unitario REAL,
        id_referencia INTEGER,
        fecha_hora TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (id_insumo) REFERENCES insumos(id_insumo)
      )
    ''');
    await _createProductSchema(db);

    await db.insert('categorias_insumo', {'nombre': 'Bebidas'});
    await db.insert('categorias_insumo', {'nombre': 'Alimentos'});
    await db.insert('categorias_insumo', {'nombre': 'Desechables'});
    for (final unit in [
      {'nombre': 'Kilogramo', 'abreviatura': 'kg'},
      {'nombre': 'Gramo', 'abreviatura': 'g'},
      {'nombre': 'Litro', 'abreviatura': 'L'},
      {'nombre': 'Mililitro', 'abreviatura': 'ml'},
      {'nombre': 'Unidad', 'abreviatura': 'und'},
    ]) {
      await db.insert('unidades_medida', unit);
    }
    await _setUnitFactors(db);
  }

  Future<void> _setUnitFactors(Database db) async {
    final factors = <String, double>{
      'Kilogramo': 1000,
      'Gramo': 1,
      'Litro': 1000,
      'Mililitro': 1,
      'Unidad': 1,
    };
    for (final entry in factors.entries) {
      await db.update(
        'unidades_medida',
        {'factor_base': entry.value},
        where: 'nombre = ?',
        whereArgs: [entry.key],
      );
    }
  }
}
