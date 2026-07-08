/// The lifetime allowances of a tier, per metered feature.
///
/// A limit of [unlimited] (`-1`) means no cap — the Pro tier. The free tier's
/// numbers are the product's locked pricing (5 scans, 20 Numi messages, 10
/// generated practice questions).
class UsageQuota {
  const UsageQuota({
    required this.scans,
    required this.numiMessages,
    required this.practiceQuestions,
  });

  /// Sentinel for an uncapped allowance.
  static const int unlimited = -1;

  /// The locked free-tier allowances.
  static const UsageQuota free = UsageQuota(
    scans: 5,
    numiMessages: 20,
    practiceQuestions: 10,
  );

  /// Pro — everything uncapped.
  static const UsageQuota pro = UsageQuota(
    scans: unlimited,
    numiMessages: unlimited,
    practiceQuestions: unlimited,
  );

  final int scans;
  final int numiMessages;
  final int practiceQuestions;

  static bool isUnlimited(int limit) => limit == unlimited;

  @override
  bool operator ==(Object other) =>
      other is UsageQuota &&
      other.scans == scans &&
      other.numiMessages == numiMessages &&
      other.practiceQuestions == practiceQuestions;

  @override
  int get hashCode => Object.hash(scans, numiMessages, practiceQuestions);
}
