/// Centralized route paths and names. Screens and navigation calls reference
/// these constants instead of raw strings.
///
/// Locations are grouped by navigation branch. Tab-root locations (`/home`,
/// `/practice`, `/scan`, `/tutor`, `/profile`) live inside the
/// [StatefulShellRoute]; their sub-routes (session, chat, result, settings…)
/// and the top-level flows (onboarding, auth, paywall) are pushed over the
/// shell on the root navigator.
class AppRoutes {
  const AppRoutes._();

  // ---- Shell tab roots (branch order = tab order) ----
  static const String home = '/home';
  static const String practice = '/practice';
  static const String scan = '/scan';
  static const String tutor = '/tutor';
  static const String profile = '/profile';
  static const String progress = '/progress';

  static const String homeName = 'home';
  static const String practiceName = 'practice';
  static const String scanName = 'scan';
  static const String tutorName = 'tutor';
  static const String profileName = 'profile';
  static const String progressName = 'progress';

  // ---- Sub-routes (relative segment + absolute location + name) ----
  static const String scanResultSegment = 'result';
  static const String scanResult = '/scan/result';
  static const String scanResultName = 'scanResult';

  static const String practiceSessionSegment = 'session';
  static const String practiceSession = '/practice/session';
  static const String practiceSessionName = 'practiceSession';

  static const String tutorChatSegment = 'chat';
  static const String tutorChat = '/tutor/chat';
  static const String tutorChatName = 'tutorChat';

  static const String profileSettingsSegment = 'settings';
  static const String profileSettings = '/profile/settings';
  static const String profileSettingsName = 'profileSettings';

  static const String profileSubscriptionSegment = 'subscription';
  static const String profileSubscription = '/profile/subscription';
  static const String profileSubscriptionName = 'profileSubscription';

  static const String progressAchievementsSegment = 'achievements';
  static const String progressAchievements = '/progress/achievements';
  static const String progressAchievementsName = 'progressAchievements';

  // ---- Top-level flows (over the shell) ----
  static const String splash = '/splash';
  static const String splashName = 'splash';

  static const String onboarding = '/onboarding';
  static const String onboardingName = 'onboarding';

  static const String auth = '/auth';
  static const String authName = 'auth';

  static const String paywall = '/paywall';
  static const String paywallName = 'paywall';

  static const String gallery = '/gallery';
  static const String galleryName = 'gallery';

  /// Branch index for each tab root (must match the order of branches in the
  /// [StatefulShellRoute]). Scan is NOT a branch — it's a full-screen route
  /// pushed over the shell from the center Scan button.
  static const int homeBranch = 0;
  static const int practiceBranch = 1;
  static const int tutorBranch = 2;
  static const int profileBranch = 3;
  static const int progressBranch = 4;
}
