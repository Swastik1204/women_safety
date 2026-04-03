// Aanchal — Fake Call Overlay
//
// Full-screen incoming call simulation with accept/decline buttons and timer.

import 'dart:async';
import 'package:flutter/material.dart';

class FakeCallOverlay extends StatefulWidget {
  final String callerName;
  final String callerLabel;

  const FakeCallOverlay({
    super.key,
    this.callerName = 'Mom',
    this.callerLabel = 'Mobile',
  });

  @override
  State<FakeCallOverlay> createState() => _FakeCallOverlayState();
}

class _FakeCallOverlayState extends State<FakeCallOverlay> {
  bool _answered = false;
  int _elapsed = 0;
  Timer? _timer;

  void _answer() {
    setState(() => _answered = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
    });
  }

  void _hangUp() {
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  String get _formattedTime {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // Caller avatar
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white24,
              child: Text(
                widget.callerName.isNotEmpty
                    ? widget.callerName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 48,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Name
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _answered ? _formattedTime : widget.callerLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),

            const Spacer(),

            // Buttons
            if (!_answered)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline
                  _CallActionButton(
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: 'Decline',
                    onTap: _hangUp,
                  ),
                  // Accept
                  _CallActionButton(
                    color: Colors.green,
                    icon: Icons.call,
                    label: 'Accept',
                    onTap: _answer,
                  ),
                ],
              )
            else
              _CallActionButton(
                color: Colors.red,
                icon: Icons.call_end,
                label: 'End',
                onTap: _hangUp,
              ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
