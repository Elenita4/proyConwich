import 'dart:typed_data';

import '../../../data/database/app_database.dart';

class Product {
  const Product({
    this.id,
    required this.code,
    required this.name,
    this.description,
    required this.salePrice,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    this.photo,
    required this.active,
    this.recipeId,
  });

  final int? id;
  final String code;
  final String name;
  final String? description;
  final double salePrice;
  final int categoryId;
  final String categoryName;
  final int categoryColor;
  final Uint8List? photo;
  final bool active;
  final int? recipeId;

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id_producto'] as int?,
    code: map['codigo'] as String,
    name: map['nombre'] as String,
    description: map['descripcion'] as String?,
    salePrice: (map['precio_venta'] as num).toDouble(),
    categoryId: map['id_categoria_producto'] as int? ?? 0,
    categoryName: map['categoria_nombre'] as String? ?? 'Sin categoría',
    categoryColor: map['categoria_color'] as int? ?? 4280391418,
    photo: map['foto'] as Uint8List?,
    active: (map['estado'] as int) == 1,
    recipeId: map['id_receta'] as int?,
  );

  Map<String, Object?> toMap() => {
    'codigo': code,
    'nombre': name,
    'descripcion': description,
    'precio_venta': salePrice,
    'id_categoria_producto': categoryId == 0 ? null : categoryId,
    'foto': photo,
    'estado': active ? 1 : 0,
  };
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientId,
    required this.ingredientName,
    required this.unitAbbreviation,
    required this.quantity,
  });

  final int ingredientId;
  final String ingredientName;
  final String unitAbbreviation;
  final double quantity;
}

class ProductRepository {
  Future<List<ProductCategory>> getCategories() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categorias_producto',
      where: 'estado = 1',
      orderBy: 'nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => ProductCategory(
            id: row['id_categoria_producto'] as int,
            name: row['nombre'] as String,
            color: row['color'] as int,
          ),
        )
        .toList();
  }

  Future<List<Product>> getProducts() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, r.id_receta, c.nombre AS categoria_nombre,
             c.color AS categoria_color
      FROM productos p
      LEFT JOIN recetas r ON r.id_producto = p.id_producto AND r.estado = 1
      LEFT JOIN categorias_producto c
        ON c.id_categoria_producto = p.id_categoria_producto
      WHERE p.estado = 1
      ORDER BY p.nombre COLLATE NOCASE
    ''');
    return rows.map(Product.fromMap).toList();
  }

  Future<void> saveProduct(Product product) async {
    final db = await AppDatabase.instance.database;
    await db.insert('productos', product.toMap());
  }

  Future<List<RecipeIngredient>> getRecipe(int productId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT d.id_insumo, i.nombre AS insumo_nombre,
             u.abreviatura AS unidad_abreviatura, d.cantidad
      FROM receta_detalle d
      INNER JOIN recetas r ON r.id_receta = d.id_receta
      INNER JOIN insumos i ON i.id_insumo = d.id_insumo
      INNER JOIN unidades_medida u ON u.id_unidad = i.id_unidad
      WHERE r.id_producto = ? AND r.estado = 1
      ORDER BY i.nombre COLLATE NOCASE
    ''',
      [productId],
    );
    return rows
        .map(
          (row) => RecipeIngredient(
            ingredientId: row['id_insumo'] as int,
            ingredientName: row['insumo_nombre'] as String,
            unitAbbreviation: row['unidad_abreviatura'] as String,
            quantity: (row['cantidad'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<void> saveRecipe({
    required int productId,
    required String name,
    required String instructions,
    required List<RecipeIngredient> ingredients,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final oldRecipes = await transaction.query(
        'recetas',
        columns: ['id_receta'],
        where: 'id_producto = ?',
        whereArgs: [productId],
      );
      for (final recipe in oldRecipes) {
        await transaction.delete(
          'receta_detalle',
          where: 'id_receta = ?',
          whereArgs: [recipe['id_receta']],
        );
      }
      await transaction.delete(
        'recetas',
        where: 'id_producto = ?',
        whereArgs: [productId],
      );
      final recipeId = await transaction.insert('recetas', {
        'id_producto': productId,
        'nombre': name,
        'instrucciones': instructions.isEmpty ? null : instructions,
      });
      for (final ingredient in ingredients) {
        await transaction.insert('receta_detalle', {
          'id_receta': recipeId,
          'id_insumo': ingredient.ingredientId,
          'cantidad': ingredient.quantity,
        });
      }
    });
  }

  Future<void> completeSale(List<CartLine> lines) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final total = lines.fold<double>(
        0,
        (sum, line) => sum + line.product.salePrice * line.quantity,
      );
      final saleId = await transaction.insert('ventas', {
        'total': total,
        'estado': 'REALIZADA',
      });
      for (final line in lines) {
        final recipeRows = await transaction.rawQuery(
          'SELECT id_receta FROM recetas WHERE id_producto = ? AND estado = 1',
          [line.product.id],
        );
        if (recipeRows.isEmpty) continue;
        final ingredients = await transaction.query(
          'receta_detalle',
          where: 'id_receta = ?',
          whereArgs: [recipeRows.first['id_receta']],
        );
        for (final ingredient in ingredients) {
          final amount =
              (ingredient['cantidad'] as num).toDouble() * line.quantity;
          final stockRows = await transaction.query(
            'insumos',
            columns: ['stock_actual'],
            where: 'id_insumo = ?',
            whereArgs: [ingredient['id_insumo']],
          );
          if (stockRows.isEmpty ||
              (stockRows.first['stock_actual'] as num).toDouble() < amount) {
            throw StateError(
              'No hay existencias suficientes para completar la venta.',
            );
          }
          await transaction.rawUpdate(
            'UPDATE insumos SET stock_actual = stock_actual - ? '
            'WHERE id_insumo = ?',
            [amount, ingredient['id_insumo']],
          );
          await transaction.insert('movimientos_inventario', {
            'id_insumo': ingredient['id_insumo'],
            'tipo': 'SALIDA',
            'origen': 'Venta',
            'cantidad': amount,
            'id_referencia': saleId,
          });
        }
        await transaction.insert('venta_detalle', {
          'id_venta': saleId,
          'id_producto': line.product.id,
          'cantidad': line.quantity,
          'precio_unitario': line.product.salePrice,
          'subtotal': line.product.salePrice * line.quantity,
        });
      }
    });
  }
}

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.color,
  });
  final int id;
  final String name;
  final int color;
}

class CartLine {
  CartLine({required this.product, this.quantity = 1});
  final Product product;
  int quantity;
}
