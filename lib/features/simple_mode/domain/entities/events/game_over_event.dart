import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/features/simple_mode/domain/entities/simple_mode_result_entity.dart';

class GameOverEvent {
  final List<SimpleModeResultEntity> ranking;
  // Null when the game ended with no living winner (e.g. every remaining
  // player left/died), so the client must tolerate its absence.
  final Coordinate? winnerPosition;

  GameOverEvent({
    required this.ranking,
    this.winnerPosition,
  });

  @override
  String toString() {
    return 'GameOverEvent ranking: $ranking, winnerPosition: $winnerPosition';
  }
}
