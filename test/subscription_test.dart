// Stage 11 tests — Monetization: usage quota tracking, feature gating triggers,
// subscription status, restore purchases and the upgrade flow.
//
// The offline LocalSubscriptionService (revenueCatReadyProvider defaults false)
// backs the controllers here, so purchases/restores are deterministic and need
// no native SDK. pump() (not pumpAndSettle) is used because the paywall's
// animations loop forever.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
import 'package:matheasy/features/auth/domain/app_user.dart';
import 'package:matheasy/features/paywall/application/paywall_controller.dart';
import 'package:matheasy/features/paywall/presentation/paywall_copy.dart';
import 'package:matheasy/features/paywall/presentation/paywall_screen.dart';
import 'package:matheasy/features/practice/application/practice_controller.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/subscription/application/subscription_cache.dart';
import 'package:matheasy/features/subscription/application/subscription_controller.dart';
import 'package:matheasy/features/subscription/application/subscription_service.dart';
import 'package:matheasy/features/subscription/application/usage_controller.dart';
import 'package:matheasy/features/subscription/application/usage_tracker.dart';
import 'package:matheasy/features/subscription/domain/entitlement.dart';
import 'package:matheasy/features/subscription/domain/paywall_trigger.dart';
import 'package:matheasy/features/subscription/domain/purchase_result.dart';
import 'package:matheasy/features/subscription/domain/subscription_plan.dart';
import 'package:matheasy/features/subscription/domain/subscription_product.dart';
import 'package:matheasy/features/subscription/domain/subscription_status.dart';
import 'package:matheasy/features/subscription/domain/usage_counts.dart';
import 'package:matheasy/features/subscription/domain/usage_quota.dart';
import 'package:matheasy/features/subscription/domain/usage_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

/// A subscription service whose `purchase()` returns [PurchasePending] (the
/// sandbox receipt-validation lag), then lets the test push the granted
/// entitlement onto the status stream LATER — reproducing the "grey/stuck
/// paywall after a successful sandbox payment" bug.
class _PendingThenActiveService implements SubscriptionService {
  final StreamController<SubscriptionStatus> _controller =
      StreamController<SubscriptionStatus>.broadcast();
  SubscriptionStatus _current = SubscriptionStatus.free;

  @override
  Stream<SubscriptionStatus> statusChanges() => _controller.stream;
  @override
  SubscriptionStatus get currentStatus => _current;
  @override
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async =>
      const PurchasePending(); // receipt not validated yet
  @override
  Future<PurchaseResult> restore() async => const PurchaseNothingToRestore();
  @override
  Future<List<SubscriptionProduct>> loadProducts() async =>
      [for (final p in SubscriptionPlan.paidPlans) SubscriptionProduct.fallback(p)];
  @override
  Future<void> refresh() async {}
  @override
  Future<void> logIn(String appUserId) async {}
  @override
  Future<void> logOut() async {}
  @override
  Future<void> attachAdAttribution({String? fbAnonymousId}) async {}
  @override
  void dispose() => unawaited(_controller.close());

  /// Simulates the entitlement propagating AFTER purchase() already returned.
  void activatePro() {
    _current = const SubscriptionStatus(
      entitlement: Entitlement.pro,
      activePlan: SubscriptionPlan.proAnnual,
    );
    _controller.add(_current);
  }
}

/// Keeps the keepAlive controllers alive across a test (mirrors settings_test).
void _activate(ProviderContainer container) {
  container
    ..listen(subscriptionControllerProvider, (_, _) {})
    ..listen(usageControllerProvider, (_, _) {});
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

UsageSnapshot _snapshot(ProviderContainer c) => c.read(usageSnapshotProvider);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // ---- Domain: quota / snapshot logic ----
  group('UsageSnapshot (free tier)', () {
    UsageSnapshot free(UsageCounts counts) =>
        UsageSnapshot(counts: counts, quota: UsageQuota.free, isPro: false);

    test('allows actions under the limit and blocks at it', () {
      final atFour = free(const UsageCounts(scansUsed: 4));
      expect(atFour.canScan, isTrue);
      expect(atFour.remainingScans, 1);

      final atFive = free(const UsageCounts(scansUsed: 5));
      expect(atFive.canScan, isFalse);
      expect(atFive.remainingScans, 0);
    });

    test('remaining never goes negative past the limit', () {
      final over = free(const UsageCounts(scansUsed: 9));
      expect(over.remainingScans, 0);
      expect(over.canScan, isFalse);
    });

    test('each feature tracks its own limit', () {
      const counts = UsageCounts(
        tutorMessagesUsed: 20,
        practiceQuestionsGenerated: 3,
      );
      final snap = free(counts);
      expect(snap.canSendTutorMessage, isFalse); // 20/20
      expect(snap.canGeneratePractice, isTrue); // 3/10
      expect(snap.remainingPracticeQuestions, 7);
    });
  });

  group('UsageSnapshot (Pro)', () {
    test('is unlimited regardless of counts', () {
      const snap = UsageSnapshot(
        counts: UsageCounts(
          scansUsed: 999,
          tutorMessagesUsed: 999,
          practiceQuestionsGenerated: 999,
        ),
        quota: UsageQuota.free,
        isPro: true,
      );
      expect(snap.canScan, isTrue);
      expect(snap.canSendTutorMessage, isTrue);
      expect(snap.canGeneratePractice, isTrue);
      expect(snap.remainingScans, UsageQuota.unlimited);
      expect(snap.limit(UsageFeature.scan), UsageQuota.unlimited);
    });
  });

  group('Entitlement / SubscriptionPlan', () {
    test('entitlement ordering gates by level', () {
      expect(Entitlement.pro.grants(Entitlement.pro), isTrue);
      expect(Entitlement.none.grants(Entitlement.pro), isFalse);
      expect(Entitlement.pro.isPaid, isTrue);
      expect(Entitlement.pro.revenueCatId, 'pro');
      expect(Entitlement.none.revenueCatId, isNull);
    });

    test('plan resolves from product id and exposes the paid set', () {
      expect(SubscriptionPlan.fromProductId('matheasy_pro_annual'),
          SubscriptionPlan.proAnnual);
      expect(SubscriptionPlan.fromProductId('matheasy_pro_monthly'),
          SubscriptionPlan.proMonthly);
      expect(SubscriptionPlan.fromProductId('nope'), isNull);
      expect(SubscriptionPlan.paidPlans, [
        SubscriptionPlan.proAnnual,
        SubscriptionPlan.proMonthly,
      ]);
      expect(SubscriptionPlan.free.isPaid, isFalse);
    });
  });

  group('SubscriptionStatus', () {
    test('free is not pro; active pro is', () {
      expect(SubscriptionStatus.free.isPro, isFalse);
      const pro = SubscriptionStatus(entitlement: Entitlement.pro);
      expect(pro.isPro, isTrue);
    });

    test('cancelled-but-active detection', () {
      // willRenew defaults to false → the cancelled-but-active case.
      final cancelled = SubscriptionStatus(
        entitlement: Entitlement.pro,
        expiresAt: DateTime(2099),
      );
      expect(cancelled.isCancelledButActive, isTrue);

      final renewing = SubscriptionStatus(
        entitlement: Entitlement.pro,
        willRenew: true,
        expiresAt: DateTime(2099),
      );
      expect(renewing.isCancelledButActive, isFalse);
    });
  });

  // ---- Persistence ----
  group('UsageCounts / UsageTracker persistence', () {
    test('JSON round-trips; corrupt fields degrade to 0', () {
      const counts = UsageCounts(
        scansUsed: 3,
        tutorMessagesUsed: 7,
        practiceQuestionsGenerated: 2,
      );
      expect(UsageCounts.fromJson(counts.toJson()), counts);
      expect(
        UsageCounts.fromJson(const {'scansUsed': 'x', 'tutorMessagesUsed': -4}),
        UsageCounts.empty,
      );
    });

    test('tracker defaults empty and saves/loads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tracker = LocalUsageTracker(PreferencesStore(prefs));
      expect(tracker.load(), UsageCounts.empty);

      await tracker.save(const UsageCounts(scansUsed: 5));
      expect(tracker.load().scansUsed, 5);
    });

    test('corrupt tracker payload falls back to empty', () async {
      SharedPreferences.setMockInitialValues({'subscription.usage': 'nope'});
      final prefs = await SharedPreferences.getInstance();
      expect(LocalUsageTracker(PreferencesStore(prefs)).load(),
          UsageCounts.empty);
    });
  });

  group('SubscriptionCache', () {
    test('round-trips a pro status', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = SubscriptionCache(PreferencesStore(prefs));

      final status = SubscriptionStatus(
        entitlement: Entitlement.pro,
        activePlan: SubscriptionPlan.proAnnual,
        willRenew: true,
        expiresAt: DateTime(2099, 6),
      );
      await cache.write(status);

      final loaded = cache.read();
      expect(loaded?.isPro, isTrue);
      expect(loaded?.activePlan, SubscriptionPlan.proAnnual);
      expect(loaded?.expiresAt, DateTime(2099, 6));
    });

    test('missing / corrupt cache reads null', () async {
      SharedPreferences.setMockInitialValues({'subscription.cache': '{oops'});
      final prefs = await SharedPreferences.getInstance();
      expect(SubscriptionCache(PreferencesStore(prefs)).read(), isNull);
    });
  });

  // ---- UsageController ----
  group('UsageController', () {
    test('records each feature and persists', () async {
      final container = await _container();
      _activate(container);
      final usage = container.read(usageControllerProvider.notifier);

      usage
        ..recordScan()
        ..recordScan()
        ..recordTutorMessage()
        ..recordPracticeGenerated(5);

      final counts = container.read(usageControllerProvider);
      expect(counts.scansUsed, 2);
      expect(counts.tutorMessagesUsed, 1);
      expect(counts.practiceQuestionsGenerated, 5);

      await _pump();
      final store = container.read(preferencesStoreProvider);
      expect(LocalUsageTracker(store).load().scansUsed, 2);
    });

    test('recordPracticeGenerated ignores non-positive counts', () async {
      final container = await _container();
      _activate(container);
      container.read(usageControllerProvider.notifier)
        ..recordPracticeGenerated(0)
        ..recordPracticeGenerated(-3);
      expect(container.read(usageControllerProvider).practiceQuestionsGenerated,
          0);
    });

    test('hydrates from persisted counts', () async {
      final container = await _container(seed: {
        'subscription.usage':
            '{"scansUsed":5,"tutorMessagesUsed":1,"practiceQuestionsGenerated":0}',
      });
      _activate(container);
      expect(container.read(usageControllerProvider).scansUsed, 5);
      expect(_snapshot(container).canScan, isFalse); // limit reached
    });
  });

  // ---- Subscription / upgrade / restore flow ----
  group('SubscriptionController (offline service)', () {
    test('starts free', () async {
      final container = await _container();
      _activate(container);
      expect(container.read(subscriptionControllerProvider).isPro, isFalse);
      expect(container.read(isProProvider), isFalse);
    });

    test('purchase grants pro and reopens every gate', () async {
      final container = await _container(seed: {
        'subscription.usage':
            '{"scansUsed":5,"tutorMessagesUsed":20,"practiceQuestionsGenerated":10}',
      });
      _activate(container);

      // Free + fully used → all gates closed.
      expect(_snapshot(container).canScan, isFalse);
      expect(_snapshot(container).canSendTutorMessage, isFalse);
      expect(_snapshot(container).canGeneratePractice, isFalse);

      final result = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);

      expect(result, isA<PurchaseSuccess>());
      expect(container.read(isProProvider), isTrue);
      // Pro → gates reopen despite exhausted counts.
      expect(_snapshot(container).canScan, isTrue);
      expect(_snapshot(container).canSendTutorMessage, isTrue);
      expect(_snapshot(container).canGeneratePractice, isTrue);
    });

    test('purchase persists so a relaunch warm-starts pro', () async {
      final container = await _container();
      _activate(container);
      await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proMonthly);
      await _pump();

      final store = container.read(preferencesStoreProvider);
      expect(SubscriptionCache(store).read()?.isPro, isTrue);
    });

    test('restore returns nothing to restore when free, success once owned',
        () async {
      final container = await _container();
      _activate(container);

      final empty = await container
          .read(subscriptionControllerProvider.notifier)
          .restore();
      expect(empty, isA<PurchaseNothingToRestore>());

      await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(SubscriptionPlan.proAnnual);
      final restored = await container
          .read(subscriptionControllerProvider.notifier)
          .restore();
      expect(restored, isA<PurchaseSuccess>());
    });
  });

  // ---- PaywallController ----
  group('PaywallController', () {
    test('defaults to the annual plan and loads a catalog', () async {
      final container = await _container();
      final state = container.read(paywallControllerProvider);
      expect(state.selectedPlan, SubscriptionPlan.proAnnual);
      // Fallback catalog is seeded immediately (two paid plans).
      expect(state.products.length, 2);
    });

    test('select switches the highlighted plan', () async {
      final container = await _container();
      container
          .read(paywallControllerProvider.notifier)
          .select(SubscriptionPlan.proMonthly);
      expect(container.read(paywallControllerProvider).selectedPlan,
          SubscriptionPlan.proMonthly);
    });

    test('purchaseSelected succeeds and records the result', () async {
      final container = await _container();
      _activate(container);
      final result = await container
          .read(paywallControllerProvider.notifier)
          .purchaseSelected();
      expect(result, isA<PurchaseSuccess>());
      expect(container.read(isProProvider), isTrue);
      expect(container.read(paywallControllerProvider).result,
          isA<PurchaseSuccess>());
    });
  });

  // ---- Practice gating ----
  group('Practice gating (PracticeController)', () {
    test('locks when the practice quota is exhausted', () async {
      final container = await _container(seed: {
        'subscription.usage':
            '{"scansUsed":0,"tutorMessagesUsed":0,"practiceQuestionsGenerated":10}',
      });
      _activate(container);

      await container
          .read(practiceControllerProvider.notifier)
          .start(const PracticeRequest(topic: PracticeTopic.algebra));

      expect(container.read(practiceControllerProvider).phase,
          PracticePhase.locked);
    });

    test('generates and consumes quota when under the limit', () async {
      final container = await _container();
      _activate(container);

      await container
          .read(practiceControllerProvider.notifier)
          .start(const PracticeRequest(topic: PracticeTopic.algebra));

      final state = container.read(practiceControllerProvider);
      expect(state.phase, PracticePhase.answering);
      final generated = state.session!.questions.length;
      expect(generated, greaterThan(0));
      expect(container.read(usageControllerProvider).practiceQuestionsGenerated,
          generated);
    });
  });

  // ---- Paywall widget ----
  group('Paywall widget', () {
    Future<ProviderContainer> pumpPaywall(WidgetTester tester,
        {PaywallTrigger trigger = PaywallTrigger.scanLimit}) async {
      final container = await _container();
      // The paywall stacks a hero, a "what you get with Pro" value strip and
      // three plan cards in a ListView; use a tall surface so every plan card
      // builds without scrolling (a real device scrolls). Reset afterwards.
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: PaywallScreen(trigger: trigger),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('renders headline, plans and a purchase CTA', (tester) async {
      await pumpPaywall(tester);
      expect(find.text('Unlock Unlimited Learning'), findsOneWidget);
      expect(find.text('Annual Pro'), findsOneWidget);
      expect(find.text('Monthly Pro'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      // The CTA carries no price — the price stays on the selected card + the
      // auto-renew disclosure. 'Unlock Unlimited' is an exact match, so it does
      // not collide with the 'Unlock Unlimited Learning' headline.
      expect(find.text('Unlock Unlimited'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      // Store-required disclosure stays intact and keeps the price visible.
      expect(find.textContaining('Auto-renews at'), findsOneWidget);
    });

    testWidgets('purchasing shows the success celebration', (tester) async {
      final container = await pumpPaywall(tester);
      await tester.tap(find.text('Unlock Unlimited'));
      await tester.pump(); // kick off purchase
      await tester.pump(); // settle result listener
      expect(find.text("You're all set!"), findsOneWidget);
      expect(container.read(isProProvider), isTrue);
      // Flush the auto-dismiss timer so none stays pending.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a PENDING purchase that activates later still celebrates + '
        'dismisses (the grey/stuck-after-paying regression)', (tester) async {
      final service = _PendingThenActiveService();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        subscriptionServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PaywallScreen(trigger: PaywallTrigger.scanLimit),
          ),
        ),
      );
      await tester.pump();

      // Sandbox lag: purchase() returns Pending → NO celebration, NOT yet Pro.
      // (Before the fix the paywall would sit here forever.)
      await tester.tap(find.text('Unlock Unlimited'));
      await tester.pump();
      await tester.pump();
      expect(find.text("You're all set!"), findsNothing);
      expect(container.read(isProProvider), isFalse);

      // The entitlement propagates via the customer-info stream. The fix must
      // now celebrate + dismiss instead of stranding the user on the paywall.
      service.activatePro();
      await tester.pump(); // stream → controller state = pro → isPro flips
      await tester.pump(); // celebration setState
      expect(container.read(isProProvider), isTrue);
      expect(find.text("You're all set!"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // flush the dismiss timer
    });
  });

  group('SubscriptionProduct pricing (per-month framing)', () {
    SubscriptionProduct annual({
      required String priceString,
      double? rawPrice,
      String? pricePerMonthString,
    }) => SubscriptionProduct(
      plan: SubscriptionPlan.proAnnual,
      priceString: priceString,
      rawPrice: rawPrice,
      pricePerMonthString: pricePerMonthString,
    );

    test('extracts the currency symbol the store returned', () {
      expect(annual(priceString: 'RM149.99').currencySymbol, 'RM');
      expect(annual(priceString: r'$59.99').currencySymbol, r'$');
      expect(annual(priceString: '€9,99').currencySymbol, '€');
      expect(annual(priceString: 'RM0').currencySymbol, 'RM');
      // Non-Latin numerals (Devanagari) must not leak into the symbol.
      expect(annual(priceString: '₹१,२९९').currencySymbol, '₹');
    });

    test('computes per-month as annual ÷ 12 with the store symbol (MYR)', () {
      // 149.99 / 12 = 12.4991… → 12.50, symbol taken from the price string.
      expect(
        annual(priceString: 'RM149.99', rawPrice: 149.99).pricePerMonthComputed,
        'RM12.50',
      );
    });

    test('renders correctly on a non-MYR storefront (USD)', () {
      expect(
        annual(priceString: r'$60.00', rawPrice: 60).pricePerMonthComputed,
        r'$5.00',
      );
    });

    test('prefers the store localized per-month string over hand-computing', () {
      // A comma-decimal locale: the store string must win so the numerals and
      // separator stay correct (hand-computing would force "€12.50").
      expect(
        annual(
          priceString: '€149,99',
          rawPrice: 149.99,
          pricePerMonthString: '€12,50',
        ).pricePerMonthComputed,
        '€12,50',
      );
    });

    test('computes only when the store gives no per-month string, else null',
        () {
      // No store per-month + no raw price -> null (no live price to compute).
      expect(annual(priceString: 'RM149.99').pricePerMonthComputed, isNull);
    });

    test('annual value line shows the billed-yearly total + computed saving',
        () {
      final a = annual(priceString: 'RM149.99', rawPrice: 149.99);
      const m = SubscriptionProduct(
        plan: SubscriptionPlan.proMonthly,
        priceString: 'RM19.99',
        rawPrice: 19.99,
      );
      // 12×19.99 = 239.88; (239.88−149.99)/239.88 ≈ 37%.
      expect(
        PaywallCopy.annualValueLine(a, m),
        'RM149.99 billed yearly · Save 37%',
      );
    });

    test('saving reconciles with the prices shown (never a fabricated %)', () {
      // Partial catalog: annual is live (RM120/yr) but monthly fell back to its
      // constant (RM19.99). The saving must be computed from those two shown
      // prices — 12×19.99=239.88 vs 120 -> ~50% — not a hardcoded 37%.
      final liveAnnual = annual(priceString: 'RM120.00', rawPrice: 120);
      final fallbackMonthly =
          SubscriptionProduct.fallback(SubscriptionPlan.proMonthly);
      expect(
        PaywallCopy.annualValueLine(liveAnnual, fallbackMonthly),
        'RM120.00 billed yearly · Save 50%',
      );
    });

    test('fallback products carry a numeric price parsed from the constant', () {
      expect(
        SubscriptionProduct.fallback(SubscriptionPlan.proAnnual).rawPrice,
        149.99,
      );
      // Offline (both fallback) still reconciles: 149.99 vs 12×19.99 -> 37%.
      expect(
        PaywallCopy.annualValueLine(
          SubscriptionProduct.fallback(SubscriptionPlan.proAnnual),
          SubscriptionProduct.fallback(SubscriptionPlan.proMonthly),
        ),
        'RM149.99 billed yearly · Save 37%',
      );
    });

    test('no savings claim when it cannot be computed from both prices', () {
      // With no price data at all we must not assert any percentage.
      expect(PaywallCopy.annualValueLine(null, null), 'Best value');
    });
  });

  group('RevenueCat billing identity (revenueCatIdentitySyncProvider)', () {
    ProviderContainer containerFor(AppUser? user) {
      final fake = _RecordingSubscriptionService();
      final container = ProviderContainer(
        overrides: [
          subscriptionServiceProvider.overrideWithValue(fake),
          currentUserProvider.overrideWith((ref) => user),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('logs in a signed-in user by their Firebase uid', () async {
      final container = containerFor(
        AppUser(
          id: 'uid_abc123',
          provider: AuthProviderType.apple,
          isGuest: false,
          createdAt: DateTime(2024),
        ),
      );
      container.read(revenueCatIdentitySyncProvider); // fireImmediately
      await Future<void>.delayed(Duration.zero);

      final fake = container.read(subscriptionServiceProvider)
          as _RecordingSubscriptionService;
      expect(fake.loggedInAs, 'uid_abc123');
      expect(fake.logOutCount, 0);
    });

    test('logs out (anonymous) for a guest session', () async {
      final container = containerFor(AppUser.guest(createdAt: DateTime(2024)));
      container.read(revenueCatIdentitySyncProvider);
      await Future<void>.delayed(Duration.zero);

      final fake = container.read(subscriptionServiceProvider)
          as _RecordingSubscriptionService;
      expect(fake.loggedInAs, isNull);
      expect(fake.logOutCount, 1);
    });

    test('logs out when signed out (no user)', () async {
      final container = containerFor(null);
      container.read(revenueCatIdentitySyncProvider);
      await Future<void>.delayed(Duration.zero);

      final fake = container.read(subscriptionServiceProvider)
          as _RecordingSubscriptionService;
      expect(fake.loggedInAs, isNull);
      expect(fake.logOutCount, 1);
    });
  });
}

/// Records the billing-identity calls the sync provider makes. Only [logIn] /
/// [logOut] are exercised, so the rest is handled by [noSuchMethod].
class _RecordingSubscriptionService implements SubscriptionService {
  String? loggedInAs;
  int logOutCount = 0;

  @override
  Future<void> logIn(String appUserId) async {
    loggedInAs = appUserId;
  }

  @override
  Future<void> logOut() async {
    logOutCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
