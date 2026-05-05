import 'dart:math' as math;

/// Normaliza un string para comparaciones tolerantes:
///  - trim de espacios al inicio/final
///  - lowercase
///  - colapsa múltiples espacios internos en uno
///  - quita acentos comunes (á → a, ñ → n, etc.)
///
/// Útil para detectar duplicados por errores de digitación: "Erick Barragan"
/// y "erick  barragán" terminan iguales.
String normalizeForMatch(String s) {
  var t = s.trim().toLowerCase();
  const replacements = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n',
  };
  replacements.forEach((from, to) => t = t.replaceAll(from, to));
  // Colapsa runs de whitespace.
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

/// Variante "agresiva" de normalización que además elimina TODOS los
/// espacios. Sirve para comparar "jhon san juan" vs "jhon sanjuan", donde
/// la diferencia es solo si pegan o no las palabras.
String normalizeAggressive(String s) =>
    normalizeForMatch(s).replaceAll(' ', '');

/// Devuelve el valor canónico (de [existing]) que coincide exactamente con
/// [input] tras normalizar (case/espacios/acentos). `null` si no hay match.
///
/// Ejemplo: input="erick BARRAGAN", existing=["Erick Barragan"]
/// → devuelve "Erick Barragan".
String? canonicalMatch(String input, Iterable<String> existing) {
  if (input.trim().isEmpty) return null;
  final ni = normalizeForMatch(input);
  for (final v in existing) {
    if (normalizeForMatch(v) == ni) return v;
  }
  return null;
}

/// Distancia de Levenshtein clásica entre dos strings: mínimo de
/// inserciones/deleciones/sustituciones para convertir [a] en [b].
///
/// Implementación O(|a|·|b|) con un solo array de tamaño |b|+1, que sobra
/// para los strings cortos (≤ 50 chars típicos en cliente/recibe).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final m = a.length;
  final n = b.length;
  final prev = List<int>.generate(n + 1, (i) => i);
  final curr = List<int>.filled(n + 1, 0);

  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    for (var j = 0; j <= n; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[n];
}

/// Devuelve el valor de [existing] más parecido a [input] dentro de cierto
/// umbral de "diferencia". Sirve para sugerencias del estilo "¿quisiste
/// decir 'Erick Barragan'?" cuando el usuario escribió "Erik Baragan".
///
/// Reglas:
///  - Compara strings normalizados (case/espacios/acentos no penalizan).
///  - También considera la versión "aggressive" sin espacios para detectar
///    "jhon sanjuan" vs "jhon san juan" como cercanos.
///  - Devuelve `null` si nada está dentro del umbral.
///  - El umbral es proporcional al largo: ~25% de la longitud máxima, con
///    un mínimo de 1 (siempre captura typos de 1 letra) y máximo de 4.
///
/// IMPORTANTE: si hay un [canonicalMatch] exacto, devuelve ese (distancia 0).
String? closestMatch(String input, Iterable<String> existing) {
  final exact = canonicalMatch(input, existing);
  if (exact != null) return exact;

  final ni = normalizeForMatch(input);
  final niAgg = normalizeAggressive(input);
  if (ni.isEmpty) return null;

  final threshold = math.max(1, math.min(4, (ni.length * 0.25).ceil()));

  String? best;
  int bestDist = threshold + 1; // estrictamente mejor que el umbral
  for (final v in existing) {
    final nv = normalizeForMatch(v);
    final nvAgg = normalizeAggressive(v);
    final dist = math.min(
      levenshtein(ni, nv),
      levenshtein(niAgg, nvAgg),
    );
    if (dist < bestDist) {
      bestDist = dist;
      best = v;
    }
  }
  return best;
}
