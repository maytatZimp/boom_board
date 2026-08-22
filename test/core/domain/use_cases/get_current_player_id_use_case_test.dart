import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:boom_board/core/domain/use_cases/get_current_player_id_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockIdentityStore identityStore;
  late GetCurrentPlayerIdUseCase useCase;

  setUp(() {
    identityStore = emptyIdentityStore();
    useCase = GetCurrentPlayerIdUseCase(identityStore: identityStore);
  });

  group('GetCurrentPlayerIdUseCase', () {
    test('returns the persisted player id, not the socket id', () {
      // The whole point of the split: socket ids rotate on every reconnect,
      // so anything keyed on one breaks the moment the connection blips.
      when(() => identityStore.playerId).thenReturn('7f1c-uuid');

      expect(useCase.call(), '7f1c-uuid');
    });

    test('survives a reconnect that hands the client a brand-new socket', () {
      when(() => identityStore.playerId).thenReturn('7f1c-uuid');

      expect(useCase.call(), '7f1c-uuid');
      // Nothing about the socket changed the answer, because nothing about the
      // socket is consulted.
      expect(useCase.call(), '7f1c-uuid');
    });

    test('returns null before this client has entered any room', () {
      // SimpleModeController.localPlayerId turns this null into '', which makes
      // `isHost` false and `localPlayer` null -- so the client renders as a
      // non-host onlooker rather than crashing.
      when(() => identityStore.playerId).thenReturn(null);

      expect(useCase.call(), isNull);
    });

    test('reads through to the store on every call, so a rejoin is picked up', () {
      final responses = <String?>[null, 'fresh-uuid'];
      when(() => identityStore.playerId).thenAnswer((_) => responses.removeAt(0));

      expect(useCase.call(), isNull);
      expect(useCase.call(), 'fresh-uuid');
    });
  });

  group('IdentityStore.credentialsFor', () {
    // Credential scoping is the security-relevant half of the design: creds are
    // never presented to a room this client isn't a member of.
    test('returns the slot only for the room it was saved against', () {
      final store = IdentityStore();

      expect(store.credentialsFor('ABCD'), isNull);
    });
  });
}
