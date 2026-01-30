import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/models/producto_model.dart';
import 'providers/admin_productos_provider.dart';
import 'providers/categorias_provider.dart';

class FormularioProductoScreen extends ConsumerStatefulWidget {
  final Producto? productoEditar;
  const FormularioProductoScreen({super.key, this.productoEditar});

  @override
  ConsumerState<FormularioProductoScreen> createState() => _FormularioProductoScreenState();
}

class _FormularioProductoScreenState extends ConsumerState<FormularioProductoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  
  int? _categoriaIdSeleccionada;
  bool _esImprimible = true;
  XFile? _imagenSeleccionada; 
  bool _isLoading = false;

  // NUEVAS VARIABLES DE ESTADO
  String _tipoCarta = 'AMBOS'; // MENU, RESTOBAR, AMBOS
  String _subtipo = 'CARTA';   // ENTRADA, SEGUNDO, CARTA

  @override
  void initState() {
    super.initState();
    if (widget.productoEditar != null) {
      final p = widget.productoEditar!;
      _nombreCtrl.text = p.nombre;
      _descCtrl.text = p.descripcion ?? '';
      _precioCtrl.text = p.precio.toString();
      _categoriaIdSeleccionada = p.categoriaId;
      _esImprimible = p.esImprimible;
      // Cargar valores existentes
      _tipoCarta = p.tipoCarta;
      _subtipo = p.subtipo;
    }
  }

  // ... (El método _pickImage queda igual) ...
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _imagenSeleccionada = pickedFile);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaIdSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una categoría')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(productosRepoProvider);
      final precio = double.tryParse(_precioCtrl.text) ?? 0.0;

      // ACTUALIZAMOS EL MAPA PARA ENVIAR LOS NUEVOS CAMPOS A SUPABASE
      // Nota: Debes actualizar también tu repositorio si usas un método .toMap(), 
      // pero si insertas campo por campo revisa el ProductosRepository.
      
      final nuevoProducto = Producto(
        id: widget.productoEditar?.id ?? 0,
        nombre: _nombreCtrl.text,
        descripcion: _descCtrl.text,
        precio: precio,
        categoriaId: _categoriaIdSeleccionada!,
        esImprimible: _esImprimible,
        imagenUrl: widget.productoEditar?.imagenUrl,
        activo: widget.productoEditar?.activo ?? true,
        // GUARDAMOS LA SELECCIÓN
        tipoCarta: _tipoCarta,
        subtipo: _subtipo,
      );

      // OJO: Asegúrate que tu ProductosRepository en 'crearProducto' y 'actualizarProducto'
      // esté enviando estos campos a Supabase.
      // Aquí asumo que modificaste el repositorio para enviar:
      // 'tipo_carta': producto.tipoCarta,
      // 'subtipo': producto.subtipo
      
      if (widget.productoEditar == null) {
        await repo.crearProducto(nuevoProducto, _imagenSeleccionada);
      } else {
        await repo.actualizarProducto(nuevoProducto, _imagenSeleccionada);
      }

      if (mounted) {
        if (context.canPop()) context.pop(); 
        else context.go('/admin/productos');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado correctamente')));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ... (El método _construirImagenPreview queda igual) ...
  Widget _construirImagenPreview() {
    if (_imagenSeleccionada != null) {
      if (kIsWeb) return Image.network(_imagenSeleccionada!.path, fit: BoxFit.cover); 
      else return Image.file(File(_imagenSeleccionada!.path), fit: BoxFit.cover);
    }
    if (widget.productoEditar?.imagenUrl != null) {
      return Image.network(widget.productoEditar!.imagenUrl!, fit: BoxFit.cover);
    }
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(Icons.add_a_photo, size: 50, color: Colors.grey), Text('Toca para foto')],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.productoEditar == null ? 'Nuevo Producto' : 'Editar Producto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: _construirImagenPreview(),
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre del Plato', prefixIcon: Icon(Icons.restaurant_menu)),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _precioCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio (S/.)', prefixIcon: Icon(Icons.attach_money)),
            ),
            const SizedBox(height: 15),
            
            // --- NUEVOS DROPDOWNS PARA CONFIGURAR MENU ---
            DropdownButtonFormField<String>(
              initialValue: _tipoCarta,
              decoration: const InputDecoration(
                labelText: 'Turno / Carta', 
                prefixIcon: Icon(Icons.access_time), // Le agregué ícono para que se vea mejor
                border: OutlineInputBorder()
              ),
              items: const [
                DropdownMenuItem(value: 'AMBOS', child: Text('Todo el día')),
                DropdownMenuItem(value: 'MENU', child: Text('Solo Menú (Día)')),
                DropdownMenuItem(value: 'RESTOBAR', child: Text('Restobar (Noche)')),
              ],
              onChanged: (val) => setState(() => _tipoCarta = val!),
            ),
            
            const SizedBox(height: 15), // Espacio vertical entre los dos

            DropdownButtonFormField<String>(
              initialValue: _subtipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de Plato', 
                prefixIcon: Icon(Icons.dinner_dining), // Le agregué ícono
                border: OutlineInputBorder()
              ),
              items: const [
                DropdownMenuItem(value: 'CARTA', child: Text('Plato a la Carta')),
                DropdownMenuItem(value: 'ENTRADA', child: Text('Entrada (Menú)')),
                DropdownMenuItem(value: 'SEGUNDO', child: Text('Segundo (Menú)')),
              ],
              onChanged: (val) => setState(() => _subtipo = val!),
            ),
            const SizedBox(height: 15),
            // ---------------------------------------------

            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción', prefixIcon: Icon(Icons.description)),
            ),
            const SizedBox(height: 15),

            categoriasAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (categorias) => DropdownButtonFormField<int>(
                initialValue: _categoriaIdSeleccionada,
                decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.category)),
                items: categorias.map((cat) => DropdownMenuItem(value: cat.id, child: Text(cat.nombre))).toList(),
                onChanged: (val) => setState(() => _categoriaIdSeleccionada = val),
              ),
            ),
            const SizedBox(height: 15),

            SwitchListTile(
              title: const Text('Enviar a Cocina'),
              value: _esImprimible,
              onChanged: (val) => setState(() => _esImprimible = val),
            ),
            const SizedBox(height: 15),

            FilledButton.icon(
              onPressed: _isLoading ? null : _guardar,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
              icon: const Icon(Icons.save),
              label: Text(_isLoading ? 'Guardando...' : 'GUARDAR PRODUCTO'),
            )
          ],
        ),
      ),
    );
  }
}