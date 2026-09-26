import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';

import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/pelines_tokens.dart';
import '../../../core/api/api_exception.dart';
import '../models/admin_session.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AdminSession?> auth = ref.watch(authControllerProvider);
    final bool loading = auth.isLoading;
    final String? errorMessage = auth.hasError
        ? _messageFor(auth.error!)
        : null;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 400 ? 16 : 24,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      image: true,
                      label: 'Pelines Tequila and Mezcal',
                      child: Image.asset(
                        'assets/branding/pelines_logo.png',
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      key: const Key('login-card'),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: PelinesColors.card,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: PelinesShadows.subtle,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(
                              constraints.maxWidth < 400 ? 20 : 40,
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    tr(context, 'Sign In'),
                                    key: const Key('login-title'),
                                    style: PelinesTypography.pageTitle(
                                      Theme.of(context).textTheme,
                                    )?.copyWith(fontSize: 36),
                                  ),
                                  const SizedBox(height: 32),
                                  _FieldLabel(tr(context, 'Email')),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    key: const Key('login-email'),
                                    controller: _emailController,
                                    enabled: !loading,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.email],
                                    decoration: PelinesControlStyles.input(
                                      variant: PelinesInputVariant.login,
                                      hint: tr(
                                        context,
                                        'Enter your email address',
                                      ),
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? tr(context, 'Enter your email.')
                                        : null,
                                  ),
                                  const SizedBox(height: 20),
                                  _FieldLabel(tr(context, 'Password')),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    key: const Key('login-password'),
                                    controller: _passwordController,
                                    enabled: !loading,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    onFieldSubmitted: loading
                                        ? null
                                        : (_) => _submit(),
                                    decoration:
                                        PelinesControlStyles.input(
                                          variant: PelinesInputVariant.login,
                                          hint: tr(
                                            context,
                                            'Enter your password',
                                          ),
                                        ).copyWith(
                                          suffixIcon: IconButton(
                                            tooltip: tr(
                                              context,
                                              _obscurePassword
                                                  ? 'Show password'
                                                  : 'Hide password',
                                            ),
                                            onPressed: loading
                                                ? null
                                                : () => setState(
                                                    () => _obscurePassword =
                                                        !_obscurePassword,
                                                  ),
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                          ),
                                        ),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? tr(context, 'Enter your password.')
                                        : null,
                                  ),
                                  if (errorMessage != null) ...[
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: PelinesColors.brandPrimarySoft,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: PelinesColors.brandPrimary
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        errorMessage,
                                        style: const TextStyle(
                                          color: PelinesColors.destructive,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 32),
                                  FilledButton(
                                    key: const Key('login-submit'),
                                    style: PelinesControlStyles.button(
                                      PelinesButtonVariant.primary,
                                    ),
                                    onPressed: loading ? null : _submit,
                                    child: PelinesButtonLabel(
                                      busy: loading,
                                      label: tr(context, 'Sign In'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            key: const Key('login-yellow-band'),
                            height: 24,
                            color: PelinesColors.brandYellow,
                          ),
                        ],
                      ),
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

  String _messageFor(Object error) {
    return switch (error) {
      AdminAccessDeniedException() => tr(
        context,
        'This account does not have administrator access.',
      ),
      AuthRetryableFetchException() => tr(
        context,
        'Could not reach Supabase. Check your connection and try again.',
      ),
      AuthException() => tr(context, 'The email or password is incorrect.'),
      ApiException() => error.message,
      _ => tr(context, 'Sign in failed. Please try again.'),
    };
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: PelinesColors.textPrimary),
  );
}
