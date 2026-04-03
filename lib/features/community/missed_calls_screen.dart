import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/call_history_service.dart';

class MissedCallsScreen extends StatefulWidget {
  final UserProfile currentUser;

  const MissedCallsScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<MissedCallsScreen> createState() => _MissedCallsScreenState();
}

class _MissedCallsScreenState extends State<MissedCallsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await CallHistoryService.fetchServerMissedCalls(
      widget.currentUser.uid,
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Missed Calls')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('No missed calls')),
                    ],
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final callerName = (item['caller_name'] as String?)?.trim();
                      final callerId = (item['caller_id'] as String?) ?? '';
                      final endReason = (item['end_reason'] as String?) ?? 'missed';
                      final endedAt = (item['ended_at'] as num?)?.toDouble();
                      final subtitle = _formatSubtitle(callerId, endReason, endedAt);

                      return ListTile(
                        leading: Icon(Icons.call_missed, color: scheme.error),
                        title: Text(
                          (callerName != null && callerName.isNotEmpty) ? callerName : callerId,
                        ),
                        subtitle: Text(subtitle),
                      );
                    },
                  ),
      ),
    );
  }

  String _formatSubtitle(String callerId, String endReason, double? endedAtEpoch) {
    final ts = endedAtEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch((endedAtEpoch * 1000).toInt())
        : null;
    final when = ts == null
        ? 'Unknown time'
        : '${ts.toLocal().year.toString().padLeft(4, '0')}-${ts.toLocal().month.toString().padLeft(2, '0')}-${ts.toLocal().day.toString().padLeft(2, '0')} '
          '${ts.toLocal().hour.toString().padLeft(2, '0')}:${ts.toLocal().minute.toString().padLeft(2, '0')}';

    return '$callerId • $endReason • $when';
  }
}
