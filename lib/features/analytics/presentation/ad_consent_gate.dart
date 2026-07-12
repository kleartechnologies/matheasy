import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/age_gate_controller.dart';
import '../application/tracking_consent_controller.dart';

/// Invisible wrapper that runs the ad-tracking consent sequence once, when the
/// user first reaches the app: (1) a neutral birth-year age gate (COPPA), then
/// (2) the ATT prompt + attribution — but the second step runs only for a
/// confirmed 13+ user. Renders [child] unchanged, so it drops into the shell
/// without affecting layout. A no-op unless Meta is configured (release only).
class AdConsentGate extends ConsumerStatefulWidget {
  const AdConsentGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AdConsentGate> createState() => _AdConsentGateState();
}

class _AdConsentGateState extends ConsumerState<AdConsentGate> {
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_ran || !mounted) return;
    _ran = true;

    final ageGate = ref.read(ageGateControllerProvider.notifier);
    if (ageGate.shouldPrompt) {
      final year = await _askBirthYear();
      if (!mounted) return;
      if (year != null) {
        await ageGate.recordBirthYear(year);
      } else {
        await ageGate.markPromptedWithoutAnswer();
      }
      if (!mounted) return;
    }

    // Proceeds to ATT + attribution only if the age gate set trackingAllowed.
    await ref
        .read(trackingConsentControllerProvider.notifier)
        .requestIfNeeded();
  }

  Future<int?> _askBirthYear() {
    final currentYear = DateTime.now().year;
    final years = [for (var y = currentYear; y >= currentYear - 100; y--) y];
    return showDialog<int>(
      context: context,
      builder: (_) => _BirthYearDialog(years: years),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A neutral birth-year picker (COPPA-safe: it doesn't state the eligible age or
/// mention advertising, so it neither leads nor encourages falsification).
class _BirthYearDialog extends StatefulWidget {
  const _BirthYearDialog({required this.years});

  final List<int> years;

  @override
  State<_BirthYearDialog> createState() => _BirthYearDialogState();
}

class _BirthYearDialogState extends State<_BirthYearDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Before you start'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please select the year you were born.'),
          const SizedBox(height: 16),
          DropdownButton<int>(
            isExpanded: true,
            value: _selected,
            hint: const Text('Year of birth'),
            items: [
              for (final year in widget.years)
                DropdownMenuItem<int>(value: year, child: Text('$year')),
            ],
            onChanged: (year) => setState(() => _selected = year),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
