import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../progress/application/achievement_service.dart' show clockProvider;
import '../../result/domain/result_models.dart';
import '../domain/history_entry.dart';
import 'history_repository.dart';

part 'history_controller.g.dart';

/// The solved-problem history — hydrates from the local cache on build and is
/// the single mutator of the on-device list. Kept alive so the recent-problems
/// surfaces (Home, History screen) share one live copy.
///
/// Mutations persist through [HistoryRepository] *before* the state notifies, so
/// the offline-first sync layer — which observes this controller — sees a
/// consistent local store when it debounces an upload.
@Riverpod(keepAlive: true)
class HistoryController extends _$HistoryController {
  @override
  List<HistoryEntry> build() => ref.read(historyRepositoryProvider).load();

  /// Caches a freshly solved problem (deduped by canonical key, most-recent
  /// first). Called after a real `solve()`; re-opening a cached problem does
  /// not solve, so it never lands here.
  Future<void> record(ResultData result) async {
    final now = ref.read(clockProvider)();
    state = await ref.read(historyRepositoryProvider).record(
          result,
          nowMillis: now.millisecondsSinceEpoch,
        );
  }

  /// Deletes a single history item.
  Future<void> remove(String canonicalKey) async {
    state = await ref.read(historyRepositoryProvider).remove(canonicalKey);
  }

  /// Clears the entire history.
  Future<void> clear() async {
    state = await ref.read(historyRepositoryProvider).clear();
  }
}
