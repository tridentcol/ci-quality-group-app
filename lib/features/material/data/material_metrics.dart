import '../domain/material_entry.dart';

/// Resumen agregado de movimientos de material para el dashboard de
/// admin. Se computa por separado para ingreso y para salida (el
/// dashboard filtra la lista por `type` antes de llamar a
/// `compute` dos veces) — acá es agnóstico del tipo, solo agrega "por
/// empresa" usando `counterpartyName` (proveedor o cliente según
/// corresponda).
class MaterialMetrics {
  const MaterialMetrics({
    required this.entryCount,
    required this.quantityByUnit,
    required this.byCompany,
    required this.byMaterial,
  });

  final int entryCount;

  /// Cantidad total, separada por unidad. Solo hay una lista maestra
  /// de unidades hoy (`Kilogramos`), pero si el admin agrega otra, no
  /// se puede sumar "5 Toneladas" + "200 Kilogramos" como si fueran un
  /// solo número — cada unidad se acumula aparte y el dashboard
  /// muestra cada una con su propio sufijo.
  final Map<String, num> quantityByUnit;

  /// Empresa (proveedor o cliente) → (# de movimientos = "vagones",
  /// cantidad total por unidad). Cubre "3 vagones de San Francisco,
  /// total X kg".
  final Map<String, ({int count, Map<String, num> quantityByUnit})> byCompany;

  /// Material → cantidad total por unidad.
  final Map<String, Map<String, num>> byMaterial;

  /// Empresas ordenadas DESC por cantidad total (sumando todas las
  /// unidades solo para efectos de orden — nunca se muestra ese
  /// número mezclado, cada unidad se despliega por separado).
  List<({String name, int count, Map<String, num> quantityByUnit})>
      get topCompanies {
    final list = byCompany.entries
        .map(
          (e) => (
            name: e.key,
            count: e.value.count,
            quantityByUnit: e.value.quantityByUnit,
          ),
        )
        .toList()
      ..sort(
        (a, b) => _sumAllUnits(b.quantityByUnit)
            .compareTo(_sumAllUnits(a.quantityByUnit)),
      );
    return list;
  }

  static num _sumAllUnits(Map<String, num> byUnit) =>
      byUnit.values.fold<num>(0, (a, b) => a + b);

  static Map<String, num> _addUnit(
    Map<String, num> byUnit,
    String unit,
    num quantity,
  ) {
    final updated = Map<String, num>.of(byUnit);
    updated.update(unit, (v) => v + quantity, ifAbsent: () => quantity);
    return updated;
  }

  static MaterialMetrics empty() => const MaterialMetrics(
        entryCount: 0,
        quantityByUnit: {},
        byCompany: {},
        byMaterial: {},
      );

  factory MaterialMetrics.compute(List<MaterialEntry> entries) {
    if (entries.isEmpty) return MaterialMetrics.empty();

    final byCompany =
        <String, ({int count, Map<String, num> quantityByUnit})>{};
    final byMaterial = <String, Map<String, num>>{};
    var quantityByUnit = <String, num>{};

    for (final e in entries) {
      quantityByUnit = _addUnit(quantityByUnit, e.unit, e.quantity);

      final prevCompany = byCompany[e.counterpartyName];
      byCompany[e.counterpartyName] = (
        count: (prevCompany?.count ?? 0) + 1,
        quantityByUnit: _addUnit(
          prevCompany?.quantityByUnit ?? const {},
          e.unit,
          e.quantity,
        ),
      );

      byMaterial[e.displayLabel] = _addUnit(
        byMaterial[e.displayLabel] ?? const {},
        e.unit,
        e.quantity,
      );
    }

    return MaterialMetrics(
      entryCount: entries.length,
      quantityByUnit: quantityByUnit,
      byCompany: byCompany,
      byMaterial: byMaterial,
    );
  }
}
