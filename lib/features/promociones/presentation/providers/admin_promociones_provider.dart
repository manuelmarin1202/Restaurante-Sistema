import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modelo simplificado para la administración de promociones
class PromocionAdmin {
  final int id;
  final String nombre;
  final String? descripcion;
  final String tipoPromocion;
  final bool activo;
  final String? horaInicio;
  final String? horaFin;
  final List<String>? diasAplicables;
  final double? precioCombo;
  final int? cantidadItems;
  final String? tipoCarta;

  PromocionAdmin({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.tipoPromocion,
    required this.activo,
    this.horaInicio,
    this.horaFin,
    this.diasAplicables,
    this.precioCombo,
    this.cantidadItems,
    this.tipoCarta,
  });

  factory PromocionAdmin.fromJson(Map<String, dynamic> json) {
    return PromocionAdmin(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      tipoPromocion: json['tipo_promocion'] as String? ?? 'precio_simple',
      activo: json['activo'] as bool? ?? false,
      horaInicio: json['hora_inicio'] as String?,
      horaFin: json['hora_fin'] as String?,
      diasAplicables: json['dias_aplicables'] != null
          ? List<String>.from(json['dias_aplicables'] as List)
          : null,
      precioCombo: json['precio_combo'] != null
          ? (json['precio_combo'] as num).toDouble()
          : null,
      cantidadItems: json['cantidad_items'] as int?,
      tipoCarta: json['tipo_carta'] as String?,
    );
  }

  PromocionAdmin copyWith({bool? activo}) {
    return PromocionAdmin(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      tipoPromocion: tipoPromocion,
      activo: activo ?? this.activo,
      horaInicio: horaInicio,
      horaFin: horaFin,
      diasAplicables: diasAplicables,
      precioCombo: precioCombo,
      cantidadItems: cantidadItems,
      tipoCarta: tipoCarta,
    );
  }
}

/// Notifier para manejar la lista de promociones
class PromocionesAdminNotifier extends AsyncNotifier<List<PromocionAdmin>> {
  @override
  Future<List<PromocionAdmin>> build() async {
    return _cargarPromociones();
  }

  Future<List<PromocionAdmin>> _cargarPromociones() async {
    final supabase = Supabase.instance.client;

    final data = await supabase
        .from('promociones')
        .select()
        .order('nombre');

    return (data as List)
        .map((json) => PromocionAdmin.fromJson(json))
        .toList();
  }

  /// Cambia el estado activo de una promoción
  Future<void> toggleActivo(int promocionId, bool nuevoEstado) async {
    // Marcar como actualizando
    ref.read(promocionUpdatingProvider(promocionId).notifier).state = true;

    try {
      final supabase = Supabase.instance.client;

      await supabase
          .from('promociones')
          .update({'activo': nuevoEstado})
          .eq('id', promocionId);

      // Actualizar estado local optimistamente
      state = state.whenData((promociones) {
        return promociones.map((p) {
          if (p.id == promocionId) {
            return p.copyWith(activo: nuevoEstado);
          }
          return p;
        }).toList();
      });

    } catch (e) {
      // En caso de error, recargar desde la BD
      state = await AsyncValue.guard(() => _cargarPromociones());
      rethrow;
    } finally {
      ref.read(promocionUpdatingProvider(promocionId).notifier).state = false;
    }
  }
}

/// Provider principal de promociones para admin
final promocionesAdminProvider =
    AsyncNotifierProvider<PromocionesAdminNotifier, List<PromocionAdmin>>(
  () => PromocionesAdminNotifier(),
);

/// Provider para rastrear qué promoción se está actualizando
final promocionUpdatingProvider = StateProvider.family<bool, int>((ref, id) => false);
