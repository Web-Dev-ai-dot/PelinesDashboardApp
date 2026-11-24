import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../account/data/account_repository.dart';
import '../data/auth_repository.dart';
import '../models/admin_session.dart';
import '../models/password_change.dart';
import 'auth_controller.dart';

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return SupabaseAuthRepository(Supabase.instance.client);
});

final passwordAuthRepositoryProvider = Provider<PasswordAuthRepository?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository is PasswordAuthRepository
      ? repository as PasswordAuthRepository
      : null;
});

ApiClient _createClient(Ref ref, {required Object? Function() scope}) {
  final auth = ref.watch(authRepositoryProvider);
  final client = ApiClient(
    accessTokenProvider: auth.getAccessToken,
    recoverToken: auth is SupabaseAuthRepository
        ? auth.recoverRejectedToken
        : null,
    sessionScope: scope,
  );
  ref.onDispose(() => client.dio.close(force: true));
  return client;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final account = ref.watch(
    authControllerProvider.select((value) => value.asData?.value?.profile.id),
  );
  final auth = ref.watch(authRepositoryProvider);
  return _createClient(
    ref,
    scope: () =>
        ref.mounted &&
            auth.currentSession?.user.id == account &&
            ref.read(authControllerProvider).asData?.value?.profile.id ==
                account
        ? account
        : null,
  );
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  // /me establishes the administrator role before protected providers start.
  final auth = ref.watch(authRepositoryProvider);
  var epoch = 0;
  final subscription = auth.authStateChanges.listen((event) {
    if (event.event == AuthChangeEvent.signedOut) epoch++;
  }, onError: (Object _) {});
  ref.onDispose(subscription.cancel);
  return ApiAccountRepository(
    _createClient(
      ref,
      scope: () {
        final user = auth.currentSession?.user.id;
        return user == null ? null : (user, epoch);
      },
    ),
  );
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AdminSession?>(AuthController.new);
