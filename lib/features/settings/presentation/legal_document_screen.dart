import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The legal documents surfaced in Settings → About.
enum LegalDocument {
  privacy('Privacy Policy', AppConstants.privacyUrl),
  terms('Terms of Service', AppConstants.termsUrl);

  const LegalDocument(this.title, this.url);

  final String title;
  final String url;
}

/// Renders a static legal document (Privacy Policy / Terms of Service) with a
/// link to the authoritative online version.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            'Last updated 8 July 2026',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in _sections(document)) ...[
            Text(
              section.$1,
              style:
                  AppTypography.headingSmall.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              section.$2,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          _OnlineLink(document: document),
        ],
      ),
    );
  }

  List<(String, String)> _sections(LegalDocument document) {
    switch (document) {
      case LegalDocument.privacy:
        return const [
          (
            'Where your data lives',
            'Matheasy keeps your progress, achievements, learning preferences '
                'and settings on this device. When you sign in with Google or '
                'Apple, this learning data is also securely synced to your '
                'account (via Google Firebase) so it is backed up and stays '
                'with you across sessions. In guest mode everything stays on '
                'this device only. Nothing you do in Matheasy is sold or shared '
                'with advertisers.',
          ),
          (
            'What we collect',
            'When you sign in with Google or Apple we receive a basic profile '
                '(name, email and photo) to create and personalise your '
                'account. To run the app we process what you scan and your '
                'practice activity; for signed-in users this learning data is '
                'stored in your account so it can sync across devices. Guest '
                'mode collects no identifying information at all.',
          ),
          (
            'AI processing (OpenAI)',
            'Matheasy is powered by AI. When you scan a problem, type an '
                'equation, ask the AI tutor, or open Visual Learning, that '
                'content — the photo of your work, the equation text, or your '
                'question — is sent over a secure connection to our AI provider, '
                'OpenAI, so it can recognise the problem and generate the '
                'solution, explanation or reply. This content is used only to '
                'answer you; it is never sold, never shown to advertisers, and '
                "not used to build advertising profiles. OpenAI's handling of "
                'this data is governed by their API data-usage policies.',
          ),
          (
            'You are in control',
            'You can edit or clear your preferences at any time. Deleting your '
                'account removes your synced learning data from our servers '
                'along with the copy on this device. Prefer to keep everything '
                'local? Use Matheasy in guest mode.',
          ),
        ];
      case LegalDocument.terms:
        return const [
          (
            'Using Matheasy',
            'Matheasy helps you learn maths through scanning, guided solutions, '
                'an AI tutor and practice. Use it for your own learning and be '
                'respectful of others.',
          ),
          (
            'Your account',
            'You are responsible for activity under your account. Guest '
                'sessions are local to this device and are not recoverable if '
                'the app is removed.',
          ),
          (
            'Learning aid, not a guarantee',
            'Solutions and explanations are generated to help you understand '
                'maths, and may not always be perfect. Always double-check '
                'important work.',
          ),
        ];
    }
  }
}

class _OnlineLink extends StatelessWidget {
  const _OnlineLink({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        children: [
          Icon(Icons.shield_moon_outlined, size: 20, color: colors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The current version is shown above. The always-up-to-date policy '
            'also lives online at',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            document.url,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              // Emerald as body text — the identity emerald is 2.97:1 here.
              color: context.isDark
                  ? AppColors.primaryLight
                  : AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
