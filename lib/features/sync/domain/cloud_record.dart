import 'sync_metadata.dart';

/// One domain's document as stored in / read from Firestore.
///
/// The [payload] is the same JSON the local repository already produces (so no
/// per-model codecs are needed); [updatedAt] + [version] carry the conflict-
/// resolution metadata, mirroring the local [RecordMeta].
class CloudRecord {
  const CloudRecord({
    required this.payload,
    required this.updatedAt,
    this.version = 1,
  });

  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final int version;

  RecordMeta get meta => RecordMeta(lastModified: updatedAt, version: version);

  /// Serializes to the Firestore document shape.
  Map<String, dynamic> toFirestore() => {
        'payload': payload,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'version': version,
      };

  /// Rebuilds from a Firestore document, or `null` if the shape is unusable.
  static CloudRecord? fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return null;
    final payload = data['payload'];
    final updatedAt = data['updatedAt'];
    if (payload is! Map || updatedAt is! int) return null;
    return CloudRecord(
      payload: Map<String, dynamic>.from(payload),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      version: data['version'] is int ? data['version'] as int : 1,
    );
  }
}
