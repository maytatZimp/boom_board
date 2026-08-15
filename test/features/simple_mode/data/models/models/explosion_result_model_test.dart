import 'package:boom_board/features/simple_mode/data/models/models/explosion_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/fixtures.dart';

void main() {
  group('ExplosionResultModel.fromJson', () {
    test('reads a hit with a victim', () {
      final model = ExplosionResultModel.fromJson(
        explosionJson(bomberId: 'p-1', victimId: 'p-2', isHit: true, x: 6, y: 2),
      );

      expect(model.bomberId, 'p-1');
      expect(model.victimId, 'p-2');
      expect(model.isHit, isTrue);
      expect(model.x, 6);
      expect(model.y, 2);
    });

    test('reads a miss with a null victim', () {
      final model = ExplosionResultModel.fromJson(explosionJson(isHit: false));

      expect(model.isHit, isFalse);
      expect(model.victimId, isNull);
    });

    test('tolerates an absent victimId key, since the field is nullable', () {
      final json = explosionJson()..remove('victimId');

      expect(ExplosionResultModel.fromJson(json).victimId, isNull);
    });

    test('throws when bomberId is absent', () {
      final json = explosionJson()..remove('bomberId');

      expect(() => ExplosionResultModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws when isHit is absent', () {
      final json = explosionJson()..remove('isHit');

      expect(() => ExplosionResultModel.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
