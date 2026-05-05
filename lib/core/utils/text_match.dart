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

/// Normalización **fonética** para español. Encima de la normalización
/// estándar (case/acentos/espacios), neutraliza diferencias de spelling
/// que suenan igual al pronunciarse en español, capturando los typos más
/// comunes en nombres propios:
///
///   - 'h' es muda          → "jhon" ≡ "jon", "hilo" ≡ "ilo"
///   - 'v' suena como 'b'   → "barragan" ≡ "varragan"
///   - 'z' = 's' (seseo)    → "perez" ≡ "peres"
///   - 'll' = 'y' (yeísmo)  → "llano" ≡ "yano"
///   - 'x' = 'ks'           → "méxico" ≡ "méksico"
///   - 'c' antes de e/i = s → "ceci" ≡ "sesi", "cinco" ≡ "sinko"
///   - 'c' / 'qu' / 'k' duros → todos a 'k'
///   - 'g' antes de e/i = j → "gente" ≡ "jente"
///   - letras dobles consecutivas → una sola: "barragan" ≡ "baragan"
///
/// Se usa **solo** para sugerencias y matching de duplicados, nunca para
/// guardar el valor — el display siempre conserva el canónico tal cual
/// está escrito en la lista maestra.
String normalizePhonetic(String s) {
  var t = normalizeForMatch(s);
  // Letras mudas / equivalencias fonéticas globales.
  t = t.replaceAll('h', '');
  t = t.replaceAll('v', 'b');
  t = t.replaceAll('z', 's');
  t = t.replaceAll('ll', 'y');
  t = t.replaceAll('x', 'ks');

  // c/qu/g dependen de la siguiente letra. Procesamos char-by-char.
  final buf = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    final next = i + 1 < t.length ? t[i + 1] : '';
    if (c == 'c') {
      // c antes de e/i suena como s; en cualquier otra posición como k.
      buf.write(next == 'e' || next == 'i' ? 's' : 'k');
    } else if (c == 'q' && next == 'u') {
      // qu se pronuncia como k (la u es muda en este contexto).
      final after = i + 2 < t.length ? t[i + 2] : '';
      buf.write(after == 'e' || after == 'i' ? 's' : 'k');
      i++; // consumimos la u
    } else if (c == 'g') {
      // g antes de e/i suena como j; resto se mantiene como g.
      buf.write(next == 'e' || next == 'i' ? 'j' : 'g');
    } else {
      buf.write(c);
    }
  }
  // Colapsa letras dobles consecutivas: "barragan" → "baragan".
  return buf.toString().replaceAll(RegExp(r'(.)\1+'), r'$1');
}

/// Devuelve el valor canónico (de [existing]) que coincide con [input]
/// tras alguna de las normalizaciones — primero strict (case/espacios/
/// acentos) y luego fonética (h muda, b/v iguales, z/s, etc).
///
/// `null` si no hay match. Si hay varios candidatos al mismo nivel, gana
/// el primero según el orden de iteración de [existing].
///
/// Ejemplos:
///   input="erick BARRAGAN", existing=["Erick Barragan"] → "Erick Barragan"
///   input="jhon",           existing=["John"]           → "John"  (fonético)
///   input="varragán",       existing=["Barragan"]       → "Barragan" (fonético)
String? canonicalMatch(String input, Iterable<String> existing) {
  if (input.trim().isEmpty) return null;

  // Match estricto primero (sin riesgo de colisiones falsas).
  final ni = normalizeForMatch(input);
  for (final v in existing) {
    if (normalizeForMatch(v) == ni) return v;
  }

  // Match fonético después: captura typos comunes pero puede tener
  // alguna colisión rara (ej. "casa" ≡ "kasa" ≡ "qaza"). Aceptable
  // para nombres propios de un equipo de 10 personas.
  final pi = normalizePhonetic(input);
  if (pi.isEmpty) return null;
  for (final v in existing) {
    if (normalizePhonetic(v) == pi) return v;
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
/// Computa la distancia de Levenshtein con TRES normalizaciones distintas
/// y se queda con la menor:
///
///  1. **Strict** (case/acentos/espacios)   → captura "Pedro" vs "pedro"
///  2. **Aggressive** (sin espacios)        → captura "san juan" vs "sanjuan"
///  3. **Phonetic** (h muda, b/v, etc)      → captura "jhon" vs "john",
///                                            "barragan" vs "varragán"
///
/// Devuelve `null` si nada está dentro del umbral.
/// El umbral es proporcional al largo: ~25% de la longitud máxima, con
/// un mínimo de 1 (siempre captura typos de 1 letra) y máximo de 4.
///
/// Si hay un [canonicalMatch] exacto (distancia 0 en cualquiera de las
/// normalizaciones), devuelve ese.
String? closestMatch(String input, Iterable<String> existing) {
  final exact = canonicalMatch(input, existing);
  if (exact != null) return exact;

  final ni = normalizeForMatch(input);
  final niAgg = normalizeAggressive(input);
  final niPhon = normalizePhonetic(input);
  if (ni.isEmpty) return null;

  final threshold = math.max(1, math.min(4, (ni.length * 0.25).ceil()));

  String? best;
  int bestDist = threshold + 1; // estrictamente mejor que el umbral
  for (final v in existing) {
    final nv = normalizeForMatch(v);
    final nvAgg = normalizeAggressive(v);
    final nvPhon = normalizePhonetic(v);
    final dist = [
      levenshtein(ni, nv),
      levenshtein(niAgg, nvAgg),
      levenshtein(niPhon, nvPhon),
    ].reduce(math.min);
    if (dist < bestDist) {
      bestDist = dist;
      best = v;
    }
  }
  return best;
}
