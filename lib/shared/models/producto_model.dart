class Producto {
  final int id;
  final int categoriaId;
  final String nombre;
  final String? descripcion;
  final double precio;
  final String? imagenUrl;
  final bool activo;
  final bool esImprimible;
  // NUEVOS CAMPOS
  final String tipoCarta; // 'MENU', 'RESTOBAR', 'AMBOS'
  final String subtipo;   // 'ENTRADA', 'SEGUNDO', 'CARTA'

  Producto({
    required this.id,
    required this.categoriaId,
    required this.nombre,
    this.descripcion,
    required this.precio,
    this.imagenUrl,
    required this.activo,
    required this.esImprimible,
    this.tipoCarta = 'AMBOS',
    this.subtipo = 'CARTA',
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'],
      categoriaId: json['categoria_id'],
      nombre: json['nombre'],
      descripcion: json['descripcion'],
      precio: (json['precio'] as num).toDouble(),
      imagenUrl: json['imagen_url'],
      activo: json['activo'] ?? true,
      esImprimible: json['es_imprimible'] ?? true,
      // MAPEO SEGURO
      tipoCarta: json['tipo_carta'] ?? 'AMBOS',
      subtipo: json['subtipo'] ?? 'CARTA',
    );
  }
  
  // Agrega métodos copyWith o toMap si los usas en el repositorio
}