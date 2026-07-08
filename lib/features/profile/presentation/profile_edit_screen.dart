import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/pressable.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../application/profile_controller.dart';
import '../domain/profile_avatar.dart';
import '../domain/profile_view.dart';
import 'widgets/profile_avatar_view.dart';

/// Edits the learner's identity: display-name override and placeholder avatar
/// (staged, applied on Save), with a link to the learning-preferences editor.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _nameController;
  late ProfileAvatar _avatar;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileControllerProvider);
    _nameController =
        TextEditingController(text: profile.editable.displayName ?? '');
    _avatar = profile.editable.avatar;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _previewInitial(ProfileView profile) {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty) return trimmed.substring(0, 1).toUpperCase();
    return profile.initial;
  }

  void _save() {
    ref.read(profileControllerProvider.notifier).saveProfile(
          displayName: _nameController.text,
          avatar: _avatar,
        );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileControllerProvider);
    final initial = _previewInitial(profile);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.xl,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          Center(
            child: ProfileAvatarView(
              avatar: _avatar,
              initial: initial,
              photoUrl: profile.photoUrl,
              size: 96,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SettingsGroupLabel('Avatar'),
          _AvatarPicker(
            selected: _avatar,
            initial: initial,
            onSelected: (avatar) => setState(() => _avatar = avatar),
          ),
          const SizedBox(height: AppSpacing.section),
          const SettingsGroupLabel('Display name'),
          _NameField(
            controller: _nameController,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsSection(
            title: 'Learning',
            children: [
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Learning preferences',
                subtitle: 'Grade, goal, topics & difficulty',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LearningPreferencesScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.sm,
          AppSpacing.screenH,
          AppSpacing.md,
        ),
        child: PrimaryButton(
          label: 'Save profile',
          icon: Icons.check_rounded,
          onPressed: _save,
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.selected,
    required this.initial,
    required this.onSelected,
  });

  final ProfileAvatar selected;
  final String initial;
  final ValueChanged<ProfileAvatar> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final avatar in ProfileAvatar.values)
          _AvatarOption(
            avatar: avatar,
            initial: initial,
            selected: avatar == selected,
            onTap: () => onSelected(avatar),
          ),
      ],
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.avatar,
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  final ProfileAvatar avatar;
  final String initial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${avatar.label} avatar',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: ProfileAvatarView(
            avatar: avatar,
            initial: initial,
            size: 52,
          ),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      textCapitalization: TextCapitalization.words,
      maxLength: 30,
      style: AppTypography.bodyLarge.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Your name',
        hintStyle:
            AppTypography.bodyLarge.copyWith(color: colors.textTertiary),
        counterText: '',
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.border, width: 1.5),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
