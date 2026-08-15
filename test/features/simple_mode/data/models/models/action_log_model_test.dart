import 'package:boom_board/features/simple_mode/data/models/enum/log_action_type.dart';
import 'package:boom_board/features/simple_mode/data/models/models/action_log_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/fixtures.dart';

void main() {
  group('ActionLogModel.fromJson', () {
    test('reads a log entry and maps its type', () {
      final model = ActionLogModel.fromJson(
        actionLogJson(id: 'log-7', type: 'PLAYER_ELIMINATED'),
      );

      expect(model.id, 'log-7');
      expect(model.type, LogActionType.playerEliminated);
      expect(model.data, <String, dynamic>{'x': 3, 'y': 4});
    });

    test('converts the epoch-millis timestamp without shifting the instant', () {
      // Compare epoch millis, not the DateTime: fromMillisecondsSinceEpoch
      // builds a local-time value, so a field-by-field assertion would pass on
      // a dev machine and fail on CI running in UTC.
      final model = ActionLogModel.fromJson(actionLogJson(timestamp: 1700000000000));

      expect(model.timestamp.millisecondsSinceEpoch, 1700000000000);
    });

    test('propagates the enum failure for an unknown log type', () {
      expect(
        () => ActionLogModel.fromJson(actionLogJson(type: 'PLAYER_TAUNTED')),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the timestamp is absent', () {
      final json = actionLogJson()..remove('timestamp');

      expect(() => ActionLogModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('accepts an empty data payload', () {
      final model = ActionLogModel.fromJson(actionLogJson(data: <String, dynamic>{}));

      expect(model.data, isEmpty);
    });
  });
}
