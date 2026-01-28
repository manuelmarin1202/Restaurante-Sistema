import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ReporteService {
  
  Future<void> imprimirCierreDia(List<dynamic> pedidos, DateTime fechaReporte, {String tituloReporte = 'CIERRE DE CAJA'}) async {
    // 1. FILTRAR
    final pedidosValidos = pedidos.where((p) => p['estado'] != 'cancelado').toList();
    
    // --- VARIABLES DE ACUMULACIÓN ---
    double totalVentaGlobal = 0;
    Map<String, double> totalPorMetodo = {'EFECTIVO': 0, 'YAPE': 0, 'PLIN': 0, 'TARJETA': 0};
    
    // Estructura: Categoría -> { Producto -> Stats }
    Map<String, Map<String, _ProductoStats>> statsPorCategoria = {};
    Map<String, double> dineroPorCategoria = {}; 
    Map<String, int> cantidadPorCategoria = {}; // Nuevo: Contador total por categoría

    // 2. PROCESAMIENTO (DIRECTO DE BD - "LO QUE ESTÁ GUARDADO ES LA VERDAD")
    for (var p in pedidosValidos) {
      
      // A. MÉTODOS DE PAGO
      final pagos = p['pagos'] as List<dynamic>?;
      if (pagos != null && pagos.isNotEmpty) {
        for(var pago in pagos) {
           String metodo = (pago['metodo_pago'] ?? 'EFECTIVO').toString().toUpperCase();
           double monto = (pago['total_pagado'] as num?)?.toDouble() ?? 0.0;
           
           // Normalización de nombres
           if (metodo.contains('PLIN')) totalPorMetodo['PLIN'] = (totalPorMetodo['PLIN'] ?? 0) + monto;
           else if (metodo.contains('YAPE')) totalPorMetodo['YAPE'] = (totalPorMetodo['YAPE'] ?? 0) + monto;
           else if (metodo.contains('TARJETA') || metodo.contains('IZI')) totalPorMetodo['TARJETA'] = (totalPorMetodo['TARJETA'] ?? 0) + monto;
           else totalPorMetodo['EFECTIVO'] = (totalPorMetodo['EFECTIVO'] ?? 0) + monto;
           
           totalVentaGlobal += monto;
        }
      } else {
        // Pendientes (sin pago registrado): Se suman al global teórico como efectivo o pendiente
        // Ojo: Si quieres cuadrar caja chica, solo deberías sumar lo pagado. 
        // Aquí sumamos todo para ver "Venta del día" aunque no se haya cobrado.
        double totalPedido = ((p['total'] ?? 0) as num).toDouble();
        totalPorMetodo['EFECTIVO'] = (totalPorMetodo['EFECTIVO'] ?? 0) + totalPedido;
        totalVentaGlobal += totalPedido;
      }

      // B. PRODUCTOS (Usamos los precios YA PROCESADOS de la BD)
      final detalles = List<dynamic>.from(p['detalle_pedido'] ?? []);
      
      for (var d in detalles) {
        final prod = d['productos'];
        final cantidad = (d['cantidad'] as int);
        final precioUnitario = (d['precio_unitario'] as num).toDouble();
        final nombreProd = prod['nombre'].toString();
        
        // Categoría: Intentamos sacar nombre, si es nulo ponemos OTROS
        String categoria = 'OTROS';
        if (prod['categorias'] != null) {
           categoria = prod['categorias']['nombre'].toString().toUpperCase();
        }

        // Acumulamos
        if (!statsPorCategoria.containsKey(categoria)) {
          statsPorCategoria[categoria] = {};
          dineroPorCategoria[categoria] = 0;
          cantidadPorCategoria[categoria] = 0;
        }

        if (!statsPorCategoria[categoria]!.containsKey(nombreProd)) {
          statsPorCategoria[categoria]![nombreProd] = _ProductoStats();
        }

        statsPorCategoria[categoria]![nombreProd]!.cantidad += cantidad;
        statsPorCategoria[categoria]![nombreProd]!.totalDinero += (precioUnitario * cantidad);
        
        dineroPorCategoria[categoria] = dineroPorCategoria[categoria]! + (precioUnitario * cantidad);
        cantidadPorCategoria[categoria] = cantidadPorCategoria[categoria]! + cantidad;
      }
    }

    // 3. GENERAR PDF (DISEÑO COMPACTO)
    final font = await PdfGoogleFonts.nunitoRegular();
    final fontBold = await PdfGoogleFonts.nunitoBold();
    final doc = pw.Document();

    final categoriasOrdenadas = statsPorCategoria.keys.toList()..sort();

    doc.addPage(
      pw.Page(
        // Margen mínimo para aprovechar papel
        pageFormat: const PdfPageFormat(72 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // HEADER COMPACTO
              pw.Center(child: pw.Text(tituloReporte, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text(DateFormat('EEEE d MMMM yyyy', 'es_PE').format(fechaReporte).toUpperCase(), style: const pw.TextStyle(fontSize: 9))),
              pw.Divider(thickness: 0.5),

              // RESUMEN CAJA
              _buildResumenCaja(totalVentaGlobal, totalPorMetodo),
              
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
              pw.Center(child: pw.Text('DETALLE VENTA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.SizedBox(height: 3),

              // LISTA POR CATEGORÍA
              ...categoriasOrdenadas.map((cat) {
                final productosMap = statsPorCategoria[cat]!;
                final subtotalCat = dineroPorCategoria[cat] ?? 0;
                final cantidadCat = cantidadPorCategoria[cat] ?? 0;

                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // CABECERA CATEGORÍA: "SEGUNDOS (50) ... S/. 500.00"
                      pw.Container(
                        color: PdfColors.grey200,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('$cat ($cantidadCat)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            pw.Text('S/. ${subtotalCat.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          ]
                        )
                      ),
                      // PRODUCTOS
                      ...productosMap.entries.map((entry) {
                        final stat = entry.value;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 2, right: 2, top: 1),
                          child: pw.Row(
                            children: [
                              // Cantidad fija a la izquierda para alinear
                              pw.SizedBox(
                                width: 20, 
                                child: pw.Text('${stat.cantidad}', style: const pw.TextStyle(fontSize: 8))
                              ),
                              // Nombre producto
                              pw.Expanded(
                                child: pw.Text(entry.key, style: const pw.TextStyle(fontSize: 8))
                              ),
                              // Total dinero producto
                              pw.Text(
                                stat.totalDinero == 0 ? '-' : stat.totalDinero.toStringAsFixed(2), 
                                style: const pw.TextStyle(fontSize: 8)
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              }).toList(),

              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),
              pw.Center(child: pw.Text('*** FIN REPORTE ***', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Cierre_${DateFormat('ddMM').format(fechaReporte)}',
    );
  }

  // --- WIDGETS INTERNOS ---

  pw.Widget _buildResumenCaja(double total, Map<String, double> metodos) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('VENTA TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text('S/. ${total.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 2),
        _rowMetodo('Efectivo', metodos['EFECTIVO']!),
        _rowMetodo('Yape', metodos['YAPE']!),
        _rowMetodo('Plin', metodos['PLIN']!),
        _rowMetodo('Tarjeta', metodos['TARJETA']!),
      ]
    );
  }

  pw.Widget _rowMetodo(String label, double val) {
    if (val == 0) return pw.SizedBox.shrink();
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        pw.Text('S/. ${val.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
      ],
    );
  }
}

// Clase para contar
class _ProductoStats {
  int cantidad = 0;
  double totalDinero = 0;
}