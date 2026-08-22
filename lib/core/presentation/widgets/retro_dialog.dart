import 'package:boom_board/core/presentation/widgets/retro_button.dart';
import 'package:boom_board/core/style/app_colors.dart';
import 'package:flutter/material.dart';

class RetroDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onConfirm;

  /// Pass null to get an acknowledgement dialog -- a single button, because
  /// there is no question to answer (e.g. "the room is gone").
  final VoidCallback? onCancel;

  const RetroDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    required this.onCancel,
  });

  bool get _isAcknowledgement => onCancel == null;

  /// An acknowledgement reads as "OK"; a confirmation reads as "YES".
  String get _confirmLabel => _isAcknowledgement ? 'OK' : 'YES';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        // maxWidth matters as much as maxHeight: Dialog hands its child loose
        // constraints, so the button Row below (mainAxisSize.max) would take
        // the whole viewport and drag the dialog with it -- on desktop web
        // that meant two ~900pt buttons.
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: retroBackground,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(8, 8))],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: retroRed,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 32),
              if (_isAcknowledgement)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: RetroButton(
                      text: _confirmLabel,
                      color: retroRed,
                      onPressed: onConfirm,
                    ),
                  ),
                )
              else
                // Expanded rather than spaceEvenly so the pair splits the
                // dialog evenly at every width. NO/YES are short enough that
                // spaceEvenly fits too -- this is about balance, not overflow.
                // (The real overflow case is the connection overlay in
                // simple_mode_screen, whose labels are much longer.)
                Row(
                  children: [
                    Expanded(
                      child: RetroButton(
                        text: 'NO',
                        color: retroPaleBlue,
                        onPressed: onCancel,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: RetroButton(
                        text: _confirmLabel,
                        color: retroRed,
                        onPressed: onConfirm,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
