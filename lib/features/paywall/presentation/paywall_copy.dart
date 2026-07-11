import '../../subscription/domain/paywall_trigger.dart';
import '../../subscription/domain/subscription_product.dart';
import '../../subscription/domain/usage_quota.dart';

/// Static copy + small pricing computations for the paywall, kept out of the
/// widgets so the messaging is easy to review and tune in one place.
class PaywallCopy {
  const PaywallCopy._();

  // TODO(headline): consider a continuity-framed headline ("Keep learning
  //   without limits") once A/B testing is set up — the paywall is shown mostly
  //   to users who just hit a free-tier limit, so continuity may convert better.
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
          'See every step come alive, practice what you actually struggle '
              'with, and get unlimited AI help.',
      };

  /// The annual card's value line — the per-month equivalent and the saving vs.
  /// paying monthly. Computed from live prices when available, else the locked
  /// "Save 37%" from the product spec.
  static String annualValueLine(
    SubscriptionProduct? annual,
    SubscriptionProduct? monthly,
  ) {
    final savings = _savingsPercent(annual, monthly);
    final perMonth = annual?.pricePerMonthComputed;
    final annualPrice = annual?.priceString;
    // Only ever append a saving we could compute from BOTH prices shown, so the
    // percentage can never contradict the two prices on the cards (e.g. a
    // partial catalog where one plan is live and the other is a fallback).
    final savingSuffix = savings != null ? ' · Save $savings%' : '';
    // When a per-month price is available it becomes the card's headline price,
    // so this value line carries the annual total (store-required to keep
    // visible) plus the saving vs paying monthly.
    if (perMonth != null && perMonth.isNotEmpty && annualPrice != null) {
      return '$annualPrice billed yearly$savingSuffix';
    }
    // No per-month framing (e.g. no annual price at all): show the saving line
    // when we can state one truthfully, else a neutral value cue.
    return savings != null ? 'Save $savings% vs monthly' : 'Best value';
  }

  /// Percentage saved by paying annually instead of 12× monthly, computed from
  /// the two prices actually shown. Returns `null` (rather than a hardcoded
  /// figure) whenever it can't be computed from both prices or the annual isn't
  /// actually cheaper — so the paywall never asserts a saving it can't back up.
  static int? _savingsPercent(
    SubscriptionProduct? annual,
    SubscriptionProduct? monthly,
  ) {
    final annualPrice = annual?.rawPrice;
    final monthlyPrice = monthly?.rawPrice;
    if (annualPrice == null ||
        monthlyPrice == null ||
        monthlyPrice <= 0 ||
        annualPrice <= 0) {
      return null;
    }
    final yearAtMonthly = monthlyPrice * 12;
    if (yearAtMonthly <= annualPrice) return null;
    return (((yearAtMonthly - annualPrice) / yearAtMonthly) * 100).round();
  }

  /// The Free vs Pro comparison table rows (in display order). The Pro-exclusive
  /// experiences lead — Visual Learning (the flagship) first — so the table
  /// frames Pro around what makes it special before the unlimited-quota rows.
  static const List<ComparisonRow> comparison = [
    ComparisonRow(
      label: 'Visual Learning Engine',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Adaptive Practice Engine',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Multiple solution methods',
      freeIncluded: false,
      proLabel: 'Included',
    ),
    ComparisonRow(
      label: 'Step-by-step explanations',
      freeLabel: 'Basic',
      proLabel: 'In depth',
    ),
    ComparisonRow(
      label: 'Advanced topics & AI questions',
      freeIncluded: false,
      proLabel: 'Included',
    ),
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
      label: 'New features as we add them',
      freeIncluded: false,
      proLabel: 'Always included',
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
