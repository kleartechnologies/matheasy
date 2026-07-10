import '../../subscription/domain/paywall_trigger.dart';
import '../../subscription/domain/subscription_product.dart';
import '../../subscription/domain/usage_quota.dart';

/// Static copy + small pricing computations for the paywall, kept out of the
/// widgets so the messaging is easy to review and tune in one place.
class PaywallCopy {
  const PaywallCopy._();

  static const String headline = 'Unlock Unlimited Learning';

  /// The sub-headline, framed around what the user just bumped into so the pitch
  /// leads with concrete value rather than a generic sell.
  static String subheadline(PaywallTrigger trigger) => switch (trigger) {
        PaywallTrigger.scanLimit =>
          "You've used all ${UsageQuota.free.scans} free scans. Go Pro for "
              'unlimited snap-and-solve.',
        PaywallTrigger.tutorLimit =>
          "You've reached ${UsageQuota.free.tutorMessages} free AI tutor "
              'messages. Go Pro to keep the conversation going.',
        PaywallTrigger.practiceLimit =>
          "You've generated all ${UsageQuota.free.practiceQuestions} free "
              'practice questions. Go Pro for unlimited practice.',
        PaywallTrigger.visualLearning =>
          'Understand math visually. Watch every step unfold and learn '
              'faster with animations — a Matheasy Pro exclusive.',
        PaywallTrigger.adaptivePractice =>
          'Practice that adapts to you. Unlimited, personalized questions that '
              'target your weak spots — a Matheasy Pro exclusive.',
        PaywallTrigger.manual =>
          'Learn faster with unlimited AI-powered math help.',
      };

  /// The annual card's value line — the per-month equivalent and the saving vs.
  /// paying monthly. Computed from live prices when available, else the locked
  /// "Save 37%" from the product spec.
  static String annualValueLine(
    SubscriptionProduct? annual,
    SubscriptionProduct? monthly,
  ) {
    final perMonth = annual?.pricePerMonthString;
    final savings = _savingsPercent(annual, monthly);
    final savingLabel = 'Save $savings%';
    if (perMonth != null && perMonth.isNotEmpty) {
      return 'Just $perMonth/mo · $savingLabel';
    }
    return '$savingLabel vs monthly';
  }

  /// Percentage saved by paying annually instead of 12× monthly. Falls back to
  /// the spec's locked 37% when raw prices aren't available.
  static int _savingsPercent(
    SubscriptionProduct? annual,
    SubscriptionProduct? monthly,
  ) {
    final annualPrice = annual?.rawPrice;
    final monthlyPrice = monthly?.rawPrice;
    if (annualPrice == null ||
        monthlyPrice == null ||
        monthlyPrice <= 0 ||
        annualPrice <= 0) {
      return 37;
    }
    final yearAtMonthly = monthlyPrice * 12;
    if (yearAtMonthly <= annualPrice) return 0;
    return (((yearAtMonthly - annualPrice) / yearAtMonthly) * 100).round();
  }

  /// The Free vs Pro comparison table rows (in display order).
  static const List<ComparisonRow> comparison = [
    ComparisonRow(
      label: 'Scans',
      freeLabel: '5 lifetime',
      proLabel: 'Unlimited',
    ),
    ComparisonRow(
      label: 'Matheasy AI Tutor',
      freeLabel: '20 messages',
      proLabel: 'Unlimited',
    ),
    ComparisonRow(
      label: 'Practice questions',
      freeLabel: '10 lifetime',
      proLabel: 'Unlimited',
    ),
    ComparisonRow(
      label: 'Adaptive Practice Engine',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Advanced topics & AI questions',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Step-by-step explanations',
      freeLabel: 'Basic',
      proLabel: 'In depth',
    ),
    ComparisonRow(
      label: 'Multiple solution methods',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Visual Learning Engine',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Future premium features',
      freeIncluded: false,
      proLabel: 'Included',
    ),
  ];
}

/// A single row of the Free vs Pro comparison table.
class ComparisonRow {
  const ComparisonRow({
    required this.label,
    required this.proLabel,
    this.freeLabel,
    this.freeIncluded = true,
  });

  final String label;

  /// The value shown in the Free column, or `null` to show a check/cross based
  /// on [freeIncluded].
  final String? freeLabel;

  /// Whether the free tier includes this feature at all (drives the ✓ / — glyph
  /// when [freeLabel] is null).
  final bool freeIncluded;

  /// The value shown in the Pro column (always included).
  final String proLabel;
}
