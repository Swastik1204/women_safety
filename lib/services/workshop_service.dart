// Aanchal — Workshop Service
//
// Manages workshops backed by Firestore.
// Collections:
//   workshops                   — workshop documents
//   workshops/{id}/registrations — sub-collection of registrations

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

enum WorkshopType { affiliated, public }

class Workshop {
  final String id;
  final String title;
  final WorkshopType type;
  final bool isFree;
  final double? price;
  final DateTime date;
  final String venue;
  final String city;
  final String? imageUrl;
  final bool isCertified;
  final String? category; // e.g. "COMMUNITY MEET", "DISCUSSION"

  const Workshop({
    required this.id,
    required this.title,
    required this.type,
    required this.isFree,
    this.price,
    required this.date,
    required this.venue,
    required this.city,
    this.imageUrl,
    required this.isCertified,
    this.category,
  });

  factory Workshop.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final typeStr = d['type'] as String? ?? 'public';
    return Workshop(
      id: doc.id,
      title: d['title'] as String? ?? 'Workshop',
      type: typeStr == 'affiliated'
          ? WorkshopType.affiliated
          : WorkshopType.public,
      isFree: d['isFree'] as bool? ?? true,
      price: (d['price'] as num?)?.toDouble(),
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      venue: d['venue'] as String? ?? '',
      city: d['city'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      isCertified: d['isCertified'] as bool? ?? false,
      category: d['category'] as String?,
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class WorkshopService {
  WorkshopService._();
  static final WorkshopService instance = WorkshopService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _col = 'workshops';

  CollectionReference<Map<String, dynamic>> get _workshops =>
      _db.collection(_col);

  /// Stream of affiliated (certified by Aanchal) workshops.
  Stream<List<Workshop>> getAffiliatedWorkshops() {
    return _workshops
        .where('type', isEqualTo: 'affiliated')
        .orderBy('date')
        .snapshots()
        .map((s) => s.docs.map(Workshop.fromDoc).toList());
  }

  /// Stream of community-led public workshops.
  Stream<List<Workshop>> getPublicWorkshops() {
    return _workshops
        .where('type', isEqualTo: 'public')
        .orderBy('date')
        .snapshots()
        .map((s) => s.docs.map(Workshop.fromDoc).toList());
  }

  /// Register a user for a workshop.
  Future<void> registerForWorkshop({
    required String workshopId,
    required String uid,
    required String name,
  }) async {
    final regRef = _workshops
        .doc(workshopId)
        .collection('registrations')
        .doc(uid);
    await regRef.set({
      'uid': uid,
      'name': name,
      'registeredAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check if user is registered for a workshop.
  Future<bool> isRegistered({
    required String workshopId,
    required String uid,
  }) async {
    final snap = await _workshops
        .doc(workshopId)
        .collection('registrations')
        .doc(uid)
        .get();
    return snap.exists;
  }

  /// Get all workshop IDs the user has registered for.
  Future<Set<String>> getUserRegistrations(String uid) async {
    // Use a collection group query to find all registrations for this uid.
    // For each workshop, check presence of uid in the registrations sub-col.
    final cgSnap = await _db
        .collectionGroup('registrations')
        .where('uid', isEqualTo: uid)
        .get();
    return cgSnap.docs
        .map((d) => d.reference.parent.parent?.id ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Seed sample workshops into Firestore (call once from an admin/debug route).
  Future<void> seedSampleData() async {
    final existing = await _workshops.limit(1).get();
    if (existing.docs.isNotEmpty) return; // already seeded

    final batch = _db.batch();

    final affiliated = [
      {
        'title': 'Elite Self-Defense Masterclass',
        'type': 'affiliated',
        'isFree': true,
        'isCertified': true,
        'date': Timestamp.fromDate(DateTime(2025, 10, 24, 10, 0)),
        'venue': 'Aanchal Training Centre',
        'city': 'Indiranagar, Bangalore',
        'imageUrl': null,
        'category': 'SELF DEFENSE',
      },
      {
        'title': 'Digital Safety & Cyber Awareness',
        'type': 'affiliated',
        'isFree': false,
        'price': 499.0,
        'isCertified': true,
        'date': Timestamp.fromDate(DateTime(2025, 11, 2, 14, 30)),
        'venue': 'Tech Park Auditorium',
        'city': 'HSR Layout, Bangalore',
        'imageUrl': null,
        'category': 'DIGITAL SAFETY',
      },
      {
        'title': 'Empowerment Through Mindfulness',
        'type': 'affiliated',
        'isFree': true,
        'isCertified': true,
        'date': Timestamp.fromDate(DateTime(2025, 11, 15, 8, 0)),
        'venue': 'Zen Studio',
        'city': 'Koramangala, Bangalore',
        'imageUrl': null,
        'category': 'WELLNESS',
      },
    ];

    final publicWs = [
      {
        'title': 'Neighbourhood Watch Sync',
        'type': 'public',
        'isFree': true,
        'isCertified': false,
        'date': Timestamp.fromDate(DateTime(2025, 10, 28, 17, 0)),
        'venue': 'Public Park B',
        'city': 'Whitefield, Bangalore',
        'imageUrl': null,
        'category': 'COMMUNITY MEET',
      },
      {
        'title': 'Women in Tech Safety Circle',
        'type': 'public',
        'isFree': false,
        'price': 150.0,
        'isCertified': false,
        'date': Timestamp.fromDate(DateTime(2025, 10, 30, 18, 30)),
        'venue': 'Cafe Coffee Day',
        'city': 'Electronic City, Bangalore',
        'imageUrl': null,
        'category': 'DISCUSSION',
      },
      {
        'title': 'Late Night Commute Safety',
        'type': 'public',
        'isFree': true,
        'isCertified': false,
        'date': Timestamp.fromDate(DateTime(2025, 11, 5, 19, 0)),
        'venue': 'Lakeside Deck',
        'city': 'Jayanagar, Bangalore',
        'imageUrl': null,
        'category': 'INTERACTIVE TALK',
      },
    ];

    for (final w in [...affiliated, ...publicWs]) {
      batch.set(_workshops.doc(), w);
    }
    await batch.commit();
  }
}
