import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';

import '../services/emergency_contacts_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  Color _relationshipColor(String relationship) {
    if (relationship.contains('Mother') || relationship.contains('Father')) {
      return Colors.blue.shade400;
    }
    if (relationship.contains('Sister') || relationship.contains('Brother')) {
      return Colors.purple.shade400;
    }
    if (relationship.contains('Friend')) return Colors.green.shade400;
    if (relationship.contains('Partner')) return Colors.pink.shade400;
    return Colors.grey.shade500;
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey.shade800.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactList(List<EmergencyContact> contacts, ColorScheme scheme) {
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: _relationshipColor(contact.relationship),
                width: 4,
              ),
            ),
            color: Colors.grey.shade900,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.person,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade900,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              contact.relationship,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade300,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact.phone,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.tertiary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Will receive: SMS + App Alert',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteContact(contact),
                  tooltip: 'Delete contact',
                  icon: Icon(
                    Icons.delete_outline,
                    color: scheme.error,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final removed = await EmergencyContactsService.removeContact(contact.id);
    if (!mounted) return;

    if (removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${contact.name} removed from emergency contacts'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove contact. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openAddContactSheet({
    String? initialName,
    String? initialPhone,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddContactSheet(
        initialName: initialName,
        initialPhone: initialPhone,
      ),
    );
  }

  Future<void> _importFromContacts() async {
    final status = await Permission.contacts.status;

    if (status.isPermanentlyDenied) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text(
            'Contacts Permission Required',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Contacts access was permanently denied.\n\n'
            'Go to Settings -> Apps -> Aanchal -> Permissions '
            'and enable Contacts.',
            style: TextStyle(color: Colors.grey.shade300),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text(
                'Open Settings',
                style: TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (status.isDenied) {
      final result = await Permission.contacts.request();
      if (!result.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Contacts permission denied'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
        return;
      }
    }

    // Permission granted — proceed with FlutterContacts.
    if (!await fc.FlutterContacts.requestPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacts permission denied')),
      );
      return;
    }

    final contacts = await fc.FlutterContacts.getContacts(
      withProperties: true,
    );
    final withPhone = contacts.where((c) => c.phones.isNotEmpty).toList();

    if (!mounted) return;
    if (withPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts with phone numbers found')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactPickerSheet(
        contacts: withPhone,
        onSelected: (name, phone) async {
          await _openAddContactSheet(
            initialName: name,
            initialPhone: phone,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: SafeArea(
        child: StreamBuilder<List<EmergencyContact>>(
          stream: EmergencyContactsService().watchContacts(),
          builder: (context, snapshot) {
            final contacts = snapshot.data ?? const <EmergencyContact>[];

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emergency Contacts',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'These people will receive your SOS alert',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${contacts.length} contacts',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: () {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmer();
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Could not load contacts',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      if (contacts.isEmpty) {
                        return _EmptyState(scheme: scheme);
                      }
                      return _buildContactList(contacts, scheme);
                    }(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Contacts without the app will receive an SMS with your '
                            'GPS location. Contacts with the app will also receive '
                            'an audio alert that overrides silent mode.',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.88),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importFromContacts,
                          icon: const Icon(Icons.contacts_outlined),
                          label: const Text('Import from Contacts'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _openAddContactSheet,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            '+ Add Emergency Contact',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;

  const _EmptyState({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 72,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              'No emergency contacts yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Add the people who should be alerted in an emergency',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;

  const _AddContactSheet({
    this.initialName,
    this.initialPhone,
  });

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  bool _saving = false;
  String _selectedRelationship = '🤝 Friend';

  static const List<String> _relationshipOptions = [
    '👩 Mother',
    '👨 Father',
    '👧 Sister',
    '👦 Brother',
    '🤝 Friend',
    '💙 Partner',
    '👤 Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);

    try {
      await EmergencyContactsService.addContact(
        _nameController.text.trim(),
        _phoneController.text.replaceAll(' ', '').trim(),
        _selectedRelationship,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Contact added - they will receive your SOS alerts'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to add contact: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Add Emergency Contact',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  maxLength: 50,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Contact name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Name is required';
                    if (v.length > 50) return 'Name must be 50 characters or less';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '+91XXXXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) return 'Phone number is required';

                    final phone = raw.replaceAll(' ', '');
                    if (!RegExp(r'^[+0-9]').hasMatch(phone)) {
                      return 'Phone must start with + or digit';
                    }
                    if (phone.length < 7 || phone.length > 15) {
                      return 'Phone must be 7 to 15 characters';
                    }
                    if (!RegExp(r'^\+?\d+$').hasMatch(phone)) {
                      return 'Use digits with optional leading +';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Relationship',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _relationshipOptions
                        .map(
                          (label) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _selectedRelationship == label,
                              onSelected: (_) =>
                                  setState(() => _selectedRelationship = label),
                              selectedColor: Colors.green.shade800,
                              backgroundColor: Colors.grey.shade900,
                              labelStyle: TextStyle(
                                color: _selectedRelationship == label
                                    ? Colors.white
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _saveContact,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Contact'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactPickerSheet extends StatefulWidget {
  final List<fc.Contact> contacts;
  final Future<void> Function(String name, String phone) onSelected;

  const _ContactPickerSheet({
    required this.contacts,
    required this.onSelected,
  });

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _query = '';

  String _displayName(fc.Contact contact) {
    final name = contact.displayName.trim();
    return name.isEmpty ? 'Contact' : name;
  }

  String _firstPhone(fc.Contact contact) {
    if (contact.phones.isEmpty) return '';
    return contact.phones.first.number.trim();
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';

    final first = parts.first.substring(0, 1).toUpperCase();
    if (parts.length == 1) {
      if (parts.first.length == 1) return first;
      return '$first${parts.first.substring(1, 2).toUpperCase()}';
    }

    return '$first${parts[1].substring(0, 1).toUpperCase()}';
  }

  List<fc.Contact> get _filteredContacts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.contacts;

    return widget.contacts.where((contact) {
      final name = _displayName(contact).toLowerCase();
      final phones = contact.phones
          .map((p) => p.number.toLowerCase())
          .join(' ');
      return name.contains(q) || phones.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Import from Contacts',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search by name or phone',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _filteredContacts.isEmpty
                ? Center(
                    child: Text(
                      'No matching contacts found',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filteredContacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = _filteredContacts[index];
                      final name = _displayName(contact);
                      final phone = _firstPhone(contact);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primary.withValues(alpha: 0.2),
                          child: Text(
                            _initials(name),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(phone),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onSelected(name, phone);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
