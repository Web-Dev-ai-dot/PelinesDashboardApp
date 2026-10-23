import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../auth/models/password_change.dart';
import '../../auth/providers/auth_providers.dart';
import '../models/profile.dart';

Future<void> showChangePasswordDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const ChangePasswordDialog(),
);

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  final _hidden = [true, true, true];
  bool _busy = false;
  bool _challenge = false;
  bool _sent = false;
  bool _success = false;
  bool _blocked = false;
  String? _error;
  late final String? _profileId;

  @override
  void initState() {
    super.initState();
    _profileId = ref.read(authControllerProvider).value?.profile.id;
  }

  void _clear() {
    for (final controller in [_current, _password, _confirm, _code]) {
      controller.clear();
    }
  }

  @override
  void dispose() {
    for (final controller in [_current, _password, _confirm, _code]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  PasswordAuthRepository _repository() {
    final session = ref.read(authControllerProvider).value;
    final repository = ref.read(passwordAuthRepositoryProvider);
    if (session?.profile.role != ProfileRole.admin ||
        session?.profile.id != _profileId ||
        repository == null) {
      throw const PasswordChangeFailure(PasswordChangeError.sessionExpired);
    }
    return repository;
  }

  Future<void> _submit() async {
    if (_busy || _blocked) return;
    if (_current.text.isEmpty ||
        _password.text.isEmpty ||
        _confirm.text.isEmpty) {
      setState(() => _error = 'Complete all password fields.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    if (_current.text == _password.text) {
      setState(
        () =>
            _error = 'Choose a password different from your current password.',
      );
      return;
    }
    if (_challenge && (!_sent || _code.text.trim().isEmpty)) {
      setState(() => _error = 'Request and enter the verification code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository().changePassword(
        userId: _profileId!,
        currentPassword: _current.text,
        newPassword: _password.text,
        nonce: _challenge ? _code.text.trim() : null,
      );
      if (!mounted) return;
      _clear();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _success = true);
    } on PasswordChangeFailure catch (failure) {
      if (mounted) _failure(failure);
    } on Object {
      if (mounted) {
        _failure(const PasswordChangeFailure(PasswordChangeError.uncertain));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _failure(PasswordChangeFailure failure) {
    setState(() {
      _error = failure.message;
      if (failure.reason == PasswordChangeError.reauthenticationRequired) {
        _challenge = true;
      }
      if (failure.reason == PasswordChangeError.uncertain ||
          failure.reason == PasswordChangeError.sessionExpired) {
        _blocked = true;
        _clear();
      }
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _blocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository().requestPasswordVerification(userId: _profileId!);
      if (mounted) {
        setState(() {
          _sent = true;
          _code.clear();
        });
      }
    } on PasswordChangeFailure catch (failure) {
      if (mounted) _failure(failure);
    } on Object {
      if (mounted) {
        _failure(const PasswordChangeFailure(PasswordChangeError.unavailable));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    if (_busy) return;
    _clear();
    Navigator.pop(context);
  }

  Widget _passwordField(
    String label,
    String key,
    TextEditingController controller,
    int index,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: PelinesSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr(context, label), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: PelinesSpacing.xs),
        Semantics(
          label: tr(context, label),
          child: TextField(
            key: Key(key),
            controller: controller,
            enabled: !_busy && !_blocked,
            obscureText: _hidden[index],
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: PelinesControlStyles.input().copyWith(
              suffixIcon: IconButton(
                tooltip: tr(
                  context,
                  _hidden[index] ? 'Show password' : 'Hide password',
                ),
                onPressed: _busy || _blocked
                    ? null
                    : () => setState(() => _hidden[index] = !_hidden[index]),
                icon: Icon(
                  _hidden[index]
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy,
    child: AlertDialog(
      key: const Key('change-password-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        tr(context, 'Change password'),
        style: PelinesTypography.sectionTitle(Theme.of(context).textTheme),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_success)
              Semantics(
                liveRegion: true,
                child: Text(tr(context, 'Your password was updated.')),
              )
            else ...[
              _passwordField(
                'Current password',
                'password-current',
                _current,
                0,
              ),
              _passwordField('New password', 'password-new', _password, 1),
              _passwordField(
                'Confirm new password',
                'password-confirm',
                _confirm,
                2,
              ),
              Text(
                tr(
                  context,
                  "Your new password must meet your account's security policy.",
                ),
              ),
              if (_challenge) ...[
                const SizedBox(height: PelinesSpacing.md),
                Text(
                  tr(context, 'An additional verification code is required.'),
                ),
                TextButton(
                  onPressed: _busy || _blocked ? null : _sendCode,
                  key: const Key('password-send-code'),
                  child: Text(
                    tr(
                      context,
                      _sent
                          ? 'Resend verification code'
                          : 'Send verification code',
                    ),
                  ),
                ),
                if (_sent) ...[
                  Text(
                    tr(
                      context,
                      'Check your confirmed email or phone for the code.',
                    ),
                  ),
                  const SizedBox(height: PelinesSpacing.sm),
                  TextField(
                    key: const Key('password-code'),
                    controller: _code,
                    enabled: !_busy && !_blocked,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: PelinesControlStyles.input(
                      label: tr(context, 'Verification code'),
                    ),
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: PelinesSpacing.md),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      tr(context, _error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                key: const Key('password-cancel'),
                style: PelinesControlStyles.button(
                  PelinesButtonVariant.secondary,
                ),
                onPressed: _busy ? null : _close,
                child: Text(tr(context, _success ? 'Done' : 'Cancel')),
              ),
              if (!_success) const SizedBox(height: PelinesSpacing.sm),
              if (!_success)
                FilledButton(
                  key: const Key('password-update'),
                  style: PelinesControlStyles.button(
                    PelinesButtonVariant.primary,
                  ),
                  onPressed: _busy || _blocked ? null : _submit,
                  child: Text(
                    tr(
                      context,
                      _busy ? 'Updating password...' : 'Update password',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
