import 'package:boom_board/core/presentation/widgets/retro_button.dart';
import 'package:boom_board/core/style/app_colors.dart';
import 'package:flutter/material.dart';

/// Offered on a fresh app load when a credential slot is still on disk.
///
/// Deliberately an explicit one-tap choice rather than a silent auto-rejoin:
/// the stored room may be long finished, and dropping the user straight back
/// into a game they thought they'd left would be worse than asking.
class RejoinPanel extends StatelessWidget {
  final String roomCode;
  final String playerName;
  final Function() onRejoinPressed;
  final Function() onDismissPressed;
  final String? errorText;

  const RejoinPanel({
    super.key,
    required this.roomCode,
    required this.playerName,
    required this.onRejoinPressed,
    required this.onDismissPressed,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: retroBackground,
        border: Border.all(color: retroYellow, width: 4),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(8, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rejoin room\n$roomCode?',
            textAlign: TextAlign.center,
            style: const TextStyle(color: retroYellow, fontSize: 24, height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'as $playerName',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 16),
            Text(
              errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: retroRed, fontSize: 14),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RetroButton(
                text: 'Rejoin',
                color: retroGreen,
                onPressed: onRejoinPressed,
              ),
              RetroButton(
                text: 'Dismiss',
                color: retroRed,
                onPressed: onDismissPressed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
