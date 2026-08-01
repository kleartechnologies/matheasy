import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../../settings/application/language_provider.dart';
import '../domain/tutor_models.dart';

/// Reads a photo the student sent Numi in chat (spec Parts 2, 12).
///
/// The contract is deliberately narrow: this **transcribes**, it never solves
/// and never judges. What comes back goes to the app's own deterministic solver
/// and to the server's work-checker, so a problem photographed in chat gets
/// exactly the same verified treatment as one scanned from the scanner tab.
abstract interface class TutorImageService {
  /// Transcribes [imageBytes] (JPEG). [caption] is what the student typed
  /// alongside the photo — used only to decide what the photo *is*.
  ///
  /// Never returns null and never signals "nothing happened": an unreadable or
  /// non-math photo comes back as a [TutorImageRead] with that [TutorImageKind],
  /// so the caller always has something honest to say.
  Future<TutorImageRead> read(Uint8List imageBytes, {String caption = ''});
}

/// Offline stand-in for the unconfigured checkout. Reading a photo genuinely
/// needs the backend, so it reports [TutorImageKind.unreadable] — the honest
/// branch — rather than pretending to have read anything.
class MockTutorImageService implements TutorImageService {
  const MockTutorImageService();

  @override
  Future<TutorImageRead> read(Uint8List imageBytes, {String caption = ''}) async =>
      TutorImageRead.unreadable;
}

/// Real reader — calls the `tutorImage` Cloud Function (OpenAI Vision behind a
/// moderation gate, server-side).
class FunctionsTutorImageService implements TutorImageService {
  const FunctionsTutorImageService(this._call);

  final Future<Map<String, dynamic>> Function(
      String name, Map<String, dynamic> data) _call;

  @override
  Future<TutorImageRead> read(
    Uint8List imageBytes, {
    String caption = '',
  }) async {
    if (imageBytes.isEmpty) return TutorImageRead.unreadable;
    final json = await _call('tutorImage', {
      'imageBase64': base64Encode(imageBytes),
      'mimeType': 'image/jpeg',
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
    return TutorImageMapper.toRead(json);
  }
}

/// Pure JSON → [TutorImageRead] mapping for the `tutorImage` response.
///
/// Split out so the wire shape is unit-testable without a Firebase stub. The
/// server already coerces its own model output; this coerces again because a
/// stale deployed function is still a possibility the client must survive.
class TutorImageMapper {
  const TutorImageMapper._();

  /// The server caps work at 12 lines; mirrored here so a stale or misbehaving
  /// deploy can't hand the UI an unbounded list.
  static const int maxWorkLines = 12;

  static TutorImageRead toRead(Map<String, dynamic> json) {
    final problem = _text(json['problem']);
    final work = <String>[];
    final rawWork = json['work'];
    if (rawWork is List) {
      for (final item in rawWork) {
        final line = _text(item);
        if (line.isEmpty) continue;
        work.add(line);
        if (work.length >= maxWorkLines) break;
      }
    }

    var kind = TutorImageKind.fromId(json['kind'] as String?);
    // Reconcile the label with what actually arrived — the same reconciliation
    // the server does, repeated because this side must not send an empty string
    // off to be solved.
    if (kind.isReadable && problem.isEmpty && work.isEmpty) {
      kind = TutorImageKind.unreadable;
    }
    if (kind == TutorImageKind.work && work.isEmpty) {
      kind = TutorImageKind.problem;
    }

    final confidence = json['confidence'];
    return TutorImageRead(
      kind: kind,
      problem: problem,
      work: work,
      note: _text(json['note']),
      confidence:
          confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 0.9,
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
}

/// Provides the active [TutorImageService]: the real Cloud-Function reader for
/// signed-in users with Firebase configured, else the offline mock.
final Provider<TutorImageService> tutorImageServiceProvider =
    Provider<TutorImageService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const MockTutorImageService();
  final functions = ref.watch(firebaseFunctionsProvider);
  final ctx = ref.watch(aiRequestContextProvider);
  // The shared context carries the learner's language, which reaches exactly one
  // field of the read — the plain-language `note` shown back to the student.
  return FunctionsTutorImageService(
    (name, data) => callFunction(functions, name, {...data, ...ctx}),
  );
});
