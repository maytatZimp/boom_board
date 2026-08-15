import 'package:boom_board/core/events/event_bus.dart';
import 'package:event_bus/event_bus.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

/// Resets every piece of global state the app relies on.
///
/// Call from `setUp` in any test that touches code reaching for `GetIt.I<...>`
/// or the global [eventBus]. Both are process-wide mutable singletons, so
/// without this reset one test's registrations and listeners leak into the
/// next and the suite passes or fails depending on file order.
///
/// Must be awaited: `GetIt.reset()` is a Future, and registering without
/// awaiting it lets the reset land afterwards and wipe the registration.
Future<void> setUpTestDependencies() async {
  await GetIt.I.reset();

  // Almost everything in lib/ resolves `GetIt.I<Logger>()` in a getter --
  // SocketService, SimpleModeSocketHandler, both controllers. Level.off keeps
  // the test output readable; the calls still have to resolve something.
  GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));

  // `eventBus` is a non-final top-level variable, so a fresh instance per test
  // drops any subscriptions a previous test left behind.
  eventBus = EventBus();
}

/// Tears down the globals so a leaked registration surfaces as a failure in
/// the test that caused it rather than in an unrelated one later.
Future<void> tearDownTestDependencies() async {
  await GetIt.I.reset();
}

/// [EventBus] delivers on an async broadcast stream, so `fire()` hands off to a
/// microtask rather than calling listeners inline. Await this after firing
/// before asserting on anything a listener was supposed to change.
Future<void> pumpEventBus() => Future.delayed(Duration.zero);
