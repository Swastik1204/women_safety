import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';
import '../../services/auth_service.dart';
import '../../ui/sos_button.dart';
import '../../ui/debug_overlay.dart';
import '../sos/sos_screen.dart';
import '../map/map_screen.dart';
import '../community/community_screen.dart';
import '../learning/learning_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserProfile currentUser;
  const HomeScreen({super.key, required this.currentUser});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showDebug = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('AANCHAL'),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: Icon(
                _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
              ),
              onPressed: () => setState(() => _showDebug = !_showDebug),
              tooltip: 'Toggle Debug Overlay',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.15),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .move(
                duration: 4.seconds,
                begin: const Offset(0, 0),
                end: const Offset(30, 30),
              ),

          Positioned(
                bottom: -50,
                right: -50,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .move(
                duration: 5.seconds,
                begin: const Offset(0, 0),
                end: const Offset(-20, -40),
              ),

          // Blur effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.transparent),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),

                // Greeting text
                Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stay Safe,',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              widget.currentUser.firstName,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                    .slideX(begin: -0.2),

                const SizedBox(height: 48),

                // SOS button
                Center(
                  child: SOSButton(
                    onActivate: () {
                      HapticFeedback.heavyImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SOSScreen(currentUser: widget.currentUser),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Opening Panic Mode'),
                          duration: Duration(milliseconds: 900),
                        ),
                      );
                    },
                  ),
                ).animate().scale(
                  delay: 200.ms,
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                ),

                const SizedBox(height: 16),

                // Quick actions grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: GridView.count(
                      physics: const BouncingScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.2,
                      children:
                          [
                                _QuickAction(
                                  icon: Icons.warning_amber_rounded,
                                  label: 'Panic Mode',
                                  color: Colors.red,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SOSScreen(
                                        currentUser: widget.currentUser,
                                      ),
                                    ),
                                  ),
                                ),
                                _QuickAction(
                                  icon: Icons.explore_outlined,
                                  label: 'Safe Map',
                                  color: Colors.tealAccent,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MapScreen(),
                                    ),
                                  ),
                                ),
                                _QuickAction(
                                  icon: Icons.people_alt_outlined,
                                  label: 'Community',
                                  color: Colors.indigoAccent,
                                  onTap: () {
                                    final bool isFemale =
                                        widget.currentUser.gender
                                            ?.toLowerCase() ==
                                        'female';
                                    final bool canAccessCommunity =
                                        widget.currentUser.isAadhaarVerified &&
                                        isFemale;

                                    if (canAccessCommunity) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CommunityScreen(
                                            currentUser: widget.currentUser,
                                          ),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'The Community section is accessible only to verified female profiles.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                _QuickAction(
                                  icon: Icons.menu_book_rounded,
                                  label: 'Safety Hub',
                                  color: Colors.amberAccent,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LearningScreen(),
                                    ),
                                  ),
                                ),
                              ]
                              .animate(interval: 100.ms)
                              .fadeIn(duration: 500.ms)
                              .slideY(begin: 0.2, curve: Curves.easeOut),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Debug overlay
          if (_showDebug)
            DebugOverlay(onClose: () => setState(() => _showDebug = false)),
        ],
      ),
    );
  }
}

//  Quick Action Tile
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E242D).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          highlightColor: color.withValues(alpha: 0.1),
          splashColor: color.withValues(alpha: 0.2),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
