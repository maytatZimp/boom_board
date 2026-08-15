import 'package:boom_board/features/simple_mode/data/models/models/simple_mode_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/fixtures.dart';

void main() {
  group('SimpleModeResultModel.fromJson', () {
    test('reads a ranking row', () {
      final model = SimpleModeResultModel.fromJson(
        resultJson(rank: 3, id: 'p-3', name: 'Cara', isAlive: false, isDisconnected: true),
      );

      expect(model.rank, 3);
      expect(model.id, 'p-3');
      expect(model.name, 'Cara');
      expect(model.isAlive, isFalse);
      expect(model.isDisconnected, isTrue);
    });

    test('throws when rank is absent', () {
      final json = resultJson()..remove('rank');

      expect(() => SimpleModeResultModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when rank arrives as a String', () {
      final json = resultJson();
      json['rank'] = '1';

      expect(() => SimpleModeResultModel.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
