// Stage 10 tests — Settings (learning preferences, notifications, appearance,
// accessibility) persistence + the SettingsController.
//
// pump() (not pumpAndSettle) is used because the app's toggle/section animations
// run on looping/entrance controllers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/onboarding/domain/onboarding_models.dart';
import 'package:matheasy/features/settings/application/settings_controller.dart';
import 'package:matheasy/features/settings/application/settings_repository.dart';
import 'package:matheasy/features/settings/domain/accessibility_settings.dart';
import 'package:matheasy/features/settings/domain/appearance_settings.dart';
import 'package:matheasy/features/settings/domain/difficulty_preference.dart';
import 'package:matheasy/features/settings/domain/learning_goal.dart';
import 'package:matheasy/features/settings/domain/learning_preferences.dart';
import 'package:matheasy/features/settings/domain/notification_settings.dart';
import 'package:matheasy/features/settings/domain/profile_settings.dart';
import 'package:matheasy/features/settings/presentation/accessibility_settings_screen.dart';
import 'package:matheasy/features/settings/presentation/appearance_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void _activate(ProviderContainer container) {
  container.listen(settingsControllerProvider, (_, _) {});
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('SettingsRepository', () {
    test('defaults to ProfileSettings.defaults when nothing is stored',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalSettingsRepository(PreferencesStore(prefs));
      expect(repository.load(), ProfileSettings.defaults);
    });

    test('round-trips every setting', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalSettingsRepository(PreferencesStore(prefs));

      const settings = ProfileSettings(
        learning: LearningPreferences(
          gradeLevel: StudyLevel.spm,
          learningGoal: LearningGoal.examPrep,
          dailyGoal: DailyGoal.min15,
          topics: {MathTopic.algebra, MathTopic.geometry},
          difficulty: DifficultyPreference.challenging,
        ),
        notifications: NotificationSettings(practiceReminder: false),
        appearance: AppearanceSettings(themeMode: ThemeMode.dark),
        accessibility: AccessibilitySettings(largerText: true),
      );
      await repository.save(settings);

      final loaded = repository.load();
      expect(loaded.learning.gradeLevel, StudyLevel.spm);
      expect(loaded.learning.learningGoal, LearningGoal.examPrep);
      expect(loaded.learning.dailyGoal, DailyGoal.min15);
      expect(loaded.learning.topics,
          {MathTopic.algebra, MathTopic.geometry});
      expect(loaded.learning.difficulty, DifficultyPreference.challenging);
      expect(loaded.notifications.practiceReminder, isFalse);
      expect(loaded.notifications.streakReminder, isTrue); // untouched default
      expect(loaded.appearance.themeMode, ThemeMode.dark);
      expect(loaded.accessibility.largerText, isTrue);
      expect(loaded, settings);
    });

    test('corrupt payload falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'settings.preferences': 'not json',
      });
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalSettingsRepository(PreferencesStore(prefs));
      expect(repository.load(), ProfileSettings.defaults);
    });
  });

  group('SettingsController — theme', () {
    test('setThemeMode updates state and persists', () async {
      final container = await _container();
      _activate(container);

      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      expect(
        container.read(settingsControllerProvider).appearance.themeMode,
        ThemeMode.dark,
      );

      await _pump();
      final store = container.read(preferencesStoreProvider);
      expect(
        LocalSettingsRepository(store).load().appearance.themeMode,
        ThemeMode.dark,
      );
    });
  });

  group('SettingsController — learning preferences', () {
    test('sets grade, goal, difficulty and toggles topics', () async {
      final container = await _container();
      _activate(container);
      final controller =
          container.read(settingsControllerProvider.notifier);

      controller
        ..setGradeLevel(StudyLevel.igcse)
        ..setLearningGoal(LearningGoal.getAhead)
        ..setDailyGoal(DailyGoal.min30)
        ..setDifficulty(DifficultyPreference.easy)
        ..toggleTopic(MathTopic.calculus)
        ..toggleTopic(MathTopic.algebra)
        ..toggleTopic(MathTopic.calculus); // toggles calculus back off

      final learning =
          container.read(settingsControllerProvider).learning;
      expect(learning.gradeLevel, StudyLevel.igcse);
      expect(learning.learningGoal, LearningGoal.getAhead);
      expect(learning.dailyGoal, DailyGoal.min30);
      expect(learning.difficulty, DifficultyPreference.easy);
      expect(learning.topics, {MathTopic.algebra});
    });
  });

  group('SettingsController — notifications & accessibility', () {
    test('notification reminders toggle and persist', () async {
      final container = await _container();
      _activate(container);
      container
          .read(settingsControllerProvider.notifier)
          .setPracticeReminder(value: false);

      expect(
        container
            .read(settingsControllerProvider)
            .notifications
            .practiceReminder,
        isFalse,
      );

      await _pump();
      final store = container.read(preferencesStoreProvider);
      expect(
        LocalSettingsRepository(store).load().notifications.practiceReminder,
        isFalse,
      );
    });

    test('accessibility toggles update state', () async {
      final container = await _container();
      _activate(container);
      final controller =
          container.read(settingsControllerProvider.notifier);

      controller
        ..setLargerText(value: true)
        ..setReducedMotion(value: true);

      final a = container.read(settingsControllerProvider).accessibility;
      expect(a.largerText, isTrue);
      expect(a.reducedMotion, isTrue);
      expect(a.textScale, greaterThan(1.0));
    });

    test('reset restores defaults', () async {
      final container = await _container();
      _activate(container);
      final controller =
          container.read(settingsControllerProvider.notifier);
      controller
        ..setThemeMode(ThemeMode.dark)
        ..setHighContrast(value: true);

      controller.reset();
      expect(container.read(settingsControllerProvider),
          ProfileSettings.defaults);
    });
  });

  group('Widgets', () {
    testWidgets('appearance screen selects and applies a theme',
        (tester) async {
      final container = await _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppearanceSettingsScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Dark'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(
        container.read(settingsControllerProvider).appearance.themeMode,
        ThemeMode.dark,
      );
    });

    testWidgets('tapping an accessibility row flips its switch',
        (tester) async {
      final container = await _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AccessibilitySettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(settingsControllerProvider).accessibility.largerText,
        isFalse,
      );
      await tester.tap(find.text('Larger text'));
      await tester.pump();
      expect(
        container.read(settingsControllerProvider).accessibility.largerText,
        isTrue,
      );
    });
  });
}
