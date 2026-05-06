import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/invite.dart';

/// CRUD for share invites + collaborator membership on Firestore lists.
///
/// Invite tokens double as document ids in `/invites/{token}`. Email-invite
/// flow: caller passes recipient email; recipient sees the pending invite
/// on their next sign-in via [pendingInvitesFor]. Link flow: caller omits
/// email, distributes the token / share link out-of-band; the recipient
/// resolves it via [acceptInvite].
class InviteService {
  static InviteService? _instance;
  factory InviteService() => _instance ??= InviteService._();
  InviteService._();

  bool get _ready => Firebase.apps.isNotEmpty;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Creates an invite document and returns the token. Returns null if
  /// Firebase isn't available.
  Future<String?> createInvite({
    required String listId,
    required String inviterUid,
    String? email,
  }) async {
    if (!_ready) return null;
    final token = _generateToken();
    final normalized = email?.trim().toLowerCase();
    try {
      await _db.collection('invites').doc(token).set({
        'listId': listId,
        'inviterUid': inviterUid,
        'email': normalized,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return token;
    } catch (e) {
      debugPrint('InviteService.createInvite failed: $e');
      return null;
    }
  }

  /// Accepts an invite — adds [acceptingUid] to the list's collaboratorUids
  /// and marks the invite document as accepted. Returns true on success.
  Future<bool> acceptInvite(String token, String acceptingUid) async {
    if (!_ready) return false;
    try {
      final ref = _db.collection('invites').doc(token);
      final snap = await ref.get();
      if (!snap.exists) return false;
      final data = snap.data()!;
      if (data['status'] != 'pending') return false;
      final listId = data['listId'] as String?;
      if (listId == null) return false;

      await _db.collection('lists').doc(listId).update({
        'collaboratorUids': FieldValue.arrayUnion([acceptingUid]),
      });
      await ref.update({
        'status': 'accepted',
        'acceptingUid': acceptingUid,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('InviteService.acceptInvite failed: $e');
      return false;
    }
  }

  /// Marks an invite revoked. The listed collaborator (if already accepted)
  /// is NOT auto-removed — call [kickCollaborator] for that.
  Future<bool> revokeInvite(String token) async {
    if (!_ready) return false;
    try {
      await _db.collection('invites').doc(token).update({'status': 'revoked'});
      return true;
    } catch (e) {
      debugPrint('InviteService.revokeInvite failed: $e');
      return false;
    }
  }

  /// Removes a UID from a list's collaboratorUids array. Owner-only by
  /// security rules.
  Future<bool> kickCollaborator(String listId, String uid) async {
    if (!_ready) return false;
    try {
      await _db.collection('lists').doc(listId).update({
        'collaboratorUids': FieldValue.arrayRemove([uid]),
      });
      return true;
    } catch (e) {
      debugPrint('InviteService.kickCollaborator failed: $e');
      return false;
    }
  }

  /// Pending invites for [email] (case-insensitive). Returns empty list
  /// when Firebase isn't initialized or the query fails.
  Future<List<Invite>> pendingInvitesFor(String email) async {
    if (!_ready) return const [];
    try {
      final qs = await _db
          .collection('invites')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .where('status', isEqualTo: 'pending')
          .get();
      return qs.docs
          .map((d) => Invite.fromJson(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      debugPrint('InviteService.pendingInvitesFor failed: $e');
      return const [];
    }
  }

  /// Lists active invites for a given list (used in the Share sheet to show
  /// outstanding pending invites alongside the collaborator list).
  Future<List<Invite>> invitesForList(String listId) async {
    if (!_ready) return const [];
    try {
      final qs = await _db
          .collection('invites')
          .where('listId', isEqualTo: listId)
          .get();
      return qs.docs
          .map((d) => Invite.fromJson(d.id, d.data()))
          .toList(growable: false);
    } catch (e) {
      debugPrint('InviteService.invitesForList failed: $e');
      return const [];
    }
  }

  String _generateToken() =>
      const Uuid().v4().replaceAll('-', '').substring(0, 22);
}
