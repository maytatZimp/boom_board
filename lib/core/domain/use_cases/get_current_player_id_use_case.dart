import 'package:boom_board/core/data/data_source/identity_store.dart';

/// The local player's stable id.
///
/// Reads the persisted credential slot rather than `socket.id`: the socket id
/// rotates on every reconnect, so anything keyed on it (is-this-me, am-I-host,
/// which avatar is mine) would break the moment the connection blipped.
class GetCurrentPlayerIdUseCase {
  final IdentityStore identityStore;

  GetCurrentPlayerIdUseCase({required this.identityStore});

  String? call() {
    return identityStore.playerId;
  }
}
