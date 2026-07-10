import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../scan/domain/detected_equation.dart';
import '../domain/visual_models.dart';
import 'result_controller.dart';
import 'visual_prompt_builder.dart';
import 'visual_solution_service.dart';

part 'visual_solution_controller.g.dart';

/// No automatic retry: a failed generation must surface immediately so the
/// Visual tab can fall back to the Explain tab, instead of Riverpod's default
/// backoff loop re-billing the AI backend behind a perpetual spinner. The
/// user retries explicitly ("Try again" → invalidate).
Duration? _noRetry(int retryCount, Object error) => null;

/// Generates the [VisualSolution] for a solved problem via the
/// [VisualSolutionService].
///
/// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
/// renders, so free users and untouched tabs never spend an AI call. Keyed by
/// the equation like [ResultController], so revisiting the same problem reuses
/// the cached visual. Waits for the solver first so the walkthrough always
/// agrees with the Solution tab's answer.
@Riverpod(retry: _noRetry)
class VisualSolutionController extends _$VisualSolutionController {
  @override
  Future<VisualSolution> build(DetectedEquation equation) async {
    // Capture every dependency before the first await: if the tab is left
    // mid-generation the (auto-dispose) provider dies, and a Ref must never
    // be touched after that.
    final service = ref.watch(visualSolutionServiceProvider);
    final rateLimiter = ref.read(rateLimitServiceProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final resultFuture = ref.watch(resultControllerProvider(equation).future);

    final result = await resultFuture;

    // Client-side abuse guard (the server re-enforces authoritatively).
    final limit = rateLimiter.check(RateLimitedAction.visualGeneration);
    if (limit.isLimited) {
      LoggingService.warning('Visual generation rate-limited: ${limit.reason}');
      throw VisualGenerationException(
        limit.reason ?? 'Please wait a moment and try again.',
      );
    }

    final VisualSolution visual;
    try {
      visual = await service.generate(
        VisualPromptBuilder.request(equation, result: result),
      );
    } on BackendException catch (error) {
      // Expected failures (offline, quota, entitlement) — breadcrumb only;
      // the tab shows its fallback and never blocks the solution flow.
      LoggingService.warning('Visual generation failed: ${error.code}');
      rethrow;
    } catch (error, stack) {
      LoggingService.error(
        'Visual generation error',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }

    // Pin the successful result so switching tabs (which unmounts the Visual
    // tab, the provider's only listener) doesn't dispose it and re-bill a
    // whole new OpenAI generation on return — the "revisiting reuses the
    // cached visual" contract. Failures stay auto-dispose so "Try again"
    // (invalidate) genuinely regenerates.
    ref.keepAlive();

    unawaited(
      analytics.logEvent(
        AnalyticsEvent.visualViewed(
          category: visual.category.name,
          tier: visual.visualization.name,
        ),
      ),
    );
    return visual;
  }
}

/// Records teaser impressions for the locked Visual tab — once per problem,
/// mirroring how `PaywallController.markViewed` keeps analytics out of
/// widgets. The teaser calls [markShown] post-frame.
@Riverpod(keepAlive: true)
class VisualTeaserTracker extends _$VisualTeaserTracker {
  final Set<String> _shown = {};

  @override
  int build() => 0;

  void markShown(DetectedEquation equation) {
    if (!_shown.add(equation.latex)) return;
    state = _shown.length;
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logEvent(AnalyticsEvent.visualTeaserViewed()),
    );
  }
}
