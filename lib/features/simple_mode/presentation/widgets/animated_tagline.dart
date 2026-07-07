import 'package:boom_board/core/domain/entities/enums/home_animation_state.dart';
import 'package:boom_board/core/presentation/controllers/home_controller.dart';
import 'package:boom_board/core/style/app_colors.dart';
import 'package:boom_board/gen/fonts.gen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AnimatedTagline extends StatelessWidget {
  const AnimatedTagline({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to the exact same ID that the background uses!
    return GetBuilder<HomeController>(
      id: HomeIds.tagline,
      builder: (ctl) {
        // 1. Define the default dim color
        const dimColor = Colors.white30;

        // 2. Initialize colors to dim
        Color hideColor = dimColor;
        Color surviveColor = dimColor;
        Color destroyColor = dimColor;

        // 3. Highlight specific words based on the current background state
        switch (ctl.currentState) {
          case HomeAnimationState.spawning:
          case HomeAnimationState.repositioning:
            hideColor = retroYellow; // Emphasize hiding during stealth
            break;
          case HomeAnimationState.waiting:
          case HomeAnimationState.attacking:
            surviveColor = retroYellow; // Emphasize survival when the bomb is falling
            break;
          case HomeAnimationState.exploding:
          case HomeAnimationState.celebrating:
            destroyColor = retroYellow; // Emphasize destruction on impact/victory
            break;
          case HomeAnimationState.resetting:
            // Leave all dim while the screen resets
            break;
        }

        // 4. Helper to build the animated words
        Widget buildAnimatedWord(String text, Color color) {
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300), // Smooth fade transition
            style: TextStyle(
              color: color,
              fontFamily: FontFamily.pressStart2P,
              fontSize: 20, // Adjust based on your font
              letterSpacing: 2.0,
              shadows: color == retroYellow
                  ? const [
                      // Add a cool neon glow only to the active word!
                      BoxShadow(color: retroYellow, blurRadius: 10, spreadRadius: 2),
                    ]
                  : null,
            ),
            child: Text(text),
          );
        }

        // 5. Layout the row with dots in between
        // Wrapped in FittedBox so the row shrinks to fit narrow (phone-width)
        // screens instead of overflowing off both edges; it never scales up
        // past its natural size, so desktop is unaffected.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildAnimatedWord('HIDE', hideColor),
                const Text('  >  ', style: TextStyle(color: dimColor, fontSize: 20)),
                buildAnimatedWord('SURVIVE', surviveColor),
                const Text('  >  ', style: TextStyle(color: dimColor, fontSize: 20)),
                buildAnimatedWord('DESTROY', destroyColor),
              ],
            ),
          ),
        );
      },
    );
  }
}
