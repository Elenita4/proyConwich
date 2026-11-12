import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';

class MenuDia {
  const MenuDia({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.estado,
    this.observacion,
  });

  final int id;
  final String fecha;
  final String tipo;
  final String estado;
  final String? observacion;

  bool get habilitado => estado == 'HABILITADO';
  bool get cerrado => estado == 'CERRADO';
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.menuDiaId,
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.tipoProducto,
    required this.disponible,
    this.motivoAgotado,
    required this.orden,
  });

  final int id;
  final int menuDiaId;
  final int productoId;
  final String nombre;
  final double precio;
  final String categoriaNombre;
  final int categoriaColor;
  final String tipoProducto;
  final bool disponible;
  final String? motivoAgotado;
  final int orden;
}

class MenuRepository {
  static const String tipoMenu = 'ALMUERZO';

  Future<MenuDia?> getMenu(DateTime fecha, String tipo) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'menus_dia',
      where: 'fecha = ? AND tipo = ?',
      whereArgs: [sqlDate(fecha), tipo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<MenuDia> crearMenu(
    DateTime fecha,
    String tipo,
    int usuarioId, {
    String? observacion,
  }) async {
    final existente = await getMenu(fecha, tipo);
    if (existente != null) return existente;
    final db = await AppDatabase.instance.database;
    final id = await db.insert('menus_dia', {
      'fecha': sqlDate(fecha),
      'tipo': tipo,
      'estado': 'BORRADOR',
      'usuario_id': usuarioId,
      'observacion': observacion,
      'creado_en': sqlNow(),
    });
    return MenuDia(
      id: id,
      fecha: sqlDate(fecha),
      tipo: tipo,
      estado: 'BORRADOR',
      observacion: observacion,
    );
  }

  Future<MenuDia?> duplicarAnterior(
    DateTime fecha,
    String tipo,
    int usuarioId,
  ) async {
    final db = await AppDatabase.instance.database;
    final anteriores = await db.query(
      'menus_dia',
      where: 'tipo = ? AND fecha < ?',
      whereArgs: [tipo, sqlDate(fecha)],
      orderBy: 'fecha DESC',
      limit: 1,
    );
    if (anteriores.isEmpty) return null;
    final anterior = _fromRow(anteriores.first);
    final nuevo = await crearMenu(fecha, tipo, usuarioId);
    final items = await db.query(
      'menu_dia_items',
      where: 'menu_dia_id = ?',
      whereArgs: [anterior.id],
      orderBy: 'orden',
    );
    for (final item in items) {
      await db.insert('menu_dia_items', {
        'menu_dia_id': nuevo.id,
        'producto_id': item['producto_id'],
        'disponible': 1,
        'orden': item['orden'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return nuevo;
  }

  Future<List<MenuItem>> getItems(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT mi.*, p.nombre, p.precio, p.tipo AS tipo_producto,
             c.nombre AS categoria_nombre, c.color AS categoria_color
      FROM menu_dia_items mi
      INNER JOIN productos p ON p.id = mi.producto_id
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      WHERE mi.menu_dia_id = ?
      ORDER BY mi.orden, p.nombre COLLATE NOCASE
    ''',
      [menuDiaId],
    );
    return rows
        .map(
          (row) => MenuItem(
            id: row['id']! as int,
            menuDiaId: row['menu_dia_id']! as int,
            productoId: row['producto_id']! as int,
            nombre: row['nombre']! as String,
            precio: (row['precio'] as num).toDouble(),
            categoriaNombre: row['categoria_nombre']! as String,
            categoriaColor: row['categoria_color']! as int,
            tipoProducto: row['tipo_producto']! as String,
            disponible: (row['disponible'] as num).toInt() == 1,
            motivoAgotado: row['motivo_agotado'] as String?,
            orden: (row['orden'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  Future<void> agregarProducto(int menuDiaId, int productoId) async {
    final db = await AppDatabase.instance.database;
    final maxRows = await db.rawQuery(
      'SELECT COALESCE(MAX(orden), 0) AS maximo FROM menu_dia_items WHERE menu_dia_id = ?',
      [menuDiaId],
    );
    final orden = ((maxRows.first['maximo'] as num?)?.toInt() ?? 0) + 1;
    await db.insert('menu_dia_items', {
      'menu_dia_id': menuDiaId,
      'producto_id': productoId,
      'disponible': 1,
      'orden': orden,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Deja el menú exactamente con los productos indicados, en ese orden.
  Future<void> reemplazarItems(int menuDiaId, List<int> productoIds) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'menu_dia_items',
        where: 'menu_dia_id = ?',
        whereArgs: [menuDiaId],
      );
      var orden = 0;
      for (final productoId in productoIds.toSet()) {
        orden++;
        await txn.insert('menu_dia_items', {
          'menu_dia_id': menuDiaId,
          'producto_id': productoId,
          'disponible': 1,
          'orden': orden,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// Productos del último menú del mismo tipo anterior a [fecha].
  Future<List<int>> getProductosMenuAnterior(
    DateTime fecha,
    String tipo,
  ) async {
    final db = await AppDatabase.instance.database;
    final anteriores = await db.query(
      'menus_dia',
      columns: ['id'],
      where: 'tipo = ? AND fecha < ?',
      whereArgs: [tipo, sqlDate(fecha)],
      orderBy: 'fecha DESC',
      limit: 1,
    );
    if (anteriores.isEmpty) return <int>[];
    final items = await db.query(
      'menu_dia_items',
      columns: ['producto_id'],
      where: 'menu_dia_id = ?',
      whereArgs: [anteriores.first['id']],
      orderBy: 'orden',
    );
    return items.map((item) => item['producto_id']! as int).toList();
  }

  Future<void> quitarItem(int itemId) async {
    final db = await AppDatabase.instance.database;
    await db.delete('menu_dia_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> setDisponible(
    int itemId,
    bool disponible, {
    String? motivo,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menu_dia_items',
      {
        'disponible': disponible ? 1 : 0,
        'motivo_agotado': disponible ? null : motivo,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> habilitar(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menus_dia',
      {'estado': 'HABILITADO', 'habilitado_en': sqlNow()},
      where: 'id = ?',
      whereArgs: [menuDiaId],
    );
  }

  Future<void> cerrar(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menus_dia',
      {'estado': 'CERRADO'},
      where: 'id = ?',
      whereArgs: [menuDiaId],
    );
  }

  Future<List<MenuItem>> getMenuHabilitado(DateTime fecha, String tipo) async {
    final menu = await getMenu(fecha, tipo);
    if (menu == null || !menu.habilitado) return <MenuItem>[];
    return getItems(menu.id);
  }

  MenuDia _fromRow(Map<String, Object?> row) => MenuDia(
    id: row['id']! as int,
    fecha: row['fecha']! as String,
    tipo: row['tipo']! as String,
    estado: row['estado']! as String,
    observacion: row['observacion'] as String?,
  );
}
