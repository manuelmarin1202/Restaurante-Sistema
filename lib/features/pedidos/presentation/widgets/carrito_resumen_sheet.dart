import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/models/producto_model.dart';
import '../providers/carrito_provider.dart';
import '../../data/pedidos_repository.dart';
import '../../../../shared/providers/modo_negocio_provider.dart';

class CarritoResumenSheet extends ConsumerStatefulWidget {
  final int mesaId;
  final int? pedidoExistenteId;

  const CarritoResumenSheet({
    super.key, 
    required this.mesaId,
    this.pedidoExistenteId,
  });

  @override
  ConsumerState<CarritoResumenSheet> createState() => _CarritoResumenSheetState();
}

class _CarritoResumenSheetState extends ConsumerState<CarritoResumenSheet> {
  bool _isSending = false;
  bool _isLoadingData = false;
  bool _esParaLlevar = false;
  bool _imprimirComanda = true;

  final TextEditingController _nombreClienteCtrl = TextEditingController();
  TimeOfDay? _horaRecojoSeleccionada;

  @override
  void initState() {
    super.initState();
    // Si estamos editando un pedido existente, cargamos sus datos (nombre, etc.)
    if (widget.pedidoExistenteId != null) {
      _cargarDatosPedidoExistente();
    }
  }

  @override
  void dispose() {
    _nombreClienteCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosPedidoExistente() async {
    setState(() => _isLoadingData = true);
    try {
      final pedido = await ref.read(pedidosRepositoryProvider).obtenerPedidoPorId(widget.pedidoExistenteId!);
      
      if (mounted) {
        setState(() {
          // 1. Rellenar nombre si existe
          if (pedido['nombre_cliente'] != null) {
            _nombreClienteCtrl.text = pedido['nombre_cliente'];
          }
          
          // 2. Detectar si era para llevar basado en si tenía hora de recojo
          if (pedido['hora_recojo'] != null) {
            _esParaLlevar = true;
            // Opcional: Podrías parsear la hora aquí si quisieras mostrarla
            // final fecha = DateTime.parse(pedido['hora_recojo']).toLocal();
            // _horaRecojoSeleccionada = TimeOfDay(hour: fecha.hour, minute: fecha.minute);
          }
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingData = false);
      debugPrint("Error cargando datos del pedido: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(carritoProvider);
    final notifier = ref.read(carritoProvider.notifier);
    final modoActual = ref.read(modoNegocioProvider);
    final bool esTurnoDia = modoActual == 'MENU';
    final double precioTaperUnitario = esTurnoDia ? 0.00 : 1.00;

    final subtotalComida = notifier.total;

    // --- LÓGICA DE VISUALIZACIÓN DE MENÚS ---
    final desglose = notifier.desgloseMenus;
    final menusCompletos = desglose['menus'] ?? 0;
    final entradasSolas = desglose['entradasSolas'] ?? 0;
    final segundosSolos = desglose['segundosSolos'] ?? 0;
    final hayEntradas = menusCompletos > 0 || entradasSolas > 0;
    final haySegundos = menusCompletos > 0 || segundosSolos > 0;

    // --- CÁLCULO DE TAPERS ---
    double costoTapers = 0;
    int cantidadTapers = 0;
    int cantidadTapersCortesia = 0; 

    if (_esParaLlevar) {
      for (var item in items) {
        if (item.producto.categoriaId == 3 || item.producto.categoriaId == 9) continue;

        final esCortesia = item.precioEfectivo == 0.00 ||
                           (item.notas != null && item.notas!.toUpperCase().contains('CORTESÍA'));

        if (esCortesia) {
          cantidadTapersCortesia += item.cantidad;
        } else {
          cantidadTapers += item.cantidad;
        }
      }
      costoTapers = cantidadTapers * precioTaperUnitario;
    }

    final totalFinal = subtotalComida + costoTapers;

    // --- SOLUCIÓN PARA TECLADO EN WEB MÓVIL ---
    // Usamos un Scaffold interno transparente. El Scaffold maneja 
    // automáticamente el resizeToAvoidBottomInset mejor que un Container manual.
    return Scaffold(
      backgroundColor: Colors.transparent, // Fondo transparente para ver el modal
      resizeToAvoidBottomInset: true,    // ESTO ES CLAVE: Se encoge al salir el teclado
      
      // Usamos Align para pegar el contenido abajo (como un BottomSheet)
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          // Decoración del Modal (Fondo blanco y bordes redondeados arriba)
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          // Padding interno fijo (ya no depende del teclado manualmente)
          padding: const EdgeInsets.all(20),
          // Constraints para no ocupar toda la pantalla
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          
          // SingleChildScrollView absorbe el cambio de tamaño del Scaffold
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --------------------------
                // CABECERA
                // --------------------------
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.pedidoExistenteId != null 
                            ? 'Adicionar a Mesa ${widget.mesaId}' 
                            : 'Nuevo Pedido - Mesa ${widget.mesaId}', 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                    ),
                    if (items.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.red),
                        onPressed: () {
                          notifier.limpiar();
                          Navigator.pop(context); 
                        },
                      )
                  ],
                ),
                const Divider(),
                
                // --------------------------
                // LISTA DE PRODUCTOS
                // --------------------------
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('El carrito está vacío', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(), // Scroll lo maneja el padre
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      
                      String subtitulo = '';
                      if (item.producto.subtipo != 'CARTA' && item.producto.subtipo != null) {
                        subtitulo += '[${item.producto.subtipo}] ';
                      }
                      if (item.notas != null) {
                        subtitulo += "Nota: ${item.notas} ";
                      }
                      if (item.tienePromocion && item.productosAdicionales != null) {
                        final noms = item.productosAdicionales!.map((p) => p.nombre).join(", ");
                        subtitulo += "\n🎁 Incluye: $noms";
                      }

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: item.tienePromocion ? Colors.orange[100] : Colors.grey[200],
                          child: Text('${item.cantidad}', 
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              color: item.tienePromocion ? Colors.deepOrange : Colors.black
                            )
                          ),
                        ),
                        title: Text(item.producto.nombre, style: TextStyle(fontWeight: item.tienePromocion ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('S/. ${(item.precioEfectivo * item.cantidad).toStringAsFixed(2)}', 
                                 style: TextStyle(fontWeight: FontWeight.bold, color: item.tienePromocion ? Colors.green[700] : Colors.black)),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                              onPressed: () => notifier.removerProducto(item.producto.id),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                
                const Divider(),

                // --------------------------
                // RESUMEN MENÚ
                // --------------------------
                if (hayEntradas || haySegundos) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.restaurant_menu, size: 16, color: Colors.blue),
                          const SizedBox(width: 5),
                          Text("Armado de Menú ($menusCompletos completos)", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ]),
                        if (menusCompletos > 0) _buildRowResumen("Menús", menusCompletos, Colors.black87),
                        if (entradasSolas > 0) _buildRowResumen("Entradas Adicionales", entradasSolas, Colors.red),
                        if (segundosSolos > 0) _buildRowResumen("Segundos Solos", segundosSolos, Colors.orange[800]!),
                      ],
                    ),
                  ),
                  const Divider(),
                ],

                // --------------------------
                // OPCIONES Y NOMBRE
                // --------------------------
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      InputChip(
                        avatar: Checkbox(value: _imprimirComanda, onChanged: (v) => setState(() => _imprimirComanda = v!)),
                        label: const Text('Imprimir Ticket Cocina'),
                        backgroundColor: Colors.white,
                        onPressed: () => setState(() => _imprimirComanda = !_imprimirComanda),
                      ),
                      const SizedBox(width: 10),
                      FilterChip(
                        selected: _esParaLlevar,
                        label: const Text('Para Llevar'),
                        avatar: const Icon(Icons.takeout_dining, size: 18),
                        onSelected: (val) => setState(() => _esParaLlevar = val),
                        selectedColor: Colors.blue[100],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                if (_isLoadingData)
                  const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator())
                else
                  TextField(
                    controller: _nombreClienteCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: _esParaLlevar ? 'Cliente / Referencia *' : 'Nombre Cliente (Opcional)',
                      prefixIcon: const Icon(Icons.person_pin),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: _esParaLlevar ? 'Ej: Juan Pérez' : 'Ej: Mesa compartida, Cumpleaños...',
                    ),
                  ),

                if (_esParaLlevar) ...[
                  const SizedBox(height: 10),
                  if (esTurnoDia)
                    Text('Envases GRATIS (Menú)', style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.bold))
                  else ...[
                    if (cantidadTapersCortesia > 0)
                      Text('Envases: $cantidadTapers cobrados + $cantidadTapersCortesia cortesía = S/. ${costoTapers.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold))
                    else
                      Text('Costo envases: S/. ${costoTapers.toStringAsFixed(2)}', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],

                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final hora = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (hora != null) setState(() => _horaRecojoSeleccionada = hora);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Hora Recojo', prefixIcon: Icon(Icons.access_time), border: OutlineInputBorder(), isDense: true),
                      child: Text(_horaRecojoSeleccionada?.format(context) ?? 'Ahora (Lo antes posible)', style: TextStyle(color: _horaRecojoSeleccionada == null ? Colors.orange[800] : Colors.black, fontWeight: _horaRecojoSeleccionada == null ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                ],

                const Divider(),
                
                // --------------------------
                // TOTAL Y BOTÓN
                // --------------------------
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text('S/. ${totalFinal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
                    onPressed: (_isSending || items.isEmpty || _isLoadingData) 
                      ? null 
                      : () => _enviarPedido(
                          context,
                          cantidadTapers,
                          cantidadTapersCortesia,
                          precioTaperUnitario
                        ),
                    icon: _isSending 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Icon(Icons.send),
                    label: Text(
                      _isSending 
                        ? 'GUARDANDO...' 
                        : (_imprimirComanda ? 'ENVIAR A COCINA' : 'GUARDAR SIN IMPRIMIR')
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget auxiliar para filas de resumen
  Widget _buildRowResumen(String label, int cantidad, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("• $label", style: TextStyle(fontSize: 12, color: color)),
          Text("x$cantidad", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Future<void> _enviarPedido(
    BuildContext context,
    int cantidadTapersPagados,
    int cantidadTapersCortesia,
    double precioTaperUnitario
  ) async {
    setState(() => _isSending = true);
    
    try {
      final itemsOriginales = ref.read(carritoProvider);
      
      // 1. DESGLOSAR ITEMS (Expander combos/promos para guardar en BD)
      final List<CartItem> itemsExpandidos = [];
      
      for (var item in itemsOriginales) {
        itemsExpandidos.add(item); // Agregamos el item principal

        // Si tiene productos extra (combo), los agregamos como items separados con precio 0
        if (item.tienePromocion && item.productosAdicionales != null) {
          for (var adicional in item.productosAdicionales!) {
            itemsExpandidos.add(CartItem(
              producto: adicional,
              cantidad: item.cantidad,
              precioPromocional: 0.00,
              notas: 'Incluido en promo',
              esParteDeCombo: true
            ));
          }
        }
      }

      // 2. AGREGAR TAPERS A LA LISTA DE PRODUCTOS
      if (_esParaLlevar) {
        // Tapers Pagados
        if (cantidadTapersPagados > 0) {
          final productoTaperPagado = Producto(
            id: 999, // ID genérico o real de tu BD
            nombre: 'Envase / Taper', 
            precio: precioTaperUnitario,
            categoriaId: 7, 
            esImprimible: false, 
            activo: true, 
            subtipo: 'CARTA', 
            tipoCarta: 'AMBOS'
          );
          itemsExpandidos.add(CartItem(
            producto: productoTaperPagado, 
            cantidad: cantidadTapersPagados, 
            notas: 'Automático'
          ));
        }
        // Tapers Cortesía
        if (cantidadTapersCortesia > 0) {
           final productoTaperCortesia = Producto(
            id: 999, 
            nombre: 'Envase / Taper', 
            precio: 0.00,
            categoriaId: 7, 
            esImprimible: false, 
            activo: true, 
            subtipo: 'CARTA', 
            tipoCarta: 'AMBOS'
          );
          itemsExpandidos.add(CartItem(
            producto: productoTaperCortesia, 
            cantidad: cantidadTapersCortesia, 
            notas: 'Cortesía'
          ));
        }
      }

      final totalBase = ref.read(carritoProvider.notifier).total;
      final totalReal = totalBase + (cantidadTapersPagados * precioTaperUnitario);
      final modoActual = ref.read(modoNegocioProvider);

      // 3. PREPARAR HORA DE RECOJO
      DateTime? fechaRecojoFinal;
      if (_esParaLlevar) {
        final now = DateTime.now();
        if (_horaRecojoSeleccionada != null) {
          // Si el usuario eligió hora, respetamos esa
          fechaRecojoFinal = DateTime(now.year, now.month, now.day, _horaRecojoSeleccionada!.hour, _horaRecojoSeleccionada!.minute);
        } else {
          // Si no eligió, mandamos AHORA. Esto activa el flag de "Para Llevar" en la impresora.
          fechaRecojoFinal = now;
        }
      }

      // 4. VALIDACIÓN DE NOMBRE
      if (_esParaLlevar && _nombreClienteCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Debe ingresar el nombre del cliente para pedidos para llevar'), backgroundColor: Colors.orange),
        );
        setState(() => _isSending = false);
        return;
      }

      final nombreCliente = _nombreClienteCtrl.text.trim().isEmpty ? null : _nombreClienteCtrl.text.trim();

      // 5. ENVIAR AL REPOSITORIO
      if (widget.pedidoExistenteId != null) {
        // Caso: Agregar a pedido existente
        await ref.read(pedidosRepositoryProvider).agregarItemsAPedido(
          pedidoId: widget.pedidoExistenteId!,
          items: itemsExpandidos,
          imprimirTicket: _imprimirComanda,
          esParaLlevar: _esParaLlevar,  // NUEVO: Pasar flag para la comanda
        );
      } else {
        // Caso: Crear nuevo pedido
        await ref.read(pedidosRepositoryProvider).crearPedido(
          mesaId: widget.mesaId,
          items: itemsExpandidos,
          total: totalReal,
          nombreCliente: nombreCliente,
          horaRecojo: fechaRecojoFinal?.toIso8601String(), // Nunca será null si _esParaLlevar es true
          imprimirTicket: _imprimirComanda,
          turno: modoActual
        );
      }

      // 6. LIMPIEZA Y NAVEGACIÓN
      if (!context.mounted) return;
      ref.read(carritoProvider.notifier).limpiar();
      Navigator.of(context).pop(); // Cierra el Sheet
      
      if (widget.pedidoExistenteId != null) {
          context.pop(); // Si venía de detalle, vuelve atrás
      } else {
          context.go('/mesas'); // Si es nuevo, va al mapa de mesas
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_imprimirComanda ? '✅ Enviado a cocina' : '✅ Guardado'), 
          backgroundColor: Colors.green
        ),
      );

    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
      );
      setState(() => _isSending = false);
    }
  }
}