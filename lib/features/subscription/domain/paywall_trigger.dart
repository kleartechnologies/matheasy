/// Why the paywall was opened — drives the headline framing and analytics.
///
/// A limit-reached trigger lets the paywall lead with the specific value the
/// user just bumped into ("You've used all 5 free scans"), which converts far
/// better than a generic pitch. [manual] is a user-initiated open (upgrade
/// button, subscription card) with no limit context.
enum PaywallTrigger {
  scanLimit,
  numiLimit,
  practiceLimit,
  manual;

  bool get isLimit => this != PaywallTrigger.manual;
}
