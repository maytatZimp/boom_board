import 'package:boom_board/core/data/data_source/identity_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'bb_player_id': 'p-1',
      'bb_player_secret': 's-1',
      'bb_room_code': 'ABCD',
      'bb_player_name': 'Ada',
    });
  });

  Future<IdentityStore> loadedStore() async {
    final store = IdentityStore();
    await store.load();
    return store;
  }

  group('IdentityStore.load', () {
    test('reads the persisted slot', () async {
      final store = await loadedStore();

      expect(store.credentials?.playerId, 'p-1');
      expect(store.credentials?.secret, 's-1');
      expect(store.playerId, 'p-1');
      expect(store.roomCode, 'ABCD');
      expect(store.isLoaded, isTrue);
    });

    test('leaves the slot empty when the persisted set is incomplete', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'bb_player_id': 'p-1'});

      final store = await loadedStore();

      expect(store.credentials, isNull);
      expect(store.isLoaded, isTrue);
    });
  });

  group('IdentityStore.clear', () {
    test('drops the in-memory slot before it yields', () async {
      final store = await loadedStore();
      expect(store.credentials, isNotNull);

      // Deliberately not awaited, because the app does not await it either:
      // LeaveRoomUseCase's callers push the home route on the very next
      // synchronous line, and HomeController reads this slot while it builds.
      // So the in-memory drop has to land before clear() suspends -- persisting
      // can finish whenever it likes.
      final pending = store.clear();

      expect(
        store.credentials,
        isNull,
        reason: 'an await above `_cached = null` would silently restore the '
            '"Rejoin room XXXX?" prompt for the room the player just left',
      );

      await pending;
    });

    test('also removes the persisted keys', () async {
      final store = await loadedStore();
      await store.clear();

      // A fresh store is the only way to prove the write went through rather
      // than just the in-memory copy being dropped.
      final reloaded = await loadedStore();
      expect(reloaded.credentials, isNull);
    });
  });

  group('IdentityStore.credentialsFor', () {
    test('hands the slot back for the room it belongs to, case-insensitively', () async {
      final store = await loadedStore();

      expect(store.credentialsFor('ABCD')?.playerId, 'p-1');
      expect(store.credentialsFor('abcd')?.playerId, 'p-1');
    });

    test('withholds it from every other room, so the server mints a fresh identity', () async {
      final store = await loadedStore();

      expect(store.credentialsFor('WXYZ'), isNull);
    });

    test('returns null once the slot is cleared', () async {
      final store = await loadedStore();
      await store.clear();

      expect(store.credentialsFor('ABCD'), isNull);
    });
  });
}
