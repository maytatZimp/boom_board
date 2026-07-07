import 'dart:async';

import 'package:flutter/material.dart';

class RetroLoadingText extends StatefulWidget {
  final String text;
  final Color color;
  final double? fontSize;

  const RetroLoadingText({
    super.key,
    this.text = 'LOADING',
    this.color = Colors.white,
    this.fontSize,
  });

  @override
  State<RetroLoadingText> createState() => _RetroLoadingTextState();
}

class _RetroLoadingTextState extends State<RetroLoadingText> {
  int _dotCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Update the dots every 500 milliseconds (half a second)
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4; // Cycles: 0, 1, 2, 3
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always render all 3 dots so the text's width never changes; dots not
    // yet "on" are painted transparent instead of being replaced by spaces,
    // since trailing spaces don't count towards line-wrap width and would
    // let the widget silently overflow until the 3-dot frame revealed it.
    // FittedBox + maxLines/softWrap then guarantee it stays on one line even
    // if it still doesn't fit, instead of wrapping and shifting layout below.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: widget.text),
            for (var i = 0; i < 3; i++)
              TextSpan(
                text: '.',
                style: i < _dotCount ? null : const TextStyle(color: Colors.transparent),
              ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: widget.color,
          fontWeight: FontWeight.bold,
          fontSize: widget.fontSize ?? 24,
        ),
      ),
    );
  }
}
