import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'catalog_repository.dart';
import 'date_utils.dart';

class MenuDia {
  const MenuDia({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.estado,
    this.observacion,
    this.precioAlmuerzo,
  });

  final int id;
  final String fecha;
  final String tipo;
  final String estado;
  final String? observacion;

  /// Precio fijo del almuerzo completo (sopa + plato suelto) del día. Si es
  /// nulo, el completo se vende como `plato + sopa`.
  final double? precioAlmuerzo;

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

  bool get esSopa => MenuRepository.esCategoriaSopa(categoriaNombre);
}

class MenuCombo {
  const MenuCombo({
    required this.id,
    required this.menuDiaId,
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.categoriaNombre,
    required this.categoriaColor,
    required this.disponible,
    required this.orden,
    required this.componentes,
    this.imagen,
  });

  final int id;
  final int menuDiaId;
  final int productoId;
  final String nombre;
  final double precio;
  final String categoriaNombre;
  final int categoriaColor;
  final bool disponible;
  final int orden;
  final List<ProductoComponente> componentes;
  final Uint8List? imagen;

  double get sumaComponentes => componentes.fold<double>(
    0,
    (suma, componente) => suma + componente.precio * componente.cantidad,
  );
}

class MenuRepository {
  static const String tipoMenu = 'ALMUERZO';

  static bool esCategoriaSopa(String nombre) =>
      nombre.trim().toUpperCase() == 'SOPAS';

  static bool esCategoriaPlatoSuelto(String nombre) =>
      nombre.trim().toUpperCase() == 'PLATOS SUELTOS';

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
    if (anterior.precioAlmuerzo != null) {
      await db.update(
        'menus_dia',
        {'precio_almuerzo': anterior.precioAlmuerzo},
        where: 'id = ?',
        whereArgs: [nuevo.id],
      );
    }
    final items = await db.rawQuery(
      '''
      SELECT mi.*, c.nombre AS categoria_nombre
      FROM menu_dia_items mi
      INNER JOIN productos p ON p.id = mi.producto_id
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      WHERE mi.menu_dia_id = ?
        AND COALESCE(mi.motivo_agotado, '') <> 'MENU_REEMPLAZADO'
      ORDER BY mi.orden, mi.id
      ''',
      [anterior.id],
    );
    var yaCopioSopa = false;
    for (final item in items) {
      final esSopa = esCategoriaSopa(item['categoria_nombre'] as String);
      if (esSopa && yaCopioSopa) continue;
      if (esSopa) yaCopioSopa = true;
      await db.insert('menu_dia_items', {
        'menu_dia_id': nuevo.id,
        'producto_id': item['producto_id'],
        'disponible': 1,
        'orden': item['orden'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // Los combos antiguos quedan como historial, pero no se copian: el
    // completo ahora se calcula al vender a partir del plato y la sopa del día.
    // El menú del día siguiente conserva la publicación anterior para que se
    // pueda vender sin volver a publicarlo. Un borrador sigue siendo borrador.
    if (anterior.habilitado) {
      await db.update(
        'menus_dia',
        {'estado': 'HABILITADO', 'habilitado_en': sqlNow()},
        where: 'id = ?',
        whereArgs: [nuevo.id],
      );
      return MenuDia(
        id: nuevo.id,
        fecha: nuevo.fecha,
        tipo: nuevo.tipo,
        estado: 'HABILITADO',
        observacion: nuevo.observacion,
        precioAlmuerzo: anterior.precioAlmuerzo,
      );
    }
    return MenuDia(
      id: nuevo.id,
      fecha: nuevo.fecha,
      tipo: nuevo.tipo,
      estado: nuevo.estado,
      observacion: nuevo.observacion,
      precioAlmuerzo: anterior.precioAlmuerzo,
    );
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
        AND COALESCE(mi.motivo_agotado, '') <> 'MENU_REEMPLAZADO'
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

  Future<List<MenuCombo>> getCombos(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT mc.*, p.nombre AS producto_nombre, p.imagen,
             c.nombre AS categoria_nombre, c.color AS categoria_color
      FROM menu_dia_combos mc
      INNER JOIN productos p ON p.id = mc.producto_id
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      WHERE mc.menu_dia_id = ?
      ORDER BY mc.orden, mc.nombre COLLATE NOCASE
    ''',
      [menuDiaId],
    );
    final catalog = CatalogRepository();
    final combos = <MenuCombo>[];
    for (final row in rows) {
      final productoId = row['producto_id']! as int;
      combos.add(
        MenuCombo(
          id: row['id']! as int,
          menuDiaId: row['menu_dia_id']! as int,
          productoId: productoId,
          nombre: row['nombre']! as String,
          precio: (row['precio'] as num).toDouble(),
          categoriaNombre: row['categoria_nombre']! as String,
          categoriaColor: (row['categoria_color'] as num).toInt(),
          disponible: (row['disponible'] as num).toInt() == 1,
          orden: (row['orden'] as num?)?.toInt() ?? 0,
          componentes: await catalog.getComponentes(productoId),
          imagen: _asBytes(row['imagen']),
        ),
      );
    }
    return combos;
  }

  Future<bool> tieneCombosLegacy(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM menu_dia_combos WHERE menu_dia_id = ?',
        [menuDiaId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<int> agregarCombo({
    required int menuDiaId,
    required int productoId,
    required String nombre,
    required double precio,
  }) async {
    final db = await AppDatabase.instance.database;
    final maxRows = await db.rawQuery(
      'SELECT COALESCE(MAX(orden), 0) AS maximo FROM menu_dia_combos WHERE menu_dia_id = ?',
      [menuDiaId],
    );
    final orden = ((maxRows.first['maximo'] as num?)?.toInt() ?? 0) + 1;
    return db.insert('menu_dia_combos', {
      'menu_dia_id': menuDiaId,
      'producto_id': productoId,
      'nombre': nombre,
      'precio': precio,
      'descuento_porcentaje': 0,
      'disponible': 1,
      'orden': orden,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> actualizarCombo(
    int comboId, {
    required String nombre,
    required double precio,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menu_dia_combos',
      {'nombre': nombre, 'precio': precio},
      where: 'id = ?',
      whereArgs: [comboId],
    );
  }

  Future<void> setComboDisponible(int comboId, bool disponible) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menu_dia_combos',
      {'disponible': disponible ? 1 : 0},
      where: 'id = ?',
      whereArgs: [comboId],
    );
  }

  Future<void> quitarCombo(int comboId) async {
    final db = await AppDatabase.instance.database;
    await db.delete('menu_dia_combos', where: 'id = ?', whereArgs: [comboId]);
  }

  /// Agrega un producto al menú del día (o lo reactiva si ya existía).
  /// Devuelve el id del item para poder actualizarlo sin recargar la pantalla.
  Future<int> agregarProducto(int menuDiaId, int productoId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final productoRows = await txn.rawQuery(
        '''
        SELECT c.nombre AS categoria_nombre
        FROM productos p
        INNER JOIN categorias_producto c ON c.id = p.categoria_id
        WHERE p.id = ?
        LIMIT 1
        ''',
        [productoId],
      );
      if (productoRows.isEmpty) {
        throw StateError('El producto no existe.');
      }
      final esSopa = esCategoriaSopa(
        productoRows.first['categoria_nombre'] as String,
      );
      if (esSopa) {
        // Solo puede quedar una sopa seleccionada para este día. Al cambiarla,
        // las ventas ya registradas conservan la sopa original.
        final sopasEnMenu = await txn.rawQuery(
          '''
          SELECT mi.id, mi.producto_id
          FROM menu_dia_items mi
          INNER JOIN productos p ON p.id = mi.producto_id
          INNER JOIN categorias_producto c ON c.id = p.categoria_id
          WHERE mi.menu_dia_id = ?
            AND UPPER(TRIM(c.nombre)) = 'SOPAS'
            AND mi.producto_id <> ?
          ''',
          [menuDiaId, productoId],
        );
        for (final sopa in sopasEnMenu) {
          await _quitarItemEnTxn(txn, sopa['id']! as int);
        }
      }
      final existente = await txn.query(
        'menu_dia_items',
        columns: ['id'],
        where: 'menu_dia_id = ? AND producto_id = ?',
        whereArgs: [menuDiaId, productoId],
        limit: 1,
      );
      if (existente.isNotEmpty) {
        final itemId = existente.first['id']! as int;
        await txn.update(
          'menu_dia_items',
          {'disponible': 1, 'motivo_agotado': null},
          where: 'id = ?',
          whereArgs: [itemId],
        );
        return itemId;
      }
      final maxRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(orden), 0) AS maximo FROM menu_dia_items WHERE menu_dia_id = ?',
        [menuDiaId],
      );
      final orden = ((maxRows.first['maximo'] as num?)?.toInt() ?? 0) + 1;
      return txn.insert('menu_dia_items', {
        'menu_dia_id': menuDiaId,
        'producto_id': productoId,
        'disponible': 1,
        'orden': orden,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  /// Selecciona o quita todos los productos de una categoría del menú.
  /// No agrega SOPAS ni productos de categorías siempre disponibles.
  Future<void> seleccionarCategoria({
    required int menuDiaId,
    required List<int> productoIds,
    required bool seleccionado,
  }) async {
    if (productoIds.isEmpty) return;
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final productoId in productoIds.toSet()) {
        final rows = await txn.rawQuery(
          '''
          SELECT c.nombre AS categoria_nombre,
                 c.siempre_disponible,
                 p.tipo,
                 p.activo
          FROM productos p
          INNER JOIN categorias_producto c ON c.id = p.categoria_id
          WHERE p.id = ?
          LIMIT 1
          ''',
          [productoId],
        );
        if (rows.isEmpty) continue;
        final row = rows.first;
        if (esCategoriaSopa(row['categoria_nombre'] as String) ||
            (row['siempre_disponible'] as num).toInt() == 1 ||
            (row['tipo'] as String) == 'DIRECTO' ||
            (row['activo'] as num).toInt() != 1) {
          continue;
        }
        final existentes = await txn.query(
          'menu_dia_items',
          columns: ['id', 'motivo_agotado'],
          where: 'menu_dia_id = ? AND producto_id = ?',
          whereArgs: [menuDiaId, productoId],
          limit: 1,
        );
        if (!seleccionado) {
          if (existentes.isNotEmpty) {
            await _quitarItemEnTxn(txn, existentes.first['id']! as int);
          }
          continue;
        }
        if (existentes.isNotEmpty) {
          if (existentes.first['motivo_agotado'] != 'MENU_REEMPLAZADO') {
            continue;
          }
          await txn.update(
            'menu_dia_items',
            {'disponible': 1, 'motivo_agotado': null},
            where: 'id = ?',
            whereArgs: [existentes.first['id']],
          );
          continue;
        }
        final maxRows = await txn.rawQuery(
          'SELECT COALESCE(MAX(orden), 0) AS maximo FROM menu_dia_items WHERE menu_dia_id = ?',
          [menuDiaId],
        );
        final orden = ((maxRows.first['maximo'] as num?)?.toInt() ?? 0) + 1;
        await txn.insert('menu_dia_items', {
          'menu_dia_id': menuDiaId,
          'producto_id': productoId,
          'disponible': 1,
          'orden': orden,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> _quitarItemEnTxn(DatabaseExecutor txn, int itemId) async {
    final referencias =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            '''
        SELECT COUNT(*) FROM detalle_pedido
        WHERE menu_dia_item_id = ? OR menu_dia_sopa_item_id = ?
        ''',
            [itemId, itemId],
          ),
        ) ??
        0;
    if (referencias > 0) {
      await txn.update(
        'menu_dia_items',
        {'disponible': 0, 'motivo_agotado': 'MENU_REEMPLAZADO'},
        where: 'id = ?',
        whereArgs: [itemId],
      );
    } else {
      await txn.delete('menu_dia_items', where: 'id = ?', whereArgs: [itemId]);
    }
  }

  /// Deja el menú exactamente con los productos indicados, en ese orden.
  Future<void> reemplazarItems(int menuDiaId, List<int> productoIds) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final existentes = await txn.query(
        'menu_dia_items',
        columns: ['id'],
        where: 'menu_dia_id = ?',
        whereArgs: [menuDiaId],
      );
      for (final item in existentes) {
        await _quitarItemEnTxn(txn, item['id']! as int);
      }
      var orden = 0;
      var yaSeleccionoSopa = false;
      for (final productoId in productoIds.toSet()) {
        final categorias = await txn.rawQuery(
          '''
          SELECT c.nombre AS categoria_nombre
          FROM productos p
          INNER JOIN categorias_producto c ON c.id = p.categoria_id
          WHERE p.id = ?
          LIMIT 1
          ''',
          [productoId],
        );
        if (categorias.isEmpty) continue;
        final esSopa = esCategoriaSopa(
          categorias.first['categoria_nombre'] as String,
        );
        if (esSopa && yaSeleccionoSopa) continue;
        if (esSopa) yaSeleccionoSopa = true;
        orden++;
        final itemExistente = await txn.query(
          'menu_dia_items',
          columns: ['id'],
          where: 'menu_dia_id = ? AND producto_id = ?',
          whereArgs: [menuDiaId, productoId],
          limit: 1,
        );
        if (itemExistente.isNotEmpty) {
          await txn.update(
            'menu_dia_items',
            {'disponible': 1, 'motivo_agotado': null, 'orden': orden},
            where: 'id = ?',
            whereArgs: [itemExistente.first['id']],
          );
        } else {
          await txn.insert('menu_dia_items', {
            'menu_dia_id': menuDiaId,
            'producto_id': productoId,
            'disponible': 1,
            'orden': orden,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  /// Deja el menú sin sopa ni platos, conservando las filas que ya tienen
  /// ventas asociadas para proteger el historial.
  Future<void> limpiarMenu(int menuDiaId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final items = await txn.query(
        'menu_dia_items',
        columns: ['id'],
        where: 'menu_dia_id = ?',
        whereArgs: [menuDiaId],
      );
      for (final item in items) {
        await _quitarItemEnTxn(txn, item['id']! as int);
      }
      await txn.delete(
        'menu_dia_combos',
        where: 'menu_dia_id = ?',
        whereArgs: [menuDiaId],
      );
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
      where: "menu_dia_id = ? AND COALESCE(motivo_agotado, '') <> 'MENU_REEMPLAZADO'",
      whereArgs: [anteriores.first['id']],
      orderBy: 'orden',
    );
    return items.map((item) => item['producto_id']! as int).toList();
  }

  Future<void> quitarItem(int itemId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) => _quitarItemEnTxn(txn, itemId));
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

  /// Fija o limpia el precio del almuerzo completo del día. Un valor nulo
  /// vuelve al cálculo automático (plato + sopa).
  Future<void> setPrecioAlmuerzo(int menuDiaId, double? precio) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'menus_dia',
      {'precio_almuerzo': precio},
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
    precioAlmuerzo: (row['precio_almuerzo'] as num?)?.toDouble(),
  );

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }
}
