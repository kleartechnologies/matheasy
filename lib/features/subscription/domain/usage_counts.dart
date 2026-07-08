/// The metered features whose free-tier usage is tracked and gated.
enum UsageFeature { scan, numiMessage, practiceQuestion }

/// The lifetime tally of a user's metered actions.
///
/// This is the "used" side of the ledger; [UsageQuota] is the "allowed" side.
/// Counts are stored locally and only matter on the free tier — Pro is
/// unlimited so recording is harmless but unread. Counts never decrement.
class UsageCounts {
  const UsageCounts({
    this.scansUsed = 0,
    this.numiMessagesUsed = 0,
    this.practiceQuestionsGenerated = 0,
  });

  /// A fresh ledger — nothing used yet.
  static const UsageCounts empty = UsageCounts();

  final int scansUsed;
  final int numiMessagesUsed;
  final int practiceQuestionsGenerated;

  int usedFor(UsageFeature feature) => switch (feature) {
        UsageFeature.scan => scansUsed,
        UsageFeature.numiMessage => numiMessagesUsed,
        UsageFeature.practiceQuestion => practiceQuestionsGenerated,
      };

  UsageCounts copyWith({
    int? scansUsed,
    int? numiMessagesUsed,
    int? practiceQuestionsGenerated,
  }) {
    return UsageCounts(
      scansUsed: scansUsed ?? this.scansUsed,
      numiMessagesUsed: numiMessagesUsed ?? this.numiMessagesUsed,
      practiceQuestionsGenerated:
          practiceQuestionsGenerated ?? this.practiceQuestionsGenerated,
    );
  }

  Map<String, dynamic> toJson() => {
        'scansUsed': scansUsed,
        'numiMessagesUsed': numiMessagesUsed,
        'practiceQuestionsGenerated': practiceQuestionsGenerated,
      };

  /// Rebuilds from JSON, degrading any missing/invalid field to `0` rather than
  /// throwing — a corrupt payload should never lock a user out mid-usage.
  factory UsageCounts.fromJson(Map<String, dynamic> json) => UsageCounts(
        scansUsed: _int(json['scansUsed']),
        numiMessagesUsed: _int(json['numiMessagesUsed']),
        practiceQuestionsGenerated: _int(json['practiceQuestionsGenerated']),
      );

  static int _int(Object? value) => value is int && value >= 0 ? value : 0;

  @override
  bool operator ==(Object other) =>
      other is UsageCounts &&
      other.scansUsed == scansUsed &&
      other.numiMessagesUsed == numiMessagesUsed &&
      other.practiceQuestionsGenerated == practiceQuestionsGenerated;

  @override
  int get hashCode =>
      Object.hash(scansUsed, numiMessagesUsed, practiceQuestionsGenerated);
}
