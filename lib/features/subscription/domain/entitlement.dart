/// The access tiers a Matheasy account can hold.
///
/// Modelled as an ordered enum so the app can gate features by *level* rather
/// than by a boolean flag. This is the seam that lets a future **Premium** tier
/// slot in above [pro] without touching any gating call site: add the value
/// here, raise the required level on the guarded feature, and the comparison
/// operators keep working.
enum Entitlement {
  /// No paid entitlement — the free tier.
  none,

  /// The `pro` entitlement (unlimited scans, Numi, practice).
  pro;

  /// Whether this tier unlocks the paid experience (anything above [none]).
  bool get isPaid => index >= pro.index;

  /// Whether this tier grants at least [other]'s access.
  bool grants(Entitlement other) => index >= other.index;

  /// The RevenueCat entitlement identifier this tier maps to, or `null` for the
  /// free tier. Kept here so the RevenueCat wrapper is the only place that needs
  /// the raw string, and a future tier just adds its identifier.
  String? get revenueCatId => switch (this) {
        Entitlement.none => null,
        Entitlement.pro => 'pro',
      };
}
