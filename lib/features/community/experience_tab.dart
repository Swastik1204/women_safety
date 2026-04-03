// Aanchal — Experience Tab
//
// Social-feed tab in the Community page.
// Streams posts from Firestore via CommunityService.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/community_service.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

class ExperienceTab extends StatelessWidget {
  final UserProfile currentUser;

  const ExperienceTab({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<CommunityPost>>(
          stream: CommunityService.instance.getPosts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final posts = snapshot.data ?? [];

            if (posts.isEmpty) {
              return _EmptyFeed(currentUser: currentUser);
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                return _PostCard(
                  post: posts[i],
                  currentUser: currentUser,
                ).animate().fadeIn(delay: (50 * i).ms).slideY(begin: 0.05);
              },
            );
          },
        ),

        // ── Floating action button ──────────────────────────────────────────
        Positioned(
          bottom: 24,
          right: 20,
          child: FloatingActionButton(
            heroTag: 'fab_create_post',
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreatePostScreen(currentUser: currentUser),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Post Card ───────────────────────────────────────────────────────────────

class _PostCard extends StatefulWidget {
  final CommunityPost post;
  final UserProfile currentUser;

  const _PostCard({required this.post, required this.currentUser});

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  late bool _liked;
  late int _likeCount;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLikedBy(widget.currentUser.uid);
    _likeCount = widget.post.likes.length;
  }

  @override
  void didUpdateWidget(_PostCard old) {
    super.didUpdateWidget(old);
    if (!_toggling) {
      _liked = widget.post.isLikedBy(widget.currentUser.uid);
      _likeCount = widget.post.likes.length;
    }
  }

  Future<void> _toggleLike() async {
    if (_toggling) return;
    setState(() {
      _toggling = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    await CommunityService.instance.toggleLike(
      widget.post.id,
      widget.currentUser.uid,
    );
    if (mounted) setState(() => _toggling = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final post = widget.post;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            post: post,
            currentUser: widget.currentUser,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Author row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  _Avatar(photoUrl: post.authorPhotoUrl, name: post.authorName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              post.authorName,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '• ${_timeAgo(post.createdAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          post.authorHandle,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_horiz,
                        color: scheme.onSurface.withValues(alpha: 0.4)),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                post.content,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),

            // ── Optional image ────────────────────────────────────────────
            if (post.imageUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(0),
                  bottomRight: Radius.circular(0),
                ),
                child: Image.network(
                  post.imageUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported),
                  ),
                ),
              ),
            ],

            // ── Engagement row ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              child: Row(
                children: [
                  // Like
                  _EngagementButton(
                    icon: _liked
                        ? Icons.thumb_up
                        : Icons.thumb_up_alt_outlined,
                    count: _likeCount,
                    active: _liked,
                    onTap: _toggleLike,
                  ),
                  const SizedBox(width: 4),
                  // Comment
                  _EngagementButton(
                    icon: Icons.chat_bubble_outline,
                    count: post.commentCount,
                    active: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: post,
                          currentUser: widget.currentUser,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Share
                  _EngagementButton(
                    icon: Icons.share_outlined,
                    count: post.shareCount,
                    active: false,
                    onTap: () async {
                      await CommunityService.instance
                          .incrementShare(post.id);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngagementButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _EngagementButton({
    required this.icon,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        '$count',
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  const _Avatar({this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  final UserProfile currentUser;
  const _EmptyFeed({required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80,
                color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 20),
            Text(
              'No posts yet',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share your safety experience with the community!',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
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
