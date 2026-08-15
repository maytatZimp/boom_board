import 'package:boom_board/core/utils/upper_case_text_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = UpperCaseTextFormatter();

  TextEditingValue format(String oldText, String newText, {int? selection}) {
    return formatter.formatEditUpdate(
      TextEditingValue(text: oldText),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection ?? newText.length),
      ),
    );
  }

  group('UpperCaseTextFormatter', () {
    test('upper-cases the incoming text', () {
      expect(format('abc', 'abcd').text, 'ABCD');
    });

    test('leaves already-upper-case text untouched', () {
      expect(format('ABC', 'ABCD').text, 'ABCD');
    });

    test('handles an empty edit', () {
      expect(format('A', '').text, '');
    });

    test('preserves digits and symbols', () {
      expect(format('', 'a1-b2').text, 'A1-B2');
    });

    test('preserves the caret position', () {
      // Room codes are 4 characters and the formatter runs on every keystroke;
      // a dropped selection would jump the caret to the start mid-typing.
      final result = format('ab', 'abc', selection: 2);

      expect(result.selection.baseOffset, 2);
    });

    test('leaves characters without an upper-case form alone', () {
      expect(format('', '1234').text, '1234');
    });
  });
}
