import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../history/domain/history_entry.dart';
import '../../../history/presentation/widgets/history_tile.dart';

/// The Home "Recent" section — the most recently solved problems, each re-opened
/// for free (cached, offline). Only shown when there's history; "See all" opens
/// the full History screen (where problems can be deleted). Kept small (a few
/// rows) so Home stays a "what next?" surface, not a log.
class HomeRecentSection extends StatelessWidget {
  const HomeRecentSection({super.key, required this.entries});

  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: context.l10n.homeRecent,
          actionLabel: context.l10n.homeSeeAll,
          onAction: () => context.push(AppRoutes.history),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          HistoryTile(
            entry: entries[i],
            onTap: () => context.push(
              AppRoutes.scanResult,
              extra: entries[i].equation,
            ),
          ),
        ],
      ],
    );
  }
}
