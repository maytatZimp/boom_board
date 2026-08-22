import 'package:boom_board/core/events/event_bus.dart';
import 'package:boom_board/core/events/models/page_resumed_event.dart';
import 'package:boom_board/core/utils/page_visibility.dart';

/// Turns browser visibility changes into a [PageResumedEvent] on the app bus.
///
/// Reads the browser directly rather than [AppLifecycleState], because the
/// engine's mapping of visibility onto lifecycle is itself unreliable after a
/// mobile background -- see [FrameWatchdog].
class PageLifecycleNotifier {
  bool _started = false;
  bool _wasHidden = false;

  void start() {
    if (_started) return;
    _started = true;

    addPageVisibilityListener((isVisible) {
      if (!isVisible) {
        _wasHidden = true;
        return;
      }

      // Only a return from hidden is a resume. Plain focus changes leave the
      // page visible throughout and have nothing to catch up on.
      if (!_wasHidden) return;
      _wasHidden = false;

      eventBus.fire(PageResumedEvent());
    });
  }
}
