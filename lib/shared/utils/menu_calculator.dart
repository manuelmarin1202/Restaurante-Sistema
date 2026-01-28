class MenuCalculator {
  // CONSTANTES DE PRECIOS (sincronizadas con carrito_provider.dart y pedidos_repository.dart)
  static const double precioPromoSegundoSolo = 10.00;
  static const double precioEntradaExtra = 5.00;

  /// Calcula el total de un pedido aplicando la lógica de menús.
  /// Esta función se usa para recalcular totales desde la BD.
  static double calcularTotal(List<dynamic> detalles) {
    double totalGeneral = 0;
    List<Map<String, dynamic>> bolsaEntradas = [];
    List<Map<String, dynamic>> bolsaSegundos = [];
    List<Map<String, dynamic>> bolsaCortesias = [];

    for (var d in detalles) {
      final prod = d['productos'];
      final subtipo = prod != null ? (prod['subtipo'] ?? 'CARTA') : 'CARTA';
      final precio = (d['precio_unitario'] as num).toDouble();
      final cantidad = d['cantidad'] as int;
      final notas = d['notas']?.toString() ?? '';

      // Expandir por cantidad
      for (int i = 0; i < cantidad; i++) {
        final itemMap = {'precio': precio, 'precio_producto': (prod?['precio'] ?? precio) as num};

        // Detectar cortesías
        final esCortesia = precio == 0.00 || notas.toUpperCase().contains('CORTESÍA');

        if (esCortesia) {
          bolsaCortesias.add(itemMap);
        } else if (subtipo == 'ENTRADA') {
          bolsaEntradas.add(itemMap);
        } else if (subtipo == 'SEGUNDO') {
          bolsaSegundos.add(itemMap);
        } else {
          totalGeneral += precio;
        }
      }
    }

    // Calcular menús completos (solo con items NO cortesía)
    int nMenus = (bolsaEntradas.length < bolsaSegundos.length)
        ? bolsaEntradas.length
        : bolsaSegundos.length;

    // Ordenar segundos por ID para consistencia (usamos precio como proxy)
    bolsaSegundos.sort((a, b) => (a['precio'] as num).compareTo(b['precio'] as num));

    // Ordenar entradas por precio descendente
    bolsaEntradas.sort((a, b) => (b['precio_producto'] as num).compareTo(a['precio_producto'] as num));

    // Sumar Segundos
    for (int i = 0; i < bolsaSegundos.length; i++) {
      if (i < nMenus) {
        // ES PARTE DE MENÚ: Usar precio guardado (ya viene correcto de BD)
        totalGeneral += bolsaSegundos[i]['precio'] as double;
      } else {
        // ES SEGUNDO SOLO: Precio promo
        totalGeneral += precioPromoSegundoSolo;
      }
    }

    // Sumar Entradas
    for (int i = 0; i < bolsaEntradas.length; i++) {
      if (i < nMenus) {
        // DENTRO DE MENÚ: Gratis (ya viene como 0 en BD)
        // No sumamos nada extra
      } else {
        // ENTRADA EXTRA
        double precioReal = (bolsaEntradas[i]['precio_producto'] as num).toDouble();
        if (precioReal <= 0) {
          totalGeneral += precioEntradaExtra;
        } else {
          totalGeneral += precioReal;
        }
      }
    }

    // Las cortesías no suman nada

    return totalGeneral;
  }
}