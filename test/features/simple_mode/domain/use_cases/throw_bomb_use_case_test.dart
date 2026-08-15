import 'package:boom_board/features/simple_mode/data/models/requests/throw_bomb_request.dart';
import 'package:boom_board/features/simple_mode/domain/use_cases/throw_bomb_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

// StartGameUseCase, SetPositionUseCase and ResetGameUseCase are pure
// pass-throughs -- they build a request and await one repository call, so a
// test there would only assert that a mock was invoked. ThrowBombUseCase is
// the one that actually transforms something: it unwraps the response to a
// nullable throwOrder.
void main() {
  late MockSimpleModeServerRepository repository;
  late ThrowBombUseCase useCase;

  setUpAll(registerTestFallbackValues);

  setUp(() {
    repository = MockSimpleModeServerRepository();
    useCase = ThrowBombUseCase(simpleModeServerRepository: repository);
  });

  group('ThrowBombUseCase', () {
    test('builds the request from the params', () async {
      when(() => repository.throwBomb(any()))
          .thenAnswer((_) async => ThrowBombResponse(throwOrder: 1));

      await useCase.call(ThrowBombParams(roomCode: 'ABCD', x: 4, y: 5));

      final captured = verify(() => repository.throwBomb(captureAny())).captured.single;

      expect((captured as ThrowBombRequest).roomCode, 'ABCD');
      expect(captured.x, 4);
      expect(captured.y, 5);
    });

    test('unwraps the throw order from the response', () async {
      when(() => repository.throwBomb(any()))
          .thenAnswer((_) async => ThrowBombResponse(throwOrder: 3));

      expect(await useCase.call(ThrowBombParams(roomCode: 'ABCD', x: 0, y: 0)), 3);
    });

    test('returns null when the repository returns no response', () async {
      // SimpleModeController.throwBomb writes this straight into
      // copyWith(throwOrder: ...), where null means "no queue position yet".
      when(() => repository.throwBomb(any())).thenAnswer((_) async => null);

      expect(await useCase.call(ThrowBombParams(roomCode: 'ABCD', x: 0, y: 0)), isNull);
    });

    test('propagates a repository error', () async {
      when(() => repository.throwBomb(any())).thenThrow(StateError('offline'));

      await expectLater(
        useCase.call(ThrowBombParams(roomCode: 'ABCD', x: 0, y: 0)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
