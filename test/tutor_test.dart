// Stage 6 tests — the AI Tutor (Numi).
//
// Covers: the deterministic reply engine (intent → response + cards), the chat
// controller's send/typing/reset/load loop, the mock home content, and the key
// widgets (Tutor home, chat send flow, interactive quiz card). pump() (not
// pumpAndSettle) is used because Numi's mascot/typing animations loop forever.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/tutor/application/tutor_controller.dart';
import 'package:matheasy/features/tutor/application/tutor_reply_engine.dart';
import 'package:matheasy/features/tutor/application/tutor_service.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';
import 'package:matheasy/features/tutor/presentation/tutor_chat_screen.dart';
import 'package:matheasy/features/tutor/presentation/tutor_screen.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_quiz_card.dart';
import 'package:matheasy/shared/mascot/numi_expression.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A zero-delay [TutorService] so controller/widget tests don't wait on the
/// mock "thinking" pause. Uses the real engine, so replies stay realistic.
class _InstantTutorService implements TutorService {
  const _InstantTutorService();

  static const TutorReplyEngine _engine = TutorReplyEngine();

  @override
  TutorResponse greeting(TutorLaunchContext? context) =>
      _engine.greeting(context);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
  }) async =>
      _engine.reply(userText, history: history, context: context);
}

ProviderContainer _instantContainer() {
  final container = ProviderContainer(
    overrides: [
      tutorServiceProvider.overrideWithValue(const _InstantTutorService()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('TutorReplyEngine', () {
    const engine = TutorReplyEngine();

    test('greets warmly without scan context', () {
      final response = engine.greeting(null);
      expect(response.text.toLowerCase(), contains('numi'));
      expect(response.suggestions, isNotEmpty);
      expect(response.expression, NumiExpression.wave);
    });

    test('greeting is aware of a scanned problem', () {
      final response = engine.greeting(
        const TutorLaunchContext(
          questionLatex: r'2x + 5 = 13',
          answerLatex: r'x = 4',
          equationType: 'Linear Equation',
        ),
      );
      expect(response.text, contains('Linear Equation'));
      expect(response.text, contains(r'x = 4'));
    });

    test('"create a quiz" returns a quiz card', () {
      final response = engine.reply('Can you create a quiz?', history: const []);
      expect(response.card, isA<QuizCard>());
      final quiz = (response.card! as QuizCard).question;
      expect(quiz.options.where((o) => o.isCorrect), hasLength(1));
    });

    test('"practice" returns a practice card', () {
      final response =
          engine.reply('Give me a practice question.', history: const []);
      expect(response.card, isA<PracticeCard>());
    });

    test('"why" explains inverse operations', () {
      final response =
          engine.reply('But why do we subtract 5?', history: const []);
      expect(response.text.toLowerCase(), contains('opposite operation'));
    });

    test('"explain like I\'m 10" uses the wall analogy', () {
      final response = engine.reply("Explain like I'm 10.", history: const []);
      expect(response.text.toLowerCase(), contains('wall'));
    });

    test('examples rotate as more are requested', () {
      final first = engine.reply('Give me an example.', history: const []);
      const priorAsk = TutorMessage.user(id: 0, text: 'give me an example');
      final second = engine.reply('Another example?', history: const [priorAsk]);

      final firstLatex = (first.card! as PracticeCard).prompt.questionLatex;
      final secondLatex = (second.card! as PracticeCard).prompt.questionLatex;
      expect(firstLatex, isNot(secondLatex));
    });

    test('unknown input falls back to an encouraging menu', () {
      final response = engine.reply('purple monkey', history: const []);
      expect(response.suggestions, isNotEmpty);
      expect(response.card, isNull);
    });

    test('greets on a real hello but not on substrings like "this"', () {
      final greeting = engine.reply('hey Numi!', history: const []);
      expect(greeting.text.toLowerCase(), contains('great to see you'));

      // "this" contains "hi" — must NOT be treated as a greeting.
      final notGreeting =
          engine.reply('What is this equation about?', history: const []);
      expect(notGreeting.text.toLowerCase(), isNot(contains('great to see')));
    });
  });

  group('TutorChatController', () {
    test('start seeds a single greeting on an empty session', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(null);

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(1));
      expect(session.messages.single.role, TutorRole.assistant);
      expect(session.isTyping, isFalse);
    });

    test('start with scan context adds a system notice then greeting',
        () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(
              questionLatex: r'2x + 5 = 13',
              equationType: 'Linear Equation',
            ),
          );

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages.first.role, TutorRole.system);
      expect(messages[1].role, TutorRole.assistant);
    });

    test('seed message auto-sends as the first user turn', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(seedMessage: 'Create a quiz for me.'),
          );

      final messages = container.read(tutorChatControllerProvider).messages;
      // greeting, user seed, assistant reply (with quiz card)
      expect(messages, hasLength(3));
      expect(messages[1].role, TutorRole.user);
      expect(messages[1].text, 'Create a quiz for me.');
      expect(messages[2].card, isA<QuizCard>());
    });

    test('a seeded launch starts a fresh thread over a persisted one',
        () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Teach me geometry.'); // 3 persisted messages

      // Re-opening from a tapped suggested prompt must NOT append onto the old
      // (unrelated) thread — it starts fresh.
      await controller.start(
        const TutorLaunchContext(seedMessage: 'Create a quiz for me.'),
      );

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages, hasLength(3)); // greeting + seed + reply, not 6
      expect(messages[1].text, 'Create a quiz for me.');
      expect(messages[2].card, isA<QuizCard>());
    });

    test('send appends user + assistant turns and clears typing', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Why do we subtract 5?');

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(3)); // greeting + user + assistant
      expect(session.messages[1].isUser, isTrue);
      expect(session.messages[2].isAssistant, isTrue);
      expect(session.isTyping, isFalse);
    });

    test('empty/whitespace messages are ignored', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('   ');
      expect(container.read(tutorChatControllerProvider).messages, hasLength(1));
    });

    test('loadConversation replaces the thread', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      const convo = TutorConversation(
        id: 'x',
        title: 'Saved chat',
        preview: '…',
        icon: Icons.calculate_rounded,
        messages: [
          TutorMessage.user(id: 0, text: 'Hello'),
          TutorMessage(id: 1, role: TutorRole.assistant, text: 'Hi there!'),
        ],
      );
      controller.loadConversation(convo);

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages, hasLength(2));
      expect(messages.first.text, 'Hello');
    });

    test('reset restarts with a fresh greeting', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Give me a quiz');
      controller.reset();

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(1));
      expect(session.messages.single.role, TutorRole.assistant);
    });
  });

  group('TutorHome content', () {
    test('provider yields the full mock landing content', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final data = container.read(tutorHomeProvider);
      expect(data.suggestedPrompts, hasLength(5));
      expect(data.categories, hasLength(7));
      expect(data.quickActions, hasLength(4));
      expect(data.recentConversations, hasLength(3));
    });
  });

  group('Tutor widgets', () {
    testWidgets('home renders the hero and a category', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: TutorScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // stagger settle

      expect(find.text('How can I help today?'), findsOneWidget);
      expect(find.text('Try asking'), findsOneWidget);

      // Categories render further down — scroll the page to reveal one.
      await tester.scrollUntilVisible(
        find.text('Algebra'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Algebra'), findsOneWidget);
    });

    testWidgets('chat greets, then answers a sent message', (tester) async {
      // Sending a message records tutor usage for progress, which needs prefs.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            tutorServiceProvider
                .overrideWithValue(const _InstantTutorService()),
          ],
          child: const MaterialApp(home: TutorChatScreen()),
        ),
      );
      await tester.pump(); // run the post-frame start()
      await tester.pump();

      expect(find.textContaining('math coach'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Why do we subtract 5?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('opposite operation'), findsOneWidget);
    });

    testWidgets('quiz card reveals feedback after answering', (tester) async {
      const question = QuizQuestion(
        prompt: 'Solve for x',
        promptLatex: r'2x = 6',
        options: [
          QuizOption(text: '2'),
          QuizOption(text: '3', isCorrect: true),
        ],
        explanation: 'Divide both sides by 2 to get x = 3.',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: TutorQuizCard(question))),
        ),
      );
      await tester.pump();

      // Explanation is hidden until an option is chosen.
      expect(find.textContaining('Divide both sides'), findsNothing);

      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Correct'), findsOneWidget);
      expect(find.textContaining('Divide both sides'), findsOneWidget);
    });
  });
}
