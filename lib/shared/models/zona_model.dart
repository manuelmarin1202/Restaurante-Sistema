class Zona {
  final int id;
  final String nombre;
  final String tipo; // 'fisica' o 'virtual'
  final bool activo;

  Zona({required this.id, required this.nombre, required this.tipo, required this.activo});

  factory Zona.fromJson(Map<String, dynamic> json) {
    return Zona(
      id: json['id'],
      nombre: json['nombre'],
      tipo: json['tipo'] ?? 'fisica',
      activo: json['activo'] ?? true,
    );
  }
}