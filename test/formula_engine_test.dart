import 'package:ci_quality_group/features/form_builder/domain/formula_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormulaEngine', () {
    test('multiplica dos campos numéricos', () {
      expect(
        FormulaEngine.evaluate('{a} * {b}', {'a': 3, 'b': 4}),
        12,
      );
    });

    test('precedencia: multiplicación antes que suma', () {
      expect(
        FormulaEngine.evaluate('{a} + {b} * 2', {'a': 1, 'b': 5}),
        11,
      );
    });

    test('paréntesis cambian la precedencia', () {
      expect(
        FormulaEngine.evaluate('({a} + {b}) * 2', {'a': 1, 'b': 5}),
        12,
      );
    });

    test('decimales con coma se aceptan (vienen del formulario)', () {
      expect(
        FormulaEngine.evaluate('{a} * {b}', {'a': '2,5', 'b': 4}),
        10,
      );
    });

    test('campo faltante devuelve null en vez de crashear', () {
      expect(
        FormulaEngine.evaluate('{a} * {b}', {'a': 3}),
        isNull,
      );
    });

    test('campo no-numérico devuelve null', () {
      expect(
        FormulaEngine.evaluate('{a} * {b}', {'a': 'abc', 'b': 2}),
        isNull,
      );
    });

    test('división por cero devuelve null', () {
      expect(
        FormulaEngine.evaluate('{a} / {b}', {'a': 10, 'b': 0}),
        isNull,
      );
    });

    test('negativos vía operador unario', () {
      expect(
        FormulaEngine.evaluate('-{a} + {b}', {'a': 5, 'b': 8}),
        3,
      );
    });

    test('whitespace mixto (tab/espacio) no rompe el parser', () {
      expect(
        FormulaEngine.evaluate('  {a} \t* \n{b}  ', {'a': 6, 'b': 7}),
        42,
      );
    });

    test('fórmula vacía devuelve null', () {
      expect(FormulaEngine.evaluate('', {}), isNull);
    });
  });
}
