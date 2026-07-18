import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../domain/result_models.dart';
import 'functions_solver_service.dart';

/// Fetches the v2 teaching layer for an already-solved problem — a SEPARATE call
/// from `solve`, so solving stays instant and the teaching loads progressively
/// (mirroring how the Visual tab calls its own enrichment). The seam mirrors
/// [SolverService]: real callable for signed-in users, no-op otherwise.
abstract interface class TeachingService {
  /// Returns [base] enriched with its teaching layer, or null when there is no
  /// teaching to add (offline, feature-off, or an honest/unverified problem).
  Future<ResultData?> enrich(ResultData base);
}

/// No teaching (guests / unconfigured backend): the solution shows unchanged.
class NoTeachingService implements TeachingService {
  const NoTeachingService();

  @override
  Future<ResultData?> enrich(ResultData base) async => null;
}

/// Real teaching — calls the `enrichTeaching` Cloud Function (OpenAI + firewall
/// server-side; depth gated by entitlement) and merges the layer into [base].
class FunctionsTeachingService implements TeachingService {
  const FunctionsTeachingService(this._call);

  /// Injected so the mapping is testable without the `cloud_functions` plugin.
  final Future<Map<String, dynamic>> Function(
      String name, Map<String, dynamic> data) _call;

  @override
  Future<ResultData?> enrich(ResultData base) async {
    final json = await _call('enrichTeaching', {
      'latex': base.equation.latex,
      // A routeToTutor problem (proof / conceptual / multi-part) has no verified
      // answer — ask for HONEST-mode concept teaching (teach the approach).
      if (base.routeToTutor) 'honest': true,
    });
    return SolveResponseMapper.mergeTeaching(base, json);
  }
}

/// The active [TeachingService]: the real callable for signed-in users with
/// Firebase configured, else a no-op (guests / offline keep the plain solution).
final Provider<TeachingService> teachingServiceProvider =
    Provider<TeachingService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const NoTeachingService();
  final functions = ref.watch(firebaseFunctionsProvider);
  return FunctionsTeachingService(
    (name, data) => callFunction(functions, name, data),
  );
});
