import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';
import 'session.dart';

String hashPassword(String password) =>
    sha256.convert(utf8.encode(password)).toString();

class AuthRepository {
  Future<bool> hayUsuarios() async {
    final db = await AppDatabase.instance.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM usuarios'),
    );
    return (count ?? 0) > 0;
  }

  Future<Usuario> crearAdminInicial({
    required String nombre,
    required String usuario,
    required String password,
  }) async {
    final db = await AppDatabase.instance.database;
    final id = await db.insert('usuarios', {
      'nombre': nombre.trim(),
      'usuario': usuario.trim(),
      'password_hash': hashPassword(password),
      'rol': 'ADMIN',
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
    return Usuario(
      id: id,
      nombre: nombre.trim(),
      usuario: usuario.trim(),
      rol: 'ADMIN',
      turnoAsignado: 'AMBOS',
      sueldoBase: 0,
      activo: true,
      permisos: Permiso.todos.toSet(),
    );
  }

  Future<Usuario?> login(String usuario, String password) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      where: 'usuario = ? AND activo = 1',
      whereArgs: [usuario.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['password_hash'] != hashPassword(password)) return null;
    final permisos = await getPermisos(row['id']! as int);
    return _fromRow(row, permisos);
  }

  Future<List<Usuario>> getUsuarios() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      orderBy: 'activo DESC, nombre COLLATE NOCASE',
    );
    final permissionRows = await db.query('usuario_permisos');
    final byUser = <int, Set<String>>{};
    for (final row in permissionRows) {
      final userId = row['usuario_id']! as int;
      byUser.putIfAbsent(userId, () => <String>{}).add(
        row['permiso']! as String,
      );
    }
    return rows
        .map((row) => _fromRow(row, byUser[row['id']] ?? <String>{}))
        .toList();
  }

  Future<Set<String>> getPermisos(int usuarioId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuario_permisos',
      columns: ['permiso'],
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
    return rows.map((row) => row['permiso']! as String).toSet();
  }

  Future<void> saveUsuario({
    int? id,
    required String nombre,
    required String usuario,
    required String rol,
    String? turnoAsignado,
    required double sueldoBase,
    required bool activo,
    required Set<String> permisos,
    String? password,
  }) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': nombre.trim(),
      'usuario': usuario.trim(),
      'rol': rol,
      'turno_asignado': turnoAsignado,
      'sueldo_base': sueldoBase,
      'activo': activo ? 1 : 0,
    };
    late int userId;
    if (id == null) {
      if (password == null || password.isEmpty) {
        throw StateError('La contraseña es obligatoria.');
      }
      values['password_hash'] = hashPassword(password);
      values['creado_en'] = sqlNow();
      userId = await db.insert('usuarios', values);
    } else {
      if (password != null && password.isNotEmpty) {
        values['password_hash'] = hashPassword(password);
      }
      await db.update('usuarios', values, where: 'id = ?', whereArgs: [id]);
      userId = id;
    }
    await db.delete(
      'usuario_permisos',
      where: 'usuario_id = ?',
      whereArgs: [userId],
    );
    for (final permiso in permisos) {
      await db.insert('usuario_permisos', {
        'usuario_id': userId,
        'permiso': permiso,
      });
    }
  }

  Future<void> setActivo(int usuarioId, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'usuarios',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [usuarioId],
    );
  }

  Future<void> cambiarPassword(int usuarioId, String password) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'usuarios',
      {'password_hash': hashPassword(password)},
      where: 'id = ?',
      whereArgs: [usuarioId],
    );
  }

  Usuario _fromRow(Map<String, Object?> row, Set<String> permisos) => Usuario(
    id: row['id']! as int,
    nombre: row['nombre']! as String,
    usuario: row['usuario']! as String,
    rol: row['rol']! as String,
    turnoAsignado: row['turno_asignado'] as String?,
    sueldoBase: (row['sueldo_base'] as num?)?.toDouble() ?? 0,
    activo: (row['activo'] as num? ?? 1).toInt() == 1,
    permisos: permisos,
  );
}
