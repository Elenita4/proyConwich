import '../../../data/database/app_database.dart';

import 'dart:typed_data';

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.code,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.unitId,
    required this.unitAbbreviation,
    required this.currentStock,
    required this.minimumStock,
    required this.averageCost,
    required this.active,
    this.photo,
  });

  final int? id;
  final String code;
  final String name;
  final int categoryId;
  final String categoryName;
  final int unitId;
  final String unitAbbreviation;
  final double currentStock;
  final double minimumStock;
  final double averageCost;
  final bool active;
  final Uint8List? photo;

  bool get lowStock => currentStock <= minimumStock;

  Map<String, Object?> toMap() => {
    'codigo': code,
    'nombre': name,
    'id_categoria': categoryId,
    'id_unidad': unitId,
    'stock_actual': currentStock,
    'stock_minimo': minimumStock,
    'costo_promedio': averageCost,
    'estado': active ? 1 : 0,
    'foto': photo,
  };

  factory InventoryItem.fromMap(Map<String, Object?> map) => InventoryItem(
    id: map['id_insumo'] as int?,
    code: map['codigo'] as String,
    name: map['nombre'] as String,
    categoryId: map['id_categoria'] as int,
    categoryName: map['categoria_nombre'] as String,
    unitId: map['id_unidad'] as int,
    unitAbbreviation: map['unidad_abreviatura'] as String,
    currentStock: (map['stock_actual'] as num).toDouble(),
    minimumStock: (map['stock_minimo'] as num).toDouble(),
    averageCost: (map['costo_promedio'] as num).toDouble(),
    active: (map['estado'] as int) == 1,
    photo: map['foto'] as Uint8List?,
  );
}

class InventoryLookup {
  const InventoryLookup({
    required this.id,
    required this.name,
    this.abbreviation,
  });
  final int id;
  final String name;
  final String? abbreviation;
}

class InventoryRepository {
  Future<String> generateCode(int categoryId) async {
    final db = await AppDatabase.instance.database;
    final category = await db.query(
      'categorias_insumo',
      columns: ['nombre'],
      where: 'id_categoria = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (category.isEmpty) throw StateError('La categoría no existe.');
    final prefix = _prefix(category.first['nombre'] as String);
    final rows = await db.query(
      'insumos',
      columns: ['codigo'],
      where: 'codigo LIKE ?',
      whereArgs: ['$prefix%'],
    );
    var next = 1;
    for (final row in rows) {
      final match = RegExp('^$prefix(\\d+)\$').firstMatch(row['codigo'] as String);
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number >= next) next = number + 1;
    }
    return '$prefix${next.toString().padLeft(4, '0')}';
  }

  String _prefix(String name) {
    final normalized = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    return normalized.padRight(3, 'X').substring(0, 3);
  }

  Future<List<InventoryItem>> getItems() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT i.*, c.nombre AS categoria_nombre, u.abreviatura AS unidad_abreviatura
      FROM insumos i
      INNER JOIN categorias_insumo c ON c.id_categoria = i.id_categoria
      INNER JOIN unidades_medida u ON u.id_unidad = i.id_unidad
      ORDER BY i.estado DESC, i.nombre COLLATE NOCASE
    ''');
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryLookup>> getCategories() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categorias_insumo',
      columns: ['id_categoria', 'nombre'],
      where: 'estado = 1',
      orderBy: 'nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => InventoryLookup(
            id: row['id_categoria']! as int,
            name: row['nombre']! as String,
          ),
        )
        .toList();
  }

  Future<List<InventoryLookup>> getUnits() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'unidades_medida',
      columns: ['id_unidad', 'nombre', 'abreviatura'],
      orderBy: 'nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => InventoryLookup(
            id: row['id_unidad']! as int,
            name: row['nombre']! as String,
            abbreviation: row['abreviatura']! as String,
          ),
        )
        .toList();
  }

  Future<void> saveItem(InventoryItem item) async {
    final db = await AppDatabase.instance.database;
    if (item.id == null) {
      await db.insert('insumos', item.toMap());
    } else {
      await db.update(
        'insumos',
        item.toMap(),
        where: 'id_insumo = ?',
        whereArgs: [item.id],
      );
    }
  }

  Future<void> addStock({
    required int itemId,
    required double quantity,
    required double unitCost,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      await transaction.rawUpdate(
        'UPDATE insumos SET '
        'costo_promedio = CASE WHEN stock_actual + ? = 0 THEN 0 '
        'ELSE ((stock_actual * costo_promedio) + (? * ?)) / (stock_actual + ?) END, '
        'stock_actual = stock_actual + ? '
        'WHERE id_insumo = ?',
        [quantity, quantity, unitCost, quantity, quantity, itemId],
      );
      await transaction.insert('movimientos_inventario', {
        'id_insumo': itemId,
        'tipo': 'ENTRADA',
        'origen': 'Carga manual',
        'cantidad': quantity,
        'costo_unitario': unitCost,
      });
    });
  }

  Future<void> deleteItem(int id) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'insumos',
      {'estado': 0},
      where: 'id_insumo = ?',
      whereArgs: [id],
    );
  }
}
