import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/presence_service.dart';

class UserDiscoveryScreen extends StatefulWidget {
  final UserProfile currentUser;

  const UserDiscoveryScreen({super.key, required this.currentUser});

  @override
  State<UserDiscoveryScreen> createState() => _UserDiscoveryScreenState();
}

class _UserDiscoveryScreenState extends State<UserDiscoveryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Users')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allDocs =
              snapshot.data?.docs.where((d) => d.id != widget.currentUser.uid).toList() ??
              const [];

          final q = _query.trim().toLowerCase();
          final docs = allDocs.where((d) {
            if (q.isEmpty) return true;
            final data = d.data() as Map<String, dynamic>;
            final name = (data['name'] as String? ?? '').toLowerCase();
            final number = (data['aanchalNumber'] as String? ?? '').toLowerCase();
            return name.contains(q) || number.contains(q);
          }).toList();

          // Sort: online users first, then alphabetical.
          docs.sort((a, b) {
            final aOnline = ((a.data() as Map<String, dynamic>)['online'] as bool?) ?? false;
            final bOnline = ((b.data() as Map<String, dynamic>)['online'] as bool?) ?? false;
            if (aOnline && !bOnline) return -1;
            if (!aOnline && bOnline) return 1;
            final aName = ((a.data() as Map<String, dynamic>)['name'] as String?) ?? '';
            final bName = ((b.data() as Map<String, dynamic>)['name'] as String?) ?? '';
            return aName.compareTo(bName);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or Aanchal number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? _EmptyState(hasUsers: allDocs.isNotEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final data = docs[i].data() as Map<String, dynamic>;
                          final name = data['name'] as String? ?? 'Unknown';
                          final number = data['aanchalNumber'] as String? ?? '—';
                          final rawOnline = data['online'] as bool? ?? false;
                          final lastSeen = PresenceService.resolveLastSeen(data);
                          final online = PresenceService.isRecentlyOnline(
                            onlineFlag: rawOnline,
                            lastSeen: lastSeen,
                          );

                          return _UserTile(
                            name: name,
                            aanchalNumber: number,
                            online: online,
                            lastSeen: lastSeen,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasUsers;

  const _EmptyState({required this.hasUsers});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: color),
          const SizedBox(height: 16),
          Text(
            hasUsers ? 'No users match your search' : 'No other users yet',
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String name;
  final String aanchalNumber;
  final bool online;
  final dynamic lastSeen;

  const _UserTile({
    required this.name,
    required this.aanchalNumber,
    required this.online,
    required this.lastSeen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              radius: 24,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? Colors.greenAccent : Colors.grey,
                  border: Border.all(
                    color: scheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              aanchalNumber,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: scheme.primary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              online
                  ? 'Online'
                  : 'Last seen ${PresenceService.formatLastSeen(lastSeen)}',
              style: TextStyle(
                fontSize: 11,
                color: online ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.people_alt_outlined),
        isThreeLine: true,
      ),
    );
  }
}
