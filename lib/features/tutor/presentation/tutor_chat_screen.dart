import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/practice_topic.dart';
import '../../progress/application/stats_controller.dart';
import '../../scan/application/scan_image_codec.dart';
import '../../scan/domain/scan_source.dart';
import '../../subscription/application/usage_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../application/tutor_controller.dart';
import '../domain/tutor_models.dart';
import 'tutor_copy.dart';
import 'widgets/tutor_chat_input.dart';
import 'widgets/tutor_message_view.dart';
import 'widgets/tutor_mode_picker.dart';
import 'widgets/tutor_page_overlay.dart';

/// The full-screen chat with Numi — a modern, premium AI conversation.
///
/// Pushed over the shell. Opens aware of a scanned problem or a tapped prompt
/// when a [launchContext] is supplied. All responses are local mocks today; the
/// screen depends only on [TutorChatController] and the domain models, so a real
/// model swaps in behind the scenes without any change here.
class TutorChatScreen extends ConsumerStatefulWidget {
  const TutorChatScreen({super.key, this.launchContext});

  final TutorLaunchContext? launchContext;

  @override
  ConsumerState<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends ConsumerState<TutorChatScreen> {
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _started = false;

  /// Held for the whole pick → encode → send flow, so a second tap can't open
  /// the native picker twice or start a second read behind the first.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    // Seed the conversation once the first frame is up (provider mutation is
    // forbidden during build). Guarded so it fires exactly once per open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      final launch = widget.launchContext;
      final seeded = launch?.seedMessage?.trim().isNotEmpty ?? false;
      // A prompt-seeded open auto-sends a message; if the user is out of free
      // AI tutor messages, replace the chat with the paywall rather than spend one.
      if (seeded && !ref.read(usageSnapshotProvider).canSendTutorMessage) {
        context.pushReplacement(
          AppRoutes.paywall,
          extra: PaywallTrigger.tutorLimit,
        );
        return;
      }
      unawaited(ref.read(tutorChatControllerProvider.notifier).start(launch));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest turn in view.
  ///
  /// A whole message appearing deserves the [smooth] glide; a reply streaming in
  /// grows by a few characters at a time, and animating towards a target that
  /// moves every frame only fights itself — so that case jumps.
  void _scrollToBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (!smooth) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: AppDurations.medium,
        curve: AppCurves.standard,
      );
    });
  }

  /// Whether the student is watching the bottom of the conversation rather than
  /// reading back through it — a streaming reply follows only when they are.
  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    return position.maxScrollExtent - position.pixels < 80;
  }

  /// True when the only change is the last bubble getting longer, i.e. a reply
  /// being written into it.
  static bool _lastMessageGrew(TutorSession prev, TutorSession next) {
    if (next.streamingId == null) return false;
    if (prev.messages.isEmpty || next.messages.isEmpty) return false;
    final before = prev.messages.last;
    final after = next.messages.last;
    return before.id == after.id && after.text.length > before.text.length;
  }

  void _recordTutorUse() =>
      ref.read(statsControllerProvider.notifier).recordTutorUsed();

  /// Returns true if an AI tutor message may be sent; otherwise opens the paywall
  /// over the conversation so dismissing it returns the user to the thread.
  bool _ensureTutorQuota() {
    if (ref.read(usageSnapshotProvider).canSendTutorMessage) return true;
    context.push(AppRoutes.paywall, extra: PaywallTrigger.tutorLimit);
    return false;
  }

  void _send(String text) {
    if (!_ensureTutorQuota()) return;
    _recordTutorUse();
    unawaited(ref.read(tutorChatControllerProvider.notifier).send(text));
  }

  void _sendAction(SuggestionAction action) {
    if (!_ensureTutorQuota()) return;
    _recordTutorUse();
    unawaited(
      ref
          .read(tutorChatControllerProvider.notifier)
          .sendAction(action, TutorCopy.message(context, action)),
    );
  }

  /// The student answered "How would you like to learn this?" — their choice
  /// costs a message, so it goes through the same quota gate as any turn.
  void _chooseMode(TutorMode mode, String label) {
    if (!_ensureTutorQuota()) return;
    _recordTutorUse();
    unawaited(
      ref.read(tutorChatControllerProvider.notifier).chooseMode(mode, label),
    );
  }

  /// Attaches a photo — a question the student is stuck on, or their own
  /// working for Numi to check (spec Parts 2 and 12).
  ///
  /// Costs two things, so it gates on both: a tutor message, and a scan (the
  /// read behind it is the same paid Vision call the scanner makes, and the
  /// server meters it identically).
  Future<void> _attach() async {
    if (_picking) return;
    if (!_ensureTutorQuota()) return;
    if (!ref.read(usageSnapshotProvider).canScan) {
      context.push(AppRoutes.paywall, extra: PaywallTrigger.scanLimit);
      return;
    }

    _picking = true;
    try {
      final source = await _askPhotoSource();
      if (source == null || !mounted) return;

      final galleryFailed = context.l10n.scanGalleryFailed;
      Uint8List bytes;
      try {
        final file = await _picker.pickImage(
          source: source == ScanSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 2000,
          imageQuality: 90,
        );
        if (file == null) return; // cancelled
        bytes = await file.readAsBytes();
      } catch (error) {
        LoggingService.warning('Tutor photo pick failed: $error');
        _toast(galleryFailed);
        return;
      }
      // Normalize to a compact, decodable JPEG off the UI thread — the same
      // step the scanner takes, and the reason the backend always gets JPEG.
      bytes = await compute(encodeScanJpeg, bytes);
      if (!mounted) return;

      _recordTutorUse();
      ref.read(usageControllerProvider.notifier).recordScan();
      final sent = await ref
          .read(tutorChatControllerProvider.notifier)
          .sendImage(bytes, copy: TutorCopy.image(context), source: source);
      // The server had the last word on the scan allowance and said no.
      if (!sent && mounted) {
        context.push(AppRoutes.paywall, extra: PaywallTrigger.scanLimit);
      }
    } finally {
      _picking = false;
    }
  }

  /// "Take photo" or "Gallery" — the same two doors the scanner offers.
  Future<ScanSource?> _askPhotoSource() {
    return showModalBottomSheet<ScanSource>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.lg,
                AppSpacing.screenH,
                AppSpacing.sm,
              ),
              child: Text(
                sheetContext.l10n.tutorImageSheetTitle,
                style: AppTypography.title.copyWith(
                  color: sheetContext.colors.textPrimary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(sheetContext.l10n.scanTakePhoto),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ScanSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(sheetContext.l10n.scanGallery),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ScanSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// Switches mode mid-conversation. Free — nothing is sent; the *next* message
  /// is answered in the new mode.
  Future<void> _switchMode(TutorMode current) async {
    final mode = await showTutorModeSheet(context, current: current);
    if (mode == null || !mounted) return;
    ref.read(tutorChatControllerProvider.notifier).setMode(mode);
    _toast(context.l10n.tutorModeSwitched(TutorCopy.modeLabel(context, mode)));
  }

  void _newChat() {
    ref.read(tutorChatControllerProvider.notifier).reset();
    _toast(context.l10n.tutorNewConversationStarted);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens a practice session from a practice card Numi offered. Numi's
  /// practice prompts are algebra-focused, so we launch an algebra session.
  void _startPractice() {
    context.push(
      AppRoutes.practiceSession,
      extra: const PracticeRequest(topic: PracticeTopic.algebra),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-scroll to the newest message whenever the thread grows or the typing
    // state flips.
    ref.listen(tutorChatControllerProvider, (prev, next) {
      if (prev == null ||
          prev.messages.length != next.messages.length ||
          prev.isThinking != next.isThinking) {
        _scrollToBottom();
        return;
      }
      // A reply streaming in doesn't add a message, it lengthens one — follow it
      // only while the student is at the bottom watching it arrive. Dragging
      // someone back down mid-scroll to chase text is worse than letting the
      // words run past the fold.
      if (_lastMessageGrew(prev, next) && _atBottom) {
        _scrollToBottom(smooth: false);
      }
    });

    final session = ref.watch(tutorChatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.tutorBack,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const _NumiAppBarTitle(),
        actions: [
          IconButton(
            icon: Icon(session.mode.icon),
            tooltip: context.l10n.tutorModeChange,
            onPressed: () => unawaited(_switchMode(session.mode)),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: context.l10n.tutorNewConversation,
            onPressed: _newChat,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: _buildThread(session)),
            TutorChatInput(
              enabled: !session.isTyping,
              onSend: _send,
              onAttach: () => unawaited(_attach()),
              onVoice: () => _toast(context.l10n.tutorVoiceChatSoon),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThread(TutorSession session) {
    if (session.isEmpty) {
      return EmptyState(
        title: context.l10n.tutorEmptyTitle,
        message: context.l10n.tutorEmptyMessage,
      );
    }

    final messages = session.messages;
    final lastAssistant = messages.lastIndexWhere((m) => m.isAssistant);
    // The picker is a trailing row, not a message — it sits under the greeting
    // until the student chooses, then disappears for the rest of the thread.
    final showPicker = session.awaitingModeChoice && !session.isTyping;
    // Resolved once for the whole thread, not per message: it's the same photo
    // and the same anchors for every turn of the conversation.
    final page = TutorScannedPage.from(session.context);
    // Only while she is still thinking: once the words are arriving, the reply
    // itself is the indicator (spec Part 18).
    final itemCount =
        messages.length + (session.isThinking ? 1 : 0) + (showPicker ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.lg,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (showPicker && index == messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: AppTransitions.slideUp(
              child: TutorModePicker(onSelected: _chooseMode),
            ),
          );
        }
        if (index >= messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Semantics(
              liveRegion: true,
              label: context.l10n.tutorTyping,
              child: const MatheasyTypingIndicator(),
            ),
          );
        }
        final message = messages[index];
        final showSuggestions = !session.isTyping && index == lastAssistant;
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.lg),
          child: AppTransitions.slideUp(
            child: TutorMessageView(
              message: message,
              showSuggestions: showSuggestions,
              onSuggestion: _sendAction,
              onPracticeStart: _startPractice,
              page: page,
            ),
          ),
        );
      },
    );
  }
}

/// The chat app-bar identity: Numi herself, her name and a warm status line.
class _NumiAppBarTitle extends StatelessWidget {
  const _NumiAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NumiAvatar(size: 34),
        const SizedBox(width: AppSpacing.sm),
        // Flexible + clamped lines so the title never overflows the app bar at
        // large text scales.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Numi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
              Text(
                context.l10n.tutorTagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
