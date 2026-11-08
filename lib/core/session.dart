class Permiso {
  static const ventas = 'VENTAS';
  static const caja = 'CAJA';
  static const menu = 'MENU';
  static const productos = 'PRODUCTOS';
  static const categorias = 'CATEGORIAS';
  static const insumos = 'INSUMOS';
  static const compras = 'COMPRAS';
  static const conteo = 'CONTEO';
  static const gastos = 'GASTOS';
  static const sueldos = 'SUELDOS';
  static const usuarios = 'USUARIOS';
  static const reportes = 'REPORTES';
  static const agotamiento = 'AGOTAMIENTO';

  static const todos = <String>[
    ventas,
    caja,
    menu,
    productos,
    categorias,
    insumos,
    compras,
    conteo,
    gastos,
    sueldos,
    usuarios,
    reportes,
    agotamiento,
  ];

  static const etiquetas = <String, String>{
    ventas: 'Registrar ventas',
    caja: 'Abrir y cerrar su caja',
    menu: 'Administrar menú del día',
    productos: 'Administrar productos y recetas',
    categorias: 'Administrar categorías',
    insumos: 'Administrar insumos',
    compras: 'Registrar compras',
    conteo: 'Conteo de inventario',
    gastos: 'Registrar gastos',
    sueldos: 'Registrar sueldos',
    usuarios: 'Administrar usuarios y permisos',
    reportes: 'Ver reportes',
    agotamiento: 'Reportar agotamiento',
  };
}

class Usuario {
  Usuario({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.rol,
    required this.turnoAsignado,
    required this.sueldoBase,
    required this.activo,
    Set<String>? permisos,
  }) : permisos = permisos ?? <String>{};

  final int id;
  final String nombre;
  final String usuario;
  final String rol;
  final String? turnoAsignado;
  final double sueldoBase;
  final bool activo;
  final Set<String> permisos;

  bool get esAdmin => rol == 'ADMIN';

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
