import 'package:boom_board/core/data/models/coordinate.dart';
import 'package:boom_board/features/simple_mode/data/models/models/simple_mode_result_model.dart';

class GameOverModel {
  final List<SimpleModeResultModel> ranking;
  // Absent when the game ends with no living winner (e.g. the disconnect that
  // ends the game leaves nobody alive). Parse defensively so a missing value
  // does not throw and silently drop the whole gameOver event.
  final Coordinate? winnerPosition;

  GameOverModel({
    required this.ranking,
    this.winnerPosition,
  });

  static GameOverModel fromJson(Map<String, dynamic> json) {
    final List<SimpleModeResultModel> ranking = [];
    for (final player in json['ranking']) {
      ranking.add(SimpleModeResultModel.fromJson(player));
    }
    final winnerPositionJson = json['winnerPosition'];
    final Coordinate? coordinate = winnerPositionJson == null
        ? null
        : Coordinate.fromJson(winnerPositionJson);

    return GameOverModel(
      ranking: ranking,
      winnerPosition: coordinate,
    );
  }
}
