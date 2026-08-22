/// Off the web there is no page to hide, so it is always on screen.
bool isPageVisible() => true;

/// No-op: nothing off the web can change [isPageVisible]. Returns a disposer
/// so callers do not have to care which implementation they got.
void Function() addPageVisibilityListener(void Function(bool isVisible) listener) {
  return () {};
}
