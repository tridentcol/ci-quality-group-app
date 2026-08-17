import '../domain/material_entry.dart';

/// Resumen agregado de movimientos de material para el dashboard de
/// admin. Se computa por separado para ingreso y para salida (el
/// dashboard filtra la lista por `type` antes de llamar a
/// `compute` dos veces) — acá es agnóstico del tipo, solo agrega "por
/// empresa" usando `counterpartyName` (proveedor o cliente según
/// corresponda).
class MaterialMetrics {
  const MaterialMetrics({
    required this.totalQuantity,
    required this.entryCount,
    required this.commonUnit,
    required this.byCompany,
    required this.byMaterial,
  });

  final num totalQuantity;
  final int entryCount;

  /// Unidad de `totalQuantity`. Solo hay una lista maestra de unidades
  /// hoy (`Kilogramos`), pero si el admin llega a agregar otra, esto
  /// evita mostrar un "kg" fijo cuando el dato real es distinto — si
  /// los movimientos del rango mezclan unidades, queda `null` (el
  /// dashboard entonces no le pone sufijo al total).
  final String? commonUnit;

  /// Empresa (proveedor o cliente) → (# de movimientos = "vagones",
  /// cantidad total). Cubre "3 vagones de San Francisco, total X kg".
  final Map<String, ({int count, num quantity})> byCompany;

  final Map<String, num> byMaterial;

  /// Empresas ordenadas DESC por cantidad, para el card resumen.
  List<({String name, int count, num quantity})> get topCompanies {
    final list = byCompany.entries
        .map(
          (e) => (name: e.key, count: e.value.count, quantity: e.value.quantity),
        )
        .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return list;
  }

  static MaterialMetrics empty() => const MaterialMetrics(
        totalQuantity: 0,
        entryCount: 0,
        commonUnit: null,
        byCompany: {},
        byMaterial: {},
      );

  factory MaterialMetrics.compute(List<MaterialEntry> entries) {
    if (entries.isEmpty) return MaterialMetrics.empty();

    final byCompany = <String, ({int count, num quantity})>{};
    final byMaterial = <String, num>{};
    num totalQuantity = 0;
    String? commonUnit = entries.first.unit;

    for (final e in entries) {
      totalQuantity += e.quantity;
      if (e.unit != commonUnit) commonUnit = null;

      final prevCompany = byCompany[e.counterpartyName];
      byCompany[e.counterpartyName] = (
        count: (prevCompany?.count ?? 0) + 1,
        quantity: (prevCompany?.quantity ?? 0) + e.quantity,
      );

      byMaterial.update(
        e.displayLabel,
        (v) => v + e.quantity,
        ifAbsent: () => e.quantity,
      );
    }

    return MaterialMetrics(
      totalQuantity: totalQuantity,
      entryCount: entries.length,
      commonUnit: commonUnit,
      byCompany: byCompany,
      byMaterial: byMaterial,
    );
  }
}
