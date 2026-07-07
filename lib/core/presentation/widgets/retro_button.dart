import 'package:boom_board/core/style/app_colors.dart';
import 'package:flutter/material.dart';

class RetroButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final Color? textColor;

  const RetroButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color = retroPaleBlue,
    this.textColor,
  });

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  bool get _isDisabled => widget.onPressed == null;

  @override
  Widget build(BuildContext context) {
    // Visually dim the button if disabled, otherwise use the normal color
    final baseColor = _isDisabled ? Colors.grey.shade800 : widget.color;

    // Handle the hover color (only lighten if NOT disabled)
    final displayColor = (_isHovered && !_isDisabled) ? baseColor.withAlpha(204) : baseColor;

    // Handle the "pushed down" shadow effect (only push down if NOT disabled)
    final double shadowOffset = (_isPressed && !_isDisabled) ? 0 : 6;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      // Change the cursor Normal arrow if disabled, Pointing hand if active.
      cursor: _isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) {
          if (!_isDisabled) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (!_isDisabled) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (!_isDisabled) setState(() => _isPressed = false);
        },
        onTap: widget.onPressed,
        // Transform translates the button down and right when pressed
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          margin: EdgeInsets.only(top: 6 - shadowOffset, bottom: shadowOffset),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: displayColor,
            border: Border.all(
              color: _isDisabled ? Colors.grey.shade600 : Colors.black,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black,
                // The shadow shrinks when pressed to look like it's moving down
                offset: Offset(shadowOffset, shadowOffset),
              ),
            ],
          ),
          // FittedBox lets the label shrink instead of wrapping mid-word
          // when the button sits in a narrow container (e.g. a slim
          // dashboard on a small landscape phone).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.textColor ?? Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
