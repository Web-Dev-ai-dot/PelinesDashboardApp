import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'router.dart';
import 'staging_indicator.dart';
import 'theme/app_theme.dart';

class PelinesAdminApp extends ConsumerWidget {
  const PelinesAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pelines Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => StagingIndicator(
        environment: AppConfig.environment,
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
