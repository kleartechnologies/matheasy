/// The COPPA age threshold: ad tracking is permitted only for users at or above
/// this age. Under-13s (and unknown-age users) get NO ad-identifier collection.
const int kAdTrackingMinAge = 13;

/// The outcome of the neutral age gate.
enum AgeAssurance {
  /// No birth year on record yet — treated as a child (no tracking) until asked.
  unknown,

  /// Confirmed under [kAdTrackingMinAge]. Ad tracking is prohibited.
  child,

  /// Confirmed at/over [kAdTrackingMinAge]. Ad tracking may proceed (still
  /// subject to ATT on iOS).
  teenOrAdult,
}

extension AgeAssuranceX on AgeAssurance {
  /// Whether ad tracking (Meta events, ATT, advertiser-id + attribution) may run.
  /// Only a confirmed teen/adult qualifies — `unknown` fails closed.
  bool get adTrackingPermitted => this == AgeAssurance.teenOrAdult;
}

/// Classifies a [birthYear] against [currentYear]. A `null` birth year is
/// [AgeAssurance.unknown]; an implausible year (future, or absurdly old) is
/// treated as [AgeAssurance.unknown] so a mis-tap never silently unlocks
/// tracking. Uses the conservative "has not yet had this year's birthday"
/// assumption (year difference), which never over-estimates age.
AgeAssurance assuranceForBirthYear(int? birthYear, {required int currentYear}) {
  if (birthYear == null) return AgeAssurance.unknown;
  if (birthYear > currentYear || birthYear < currentYear - 120) {
    return AgeAssurance.unknown;
  }
  final age = currentYear - birthYear;
  return age >= kAdTrackingMinAge
      ? AgeAssurance.teenOrAdult
      : AgeAssurance.child;
}
