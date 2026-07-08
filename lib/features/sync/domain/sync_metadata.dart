import 'sync_domain.dart';

/// Version + timestamp for one domain's local copy, used to resolve conflicts
/// (newest wins). [version] is a monotonically-increasing counter bumped on
/// every local write; [lastModified] is the wall-clock time of that write.
///
/// Newest-wins uses [lastModified] as the primary discriminator, so it inherits
/// the usual client-clock caveat: a device with a badly-skewed clock could win
/// a profile/settings conflict it shouldn't. This is an accepted trade-off —
/// the local store is always the source of truth, and every additive domain
/// (progress, achievements, usage, analytics) merges rather than overwrites, so
/// no *earned* data can be lost to skew; only a "current value" edit
/// (name/theme) could be superseded. A future hardening pass could swap in a
/// Firestore server timestamp.
class RecordMeta {
  const RecordMeta({required this.lastModified, this.version = 1});

  static final RecordMeta zero =
      RecordMeta(lastModified: DateTime.fromMillisecondsSinceEpoch(0), version: 0);

  final DateTime lastModified;
  final int version;

  /// Whether this record is strictly newer than [other] — newer timestamp, or
  /// an equal timestamp with a higher version (the tie-breaker).
  bool isNewerThan(RecordMeta other) {
    if (lastModified.isAfter(other.lastModified)) return true;
    if (lastModified.isAtSameMomentAs(other.lastModified)) {
      return version > other.version;
    }
    return false;
  }

  RecordMeta bumped(DateTime now) =>
      RecordMeta(lastModified: now, version: version + 1);

  Map<String, dynamic> toJson() => {
        'lastModified': lastModified.millisecondsSinceEpoch,
        'version': version,
      };

  factory RecordMeta.fromJson(Map<String, dynamic> json) => RecordMeta(
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          json['lastModified'] is int ? json['lastModified'] as int : 0,
        ),
        version: json['version'] is int ? json['version'] as int : 0,
      );

  @override
  bool operator ==(Object other) =>
      other is RecordMeta &&
      other.lastModified == lastModified &&
      other.version == version;

  @override
  int get hashCode => Object.hash(lastModified, version);
}

/// The per-domain metadata map persisted locally (prefs key `sync.metadata`).
/// Missing domains resolve to [RecordMeta.zero] (never synced).
class SyncMetadata {
  const SyncMetadata(this._byDomain);

  static const SyncMetadata empty = SyncMetadata({});

  final Map<SyncDomain, RecordMeta> _byDomain;

  RecordMeta metaFor(SyncDomain domain) => _byDomain[domain] ?? RecordMeta.zero;

  SyncMetadata withMeta(SyncDomain domain, RecordMeta meta) =>
      SyncMetadata({..._byDomain, domain: meta});

  Map<String, dynamic> toJson() => {
        for (final entry in _byDomain.entries)
          entry.key.docId: entry.value.toJson(),
      };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    final map = <SyncDomain, RecordMeta>{};
    json.forEach((key, value) {
      final domain = SyncDomain.fromDocId(key);
      if (domain != null && value is Map) {
        map[domain] = RecordMeta.fromJson(Map<String, dynamic>.from(value));
      }
    });
    return SyncMetadata(map);
  }
}
