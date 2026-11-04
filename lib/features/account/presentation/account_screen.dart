import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_settings_content.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/admin_navigation.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../auth/models/admin_session.dart';
import '../../locations/presentation/pelines_location_context.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/profile.dart';
import '../models/profile_edit.dart';
import '../providers/profile_mutation_controller.dart';
import 'change_password_dialog.dart';

import 'package:pelines_admin_app/core/config/legal_links.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AdminSession?> session = ref.watch(authControllerProvider);
    return session.when(
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
        return EditProfileScreen(
          key: ValueKey(value.profile.id),
          profile: value.profile,
          email: value.email!,
          inline: true,
        );
      },
    );
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.email,
    this.inline = false,
  });
  final Profile profile;
  final String email;
  final bool inline;

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
    final form = PelinesPageBody(
      child: ListView(
        padding: const EdgeInsets.all(PelinesSpacing.lg),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PelinesPageHeader(
                    title: tr(context, 'My Profile'),
                    location: const SectionLocationContext(bottomSpacing: 0),
                    subtitle: tr(
                      context,
                      'Manage your personal account information.',
                    ),
                  ),
                  const SizedBox(height: PelinesSpacing.xl),
                  PelinesSectionHeading(tr(context, 'Profile information')),
                  const SizedBox(height: PelinesSpacing.md),
                  PelinesSettingsCard(
                    key: const Key('profile-card'),
                    children: [
                      _field(
                        tr(context, 'Full name'),
                        TextField(
                          key: const Key('profile-full-name'),
                          controller: _name,
                          enabled: !operation.isBusy,
                          maxLength: 120,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: PelinesControlStyles.input().copyWith(
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.lg),
                      _field(
                        tr(context, 'Email address'),
                        TextFormField(
                          key: const Key('profile-email'),
                          initialValue: widget.email,
                          readOnly: true,
                          maxLines: null,
                          decoration: PelinesControlStyles.input().copyWith(
                            fillColor: PelinesColors.mutedSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.lg),
                      _field(
                        tr(context, 'Phone number'),
                        TextField(
                          key: const Key('profile-phone'),
                          controller: _phone,
                          enabled: !operation.isBusy,
                          maxLength: 40,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: PelinesControlStyles.input().copyWith(
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.lg),
                      const Divider(color: PelinesColors.border),
                      const SizedBox(height: PelinesSpacing.md),
                      Text(
                        tr(context, 'Password'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: PelinesSpacing.sm),
                      Text(
                        tr(
                          context,
                          "Use a strong password you don't reuse elsewhere.",
                        ),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: PelinesColors.textSecondary),
                      ),
                      const SizedBox(height: PelinesSpacing.md),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton(
                          key: const Key('profile-change-password'),
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.secondary,
                          ),
                          onPressed: operation.isBusy
                              ? null
                              : () => showChangePasswordDialog(context),
                          child: Text(
                            tr(context, 'Change password'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.md),
                      if (desired.message != null)
                        _message(desired.message!, error: true),
                      if (operation.phase == ProfileMutationPhase.error &&
                          operation.message != null)
                        _message(operation.message!, error: true),
                      if (operation.phase == ProfileMutationPhase.success)
                        _message(tr(context, 'Profile updated.')),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton(
                          key: const Key('profile-save'),
                          style: PelinesControlStyles.button(
                            PelinesButtonVariant.primary,
                          ),
                          onPressed:
                              operation.isBusy || !desired.isValid || !_dirty
                              ? null
                              : _save,
                          child: Text(
                            tr(
                              context,
                              operation.isBusy ? 'Saving...' : 'Save changes',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      if (operation.isBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      const SizedBox(height: PelinesSpacing.md),
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: PrivacyPolicyLink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return AdminPopScope<void>(
      canPop: !_dirty && !operation.isBusy,
      onRequestLeave: widget.inline ? _confirmLeave : null,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (!didPop && !operation.isBusy) await _leave();
      },
      child: Scaffold(
        appBar: widget.inline
            ? null
            : AdminAppBar(
                title: Text(tr(context, 'My Profile')),
                leading: IconButton(
                  onPressed: operation.isBusy ? null : _leave,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
        body: SafeArea(child: form),
      ),
    );
  }

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: PelinesSpacing.xs),
      Semantics(label: label, child: child),
    ],
  );

  Widget _message(String message, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.sm),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: error
              ? Theme.of(context).colorScheme.error
              : PelinesColors.textPrimary,
        ),
      ),
    ),
  );

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
      if (widget.inline) {
        final canonical = ref.read(authControllerProvider).value?.profile;
        if (canonical != null) _load(canonical, reset: false);
        FocusManager.instance.primaryFocus?.unfocus();
      } else {
        Navigator.pop(context);
      }
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

  void _load(Profile profile, {bool reset = true}) {
    setState(() {
      _snapshot = profile;
      _name.text = profile.fullName ?? '';
      _phone.text = profile.phone ?? '';
      if (reset) ref.read(profileMutationProvider.notifier).reset();
    });
  }

  Future<void> _leave() async {
    if (!await _confirmLeave() || !mounted) return;
    if (widget.inline) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.maybePop(context);
    } else {
      Navigator.pop(context);
    }
  }

  Future<bool> _confirmLeave() async {
    if (ref.read(profileMutationProvider).isBusy) return false;
    if (!_dirty) return true;
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
    if (!mounted) return false;
    if (discard) {
      _load(_snapshot);
      // The shell checks this route's PopScope again after confirmation.
      await WidgetsBinding.instance.endOfFrame;
    }
    return discard;
  }
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
