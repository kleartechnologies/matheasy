/// Why the paywall was opened — drives the headline framing and analytics.
///
/// A limit-reached trigger lets the paywall lead with the specific value the
/// user just bumped into ("You've used all 5 free scans"), which converts far
/// better than a generic pitch. [visualLearning] and [adaptivePractice] are
/// Pro-exclusive feature gates (the locked Visual tab; advanced / adaptive
/// practice), not usage limits. [manual] is a user-initiated open (upgrade
/// button, subscription card) with no context.
enum PaywallTrigger {
  scanLimit,
  numiLimit,
  practiceLimit,
  visualLearning,
  adaptivePractice,
  manual;

  bool get isLimit => switch (this) {
        PaywallTrigger.scanLimit ||
        PaywallTrigger.numiLimit ||
        PaywallTrigger.practiceLimit =>
          true,
        PaywallTrigger.visualLearning ||
        PaywallTrigger.adaptivePractice ||
        PaywallTrigger.manual =>
          false,
      };
}
