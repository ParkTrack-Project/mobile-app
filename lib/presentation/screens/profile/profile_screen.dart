import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    final user = authState.maybeWhen(
      authenticated: (u) => u,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 40,
            child: Icon(Icons.person, size: 40),
          ),
          const SizedBox(height: 16),
          if (user != null) ...[
            Text(
              user.fullName ?? user.email,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              user.email,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF757575)),
            ),
          ],
          const SizedBox(height: 40),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authStateProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text('Выйти', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
