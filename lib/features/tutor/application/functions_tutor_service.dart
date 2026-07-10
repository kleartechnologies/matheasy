import '../domain/tutor_models.dart';
import 'tutor_reply_engine.dart';
import 'tutor_service.dart';

/// Real tutor — calls the `tutorReply` Cloud Function (OpenAI server-side) for
/// each message. The opening [greeting] stays local (it's synchronous and needs
/// no model), reusing the offline [TutorReplyEngine].
///
/// Used only for signed-in users with Firebase configured; guests / the
/// unconfigured checkout keep [MockTutorService] (see [tutorServiceProvider]).
class FunctionsTutorService implements TutorService {
  const FunctionsTutorService(
    this._call, {
    this.engine = const TutorReplyEngine(),
  });

  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)
      _call;
  final TutorReplyEngine engine;

  @override
  TutorResponse greeting(TutorLaunchContext? context) => engine.greeting(context);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
  }) async {
    final json = await _call('tutorReply', {
      'userText': userText,
      'history': [
        for (final m in history)
          if (m.role != TutorRole.system)
            {
              'role': m.role == TutorRole.user ? 'user' : 'assistant',
              'text': m.text,
            },
      ],
      if (context?.questionLatex != null) 'problemLatex': context!.questionLatex,
      if (context?.visualStepSummary != null)
        'visualStep': context!.visualStepSummary,
    });
    return TutorReplyMapper.toResponse(json);
  }
}

/// Pure JSON → [TutorResponse] mapping for the `tutorReply` response.
class TutorReplyMapper {
  const TutorReplyMapper._();

  static TutorResponse toResponse(Map<String, dynamic> json) {
    final text = json['reply'] is String ? json['reply'] as String : '';
    final raw = json['suggestions'];
    final suggestions = <SuggestionAction>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! String) continue;
        final action = _matchAction(item);
        if (action != null && !suggestions.contains(action)) {
          suggestions.add(action);
        }
      }
    }
    return TutorResponse(
      text: text.isEmpty ? "Let's keep going!" : text,
      // The model returns free-text prompts; map them onto the app's typed chips
      // (drop unmatched). Fall back to a helpful default set if none matched.
      suggestions: suggestions.isEmpty ? _defaults : suggestions.take(3).toList(),
    );
  }

  static const List<SuggestionAction> _defaults = [
    SuggestionAction.tellMeWhy,
    SuggestionAction.giveExample,
    SuggestionAction.explainSimpler,
  ];

  /// Best-effort keyword match of a free-text suggestion onto a [SuggestionAction].
  static SuggestionAction? _matchAction(String text) {
    final t = text.toLowerCase();
    if (t.contains('simpl')) return SuggestionAction.explainSimpler;
    if (t.contains('example')) return SuggestionAction.giveExample;
    if (t.contains('why')) return SuggestionAction.tellMeWhy;
    if (t.contains('method') || t.contains('another way')) {
      return SuggestionAction.showAnotherMethod;
    }
    if (t.contains('quiz')) return SuggestionAction.createQuiz;
    if (t.contains('practice') || t.contains('practise')) {
      return SuggestionAction.practiceMore;
    }
    return null;
  }
}
