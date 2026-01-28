import 'dart:io' show Platform; // Importamos solo Platform
import 'package:flutter/foundation.dart'; // Importamos kIsWeb para detectar si es navegador
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/mesa_model.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../presentation/providers/mesa_provider.dart';

class MesasScreen extends ConsumerWidget {
  const MesasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesasAsyncValue = ref.watch(mesasProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Control de Mesas'),
        actions: [
          // --- CORRECCIÓN CRÍTICA PARA WEB ---
          // Primero preguntamos si NO es Web. Si es Web, Flutter detiene la lectura ahí
          // y nunca ejecuta Platform.isWindows, evitando el error de "Unsupported operation".
          if (!kIsWeb && Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Test Impresora',
              onPressed: () => _testImpresora(context),
            ),
          
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(mesasProvider),
          ),
        ],
      ),
      body: mesasAsyncValue.when(
        data: (mesas) {
          if (mesas.isEmpty) return const Center(child: Text('No hay mesas configuradas'));
          return _MesasAgrupadasView(mesas: mesas);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  // FUNCIONALIDAD: Test de impresión (Solo funcionará en Windows gracias a la protección de arriba)
  Future<void> _testImpresora(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buscando impresora POS-80C...')),
      );

      final printers = await Printing.listPrinters();
      
      final myPrinter = printers.firstWhere(
        (p) => p.name == 'POS-80C', 
        orElse: () => printers.firstWhere(
          (p) => p.name.toUpperCase().contains('POS'),
          orElse: () => printers.first,
        ),
      );

      debugPrint("🖨️ Testeando en: ${myPrinter.name}");

      final font = await PdfGoogleFonts.nunitoRegular();
      final fontBold = await PdfGoogleFonts.nunitoBold();

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('TEST DE CONEXION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.SizedBox(height: 10),
                  pw.Text('Impresora: ${myPrinter.name}'),
                  pw.Text('Sistema: Flutter Windows'),
                  pw.SizedBox(height: 20),
                  pw.Text('................................'),
                  pw.SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      );

      await Printing.directPrintPdf(
        printer: myPrinter,
        onLayout: (PdfPageFormat format) async => doc.save(),
        usePrinterSettings: true,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Enviado a ${myPrinter.name}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _MesasAgrupadasView extends StatelessWidget {
  final List<Mesa> mesas;

  const _MesasAgrupadasView({required this.mesas});

  @override
  Widget build(BuildContext context) {
    // 1. AGRUPAR MESAS POR ZONA
    final Map<String, List<Mesa>> mesasPorZona = {};
    for (var mesa in mesas) {
      final zona = mesa.nombreZona ?? 'Sin Zona';
      if (!mesasPorZona.containsKey(zona)) {
        mesasPorZona[zona] = [];
      }
      mesasPorZona[zona]!.add(mesa);
    }

    final zonasOrdenadas = mesasPorZona.keys.toList()..sort();

    // 2. CONSTRUIR LA VISTA
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomScrollView(
        slivers: [
          for (var zona in zonasOrdenadas) ...[
            // CABECERA DE LA ZONA
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  children: [
                    Container(
                      width: 4, 
                      height: 24, 
                      color: Colors.redAccent, 
                      margin: const EdgeInsets.only(right: 8)
                    ),
                    Text(
                      zona.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: Text(
                        '${mesasPorZona[zona]!.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
              ),
            ),

            // REJILLA DE MESAS DE ESA ZONA
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200, 
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1, 
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final mesa = mesasPorZona[zona]![index];
                  return _MesaCard(mesa: mesa);
                },
                childCount: mesasPorZona[zona]!.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _MesaCard extends StatelessWidget {
  final Mesa mesa;

  const _MesaCard({required this.mesa});

  // Función helper para bloquear mesa
  Future<bool> _intentarBloquearMesa(BuildContext context, int mesaId) async {
    try {
      final supabase = Supabase.instance.client;

      // Intentar actualización condicional: solo actualiza si está libre
      final resultado = await supabase
          .from('mesas')
          .update({'estado': 'en_uso_temporal'})
          .eq('id', mesaId)
          .eq('estado', 'libre')
          .select();

      if (resultado.isEmpty) {
        // Otra persona ya la tomó
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Otro usuario ya está tomando pedido en esta mesa'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esLibre = mesa.estado == 'libre';
    final bool tieneInfoLlevar = !esLibre && mesa.clienteActivo != null && mesa.clienteActivo!.isNotEmpty;
    //final colorFondo = esLibre ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final colorBorde = esLibre ? Colors.green[600] : Colors.red[600];
    final colorIcono = esLibre ? Colors.green[700] : Colors.red[700];
    Color colorFondo = esLibre ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    String tiempoRestanteTexto = '';
    Color colorTiempo = Colors.grey;
    if (tieneInfoLlevar && mesa.horaRecojo != null) {
      final diff = mesa.horaRecojo!.difference(DateTime.now());
      if (diff.isNegative) {
        tiempoRestanteTexto = '¡RETRASADO!';
        colorTiempo = Colors.red;
        colorFondo = Colors.red[50]!; // Alerta visual
      } else {
        final horas = diff.inHours;
        final minutos = diff.inMinutes % 60;
        tiempoRestanteTexto = horas > 0 ? '${horas}h ${minutos}m' : '${minutos} min';
        
        if (diff.inMinutes < 10) colorTiempo = Colors.orange[800]!; // Urgente
        else colorTiempo = Colors.green[800]!;
      }
    }
    return Card(
      elevation: 2,
      color: colorFondo,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorBorde!, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          // Navegación segura usando GoRouter con bloqueo concurrente
          if (esLibre) {
            // BLOQUEO: Intentar marcar la mesa como ocupada antes de entrar
            final mesaActualizada = await _intentarBloquearMesa(context, mesa.id);
            if (mesaActualizada && context.mounted) {
              context.go('/pedido/${mesa.id}');
            }
          } else {
            context.go('/detalle-mesa/${mesa.id}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    tieneInfoLlevar ? Icons.shopping_bag : Icons.table_restaurant, 
                    size: 20, 
                    color: Colors.grey[700]
                  ),
                  if (tiempoRestanteTexto.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                      child: Text(tiempoRestanteTexto, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorTiempo)),
                    ),
                ],
              ),
              
              // CONTENIDO CENTRAL (Número o Nombre)
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      // AQUÍ ESTÁ EL CAMBIO VISUAL:
                      tieneInfoLlevar ? mesa.clienteActivo! : mesa.numero,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: tieneInfoLlevar ? 20 : 28, // Texto más pequeño si es nombre largo
                        color: Colors.blueGrey[800],
                      ),
                    ),
                  ),
                ),
              ),

              // PIE (Zona u Hora)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: tieneInfoLlevar && mesa.horaRecojo != null
                  ? Row(
                      children: [
                        const Icon(Icons.access_time_filled, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('HH:mm').format(mesa.horaRecojo!),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    )
                  : Text(mesa.nombreZona ?? '', style: const TextStyle(fontSize: 10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}