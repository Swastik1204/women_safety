// Aanchal — Post Detail Screen
//
// Displays a single post with its full comment thread.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/community_service.dart';

class PostDetailScreen extends StatefulWidget {
  final CommunityPost post;
  final UserProfile currentUser;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.currentUser,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await CommunityService.instance.addComment(
        postId: widget.post.id,
        authorUid: widget.currentUser.uid,
        authorName:
            '${widget.currentUser.firstName} ${widget.currentUser.lastName}',
        authorPhotoUrl: widget.currentUser.photoUrl,
        text: text,
      );
      _commentCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to comment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = widget.post;

    return Scaffold(
      appBar: AppBar(
        title: Text('Post',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // ── Post content ──────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Author info
                Row(
                  children: [
                    _Avatar(
                        photoUrl: post.authorPhotoUrl,
                        name: post.authorName),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.authorName,
                            style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700)),
                        Text(post.authorHandle,
                            style: TextStyle(
                                color: scheme.primary, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      _timeAgo(post.createdAt),
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.4)),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Text(
                  post.content,
                  style: GoogleFonts.outfit(fontSize: 15, height: 1.55),
                ),

                if (post.imageUrl != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      post.imageUrl!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Divider(color: scheme.primary.withValues(alpha: 0.1)),
                const SizedBox(height: 10),

                Text(
                  'Comments (${post.commentCount})',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 12),

                // ── Comments stream ─────────────────────────────────────
                StreamBuilder<List<PostComment>>(
                  stream:
                      CommunityService.instance.getComments(post.id),
                  builder: (context, snap) {
                    if (snap.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final comments = snap.data ?? [];
                    if (comments.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'No comments yet. Be the first!',
                            style: TextStyle(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.4),
                                fontSize: 13),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: comments
                          .asMap()
                          .entries
                          .map(
                            (e) => _CommentTile(comment: e.value)
                                .animate()
                                .fadeIn(delay: (40 * e.key).ms),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Comment input ─────────────────────────────────────────────
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border:
                    Border(top: BorderSide(color: scheme.primary.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  _Avatar(
                    photoUrl: widget.currentUser.photoUrl,
                    name: widget.currentUser.firstName,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        filled: true,
                        fillColor:
                            scheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _submitComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _submitting ? null : _submitComment,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Comment Tile ─────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final PostComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
              photoUrl: comment.authorPhotoUrl,
              name: comment.authorName,
              radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.authorName,
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      _timeAgo(comment.createdAt),
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              scheme.onSurface.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text,
                    style: GoogleFonts.outfit(
                        fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Avatar ──────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  const _Avatar(
      {this.photoUrl, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage:
          photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
