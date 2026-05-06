/// Pending / accepted / revoked invitation to a shared list.
///
/// Tokens are 22-char URL-safe strings used as the invite document id and
/// as the path component of share links (`/join/{token}`).
class Invite {
  final String token;
  final String listId;
  final String inviterUid;
  final String? email; // lowercased, trimmed; null = link-only invite
  final String status; // pending | accepted | revoked
  final int? createdAtMs;

  const Invite({
    required this.token,
    required this.listId,
    required this.inviterUid,
    required this.status,
    this.email,
    this.createdAtMs,
  });

  factory Invite.fromJson(String token, Map<String, dynamic> data) {
    return Invite(
      token: token,
      listId: (data['listId'] as String?) ?? '',
      inviterUid: (data['inviterUid'] as String?) ?? '',
      email: data['email'] as String?,
      status: (data['status'] as String?) ?? 'pending',
      // Firestore Timestamps deserialize as Timestamp; the createdAt field
      // is server-stamped so callers should treat null as "not yet committed".
      createdAtMs: _toMs(data['createdAt']),
    );
  }

  static int? _toMs(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    // Cloud Firestore Timestamp; avoid importing the package here.
    try {
      // ignore: avoid_dynamic_calls
      return (v.millisecondsSinceEpoch as int?);
    } catch (_) {
      return null;
    }
  }
}
