// Aanchal — Learning / Safety Hub Screen
//
// Safety tips, self-defense resources, and emergency helpline numbers.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  Future<void> _dial(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Hub')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Helplines
          const _SectionHeader(title: 'Emergency Helplines'),
          _HelplineTile(
            label: 'Women Helpline',
            number: '181',
            onTap: () => _dial('181'),
          ),
          _HelplineTile(
            label: 'Police',
            number: '100',
            onTap: () => _dial('100'),
          ),
          _HelplineTile(
            label: 'Ambulance',
            number: '108',
            onTap: () => _dial('108'),
          ),
          _HelplineTile(
            label: 'NCW',
            number: '7827-170-170',
            onTap: () => _dial('7827170170'),
          ),

          const SizedBox(height: 24),

          // Safety tips
          const _SectionHeader(title: 'Safety Tips'),
          _TipCard(
            text:
                'Share your live location with trusted contacts when traveling alone.',
          ),
          _TipCard(
            text: 'Keep your phone charged and accessible at all times.',
          ),
          _TipCard(
            text: 'Avoid poorly lit or isolated areas, especially at night.',
          ),
          _TipCard(
            text:
                'Trust your instincts — if something feels wrong, move to a safe space.',
          ),

          const SizedBox(height: 24),

          // Self-defense
          const _SectionHeader(title: 'Self-Defense Resources'),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text(
              'Search self-defense tutorials',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Opens YouTube search in your browser'),
            onTap: () => _openUrl(
              'https://www.youtube.com/results?search_query=basic+self+defense+for+women',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _HelplineTile extends StatelessWidget {
  final String label;
  final String number;
  final VoidCallback onTap;

  const _HelplineTile({
    required this.label,
    required this.number,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.phone),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(number),
        onTap: onTap,
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String text;
  const _TipCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: Theme.of(context).colorScheme.tertiary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
