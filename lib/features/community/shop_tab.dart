// Aanchal — Shop Tab
//
// Safety products tab with categories: essentials, new arrivals,
// top-rated, curated kits, and safety guides.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/shop_service.dart';

class ShopTab extends StatefulWidget {
  final UserProfile currentUser;

  const ShopTab({super.key, required this.currentUser});

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  final _searchCtrl = TextEditingController();
  Set<String> _wishlist = {};

  @override
  void initState() {
    super.initState();
    // Seed sample data on first launch
    ShopService.instance.seedSampleData();

    // Listen to wishlist changes
    ShopService.instance
        .getWishlist(widget.currentUser.uid)
        .listen((wl) {
      if (mounted) setState(() => _wishlist = wl);
    });


  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _buy(ShopProduct p) async {
    await ShopService.instance.addToCart(widget.currentUser.uid, p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${p.name}" added to cart 🛒'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleWishlist(ShopProduct p) async {
    await ShopService.instance.toggleWishlist(widget.currentUser.uid, p);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // ── Search ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search safety gear, alarms, sprays...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.1)),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),

        // ── Self-Defense Essentials ────────────────────────────────────
        _SectionHeader(title: 'Self-Defense Essentials', onViewAll: () {}),
        StreamBuilder<List<ShopProduct>>(
          stream: ShopService.instance.getEssentials(),
          builder: (ctx, snap) {
            final products = snap.data ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingRow();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: products.length,
                itemBuilder: (_, i) => _ProductCard(
                  product: products[i],
                  isWishlisted: _wishlist.contains(products[i].id),
                  onBuy: () => _buy(products[i]),
                  onToggleWishlist: () => _toggleWishlist(products[i]),
                ).animate().fadeIn(delay: (60 * i).ms),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── New Arrivals ───────────────────────────────────────────────
        _SectionHeader(title: 'New Arrivals', onViewAll: () {}),
        StreamBuilder<List<ShopProduct>>(
          stream: ShopService.instance.getNewArrivals(),
          builder: (ctx, snap) {
            final products = snap.data ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingRow();
            }
            return SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _NewArrivalCard(
                  product: products[i],
                  onTap: () => _buy(products[i]),
                ).animate().fadeIn(delay: (80 * i).ms),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Top Rated ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text('Top Rated',
              style:
                  GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        StreamBuilder<List<ShopProduct>>(
          stream: ShopService.instance.getTopRated(),
          builder: (ctx, snap) {
            final products = snap.data ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingRow();
            }
            return Column(
              children: products
                  .asMap()
                  .entries
                  .map(
                    (e) => _TopRatedRow(
                      product: e.value,
                      onAddToCart: () => _buy(e.value),
                    ).animate().fadeIn(delay: (80 * e.key).ms),
                  )
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Curated Kits ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Curated Kits',
              style:
                  GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _CuratedKitBanner(),
        ),

        const SizedBox(height: 28),

        // ── Safety Guides ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Safety Guides',
              style:
                  GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _SafetyGuideCard(
                title: 'How to properly use pepper spray',
                subtitle:
                    'Learn the correct grip, aim, and wind considerations for effective use.',
                actionLabel: 'WATCH VIDEO',
                actionIcon: Icons.play_circle_outline,
                isVideo: true,
              ),
              const SizedBox(height: 12),
              _SafetyGuideCard(
                title: 'Situational Awareness 101',
                subtitle:
                    'Expert tips on staying alert in public spaces and identifying potential risks.',
                actionLabel: 'READ ARTICLE',
                actionIcon: Icons.menu_book_outlined,
                isVideo: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Product Card ─────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final ShopProduct product;
  final bool isWishlisted;
  final VoidCallback onBuy;
  final VoidCallback onToggleWishlist;

  const _ProductCard({
    required this.product,
    required this.isWishlisted,
    required this.onBuy,
    required this.onToggleWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: scheme.surfaceContainerHighest,
                  child: product.imageUrl != null
                      ? Image.network(product.imageUrl!,
                          width: double.infinity, fit: BoxFit.cover)
                      : Center(
                          child: Icon(Icons.shield_outlined,
                              size: 48,
                              color: scheme.onSurface.withValues(alpha: 0.2)),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onToggleWishlist,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color:
                            scheme.surface.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isWishlisted
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '₹${product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onBuy,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'BUY',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── New Arrival Card ─────────────────────────────────────────────────────────

class _NewArrivalCard extends StatelessWidget {
  final ShopProduct product;
  final VoidCallback onTap;

  const _NewArrivalCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: scheme.primary.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 130,
                  width: double.infinity,
                  color: scheme.surfaceContainerHighest,
                  child: product.imageUrl != null
                      ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                      : Icon(Icons.shield_outlined,
                          size: 40,
                          color: scheme.onSurface.withValues(alpha: 0.2)),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'NEW',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
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

// ─── Top Rated Row ────────────────────────────────────────────────────────────

class _TopRatedRow extends StatelessWidget {
  final ShopProduct product;
  final VoidCallback onAddToCart;

  const _TopRatedRow(
      {required this.product, required this.onAddToCart});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 72,
              height: 72,
              color: scheme.surfaceContainerHighest,
              child: product.imageUrl != null
                  ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                  : Icon(Icons.shield_outlined,
                      size: 32,
                      color: scheme.onSurface.withValues(alpha: 0.2)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.rating != null)
                  Row(
                    children: [
                      Icon(Icons.star, size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        '${product.rating} (${_formatCount(product.reviewCount ?? 0)} reviews)',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                Text(product.name,
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  '₹${product.price.toStringAsFixed(0)}',
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAddToCart,
            style: IconButton.styleFrom(
              backgroundColor: scheme.primary.withValues(alpha: 0.1),
              foregroundColor: scheme.primary,
            ),
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ─── Curated Kit Banner ───────────────────────────────────────────────────────

class _CuratedKitBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.8),
            scheme.primary.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Icon(
              Icons.backpack_outlined,
              size: 120,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'The Solo Traveler Kit',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Everything you need for your next adventure.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {},
                  child: Row(children: [
                    Text(
                      'Shop Collection',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward,
                        size: 14, color: Colors.white),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Safety Guide Card ────────────────────────────────────────────────────────

class _SafetyGuideCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final bool isVideo;

  const _SafetyGuideCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.primary.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 110,
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  isVideo ? Icons.videocam_outlined : Icons.article_outlined,
                  size: 48,
                  color: scheme.onSurface.withValues(alpha: 0.15),
                ),
              ),
              if (isVideo)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      actionLabel,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(actionIcon, size: 14, color: scheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              child: Text('View All',
                  style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
}
