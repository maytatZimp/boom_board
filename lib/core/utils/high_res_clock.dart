/// A millisecond clock on the same timeline the browser hands to
/// `requestAnimationFrame`.
///
/// Frames the watchdog drives by hand have to carry a timestamp from this
/// clock, so tickers keep advancing and so the numbers stay continuous with
/// the ones real animation frames bring.
library;

export 'high_res_clock_stub.dart' if (dart.library.js_interop) 'high_res_clock_web.dart';
