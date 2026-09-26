import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../auth/models/admin_session.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/profile.dart';
import '../models/profile_edit.dart';
import '../providers/profile_mutation_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AdminSession?> session = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AdminAppBar(
        title: Text(
          tr(context, 'My Profile'),
          style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
        ),
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => _AccountError(
          message: error.toString(),
          onRetry: ref.read(authControllerProvider.notifier).retrySession,
        ),
        data: (AdminSession? value) {
          if (value == null || value.email == null || value.email!.isEmpty) {
            return _AccountError(
              message: tr(
                context,
                'Your authenticated email is unavailable. Please sign in again.',
              ),
              onRetry: ref.read(authControllerProvider.notifier).retrySession,
            );
          }
          return _AccountContent(session: value);
        },
      ),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Profile profile = session.profile;
    return PelinesPageBody(
      child: ListView(
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        children: <Widget>[
          PelinesSettingsCard(
            key: const Key('profile-card'),
            title: tr(context, 'My Profile'),
            children: [
              PelinesSettingsFields(
                children: [
                  _ProfileRow(
                    tr(context, 'Full name'),
                    _display(profile.fullName),
                  ),
                  _ProfileRow(
                    tr(context, 'Email'),
                    session.email!,
                    helper: tr(context, 'Read-only'),
                  ),
                  _ProfileRow(tr(context, 'Phone'), _display(profile.phone)),
                  _ProfileRow(
                    tr(context, 'Role'),
                    tr(context, 'Admin'),
                    helper: tr(context, 'Read-only'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: PelinesSpacing.md),
          FilledButton.icon(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            key: const Key('edit-profile'),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    EditProfileScreen(profile: profile, email: session.email!),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: Text(tr(context, 'Edit Profile')),
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.email,
  });
  final Profile profile;
  final String email;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late Profile _snapshot;
  late final TextEditingController _name;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.profile;
    _name = TextEditingController(text: _snapshot.fullName ?? '');
    _phone = TextEditingController(text: _snapshot.phone ?? '');
    _name.addListener(_changed);
    _phone.addListener(_changed);
    Future<void>.microtask(
      () => ref.read(profileMutationProvider.notifier).reset(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  ProfileDraftResult get _desired =>
      ProfileDraft(fullName: _name.text, phone: _phone.text).validate();

  bool get _dirty =>
      !_desired.isValid || profilePatch(_snapshot, _desired).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ProfileMutationState operation = ref.watch(profileMutationProvider);
    final ProfileDraftResult desired = _desired;
    return AdminPopScope<void>(
      canPop: !_dirty || operation.isBusy,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (!didPop && !operation.isBusy) await _leave();
      },
      child: Scaffold(
        appBar: AdminAppBar(
          title: Text(
            tr(context, 'Edit Profile'),
            style: PelinesTypography.pageTitle(Theme.of(context).textTheme),
          ),
          leading: IconButton(
            onPressed: operation.isBusy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: PelinesPageBody(
          child: PelinesSettingsForm(
            padding: const EdgeInsets.all(PelinesSpacing.lg),
            children: <Widget>[
              PelinesSettingsFields(
                children: [
                  TextField(
                    key: const Key('profile-full-name'),
                    controller: _name,
                    enabled: !operation.isBusy,
                    maxLength: 120,
                    decoration: PelinesControlStyles.input(
                      label: tr(context, 'Full name'),
                    ),
                  ),
                  TextField(
                    key: const Key('profile-phone'),
                    controller: _phone,
                    enabled: !operation.isBusy,
                    maxLength: 40,
                    keyboardType: TextInputType.phone,
                    decoration: PelinesControlStyles.input(
                      label: tr(context, 'Phone'),
                    ),
                  ),
                ],
              ),
              PelinesSettingsFields(
                children: [
                  PelinesReadOnlyField(
                    label: tr(context, 'Email'),
                    value: widget.email,
                  ),
                  PelinesReadOnlyField(
                    label: tr(context, 'Role'),
                    value: tr(context, 'Admin'),
                  ),
                ],
              ),
              const SizedBox(height: PelinesSpacing.xl),
              if (desired.message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    desired.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (operation.phase == ProfileMutationPhase.error &&
                  operation.message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    operation.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              OutlinedButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.secondary,
                ),
                onPressed: operation.isBusy ? null : _leave,
                child: Text(tr(context, 'Cancel')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                key: const Key('profile-save'),
                onPressed: operation.isBusy || !desired.isValid || !_dirty
                    ? null
                    : _save,
                child: Text(
                  operation.isBusy
                      ? tr(context, 'Saving...')
                      : tr(context, 'Save Changes'),
                ),
              ),
              if (operation.isBusy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    await ref
        .read(profileMutationProvider.notifier)
        .save(
          profileId: _snapshot.id,
          originalUpdatedAt: _snapshot.updatedAt,
          desired: _desired,
        );
    if (!mounted) return;
    final ProfileMutationState result = ref.read(profileMutationProvider);
    if (result.phase == ProfileMutationPhase.success) {
      Navigator.pop(context);
      return;
    }
    if (result.phase == ProfileMutationPhase.conflict) {
      final bool reload =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('Your profile was changed elsewhere.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Reload'),
                ),
              ],
            ),
          ) ??
          false;
      if (reload && mounted) {
        final Profile? canonical = ref
            .read(authControllerProvider)
            .value
            ?.profile;
        if (canonical != null) _load(canonical);
      }
    }
  }

  void _load(Profile profile) {
    setState(() {
      _snapshot = profile;
      _name.text = profile.fullName ?? '';
      _phone.text = profile.phone ?? '';
      ref.read(profileMutationProvider.notifier).reset();
    });
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final bool discard =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.primary,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) Navigator.pop(context);
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.label, this.value, {this.helper});
  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: PelinesControlStyles.input(label: label)
        .copyWith(helperText: helper),
    child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );
}

class _AccountError extends StatelessWidget {
  const _AccountError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.account_circle_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            style: PelinesControlStyles.button(PelinesButtonVariant.primary),
            onPressed: onRetry,
            child: Text(tr(context, 'Try again')),
          ),
        ],
      ),
    ),
  );
}

String _display(String? value) =>
    value == null || value.isEmpty ? 'Not set' : value;
