// Aanchal — Community Service
//
// Manages the Experience feed backed by Firestore.
// Collections:
//   community_posts        — top-level posts
//   community_posts/{id}/comments — sub-collection of comments

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class CommunityPost {
  final String id;
  final String authorUid;
  final String authorName;
  final String authorHandle;
  final String? authorPhotoUrl;
  final String content;
  final String? imageUrl;
  final List<String> likes;
  final int commentCount;
  final int shareCount;
  final DateTime createdAt;

  const CommunityPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorHandle,
    this.authorPhotoUrl,
    required this.content,
    this.imageUrl,
    required this.likes,
    required this.commentCount,
    required this.shareCount,
    required this.createdAt,
  });

  bool isLikedBy(String uid) => likes.contains(uid);

  factory CommunityPost.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CommunityPost(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Unknown',
      authorHandle: d['authorHandle'] as String? ?? '@user',
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      content: d['content'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      likes: List<String>.from(d['likes'] as List? ?? []),
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      shareCount: (d['shareCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class PostComment {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final DateTime createdAt;

  const PostComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorPhotoUrl,
    required this.text,
    required this.createdAt,
  });

  factory PostComment.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PostComment(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Unknown',
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      text: d['text'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class CommunityService {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _postsCol = 'community_posts';

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection(_postsCol);

  /// Realtime stream of all posts, newest first.
  Stream<List<CommunityPost>> getPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CommunityPost.fromDoc).toList());
  }

  /// Create a new post.
  Future<void> createPost({
    required String authorUid,
    required String authorName,
    required String authorHandle,
    String? authorPhotoUrl,
    required String content,
    String? imageUrl,
  }) async {
    await _posts.add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorHandle': authorHandle,
      'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'imageUrl': imageUrl,
      'likes': <String>[],
      'commentCount': 0,
      'shareCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle like on a post for the given uid.
  Future<void> toggleLike(String postId, String uid) async {
    final ref = _posts.doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final likes = List<String>.from(
          (snap.data()?['likes'] as List?) ?? []);
      if (likes.contains(uid)) {
        likes.remove(uid);
      } else {
        likes.add(uid);
      }
      tx.update(ref, {'likes': likes});
    });
  }

  /// Add a comment to a post.
  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorName,
    String? authorPhotoUrl,
    required String text,
  }) async {
    final commentRef = _posts.doc(postId).collection('comments');
    final batch = _db.batch();
    batch.set(commentRef.doc(), {
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Increment comment count on the post document.
    batch.update(_posts.doc(postId), {
      'commentCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Realtime stream of comments for a post, oldest first.
  Stream<List<PostComment>> getComments(String postId) {
    return _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(PostComment.fromDoc).toList());
  }

  /// Increment share count.
  Future<void> incrementShare(String postId) async {
    await _posts.doc(postId).update({
      'shareCount': FieldValue.increment(1),
    });
  }
}
