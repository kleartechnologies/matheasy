import 'package:flutter/widgets.dart';

/// Corner-radius tokens. Exposed both as raw `double` values and as ready-made
/// [BorderRadius] helpers so widgets never hardcode a radius.
class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double card = 22;
  static const double xl = 24;
  static const double hero = 26;
  static const double modal = 30;

  /// Fully rounded (stadium / pill) radius for CTAs and chips.
  static const double pill = 999;

  // ---- BorderRadius helpers ----
  static const BorderRadius xsRadius = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius heroRadius = BorderRadius.all(Radius.circular(hero));
  static const BorderRadius modalRadius =
      BorderRadius.all(Radius.circular(modal));
  static const BorderRadius pillRadius =
      BorderRadius.all(Radius.circular(pill));

  /// Rounded top corners only — used by bottom sheets.
  static const BorderRadius sheetRadius = BorderRadius.only(
    topLeft: Radius.circular(modal),
    topRight: Radius.circular(modal),
  );
}
