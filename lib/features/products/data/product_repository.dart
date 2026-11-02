import 'dart:typed_data';

import '../../../data/database/app_database.dart';

class Product {
  const Product({
    this.id,
    required this.code,
    required this.name,
    this.description,
    required this.salePrice,
    this.photo,
    required this.active,
    this.recipeId,
  });

  final int? id;
  final String code;
  final String name;
  final String? description;
  final double salePrice;
  final Uint8List? photo;
  final bool active;
  final int? recipeId;

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id_producto'] as int?,
    code: map['codigo'] as String,
    name: map['nombre'] as String,
    description: map['descripcion'] as String?,
    salePrice: (map['precio_venta'] as num).toDouble(),
    photo: map['foto'] as Uint8List?,
    active: (map['estado'] as int) == 1,
    recipeId: map['id_receta'] as int?,
  );

  Map<String, Object?> toMap() => {
    'codigo': code,
    'nombre': name,
    'descripcion': description,
    'precio_venta': salePrice,
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
  Future<List<Product>> getProducts() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, r.id_receta
      FROM productos p
      LEFT JOIN recetas r ON r.id_producto = p.id_producto AND r.estado = 1
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
}
