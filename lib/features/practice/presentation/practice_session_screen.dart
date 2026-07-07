import 'package:flutter/material.dart';

import '../../../shared/dev/nav_placeholder.dart';

/// Full-screen practice session (pushed over the shell). Question flow, grading
/// and XP arrive in Stage 8.
class PracticeSessionScreen extends StatelessWidget {
  const PracticeSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const NavPlaceholder(
      title: 'Practice session',
      subtitle: 'Questions, hints, grading and XP rewards run here in Stage 8.',
      showBack: true,
    );
  }
}
