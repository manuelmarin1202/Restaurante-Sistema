import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/producto_model.dart';
import '../../../../shared/models/promocion_model.dart';

class CartItem {
  final Producto producto;
  int cantidad;
  String? notas;

  // Datos de promoción si aplica
  final int? promocionId;
  final double? precioPromocional; // Precio específico de la promoción
  final List<Producto>? productosAdicionales; // Productos incluidos gratis (gaseosas, jarras)
  final bool esParteDeCombo; // Si es parte de un combo múltiple (2x25)
  final String? grupoCombo; // ID único del combo para agrupar items relacionados

  CartItem({
    required this.producto,
    this.cantidad = 1,
    this.notas,
    this.promocionId,
    this.precioPromocional,
    this.productosAdicionales,
    this.esParteDeCombo = false,
    this.grupoCombo,
  });

  CartItem copyWith({
    int? cantidad,
    String? notas,
    int? promocionId,
    double? precioPromocional,
    List<Producto>? productosAdicionales,
    bool? esParteDeCombo,
    String? grupoCombo,
  }) {
    return CartItem(
      producto: producto,
      cantidad: cantidad ?? this.cantidad,
      notas: notas ?? this.notas,
      promocionId: promocionId ?? this.promocionId,
      precioPromocional: precioPromocional ?? this.precioPromocional,
      productosAdicionales: productosAdicionales ?? this.productosAdicionales,
      esParteDeCombo: esParteDeCombo ?? this.esParteDeCombo,
      grupoCombo: grupoCombo ?? this.grupoCombo,
    );
  }

  // Precio efectivo considerando promoción
  double get precioEfectivo => precioPromocional ?? producto.precio;

  // Indica si tiene promoción activa
  bool get tienePromocion => promocionId != null;
}

class CarritoNotifier extends StateNotifier<List<CartItem>> {
  CarritoNotifier() : super([]);

  // Método original (sin promoción)
  void agregarProducto(Producto producto, {int cantidad = 1, String? notas}) {
    // Buscamos si ya existe el producto con LAS MISMAS NOTAS
    final index = state.indexWhere((item) =>
        item.producto.id == producto.id && item.notas == notas && !item.tienePromocion);

    if (index >= 0) {
      // Si existe, aumentamos cantidad
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            state[i].copyWith(cantidad: state[i].cantidad + cantidad)
          else
            state[i]
      ];
    } else {
      // Si no, agregamos nuevo item
      state = [
        ...state,
        CartItem(producto: producto, cantidad: cantidad, notas: notas),
      ];
    }
  }

  // Método NUEVO para agregar con promoción
  void agregarProductoConPromocion({
    required Producto producto,
    required int promocionId,
    required double precioPromocional,
    int cantidad = 1,
    String? notas,
    List<Producto>? productosAdicionales,
    bool esParteDeCombo = false,
    String? grupoCombo,
  }) {
    // Para combos, siempre agregar nuevo (no acumular)
    if (esParteDeCombo) {
      state = [
        ...state,
        CartItem(
          producto: producto,
          cantidad: cantidad,
          notas: notas,
          promocionId: promocionId,
          precioPromocional: precioPromocional,
          productosAdicionales: productosAdicionales,
          esParteDeCombo: true,
          grupoCombo: grupoCombo,
        ),
      ];
      return;
    }

    // Para promociones simples, verificar si ya existe
    final index = state.indexWhere((item) =>
        item.producto.id == producto.id &&
        item.notas == notas &&
        item.promocionId == promocionId);

    if (index >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            state[i].copyWith(cantidad: state[i].cantidad + cantidad)
          else
            state[i]
      ];
    } else {
      state = [
        ...state,
        CartItem(
          producto: producto,
          cantidad: cantidad,
          notas: notas,
          promocionId: promocionId,
          precioPromocional: precioPromocional,
          productosAdicionales: productosAdicionales,
        ),
      ];
    }
  }

  // Agregar combo completo (2x25 tragos, por ejemplo)
  // En lib/features/pedidos/presentation/providers/carrito_provider.dart

  void agregarCombo({
    required List<Producto> productos,
    required int promocionId,
    required double precioTotal,
    Map<int, String>? notasPorProducto,
  }) {
    final grupoComboId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Aquí está la magia: Divide 25 / 2 = 12.50 para cada uno
    final precioPorProducto = precioTotal / productos.length; 

    print("🛒 [CARRITO] Agregando combo. Precio unitario calc: $precioPorProducto");

    final nuevosItems = productos.map((prod) {
      return CartItem(
        producto: prod,
        cantidad: 1,
        notas: notasPorProducto?[prod.id],
        promocionId: promocionId,
        precioPromocional: precioPorProducto, // <--- ESTO ES CRÍTICO
        esParteDeCombo: true,
        grupoCombo: grupoComboId,
      );
    }).toList();

    // Agregamos todos de golpe
    state = [...state, ...nuevosItems];
  }

  void removerProducto(int productoId) {
    state = state.where((item) => item.producto.id != productoId).toList();
  }

  void limpiar() => state = [];

  // PRECIO PROMOCIONAL DEL SEGUNDO (cuando está solo, sin entrada)
  static const double precioPromoSegundoSolo = 10.00;
  // PRECIO DE ENTRADA EXTRA (cuando sobran entradas sin segundo)
  static const double precioEntradaExtra = 5.00;

  // EL CEREBRO MATEMÁTICO (Versión Sincronizada con Repository)
  double get total {
    double totalGeneral = 0;

    // 1. Clasificar items en bolsas separadas
    List<CartItem> bolsaEntradas = [];
    List<CartItem> bolsaSegundos = [];
    List<CartItem> bolsaCortesias = [];
    List<CartItem> bolsaOtros = [];

    for (var item in state) {
      // Expandir por cantidad para manejar individualmente
      for (int i = 0; i < item.cantidad; i++) {
        // Detectar cortesías (precio 0 o nota con "CORTESÍA")
        final esCortesia = item.precioEfectivo == 0.00 ||
            (item.notas != null && item.notas!.toUpperCase().contains('CORTESÍA'));

        if (esCortesia) {
          bolsaCortesias.add(item);
        } else if (item.producto.subtipo == 'ENTRADA') {
          bolsaEntradas.add(item);
        } else if (item.producto.subtipo == 'SEGUNDO') {
          bolsaSegundos.add(item);
        } else {
          bolsaOtros.add(item);
        }
      }
    }

    // 2. Calcular cuántos Menús Completos se forman (solo con items NO cortesía)
    int nMenus = (bolsaEntradas.length < bolsaSegundos.length)
                 ? bolsaEntradas.length
                 : bolsaSegundos.length;

    // 3. Ordenar segundos por ID para consistencia con el repository
    bolsaSegundos.sort((a, b) => a.producto.id.compareTo(b.producto.id));

    // Ordenar entradas por precio descendente (las más caras primero, para cobrarlas si sobran)
    bolsaEntradas.sort((a, b) => b.producto.precio.compareTo(a.producto.precio));

    // 4. Sumar Cortesías (siempre 0)
    // No sumamos nada, pero las contamos para debug si es necesario

    // 5. Sumar Segundos
    for (int i = 0; i < bolsaSegundos.length; i++) {
      if (i < nMenus) {
        // ES PARTE DE MENÚ: Precio de carta (ej: S/ 13.00)
        totalGeneral += bolsaSegundos[i].producto.precio;
      } else {
        // ES SEGUNDO SOLO (huérfano): Precio promo (S/ 10.00)
        totalGeneral += precioPromoSegundoSolo;
      }
    }

    // 6. Sumar Entradas
    for (int i = 0; i < bolsaEntradas.length; i++) {
      if (i < nMenus) {
        // DENTRO DE MENÚ: Gratis (incluida)
        // No sumamos nada
      } else {
        // ENTRADA EXTRA (huérfana): Se cobra
        double precioReal = bolsaEntradas[i].producto.precio;
        // Si el precio en BD es 0 (ítem de menú), usamos precio fijo de entrada extra
        if (precioReal <= 0) {
          totalGeneral += precioEntradaExtra;
        } else {
          totalGeneral += precioReal;
        }
      }
    }

    // 7. Sumar Otros (Gaseosas, Tragos, etc.) - precio efectivo directo
    for (var item in bolsaOtros) {
      totalGeneral += item.precioEfectivo;
    }

    return totalGeneral;
  }

  // Método auxiliar para obtener el desglose visual de menús
  Map<String, int> get desgloseMenus {
    int entradas = 0;
    int segundos = 0;

    for (var item in state) {
      // Excluir cortesías del conteo de menú
      final esCortesia = item.precioEfectivo == 0.00 ||
          (item.notas != null && item.notas!.toUpperCase().contains('CORTESÍA'));

      if (esCortesia) continue;

      if (item.producto.subtipo == 'ENTRADA') {
        entradas += item.cantidad;
      } else if (item.producto.subtipo == 'SEGUNDO') {
        segundos += item.cantidad;
      }
    }

    int menusCompletos = (entradas < segundos) ? entradas : segundos;
    int entradasSolas = (entradas - segundos) > 0 ? (entradas - segundos) : 0;
    int segundosSolos = (segundos - entradas) > 0 ? (segundos - entradas) : 0;

    return {
      'menus': menusCompletos,
      'entradasSolas': entradasSolas,
      'segundosSolos': segundosSolos,
    };
  }
}

final carritoProvider = StateNotifierProvider<CarritoNotifier, List<CartItem>>((ref) {
  return CarritoNotifier();
});