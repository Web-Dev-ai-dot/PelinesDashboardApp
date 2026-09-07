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
          builder: (BuildContext context, BoxConstraints constraints) {
            final double horizontalPadding = constraints.maxWidth < 360
                ? PelinesSpacing.md
                : PelinesSpacing.xl;
            final double logoWidth = (constraints.maxWidth * 0.52)
                .clamp(160.0, 240.0)
                .toDouble();
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: PelinesSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Semantics(
                        image: true,
                        label: 'Pelines Tequila and Mezcal',
                        child: Center(
                          child: Image.asset(
                            'assets/branding/pelines_logo.png',
                            width: logoWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: PelinesSpacing.xl),
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: PelinesColors.card,
                          borderRadius: BorderRadius.circular(
                            PelinesRadius.prominentCard,
                          ),
                          boxShadow: PelinesShadows.subtle,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Container(
                              height: PelinesSpacing.xxs,
                              color: PelinesColors.brandYellow,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(PelinesSpacing.xl),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Text(
                                      'Admin Dashboard',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: PelinesSpacing.xs),
                                    Text(
                                      'Administrator sign in',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: PelinesColors.textSecondary,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: PelinesSpacing.xl),
                                    const _FieldLabel('Email'),
                                    const SizedBox(height: PelinesSpacing.xs),
                                    TextFormField(
                                      controller: _emailController,
                                      enabled: !loading,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const <String>[
                                        AutofillHints.email,
                                      ],
                                      decoration: const InputDecoration(
                                        hintText: 'Enter your email address',
                                      ),
                                      validator: (String? value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Enter your email.'
                                          : null,
                                    ),
                                    const SizedBox(height: PelinesSpacing.md),
                                    const _FieldLabel('Password'),
                                    const SizedBox(height: PelinesSpacing.xs),
                                    TextFormField(
                                      controller: _passwordController,
                                      enabled: !loading,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const <String>[
                                        AutofillHints.password,
                                      ],
                                      onFieldSubmitted: loading
                                          ? null
                                          : (_) => _submit(),
                                      decoration: InputDecoration(
                                        hintText: 'Enter your password',
                                        suffixIcon: IconButton(
                                          onPressed: loading
                                              ? null
                                              : () => setState(
                                                  () => _obscurePassword =
                                                      !_obscurePassword,
                                                ),
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (String? value) =>
                                          value == null || value.isEmpty
                                          ? 'Enter your password.'
                                          : null,
                                    ),
                                    if (errorMessage != null) ...<Widget>[
                                      const SizedBox(height: PelinesSpacing.md),
                                      Container(
                                        padding: const EdgeInsets.all(
                                          PelinesSpacing.sm,
                                        ),
                                        decoration: BoxDecoration(
                                          color: PelinesColors.brandPrimarySoft,
                                          borderRadius: BorderRadius.circular(
                                            PelinesRadius.control,
                                          ),
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
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: PelinesSpacing.xl),
                                    FilledButton(
                                      onPressed: loading ? null : _submit,
                                      child: loading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Sign In'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    return switch (error) {
      AdminAccessDeniedException() =>
        'This account does not have administrator access.',
      AuthRetryableFetchException() =>
        'Could not reach Supabase. Check your connection and try again.',
      AuthException() => 'The email or password is incorrect.',
      ApiException() => error.message,
      _ => 'Sign in failed. Please try again.',
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
