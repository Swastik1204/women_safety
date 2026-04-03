// Aanchal — Workshops Tab
//
// Displays affiliated (certified) and public community workshops.
// Sources data from Firestore via WorkshopService.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../services/workshop_service.dart';

class WorkshopsTab extends StatefulWidget {
  final UserProfile currentUser;

  const WorkshopsTab({super.key, required this.currentUser});

  @override
  State<WorkshopsTab> createState() => _WorkshopsTabState();
}

class _WorkshopsTabState extends State<WorkshopsTab> {
  Set<String> _registered = {};

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
    // Seed workshops on first load (no-op if already seeded)
    WorkshopService.instance.seedSampleData();
  }

  Future<void> _loadRegistrations() async {
    final regs = await WorkshopService.instance
        .getUserRegistrations(widget.currentUser.uid);
    if (mounted) setState(() => _registered = regs);
  }

  Future<void> _register(Workshop w) async {
    await WorkshopService.instance.registerForWorkshop(
      workshopId: w.id,
      uid: widget.currentUser.uid,
      name: '${widget.currentUser.firstName} ${widget.currentUser.lastName}',
    );
    if (mounted) {
      setState(() => _registered.add(w.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registered for "${w.title}" ✓'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ── Affiliated Workshops ──────────────────────────────────────────
        _SectionHeader(
          title: 'Affiliated Workshops',
          subtitle: 'Certified programs by Aanchal partners',
          onViewAll: () {},
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Workshop>>(
          stream: WorkshopService.instance.getAffiliatedWorkshops(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingCards();
            }
            final workshops = snap.data ?? [];
            if (workshops.isEmpty) return const _EmptySection();
            return Column(
              children: workshops
                  .asMap()
                  .entries
                  .map(
                    (e) => _AffiliatedCard(
                      workshop: e.value,
                      isRegistered: _registered.contains(e.value.id),
                      onRegister: () => _register(e.value),
                    )
                        .animate()
                        .fadeIn(delay: (60 * e.key).ms)
                        .slideY(begin: 0.05),
                  )
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 28),

        // ── Public Workshops ──────────────────────────────────────────────
        _SectionHeader(
          title: 'Public Workshops',
          subtitle: 'Community-led events and meetups',
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Workshop>>(
          stream: WorkshopService.instance.getPublicWorkshops(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingCards();
            }
            final workshops = snap.data ?? [];
            if (workshops.isEmpty) return const _EmptySection();
            return Column(
              children: workshops
                  .asMap()
                  .entries
                  .map(
                    (e) => _PublicWorkshopRow(
                      workshop: e.value,
                      isRegistered: _registered.contains(e.value.id),
                      onRegister: () => _register(e.value),
                    ).animate().fadeIn(delay: (80 * e.key).ms),
                  )
                  .toList(),
            );
          },
        ),

        const SizedBox(height: 28),

        // ── Map Banner ────────────────────────────────────────────────────
        _MapBanner(),
      ],
    );
  }
}

// ─── Affiliated Card ─────────────────────────────────────────────────────────

class _AffiliatedCard extends StatelessWidget {
  final Workshop workshop;
  final bool isRegistered;
  final VoidCallback onRegister;

  const _AffiliatedCard({
    required this.workshop,
    required this.isRegistered,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priceLabel = workshop.isFree
        ? 'Free'
        : '₹${workshop.price?.toStringAsFixed(0) ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image ─────────────────────────────────────────────────────
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                child: workshop.imageUrl != null
                    ? Image.network(workshop.imageUrl!, fit: BoxFit.cover)
                    : Icon(Icons.self_improvement,
                        size: 60,
                        color: scheme.onSurface.withValues(alpha: 0.2)),
              ),
              if (workshop.isCertified)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'CERTIFIED',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ── Details ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        workshop.title,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      priceLabel,
                      style: GoogleFonts.outfit(
                        color: workshop.isFree
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _InfoRow(
                    icon: Icons.calendar_today,
                    text: DateFormat('MMM dd, yyyy • hh:mm a')
                        .format(workshop.date)),
                const SizedBox(height: 4),
                _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: '${workshop.venue}, ${workshop.city}'),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: isRegistered
                          ? scheme.primary.withValues(alpha: 0.2)
                          : scheme.primary,
                      foregroundColor:
                          isRegistered ? scheme.primary : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isRegistered ? null : onRegister,
                    child: Text(isRegistered ? 'Registered ✓' : 'Register Now'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Public Workshop Row ─────────────────────────────────────────────────────

class _PublicWorkshopRow extends StatelessWidget {
  final Workshop workshop;
  final bool isRegistered;
  final VoidCallback onRegister;

  const _PublicWorkshopRow({
    required this.workshop,
    required this.isRegistered,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priceLabel = workshop.isFree
        ? 'Free'
        : '₹${workshop.price?.toStringAsFixed(0) ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 80,
              height: 72,
              color: scheme.surfaceContainerHighest,
              child: workshop.imageUrl != null
                  ? Image.network(workshop.imageUrl!, fit: BoxFit.cover)
                  : Icon(Icons.people_alt_outlined,
                      size: 32,
                      color: scheme.onSurface.withValues(alpha: 0.2)),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workshop.title,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (workshop.category != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      workshop.category!,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(workshop.date),
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                Text(
                  workshop.city,
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),

          // Price + Register
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                priceLabel,
                style: GoogleFonts.outfit(
                  color: workshop.isFree
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: scheme.primary),
                    foregroundColor:
                        isRegistered ? scheme.primary : scheme.primary,
                    backgroundColor: isRegistered
                        ? scheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: isRegistered ? null : onRegister,
                  child: Text(isRegistered ? '✓' : 'Register',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Map Banner ──────────────────────────────────────────────────────────────

class _MapBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.map_outlined, color: scheme.primary, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            'Explore workshops on Map',
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Find safety workshops happening right in your neighbourhood.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.map, size: 16),
            label: const Text('Open Map'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onViewAll;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800, fontSize: 18)),
              Text(subtitle,
                  style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 12)),
            ],
          ),
        ),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Row(children: [
              Text('View all', style: TextStyle(color: scheme.primary)),
              Icon(Icons.arrow_forward, size: 14, color: scheme.primary),
            ]),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color))),
      ],
    );
  }
}

class _LoadingCards extends StatelessWidget {
  const _LoadingCards();
  @override
  Widget build(BuildContext context) {
    return const Center(
        child: Padding(
      padding: EdgeInsets.all(24),
      child: CircularProgressIndicator(),
    ));
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
          child: Text('No workshops available yet',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4)))),
    );
  }
}
