class Categoria {
  final int id;
  final String nombre;
  final int orden;
  final bool activo;
  final String tipoCarta; // <--- NUEVO CAMPO

  Categoria({
    required this.id,
    required this.nombre,
    required this.orden,
    required this.activo,
    this.tipoCarta = 'AMBOS', // Valor por defecto para evitar errores
  });

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      id: json['id'],
      nombre: json['nombre'],
      orden: json['orden'],
      activo: json['activo'] ?? true,
      tipoCarta: json['tipo_carta'] ?? 'AMBOS', // <--- Mapeamos el campo SQL
    );
  }
}