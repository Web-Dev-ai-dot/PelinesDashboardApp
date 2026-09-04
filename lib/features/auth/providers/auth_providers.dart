import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../account/data/account_repository.dart';
import '../data/auth_repository.dart';
import '../models/admin_session.dart';
import 'auth_controller.dart';

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return SupabaseAuthRepository(Supabase.instance.client);
});

final apiClientProvider = Provider<ApiClient>((Ref ref) {
  final AuthRepository auth = ref.watch(authRepositoryProvider);
  return ApiClient(accessTokenProvider: auth.getAccessToken);
});

final accountRepositoryProvider = Provider<AccountRepository>((Ref ref) {
  return ApiAccountRepository(ref.watch(apiClientProvider));
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AdminSession?>(AuthController.new);
