import 'dart:typed_data';

import '../data/database/app_database.dart';
import 'date_utils.dart';

class CategoriaProducto {
  const CategoriaProducto({
    this.id,
    required this.nombre,
    required this.color,
    required this.siempreDisponible,
    required this.orden,
    required this.activo,
  });

  final int? id;
  final String nombre;
  final int color;
  final bool siempreDisponible;
  final int orden;
  final bool activo;
}

class UnidadMedida {
  const UnidadMedida({
    required this.id,
    required this.nombre,
    required this.abreviatura,
  });

  final int id;
  final String nombre;
  final String abreviatura;
}

class Producto {
  const Producto({
    this.id,
    required this.nombre,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.categoriaColor,
    this.descripcion,
    required this.precio,
    this.imagen,
    required this.tipo,
    required this.stockMinimo,
    required this.costoUnitario,
    required this.activo,
    required this.stock,
  });

  final int? id;
  final String nombre;
  final int categoriaId;
  final String categoriaNombre;
  final int categoriaColor;
  final String? descripcion;
  final double precio;
  final Uint8List? imagen;
  final String tipo;
  final double stockMinimo;
  final double costoUnitario;
  final bool activo;
  final double stock;

  bool get esDirecto => tipo == 'DIRECTO';
}

class Insumo {
  const Insumo({
    this.id,
    required this.nombre,
    required this.unidadId,
    required this.unidadAbreviatura,
    required this.modoControl,
    required this.disponible,
    required this.stockMinimo,
    required this.costoPromedio,
    this.presentacionCompra,
    required this.factorCompra,
    required this.activo,
    required this.stock,
  });

  final int? id;
  final String nombre;
  final int unidadId;
  final String unidadAbreviatura;
  final String modoControl;
  final bool disponible;
  final double stockMinimo;
  final double costoPromedio;
  final String? presentacionCompra;
  final double factorCompra;
  final bool activo;
  final double stock;

  bool get porDisponibilidad => modoControl == 'DISPONIBILIDAD';
  bool get bajoStock => !porDisponibilidad && stock <= stockMinimo;
}

class RecetaLinea {
  const RecetaLinea({
    required this.insumoId,
    required this.insumoNombre,
    required this.unidadAbreviatura,
    required this.modoControl,
    required this.cantidad,
    required this.stock,
    required this.disponible,
  });

  final int insumoId;
  final String insumoNombre;
  final String unidadAbreviatura;
  final String modoControl;
  final double cantidad;
  final double stock;
  final bool disponible;
}

class CatalogRepository {
  Future<List<CategoriaProducto>> getCategorias({
    bool soloActivas = false,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categorias_producto',
      where: soloActivas ? 'activo = 1' : null,
      orderBy: 'activo DESC, orden, nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => CategoriaProducto(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            color: row['color']! as int,
            siempreDisponible: (row['siempre_disponible'] as num).toInt() == 1,
            orden: (row['orden'] as num?)?.toInt() ?? 0,
            activo: (row['activo'] as num).toInt() == 1,
          ),
        )
        .toList();
  }

  Future<void> saveCategoria(CategoriaProducto categoria) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': categoria.nombre.trim(),
      'color': categoria.color,
      'siempre_disponible': categoria.siempreDisponible ? 1 : 0,
      'orden': categoria.orden,
      'activo': categoria.activo ? 1 : 0,
    };
    if (categoria.id == null) {
      await db.insert('categorias_producto', values);
    } else {
      await db.update(
        'categorias_producto',
        values,
        where: 'id = ?',
        whereArgs: [categoria.id],
      );
    }
  }

  Future<void> setCategoriaActiva(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'categorias_producto',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<UnidadMedida>> getUnidades() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'unidades_medida',
      where: 'activo = 1',
      orderBy: 'nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => UnidadMedida(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            abreviatura: row['abreviatura']! as String,
          ),
        )
        .toList();
  }

  Future<List<Producto>> getProductos({bool soloActivos = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.nombre AS categoria_nombre, c.color AS categoria_color,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      ${soloActivos ? 'WHERE p.activo = 1 AND c.activo = 1' : ''}
      ORDER BY p.activo DESC, c.orden, p.nombre COLLATE NOCASE
    ''');
    return rows.map(_productFromRow).toList();
  }

  Future<Producto?> getProducto(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.nombre AS categoria_nombre, c.color AS categoria_color,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      WHERE p.id = ?
      LIMIT 1
    ''', [id]);
    return rows.isEmpty ? null : _productFromRow(rows.first);
  }

  Future<int> saveProducto(Producto producto) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': producto.nombre.trim(),
      'categoria_id': producto.categoriaId,
      'descripcion': producto.descripcion?.trim().isEmpty == true
          ? null
          : producto.descripcion?.trim(),
      'precio': producto.precio,
      'imagen': producto.imagen,
      'tipo': producto.tipo,
      'stock_minimo': producto.esDirecto ? producto.stockMinimo : 0,
      'costo_unitario': producto.esDirecto ? producto.costoUnitario : 0,
      'activo': producto.activo ? 1 : 0,
    };
    if (producto.id == null) {
      values['creado_en'] = sqlNow();
      return db.insert('productos', values);
    }
    await db.update(
      'productos',
      values,
      where: 'id = ?',
      whereArgs: [producto.id],
    );
    return producto.id!;
  }

  Future<void> setProductoActivo(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'productos',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<RecetaLinea>> getReceta(int productoId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT r.insumo_id, i.nombre AS insumo_nombre,
             u.abreviatura AS unidad_abreviatura, i.modo_control,
             r.cantidad, i.disponible,
             COALESCE(s.stock, 0) AS stock
      FROM receta_insumos r
      INNER JOIN insumos i ON i.id = r.insumo_id
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE r.producto_id = ?
      ORDER BY i.nombre COLLATE NOCASE
    ''', [productoId]);
    return rows
        .map(
          (row) => RecetaLinea(
            insumoId: row['insumo_id']! as int,
            insumoNombre: row['insumo_nombre']! as String,
            unidadAbreviatura: row['unidad_abreviatura']! as String,
            modoControl: row['modo_control']! as String,
            cantidad: (row['cantidad'] as num).toDouble(),
            stock: (row['stock'] as num).toDouble(),
            disponible: (row['disponible'] as num).toInt() == 1,
          ),
        )
        .toList();
  }

  Future<void> saveReceta(int productoId, List<RecetaLinea> lineas) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'receta_insumos',
        where: 'producto_id = ?',
        whereArgs: [productoId],
      );
      for (final linea in lineas) {
        await txn.insert('receta_insumos', {
          'producto_id': productoId,
          'insumo_id': linea.insumoId,
          'cantidad': linea.cantidad,
        });
      }
    });
  }

  Future<void> saveRecetaCantidades(
    int productoId,
    Map<int, double> cantidades,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'receta_insumos',
        where: 'producto_id = ?',
        whereArgs: [productoId],
      );
      for (final entry in cantidades.entries) {
        if (entry.value <= 0) continue;
        await txn.insert('receta_insumos', {
          'producto_id': productoId,
          'insumo_id': entry.key,
          'cantidad': entry.value,
        });
      }
    });
  }

  Future<List<Insumo>> getInsumos({bool soloActivos = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT i.*, u.abreviatura AS unidad_abreviatura,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      ${soloActivos ? 'WHERE i.activo = 1' : ''}
      ORDER BY i.activo DESC, i.nombre COLLATE NOCASE
    ''');
    return rows
        .map(
          (row) => Insumo(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            unidadId: row['unidad_id']! as int,
            unidadAbreviatura: row['unidad_abreviatura']! as String,
            modoControl: row['modo_control']! as String,
            disponible: (row['disponible'] as num).toInt() == 1,
            stockMinimo: (row['stock_minimo'] as num).toDouble(),
            costoPromedio: (row['costo_promedio'] as num).toDouble(),
            presentacionCompra: row['presentacion_compra'] as String?,
            factorCompra: (row['factor_compra'] as num?)?.toDouble() ?? 1,
            activo: (row['activo'] as num).toInt() == 1,
            stock: (row['stock'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<Insumo?> getInsumo(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT i.*, u.abreviatura AS unidad_abreviatura,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE i.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Insumo(
      id: row['id']! as int,
      nombre: row['nombre']! as String,
      unidadId: row['unidad_id']! as int,
      unidadAbreviatura: row['unidad_abreviatura']! as String,
      modoControl: row['modo_control']! as String,
      disponible: (row['disponible'] as num).toInt() == 1,
      stockMinimo: (row['stock_minimo'] as num).toDouble(),
      costoPromedio: (row['costo_promedio'] as num).toDouble(),
      presentacionCompra: row['presentacion_compra'] as String?,
      factorCompra: (row['factor_compra'] as num?)?.toDouble() ?? 1,
      activo: (row['activo'] as num).toInt() == 1,
      stock: (row['stock'] as num).toDouble(),
    );
  }

  Future<void> saveInsumo(Insumo insumo) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': insumo.nombre.trim(),
      'unidad_id': insumo.unidadId,
      'modo_control': insumo.modoControl,
      'disponible': insumo.disponible ? 1 : 0,
      'stock_minimo': insumo.stockMinimo,
      'costo_promedio': insumo.costoPromedio,
      'presentacion_compra': insumo.presentacionCompra?.trim().isEmpty == true
          ? null
          : insumo.presentacionCompra?.trim(),
      'factor_compra': insumo.factorCompra,
      'activo': insumo.activo ? 1 : 0,
    };
    if (insumo.id == null) {
      await db.insert('insumos', values);
    } else {
      await db.update(
        'insumos',
        values,
        where: 'id = ?',
        whereArgs: [insumo.id],
      );
    }
  }

  Future<void> setInsumoActivo(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'insumos',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setInsumoDisponible(int id, bool disponible) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'insumos',
      {'disponible': disponible ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> getStockInsumo(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'v_stock_insumos',
      columns: ['stock'],
      where: 'insumo_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['stock'] as num).toDouble();
  }

  Future<double> getStockProducto(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'v_stock_productos',
      columns: ['stock'],
      where: 'producto_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['stock'] as num).toDouble();
  }

  Future<String?> motivoNoDisponible(int productoId, double cantidad) async {
    final producto = await getProducto(productoId);
    if (producto == null || !producto.activo) return 'Producto inactivo';
    if (producto.esDirecto) {
      if (producto.stock < cantidad) {
        return 'Sin stock (quedan ${producto.stock.toStringAsFixed(0)})';
      }
      return null;
    }
    final receta = await getReceta(productoId);
    if (receta.isEmpty) return 'Sin receta configurada';
    for (final linea in receta) {
      if (linea.modoControl == 'DISPONIBILIDAD') {
        if (!linea.disponible) return 'Falta ${linea.insumoNombre}';
        continue;
      }
      if (linea.stock < linea.cantidad * cantidad) {
        return 'Falta ${linea.insumoNombre}';
      }
    }
    return null;
  }

  Future<List<Producto>> getProductosSiempreDisponibles() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.nombre AS categoria_nombre, c.color AS categoria_color,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      WHERE p.activo = 1 AND c.activo = 1 AND c.siempre_disponible = 1
      ORDER BY c.orden, p.nombre COLLATE NOCASE
    ''');
    return rows.map(_productFromRow).toList();
  }

  Producto _productFromRow(Map<String, Object?> row) => Producto(
    id: row['id']! as int,
    nombre: row['nombre']! as String,
    categoriaId: row['categoria_id']! as int,
    categoriaNombre: row['categoria_nombre']! as String,
    categoriaColor: row['categoria_color']! as int,
    descripcion: row['descripcion'] as String?,
    precio: (row['precio'] as num).toDouble(),
    imagen: row['imagen'] as Uint8List?,
    tipo: row['tipo']! as String,
    stockMinimo: (row['stock_minimo'] as num).toDouble(),
    costoUnitario: (row['costo_unitario'] as num).toDouble(),
    activo: (row['activo'] as num).toInt() == 1,
    stock: (row['stock'] as num?)?.toDouble() ?? 0,
  );
}
