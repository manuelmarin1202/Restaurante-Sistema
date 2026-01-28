// Modelo para Promociones
class Promocion {
  final int id;
  final String nombre;
  final String? descripcion;
  final TipoPromocion tipoPromocion;
  final bool activo;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final List<String>? diasAplicables; // ["lunes", "martes", ...]
  final String? horaInicio; // "18:00"
  final String? horaFin; // "23:59"
  final double? precioCombo; // Para combos tipo "2x25"
  final int? cantidadItems; // Cantidad de items en el combo
  final String? tipoCarta; // 'MENU', 'RESTOBAR', 'AMBOS'

  // Relaciones cargadas
  final List<PromocionProducto>? productos;
  final List<PromocionAdicional>? adicionales;

  Promocion({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.tipoPromocion,
    required this.activo,
    this.fechaInicio,
    this.fechaFin,
    this.diasAplicables,
    this.horaInicio,
    this.horaFin,
    this.precioCombo,
    this.cantidadItems,
    this.tipoCarta,
    this.productos,
    this.adicionales,
  });

  factory Promocion.fromJson(Map<String, dynamic> json) {
    return Promocion(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      tipoPromocion: TipoPromocion.fromString(json['tipo_promocion'] as String),
      activo: json['activo'] as bool? ?? true,
      fechaInicio: json['fecha_inicio'] != null
          ? DateTime.parse(json['fecha_inicio'])
          : null,
      fechaFin: json['fecha_fin'] != null ? DateTime.parse(json['fecha_fin']) : null,
      diasAplicables: json['dias_aplicables'] != null
          ? List<String>.from(json['dias_aplicables'] as List)
          : null,
      horaInicio: json['hora_inicio'] as String?,
      horaFin: json['hora_fin'] as String?,
      precioCombo: json['precio_combo'] != null
          ? (json['precio_combo'] as num).toDouble()
          : null,
      cantidadItems: json['cantidad_items'] as int?,
      tipoCarta: json['tipo_carta'] as String?,
      productos: json['promocion_productos'] != null
          ? (json['promocion_productos'] as List)
              .map((p) => PromocionProducto.fromJson(p))
              .toList()
          : null,
      adicionales: json['promocion_adicionales'] != null
          ? (json['promocion_adicionales'] as List)
              .map((a) => PromocionAdicional.fromJson(a))
              .toList()
          : null,
    );
  }

  // Verifica si la promoción está activa en este momento
  bool estaActivaAhora() {
    final ahora = DateTime.now();

    // Verificar fechas
    if (fechaInicio != null && ahora.isBefore(fechaInicio!)) return false;
    if (fechaFin != null && ahora.isAfter(fechaFin!)) return false;

    // Verificar día de la semana
    if (diasAplicables != null && diasAplicables!.isNotEmpty) {
      final diaActual = _obtenerNombreDia(ahora.weekday);
      if (!diasAplicables!.contains(diaActual)) return false;
    }

    // Verificar horario
    if (horaInicio != null || horaFin != null) {
      final horaActual = TimeOfDay.fromDateTime(ahora);
      if (horaInicio != null) {
        final inicio = _parseHora(horaInicio!);
        if (_compararHoras(horaActual, inicio) < 0) return false;
      }
      if (horaFin != null) {
        final fin = _parseHora(horaFin!);
        if (_compararHoras(horaActual, fin) > 0) return false;
      }
    }

    return activo;
  }

  String _obtenerNombreDia(int weekday) {
    const dias = [
      'lunes',
      'martes',
      'miercoles',
      'jueves',
      'viernes',
      'sabado',
      'domingo'
    ];
    return dias[weekday - 1];
  }

  TimeOfDay _parseHora(String hora) {
    final partes = hora.split(':');
    return TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
  }

  int _compararHoras(TimeOfDay a, TimeOfDay b) {
    if (a.hour != b.hour) return a.hour - b.hour;
    return a.minute - b.minute;
  }
}

// Enum para tipos de promoción
enum TipoPromocion {
  precioSimple, // Solo cambia el precio del producto
  comboProducto, // Producto principal + adicionales obligatorios
  comboMultiple; // Varios productos a elegir por un precio fijo

  static TipoPromocion fromString(String tipo) {
    switch (tipo) {
      case 'precio_simple':
        return TipoPromocion.precioSimple;
      case 'combo_producto':
        return TipoPromocion.comboProducto;
      case 'combo_multiple':
        return TipoPromocion.comboMultiple;
      default:
        return TipoPromocion.precioSimple;
    }
  }

  String toDbString() {
    switch (this) {
      case TipoPromocion.precioSimple:
        return 'precio_simple';
      case TipoPromocion.comboProducto:
        return 'combo_producto';
      case TipoPromocion.comboMultiple:
        return 'combo_multiple';
    }
  }
}

// Modelo para productos en promoción
class PromocionProducto {
  final int id;
  final int promocionId;
  final int productoId;
  final double? precioPromocional;
  final bool esPrincipal;
  final bool esAdicionalObligatorio;
  final int cantidadAdicional;

  // Relación con producto (opcional, si se carga con join)
  final Map<String, dynamic>? producto;

  PromocionProducto({
    required this.id,
    required this.promocionId,
    required this.productoId,
    this.precioPromocional,
    required this.esPrincipal,
    required this.esAdicionalObligatorio,
    required this.cantidadAdicional,
    this.producto,
  });

  factory PromocionProducto.fromJson(Map<String, dynamic> json) {
    return PromocionProducto(
      id: json['id'] as int,
      promocionId: json['promocion_id'] as int,
      productoId: json['producto_id'] as int,
      precioPromocional: json['precio_promocional'] != null
          ? (json['precio_promocional'] as num).toDouble()
          : null,
      esPrincipal: json['es_producto_principal'] as bool? ?? true,
      esAdicionalObligatorio: json['es_adicional_obligatorio'] as bool? ?? false,
      cantidadAdicional: json['cantidad_adicional'] as int? ?? 0,
      producto: json['productos'] as Map<String, dynamic>?,
    );
  }
}

// Modelo para adicionales de promoción
class PromocionAdicional {
  final int id;
  final int promocionId;
  final int productoId;
  final int cantidad;
  final bool esObligatorio;
  final bool esSeleccionable;
  final String? grupoSeleccion; // Para agrupar opciones (ej: "gaseosa_vidrio")

  // Relación con producto
  final Map<String, dynamic>? producto;

  PromocionAdicional({
    required this.id,
    required this.promocionId,
    required this.productoId,
    required this.cantidad,
    required this.esObligatorio,
    required this.esSeleccionable,
    this.grupoSeleccion,
    this.producto,
  });

  factory PromocionAdicional.fromJson(Map<String, dynamic> json) {
    return PromocionAdicional(
      id: json['id'] as int,
      promocionId: json['promocion_id'] as int,
      productoId: json['producto_id'] as int,
      cantidad: json['cantidad'] as int? ?? 1,
      esObligatorio: json['es_obligatorio'] as bool? ?? true,
      esSeleccionable: json['es_seleccionable'] as bool? ?? false,
      grupoSeleccion: json['grupo_seleccion'] as String?,
      producto: json['productos'] as Map<String, dynamic>?,
    );
  }
}

// Modelo para registro de promoción aplicada en un pedido
class PedidoPromocion {
  final int id;
  final int pedidoId;
  final int promocionId;
  final List<Map<String, dynamic>> productosIncluidos;
  final double precioOriginal;
  final double precioAplicado;
  final double descuento;

  PedidoPromocion({
    required this.id,
    required this.pedidoId,
    required this.promocionId,
    required this.productosIncluidos,
    required this.precioOriginal,
    required this.precioAplicado,
    required this.descuento,
  });

  factory PedidoPromocion.fromJson(Map<String, dynamic> json) {
    return PedidoPromocion(
      id: json['id'] as int,
      pedidoId: json['pedido_id'] as int,
      promocionId: json['promocion_id'] as int,
      productosIncluidos: List<Map<String, dynamic>>.from(
          json['productos_incluidos'] as List),
      precioOriginal: (json['precio_original'] as num).toDouble(),
      precioAplicado: (json['precio_aplicado'] as num).toDouble(),
      descuento: (json['descuento'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pedido_id': pedidoId,
      'promocion_id': promocionId,
      'productos_incluidos': productosIncluidos,
      'precio_original': precioOriginal,
      'precio_aplicado': precioAplicado,
      'descuento': descuento,
    };
  }
}

// Clase auxiliar para TimeOfDay (no existe en dart:core puro)
class TimeOfDay {
  final int hour;
  final int minute;

  TimeOfDay({required this.hour, required this.minute});

  factory TimeOfDay.fromDateTime(DateTime dt) {
    return TimeOfDay(hour: dt.hour, minute: dt.minute);
  }
}
