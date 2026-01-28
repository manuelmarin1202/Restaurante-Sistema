import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/categoria_model.dart';
import '../../../../shared/models/producto_model.dart'; // <--- Importante
import '../../../../shared/models/promocion_model.dart'; // <--- Importante
import 'providers/carrito_provider.dart';
import 'providers/productos_provider.dart';
import '../../menu/presentation/providers/categorias_provider.dart';
import 'widgets/carrito_resumen_sheet.dart';
import '../../menu/data/productos_repository.dart'; // Ajusta la ruta según tu estructura
// O si está en otra carpeta, búscalo.
// NUEVOS IMPORTS PARA PROMOCIONES
import '../../promociones/data/promociones_repository.dart';
import '../../promociones/presentation/widgets/promocion_adicionales_sheet.dart';
// import '../../promociones/presentation/widgets/combo_multiple_sheet.dart'; // Si usas combos múltiples
import '../../../../shared/providers/modo_negocio_provider.dart';
import '../../promociones/presentation/widgets/combo_multiple_sheet.dart';
// Y asegúrate de tener acceso a tus productos (puede ser ref.read(productosProvider) si ya los tienes cargados)

// --- OPTIMIZACIÓN: CACHÉ DE PROMOCIONES ---
// Esto carga las promos UNA sola vez al entrar a la pantalla, eliminando el lag.
final promocionesCacheProvider = FutureProvider.autoDispose.family<List<Promocion>, String>((ref, tipoCarta) {
  return ref.read(promocionesRepositoryProvider).obtenerPromocionesActivas(tipoCarta: tipoCarta);
});

// Provider local de productos
final productosRepoProvider = Provider((ref) => ProductosRepository());

class TomaPedidoScreen extends ConsumerStatefulWidget {
  final int mesaId;
  final int? pedidoExistenteId;

  const TomaPedidoScreen({
    super.key,
    required this.mesaId,
    this.pedidoExistenteId
  });

  @override
  ConsumerState<TomaPedidoScreen> createState() => _TomaPedidoScreenState();
}

// AGREGAMOS: WidgetsBindingObserver para detectar cuando "despierta"
class _TomaPedidoScreenState extends ConsumerState<TomaPedidoScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // LIBERAR MESA si se sale sin crear pedido (solo si es nuevo)
    if (widget.pedidoExistenteId == null) {
      _liberarMesaTemporal();
    }
    super.dispose();
  }

  // --- DETECTOR DE "DESPERTAR" ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 APP REANUDADA: Refrescando productos y promos...");
      // Forzamos la recarga de los providers críticos
      ref.invalidate(categoriasProvider);
      ref.invalidate(productosListProvider); // Refrescar productos
      final modoActual = ref.read(modoNegocioProvider);
      ref.invalidate(promocionesCacheProvider(modoActual)); // Refrescar promociones
      debugPrint("✅ Providers refrescados exitosamente");
    }
  }

  Future<void> _liberarMesaTemporal() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('mesas')
          .update({'estado': 'libre'})
          .eq('id', widget.mesaId)
          .eq('estado', 'en_uso_temporal');
    } catch (e) {
      debugPrint('Error liberando mesa temporal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasProvider);
    final carrito = ref.watch(carritoProvider);
    final totalCarrito = ref.watch(carritoProvider.notifier).total;
    
    // PRE-CARGA DE PROMOS
    final modoActual = ref.watch(modoNegocioProvider);
    ref.watch(promocionesCacheProvider(modoActual));

    return categoriasAsync.when(
      data: (categorias) => DefaultTabController(
        length: categorias.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Mesa ${widget.mesaId} - Pedido'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/mesas'),
            ),
            bottom: TabBar(
              isScrollable: true,
              tabs: categorias.map((c) => Tab(text: c.nombre)).toList(),
            ),
          ),
          body: TabBarView(
            children: categorias.map((c) => _ListaProductos(categoria: c)).toList(),
          ),
          floatingActionButton: carrito.isNotEmpty 
            ? FloatingActionButton.extended(
                backgroundColor: Colors.red,
                onPressed: () => _mostrarResumen(context),
                label: Text('Ver Pedido (S/. ${totalCarrito.toStringAsFixed(2)})'),
                icon: const Icon(Icons.shopping_basket, color: Colors.white),
              )
            : null,
        ),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.signal_wifi_off, size: 50, color: Colors.grey),
          Text('Error de conexión: $e'),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
               ref.invalidate(categoriasProvider);
               ref.invalidate(promocionesCacheProvider(modoActual));
            }, 
            child: const Text('Reintentar')
          )
        ],
      ))),
    );
  }

  void _mostrarResumen(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CarritoResumenSheet(
        mesaId: widget.mesaId,
        pedidoExistenteId: widget.pedidoExistenteId,
      ),
    );
  }
}

class _ListaProductos extends ConsumerWidget {
  final Categoria categoria;
  
  const _ListaProductos({required this.categoria});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(productosPorCategoriaProvider(categoria.id));

    if (productos.isEmpty) {
      // AQUÍ ESTÁ EL TRUCO: Si está vacío, podría ser error de carga.
      // Damos un botón para refrescar TODOS los providers críticos.
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No hay productos disponibles',
                       style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Esto puede deberse a una falla de conexión\no que la app estuvo suspendida',
                       textAlign: TextAlign.center,
                       style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('RECARGAR PRODUCTOS'),
              onPressed: () {
                // Invalidar TODOS los providers críticos para forzar recarga completa
                ref.invalidate(productosListProvider);
                ref.invalidate(categoriasProvider);
                final modoActual = ref.read(modoNegocioProvider);
                ref.invalidate(promocionesCacheProvider(modoActual));
              },
            )
          ],
        )
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: productos.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final producto = productos[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(producto.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('S/. ${producto.precio.toStringAsFixed(2)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // BOTÓN 1: NOTA PERSONALIZADA
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.orange, size: 30),
                tooltip: 'Agregar con nota especial',
                onPressed: () async {
                  // 1. AHORA ESPERAMOS UN MAPA (DYNAMIC)
                  final resultado = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (ctx) => _DialogoNotaLibre(nombreProducto: producto.nombre),
                  );

                  if (resultado == null || !context.mounted) return;

                  // 2. EXTRAEMOS DATOS
                  String notaFinal = resultado['nota'] ?? '';
                  final bool esCortesia = resultado['esCortesia'] ?? false;

                  // 3. LÓGICA DE CORTESÍA
                  if (esCortesia) {
                    // Anteponemos la etiqueta visual
                    if (notaFinal.isNotEmpty) {
                      notaFinal = "(CORTESÍA) $notaFinal";
                    } else {
                      notaFinal = "(CORTESÍA)";
                    }

                    // Usamos el método de 'promoción' para forzar precio 0.00
                    // Pasamos promocionId: null porque no está ligado a una promo de BD
                    ref.read(carritoProvider.notifier).agregarProductoConPromocion(
                      producto: producto,
                      promocionId: -1, // OJO: Asegúrate que tu provider acepte null aquí, si no pon -1
                      precioPromocional: 0.00, // ¡GRATIS!
                      cantidad: 1,
                      notas: notaFinal,
                    );
                    
                    _mostrarConfirmacion(context, producto.nombre, "CORTESÍA APLICADA");

                  } else {
                    // LÓGICA NORMAL (SI NO ES CORTESÍA)
                    ref.read(carritoProvider.notifier).agregarProducto(
                      producto, 
                      notas: notaFinal.isEmpty ? null : notaFinal,
                    );
                    _mostrarConfirmacion(context, producto.nombre, notaFinal);
                  }
                },
              ),
              
              const SizedBox(width: 8),

              // BOTÓN 2: AGREGAR RÁPIDO (Lógica de Promociones Integrada)
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 36),
                tooltip: 'Agregar rápido',
                onPressed: () => _procesarAgregado(context, ref, producto), // <--- AQUÍ EL CAMBIO
              ),
            ],
          ),
        );
      },
    );
  }

  // --- LÓGICA DE AGREGADO INTELIGENTE (Promociones + Legacy) ---
  // --- LÓGICA DE AGREGADO INTELIGENTE (CORREGIDA) ---
  Future<void> _procesarAgregado(BuildContext context, WidgetRef ref, Producto producto) async {
    final modoActual = ref.read(modoNegocioProvider);
    
    // 1. Usamos la caché en lugar de ir a BD
    final promocionesAsync = ref.read(promocionesCacheProvider(modoActual));
    
    // Si la caché aún carga, mostramos un pequeño loading (o esperamos)
    List<Promocion> promociones = [];
    if (promocionesAsync.hasValue) {
      promociones = promocionesAsync.value!;
    } else {
      // Fallback: esperamos (esto solo pasará en el primer click si es muy rápido)
      promociones = await ref.read(promocionesRepositoryProvider).obtenerPromocionesActivas(tipoCarta: modoActual);
    }

    // 2. Buscamos promo en memoria (instantáneo)
    // Replicamos la lógica de 'calcularPrecioConPromocion' pero en local
    PrecioPromocionResult? resultado;
    
    // ... (Lógica de búsqueda simplificada o llamada a función sincrona si la tuvieras)
    // Para no romper tu repo, llamaremos a una versión SINCRONA o simulada rápida,
    // o simplemente usamos el repo que ahora debería responder rápido si Supabase cachea,
    // PERO la mejor forma es pasarle la lista ya cargada.
    
    // Como tu repo espera llamadas a DB, vamos a hacer un pequeño "bypass" usando la lista en memoria:
    final repo = ref.read(promocionesRepositoryProvider);
    // (Asumimos que el repo tiene un método para buscar en lista, si no, usaremos la lógica aquí)
    
    // BÚSQUEDA MANUAL EN MEMORIA (Lógica corregida para Combos)
    // BÚSQUEDA MANUAL EN MEMORIA (Lógica Híbrida Inteligente)
    // BÚSQUEDA MANUAL EN MEMORIA (CON DEBUG PROFUNDO)
    Promocion? mejorPromo;
    double mejorPrecio = producto.precio;
    bool tienePromo = false;

    debugPrint("🔍 [DEBUG] Iniciando escaneo de promos para: ${producto.nombre} (ID: ${producto.id})");
    debugPrint("🔍 [DEBUG] Total promos candidatas: ${promociones.length}");

    for (var promo in promociones) {
        // 1. Verificar match
        bool enPrincipales = promo.productos?.any((pp) => pp.productoId == producto.id) ?? false;
        bool enAdicionales = promo.adicionales?.any((pa) => pa.productoId == producto.id) ?? false;
        bool match = enPrincipales || enAdicionales;
        
        debugPrint("   > Revisando Promo: '${promo.nombre}' (ID: ${promo.id})");
        debugPrint("     - Match Principal: $enPrincipales | Match Adicional: $enAdicionales | FINAL: $match");
        
        if (match) {
           final tipoString = promo.tipoPromocion.toString().toLowerCase().replaceAll(RegExp(r'[._]'), '');
           debugPrint("     - Tipo detectado: '$tipoString'");
           
           // CASO A: COMBO MÚLTIPLE (2x25 Tragos)
           if (tipoString.contains('combomultiple')) {
              debugPrint("     ✅ ¡MATCH COMBO MÚLTIPLE!");
              mejorPromo = promo; 
              tienePromo = true;
           } 
           
           // CASO B: COMBO PRODUCTO (Alitas, Hamburguesas...)
           else if (tipoString.contains('comboproducto')) {
              final pp = promo.productos?.firstWhere(
                  (p) => p.productoId == producto.id, 
                  orElse: () => PromocionProducto(id: 0, promocionId: 0, productoId: 0, esPrincipal: false, esAdicionalObligatorio: false, cantidadAdicional: 0)
              );
              
              if (pp != null && pp.esPrincipal) {
                 debugPrint("     - Es Producto Principal. Precio Promo: ${pp.precioPromocional} vs Base: $mejorPrecio");
                 
                 // Opción 1: El precio baja
                 if (pp.precioPromocional != null && pp.precioPromocional! < mejorPrecio) {
                    debugPrint("     ✅ ¡GANADOR POR PRECIO BAJO! (${pp.precioPromocional})");
                    mejorPrecio = pp.precioPromocional!;
                    mejorPromo = promo; 
                    tienePromo = true;
                 }
                 // Opción 2: El precio es igual, pero tiene extras
                 else if (!tienePromo) { // Solo si no hay una mejor ya seleccionada
                    bool tieneExtras = promo.adicionales != null && promo.adicionales!.isNotEmpty;
                    debugPrint("     - Precio no mejora. ¿Tiene extras? $tieneExtras");
                    
                    if (tieneExtras) {
                        debugPrint("     ✅ ¡GANADOR POR EXTRAS! (Jarra/Gaseosa)");
                        mejorPromo = promo;
                        tienePromo = true;
                    }
                 }
              } else {
                 debugPrint("     ❌ No es producto principal en este combo (es adicional o error)");
              }
           } 
           
           // CASO C: PRECIO SIMPLE
           else if (tipoString.contains('preciosimple')) {
              final pp = promo.productos?.firstWhere((p) => p.productoId == producto.id);
              if (pp != null && pp.precioPromocional != null && pp.precioPromocional! < mejorPrecio) {
                 debugPrint("     ✅ ¡GANADOR PRECIO SIMPLE!");
                 mejorPrecio = pp.precioPromocional!;
                 mejorPromo = promo; 
                 tienePromo = true;
              }
           }
        }
    }

    if (tienePromo && mejorPromo != null) {
        final tipoString = mejorPromo.tipoPromocion.toString().toLowerCase().replaceAll(RegExp(r'[._]'), '');

        // CASO A: ALITAS + GASEOSA (Con Interceptor de Sabores)
        if (tipoString.contains('comboproducto')) {
           
           // --- INTERCEPTOR DE SABORES ---
           String? notaSabores;
           final nombreUpper = producto.nombre.toUpperCase();
           
           if (nombreUpper.contains('ALITAS') || nombreUpper.contains('WINGS')) {
              int maxSabores = 1;
              if (nombreUpper.contains('FAMILIAR')) maxSabores = 4; // Corregido a 4
              else if (nombreUpper.contains('COMPLETA')) maxSabores = 3;
              else if (nombreUpper.contains('JUNIOR') || nombreUpper.contains('MEDIAN')) maxSabores = 1;

              if (context.mounted) {
                if (maxSabores == 1) {
                   notaSabores = await showDialog<String>(
                     context: context,
                     builder: (ctx) => _DialogoSaborAlitas(),
                   );
                } else {
                   final lista = await showDialog<List<String>>(
                     context: context,
                     builder: (ctx) => _DialogoSaboresMultiples(maximo: maxSabores),
                   );
                   if (lista != null) notaSabores = lista.join(" / ");
                }
                
                // Si canceló la elección de sabores, cancelamos todo el proceso
                if (notaSabores == null) return;
              }
           }
           // ------------------------------

           if (mejorPromo.productos != null) {
             final promoProducto = mejorPromo.productos!.firstWhere((pp) => pp.productoId == producto.id);
             
             if (context.mounted) {
               showModalBottomSheet(
                 context: context,
                 isScrollControlled: true,
                 builder: (ctx) => PromocionAdicionalesSheet(
                   promocion: mejorPromo!,
                   productoPrincipal: producto,
                   promoProducto: promoProducto,
                   notaInicial: notaSabores, // <--- PASAMOS LOS SABORES
                 ),
               );
             }
             return;
           }
        }
        
        // CASO B: COMBO MÚLTIPLE
        else if (tipoString.contains('combomultiple')) {
           final productosDelCombo = await _cargarProductosDePromo(ref, mejorPromo);
           if (context.mounted) {
             showModalBottomSheet(
               context: context,
               isScrollControlled: true,
               builder: (ctx) => ComboMultipleSheet(
                 promocion: mejorPromo!,
                 productosDisponibles: productosDelCombo,
               ),
             );
           }
           return;
        }

        // CASO C: PRECIO SIMPLE
        else if (tipoString.contains('preciosimple')) {
           if (context.mounted) {
             ref.read(carritoProvider.notifier).agregarProductoConPromocion(
                producto: producto,
                promocionId: mejorPromo.id,
                precioPromocional: mejorPrecio,
                cantidad: 1,
             );
             _mostrarConfirmacion(context, producto.nombre, "Precio Promo: S/. $mejorPrecio");
           }
           return;
        }
    }

    // 3. Fallback (Lógica Manual Antigua) - Solo si no hubo promo
    String? notaAuto;
    final nombreProd = producto.nombre.toUpperCase();
    
    if (nombreProd.contains('COMPLETA') || nombreProd.contains('FAMILIAR')) {
      int maxSabores = nombreProd.contains('FAMILIAR') ? 4 : 3; 
      final saboresElegidos = await showDialog<List<String>>(
        context: context,
        builder: (context) => _DialogoSaboresMultiples(maximo: maxSabores),
      );
      if (saboresElegidos == null) return;
      notaAuto = saboresElegidos.join(" / ");
    }
    else if (nombreProd.contains('ALITAS') || nombreProd.contains('WINGS')) {
      notaAuto = await showDialog<String>(
        context: context,
        builder: (context) => _DialogoSaborAlitas(),
      );
      if (notaAuto == null) return; 
    }

    if (!context.mounted) return;
    ref.read(carritoProvider.notifier).agregarProducto(producto, notas: notaAuto);
    _mostrarConfirmacion(context, producto.nombre, notaAuto);
  }

  // Helper para cargar los productos del combo múltiple
  Future<List<Producto>> _cargarProductosDePromo(WidgetRef ref, Promocion promo) async {
    final productosRepoProvider = Provider((ref) => ProductosRepository());
    // Usamos el repositorio para traer los productos
    final todosLosProductos = await ref.read(productosRepoProvider).getProductos(); 
    
    // Obtenemos los IDs de productos que participan en la promo
    final idsEnPromo = promo.productos?.map((p) => p.productoId).toList() ?? [];
    
    // Filtramos solo los que coinciden
    return todosLosProductos.where((p) => idsEnPromo.contains(p.id)).toList();
  }


  

  void _mostrarConfirmacion(BuildContext context, String prod, String? nota) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$prod ${nota != null ? "($nota)" : ""} añadido'), 
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ... (Tus clases _DialogoSaborAlitas, _DialogoNotaLibre, etc. siguen aquí abajo igual)
class _DialogoSaborAlitas extends StatelessWidget {
  final List<String> sabores = [
    'BBQ', 'Búfalo', 'Crispy', 'Crispy Picante', 'Orientales', 'Acevichadas'
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Elija Sabor'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: sabores.length,
          separatorBuilder: (_,__) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(sabores[index]),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.pop(context, sabores[index]),
            );
          },
        ),
      ),
    );
  }
}

class _DialogoNotaLibre extends StatefulWidget {
  final String nombreProducto;
  const _DialogoNotaLibre({required this.nombreProducto});

  @override
  State<_DialogoNotaLibre> createState() => _DialogoNotaLibreState();
}

class _DialogoNotaLibreState extends State<_DialogoNotaLibre> {
  final _controller = TextEditingController();
  bool _esCortesia = false; // <--- NUEVO CAMPO

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nota para: ${widget.nombreProducto}', style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min, // Para que no ocupe toda la pantalla
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ej: Sin cebolla, Bajo en sal...',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          // --- SWITCH DE CORTESÍA ---
          SwitchListTile(
            title: const Text('¿Es Cortesía? (S/. 0.00)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: const Text('No sumará al total de la cuenta'),
            value: _esCortesia,
            activeThumbColor: Colors.purple,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                _esCortesia = val;
              });
            },
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          // DEVUELVE UN MAPA EN LUGAR DE SOLO STRING
          onPressed: () => Navigator.pop(context, {
            'nota': _controller.text.trim(),
            'esCortesia': _esCortesia
          }),
          child: const Text('Agregar al Pedido'),
        ),
      ],
    );
  }
}

class _DialogoSaboresMultiples extends StatefulWidget {
  final int maximo;
  const _DialogoSaboresMultiples({required this.maximo});

  @override
  State<_DialogoSaboresMultiples> createState() => _DialogoSaboresMultiplesState();
}

class _DialogoSaboresMultiplesState extends State<_DialogoSaboresMultiples> {
  final List<String> sabores = [
    'BBQ', 'Búfalo', 'Crispy', 'Crispy Picante', 'Orientales', 'Acevichadas'
  ];
  final Set<String> _seleccionados = {};

  @override
  Widget build(BuildContext context) {
    final bool puedeElegirMas = _seleccionados.length < widget.maximo;

    return AlertDialog(
      title: Text('Elija hasta ${widget.maximo} sabores'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: sabores.length,
          separatorBuilder: (_,__) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final sabor = sabores[index];
            final estaSeleccionado = _seleccionados.contains(sabor);

            return CheckboxListTile(
              title: Text(sabor),
              value: estaSeleccionado,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    if (puedeElegirMas) _seleccionados.add(sabor);
                  } else {
                    _seleccionados.remove(sabor);
                  }
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _seleccionados.isEmpty 
              ? null 
              : () => Navigator.pop(context, _seleccionados.toList()),
          child: Text('Aceptar (${_seleccionados.length}/${widget.maximo})'),
        ),
      ],
    );
  }
}