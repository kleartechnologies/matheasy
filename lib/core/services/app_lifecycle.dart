import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../utils/app_logger.dart';

part 'app_lifecycle.g.dart';

/// Tracks the app's [AppLifecycleState] and exposes it to the rest of the app.
///
/// Keeping this in a provider lets any feature react to
/// foreground/background transitions (pause a camera, stop polling, refresh
/// data on resume, flush analytics on pause) without each screen wiring its own
/// observer. Watched once in the shell to keep it alive for the session.
@riverpod
class AppLifecycle extends _$AppLifecycle {
  @override
  AppLifecycleState build() {
    final listener = AppLifecycleListener(
      onStateChange: (next) {
        AppLogger.debug('Lifecycle → ${next.name}', name: 'lifecycle');
        state = next;
      },
    );
    ref.onDispose(listener.dispose);
    return WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }
}
