import 'package:flutter/foundation.dart';

import '../../result/domain/result_models.dart';
import '../../result/domain/teaching_models.dart';

/// The rung of a practice-set item. The first three mirror the server ladder;
/// [challenge] is the stretch goal unlocked after the core three are done.
enum PracticeSetRung {
  easier('easier'),
  similar('similar'),
  harder('harder'),
  challenge('challenge');

  const PracticeSetRung(this.wire);

  /// Wire id shared with the server ladder (`PracticeItem.rung`).
  final String wire;

  /// XP awarded when an item of this rung is completed — aligned with
  /// `PracticeDifficulty.baseXp` (easy/medium/hard/expert) so practice-set XP
  /// and session XP stay one currency.
  int get xp => switch (this) {
        PracticeSetRung.easier => 10,
        PracticeSetRung.similar => 20,
        PracticeSetRung.harder => 40,
        PracticeSetRung.challenge => 75,
      };

  static PracticeSetRung fromWire(String wire) => values.firstWhere(
        (r) => r.wire == wire,
        orElse: () => PracticeSetRung.similar,
      );
}

/// One problem in a practice set — a PROBLEM, never an answer (it re-enters the
/// full solve pipeline when attempted), plus its completion state.
@immutable
class PracticeSetItem {
  const PracticeSetItem({
    required this.latex,
    required this.rung,
    this.plain,
    this.skillHint,
    this.completedAtMillis,
  });

  final String latex;
  final PracticeSetRung rung;
  final String? plain;
  final String? skillHint;

  /// When the learner solved this item (epoch millis), or null while pending.
  final int? completedAtMillis;

  bool get completed => completedAtMillis != null;

  PracticeSetItem complete(int nowMillis) => PracticeSetItem(
        latex: latex,
        rung: rung,
        plain: plain,
        skillHint: skillHint,
        completedAtMillis: completedAtMillis ?? nowMillis,
      );

  factory PracticeSetItem.fromTeaching(PracticeItem item) => PracticeSetItem(
        latex: item.latex,
        rung: PracticeSetRung.fromWire(item.rung),
        plain: item.plain,
        skillHint: item.skillHint,
      );

  Map<String, dynamic> toJson() => {
        'latex': latex,
        'rung': rung.wire,
        if (plain != null) 'plain': plain,
        if (skillHint != null) 'skillHint': skillHint,
        if (completedAtMillis != null) 'completedAtMillis': completedAtMillis,
      };

  factory PracticeSetItem.fromJson(Map<String, dynamic> j) => PracticeSetItem(
        latex: j['latex'] is String ? j['latex'] as String : '',
        rung: PracticeSetRung.fromWire(
            j['rung'] is String ? j['rung'] as String : ''),
        plain: j['plain'] is String ? j['plain'] as String : null,
        skillHint: j['skillHint'] is String ? j['skillHint'] as String : null,
        completedAtMillis:
            j['completedAtMillis'] is int ? j['completedAtMillis'] as int : null,
      );
}

/// A reusable practice set generated from a solved problem: the verified
/// easier / similar / harder ladder plus the unlockable challenge, with the
/// learner's progress through it. Linked to the solved problem by [sourceKey]
/// (the history canonical key) and kept until completed or explicitly re-rolled.
@immutable
class PracticeSet {
  const PracticeSet({
    required this.sourceKey,
    required this.sourceLatex,
    required this.sourceType,
    required this.items,
    required this.createdAtMillis,
    this.challenge,
    this.variant = 0,
    this.mixedReviewAtMillis,
    this.masteredAtMillis,
  });

  /// The canonical key of the SOLVED problem this set was generated from
  /// (`historyCacheKey(sourceLatex)`) — the link to its history entry.
  final String sourceKey;

  /// The solved problem, for display ("from x² − 7x + 12 = 0").
  final String sourceLatex;

  /// The solved problem's type — maps to a practice topic for mixed review.
  final ResultType sourceType;

  /// The core rungs, in order: easier, similar, harder.
  final List<PracticeSetItem> items;

  /// The stretch goal — locked until [coreComplete]. Absent when the server
  /// shipped no challenge rung.
  final PracticeSetItem? challenge;

  /// Which deterministic server roll this set is ("new set" increments it).
  final int variant;

  final int createdAtMillis;

  /// When the unlocked mixed-review session was completed, or null.
  final int? mixedReviewAtMillis;

  /// When the whole journey (core + challenge + mixed review) was celebrated
  /// as mastered, or null.
  final int? masteredAtMillis;

  factory PracticeSet.fromLadder({
    required String sourceKey,
    required String sourceLatex,
    required ResultType sourceType,
    required PracticeLadder ladder,
    required int nowMillis,
    int variant = 0,
  }) =>
      PracticeSet(
        sourceKey: sourceKey,
        sourceLatex: sourceLatex,
        sourceType: sourceType,
        items: [for (final r in ladder.rungs) PracticeSetItem.fromTeaching(r)],
        challenge: ladder.challenge == null
            ? null
            : PracticeSetItem.fromTeaching(ladder.challenge!),
        variant: variant,
        createdAtMillis: nowMillis,
      );

  // ---- Progress ----

  /// Every item, challenge last (present or not, locked or not).
  List<PracticeSetItem> get allItems => [...items, ?challenge];

  bool get coreComplete => items.isNotEmpty && items.every((i) => i.completed);

  /// Challenge + mixed review only unlock once the core three are done.
  bool get challengeUnlocked => coreComplete;

  bool get mixedReviewComplete => mixedReviewAtMillis != null;

  bool get mastered => masteredAtMillis != null;

  /// Everything there is to do here is done — the "Topic mastered" condition.
  bool get journeyComplete =>
      coreComplete &&
      (challenge == null || challenge!.completed) &&
      mixedReviewComplete;

  int get completedCount => allItems.where((i) => i.completed).length;

  int get totalCount => allItems.length;

  /// The next problem to attempt: first pending core rung, then the challenge
  /// once unlocked. Null when every problem is done.
  PracticeSetItem? get nextItem {
    for (final item in items) {
      if (!item.completed) return item;
    }
    final c = challenge;
    if (c != null && challengeUnlocked && !c.completed) return c;
    return null;
  }

  /// Whether [latex] (canonicalized by the caller to [itemKey]) is one of this
  /// set's pending problems.
  bool hasPendingItemKey(String itemKey, String Function(String) canonicalize) {
    for (final item in allItems) {
      if (!item.completed && canonicalize(item.latex) == itemKey) return true;
    }
    return false;
  }

  // ---- Mutation (immutable copies) ----

  PracticeSet copyWith({
    List<PracticeSetItem>? items,
    PracticeSetItem? challenge,
    int? mixedReviewAtMillis,
    int? masteredAtMillis,
  }) =>
      PracticeSet(
        sourceKey: sourceKey,
        sourceLatex: sourceLatex,
        sourceType: sourceType,
        items: items ?? this.items,
        challenge: challenge ?? this.challenge,
        variant: variant,
        createdAtMillis: createdAtMillis,
        mixedReviewAtMillis: mixedReviewAtMillis ?? this.mixedReviewAtMillis,
        masteredAtMillis: masteredAtMillis ?? this.masteredAtMillis,
      );

  // ---- Serialization ----

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'sourceLatex': sourceLatex,
        'sourceType': sourceType.name,
        'items': [for (final i in items) i.toJson()],
        if (challenge != null) 'challenge': challenge!.toJson(),
        'variant': variant,
        'createdAtMillis': createdAtMillis,
        if (mixedReviewAtMillis != null)
          'mixedReviewAtMillis': mixedReviewAtMillis,
        if (masteredAtMillis != null) 'masteredAtMillis': masteredAtMillis,
      };

  /// Null on a malformed record (sync payloads are untrusted).
  static PracticeSet? tryFromJson(Map<String, dynamic> j) {
    final key = j['sourceKey'];
    final latex = j['sourceLatex'];
    final rawItems = j['items'];
    if (key is! String || key.isEmpty) return null;
    if (latex is! String || latex.isEmpty) return null;
    if (rawItems is! List || rawItems.isEmpty) return null;
    final items = [
      for (final e in rawItems)
        if (e is Map) PracticeSetItem.fromJson(Map<String, dynamic>.from(e)),
    ];
    if (items.isEmpty || items.any((i) => i.latex.isEmpty)) return null;
    final rawChallenge = j['challenge'];
    return PracticeSet(
      sourceKey: key,
      sourceLatex: latex,
      sourceType: ResultType.values.asNameMap()[j['sourceType']] ??
          ResultType.expression,
      items: items,
      challenge: rawChallenge is Map
          ? PracticeSetItem.fromJson(Map<String, dynamic>.from(rawChallenge))
          : null,
      variant: j['variant'] is int ? j['variant'] as int : 0,
      createdAtMillis:
          j['createdAtMillis'] is int ? j['createdAtMillis'] as int : 0,
      mixedReviewAtMillis: j['mixedReviewAtMillis'] is int
          ? j['mixedReviewAtMillis'] as int
          : null,
      masteredAtMillis:
          j['masteredAtMillis'] is int ? j['masteredAtMillis'] as int : null,
    );
  }
}
