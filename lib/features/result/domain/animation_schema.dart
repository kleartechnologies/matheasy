import 'package:flutter/foundation.dart';

/// The client model of the server-side `animationSchema` sidecar
/// (`functions/src/solver/animationSchema.ts`).
///
/// The server attaches this OPTIONAL, per-step "watch math transform" script to a
/// verified SolvePayload only when its flag is on AND the solve used the mathsteps
/// equation path. It is strictly additive and non-load-bearing: absence is the
/// common case, never an error (see [ResultData.animationSchema]).
///
/// The wire shape is EXACTLY (one entry per step):
/// ```
/// { stepIndex, changeType, beforeLatex, afterLatex, animationTemplate,
///   tokens: [ { value, fromPath, toPath, color, highlight } ], explanationKey }
/// ```
/// Every enum is parsed TOTALLY (unknown value → a safe fallback) so a newer
/// server can never crash an older client.

/// Total string coercion — a non-String degrades to '' instead of throwing, so a
/// foreign / hand-edited / older blob can't crash a `fromJson`.
String _s(Object? v) => v is String ? v : '';

/// Nullable string coercion — preserves an explicit `null` (a token's absent
/// endpoint) and degrades any non-String to null.
String? _sn(Object? v) => v is String ? v : null;

/// How a single step should be animated (a LATER phase; this phase renders
/// statically). Mirrors the server `AnimationTemplate` union.
enum AnimationTemplate {
  moveAcrossEquals('move_across_equals'),
  divideBothSides('divide_both_sides'),
  combineTerms('combine_terms'),
  simplifyInPlace('simplify_in_place'),
  fadeInNewLine('fade_in_new_line');

  const AnimationTemplate(this.wire);

  /// The server's snake_case value.
  final String wire;

  /// Total parse — an unknown/absent template degrades to [fadeInNewLine] (the
  /// server's own default), never throws.
  static AnimationTemplate fromWire(Object? v) => AnimationTemplate.values
      .firstWhere((t) => t.wire == v, orElse: () => AnimationTemplate.fadeInNewLine);
}

/// The colour family a highlighted token is drawn in. Mirrors the server
/// `TokenColor` union. Kept theme-agnostic here (the widget maps it to a concrete
/// palette colour) so the domain stays pure.
enum TokenColor {
  pink,
  blue,
  green;

  /// Total parse — an unknown/absent colour degrades to [blue], never throws.
  static TokenColor fromWire(Object? v) =>
      TokenColor.values.firstWhere((c) => c.name == v, orElse: () => TokenColor.blue);
}

/// The mark drawn on a highlighted token. Mirrors the server `TokenHighlight`
/// union. (Not drawn this phase — the animation phase reads it.)
enum TokenHighlight {
  circle,
  underline,
  box;

  /// Total parse — an unknown/absent highlight degrades to [box], never throws.
  static TokenHighlight fromWire(Object? v) => TokenHighlight.values
      .firstWhere((h) => h.name == v, orElse: () => TokenHighlight.box);
}

/// One token the player should move/highlight, addressed by AST path.
///
/// [fromPath] is the token's origin in the *old* expression (null ⇒ it is new);
/// [toPath] is its destination in the *new* expression (null ⇒ it was removed). A
/// null side means the pairing genuinely couldn't be determined structurally
/// server-side — never invented.
@immutable
class TokenMapping {
  const TokenMapping({
    required this.value,
    required this.fromPath,
    required this.toPath,
    required this.color,
    required this.highlight,
  });

  /// Token text as it appears in the expression, e.g. "3", "2x".
  final String value;

  /// AST path in the old expression, e.g. "L/1" (left side, 2nd arg). Null if new.
  final String? fromPath;

  /// AST path in the new expression. Null if removed.
  final String? toPath;

  final TokenColor color;
  final TokenHighlight highlight;

  Map<String, dynamic> toJson() => {
        'value': value,
        'fromPath': fromPath,
        'toPath': toPath,
        'color': color.name,
        'highlight': highlight.name,
      };

  factory TokenMapping.fromJson(Map<String, dynamic> j) => TokenMapping(
        value: _s(j['value']),
        fromPath: _sn(j['fromPath']),
        toPath: _sn(j['toPath']),
        color: TokenColor.fromWire(j['color']),
        highlight: TokenHighlight.fromWire(j['highlight']),
      );
}

/// One animation instruction — exactly one per equation-solving step.
@immutable
class AnimationInstruction {
  const AnimationInstruction({
    required this.stepIndex,
    required this.changeType,
    required this.beforeLatex,
    required this.afterLatex,
    required this.template,
    required this.tokens,
    required this.explanationKey,
  });

  /// Index of this step in the server's step list.
  final int stepIndex;

  /// The mathsteps changeType this was derived from, e.g. `SUBTRACT_FROM_BOTH_SIDES`.
  final String changeType;

  /// The expression BEFORE this step, as LaTeX.
  final String beforeLatex;

  /// The expression AFTER this step, as LaTeX — the state this step arrives at.
  final String afterLatex;

  final AnimationTemplate template;
  final List<TokenMapping> tokens;

  /// Stable key the narration layer fills in (not the narration text itself). No
  /// narration is wired to these keys yet — this phase shows the key as a
  /// placeholder.
  final String explanationKey;

  Map<String, dynamic> toJson() => {
        'stepIndex': stepIndex,
        'changeType': changeType,
        'beforeLatex': beforeLatex,
        'afterLatex': afterLatex,
        'animationTemplate': template.wire,
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'explanationKey': explanationKey,
      };

  factory AnimationInstruction.fromJson(Map<String, dynamic> j) =>
      AnimationInstruction(
        stepIndex: (j['stepIndex'] as num?)?.toInt() ?? 0,
        changeType: _s(j['changeType']),
        beforeLatex: _s(j['beforeLatex']),
        afterLatex: _s(j['afterLatex']),
        template: AnimationTemplate.fromWire(j['animationTemplate']),
        tokens: (j['tokens'] as List<dynamic>? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => TokenMapping.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        explanationKey: _s(j['explanationKey']),
      );
}

/// The full animation sidecar — an ordered list of per-step [AnimationInstruction].
///
/// A thin wrapper over the list so it parses cleanly from the wire array and the
/// UI can null-check it in one place. [tryParse] returns null for an absent or
/// empty schema, so the common "no sidecar" case reads naturally at the call site.
@immutable
class AnimationSchema {
  const AnimationSchema(this.steps);

  final List<AnimationInstruction> steps;

  bool get isEmpty => steps.isEmpty;
  bool get isNotEmpty => steps.isNotEmpty;
  int get length => steps.length;
  AnimationInstruction operator [](int i) => steps[i];

  List<dynamic> toJson() => steps.map((s) => s.toJson()).toList();

  factory AnimationSchema.fromJson(List<dynamic> json) => AnimationSchema(
        json
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => AnimationInstruction.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  /// Parse an optional schema: null for anything that isn't a non-empty list, so
  /// the (common) absent case doesn't need to be an empty object at the call site.
  static AnimationSchema? tryParse(Object? json) {
    if (json is! List || json.isEmpty) return null;
    final schema = AnimationSchema.fromJson(json);
    return schema.isEmpty ? null : schema;
  }
}
