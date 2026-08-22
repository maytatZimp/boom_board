import 'package:boom_board/core/utils/frame_watchdog.dart';
import 'package:boom_board/core/utils/high_res_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// The watchdog's whole job is telling "stalled" apart from "idle". Getting it
/// wrong in either direction is expensive: miss a stall and the app stays
/// frozen, cry wolf on a quiet board and it forces repaints twice a second
/// forever.
///
/// The decision is tested directly rather than through SchedulerBinding: the
/// test binding reimplements frame scheduling, so driving it here would assert
/// its quirks instead of the real pipeline's.
void main() {
  const threshold = Duration(seconds: 1);

  FrameWatchdogAction decide({
    bool isVisible = true,
    bool withinResumeGrace = false,
    bool framesEnabled = true,
    bool hasScheduledFrame = false,
    Duration sinceLastFrame = Duration.zero,
    bool recoveryAttempted = false,
  }) {
    return decideFrameWatchdogAction(
      isVisible: isVisible,
      withinResumeGrace: withinResumeGrace,
      framesEnabled: framesEnabled,
      hasScheduledFrame: hasScheduledFrame,
      sinceLastFrame: sinceLastFrame,
      stallThreshold: threshold,
      recoveryAttempted: recoveryAttempted,
    );
  }

  group('leaves the pipeline alone', () {
    test('when nothing is dirty, however long since the last frame', () {
      // The steady state of a lobby or a board between rounds: the framework
      // renders nothing because nothing asked it to. A plain "no frame lately"
      // check would misread this as a stall and repaint forever.
      expect(
        decide(hasScheduledFrame: false, sinceLastFrame: const Duration(minutes: 5)),
        FrameWatchdogAction.none,
      );
    });

    test('when a requested frame is merely slow', () {
      expect(
        decide(hasScheduledFrame: true, sinceLastFrame: const Duration(milliseconds: 800)),
        FrameWatchdogAction.none,
      );
    });

    test('when the page is genuinely hidden', () {
      // Frames being off is correct here. Forcing one would queue an animation
      // frame that cannot run -- which is how the stuck flag gets created.
      expect(
        decide(isVisible: false, framesEnabled: false),
        FrameWatchdogAction.none,
      );
      expect(
        decide(
          isVisible: false,
          hasScheduledFrame: true,
          sinceLastFrame: const Duration(seconds: 30),
        ),
        FrameWatchdogAction.none,
      );
    });
  });

  group('lifecycle stuck hidden while the page is visible', () {
    test('restores the lifecycle rather than forcing a one-off frame', () {
      // Forcing frames would leave framesEnabled false and every later
      // animation tick still dropped.
      expect(decide(framesEnabled: false), FrameWatchdogAction.resumeLifecycle);
    });

    test('does not wait out the stall threshold', () {
      // Nothing is pending to time out: scheduleFrame() bailed before it could
      // record that a frame was wanted.
      expect(
        decide(framesEnabled: false, hasScheduledFrame: false, sinceLastFrame: Duration.zero),
        FrameWatchdogAction.resumeLifecycle,
      );
    });
  });

  group('a requested frame that never arrived', () {
    test('is pumped by hand straight away', () {
      // No cheaper attempt exists to make first: every scheduling call bails on
      // the very flag that is stuck. scheduleForcedFrame() ignores the
      // lifecycle gate but not that one, so asking it here would be a
      // guaranteed no-op that only costs another tick of frozen screen.
      expect(
        decide(hasScheduledFrame: true, sinceLastFrame: const Duration(seconds: 2)),
        FrameWatchdogAction.pumpFrame,
      );
    });

    test('is pumped by hand whether or not recovery was already tried', () {
      // recoveryAttempted distinguishes nothing here -- there is no first
      // attempt for it to record.
      expect(
        decide(
          hasScheduledFrame: true,
          sinceLastFrame: const Duration(seconds: 2),
          recoveryAttempted: true,
        ),
        FrameWatchdogAction.pumpFrame,
      );
    });

    test('is pumped by hand when the lifecycle fix did not take either', () {
      expect(
        decide(framesEnabled: false, recoveryAttempted: true),
        FrameWatchdogAction.pumpFrame,
      );
    });
  });

  test('a recovered pipeline stops being acted on even mid-recovery', () {
    // recoveryAttempted is cleared by the next delivered frame, but a healthy
    // state must read as none regardless -- otherwise a recovery in flight
    // would keep pumping after the engine came back.
    expect(decide(recoveryAttempted: true), FrameWatchdogAction.none);
  });

  group('a page that has only just come back', () {
    test('is left to the browser while the grace runs', () {
      // sinceLastFrame spans the entire time the tab was away, so it always
      // reads as a stall the moment the page returns. Acting on that would
      // mostly mean interrupting a recovery already under way.
      expect(
        decide(
          withinResumeGrace: true,
          hasScheduledFrame: true,
          sinceLastFrame: const Duration(minutes: 5),
        ),
        FrameWatchdogAction.none,
      );
      expect(
        decide(withinResumeGrace: true, framesEnabled: false),
        FrameWatchdogAction.none,
      );
    });

    test('is repaired once the grace has run out', () {
      // Same state, no longer excused: waiting is a delay, not a pardon.
      expect(
        decide(hasScheduledFrame: true, sinceLastFrame: const Duration(minutes: 5)),
        FrameWatchdogAction.pumpFrame,
      );
      expect(decide(framesEnabled: false), FrameWatchdogAction.resumeLifecycle);
    });
  });

  group('the stamp put on a pumped frame', () {
    // A stamp that lands ahead of the next real frame makes that frame a step
    // backwards, and a ticker started on the higher one dies of a negative
    // elapsed -- permanently, and only that ticker.
    test('stays behind the clock it is sampled from', () {
      final watchdog = FrameWatchdog(pumpTimestampMargin: const Duration(milliseconds: 250));
      expect(watchdog.pumpTimestampMs(), lessThan(highResTimestampMs()));
    });

    test('never goes backwards across pumps', () {
      final watchdog = FrameWatchdog();
      var previous = watchdog.pumpTimestampMs();
      for (var i = 0; i < 50; i++) {
        final next = watchdog.pumpTimestampMs();
        expect(next, greaterThanOrEqualTo(previous));
        previous = next;
      }
    });

    test('does not undercut a frame the engine already delivered', () {
      // The floor matters most on the lifecycle-stuck path, which pumps
      // without waiting out the stall threshold -- so a real frame may be more
      // recent than the margin is wide.
      // An absurd margin stands in for "a real frame more recent than the
      // margin", which is the case the floor exists to catch. The threshold
      // moves with it to keep the constructor's invariant intact.
      final watchdog = FrameWatchdog(
        pumpTimestampMargin: const Duration(days: 1),
        stallThreshold: const Duration(days: 2),
      );
      expect(watchdog.pumpTimestampMs(), greaterThanOrEqualTo(0));
    });
  });
}
