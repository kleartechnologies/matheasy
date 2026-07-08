// Stage 10 tests — Profile: the editable profile, the assembled ProfileView and
// the account actions (edit, sign out, delete) + guest upgrade.
//
// pump() (not pumpAndSettle) is used because the profile stat count-up and
// section-reveal animations run on entrance controllers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/session/app_session.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
import 'package:matheasy/features/auth/application/auth_service.dart';
import 'package:matheasy/features/auth/domain/app_user.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/profile/application/profile_controller.dart';
import 'package:matheasy/features/profile/application/profile_service.dart';
import 'package:matheasy/features/profile/domain/editable_profile.dart';
import 'package:matheasy/features/profile/domain/profile_avatar.dart';
import 'package:matheasy/features/profile/presentation/profile_screen.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart';
import 'package:matheasy/features/settings/application/settings_controller.dart';
import 'package:matheasy/features/settings/domain/profile_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';

final _fixedNow = DateTime(2026, 7, 8);

Future<ProviderContainer> _container({bool guest = false, AppUser? signedIn}) async {
  SharedPreferences.setMockInitialValues({
    'session.onboarding_complete': true,
    if (guest) 'session.guest_mode': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authServiceProvider.overrideWithValue(FakeAuthService(initialUser: signedIn)),
      clockProvider.overrideWithValue(() => _fixedNow),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void _activate(ProviderContainer container) {
  container
    ..listen(authControllerProvider, (_, _) {})
    ..listen(profileControllerProvider, (_, _) {})
    ..listen(practiceProgressControllerProvider, (_, _) {})
    ..listen(settingsControllerProvider, (_, _) {});
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ProfileService', () {
    test('round-trips display name and avatar', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalProfileService(PreferencesStore(prefs));

      await service.save(
        const EditableProfile(displayName: 'Numi Fan', avatar: ProfileAvatar.sunset),
      );
      final loaded = service.load();
      expect(loaded.displayName, 'Numi Fan');
      expect(loaded.avatar, ProfileAvatar.sunset);
    });

    test('missing profile loads defaults; corrupt payload too', () async {
      SharedPreferences.setMockInitialValues({'profile.editable': 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalProfileService(PreferencesStore(prefs));
      expect(service.load(), EditableProfile.defaults);
    });
  });

  group('ProfileController — assembly & editing', () {
    test('assembles identity + stats for a signed-in user', () async {
      final container = await _container(signedIn: googleTestUser());
      _activate(container);
      await _settle();

      final view = container.read(profileControllerProvider);
      expect(view.isGuest, isFalse);
      expect(view.provider, AuthProviderType.google);
      expect(view.displayName, 'Sarah Lee');
      expect(view.email, 'sarah@example.com');
      expect(view.initial, 'S');
      expect(view.stats.level, greaterThanOrEqualTo(1));
    });

    test('saveProfile overrides the display name and persists', () async {
      final container = await _container(signedIn: googleTestUser());
      _activate(container);
      await _settle();

      container.read(profileControllerProvider.notifier).saveProfile(
            displayName: 'Math Whiz',
            avatar: ProfileAvatar.meadow,
          );
      await _settle();

      final view = container.read(profileControllerProvider);
      expect(view.displayName, 'Math Whiz');
      expect(view.editable.avatar, ProfileAvatar.meadow);

      final store = container.read(preferencesStoreProvider);
      expect(LocalProfileService(store).load().displayName, 'Math Whiz');
    });

    test('a blank name clears the override and falls back to the account name',
        () async {
      final container = await _container(signedIn: googleTestUser());
      _activate(container);
      await _settle();

      container
          .read(profileControllerProvider.notifier)
          .saveProfile(displayName: '   ', avatar: ProfileAvatar.ocean);
      await _settle();

      final view = container.read(profileControllerProvider);
      expect(view.editable.displayName, isNull);
      expect(view.displayName, 'Sarah Lee');
    });

    test('a guest with no name shows a friendly fallback', () async {
      final container = await _container(guest: true);
      _activate(container);
      await _settle();

      final view = container.read(profileControllerProvider);
      expect(view.isGuest, isTrue);
      expect(view.provider, AuthProviderType.guest);
      expect(view.displayName, 'Guest learner');
    });
  });

  group('Account actions', () {
    test('signOut ends the session', () async {
      final container = await _container(signedIn: googleTestUser());
      _activate(container);
      await _settle();
      expect(container.read(authStatusProvider), AuthStatus.authenticated);

      await container.read(profileControllerProvider.notifier).signOut();
      await _settle();

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
    });

    test('deleteAccount ends the session and wipes local data', () async {
      final container = await _container(guest: true);
      _activate(container);
      await _settle();

      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      container.read(practiceProgressControllerProvider.notifier).awardXp(50);
      await _settle();
      expect(container.read(authControllerProvider).isGuest, isTrue);

      await container.read(profileControllerProvider.notifier).deleteAccount();
      await _settle();

      expect(container.read(authStatusProvider), AuthStatus.unauthenticated);
      final store = container.read(preferencesStoreProvider);
      expect(store.settingsJson, isNull);
      expect(store.practiceProgressJson, isNull);
      expect(store.profileJson, isNull);
      expect(
        container.read(settingsControllerProvider),
        ProfileSettings.defaults,
      );
      expect(container.read(practiceProgressControllerProvider).totalXp, 0);
    });

    test('guest upgrade preserves local progress and settings', () async {
      final container = await _container(guest: true);
      _activate(container);
      await _settle();

      container.read(practiceProgressControllerProvider.notifier).awardXp(80);
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await _settle();

      await container.read(authControllerProvider.notifier).signInWithGoogle();
      await _settle();

      final auth = container.read(authControllerProvider);
      expect(auth.isGuest, isFalse);
      expect(auth.user?.provider, AuthProviderType.google);
      expect(container.read(practiceProgressControllerProvider).totalXp, 80);
      expect(
        container.read(settingsControllerProvider).appearance.themeMode,
        ThemeMode.dark,
      );
    });
  });

  group('Widgets', () {
    testWidgets('guest profile shows the create-account upsell',
        (tester) async {
      final container = await _container(guest: true);
      _activate(container);
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Create free account'), findsOneWidget);
      expect(find.text('Guest account'), findsOneWidget);
      expect(find.text('Delete guest data'), findsOneWidget);
    });

    testWidgets('signed-in profile shows account details', (tester) async {
      final container = await _container(signedIn: googleTestUser());
      _activate(container);
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Sarah Lee'), findsWidgets);
      expect(find.textContaining('Signed in with Google'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    });
  });
}
