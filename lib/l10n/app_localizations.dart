import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_ms.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('ms'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get navPractice;

  /// No description provided for @navProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get navProgress;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionUnlockPro.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pro'**
  String get actionUnlockPro;

  /// No description provided for @actionTypeIt.
  ///
  /// In en, this message translates to:
  /// **'Type it'**
  String get actionTypeIt;

  /// No description provided for @actionRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get actionRescan;

  /// No description provided for @commonNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get commonNotSet;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLearningPreferences.
  ///
  /// In en, this message translates to:
  /// **'Learning preferences'**
  String get settingsLearningPreferences;

  /// No description provided for @settingsStudyProfile.
  ///
  /// In en, this message translates to:
  /// **'Study profile'**
  String get settingsStudyProfile;

  /// No description provided for @settingsGradeLevel.
  ///
  /// In en, this message translates to:
  /// **'Grade level'**
  String get settingsGradeLevel;

  /// No description provided for @settingsLearningGoal.
  ///
  /// In en, this message translates to:
  /// **'Learning goal'**
  String get settingsLearningGoal;

  /// No description provided for @settingsDailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get settingsDailyGoal;

  /// No description provided for @settingsPracticeDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Practice difficulty'**
  String get settingsPracticeDifficulty;

  /// No description provided for @settingsFocusTopics.
  ///
  /// In en, this message translates to:
  /// **'Focus topics'**
  String get settingsFocusTopics;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The language of every explanation, question and tutor reply. Math notation stays universal.'**
  String get settingsLanguageSubtitle;

  /// No description provided for @difficultyVeryEasy.
  ///
  /// In en, this message translates to:
  /// **'Very Easy'**
  String get difficultyVeryEasy;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// No description provided for @difficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// No description provided for @difficultyExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get difficultyExpert;

  /// No description provided for @practiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get practiceTitle;

  /// No description provided for @practiceDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get practiceDifficulty;

  /// No description provided for @practiceRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get practiceRecommended;

  /// No description provided for @practiceDailyChallenge.
  ///
  /// In en, this message translates to:
  /// **'Daily Challenge'**
  String get practiceDailyChallenge;

  /// No description provided for @resultTabSolution.
  ///
  /// In en, this message translates to:
  /// **'Solution'**
  String get resultTabSolution;

  /// No description provided for @resultTabExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get resultTabExplain;

  /// No description provided for @resultTabMethods.
  ///
  /// In en, this message translates to:
  /// **'Methods'**
  String get resultTabMethods;

  /// No description provided for @resultTabPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get resultTabPractice;

  /// No description provided for @resultTabVisual.
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get resultTabVisual;

  /// No description provided for @resultDetected.
  ///
  /// In en, this message translates to:
  /// **'Detected'**
  String get resultDetected;

  /// No description provided for @resultFinalAnswer.
  ///
  /// In en, this message translates to:
  /// **'FINAL ANSWER'**
  String get resultFinalAnswer;

  /// No description provided for @resultPlayStepByStep.
  ///
  /// In en, this message translates to:
  /// **'Play step-by-step'**
  String get resultPlayStepByStep;

  /// No description provided for @tutorTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Tutor'**
  String get tutorTitle;

  /// No description provided for @tutorAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy'**
  String get tutorAsk;

  /// No description provided for @tutorHint.
  ///
  /// In en, this message translates to:
  /// **'Give me a hint'**
  String get tutorHint;

  /// No description provided for @homeHeroPrompt.
  ///
  /// In en, this message translates to:
  /// **'What would you like to solve today?'**
  String get homeHeroPrompt;

  /// No description provided for @homeHeroScanQuestion.
  ///
  /// In en, this message translates to:
  /// **'Scan Question'**
  String get homeHeroScanQuestion;

  /// No description provided for @homeHeroType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get homeHeroType;

  /// No description provided for @homeOpenProfile.
  ///
  /// In en, this message translates to:
  /// **'Open profile'**
  String get homeOpenProfile;

  /// No description provided for @homeContinueLearning.
  ///
  /// In en, this message translates to:
  /// **'Continue learning'**
  String get homeContinueLearning;

  /// No description provided for @homeRecommendedForYou.
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get homeRecommendedForYou;

  /// No description provided for @homeTodaysChallenge.
  ///
  /// In en, this message translates to:
  /// **'Today\'s challenge'**
  String get homeTodaysChallenge;

  /// No description provided for @homeCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get homeCompletedToday;

  /// No description provided for @homeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeRecent;

  /// No description provided for @homeSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// No description provided for @practiceLevelShort.
  ///
  /// In en, this message translates to:
  /// **'LV'**
  String get practiceLevelShort;

  /// No description provided for @practiceNoStreak.
  ///
  /// In en, this message translates to:
  /// **'No streak yet'**
  String get practiceNoStreak;

  /// No description provided for @practiceVisualTitle.
  ///
  /// In en, this message translates to:
  /// **'Visual walkthrough'**
  String get practiceVisualTitle;

  /// No description provided for @practiceVisualNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to visualize right now.'**
  String get practiceVisualNothing;

  /// No description provided for @practiceVisualLoading.
  ///
  /// In en, this message translates to:
  /// **'Matheasy is sketching your visual walkthrough…'**
  String get practiceVisualLoading;

  /// No description provided for @practiceVisualProFeature.
  ///
  /// In en, this message translates to:
  /// **'Visual Learning is a Matheasy Pro feature.'**
  String get practiceVisualProFeature;

  /// No description provided for @practiceSeeProPlans.
  ///
  /// In en, this message translates to:
  /// **'See Pro plans'**
  String get practiceSeeProPlans;

  /// No description provided for @practiceVisualUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The visual walkthrough isn\'t available right now. Give it another try in a moment.'**
  String get practiceVisualUnavailable;

  /// No description provided for @practiceBackToPractice.
  ///
  /// In en, this message translates to:
  /// **'Back to practice'**
  String get practiceBackToPractice;

  /// No description provided for @practiceResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get practiceResults;

  /// No description provided for @practiceBuildingSession.
  ///
  /// In en, this message translates to:
  /// **'Building your session…'**
  String get practiceBuildingSession;

  /// No description provided for @practiceSessionStartError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t start that session. Please try again.'**
  String get practiceSessionStartError;

  /// No description provided for @practiceOnARoll.
  ///
  /// In en, this message translates to:
  /// **'You\'re on a roll!'**
  String get practiceOnARoll;

  /// No description provided for @practiceFreeLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used all your free practice questions. Go Pro for unlimited practice tailored to you.'**
  String get practiceFreeLimitReached;

  /// No description provided for @practiceMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get practiceMaybeLater;

  /// No description provided for @practiceSeeResults.
  ///
  /// In en, this message translates to:
  /// **'See results'**
  String get practiceSeeResults;

  /// No description provided for @practiceCheckAnswer.
  ///
  /// In en, this message translates to:
  /// **'Check answer'**
  String get practiceCheckAnswer;

  /// No description provided for @practiceAllTopics.
  ///
  /// In en, this message translates to:
  /// **'All topics'**
  String get practiceAllTopics;

  /// No description provided for @practiceStrengthenThese.
  ///
  /// In en, this message translates to:
  /// **'Strengthen these'**
  String get practiceStrengthenThese;

  /// No description provided for @practiceContinueTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue practice'**
  String get practiceContinueTitle;

  /// No description provided for @practiceRecommendedForYou.
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get practiceRecommendedForYou;

  /// No description provided for @practiceAskMatheasyWhy.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy why'**
  String get practiceAskMatheasyWhy;

  /// No description provided for @practiceShowVisually.
  ///
  /// In en, this message translates to:
  /// **'Show me visually'**
  String get practiceShowVisually;

  /// No description provided for @practiceUntimed.
  ///
  /// In en, this message translates to:
  /// **'Untimed practice'**
  String get practiceUntimed;

  /// No description provided for @practiceNoTimer.
  ///
  /// In en, this message translates to:
  /// **'No timer'**
  String get practiceNoTimer;

  /// No description provided for @practiceTypeAnswer.
  ///
  /// In en, this message translates to:
  /// **'Type your answer'**
  String get practiceTypeAnswer;

  /// No description provided for @practiceOptionCorrectSuffix.
  ///
  /// In en, this message translates to:
  /// **', correct answer'**
  String get practiceOptionCorrectSuffix;

  /// No description provided for @practiceOptionWrongSuffix.
  ///
  /// In en, this message translates to:
  /// **', your answer, incorrect'**
  String get practiceOptionWrongSuffix;

  /// No description provided for @practicePerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect! 🎉'**
  String get practicePerfect;

  /// No description provided for @practiceSessionComplete.
  ///
  /// In en, this message translates to:
  /// **'Session complete!'**
  String get practiceSessionComplete;

  /// No description provided for @practiceKeepPracticing.
  ///
  /// In en, this message translates to:
  /// **'Keep practicing'**
  String get practiceKeepPracticing;

  /// No description provided for @practiceStatCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get practiceStatCorrect;

  /// No description provided for @practiceStatAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get practiceStatAccuracy;

  /// No description provided for @practiceStatXpEarned.
  ///
  /// In en, this message translates to:
  /// **'XP earned'**
  String get practiceStatXpEarned;

  /// No description provided for @tutorNewConversationStarted.
  ///
  /// In en, this message translates to:
  /// **'Started a new conversation'**
  String get tutorNewConversationStarted;

  /// No description provided for @tutorBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get tutorBack;

  /// No description provided for @tutorNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get tutorNewConversation;

  /// No description provided for @tutorImageUploadSoon.
  ///
  /// In en, this message translates to:
  /// **'Image upload arrives soon.'**
  String get tutorImageUploadSoon;

  /// No description provided for @tutorVoiceChatSoon.
  ///
  /// In en, this message translates to:
  /// **'Voice chat arrives soon.'**
  String get tutorVoiceChatSoon;

  /// No description provided for @tutorEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy anything'**
  String get tutorEmptyTitle;

  /// No description provided for @tutorEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Snap a photo or type a question and get a clear, step-by-step explanation.'**
  String get tutorEmptyMessage;

  /// No description provided for @tutorTyping.
  ///
  /// In en, this message translates to:
  /// **'Matheasy is typing'**
  String get tutorTyping;

  /// No description provided for @tutorTagline.
  ///
  /// In en, this message translates to:
  /// **'Your AI math tutor'**
  String get tutorTagline;

  /// No description provided for @tutorHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'How can I help today?'**
  String get tutorHeroTitle;

  /// No description provided for @tutorHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask me anything about math.'**
  String get tutorHeroSubtitle;

  /// No description provided for @tutorAskMatheasy.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy'**
  String get tutorAskMatheasy;

  /// No description provided for @tutorExploreTopics.
  ///
  /// In en, this message translates to:
  /// **'Explore topics'**
  String get tutorExploreTopics;

  /// No description provided for @tutorQuickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get tutorQuickActionsTitle;

  /// No description provided for @tutorRecentConversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent conversations'**
  String get tutorRecentConversationsTitle;

  /// No description provided for @tutorTryAsking.
  ///
  /// In en, this message translates to:
  /// **'Try asking'**
  String get tutorTryAsking;

  /// No description provided for @tutorUploadQuestion.
  ///
  /// In en, this message translates to:
  /// **'Upload a question'**
  String get tutorUploadQuestion;

  /// No description provided for @tutorInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy anything…'**
  String get tutorInputHint;

  /// No description provided for @tutorVoiceInput.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get tutorVoiceInput;

  /// No description provided for @tutorSendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get tutorSendMessage;

  /// No description provided for @tutorPracticeLabel.
  ///
  /// In en, this message translates to:
  /// **'PRACTICE'**
  String get tutorPracticeLabel;

  /// No description provided for @tutorTryIt.
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get tutorTryIt;

  /// No description provided for @tutorQuickQuiz.
  ///
  /// In en, this message translates to:
  /// **'QUICK QUIZ'**
  String get tutorQuickQuiz;

  /// No description provided for @tutorQuizCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct — well done! 🎉'**
  String get tutorQuizCorrect;

  /// No description provided for @tutorQuizNotQuite.
  ///
  /// In en, this message translates to:
  /// **'Not quite — but close!'**
  String get tutorQuizNotQuite;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingWelcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Make Math Easy'**
  String get onboardingWelcomeHeadline;

  /// No description provided for @onboardingWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your personal AI Math Tutor.'**
  String get onboardingWelcomeSubtitle;

  /// No description provided for @onboardingSnapHeadline.
  ///
  /// In en, this message translates to:
  /// **'Snap Any Math Question'**
  String get onboardingSnapHeadline;

  /// No description provided for @onboardingSnapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at any problem and get a clear, step-by-step answer in seconds.'**
  String get onboardingSnapSubtitle;

  /// No description provided for @onboardingSnapCaption.
  ///
  /// In en, this message translates to:
  /// **'Linear equation · one unknown'**
  String get onboardingSnapCaption;

  /// No description provided for @onboardingUnderstandHeadline.
  ///
  /// In en, this message translates to:
  /// **'Understand Every Step'**
  String get onboardingUnderstandHeadline;

  /// No description provided for @onboardingUnderstandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Matheasy explains the why behind each step — so it actually sticks, not just copies.'**
  String get onboardingUnderstandSubtitle;

  /// No description provided for @onboardingUnderstandQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why do we subtract 5?'**
  String get onboardingUnderstandQuestion;

  /// No description provided for @onboardingUnderstandAnswer.
  ///
  /// In en, this message translates to:
  /// **'To get 2x on its own we undo the +5 first. Whatever we do to one side, we do to the other. 👍'**
  String get onboardingUnderstandAnswer;

  /// No description provided for @onboardingPracticeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Practice Until You Master It'**
  String get onboardingPracticeHeadline;

  /// No description provided for @onboardingPracticeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlimited practice, XP, streaks and achievements keep you motivated every day.'**
  String get onboardingPracticeSubtitle;

  /// No description provided for @onboardingAchievementTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharp Shooter'**
  String get onboardingAchievementTitle;

  /// No description provided for @onboardingExamHeadline.
  ///
  /// In en, this message translates to:
  /// **'Built For Your Exams'**
  String get onboardingExamHeadline;

  /// No description provided for @onboardingExamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized help tuned to SPM, IGCSE, GCSE, SAT and more.'**
  String get onboardingExamSubtitle;

  /// No description provided for @onboardingMeetHeadline.
  ///
  /// In en, this message translates to:
  /// **'Meet Matheasy'**
  String get onboardingMeetHeadline;

  /// No description provided for @onboardingMeetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your AI Math Coach.'**
  String get onboardingMeetSubtitle;

  /// No description provided for @onboardingCompletionHeadline.
  ///
  /// In en, this message translates to:
  /// **'You\'re Ready To Start Learning.'**
  String get onboardingCompletionHeadline;

  /// No description provided for @onboardingCompletionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Matheasy will guide you every step of the way.'**
  String get onboardingCompletionSubtitle;

  /// No description provided for @onboardingStudyLevelQuestion.
  ///
  /// In en, this message translates to:
  /// **'What are you studying?'**
  String get onboardingStudyLevelQuestion;

  /// No description provided for @onboardingStudyLevelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We tailor every lesson and exam to your level.'**
  String get onboardingStudyLevelSubtitle;

  /// No description provided for @onboardingChallengeQuestion.
  ///
  /// In en, this message translates to:
  /// **'What do you find hardest?'**
  String get onboardingChallengeQuestion;

  /// No description provided for @onboardingChallengeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick as many as you like — we\'ll help you strengthen them.'**
  String get onboardingChallengeSubtitle;

  /// No description provided for @onboardingDailyGoalQuestion.
  ///
  /// In en, this message translates to:
  /// **'How much would you like to study each day?'**
  String get onboardingDailyGoalQuestion;

  /// No description provided for @onboardingDailyGoalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Little and often beats cramming. You can change this anytime.'**
  String get onboardingDailyGoalSubtitle;

  /// No description provided for @paywallHeadline.
  ///
  /// In en, this message translates to:
  /// **'Unlock Unlimited Learning'**
  String get paywallHeadline;

  /// No description provided for @paywallConfirmingPurchase.
  ///
  /// In en, this message translates to:
  /// **'Confirming your purchase — this can take a moment…'**
  String get paywallConfirmingPurchase;

  /// No description provided for @paywallNothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'No previous purchases found to restore.'**
  String get paywallNothingToRestore;

  /// No description provided for @paywallPlanAnnual.
  ///
  /// In en, this message translates to:
  /// **'Annual Pro'**
  String get paywallPlanAnnual;

  /// No description provided for @paywallPlanMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly Pro'**
  String get paywallPlanMonthly;

  /// No description provided for @paywallPlanFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get paywallPlanFree;

  /// No description provided for @paywallPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/month'**
  String get paywallPerMonth;

  /// No description provided for @paywallPerYear.
  ///
  /// In en, this message translates to:
  /// **'/year'**
  String get paywallPerYear;

  /// No description provided for @paywallForever.
  ///
  /// In en, this message translates to:
  /// **'forever'**
  String get paywallForever;

  /// No description provided for @paywallBadgeBestValue.
  ///
  /// In en, this message translates to:
  /// **'BEST VALUE'**
  String get paywallBadgeBestValue;

  /// No description provided for @paywallMonthlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything unlimited, billed monthly'**
  String get paywallMonthlySubtitle;

  /// No description provided for @paywallFreePlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'5 scans · 20 AI tutor messages · 10 practice'**
  String get paywallFreePlanSubtitle;

  /// No description provided for @paywallWhatYouGet.
  ///
  /// In en, this message translates to:
  /// **'What you get with Pro'**
  String get paywallWhatYouGet;

  /// No description provided for @paywallAlreadyPro.
  ///
  /// In en, this message translates to:
  /// **'You\'re on Matheasy Pro 🎉'**
  String get paywallAlreadyPro;

  /// No description provided for @paywallContinueFree.
  ///
  /// In en, this message translates to:
  /// **'Continue with Free'**
  String get paywallContinueFree;

  /// No description provided for @paywallUnlockUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlock Unlimited'**
  String get paywallUnlockUnlimited;

  /// No description provided for @paywallFreeDisclosure.
  ///
  /// In en, this message translates to:
  /// **'You can upgrade anytime. Free includes limited scans, AI tutor and practice.'**
  String get paywallFreeDisclosure;

  /// No description provided for @paywallRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get paywallRestoring;

  /// No description provided for @paywallRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get paywallRestore;

  /// No description provided for @paywallComparePlans.
  ///
  /// In en, this message translates to:
  /// **'COMPARE PLANS'**
  String get paywallComparePlans;

  /// No description provided for @paywallColumnFree.
  ///
  /// In en, this message translates to:
  /// **'FREE'**
  String get paywallColumnFree;

  /// No description provided for @paywallColumnPro.
  ///
  /// In en, this message translates to:
  /// **'PRO'**
  String get paywallColumnPro;

  /// No description provided for @paywallAllSet.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set!'**
  String get paywallAllSet;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileExitGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit guest session?'**
  String get profileExitGuestTitle;

  /// No description provided for @profileSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get profileSignOutTitle;

  /// No description provided for @profileExitGuestMessage.
  ///
  /// In en, this message translates to:
  /// **'Your guest progress stays on this device — you can continue as a guest again anytime.'**
  String get profileExitGuestMessage;

  /// No description provided for @profileSignOutMessage.
  ///
  /// In en, this message translates to:
  /// **'You can sign back in anytime to pick up where you left off.'**
  String get profileSignOutMessage;

  /// No description provided for @profileExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get profileExit;

  /// No description provided for @profileSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get profileSignOut;

  /// No description provided for @profileDeleteGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete guest data?'**
  String get profileDeleteGuestTitle;

  /// No description provided for @profileDeleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get profileDeleteAccountTitle;

  /// No description provided for @profileDeleteWarning.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your progress, achievements, learning preferences and settings from this device. This cannot be undone.'**
  String get profileDeleteWarning;

  /// No description provided for @profileDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you absolutely sure?'**
  String get profileDeleteConfirmTitle;

  /// No description provided for @profileDeleteGuestConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your guest data will be erased immediately.'**
  String get profileDeleteGuestConfirmMessage;

  /// No description provided for @profileDeleteAccountConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Your account and all learning data will be erased immediately.'**
  String get profileDeleteAccountConfirmMessage;

  /// No description provided for @profileDeleteData.
  ///
  /// In en, this message translates to:
  /// **'Delete data'**
  String get profileDeleteData;

  /// No description provided for @profileDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get profileDeleteAccount;

  /// No description provided for @profileKeepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get profileKeepIt;

  /// No description provided for @profileSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications, appearance, accessibility'**
  String get profileSettingsSubtitle;

  /// No description provided for @profileExitGuestSession.
  ///
  /// In en, this message translates to:
  /// **'Exit guest session'**
  String get profileExitGuestSession;

  /// No description provided for @profileDeleteGuestData.
  ///
  /// In en, this message translates to:
  /// **'Delete guest data'**
  String get profileDeleteGuestData;

  /// No description provided for @profileUpdatedToast.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdatedToast;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditTitle;

  /// No description provided for @profileAvatarLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} avatar'**
  String profileAvatarLabel(String label);

  /// No description provided for @profileDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get profileDisplayNameLabel;

  /// No description provided for @profileLearningSection.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get profileLearningSection;

  /// No description provided for @profileLearningPreferences.
  ///
  /// In en, this message translates to:
  /// **'Learning preferences'**
  String get profileLearningPreferences;

  /// No description provided for @profileLearningPreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Grade, goal, topics & difficulty'**
  String get profileLearningPreferencesSubtitle;

  /// No description provided for @profileSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get profileSaveButton;

  /// No description provided for @profileNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get profileNameHint;

  /// No description provided for @profileRestoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your Pro subscription has been restored.'**
  String get profileRestoreSuccess;

  /// No description provided for @profileRestoreNothing.
  ///
  /// In en, this message translates to:
  /// **'No previous purchases found to restore.'**
  String get profileRestoreNothing;

  /// No description provided for @profileRestoreFinished.
  ///
  /// In en, this message translates to:
  /// **'Restore finished.'**
  String get profileRestoreFinished;

  /// No description provided for @profileManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get profileManageSubscription;

  /// No description provided for @profileManageIosMessage.
  ///
  /// In en, this message translates to:
  /// **'Open the App Store app → tap your profile → Subscriptions to change or cancel your plan. Changes sync back automatically.'**
  String get profileManageIosMessage;

  /// No description provided for @profileManageAndroidMessage.
  ///
  /// In en, this message translates to:
  /// **'Open the Play Store app → Menu → Payments & subscriptions → Subscriptions to change or cancel your plan. Changes sync back automatically.'**
  String get profileManageAndroidMessage;

  /// No description provided for @profileGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get profileGotIt;

  /// No description provided for @profileSubscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get profileSubscriptionTitle;

  /// No description provided for @profileAnnualPro.
  ///
  /// In en, this message translates to:
  /// **'Annual Pro'**
  String get profileAnnualPro;

  /// No description provided for @profileMonthlyPro.
  ///
  /// In en, this message translates to:
  /// **'Monthly Pro'**
  String get profileMonthlyPro;

  /// No description provided for @profileMatheasyPro.
  ///
  /// In en, this message translates to:
  /// **'Matheasy Pro'**
  String get profileMatheasyPro;

  /// No description provided for @profileActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profileActive;

  /// No description provided for @profileBillingIssue.
  ///
  /// In en, this message translates to:
  /// **'There is a billing issue — update your payment method to keep Pro.'**
  String get profileBillingIssue;

  /// No description provided for @profileFreePlan.
  ///
  /// In en, this message translates to:
  /// **'Free plan'**
  String get profileFreePlan;

  /// No description provided for @profileFreePlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro for unlimited scans, AI tutor and practice.'**
  String get profileFreePlanSubtitle;

  /// No description provided for @profileUpgradeToPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get profileUpgradeToPro;

  /// No description provided for @profileYourUsage.
  ///
  /// In en, this message translates to:
  /// **'Your usage'**
  String get profileYourUsage;

  /// No description provided for @profileUsageScans.
  ///
  /// In en, this message translates to:
  /// **'Scans'**
  String get profileUsageScans;

  /// No description provided for @profileUsageTutor.
  ///
  /// In en, this message translates to:
  /// **'AI tutor messages'**
  String get profileUsageTutor;

  /// No description provided for @profileUsagePractice.
  ///
  /// In en, this message translates to:
  /// **'Practice questions'**
  String get profileUsagePractice;

  /// No description provided for @profileManageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Change plan or cancel'**
  String get profileManageSubtitle;

  /// No description provided for @profileRestorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get profileRestorePurchases;

  /// No description provided for @profileRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recover a subscription bought before'**
  String get profileRestoreSubtitle;

  /// No description provided for @profileGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re learning as a guest'**
  String get profileGuestTitle;

  /// No description provided for @profileGuestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a free account to keep your progress safe.'**
  String get profileGuestSubtitle;

  /// No description provided for @profileCreateFreeAccount.
  ///
  /// In en, this message translates to:
  /// **'Create free account'**
  String get profileCreateFreeAccount;

  /// No description provided for @profileContinueLearning.
  ///
  /// In en, this message translates to:
  /// **'Continue learning'**
  String get profileContinueLearning;

  /// No description provided for @profileNoScansLeft.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used your free scans — go unlimited'**
  String get profileNoScansLeft;

  /// No description provided for @profileUpgradeMatheasyPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Matheasy Pro'**
  String get profileUpgradeMatheasyPro;

  /// No description provided for @profileProSemantics.
  ///
  /// In en, this message translates to:
  /// **'Matheasy Pro. Manage subscription'**
  String get profileProSemantics;

  /// No description provided for @profileProSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlimited everything · manage plan'**
  String get profileProSubtitle;

  /// No description provided for @profileStatStreak.
  ///
  /// In en, this message translates to:
  /// **'Day streak'**
  String get profileStatStreak;

  /// No description provided for @profileStatBadges.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get profileStatBadges;

  /// No description provided for @profileStatMastered.
  ///
  /// In en, this message translates to:
  /// **'Mastered'**
  String get profileStatMastered;

  /// No description provided for @profileMemberRecently.
  ///
  /// In en, this message translates to:
  /// **'Recently'**
  String get profileMemberRecently;

  /// No description provided for @profileAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccountSection;

  /// No description provided for @profileMemberSince.
  ///
  /// In en, this message translates to:
  /// **'Member since'**
  String get profileMemberSince;

  /// No description provided for @profileFreePlanUsage.
  ///
  /// In en, this message translates to:
  /// **'Free plan usage'**
  String get profileFreePlanUsage;

  /// No description provided for @profileBenefitProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Preserve your progress'**
  String get profileBenefitProgressTitle;

  /// No description provided for @profileBenefitProgressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your XP, streak and achievements.'**
  String get profileBenefitProgressSubtitle;

  /// No description provided for @profileBenefitSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync future data'**
  String get profileBenefitSyncTitle;

  /// No description provided for @profileBenefitSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick up on any device once sync arrives.'**
  String get profileBenefitSyncSubtitle;

  /// No description provided for @profileBenefitFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock future features'**
  String get profileBenefitFeaturesTitle;

  /// No description provided for @profileBenefitFeaturesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Be first to try new tools as they launch.'**
  String get profileBenefitFeaturesSubtitle;

  /// No description provided for @profileCreateAccountSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your free account'**
  String get profileCreateAccountSheetTitle;

  /// No description provided for @profileGuestUpgradedToast.
  ///
  /// In en, this message translates to:
  /// **'Welcome! Your progress is saved.'**
  String get profileGuestUpgradedToast;

  /// No description provided for @profileGuestUpgradeFootnote.
  ///
  /// In en, this message translates to:
  /// **'Your progress stays on this device and links to your new account.'**
  String get profileGuestUpgradeFootnote;

  /// No description provided for @profileAvatarSemantics.
  ///
  /// In en, this message translates to:
  /// **'Profile avatar'**
  String get profileAvatarSemantics;

  /// No description provided for @progressBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get progressBack;

  /// No description provided for @progressAchievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get progressAchievementsTitle;

  /// No description provided for @progressSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get progressSeeAll;

  /// No description provided for @progressMatheasySays.
  ///
  /// In en, this message translates to:
  /// **'Matheasy says'**
  String get progressMatheasySays;

  /// No description provided for @progressRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get progressRecentActivity;

  /// No description provided for @progressQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get progressQuestions;

  /// No description provided for @progressSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get progressSessions;

  /// No description provided for @progressTopics.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get progressTopics;

  /// No description provided for @progressMasteryOverview.
  ///
  /// In en, this message translates to:
  /// **'Mastery overview'**
  String get progressMasteryOverview;

  /// No description provided for @progressAchievementUnlocked.
  ///
  /// In en, this message translates to:
  /// **'ACHIEVEMENT UNLOCKED'**
  String get progressAchievementUnlocked;

  /// No description provided for @progressAwesome.
  ///
  /// In en, this message translates to:
  /// **'Awesome!'**
  String get progressAwesome;

  /// No description provided for @scanCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t take the photo. Try again.'**
  String get scanCaptureFailed;

  /// No description provided for @scanGalleryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your photos.'**
  String get scanGalleryFailed;

  /// No description provided for @scanHintHoldSteady.
  ///
  /// In en, this message translates to:
  /// **'Hold steady on the question — I’ll capture it'**
  String get scanHintHoldSteady;

  /// No description provided for @scanHintLineUp.
  ///
  /// In en, this message translates to:
  /// **'Line up the whole question, then tap to capture'**
  String get scanHintLineUp;

  /// No description provided for @scanAutoCaptureOn.
  ///
  /// In en, this message translates to:
  /// **'Auto capture on'**
  String get scanAutoCaptureOn;

  /// No description provided for @scanAutoCaptureOff.
  ///
  /// In en, this message translates to:
  /// **'Auto capture off'**
  String get scanAutoCaptureOff;

  /// No description provided for @scanAutoOn.
  ///
  /// In en, this message translates to:
  /// **'Auto on'**
  String get scanAutoOn;

  /// No description provided for @scanAutoOff.
  ///
  /// In en, this message translates to:
  /// **'Auto off'**
  String get scanAutoOff;

  /// No description provided for @scanCloseScanner.
  ///
  /// In en, this message translates to:
  /// **'Close scanner'**
  String get scanCloseScanner;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a problem'**
  String get scanTitle;

  /// No description provided for @scanFlashOff.
  ///
  /// In en, this message translates to:
  /// **'Turn flash off'**
  String get scanFlashOff;

  /// No description provided for @scanFlashOn.
  ///
  /// In en, this message translates to:
  /// **'Turn flash on'**
  String get scanFlashOn;

  /// No description provided for @scanBrandHint.
  ///
  /// In en, this message translates to:
  /// **'Point at a whole question — I’ll read it for you.'**
  String get scanBrandHint;

  /// No description provided for @scanGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get scanGallery;

  /// No description provided for @scanTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get scanTakePhoto;

  /// No description provided for @scanErrorRecognizeTitle.
  ///
  /// In en, this message translates to:
  /// **'That was hard to read'**
  String get scanErrorRecognizeTitle;

  /// No description provided for @scanErrorRecognizeBody.
  ///
  /// In en, this message translates to:
  /// **'Line the whole problem up in good light and try again — or type it in and I’ll take it from there.'**
  String get scanErrorRecognizeBody;

  /// No description provided for @scanTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get scanTryAgain;

  /// No description provided for @scanErrorOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get scanErrorOfflineTitle;

  /// No description provided for @scanErrorOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Reading a new problem needs a connection. Your saved solutions still open offline — reconnect and try again.'**
  String get scanErrorOfflineBody;

  /// No description provided for @scanErrorGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'That scan didn’t go through'**
  String get scanErrorGenericTitle;

  /// No description provided for @scanErrorGenericBody.
  ///
  /// In en, this message translates to:
  /// **'Something interrupted it. Give it another try, or type the problem in instead.'**
  String get scanErrorGenericBody;

  /// No description provided for @scanTypeItIn.
  ///
  /// In en, this message translates to:
  /// **'Type it in'**
  String get scanTypeItIn;

  /// No description provided for @scanCameraDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Matheasy needs the camera to scan problems'**
  String get scanCameraDeniedTitle;

  /// No description provided for @scanCameraDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'It\'s turned off right now. Turn it on in Settings, or pick a photo or type the problem instead.'**
  String get scanCameraDeniedBody;

  /// No description provided for @scanOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get scanOpenSettings;

  /// No description provided for @scanCameraUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Your camera isn’t available'**
  String get scanCameraUnavailableTitle;

  /// No description provided for @scanCameraUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Something’s blocking it on this device. You can still pick a photo or type the problem in.'**
  String get scanCameraUnavailableBody;

  /// No description provided for @scanConfirmLowConfidence.
  ///
  /// In en, this message translates to:
  /// **'This might be misread — tap the problem to fix it before solving.'**
  String get scanConfirmLowConfidence;

  /// No description provided for @scanRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get scanRetake;

  /// No description provided for @scanSolve.
  ///
  /// In en, this message translates to:
  /// **'Solve'**
  String get scanSolve;

  /// No description provided for @scanEditEquation.
  ///
  /// In en, this message translates to:
  /// **'Edit the detected equation'**
  String get scanEditEquation;

  /// No description provided for @manualErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get manualErrorGeneric;

  /// No description provided for @manualFixProblem.
  ///
  /// In en, this message translates to:
  /// **'Fix the problem'**
  String get manualFixProblem;

  /// No description provided for @manualTypeProblem.
  ///
  /// In en, this message translates to:
  /// **'Type a problem'**
  String get manualTypeProblem;

  /// No description provided for @manualUseThis.
  ///
  /// In en, this message translates to:
  /// **'Use this'**
  String get manualUseThis;

  /// No description provided for @manualPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'Build your problem with the math keyboard'**
  String get manualPreviewEmpty;

  /// No description provided for @cropFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t crop that. Try again.'**
  String get cropFailed;

  /// No description provided for @cropCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel crop'**
  String get cropCancel;

  /// No description provided for @cropTitle.
  ///
  /// In en, this message translates to:
  /// **'Crop the problem'**
  String get cropTitle;

  /// No description provided for @cropInstruction.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners around just the problem.'**
  String get cropInstruction;

  /// No description provided for @cropPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get cropPreparing;

  /// No description provided for @cropUsePhoto.
  ///
  /// In en, this message translates to:
  /// **'Use photo'**
  String get cropUsePhoto;

  /// No description provided for @keyboardMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get keyboardMoveLeft;

  /// No description provided for @keyboardMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get keyboardMoveRight;

  /// No description provided for @keyboardDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get keyboardDelete;

  /// No description provided for @resultBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get resultBack;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Solution'**
  String get resultTitle;

  /// No description provided for @resultShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get resultShare;

  /// No description provided for @resultSharingSoon.
  ///
  /// In en, this message translates to:
  /// **'Sharing arrives soon.'**
  String get resultSharingSoon;

  /// No description provided for @resultSolvingMessage.
  ///
  /// In en, this message translates to:
  /// **'Matheasy is solving your problem…'**
  String get resultSolvingMessage;

  /// No description provided for @resultPracticeReady.
  ///
  /// In en, this message translates to:
  /// **'Fresh practice ready below 👇'**
  String get resultPracticeReady;

  /// No description provided for @resultSavedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Saved to your library'**
  String get resultSavedToLibrary;

  /// No description provided for @resultRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get resultRemoved;

  /// No description provided for @resultOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get resultOfflineTitle;

  /// No description provided for @resultOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'I need a connection to work out a new solution. Your saved solutions still open offline — reconnect and try again.'**
  String get resultOfflineMessage;

  /// No description provided for @resultSolveErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'That one didn\'t go through'**
  String get resultSolveErrorTitle;

  /// No description provided for @resultSolveErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'I couldn\'t work that solution out just now. Give it another try.'**
  String get resultSolveErrorMessage;

  /// No description provided for @resultNoProblemMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing to solve yet — scan a problem and I will walk you through it.'**
  String get resultNoProblemMessage;

  /// No description provided for @resultScanAProblem.
  ///
  /// In en, this message translates to:
  /// **'Scan a problem'**
  String get resultScanAProblem;

  /// No description provided for @practiceEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No practice yet — want a few problems just like this one? I\'ll build them for you.'**
  String get practiceEmptyMessage;

  /// No description provided for @practiceGeneratePractice.
  ///
  /// In en, this message translates to:
  /// **'Generate practice'**
  String get practiceGeneratePractice;

  /// No description provided for @practiceMasterItIntro.
  ///
  /// In en, this message translates to:
  /// **'Master it! Here are similar questions tuned to your level.'**
  String get practiceMasterItIntro;

  /// No description provided for @practiceGenerateMore.
  ///
  /// In en, this message translates to:
  /// **'Generate more like this'**
  String get practiceGenerateMore;

  /// No description provided for @methodsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Only one clean method here — sometimes simple is best!'**
  String get methodsEmptyMessage;

  /// No description provided for @methodsIntro.
  ///
  /// In en, this message translates to:
  /// **'Three ways to reach the same answer. Tap one to compare — the badge is my exam pick.'**
  String get methodsIntro;

  /// No description provided for @methodsHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get methodsHideDetails;

  /// No description provided for @methodsSeeHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'See how it works'**
  String get methodsSeeHowItWorks;

  /// No description provided for @methodsStepsLabel.
  ///
  /// In en, this message translates to:
  /// **'STEPS'**
  String get methodsStepsLabel;

  /// No description provided for @methodsGoodFor.
  ///
  /// In en, this message translates to:
  /// **'GOOD FOR'**
  String get methodsGoodFor;

  /// No description provided for @methodsRecommended.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get methodsRecommended;

  /// No description provided for @explainEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No write-up for this one — but I can talk you through it step by step.'**
  String get explainEmptyMessage;

  /// No description provided for @resultAskMatheasy.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy'**
  String get resultAskMatheasy;

  /// No description provided for @explainStillStuck.
  ///
  /// In en, this message translates to:
  /// **'Still stuck? Ask Matheasy'**
  String get explainStillStuck;

  /// No description provided for @visualLoadingMessage.
  ///
  /// In en, this message translates to:
  /// **'Matheasy is sketching your visual walkthrough…'**
  String get visualLoadingMessage;

  /// No description provided for @visualUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The visual walkthrough isn\'t available right now — the Explain tab has the full story in the meantime.'**
  String get visualUnavailableMessage;

  /// No description provided for @visualTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get visualTryAgain;

  /// No description provided for @visualOpenExplain.
  ///
  /// In en, this message translates to:
  /// **'Open Explain'**
  String get visualOpenExplain;

  /// No description provided for @solutionRevealAllSteps.
  ///
  /// In en, this message translates to:
  /// **'Reveal all steps'**
  String get solutionRevealAllSteps;

  /// No description provided for @solutionRevealAll.
  ///
  /// In en, this message translates to:
  /// **'Reveal all'**
  String get solutionRevealAll;

  /// No description provided for @solutionHideWhy.
  ///
  /// In en, this message translates to:
  /// **'Hide why'**
  String get solutionHideWhy;

  /// No description provided for @solutionWhy.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get solutionWhy;

  /// No description provided for @solutionYourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn — '**
  String get solutionYourTurn;

  /// No description provided for @solutionOpenVisualLearning.
  ///
  /// In en, this message translates to:
  /// **'Open Visual Learning'**
  String get solutionOpenVisualLearning;

  /// No description provided for @resultVisualLearningLabel.
  ///
  /// In en, this message translates to:
  /// **'VISUAL LEARNING'**
  String get resultVisualLearningLabel;

  /// No description provided for @solutionVisualHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch every step come alive'**
  String get solutionVisualHeroTitle;

  /// No description provided for @solutionVisualHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Understand the solution — not just the final answer.'**
  String get solutionVisualHeroSubtitle;

  /// No description provided for @resultRescanProblem.
  ///
  /// In en, this message translates to:
  /// **'Rescan the problem'**
  String get resultRescanProblem;

  /// No description provided for @resultPlayWalkthrough.
  ///
  /// In en, this message translates to:
  /// **'Play solution walkthrough'**
  String get resultPlayWalkthrough;

  /// No description provided for @resultGraphHideLabel.
  ///
  /// In en, this message translates to:
  /// **'Hide graph'**
  String get resultGraphHideLabel;

  /// No description provided for @resultGraphShowLabel.
  ///
  /// In en, this message translates to:
  /// **'Show graph'**
  String get resultGraphShowLabel;

  /// No description provided for @resultGraphTitle.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get resultGraphTitle;

  /// No description provided for @resultGraphHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get resultGraphHide;

  /// No description provided for @resultGraphShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get resultGraphShow;

  /// No description provided for @resultRemoveFromSaved.
  ///
  /// In en, this message translates to:
  /// **'Remove from saved'**
  String get resultRemoveFromSaved;

  /// No description provided for @resultSaveSolution.
  ///
  /// In en, this message translates to:
  /// **'Save solution'**
  String get resultSaveSolution;

  /// No description provided for @resultScannedProblem.
  ///
  /// In en, this message translates to:
  /// **'SCANNED PROBLEM'**
  String get resultScannedProblem;

  /// No description provided for @resultScannedImageLabel.
  ///
  /// In en, this message translates to:
  /// **'The problem you scanned'**
  String get resultScannedImageLabel;

  /// No description provided for @resultEditProblem.
  ///
  /// In en, this message translates to:
  /// **'Edit the problem'**
  String get resultEditProblem;

  /// No description provided for @resultWorkThroughTutor.
  ///
  /// In en, this message translates to:
  /// **'Work through it with the tutor'**
  String get resultWorkThroughTutor;

  /// No description provided for @resultCouldntVerify.
  ///
  /// In en, this message translates to:
  /// **'COULDN\'T VERIFY'**
  String get resultCouldntVerify;

  /// No description provided for @resultCouldntVerifyMessage.
  ///
  /// In en, this message translates to:
  /// **'I check every answer by working it back through your problem. This one didn\'t pass, so I\'m not showing an answer at all — that check is the whole point. If I misread anything above, correcting it usually clears this up.'**
  String get resultCouldntVerifyMessage;

  /// No description provided for @resultWhatIRead.
  ///
  /// In en, this message translates to:
  /// **'WHAT I READ'**
  String get resultWhatIRead;

  /// No description provided for @resultTapToFix.
  ///
  /// In en, this message translates to:
  /// **'tap to fix'**
  String get resultTapToFix;

  /// No description provided for @resultLetsReason.
  ///
  /// In en, this message translates to:
  /// **'LET\'S REASON IT THROUGH'**
  String get resultLetsReason;

  /// No description provided for @resultTutorReasonSystem.
  ///
  /// In en, this message translates to:
  /// **'This system of equations may have several solutions — I only show an answer when I can prove it\'s complete, and I can\'t do that here, so I won\'t pretend to. But this is exactly what the tutor is for: we can solve it together and check every step.'**
  String get resultTutorReasonSystem;

  /// No description provided for @resultTutorReasonMultiPart.
  ///
  /// In en, this message translates to:
  /// **'This problem asks for more than one thing, so there\'s no single answer I can check by working it backwards — and I won\'t pretend there is. The tutor is the right tool: we can take it one part at a time.'**
  String get resultTutorReasonMultiPart;

  /// No description provided for @resultTutorReasonProof.
  ///
  /// In en, this message translates to:
  /// **'This is a proof-style problem — there\'s no single answer I can compute and check by working it backwards, so I won\'t pretend there is. But this is exactly what the tutor is for: we can build the argument together, one step at a time.'**
  String get resultTutorReasonProof;

  /// No description provided for @resultPlaySolution.
  ///
  /// In en, this message translates to:
  /// **'Play Solution'**
  String get resultPlaySolution;

  /// No description provided for @resultSolved.
  ///
  /// In en, this message translates to:
  /// **'SOLVED'**
  String get resultSolved;

  /// No description provided for @resultCloseWalkthrough.
  ///
  /// In en, this message translates to:
  /// **'Close walkthrough'**
  String get resultCloseWalkthrough;

  /// No description provided for @resultPreviousStep.
  ///
  /// In en, this message translates to:
  /// **'Previous step'**
  String get resultPreviousStep;

  /// No description provided for @resultPauseWalkthrough.
  ///
  /// In en, this message translates to:
  /// **'Pause walkthrough'**
  String get resultPauseWalkthrough;

  /// No description provided for @resultPlayWalkthroughShort.
  ///
  /// In en, this message translates to:
  /// **'Play walkthrough'**
  String get resultPlayWalkthroughShort;

  /// No description provided for @resultGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get resultGotIt;

  /// No description provided for @resultNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get resultNextStep;

  /// No description provided for @visualStep1Preview.
  ///
  /// In en, this message translates to:
  /// **'Step 1 preview'**
  String get visualStep1Preview;

  /// No description provided for @visualUnlockToContinue.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pro to continue'**
  String get visualUnlockToContinue;

  /// No description provided for @visualUnlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Understand math visually — watch every step unfold.'**
  String get visualUnlockSubtitle;

  /// No description provided for @visualUnlockDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Unlocks every Pro feature · Cancel anytime'**
  String get visualUnlockDisclaimer;

  /// No description provided for @visualProBadge.
  ///
  /// In en, this message translates to:
  /// **'PRO'**
  String get visualProBadge;

  /// No description provided for @visualTapToLearn.
  ///
  /// In en, this message translates to:
  /// **'Tap to learn'**
  String get visualTapToLearn;

  /// No description provided for @visualShowHint.
  ///
  /// In en, this message translates to:
  /// **'Show hint'**
  String get visualShowHint;

  /// No description provided for @visualKeyIdeas.
  ///
  /// In en, this message translates to:
  /// **'KEY IDEAS'**
  String get visualKeyIdeas;

  /// No description provided for @visualAskAboutStep.
  ///
  /// In en, this message translates to:
  /// **'Ask Matheasy about this step'**
  String get visualAskAboutStep;

  /// No description provided for @visualReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get visualReplay;

  /// No description provided for @visualPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get visualPause;

  /// No description provided for @visualPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get visualPlay;

  /// No description provided for @teachingTheIdea.
  ///
  /// In en, this message translates to:
  /// **'THE IDEA'**
  String get teachingTheIdea;

  /// No description provided for @teachingWhatItAsks.
  ///
  /// In en, this message translates to:
  /// **'What it asks'**
  String get teachingWhatItAsks;

  /// No description provided for @teachingThePlan.
  ///
  /// In en, this message translates to:
  /// **'The plan'**
  String get teachingThePlan;

  /// No description provided for @teachingWhyThisMethod.
  ///
  /// In en, this message translates to:
  /// **'Why this method'**
  String get teachingWhyThisMethod;

  /// No description provided for @teachingCompareMethods.
  ///
  /// In en, this message translates to:
  /// **'Compare methods'**
  String get teachingCompareMethods;

  /// No description provided for @teachingWatchOutFor.
  ///
  /// In en, this message translates to:
  /// **'WATCH OUT FOR'**
  String get teachingWatchOutFor;

  /// No description provided for @teachingRememberThis.
  ///
  /// In en, this message translates to:
  /// **'REMEMBER THIS'**
  String get teachingRememberThis;

  /// No description provided for @teachingYourTurn.
  ///
  /// In en, this message translates to:
  /// **'YOUR TURN'**
  String get teachingYourTurn;

  /// No description provided for @teachingPracticeLadderIntro.
  ///
  /// In en, this message translates to:
  /// **'Try these — a gentle warm-up, one just like it, then a stretch.'**
  String get teachingPracticeLadderIntro;

  /// No description provided for @teachingRungEasier.
  ///
  /// In en, this message translates to:
  /// **'Easier'**
  String get teachingRungEasier;

  /// No description provided for @teachingRungHarder.
  ///
  /// In en, this message translates to:
  /// **'Harder'**
  String get teachingRungHarder;

  /// No description provided for @teachingRungSimilar.
  ///
  /// In en, this message translates to:
  /// **'Similar'**
  String get teachingRungSimilar;

  /// No description provided for @teachingAskPrompt.
  ///
  /// In en, this message translates to:
  /// **'Still fuzzy on a step, or want to try the next one yourself? I can talk you through it.'**
  String get teachingAskPrompt;

  /// No description provided for @teachingAskNumi.
  ///
  /// In en, this message translates to:
  /// **'Ask Numi'**
  String get teachingAskNumi;

  /// No description provided for @teachingHowToApproach.
  ///
  /// In en, this message translates to:
  /// **'HOW TO APPROACH IT'**
  String get teachingHowToApproach;

  /// No description provided for @historyBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get historyBack;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get historyClear;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Problems you solve appear here — tap any to re-open the full solution instantly, even offline.'**
  String get historyEmptyMessage;

  /// No description provided for @historyEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Scan a problem'**
  String get historyEmptyAction;

  /// No description provided for @historyClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get historyClearTitle;

  /// No description provided for @historyClearMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes every saved solution from this device. It can’t be undone.'**
  String get historyClearMessage;

  /// No description provided for @historyClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get historyClearConfirm;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Learn math with AI'**
  String get authTagline;

  /// No description provided for @authWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Matheasy! Let\'s start learning together.'**
  String get authWelcome;

  /// No description provided for @authBenefitScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan questions'**
  String get authBenefitScanTitle;

  /// No description provided for @authBenefitScanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Snap any problem and get a clear, worked solution.'**
  String get authBenefitScanSubtitle;

  /// No description provided for @authBenefitLearnTitle.
  ///
  /// In en, this message translates to:
  /// **'Learn faster'**
  String get authBenefitLearnTitle;

  /// No description provided for @authBenefitLearnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Matheasy explains the why, at your level, step by step.'**
  String get authBenefitLearnSubtitle;

  /// No description provided for @authBenefitPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice smarter'**
  String get authBenefitPracticeTitle;

  /// No description provided for @authBenefitPracticeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Targeted practice that adapts as you improve.'**
  String get authBenefitPracticeSubtitle;

  /// No description provided for @authLegalPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to our'**
  String get authLegalPrefix;

  /// No description provided for @authLegalTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get authLegalTerms;

  /// No description provided for @authLegalPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get authLegalPrivacy;

  /// No description provided for @authContinueApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authContinueApple;

  /// No description provided for @authContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueGoogle;

  /// No description provided for @authSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get authSigningIn;

  /// No description provided for @profileAccessUntil.
  ///
  /// In en, this message translates to:
  /// **'Access until {date} · auto-renew off'**
  String profileAccessUntil(String date);

  /// No description provided for @profileRenewsOn.
  ///
  /// In en, this message translates to:
  /// **'Renews on {date}'**
  String profileRenewsOn(String date);

  /// No description provided for @profileSignedInWith.
  ///
  /// In en, this message translates to:
  /// **'Signed in with {provider}'**
  String profileSignedInWith(String provider);

  /// No description provided for @profileStatsLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String profileStatsLevel(int level);

  /// No description provided for @profileStatsXpToNextLevel.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to Level {level}'**
  String profileStatsXpToNextLevel(int xp, int level);

  /// No description provided for @profileFreeScansLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} free scans left · unlock unlimited'**
  String profileFreeScansLeft(int count);

  /// No description provided for @scanConfirmCheckThisPercent.
  ///
  /// In en, this message translates to:
  /// **'CHECK THIS · {percent}%'**
  String scanConfirmCheckThisPercent(int percent);

  /// No description provided for @scanConfirmDetectedPercent.
  ///
  /// In en, this message translates to:
  /// **'DETECTED · {percent}%'**
  String scanConfirmDetectedPercent(int percent);

  /// No description provided for @scanKeyboardCategoryKeys.
  ///
  /// In en, this message translates to:
  /// **'{category} keys'**
  String scanKeyboardCategoryKeys(String category);

  /// No description provided for @tutorXpAmount.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP'**
  String tutorXpAmount(int xp);

  /// No description provided for @profileAvatarSection.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get profileAvatarSection;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'en',
    'hi',
    'id',
    'ja',
    'ko',
    'ms',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'ms':
      return AppLocalizationsMs();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
