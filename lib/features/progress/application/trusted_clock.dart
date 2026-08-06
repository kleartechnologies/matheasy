import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import 'achievement_service.dart' show clockProvider;

/// How far the device clock may drift from the last observed server time before
/// the trusted clock starts correcting. Generous (90 min) so ordinary drift,
/// DST edges and a stale offset from hours-old app sessions never shift the
/// user's genuine local calendar day — only a deliberately wound clock does.
const Duration serverClockTolerance = Duration(minutes: 90);

/// The wall clock the daily-challenge and streak bookkeeping should trust.
///
/// Device time is right for almost everyone, and honest local midnight is the
/// product behaviour we want (requirement: the challenge rolls at the USER'S
/// midnight). So this returns plain device time — corrected by the last
/// persisted `server - device` offset ONLY when that offset is implausibly
/// large, which is the signature of clock-change reward farming ("set the date
/// forward, finish the challenge, repeat").
///
/// The offset is captured on every `usageStatus` refresh (see
/// `ServerUsageController`). A device that has never reached the server has no
/// offset and is trusted as-is: offline users keep a working daily challenge,
/// per the honest-limitations note in the anti-abuse doc — XP is client-side,
/// so this is deterrence, not enforcement.
final Provider<DateTime Function()> trustedClockProvider =
    Provider<DateTime Function()>((ref) {
  final deviceNow = ref.watch(clockProvider);
  final prefs = ref.watch(preferencesStoreProvider);
  return () {
    final now = deviceNow();
    final offsetMs = prefs.serverClockOffsetMs;
    if (offsetMs == null || offsetMs.abs() <= serverClockTolerance.inMilliseconds) {
      return now;
    }
    return now.add(Duration(milliseconds: offsetMs));
  };
});
