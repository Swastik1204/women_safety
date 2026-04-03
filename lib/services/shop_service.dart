// Aanchal — Shop Service
//
// Manages safety product catalog backed by Firestore.
// Collections:
//   shop_products        — all products
//   users/{uid}/cart     — cart items per user
//   users/{uid}/wishlist — wishlist items per user

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class ShopProduct {
  final String id;
  final String brand;
  final String name;
  final double price;
  final String? imageUrl;
  final String category; // 'essential' | 'new_arrival' | 'top_rated'
  final double? rating;
  final int? reviewCount;
  final bool isNew;
  final bool isTopRated;

  const ShopProduct({
    required this.id,
    required this.brand,
    required this.name,
    required this.price,
    this.imageUrl,
    required this.category,
    this.rating,
    this.reviewCount,
    this.isNew = false,
    this.isTopRated = false,
  });

  factory ShopProduct.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ShopProduct(
      id: doc.id,
      brand: d['brand'] as String? ?? '',
      name: d['name'] as String? ?? 'Product',
      price: (d['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: d['imageUrl'] as String?,
      category: d['category'] as String? ?? 'essential',
      rating: (d['rating'] as num?)?.toDouble(),
      reviewCount: (d['reviewCount'] as num?)?.toInt(),
      isNew: d['isNew'] as bool? ?? false,
      isTopRated: d['isTopRated'] as bool? ?? false,
    );
  }
}

class CartItem {
  final String productId;
  final String name;
  final String brand;
  final double price;
  final String? imageUrl;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.brand,
    required this.price,
    this.imageUrl,
    this.quantity = 1,
  });

  factory CartItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CartItem(
      productId: doc.id,
      name: d['name'] as String? ?? '',
      brand: d['brand'] as String? ?? '',
      price: (d['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: d['imageUrl'] as String?,
      quantity: (d['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ShopService {
  ShopService._();
  static final ShopService instance = ShopService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _productsCol = 'shop_products';

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection(_productsCol);

  // ── Products ────────────────────────────────────────────────────────────────

  /// All products in a given category.
  Stream<List<ShopProduct>> getProductsByCategory(String category) {
    return _products
        .where('category', isEqualTo: category)
        .snapshots()
        .map((s) => s.docs.map(ShopProduct.fromDoc).toList());
  }

  /// Self-defense essentials.
  Stream<List<ShopProduct>> getEssentials() =>
      getProductsByCategory('essential');

  /// New arrivals.
  Stream<List<ShopProduct>> getNewArrivals() =>
      _products
          .where('isNew', isEqualTo: true)
          .snapshots()
          .map((s) => s.docs.map(ShopProduct.fromDoc).toList());

  /// Top-rated products (sorted by rating desc).
  Stream<List<ShopProduct>> getTopRated() =>
      _products
          .where('isTopRated', isEqualTo: true)
          .orderBy('rating', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ShopProduct.fromDoc).toList());

  // ── Cart ────────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _cart(String uid) =>
      _db.collection('users').doc(uid).collection('cart');

  /// Stream of cart items for the current user.
  Stream<List<CartItem>> getCart(String uid) {
    return _cart(uid)
        .snapshots()
        .map((s) => s.docs.map(CartItem.fromDoc).toList());
  }

  /// Add or increment a product in the cart.
  Future<void> addToCart(String uid, ShopProduct product) async {
    final ref = _cart(uid).doc(product.id);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({'quantity': FieldValue.increment(1)});
    } else {
      await ref.set({
        'name': product.name,
        'brand': product.brand,
        'price': product.price,
        'imageUrl': product.imageUrl,
        'quantity': 1,
        'addedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Remove a product from the cart.
  Future<void> removeFromCart(String uid, String productId) async {
    await _cart(uid).doc(productId).delete();
  }

  // ── Wishlist ────────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _wishlist(String uid) =>
      _db.collection('users').doc(uid).collection('wishlist');

  /// Realtime stream of wishlisted product IDs.
  Stream<Set<String>> getWishlist(String uid) {
    return _wishlist(uid)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Toggle a product in the wishlist.
  Future<void> toggleWishlist(String uid, ShopProduct product) async {
    final ref = _wishlist(uid).doc(product.id);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'name': product.name,
        'imageUrl': product.imageUrl,
        'addedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Seed ────────────────────────────────────────────────────────────────────

  /// Seed sample products into Firestore (call once).
  Future<void> seedSampleData() async {
    final existing = await _products.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = _db.batch();
    final products = [
      {
        'brand': 'Sabre Red',
        'name': 'Maximum Strength Pepper Spray',
        'price': 999.0,
        'category': 'essential',
        'isNew': false,
        'isTopRated': false,
        'imageUrl': null,
      },
      {
        'brand': "She's Birdie",
        'name': 'Personal Safety Alarm',
        'price': 2499.0,
        'category': 'essential',
        'isNew': false,
        'isTopRated': false,
        'imageUrl': null,
      },
      {
        'brand': 'SafeGuard',
        'name': 'Discreet Wi-Fi Smoke Detector Cam',
        'price': 7299.0,
        'category': 'new_arrival',
        'isNew': true,
        'isTopRated': false,
        'imageUrl': null,
      },
      {
        'brand': 'Guardian',
        'name': 'LED Strobe Keychain Alarm',
        'price': 1999.0,
        'category': 'new_arrival',
        'isNew': true,
        'isTopRated': false,
        'imageUrl': null,
      },
      {
        'brand': 'StrikePen',
        'name': 'Self-Defense Ring V2',
        'price': 1249.0,
        'category': 'top_rated',
        'isNew': false,
        'isTopRated': true,
        'rating': 4.9,
        'reviewCount': 1200,
        'imageUrl': null,
      },
      {
        'brand': 'TactiPen',
        'name': 'Tactical Pen Pro',
        'price': 1549.0,
        'category': 'top_rated',
        'isNew': false,
        'isTopRated': true,
        'rating': 4.8,
        'reviewCount': 850,
        'imageUrl': null,
      },
    ];

    for (final p in products) {
      batch.set(_products.doc(), p);
    }
    await batch.commit();
  }
}
