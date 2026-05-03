/// Evaluador minimalista de fórmulas para campos `FieldType.computed`.
///
/// Sintaxis soportada:
///  - `{fieldId}` → valor del campo (lee de `values`).
///  - Operadores binarios `+ - * /`.
///  - Paréntesis.
///  - Números literales (enteros o decimales con `.`).
///
/// Ejemplo: `{quantity} * {unitPrice}`.
///
/// Si la fórmula es inválida o algún campo referenciado no es numérico,
/// devuelve `null` para que la UI muestre "Pendiente".
class FormulaEngine {
  FormulaEngine._();

  static num? evaluate(String formula, Map<String, Object?> values) {
    try {
      final substituted = formula.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) {
          final id = m.group(1)!;
          final raw = values[id];
          final n = _asNum(raw);
          if (n == null) throw const _FormulaError();
          return n.toString();
        },
      );
      final parser = _Parser(substituted);
      final result = parser.parseExpression();
      parser.expectEnd();
      return result;
    } catch (_) {
      return null;
    }
  }

  static num? _asNum(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) {
      final cleaned = raw.replaceAll(',', '.').trim();
      if (cleaned.isEmpty) return null;
      return num.tryParse(cleaned);
    }
    return null;
  }
}

class _FormulaError implements Exception {
  const _FormulaError();
}

/// Parser recursivo de expresiones aritméticas. No es bonito, pero soporta
/// precedencia (* / antes de + -) y paréntesis. Mantenerlo en un archivo
/// para no traer un paquete entero por ~80 líneas.
class _Parser {
  _Parser(this._source) : _pos = 0;

  final String _source;
  int _pos;

  num parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWs();
      if (_pos >= _source.length) break;
      final c = _source[_pos];
      if (c == '+') {
        _pos++;
        value = value + _parseTerm();
      } else if (c == '-') {
        _pos++;
        value = value - _parseTerm();
      } else {
        break;
      }
    }
    return value;
  }

  num _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipWs();
      if (_pos >= _source.length) break;
      final c = _source[_pos];
      if (c == '*') {
        _pos++;
        value = value * _parseFactor();
      } else if (c == '/') {
        _pos++;
        final divisor = _parseFactor();
        if (divisor == 0) throw const _FormulaError();
        value = value / divisor;
      } else {
        break;
      }
    }
    return value;
  }

  num _parseFactor() {
    _skipWs();
    if (_pos >= _source.length) throw const _FormulaError();
    final c = _source[_pos];
    if (c == '(') {
      _pos++;
      final v = parseExpression();
      _skipWs();
      if (_pos >= _source.length || _source[_pos] != ')') {
        throw const _FormulaError();
      }
      _pos++;
      return v;
    }
    if (c == '-') {
      _pos++;
      return -_parseFactor();
    }
    return _parseNumber();
  }

  num _parseNumber() {
    final start = _pos;
    while (_pos < _source.length) {
      final c = _source[_pos];
      if ((c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) || c == '.') {
        _pos++;
      } else {
        break;
      }
    }
    if (start == _pos) throw const _FormulaError();
    final n = num.tryParse(_source.substring(start, _pos));
    if (n == null) throw const _FormulaError();
    return n;
  }

  void _skipWs() {
    while (_pos < _source.length && _isWhitespace(_source.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  static bool _isWhitespace(int code) {
    // Tab, newline, carriage return, espacio.
    return code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
  }

  void expectEnd() {
    _skipWs();
    if (_pos != _source.length) throw const _FormulaError();
  }
}
