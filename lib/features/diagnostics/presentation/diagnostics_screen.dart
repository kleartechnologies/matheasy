import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../application/diagnostics_service.dart';
import '../domain/app_health_report.dart';
import '../domain/diagnostic_status.dart';

/// Developer diagnostics — backend/app health at a glance. Reachable only from a
/// debug/profile build (the entry point is gated), never surfaced in release.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(appHealthReportProvider);
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          _OverallBanner(status: report.overall),
          const SizedBox(height: AppSpacing.section),
          Text('Subsystems',
              style: AppTypography.label.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < report.subsystems.length; i++) ...[
                  if (i > 0)
                    Divider(height: AppSpacing.lg, color: colors.divider),
                  _SubsystemRow(entry: report.subsystems[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          Text('Build',
              style: AppTypography.label.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                _InfoRow(label: 'Version', value: report.appVersion),
                Divider(height: AppSpacing.lg, color: colors.divider),
                _InfoRow(label: 'Build', value: report.buildNumber),
                Divider(height: AppSpacing.lg, color: colors.divider),
                _InfoRow(label: 'Mode', value: report.buildMode),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Developer tooling — excluded from release builds.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(DiagnosticStatus status) => switch (status) {
      DiagnosticStatus.ok => AppColors.success,
      DiagnosticStatus.degraded => AppColors.warning,
      DiagnosticStatus.down => AppColors.error,
      DiagnosticStatus.disabled => AppColors.primaryTint,
      DiagnosticStatus.unknown => AppColors.amber,
    };

class _OverallBanner extends StatelessWidget {
  const _OverallBanner({required this.status});

  final DiagnosticStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Semantics(
      label: 'Overall status: ${status.label}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: AppSpacing.md),
            Text(
              'Overall: ${status.label}',
              style: AppTypography.title.copyWith(color: context.colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubsystemRow extends StatelessWidget {
  const _SubsystemRow({required this.entry});

  final DiagnosticEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _statusColor(entry.status);
    return Semantics(
      label: '${entry.label}: ${entry.status.label}'
          '${entry.detail == null ? '' : ', ${entry.detail}'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: AppTypography.title.copyWith(color: colors.textPrimary)),
                if (entry.detail != null)
                  Text(entry.detail!,
                      style: AppTypography.bodySmall
                          .copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
          Text(entry.status.label,
              style: AppTypography.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: colors.textSecondary)),
        Text(value,
            style: AppTypography.title.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}
