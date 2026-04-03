// Aanchal — SOS / Panic Screen
//
// Dedicated SOS screen with panic trigger, persona selector, and quick actions.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/sos_service.dart';
import '../../services/auth_service.dart';
import '../../services/emergency_contacts_service.dart';
import '../../ui/fake_call_overlay.dart';
import '../../core/logger.dart';
import '../../screens/emergency_contacts_screen.dart';

const _tag = 'SOSScreen';

class SOSScreen extends StatefulWidget {
  final UserProfile currentUser;

  const SOSScreen({super.key, required this.currentUser});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final SOSService _sos = SOSService();
  bool _panicActive = false;
  bool _sosTriggering = false;
  int _contactsCount = 0;
  bool _contactsLoading = true;
  String _selectedPersona = 'Parent';

  final List<String> _personas = ['Parent', 'Dispatcher', 'Helpline'];

  @override
  void initState() {
    super.initState();
    _loadContactsCount();
  }

  Future<void> _loadContactsCount() async {
    final contacts = await EmergencyContactsService.getContacts();
    if (!mounted) return;
    setState(() {
      _contactsCount = contacts.length;
      _contactsLoading = false;
    });
  }

  Future<void> _resetPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_phone_number');
    if (!mounted) return;

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Phone number cleared. Restart the app to re-detect.',
        ),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }

  Future<void> _activatePanic() async {
    setState(() {
      _panicActive = true;
      _sosTriggering = true;
    });

    // Show immediate visual feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u{1F198} SOS Activated — alerting your contacts...'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      await _sos.triggerSOS(
        userName: widget.currentUser.firstName.isNotEmpty
            ? widget.currentUser.firstName
            : 'Your contact',
      );
    } catch (e) {
      logError(_tag, 'Failed to activate panic: $e');
      if (mounted) setState(() => _panicActive = false);
    } finally {
      if (mounted) setState(() => _sosTriggering = false);
    }
  }

  void _deactivatePanic() {
    _sos.deactivate();
    setState(() => _panicActive = false);
  }

  void _triggerFakeCall() {
    logInfo(_tag, 'Fake call triggered with persona: $_selectedPersona');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FakeCallOverlay(callerName: _selectedPersona),
    );
  }

  /// Opens the emergency contacts management screen (non-pick mode).
  Future<void> _openContactsManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
    );
    await _loadContactsCount();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _panicActive
          ? scheme.error.withValues(alpha: 0.25)
          : null,
      appBar: AppBar(
        title: const Text('Panic Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Emergency Contacts',
            onPressed: () => _openContactsManager(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Status
              Text(
                _panicActive ? 'SOS ACTIVE' : 'Ready',
                style: TextStyle(
                  color: _panicActive ? scheme.onError : scheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),

              Material(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openContactsManager(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primary,
                          child: const Icon(
                            Icons.contacts,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage Emergency Contacts',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _contactsLoading
                                    ? 'Loading contacts...'
                                    : '$_contactsCount contact(s) will be alerted',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer.withValues(
                                    alpha: 0.75,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<String>(
                future: SharedPreferences.getInstance().then(
                  (p) => p.getString('user_phone_number') ?? 'Not set',
                ),
                builder: (context, snapshot) {
                  final phone = snapshot.data ?? '...';
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.sim_card_outlined,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Your SOS number: $phone',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _resetPhoneNumber,
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),

              // Big SOS button
              GestureDetector(
                onLongPress: _panicActive ? null : _activatePanic,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _panicActive ? Colors.red : Colors.red.shade700,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: _panicActive ? 40 : 20,
                        spreadRadius: _panicActive ? 10 : 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: _sosTriggering
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _panicActive ? 'ACTIVE' : 'HOLD\nSOS',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),

              if (_panicActive) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _deactivatePanic,
                  child: const Text('Deactivate SOS'),
                ),
              ],

              const SizedBox(height: 24),

              // Persona selector
              const Text('Fake Call Persona', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: _personas
                    .map((p) => ButtonSegment(value: p, label: Text(p)))
                    .toList(),
                selected: {_selectedPersona},
                onSelectionChanged: (s) =>
                    setState(() => _selectedPersona = s.first),
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.all(scheme.onSurface),
                ),
              ),

              const SizedBox(height: 16),

              // Quick actions row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionChip(
                    icon: Icons.phone,
                    label: 'Fake Call',
                    onTap: _triggerFakeCall,
                  ),
                  _ActionChip(
                    icon: Icons.chat,
                    label: 'WhatsApp',
                    onTap: () => logInfo(_tag, 'WhatsApp quick action'),
                  ),
                  _ActionChip(
                    icon: Icons.volume_up,
                    label: 'Alarm',
                    onTap: () => logInfo(_tag, 'Alarm quick action (stub)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
