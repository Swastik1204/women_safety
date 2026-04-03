import 'package:flutter/material.dart';

import '../services/sim_service.dart';

class SimPickerDialog extends StatelessWidget {
  final List<SimInfo> sims;

  const SimPickerDialog({required this.sims, super.key});

  static Future<String?> show(BuildContext context, List<SimInfo> sims) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SimPickerDialog(sims: sims),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.sim_card, color: Colors.green, size: 24),
          SizedBox(width: 8),
          Text(
            'Select Your SIM',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Which SIM number should be used to identify you '
            'to your emergency contacts?',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ...sims.map(
            (sim) => _SimTile(
              sim: sim,
              onTap: () => Navigator.pop(context, sim.phoneNumber),
            ),
          ),
          if (sims.every((s) => !s.hasNumber))
            _EnterManuallyTile(onTap: () => Navigator.pop(context, '')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text(
            'Skip',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _SimTile extends StatelessWidget {
  final SimInfo sim;
  final VoidCallback onTap;

  const _SimTile({required this.sim, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: sim.hasNumber ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sim.hasNumber ? Colors.green.shade700 : Colors.grey.shade700,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade900,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'SIM ${sim.slotIndex + 1}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sim.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sim.hasNumber
                        ? sim.phoneNumber
                        : 'Number not available on this SIM',
                    style: TextStyle(
                      color:
                          sim.hasNumber ? Colors.grey.shade300 : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (sim.hasNumber)
              const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _EnterManuallyTile extends StatelessWidget {
  final VoidCallback onTap;

  const _EnterManuallyTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade700),
        ),
        child: const Row(
          children: [
            Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
            SizedBox(width: 10),
            Text(
              'Enter number manually',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }
}
