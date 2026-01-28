import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/pagos_repository.dart';

class CobroScreen extends ConsumerStatefulWidget {
  final int pedidoId;
  final int mesaId;
  final double total;
  final String? nombreClienteExistente; // Nuevo parámetro

  const CobroScreen({
    super.key,
    required this.pedidoId,
    required this.mesaId,
    required this.total,
    this.nombreClienteExistente,
  });

  @override
  ConsumerState<CobroScreen> createState() => _CobroScreenState();
}

class _CobroScreenState extends ConsumerState<CobroScreen> {
  // Estado Local
  final List<PagoParcial> _pagosAgregados = [];
  String _metodoSeleccionado = 'EFECTIVO';
  
  final TextEditingController _montoAPagarCtrl = TextEditingController();
  final TextEditingController _clienteCtrl = TextEditingController();
  
  bool _imprimirTicket = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _montoAPagarCtrl.text = widget.total.toStringAsFixed(2);

    // DEBUG: Ver qué nombre recibimos
    print('🔍 [COBRO] initState - nombreClienteExistente recibido: "${widget.nombreClienteExistente}"');

    // Preservar nombre del cliente existente
    if (widget.nombreClienteExistente != null && widget.nombreClienteExistente!.isNotEmpty) {
      _clienteCtrl.text = widget.nombreClienteExistente!;
      print('✅ [COBRO] Campo de texto pre-llenado con: "${_clienteCtrl.text}"');
    } else {
      print('⚠️ [COBRO] No hay nombre existente para pre-llenar');
    }
  }

  double get _totalPagado => _pagosAgregados.fold(0, (sum, p) => sum + p.monto);
  double get _restante => widget.total - _totalPagado;
  bool get _estaCompleto => _restante <= 0.1; 

  void _agregarPagoParcial() {
    final montoIngresado = double.tryParse(_montoAPagarCtrl.text) ?? 0;

    if (montoIngresado <= 0) return;
    if (montoIngresado > _restante + 0.1) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto excede lo que falta por cobrar')),
      );
      return;
    }

    setState(() {
      _pagosAgregados.add(PagoParcial(
        metodo: _metodoSeleccionado, 
        monto: montoIngresado
      ));
      
      final nuevoRestante = widget.total - (_totalPagado + montoIngresado);
      _montoAPagarCtrl.text = nuevoRestante > 0 ? nuevoRestante.toStringAsFixed(2) : '';
    });
  }

  void _eliminarPago(int index) {
    setState(() {
      _pagosAgregados.removeAt(index);
      _montoAPagarCtrl.text = _restante.toStringAsFixed(2); 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cobrar Mesa ${widget.mesaId}')),
      body: Column(
        children: [
          // 1. RESUMEN DEUDA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: _estaCompleto ? Colors.green[100] : Colors.red[50],
            child: Column(
              children: [
                const Text('TOTAL A COBRAR', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('S/. ${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _InfoBadge(label: 'PAGADO', valor: _totalPagado, color: Colors.blue),
                    const SizedBox(width: 20),
                    _InfoBadge(label: 'FALTA', valor: _restante > 0 ? _restante : 0, color: _estaCompleto ? Colors.green : Colors.red),
                  ],
                )
              ],
            ),
          ),

          // 2. FORMULARIO DE INGRESO
          if (!_estaCompleto) 
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Seleccionar Medio de Pago:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    
                    // --- NUEVO DISEÑO DE BOTONES (4 OPCIONES) ---
                    Row(
                      children: [
                        _PaymentButton(
                          icon: Icons.money, 
                          label: 'EFECTIVO', 
                          isSelected: _metodoSeleccionado == 'EFECTIVO', 
                          onTap: () => setState(() => _metodoSeleccionado = 'EFECTIVO'),
                          color: Colors.green
                        ),
                        const SizedBox(width: 8),
                        _PaymentButton(
                          icon: Icons.qr_code, 
                          label: 'YAPE', 
                          isSelected: _metodoSeleccionado == 'YAPE', 
                          onTap: () => setState(() => _metodoSeleccionado = 'YAPE'),
                          color: Colors.purple
                        ),
                        const SizedBox(width: 8),
                        _PaymentButton( // <--- BOTÓN PLIN INDEPENDIENTE
                          icon: Icons.mobile_friendly, 
                          label: 'PLIN', 
                          isSelected: _metodoSeleccionado == 'PLIN', 
                          onTap: () => setState(() => _metodoSeleccionado = 'PLIN'),
                          color: Colors.pinkAccent
                        ),
                        const SizedBox(width: 8),
                        _PaymentButton(
                          icon: Icons.credit_card, 
                          label: 'TARJETA', 
                          isSelected: _metodoSeleccionado == 'TARJETA', 
                          onTap: () => setState(() => _metodoSeleccionado = 'TARJETA'),
                          color: Colors.blue
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Input Monto
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _montoAPagarCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Monto a agregar',
                              border: OutlineInputBorder(),
                              prefixText: 'S/. ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _agregarPagoParcial,
                          icon: const Icon(Icons.add),
                          label: const Text('AGREGAR'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          ),
                        ),
                      ],
                    ),
                    
                    const Divider(height: 30),
                    
                    // Lista de Pagos Parciales
                    if (_pagosAgregados.isNotEmpty) ...[
                      const Text('Pagos registrados:', style: TextStyle(color: Colors.grey)),
                      ..._pagosAgregados.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        IconData icon;
                        Color color;
                        
                        if(p.metodo == 'EFECTIVO') { icon = Icons.money; color = Colors.green; }
                        else if(p.metodo == 'YAPE') { icon = Icons.qr_code; color = Colors.purple; }
                        else if(p.metodo == 'PLIN') { icon = Icons.mobile_friendly; color = Colors.pink; }
                        else { icon = Icons.credit_card; color = Colors.blue; }

                        return ListTile(
                          dense: true,
                          leading: Icon(icon, color: color),
                          title: Text(p.metodo, style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('S/. ${p.monto.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _eliminarPago(i),
                              )
                            ],
                          ),
                        );
                      }),
                    ]
                  ],
                ),
              ),
            )
          
          // 3. PANTALLA DE CIERRE
          else 
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                    const SizedBox(height: 10),
                    const Text('¡Cobro Completo!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 30),
                    
                    TextField(
                      controller: _clienteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Cliente (Opcional)',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder()
                      ),
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      title: const Text('Imprimir Comprobante'),
                      value: _imprimirTicket,
                      onChanged: (v) => setState(() => _imprimirTicket = v),
                    ),
                  ],
                ),
              ),
            ),

          // 4. BOTÓN FINAL
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: FilledButton(
                  onPressed: (_estaCompleto && !_isProcessing) ? _finalizarCobro : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isProcessing 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('FINALIZAR Y CERRAR MESA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizarCobro() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      // DEBUG: Estado del campo antes de procesar
      print('💰 [COBRO] _finalizarCobro iniciado');
      print('   - Valor del campo _clienteCtrl.text: "${_clienteCtrl.text}"');
      print('   - nombreClienteExistente (widget): "${widget.nombreClienteExistente}"');

      // LÓGICA CORREGIDA: Preservar nombre existente si no se ingresó uno nuevo
      String? nombreFinal;
      if (_clienteCtrl.text.isNotEmpty) {
        // Si el usuario escribió algo, usar eso
        nombreFinal = _clienteCtrl.text.trim();
        print('   ✅ Usando nombre del campo: "$nombreFinal"');
      } else if (widget.nombreClienteExistente != null && widget.nombreClienteExistente!.isNotEmpty) {
        // Si no escribió nada pero ya había un nombre, mantenerlo
        nombreFinal = widget.nombreClienteExistente;
        print('   ✅ Preservando nombre existente: "$nombreFinal"');
      } else {
        print('   ⚠️ No hay nombre para guardar (nombreFinal = null)');
      }
      // Si ambos son null/vacío, nombreFinal será null (no sobrescribe)

      print('   🎯 nombreFinal que se enviará a BD: "$nombreFinal"');

      await ref.read(pagosRepositoryProvider).procesarCobroMultiple(
        pedidoId: widget.pedidoId,
        mesaId: widget.mesaId,
        totalTotal: widget.total,
        listaPagos: _pagosAgregados,
        imprimirTicket: _imprimirTicket,
        clienteNombre: nombreFinal,
      );

      if (mounted) {
        context.go('/mesas');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Venta registrada con éxito'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      setState(() => _isProcessing = false);
    }
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final double valor;
  final Color color;
  const _InfoBadge({required this.label, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        Text('S/. ${valor.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PaymentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color; // Nuevo parámetro para color personalizado

  const _PaymentButton({
    required this.icon, 
    required this.label, 
    required this.isSelected, 
    required this.onTap,
    this.color = Colors.blueGrey // Default
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isSelected ? color : Colors.white;
    final borderColor = isSelected ? color : Colors.grey.shade300;
    final textColor = isSelected ? Colors.white : Colors.grey[700];
    final iconColor = isSelected ? Colors.white : color;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: activeColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  label, 
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor)
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}