import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../../../shared/utils/menu_calculator.dart'; 

class PrinterListenerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  RealtimeChannel? _channel;
  bool _isInitializing = false;

  // --- CONFIGURACIÓN DE IMPRESORAS ---
  static const String printerPrincipal = 'POS-80C-PRINCIPAL';
  static const String printerBar = 'POS-80C-BAR';
  static const String printerCocina = 'POS-80C-COCINA'; 

  // --- MAPA DE CATEGORÍAS (IDs) ---
  
  // En la noche (Restobar), todo lo líquido va al Bar
  static const Set<int> catIdsLiquidos = {
    3,  // BEBIDAS
    5,  // TRAGOS
    9,  // REFRESCOS Y JUGOS
    10, 11, 12, 13, 14, 15, 16, // LICORES VARIOS
    21, // D-JUGOS
    22, // D-REFRESCOS
    23, // D-CALIENTES
    24  // D-BEBIDAS
  };

  // En la mañana (Menú), solo esto va a Principal como item individual (lo demás a Cocina)
  static const Set<int> catIdsPrincipalMenu = {
    3,  // BEBIDAS (Gaseosas)
    22, // D-REFRESCOS
    23, // D-CALIENTES
    24  // D-BEBIDAS
  }; 

  // 1. Modificamos el startListening para que sea el orquestador
  void startListening() async { // <--- Ahora es async
    if (_isInitializing || _channel != null) return;
    _isInitializing = true;

    // PASO A: Primero limpiamos la casa (Procesar lo viejo)
    debugPrint("🔄 SINCRONIZANDO TICKETS PENDIENTES...");
    await _procesarPendientesAlInicio();

    // PASO B: Luego nos conectamos para escuchar lo nuevo
    _conectarCanal();
  }

  // 2. Método NUEVO: La rutina de "recuperación"
  Future<void> _procesarPendientesAlInicio() async {
    try {
      // Buscamos todo lo que se quedó en 'pendiente' ordenado por antigüedad (FIFO)
      final List<dynamic> pendientes = await _supabase
          .from('cola_impresion')
          .select()
          .eq('estado', 'pendiente')
          .order('id', ascending: true); // Lo más viejo primero

      if (pendientes.isEmpty) {
        debugPrint("✅ No hay tickets pendientes antiguos.");
        return;
      }

      debugPrint("⚠️ ENCONTRADOS ${pendientes.length} TICKETS PENDIENTES. IMPRIMIENDO...");

      for (var ticket in pendientes) {
        debugPrint("🖨️ Recuperando impresión Ticket #${ticket['id']}...");
        // Reutilizamos tu lógica existente
        await _procesarImpresion(ticket); 
        
        // Pequeña pausa para no saturar el buffer de la impresora si son muchos
        await Future.delayed(const Duration(milliseconds: 500)); 
      }
    } catch (e) {
      debugPrint("❌ Error sincronizando pendientes: $e");
    }
  }

  void _conectarCanal() {
    debugPrint("🖨️ SERVICIO DE IMPRESIÓN INICIADO...");
    _channel = _supabase.channel('public:cola_impresion');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cola_impresion',
          callback: (payload) async {
            final nuevoTicket = payload.newRecord;
            if (nuevoTicket['estado'] == 'pendiente') {
              debugPrint("📩 PROCESANDO TICKET #${nuevoTicket['id']}");
              await _procesarImpresion(nuevoTicket);
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint("✅ CONECTADO A COLA DE IMPRESIÓN");
            _isInitializing = false;
          } else if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.channelError) {
            debugPrint("⚠️ RECONECTANDO...");
            _reintentarConexion();
          }
        });
  }

  void _reintentarConexion() {
    if (_isInitializing) return;
    _supabase.removeChannel(_channel!);
    _channel = null;
    _isInitializing = false;
    Future.delayed(const Duration(seconds: 5), () => startListening());
  }

  Future<void> _procesarImpresion(Map<String, dynamic> ticketCola) async {
    try {
      final pedidoId = ticketCola['pedido_id'];
      
      final pedidoData = await _supabase
          .from('pedidos')
          .select('''
            id, created_at, updated_at, estado, total, turno, nombre_cliente, hora_recojo,
            mesas(numero, zonas(nombre)),
            detalle_pedido(
              *,
              productos(nombre, subtipo, precio, categoria_id)
            ),
            pagos(fecha_hora_pago, metodo_pago, total_pagado)
          ''')
          .eq('id', pedidoId)
          .single();

      final turno = pedidoData['turno'] ?? 'RESTOBAR';
      final tipoTicket = ticketCola['tipo_ticket'];
      final datosExtra = ticketCola['datos_extra'];

      // ==============================================================================
      // 🚦 LÓGICA DE DISTRIBUCIÓN
      // ==============================================================================
      
      if (tipoTicket == 'comanda') {

        // 1. Preparar lista plana de items
        List<dynamic> todosLosItems = [];
        // NUEVO: Verificar flag de "para llevar" desde datos_extra (enviado por el carrito)
        final bool esParaLlevarDesdeCarrito = datosExtra != null && datosExtra['es_para_llevar'] == true;

        if (datosExtra != null && datosExtra['es_adicional'] == true) {
          todosLosItems = List<dynamic>.from(datosExtra['items_nuevos']);
        } else {
          todosLosItems = (pedidoData['detalle_pedido'] as List).map((d) {
            return {
              'nombre': d['productos']['nombre'],
              'cantidad': d['cantidad'],
              'notas': d['notas'],
              'categoria_id': d['productos']['categoria_id'],
            };
          }).toList();
        }

        if (turno == 'MENU') {
          // --- MAÑANA (MENÚ) ---

          // 1. Filtro para Cocina (Comida + Jugos)
          final itemsCocina = todosLosItems.where((i) {
             final cat = i['categoria_id'];
             return cat == null || !catIdsPrincipalMenu.contains(cat);
          }).toList();

          // 2. Imprimir Cocina
          if (itemsCocina.isNotEmpty) {
             await _imprimirTicketFisico(
               pedido: pedidoData, tipo: 'comanda', datosExtra: datosExtra,
               printerName: printerCocina, itemsForzados: itemsCocina, esDobleCopia: false,
               forzarParaLlevar: esParaLlevarDesdeCarrito,
             );
          }

          // 3. Imprimir COPIA COMPLETA en Principal (SOLICITUD DEL USUARIO)
          // Aquí mandamos "todosLosItems" sin filtrar para que salga todo en caja
          await _imprimirTicketFisico(
             pedido: pedidoData, tipo: 'comanda', datosExtra: datosExtra,
             printerName: printerPrincipal, itemsForzados: todosLosItems, esDobleCopia: false,
             forzarParaLlevar: esParaLlevarDesdeCarrito,
          );

        } else {
          // --- NOCHE (RESTOBAR) ---
          // Bar: Todo lo líquido
          // Cocina: Todo lo sólido
          // Principal: Nada (salvo cuentas)

          final itemsBar = todosLosItems.where((i) {
            final cat = i['categoria_id'];
            return cat != null && catIdsLiquidos.contains(cat);
          }).toList();

          final itemsCocina = todosLosItems.where((i) {
            final cat = i['categoria_id'];
            return cat == null || !catIdsLiquidos.contains(cat);
          }).toList();

          if (itemsBar.isNotEmpty) {
            await _imprimirTicketFisico(
              pedido: pedidoData, tipo: 'comanda', datosExtra: datosExtra,
              printerName: printerBar, itemsForzados: itemsBar, esDobleCopia: false,
              forzarParaLlevar: esParaLlevarDesdeCarrito,
            );
          }
          if (itemsCocina.isNotEmpty) {
            await _imprimirTicketFisico(
              pedido: pedidoData, tipo: 'comanda', datosExtra: datosExtra,
              printerName: printerCocina, itemsForzados: itemsCocina, esDobleCopia: false,
              forzarParaLlevar: esParaLlevarDesdeCarrito,
            );
          }
        }

      } else {
        // CASO: CUENTAS / PRECUENTAS (Siempre a Principal, sin copias extra)
        await _imprimirTicketFisico(
          pedido: pedidoData, 
          tipo: tipoTicket, 
          datosExtra: datosExtra, 
          printerName: printerPrincipal,
          esDobleCopia: false
        );
      }

      // Finalizar
      await _supabase.from('cola_impresion').update({'estado': 'impreso'}).eq('id', ticketCola['id']);
      debugPrint("✅ TICKET #${ticketCola['id']} DISTRIBUIDO CORRECTAMENTE");

    } catch (e) {
      debugPrint("❌ ERROR DE IMPRESIÓN: $e");
      await _supabase.from('cola_impresion').update({'estado': 'error', 'datos_extra': {'error': e.toString()}}).eq('id', ticketCola['id']);
    }
  }

  // --- MOTOR DE IMPRESIÓN ---
  Future<void> _imprimirTicketFisico({
    required Map<String, dynamic> pedido,
    required String tipo,
    Map<String, dynamic>? datosExtra,
    required String printerName,
    bool esDobleCopia = false,
    List<dynamic>? itemsForzados,
    bool forzarParaLlevar = false,  // NUEVO: Flag para forzar indicación "Para Llevar"
  }) async {
    
    final printers = await Printing.listPrinters();
    final myPrinter = printers.firstWhere(
      (p) => p.name.toUpperCase().contains(printerName.toUpperCase()),
      orElse: () {
        debugPrint("⚠️ Impresora $printerName no encontrada. Usando default.");
        return printers.first;
      },
    );

    // Preparar Items
    List<Map<String, dynamic>> itemsFinales = [];
    String tituloTicket = tipo.toUpperCase();

    if (itemsForzados != null) {
      tituloTicket = (datosExtra?['es_adicional'] == true) ? 'ADICIONAL' : 'COMANDA';
      // Etiquetas de Zona
      if (printerName == printerBar) tituloTicket += ' BAR';
      if (printerName == printerCocina) tituloTicket += ' COCINA';
      if (printerName == printerPrincipal && tipo == 'comanda') tituloTicket += ' CAJA/CONTROL'; // Etiqueta para la copia completa
      
      itemsFinales = itemsForzados.map((i) => {
        'nombre': i['nombre'] ?? (i['nombre_producto_temporal'] ?? '?'),
        'cantidad': i['cantidad'],
        'notas': i['notas'],
        'precio': 0.0
      }).toList().cast<Map<String, dynamic>>();
    } 
    else if (tipo == 'comanda') {
      tituloTicket = 'COMANDA GENERAL';
      final raw = List<dynamic>.from(pedido['detalle_pedido']);
      itemsFinales = raw.map((i) => {
        'nombre': i['productos']['nombre'], 'cantidad': i['cantidad'], 'notas': i['notas'], 'precio': 0.0
      }).toList().cast<Map<String, dynamic>>();
    } 
    else {
      tituloTicket = (tipo == 'cuenta') ? 'CUENTA MESA' : 'PRE-CUENTA';
      final rawDB = List<dynamic>.from(pedido['detalle_pedido']);
      itemsFinales = _agruparProductos(rawDB); 
    }

    // Cabecera
    final numeroMesa = pedido['mesas']['numero'];
    final nombreZona = pedido['mesas']['zonas']?['nombre'] ?? '';
    final clienteNombre = pedido['nombre_cliente'];
    // --- LÓGICA "PARA LLEVAR" ---
    // Se activa si:
    // 1. La zona contiene "LLEVAR" en el nombre, O
    // 2. Hay hora de recojo programada, O
    // 3. Se marcó explícitamente como "para llevar" en el carrito (forzarParaLlevar)
    final bool tieneHoraRecojo = pedido['hora_recojo'] != null;
    final bool zonaEsLlevar = nombreZona.toString().toUpperCase().contains('LLEVAR');

    final bool esParaLlevar = zonaEsLlevar || tieneHoraRecojo || forzarParaLlevar;

    final fechaInicio = DateTime.parse(pedido['created_at']).toLocal();
    final horaInicio = DateFormat('HH:mm').format(fechaInicio);
    
    String? horaRecojoStr;
    if (pedido['hora_recojo'] != null) {
       horaRecojoStr = DateFormat('hh:mm a').format(DateTime.parse(pedido['hora_recojo']).toLocal());
    }
    
    double totalCuenta = 0;
    if (tipo != 'comanda') {
       totalCuenta = (pedido['total'] as num?)?.toDouble() ?? 0.0;
    }

    // PDF Builder
    final font = await PdfGoogleFonts.nunitoRegular();
    final fontBold = await PdfGoogleFonts.nunitoBold();
    final doc = pw.Document();

    pw.Widget buildContent() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text(tituloTicket, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
          pw.Divider(borderStyle: pw.BorderStyle.dashed),
          
          if (esParaLlevar)
             pw.Center(child: pw.Text('*** PARA LLEVAR ***', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          
          pw.SizedBox(height: 5),

          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(esParaLlevar ? 'MESA (REF): $numeroMesa' : 'MESA: $numeroMesa', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(horaInicio, style: const pw.TextStyle(fontSize: 12)),
          ]),
          
          if (clienteNombre != null && clienteNombre.toString().isNotEmpty)
             pw.Container(
               margin: const pw.EdgeInsets.only(top: 2),
               child: pw.Text('CLIENTE: ${clienteNombre.toUpperCase()}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))
             ),

          if (horaRecojoStr != null) 
            pw.Text('RECOJO: $horaRecojoStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),

          pw.SizedBox(height: 5),
          pw.Text('#${pedido['id']}'),
          pw.Divider(),

          // ITEMS
          ...itemsFinales.map((item) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(width: 20, child: pw.Text('${item['cantidad']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                    pw.Expanded(child: pw.Text(item['nombre'], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
                    if (tipo != 'comanda')
                      pw.Text(((item['precio'] as num) * (item['cantidad'] as num)).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 12)),
                  ]
                ),
                if (item['notas'] != null && item['notas'].toString().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 20), 
                    child: pw.Text('(${item['notas']})', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic))
                  )
              ]
            )
          )), 

          if (tipo != 'comanda') ...[
             pw.Divider(),
             pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text('S/. ${totalCuenta.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
             ]),
             
             if (tipo == 'cuenta' && (datosExtra != null && datosExtra['es_pago_dividido'] == true)) ...[
                pw.SizedBox(height: 5),
                pw.Text('PAGOS:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ...(datosExtra['desglose_pagos'] as List).map((p) => pw.Row(
                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                   children: [
                      pw.Text(p['metodo'].toString().toUpperCase(), style: const pw.TextStyle(fontSize: 10)),
                      pw.Text(p['monto'].toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                   ]
                )).toList()
             ] else if (tipo == 'cuenta' && pedido['pagos'] != null && (pedido['pagos'] as List).isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text('PAGOS:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ...(pedido['pagos'] as List).map((p) => pw.Row(
                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                   children: [
                      pw.Text((p['metodo_pago'] ?? 'EFECTIVO').toString().toUpperCase(), style: const pw.TextStyle(fontSize: 10)),
                      pw.Text((p['total_pagado'] ?? 0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                   ]
                )).toList()
             ]
          ],

          pw.SizedBox(height: 30), 
          pw.Center(child: pw.Text(".", style: pw.TextStyle(color: PdfColors.white))), 
        ]
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(72 * PdfPageFormat.mm, 3276 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => buildContent(),
      ),
    );

    if (esDobleCopia) {
       doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(72 * PdfPageFormat.mm, 3276 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (context) => buildContent(), 
        ),
      );
    }

    await Printing.directPrintPdf(printer: myPrinter, onLayout: (_) async => doc.save(), usePrinterSettings: true);
  }

  List<Map<String, dynamic>> _agruparProductos(List<dynamic> itemsRaw) {
    final Map<String, Map<String, dynamic>> agrupados = {};
    for (var item in itemsRaw) {
      final prodId = item['producto_id'];
      final notas = item['notas'] ?? '';
      final precio = (item['precio_unitario'] ?? 0.0) as num;
      
      final key = '$prodId-$notas-$precio'; 
      
      final prodData = item['productos'] ?? {};
      final nombre = prodData['nombre'] ?? 'Item';
      
      if (!agrupados.containsKey(key)) {
        agrupados[key] = {
          'nombre': nombre,
          'cantidad': 0,
          'precio_unitario': precio.toDouble(),
          'notas': notas,
          'precio': precio.toDouble()
        };
      }
      agrupados[key]!['cantidad'] += (item['cantidad'] as int);
    }
    return List<Map<String, dynamic>>.from(agrupados.values);
  }
}