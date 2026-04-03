import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SOSButton extends StatefulWidget {
  final VoidCallback onActivate;
  final double size;

  const SOSButton({super.key, required this.onActivate, this.size = 200});

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> {
  bool _isHolding = false;
  double _holdProgress = 0.0;
  Timer? _holdTimer;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _holdTimer?.cancel();
    setState(() {
      _isHolding = true;
      _holdProgress = 0.0;
    });

    const steps = 30; // 1.5s / 50ms intervals
    var count = 0;

    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      count++;
      if (!mounted) {
        t.cancel();
        return;
      }

      setState(() => _holdProgress = count / steps);
      if (count >= steps) {
        t.cancel();
        _onHoldComplete();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isHolding = false;
      _holdProgress = 0.0;
    });
  }

  void _activatePanic() {
    widget.onActivate();

    setState(() => _confirmed = true);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _confirmed = false);
    });
  }

  void _onHoldComplete() {
    _holdTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isHolding = false;
      _holdProgress = 0.0;
    });
    _activatePanic();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: _confirmed ? null : (_) => _startHold(),
          onLongPressEnd: _confirmed ? null : (_) => _cancelHold(),
          onLongPressCancel: _confirmed ? null : _cancelHold,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_confirmed)
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade800,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 64,
                  ),
                )
              else ...[
                // Outer glowing rings
                Container(
                  width: widget.size + 80,
                  height: widget.size + 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.1),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(
                      begin: 0.8,
                      end: 1.5,
                      duration: 1500.ms,
                      curve: Curves.easeOut,
                    )
                    .fadeOut(duration: 1500.ms),
                Container(
                  width: widget.size + 40,
                  height: widget.size + 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(alpha: 0.2),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(
                      begin: 1.0,
                      end: 1.3,
                      duration: 1500.ms,
                      curve: Curves.easeOut,
                      delay: 300.ms,
                    )
                    .fadeOut(duration: 1500.ms),

                // Core button
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFF4B4B), Color(0xFFFF1111)],
                      center: Alignment(-0.3, -0.5),
                      radius: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                      const BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_rounded,
                        color: Colors.white,
                        size: 48,
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .shimmer(duration: 1200.ms, color: Colors.white54),
                      const SizedBox(height: 8),
                      const Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'HOLD TO ACTIVATE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                      begin: 1.0,
                      end: 1.05,
                      duration: 1.seconds,
                      curve: Curves.easeInOutSine,
                    ),
              ],
              if (_isHolding)
                SizedBox(
                  width: 176,
                  height: 176,
                  child: CircularProgressIndicator(
                    value: _holdProgress,
                    strokeWidth: 8,
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation(Colors.red),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_confirmed)
          const Text(
            '✓ Alert Sent',
            style: TextStyle(
              color: Colors.green,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          )
        else
          Text(
            _isHolding ? 'Keep holding...' : 'Hold to send SOS',
            style: TextStyle(
              color: _isHolding ? Colors.red : Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}
