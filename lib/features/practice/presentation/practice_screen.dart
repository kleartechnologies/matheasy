import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/dev/nav_placeholder.dart';

/// Tab root for the Practice branch. Topic picker + adaptive sessions arrive in
/// Stage 8.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NavPlaceholder(
      title: 'Practice',
      subtitle: 'Adaptive practice and topic mastery arrive in Stage 8.',
      expression: NumiExpression.celebrate,
      actions: [
        PrimaryButton(
          label: 'Start a session',
          icon: Icons.play_arrow_rounded,
          onPressed: () => context.push(AppRoutes.practiceSession),
        ),
      ],
    );
  }
}
