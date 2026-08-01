import 'package:flutter/widgets.dart';

import '../../../core/localization/l10n_extension.dart';
import '../domain/tutor_models.dart';

/// Localized copy for the tutor's fixed vocabulary — the five [TutorMode]s and
/// the sixteen [SuggestionAction] chips.
///
/// The enums carry only ids and icons: an id is the wire contract with the
/// `tutorReply` Cloud Function and must be identical in every language, while
/// what the student *reads* must follow their language. This class is the join
/// between the two.
///
/// [message] matters as much as [label]: tapping a chip posts that text as the
/// student's own turn, so it appears in their chat history and is what Numi
/// reads. A Spanish student must not see themselves say "Can you explain that
/// more simply?".
class TutorCopy {
  const TutorCopy._();

  /// The chip's visible label.
  static String label(BuildContext context, SuggestionAction action) {
    final l10n = context.l10n;
    return switch (action) {
      SuggestionAction.explainSimpler => l10n.tutorActionExplainSimpler,
      SuggestionAction.giveExample => l10n.tutorActionGiveExample,
      SuggestionAction.tellMeWhy => l10n.tutorActionTellMeWhy,
      SuggestionAction.showAnotherMethod => l10n.tutorActionShowAnotherMethod,
      SuggestionAction.createQuiz => l10n.tutorActionCreateQuiz,
      SuggestionAction.practiceMore => l10n.tutorActionPracticeMore,
      SuggestionAction.giveHint => l10n.tutorActionGiveHint,
      SuggestionAction.nextStep => l10n.tutorActionNextStep,
      SuggestionAction.checkMyWork => l10n.tutorActionCheckMyWork,
      SuggestionAction.commonMistakes => l10n.tutorActionCommonMistakes,
      SuggestionAction.practiceEasier => l10n.tutorActionPracticeEasier,
      SuggestionAction.practiceSimilar => l10n.tutorActionPracticeSimilar,
      SuggestionAction.practiceHarder => l10n.tutorActionPracticeHarder,
      SuggestionAction.practiceChallenge => l10n.tutorActionPracticeChallenge,
      SuggestionAction.showSolution => l10n.tutorActionShowSolution,
      SuggestionAction.iDontUnderstand => l10n.tutorActionIDontUnderstand,
    };
  }

  /// What tapping the chip says on the student's behalf.
  static String message(BuildContext context, SuggestionAction action) {
    final l10n = context.l10n;
    return switch (action) {
      SuggestionAction.explainSimpler => l10n.tutorActionExplainSimplerMessage,
      SuggestionAction.giveExample => l10n.tutorActionGiveExampleMessage,
      SuggestionAction.tellMeWhy => l10n.tutorActionTellMeWhyMessage,
      SuggestionAction.showAnotherMethod =>
        l10n.tutorActionShowAnotherMethodMessage,
      SuggestionAction.createQuiz => l10n.tutorActionCreateQuizMessage,
      SuggestionAction.practiceMore => l10n.tutorActionPracticeMoreMessage,
      SuggestionAction.giveHint => l10n.tutorActionGiveHintMessage,
      SuggestionAction.nextStep => l10n.tutorActionNextStepMessage,
      SuggestionAction.checkMyWork => l10n.tutorActionCheckMyWorkMessage,
      SuggestionAction.commonMistakes => l10n.tutorActionCommonMistakesMessage,
      SuggestionAction.practiceEasier => l10n.tutorActionPracticeEasierMessage,
      SuggestionAction.practiceSimilar => l10n.tutorActionPracticeSimilarMessage,
      SuggestionAction.practiceHarder => l10n.tutorActionPracticeHarderMessage,
      SuggestionAction.practiceChallenge =>
        l10n.tutorActionPracticeChallengeMessage,
      SuggestionAction.showSolution => l10n.tutorActionShowSolutionMessage,
      SuggestionAction.iDontUnderstand =>
        l10n.tutorActionIDontUnderstandMessage,
    };
  }

  /// The mode's name, as shown in the picker and the switcher.
  static String modeLabel(BuildContext context, TutorMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      TutorMode.hint => l10n.tutorModeHint,
      TutorMode.solveTogether => l10n.tutorModeSolveTogether,
      TutorMode.teachMe => l10n.tutorModeTeachMe,
      TutorMode.showSolution => l10n.tutorModeShowSolution,
      TutorMode.quizMe => l10n.tutorModeQuizMe,
    };
  }

  /// Every line the photo flow can speak, resolved in one go.
  ///
  /// Built at the call site (where a [BuildContext] exists) and handed to the
  /// controller, so the orchestration stays widget-free and testable while the
  /// student still reads their own language — including the turns posted on
  /// their behalf.
  static TutorImageCopy image(BuildContext context) {
    final l10n = context.l10n;
    return TutorImageCopy(
      askProblem: l10n.tutorImageAskProblem,
      askWork: l10n.tutorImageAskWork,
      sawProblem: l10n.tutorImageSawProblem,
      sawWork: l10n.tutorImageSawWork,
      notMath: l10n.tutorImageNotMath,
      unreadable: l10n.tutorImageUnreadable,
      failed: l10n.tutorImageFailed,
    );
  }

  /// One line on what the mode will actually do — the student is choosing a
  /// contract, so the difference has to be legible before they commit.
  static String modeDetail(BuildContext context, TutorMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      TutorMode.hint => l10n.tutorModeHintDetail,
      TutorMode.solveTogether => l10n.tutorModeSolveTogetherDetail,
      TutorMode.teachMe => l10n.tutorModeTeachMeDetail,
      TutorMode.showSolution => l10n.tutorModeShowSolutionDetail,
      TutorMode.quizMe => l10n.tutorModeQuizMeDetail,
    };
  }
}
