import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/admin_session.dart';
import '../../auth/providers/auth_providers.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdminSession? session = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelines Admin'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Log out',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Icon(Icons.verified_user_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Administrator access confirmed',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _ProfileRow(
                      label: 'Name',
                      value: session?.profile.fullName ?? 'Not provided',
                    ),
                    _ProfileRow(
                      label: 'Email',
                      value: session?.email ?? 'Not provided',
                    ),
                    _ProfileRow(
                      label: 'Role',
                      value: session?.profile.role.name ?? 'admin',
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 72, child: Text('$label:')),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
