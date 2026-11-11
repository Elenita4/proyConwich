import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';
import 'password_utils.dart';
import 'session.dart';

export 'password_utils.dart' show hashPassword;

class AuthRepository {
  bool? _tieneColumnaPerfil;

  Future<bool> _soportaPerfil(Database db) async {
    final cache = _tieneColumnaPerfil;
    if (cache != null) return cache;
    var soporta = false;
    try {
      final columnas = await db.rawQuery('PRAGMA table_info(usuarios)');
      soporta = columnas.any((c) => c['name'] == 'perfil');
    } catch (_) {
      soporta = false;
    }
    _tieneColumnaPerfil = soporta;
    return soporta;
  }

  Future<bool> hayUsuarios() async {
    final db = await AppDatabase.instance.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM usuarios'),
    );
    return (count ?? 0) > 0;
  }

  Future<bool> usaCredencialesPorDefecto() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      columns: ['password_hash'],
      where: 'usuario = ?',
      whereArgs: ['admin'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['password_hash'] == hashPassword('1234');
  }

  /// Comprueba si el nombre de usuario está libre, sin distinguir mayúsculas.
  Future<bool> usuarioDisponible(String usuario, {int? exceptoId}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      columns: ['id'],
      where: exceptoId == null
          ? 'LOWER(usuario) = LOWER(?)'
          : 'LOWER(usuario) = LOWER(?) AND id <> ?',
      whereArgs: exceptoId == null
          ? [usuario.trim()]
          : [usuario.trim(), exceptoId],
      limit: 1,
    );
    return rows.isEmpty;
  }

  /// Guarda el usuario y la contraseña definitivos del primer acceso y
  /// desactiva la obligación de cambiarlos.
  Future<void> actualizarCredenciales({
    required int usuarioId,
    required String usuario,
    required String password,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'usuarios',
        {
          'usuario': usuario.trim(),
          'password_hash': hashPassword(password),
          'debe_cambiar_password': 0,
        },
        where: 'id = ?',
        whereArgs: [usuarioId],
      );
    });
  }

  Future<Usuario?> login(String usuario, String password) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      where: 'LOWER(usuario) = LOWER(?) AND activo = 1',
      whereArgs: [usuario.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['password_hash'] != hashPassword(password)) return null;
    final permisos = await getPermisos(row['id']! as int);
    return _fromRow(row, permisos);
  }

  /// Busca un administrador activo cuya contraseña coincida. Se usa para
  /// "Ver como administrador" desde cualquier otro usuario.
  Future<Usuario?> loginAdminPorPassword(String password) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('usuarios', where: 'activo = 1', orderBy: 'id');
    final hash = hashPassword(password);
    for (final row in rows) {
      final esAdmin = row['rol'] == 'ADMIN' || row['perfil'] == Perfil.admin;
      if (!esAdmin) continue;
      if (row['password_hash'] != hash) continue;
      final permisos = await getPermisos(row['id']! as int);
      return _fromRow(row, permisos);
    }
    return null;
  }

  Future<Usuario?> restaurarSesion() async {
    final db = await AppDatabase.instance.database;
    final sesiones = await db.query('sesion_actual', limit: 1);
    if (sesiones.isEmpty) return null;
    final usuarioId = sesiones.first['usuario_id']! as int;
    final rows = await db.query(
      'usuarios',
      where: 'id = ? AND activo = 1',
      whereArgs: [usuarioId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await cerrarSesion();
      return null;
    }
    final permisos = await getPermisos(usuarioId);
    return _fromRow(rows.first, permisos);
  }

  Future<void> guardarSesion(int usuarioId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('sesion_actual');
      await txn.insert('sesion_actual', {
        'id': 1,
        'usuario_id': usuarioId,
        'iniciada_en': sqlNow(),
      });
    });
  }

  Future<void> cerrarSesion() async {
    final db = await AppDatabase.instance.database;
    await db.delete('sesion_actual');
  }

  Future<bool> verificarPassword(int usuarioId, String password) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'usuarios',
      columns: ['password_hash'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return rows.first['password_hash'] == hashPassword(password);
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
      byUser
          .putIfAbsent(userId, () => <String>{})
          .add(row['permiso']! as String);
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
    required String perfil,
    required bool activo,
    required Set<String> permisos,
    String? password,
  }) async {
    final db = await AppDatabase.instance.database;
    final esAdmin = perfil == Perfil.admin;
    final values = <String, Object?>{
      'nombre': nombre.trim(),
      'usuario': usuario.trim(),
      'rol': esAdmin ? 'ADMIN' : 'CAJERO',
      'activo': activo ? 1 : 0,
    };
    if (await _soportaPerfil(db)) values['perfil'] = perfil;
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
    final finales = esAdmin ? Permiso.todos.toSet() : permisos;
    for (final permiso in finales) {
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
      {'password_hash': hashPassword(password), 'debe_cambiar_password': 0},
      where: 'id = ?',
      whereArgs: [usuarioId],
    );
  }

  Usuario _fromRow(Map<String, Object?> row, Set<String> permisos) => Usuario(
    id: row['id']! as int,
    nombre: row['nombre']! as String,
    usuario: row['usuario']! as String,
    perfil: ((row['perfil'] as String?)?.isNotEmpty ?? false)
        ? row['perfil']! as String
        : (row['rol'] == 'ADMIN' ? Perfil.admin : Perfil.cajero),
    activo: (row['activo'] as num? ?? 1).toInt() == 1,
    debeCambiarPassword:
        (row['debe_cambiar_password'] as num? ?? 0).toInt() == 1,
    permisos: permisos,
  );
}
