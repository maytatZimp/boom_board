import 'package:boom_board/features/simple_mode/domain/repositories/simple_mode_server_repository.dart';

/// Pulls the authoritative room state down again, without rejoining.
///
/// Used after the page comes back from a background: the phase clock kept
/// draining and rounds may have resolved while nothing was being painted, and
/// unlike a reconnect there is no join to hang a fresh snapshot off.
class RequestSnapshotUseCase {
  final SimpleModeServerRepository simpleModeServerRepository;

  RequestSnapshotUseCase({required this.simpleModeServerRepository});

  Future<void> call() async {
    await simpleModeServerRepository.requestSnapshot();
  }
}
