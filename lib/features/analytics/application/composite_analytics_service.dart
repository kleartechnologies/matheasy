import '../../../core/monitoring/logging_service.dart';
import '../domain/analytics_event.dart';
import 'analytics_service.dart';

/// Fans every analytics call out to several [AnalyticsService] backends (e.g.
/// Firebase Analytics + Meta App Events) so a single event emission point in the
/// app reaches all of them — no call site learns there is more than one sink,
/// and there is no duplicate firing.
///
/// Each delegate is isolated: if one backend throws (a missing plugin, a
/// transient SDK error), the others still receive the call and the failure is
/// swallowed to a breadcrumb rather than surfacing as an uncaught async error.
class CompositeAnalyticsService implements AnalyticsService {
  CompositeAnalyticsService(this._delegates);

  final List<AnalyticsService> _delegates;

  @override
  Future<void> logEvent(AnalyticsEvent event) =>
      _fanOut((service) => service.logEvent(event));

  @override
  Future<void> setUserId(String? id) =>
      _fanOut((service) => service.setUserId(id));

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _fanOut((service) => service.setUserProperty(name, value));

  Future<void> _fanOut(Future<void> Function(AnalyticsService) op) async {
    await Future.wait(
      _delegates.map((service) async {
        try {
          await op(service);
        } catch (error) {
          LoggingService.warning('Analytics delegate failed: $error');
        }
      }),
    );
  }
}
