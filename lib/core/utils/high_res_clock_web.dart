import 'package:web/web.dart' as web;

/// Milliseconds since the page's time origin -- the same value
/// `requestAnimationFrame` passes its callback, so hand-driven frames and real
/// ones share a timeline.
double highResTimestampMs() => web.window.performance.now().toDouble();
