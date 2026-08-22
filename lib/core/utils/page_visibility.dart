/// Whether the browser page is on screen, and a hook for when that changes.
///
/// The engine already maps `visibilitychange` onto [AppLifecycleState], but
/// that mapping is exactly what goes wrong when mobile Chrome backgrounds the
/// tab -- so anything trying to detect or repair that failure has to read the
/// browser directly rather than trust the framework's view of it.
///
/// The stub keeps `package:web` out of the VM (tests, `flutter analyze` on a
/// non-web target) and reports a permanently visible page, which is the right
/// answer everywhere the concept does not apply.
library;

export 'page_visibility_stub.dart' if (dart.library.js_interop) 'page_visibility_web.dart';
