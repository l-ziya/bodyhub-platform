import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coach_profile_model.dart';
import '../providers/coach_discovery_provider.dart';

/// Isolated V2 Coach selector for the future sport-to-Coach booking journey.
///
/// It returns a selected public profile but deliberately does not create a
/// booking request, Session, entitlement mutation, or busy block.
class CoachDiscoveryScreen extends ConsumerWidget {
  const CoachDiscoveryScreen({super.key, required this.sportId});

  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coaches = ref.watch(discoverableCoachesProvider(sportId));
    return Scaffold(
      appBar: AppBar(title: const Text('Koç Seç')),
      body: coaches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (profiles) {
          if (profiles.isEmpty) {
            return const Center(
              child: Text('Bu branş için uygun koç bulunamadı.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: profiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _CoachProfileTile(
              profile: profiles[index],
              onTap: () => Navigator.of(context).pop(profiles[index]),
            ),
          );
        },
      ),
    );
  }
}

class _CoachProfileTile extends StatelessWidget {
  const _CoachProfileTile({required this.profile, required this.onTap});

  final CoachProfileModel profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundImage: profile.photoUrl.trim().isEmpty
            ? null
            : NetworkImage(profile.photoUrl),
        child: profile.photoUrl.trim().isEmpty
            ? Text(profile.displayName.isEmpty ? '?' : profile.displayName[0])
            : null,
      ),
      title: Text(profile.displayName),
      subtitle: profile.bio.trim().isEmpty ? null : Text(profile.bio),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
