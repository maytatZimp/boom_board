import 'package:boom_board/core/presentation/controllers/home_controller.dart';
import 'package:boom_board/core/presentation/models/enums/home_panel_type.dart';
import 'package:boom_board/core/presentation/widgets/home_background_anim.dart';
import 'package:boom_board/core/presentation/widgets/host_panel.dart';
import 'package:boom_board/core/presentation/widgets/join_panel.dart';
import 'package:boom_board/core/presentation/utils/responsive.dart';
import 'package:boom_board/core/presentation/widgets/retro_loading_text.dart';
import 'package:boom_board/core/presentation/widgets/start_panel.dart';
import 'package:boom_board/core/style/app_colors.dart';
import 'package:boom_board/features/simple_mode/presentation/widgets/animated_tagline.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logoFontSize = clampedFraction(MediaQuery.of(context).size.width, 0.11, min: 32, max: 48);

    return Scaffold(
      backgroundColor: retroBackground,
      body: Stack(
        children: [
          const HomeBackgroundAnim(),

          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Push the logo down from the top of the screen (e.g., 15% of screen height)
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  // --- LOGO AREA ---
                  // TODO: Replace this Text with Image.asset('assets/logo.png') later
                  Container(
                    padding: const EdgeInsets.only(
                      left: 36,
                      right: 24,
                      top: 16,
                      bottom: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Text(
                      'BOOM\nBOARD',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: logoFontSize,
                        height: 1.1,
                        letterSpacing: logoFontSize / 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // The Silent Tutorial Tagline
                  const AnimatedTagline(),
                  const SizedBox(height: 60),

                  // --- CONNECTION STATUS ---
                  GetBuilder<HomeController>(
                    id: HomeIds.connectingIndicator,
                    builder: (ctl) {
                      if (ctl.isConnecting) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: RetroLoadingText(
                            text: 'Connecting',
                            color: retroYellow,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  GetBuilder<HomeController>(
                    id: HomeIds.connectErrorText,
                    builder: (ctl) {
                      if (!ctl.connectedToServer && !ctl.isConnecting) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(
                            'SERVER OFFLINE',
                            style: TextStyle(
                              color: retroRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // --- INTERACTIVE PANELS ---
                  GetBuilder<HomeController>(
                    id: HomeIds.panel,
                    builder: (ctl) {
                      // Disable panels if not connected
                      if (!ctl.connectedToServer) return const SizedBox.shrink();

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                          return Stack(
                            alignment: Alignment
                                .topCenter, // Locks the children to the top so that when children size changed the widget doesn't move around
                            children: <Widget>[
                              ...previousChildren,
                              ?currentChild,
                            ],
                          );
                        },
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          // A quick scale and fade effect
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: _buildCurrentPanel(ctl),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // --- VERSION TEXT (Bottom Right Corner) ---
          Positioned(
            bottom: 16,
            right: 16,
            child: Text(
              'v0.1.1',
              style: TextStyle(
                color: Colors.white.withAlpha(128),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPanel(HomeController ctl) {
    if (ctl.panelType == HomePanelType.start) {
      return StartPanel(
        key: const ValueKey('start_panel'), // REQUIRED for AnimatedSwitcher
        onHostPressed: controller.onHostPressed,
        onJoinPressed: controller.onJoinPressed,
      );
    } else if (ctl.panelType == HomePanelType.host) {
      return HostPanel(
        key: const ValueKey('host_panel'), // REQUIRED for AnimatedSwitcher
        textEditingCtl: controller.playerNameTextFieldCtl,
        onCreatePressed: controller.onCreatePressed,
        onCancelPressed: controller.onCancelPressed,
        errorText: ctl.panelError,
      );
    } else if (ctl.panelType == HomePanelType.join) {
      return JoinPanel(
        key: const ValueKey('join_panel'), // REQUIRED for AnimatedSwitcher
        playerNameTextCtl: controller.playerNameTextFieldCtl,
        roomCodeTextCtl: controller.roomCodeTextFieldCtl,
        onJoinConfirmPressed: controller.onJoinConfirmPressed,
        onCancelPressed: controller.onCancelPressed,
        errorText: ctl.panelError,
      );
    }
    return const SizedBox.shrink(key: ValueKey('empty_panel'));
  }
}
