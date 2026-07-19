import 'package:flutter/widgets.dart';

import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../domain/animation/animation_copy.dart';

/// Builds the Animated Learning Engine's localized [AnimationCopy] from the
/// current locale. Shared by both entry seams (result tab + practice).
AnimationCopy engineCopy(BuildContext context) {
  final l = context.l10n;
  return AnimationCopy(
    intro: l.engineIntro,
    understandTitle: l.engineUnderstandTitle,
    understandDetail: l.engineUnderstandDetail,
    verifyTitle: l.engineVerifyTitle,
    answerTitle: l.engineAnswerTitle,
    answerDetail: l.engineAnswerDetail,
  );
}
