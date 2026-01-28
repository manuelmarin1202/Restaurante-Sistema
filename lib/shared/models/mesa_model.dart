class Mesa {
  final int id;
  final String numero;
  final int zonaId;
  final String estado;
  
  final String? nombreZona;
  
  // DATOS NUEVOS (Opcionales, solo si está ocupada)
  final String? clienteActivo;
  final DateTime? horaRecojo;

  Mesa({
    required this.id,
    required this.numero,
    required this.zonaId,
    required this.estado,
    
    this.nombreZona,
    this.clienteActivo,
    this.horaRecojo,
  });

  factory Mesa.fromJson(Map<String, dynamic> json) {
    // Buscar si hay un pedido pendiente adjunto
    String? cliente;
    DateTime? recojo;

    if (json['pedidos'] != null && (json['pedidos'] as List).isNotEmpty) {
      // Supabase puede devolver una lista, tomamos el primero (el activo)
      final pedidoActivo = (json['pedidos'] as List).first;
      // El campo correcto en la BD es 'nombre_cliente'
      cliente = pedidoActivo['nombre_cliente'];
      if (pedidoActivo['hora_recojo'] != null) {
        recojo = DateTime.parse(pedidoActivo['hora_recojo']).toLocal();
      }
    }

    return Mesa(
      id: json['id'],
      numero: json['numero'],
      zonaId: json['zona_id'],
      estado: json['estado'],

      nombreZona: json['zonas']?['nombre'],
      clienteActivo: cliente,
      horaRecojo: recojo,
    );
  }
}