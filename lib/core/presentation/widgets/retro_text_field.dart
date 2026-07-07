import 'package:boom_board/core/utils/upper_case_text_formatter.dart';
import 'package:flutter/material.dart';

class RetroTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final bool isRoomCode;

  const RetroTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.isRoomCode = false,
  });

  @override
  Widget build(BuildContext context) {
    final fieldWidth = (MediaQuery.of(context).size.width - 32).clamp(200.0, 300.0);

    return Container(
      width: fieldWidth,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(4, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        inputFormatters: isRoomCode ? [UpperCaseTextFormatter()] : null,
        textCapitalization: isRoomCode ? TextCapitalization.characters : TextCapitalization.words,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          counterText: '', // Hides the character counter
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
