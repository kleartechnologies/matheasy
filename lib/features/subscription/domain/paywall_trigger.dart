/// Why the paywall was opened — drives the headline framing and analytics.
///
/// A limit-reached trigger lets the paywall lead with the specific value the
/// user just bumped into ("You've used all 5 free scans"), which converts far
/// better than a generic pitch. [visualLearning] is a Pro-exclusive feature
/// gate (the locked Visual tab), not a usage limit. [manual] is a
/// user-initiated open (upgrade button, subscription card) with no context.
enum PaywallTrigger {
  scanLimit,
  numiLimit,
  practiceLimit,
  visualLearning,
  manual;

  bool get isLimit => switch (this) {
        PaywallTrigger.scanLimit ||
        PaywallTrigger.numiLimit ||
        PaywallTrigger.practiceLimit =>
          true,
        PaywallTrigger.visualLearning || PaywallTrigger.manual => false,
      };
}
