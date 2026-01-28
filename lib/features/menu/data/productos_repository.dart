// BORRAMOS: import 'dart:io'; (Esto es veneno para la web)
import 'dart:typed_data'; // Para manejar bytes (Uint8List)
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cross_file/cross_file.dart'; // O usa 'package:image_picker/image_picker.dart'
import '../../../shared/models/producto_model.dart';
import 'dart:io' show Platform; // Importación condicional segura (solo usamos Platform si no es web)

class ProductosRepository {
  final _supabase = Supabase.instance.client;

  // LEER
  Future<List<Producto>> getProductos() async {
    final data = await _supabase.from('productos').select().order('nombre');
    return (data as List).map((json) => Producto.fromJson(json)).toList();
  }

  // MÉTODO BLINDADO: Funciona en Web, Windows y Móvil
  Future<String> _subirYOptimizarImagen(XFile xfile, int productoId) async {
    try {
      Uint8List bytesSubida;
      String extension = xfile.path.split('.').last.toLowerCase();
      // En web a veces el path no tiene extensión clara, asumimos jpg por defecto si falla
      if (extension.isEmpty || extension.length > 4) extension = 'jpeg';
      if (extension == 'jpg') extension = 'jpeg';

      // 1. LÓGICA DE COMPRESIÓN (Separada por plataforma)
      
      // CASO WEB: No comprimimos (o usamos lógica web específica), subimos directo los bytes
      if (kIsWeb) {
        bytesSubida = await xfile.readAsBytes();
      } 
      // CASO MÓVIL (Android/iOS Nativos): Comprimimos para ahorrar datos
      else if (Platform.isAndroid || Platform.isIOS) {
        final Uint8List bytesOriginales = await xfile.readAsBytes();
        
        // Comprimimos usando bytes, no path (más seguro)
        final compressed = await FlutterImageCompress.compressWithList(
          bytesOriginales,
          minWidth: 800,
          minHeight: 800,
          quality: 80,
          format: CompressFormat.jpeg,
        );
        bytesSubida = compressed;
      } 
      // CASO WINDOWS/DESKTOP: Subimos tal cual (la librería de compresión a veces falla en desktop)
      else {
        bytesSubida = await xfile.readAsBytes();
      }

      // 2. Nombre Estático
      final path = 'platos/producto_$productoId.$extension';

      // 3. Subir (UploadBinary funciona igual en todas las plataformas)
      await _supabase.storage.from('menu-images').uploadBinary(
        path,
        bytesSubida,
        fileOptions: FileOptions(upsert: true, contentType: 'image/$extension'),
      );

      // 4. Retornar URL
      final url = _supabase.storage.from('menu-images').getPublicUrl(path);
      return '$url?t=${DateTime.now().millisecondsSinceEpoch}';

    } catch (e) {
      debugPrint("Error subiendo imagen: $e");
      throw Exception('Error procesando imagen: $e');
    }
  }

  // CREAR (Recibe XFile en vez de File)
  Future<void> crearProducto(Producto producto, XFile? imagenFile) async {
    final res = await _supabase.from('productos').insert({
      'nombre': producto.nombre,
      'descripcion': producto.descripcion,
      'precio': producto.precio,
      'categoria_id': producto.categoriaId,
      'es_imprimible': producto.esImprimible,
      'activo': true,
      'imagen_url': null,
      'tipo_carta': producto.tipoCarta, 
      'subtipo': producto.subtipo,
    }).select().single();

    final nuevoId = res['id'];

    if (imagenFile != null) {
      final url = await _subirYOptimizarImagen(imagenFile, nuevoId);
      await _supabase.from('productos').update({'imagen_url': url}).eq('id', nuevoId);
    }
  }

  // ACTUALIZAR (Recibe XFile en vez de File)
  Future<void> actualizarProducto(Producto producto, XFile? nuevaImagen) async {
    String? urlFinal = producto.imagenUrl;

    if (nuevaImagen != null) {
      urlFinal = await _subirYOptimizarImagen(nuevaImagen, producto.id);
    }

    await _supabase.from('productos').update({
      'nombre': producto.nombre,
      'descripcion': producto.descripcion,
      'precio': producto.precio,
      'categoria_id': producto.categoriaId,
      'es_imprimible': producto.esImprimible,
      'imagen_url': urlFinal,
      'tipo_carta': producto.tipoCarta,
      'subtipo': producto.subtipo,
    }).eq('id', producto.id);
  }

  // DESACTIVAR
  Future<void> desactivarProducto(int id) async {
    await _supabase.from('productos').update({'activo': false}).eq('id', id);
  }

  // CAMBIAR ESTADO (Stock rápido)
  Future<void> toggleActivo(int id, bool nuevoEstado) async {
    await _supabase.from('productos').update({'activo': nuevoEstado}).eq('id', id);
  }

  // ELIMINAR (Asegúrate de no usar dart:io aquí tampoco si tenías lógica rara)
   Future<void> eliminarProducto(int id, String? imagenUrl) async {
    if (imagenUrl != null) {
      try {
        final path = imagenUrl.split('/menu-images/').last;
        await _supabase.storage.from('menu-images').remove([path]);
      } catch (e) {
        debugPrint('Error borrando imagen: $e');
      }
    }
    await _supabase.from('productos').delete().eq('id', id);
  }
}