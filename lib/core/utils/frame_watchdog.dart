import 'dart:async';

import 'package:boom_board/core/utils/high_res_clock.dart';
import 'package:boom_board/core/utils/page_visibility.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

/// What [FrameWatchdog] should do about the pipeline's current state.
enum FrameWatchdogAction {
  /// Healthy, or idle -- which looks identical from the outside and must be
  /// left alone either way.
  none,

  /// Frames are gated off while the page is on screen. Put the lifecycle back
  /// rather than drive frames by hand, so `framesEnabled` is restored for good
  /// instead of one frame at a time.
  resumeLifecycle,

  /// Drive begin/draw by hand -- the only way to clear a stuck
  /// `hasScheduledFrame` from Dart. Note there is no cheaper first attempt to
  /// try against that flag: `scheduleForcedFrame()` ignores the lifecycle gate
  /// but is itself gated on `hasScheduledFrame`, so it can only ever no-op
  /// here.
  pumpFrame,
}

/// Decides what a given pipeline state calls for.
///
/// Pulled out of [FrameWatchdog.check] because this is the part worth being
/// sure about: crying wolf on an idle app means forcing repaints forever, and
/// missing a stall means staying frozen.
FrameWatchdogAction decideFrameWatchdogAction({
  required bool isVisible,
  required bool framesEnabled,
  required bool hasScheduledFrame,
  required Duration sinceLastFrame,
  required Duration stallThreshold,
  required bool recoveryAttempted,
}) {
  // A hidden page is *supposed* to have frames disabled. Forcing one here
  // would request an animation frame that cannot run, which is precisely how
  // the stuck-flag failure mode gets created.
  if (!isVisible) return FrameWatchdogAction.none;

  // scheduleFrame() bailed on !framesEnabled, so it never got as far as
  // recording that a frame was wanted -- the lifecycle is the stuck part.
  final lifecycleStuck = !framesEnabled;

  // scheduleFrame() bailed on hasScheduledFrame instead: the framework asked
  // for a frame and the browser never delivered one.
  final frameStuck = hasScheduledFrame && sinceLastFrame > stallThreshold;

  // Nothing dirty means no frames at all, and `hasScheduledFrame` false with
  // it -- so a quiet board reads as healthy and costs nothing.
  if (!lifecycleStuck && !frameStuck) return FrameWatchdogAction.none;

  // A stuck lifecycle gets one cheap attempt first: putting it back re-enables
  // frames for good, where a pumped frame only ever buys the one.
  if (lifecycleStuck) {
    return recoveryAttempted ? FrameWatchdogAction.pumpFrame : FrameWatchdogAction.resumeLifecycle;
  }

  // A stuck `hasScheduledFrame` has no such attempt to make -- every
  // scheduling call bails on that exact flag -- so `recoveryAttempted` has
  // nothing to distinguish here and the hand pump is the first resort.
  return FrameWatchdogAction.pumpFrame;
}

/// Restarts the render pipeline when the browser strands it.
///
/// Backgrounding mobile Chrome can wedge Flutter web in one of two ways, both
/// of which turn `SchedulerBinding.scheduleFrame()` into a silent no-op:
///
///  * `framesEnabled == false`. The engine derives [AppLifecycleState] from
///    `visibilitychange`/`focus`/`blur`, and the app can be left believing it
///    is still hidden after the page is back on screen. `scheduleFrame()`
///    bails before it even records that a frame was wanted.
///  * `hasScheduledFrame == true`, forever. The `requestAnimationFrame` that
///    was in flight when the tab was frozen is never delivered, so the flag
///    guarding against double-scheduling is never cleared and every later
///    request is dropped as redundant.
///
/// Either way the app looks frozen on its last painted frame while timers,
/// socket callbacks and tap handling all keep running -- taps still reach the
/// server, they just never show. Every UI update in this app funnels through
/// `GetBuilder.update()` -> `markNeedsBuild` -> `ensureVisualUpdate()` ->
/// `scheduleFrame()`, so one stuck flag silences the entire interface.
///
/// Timers survive the stall, which is what makes a timer the right detector.
class FrameWatchdog {
  FrameWatchdog({
    this.checkInterval = const Duration(milliseconds: 500),
    this.stallThreshold = const Duration(seconds: 1),
  });

  /// How often to look for a stall. Two no-op field reads a second, against a
  /// render loop that wakes 60 times a second when it is healthy.
  final Duration checkInterval;

  /// How long a requested-but-undelivered frame has to be outstanding before
  /// we call it stuck rather than slow.
  final Duration stallThreshold;

  Timer? _timer;
  bool _frameCallbackInstalled = false;
  DateTime _lastFrameAt = DateTime.now();

  /// Set while we are driving a frame by hand, so the frame we produce is not
  /// mistaken for proof that the engine recovered.
  bool _pumping = false;

  bool _recoveryAttempted = false;
  int _consecutivePumps = 0;

  Logger get logger => GetIt.I<Logger>();

  @visibleForTesting
  int get consecutivePumps => _consecutivePumps;

  void start() {
    // Off the web there is no page to read, so `isPageVisible()` is a constant
    // true -- which would read a genuinely backgrounded app's disabled frames
    // as a stall and fake a resume at it, forever. The failure this repairs is
    // a browser one; nothing else should be touched.
    if (!kIsWeb) return;
    if (_timer != null) return;

    if (!_frameCallbackInstalled) {
      // Persistent callbacks run on every frame the engine actually delivers,
      // so this stamp is our proof of life. They cannot be removed once added,
      // hence the install-once guard.
      SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
      _frameCallbackInstalled = true;
    }

    _timer = Timer.periodic(checkInterval, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _onFrame(Duration _) {
    if (_pumping) return;
    _lastFrameAt = DateTime.now();
    _recoveryAttempted = false;
    _consecutivePumps = 0;
  }

  @visibleForTesting
  void check() {
    final binding = SchedulerBinding.instance;

    final action = decideFrameWatchdogAction(
      isVisible: isPageVisible(),
      framesEnabled: binding.framesEnabled,
      hasScheduledFrame: binding.hasScheduledFrame,
      sinceLastFrame: DateTime.now().difference(_lastFrameAt),
      stallThreshold: stallThreshold,
      recoveryAttempted: _recoveryAttempted,
    );

    switch (action) {
      case FrameWatchdogAction.none:
        return;

      case FrameWatchdogAction.resumeLifecycle:
        _recoveryAttempted = true;
        _logStall(binding);
        _resumeLifecycle();

      case FrameWatchdogAction.pumpFrame:
        _pump(binding);
    }
  }

  void _logStall(SchedulerBinding binding) {
    logger.w(
      'FrameWatchdog: render pipeline stalled while the page is visible '
      '(framesEnabled=${binding.framesEnabled}, '
      'hasScheduledFrame=${binding.hasScheduledFrame}, '
      'lifecycleState=${binding.lifecycleState}).',
    );
  }

  /// Drives a frame by hand. `handleBeginFrame` clears `hasScheduledFrame` on
  /// its way through, which is the only route out of that state from Dart.
  ///
  /// This cannot reach the engine's own scheduling flag. If we land here every
  /// tick, the app is running at the watchdog's rate rather than 60fps --
  /// degraded, but responsive instead of frozen, and the log says so.
  void _pump(SchedulerBinding binding) {
    if (binding.schedulerPhase != SchedulerPhase.idle) return;

    _consecutivePumps++;
    if (_consecutivePumps == 1) {
      _logStall(binding);
      logger.w('FrameWatchdog: driving frames by hand.');
    } else if (_consecutivePumps % 20 == 0) {
      logger.w('FrameWatchdog: still driving frames by hand (pump #$_consecutivePumps).');
    }

    _pumping = true;
    try {
      // Must be a real timestamp. Passing null reuses the previous frame's,
      // and every pumped frame carrying the same one means tickers measure no
      // elapsed time -- the whole app renders and responds while every
      // animation sits frozen on a single frame. This clock is the one
      // requestAnimationFrame draws from, so pumped and real frames stay
      // continuous when the engine comes back.
      binding.handleBeginFrame(Duration(microseconds: (highResTimestampMs() * 1000).round()));
      binding.handleDrawFrame();
    } finally {
      _pumping = false;
    }
  }

  /// Pushes a resumed lifecycle message through the same channel the engine
  /// uses, so the framework performs a real transition -- restoring
  /// `framesEnabled` and scheduling a frame -- instead of us poking at state.
  void _resumeLifecycle() {
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.lifecycle.name,
      const StringCodec().encodeMessage('AppLifecycleState.resumed'),
      (ByteData? _) {},
    );
  }
}
