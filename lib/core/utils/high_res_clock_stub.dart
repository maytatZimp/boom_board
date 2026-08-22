final Stopwatch _clock = Stopwatch()..start();

/// Milliseconds since the app started. Off the web there is no shared time
/// origin to match, so any monotonic clock will do.
double highResTimestampMs() => _clock.elapsedMicroseconds / 1000;
