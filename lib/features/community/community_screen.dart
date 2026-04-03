// Aanchal — Community Screen
//
// Three-tab community hub:
//   1. Experience — social feed backed by Firestore
//   2. Workshops  — affiliated + public safety workshops
//   3. Shop       — safety products catalog
//
// The existing "Find & Call" user-discovery feature is preserved via
// the top-right search icon.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import 'experience_tab.dart';
import 'shop_tab.dart';
import 'user_discovery_screen.dart';
import 'workshops_tab.dart';

class CommunityScreen extends StatefulWidget {
  final UserProfile currentUser;

  const CommunityScreen({super.key, required this.currentUser});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // ── App bar ─────────────────────────────────────────────────────────
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            // Profile avatar
            GestureDetector(
              onTap: () {},
              child: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: widget.currentUser.photoUrl != null
                    ? NetworkImage(widget.currentUser.photoUrl!)
                    : null,
                child: widget.currentUser.photoUrl == null
                    ? Text(
                        widget.currentUser.firstName.isNotEmpty
                            ? widget.currentUser.firstName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Community',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_outlined),
            tooltip: 'Find Aanchal Users',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    UserDiscoveryScreen(currentUser: widget.currentUser),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _CommunityTabBar(controller: _tabController),
        ),
      ),

      // ── Body ─────────────────────────────────────────────────────────────
      body: TabBarView(
        controller: _tabController,
        children: [
          ExperienceTab(currentUser: widget.currentUser),
          WorkshopsTab(currentUser: widget.currentUser),
          ShopTab(currentUser: widget.currentUser),
        ],
      ),
    );
  }
}

// ─── Custom Segmented Tab Bar ─────────────────────────────────────────────────
//
// A fully custom implementation that avoids Flutter's TabBar indicator sizing
// bugs. Uses a fixed-height container with AnimatedPositioned for a smooth
// sliding pill that never overflows or misaligns.

class _CommunityTabBar extends StatelessWidget {
  final TabController controller;
  static const _labels = ['Experience', 'Workshops', 'Shop'];
  static const _height = 42.0;

  const _CommunityTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segmentWidth = totalWidth / _labels.length;

          return Container(
            height: _height,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(_height / 2),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Stack(
              children: [
                // ── Animated sliding pill ───────────────────────────────
                AnimatedBuilder(
                  animation: controller.animation!,
                  builder: (context, _) {
                    final index = controller.animation!.value;
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      left: index * segmentWidth + 3,
                      top: 3,
                      bottom: 3,
                      width: segmentWidth - 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius:
                              BorderRadius.circular((_height - 6) / 2),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // ── Tap targets + labels ────────────────────────────────
                Row(
                  children: List.generate(_labels.length, (i) {
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => controller.animateTo(i),
                        child: AnimatedBuilder(
                          animation: controller.animation!,
                          builder: (context, _) {
                            final selected =
                                (controller.animation!.value.round() == i);
                            return Center(
                              child: Text(
                                _labels[i],
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : scheme.onSurface
                                          .withValues(alpha: 0.55),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
