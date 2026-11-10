class Permiso {
  static const tablero = 'TABLERO';
  static const ventas = 'VENTAS';
  static const caja = 'CAJA';
  static const menu = 'MENU';
  static const productos = 'PRODUCTOS';
  static const insumos = 'INSUMOS';
  static const usuarios = 'USUARIOS';
  static const reportes = 'REPORTES';
  static const agotamiento = 'AGOTAMIENTO';

  static const todos = <String>[
    tablero,
    ventas,
    caja,
    menu,
    productos,
    insumos,
    usuarios,
    reportes,
    agotamiento,
  ];

  static const etiquetas = <String, String>{
    tablero: 'Tablero',
    ventas: 'Ventas',
    caja: 'Caja',
    menu: 'Menú del día',
    productos: 'Productos',
    insumos: 'Insumos',
    usuarios: 'Usuarios',
    reportes: 'Reportes',
    agotamiento: 'Reportar agotamiento',
  };
}

/// Perfiles predefinidos de usuario. Solo el administrador es fijo.
class Perfil {
  static const admin = 'ADMIN';
  static const cajero = 'CAJERO';
  static const vendedor = 'VENDEDOR';

  static const todos = <String>[admin, cajero, vendedor];

  static const nombres = <String, String>{
    admin: 'Administrador',
    cajero: 'Cajero',
    vendedor: 'Vendedor',
  };

  static const vistasPorDefecto = <String, Set<String>>{
    admin: {...Permiso.todos},
    cajero: {Permiso.ventas, Permiso.caja, Permiso.agotamiento},
    vendedor: {Permiso.ventas, Permiso.agotamiento},
  };
}

class Usuario {
  Usuario({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.perfil,
    required this.activo,
    this.debeCambiarPassword = false,
    Set<String>? permisos,
  }) : permisos = permisos ?? <String>{};

  final int id;
  final String nombre;
  final String usuario;
  final String perfil;
  final bool activo;

  /// `true` cuando la cuenta todavía usa credenciales por defecto
  /// (`admin` / `1234`) y debe pasar por el primer acceso obligatorio.
  final bool debeCambiarPassword;

  final Set<String> permisos;

  bool get esAdmin => perfil == Perfil.admin;

  Usuario copyWith({
    String? nombre,
    String? usuario,
    String? perfil,
    bool? activo,
    bool? debeCambiarPassword,
    Set<String>? permisos,
  }) {
    return Usuario(
      id: id,
      nombre: nombre ?? this.nombre,
      usuario: usuario ?? this.usuario,
      perfil: perfil ?? this.perfil,
      activo: activo ?? this.activo,
      debeCambiarPassword:
          debeCambiarPassword ?? this.debeCambiarPassword,
      permisos: permisos ?? this.permisos,
    );
  }

  String get nombrePerfil => Perfil.nombres[perfil] ?? perfil;

  bool puede(String permiso) => esAdmin || permisos.contains(permiso);

  String get inicial => nombre.trim().isEmpty
      ? '?'
      : nombre.trim().substring(0, 1).toUpperCase();
}

class Sesion {
  Sesion._();

  static final Sesion instance = Sesion._();

  Usuario? usuario;

  bool get autenticado => usuario != null;

  bool puede(String permiso) => usuario?.puede(permiso) ?? false;

  void iniciar(Usuario value) => usuario = value;

  void cerrar() => usuario = null;
}
