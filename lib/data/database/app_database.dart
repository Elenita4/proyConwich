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
    return openDatabase(path, version: 1, onCreate: _createSchema);
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
        abreviatura TEXT NOT NULL
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
  }
}
