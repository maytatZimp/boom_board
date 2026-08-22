import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool isPageVisible() => web.document.visibilityState == 'visible';

/// Returns a disposer that unregisters the listener again.
void Function() addPageVisibilityListener(void Function(bool isVisible) listener) {
  // Held in a variable so removeEventListener gets the same JS function
  // reference it was registered with -- a second `.toJS` would be a new one.
  final callback = ((web.Event _) => listener(isPageVisible())).toJS;

  web.document.addEventListener('visibilitychange', callback);

  return () => web.document.removeEventListener('visibilitychange', callback);
}
