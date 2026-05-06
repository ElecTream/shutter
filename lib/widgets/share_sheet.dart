import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/list.dart';
import '../providers/auth_notifier.dart';
import '../services/invite_service.dart';
import '../utils/haptics.dart';

/// Per-list sharing sheet.
///
/// - Owner-only "Send invite" by email + "Copy link" generating a `/join/<token>` URL.
/// - Collaborator list with kick action (owner only).
/// - Recipients of the email-invite see the pending entry on their next
///   sign-in via [InviteService.pendingInvitesFor].
///
/// Caller must guarantee the list is already Firestore-backed before
/// showing this sheet — the migrator should run first.
Future<void> showShareSheet(BuildContext context, TaskList list) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(list: list),
  );
}

class _ShareSheet extends StatefulWidget {
  final TaskList list;
  const _ShareSheet({required this.list});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final TextEditingController _emailController = TextEditingController();
  final InviteService _invites = InviteService();
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isOwner(AuthNotifier auth) =>
      auth.firebaseUid != null && auth.firebaseUid == widget.list.ownerUid;

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final auth = context.read<AuthNotifier>();
    final uid = auth.firebaseUid;
    if (uid == null) return;
    setState(() => _sending = true);
    final token = await _invites.createInvite(
      listId: widget.list.id,
      inviterUid: uid,
      email: email,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (token == null) {
      _toast('Invite failed. Check connection.');
      return;
    }
    Haptics.light();
    _emailController.clear();
    _toast('Invite sent to $email');
  }

  Future<void> _copyLink() async {
    final auth = context.read<AuthNotifier>();
    final uid = auth.firebaseUid;
    if (uid == null) return;
    final token = await _invites.createInvite(
      listId: widget.list.id,
      inviterUid: uid,
    );
    if (!mounted) return;
    if (token == null) {
      _toast('Link failed. Check connection.');
      return;
    }
    final url = 'https://shutter.app/join/$token';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    Haptics.light();
    _toast('Link copied to clipboard');
  }

  Future<void> _kick(String uid) async {
    final ok = await _invites.kickCollaborator(widget.list.id, uid);
    if (!mounted) return;
    if (!ok) {
      _toast('Could not remove collaborator');
      return;
    }
    Haptics.medium();
    _toast('Collaborator removed');
    setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthNotifier>();
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final isOwner = _isOwner(auth);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Share "${widget.list.name}"',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (isOwner) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Recipient email',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label:
                              Text(_sending ? 'Sending…' : 'Send invite'),
                          onPressed: _sending ? null : _sendInvite,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link),
                        label: const Text('Copy link'),
                        onPressed: _copyLink,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'Only the list owner can invite or remove people.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              _CollaboratorList(
                list: widget.list,
                onKick: isOwner ? _kick : null,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollaboratorList extends StatelessWidget {
  final TaskList list;
  final Future<void> Function(String uid)? onKick;
  const _CollaboratorList({required this.list, required this.onKick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (list.collaboratorUids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'No collaborators yet.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return FutureBuilder<Map<String, String>>(
      future: _resolveEmails(list.collaboratorUids),
      builder: (context, snap) {
        final emails = snap.data ?? const {};
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Collaborators (${list.collaboratorUids.length})',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            for (final uid in list.collaboratorUids)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(emails[uid] ?? uid),
                trailing: onKick == null
                    ? null
                    : IconButton(
                        icon: Icon(Icons.person_remove,
                            color: theme.colorScheme.error),
                        tooltip: 'Remove',
                        onPressed: () => onKick!(uid),
                      ),
              ),
          ],
        );
      },
    );
  }

  Future<Map<String, String>> _resolveEmails(List<String> uids) async {
    if (uids.isEmpty) return const {};
    try {
      final db = FirebaseFirestore.instance;
      final result = <String, String>{};
      // Firestore `whereIn` caps at 30; chunk if needed.
      for (var i = 0; i < uids.length; i += 30) {
        final chunk = uids.sublist(i, (i + 30).clamp(0, uids.length));
        final qs =
            await db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in qs.docs) {
          final email = doc.data()['email'] as String?;
          if (email != null) result[doc.id] = email;
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }
}
