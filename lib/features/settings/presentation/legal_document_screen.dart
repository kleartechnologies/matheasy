import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/app_localizations.dart';

/// The legal documents surfaced in Settings → About.
enum LegalDocument {
  privacy(AppConstants.privacyUrl),
  terms(AppConstants.termsUrl);

  const LegalDocument(this.url);

  final String url;

  /// The document's title in the reader's language.
  String title(AppLocalizations l10n) => switch (this) {
        LegalDocument.privacy => l10n.legalPrivacyTitle,
        LegalDocument.terms => l10n.legalTermsTitle,
      };
}

/// Renders a static legal document (Privacy Policy / Terms of Service) with a
/// link to the authoritative online version.
///
/// The copy here is the version the App Store / Play reviewer reads, so it must
/// describe what the app ACTUALLY does — including the parts that are least
/// flattering. Every claim below is traceable to code: the Meta disclosure to
/// `MetaAnalyticsService` + `MetaEventMapper`, the age gate to
/// `AgeGateController`, and the sign-in-before-delete promise to
/// `FirebaseAuthService.ensureRecentLogin`.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(document.title(l10n))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            l10n.legalLastUpdated,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in _sections(l10n)) ...[
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

  List<(String, String)> _sections(AppLocalizations l10n) {
    switch (document) {
      case LegalDocument.privacy:
        return [
          (l10n.legalPrivacyDataTitle, l10n.legalPrivacyDataBody),
          (l10n.legalPrivacyCollectTitle, l10n.legalPrivacyCollectBody),
          (l10n.legalPrivacyAiTitle, l10n.legalPrivacyAiBody),
          (l10n.legalPrivacyAdsTitle, l10n.legalPrivacyAdsBody),
          (l10n.legalPrivacyAdsChoiceTitle, l10n.legalPrivacyAdsChoiceBody),
          (l10n.legalPrivacyAnalyticsTitle, l10n.legalPrivacyAnalyticsBody),
          (l10n.legalPrivacyChildrenTitle, l10n.legalPrivacyChildrenBody),
          (l10n.legalPrivacyControlTitle, l10n.legalPrivacyControlBody),
          (
            l10n.legalPrivacyContactTitle,
            l10n.legalPrivacyContactBody(AppConstants.supportEmail),
          ),
        ];
      case LegalDocument.terms:
        return [
          (l10n.legalTermsUsingTitle, l10n.legalTermsUsingBody),
          (l10n.legalTermsAccountTitle, l10n.legalTermsAccountBody),
          (l10n.legalTermsBillingTitle, l10n.legalTermsBillingBody),
          (l10n.legalTermsAiTitle, l10n.legalTermsAiBody),
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
            context.l10n.legalOnlineNote,
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
