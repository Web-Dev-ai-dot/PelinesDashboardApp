import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'theme/pelines_tokens.dart';

/// Labels every staging route, including login, without covering controls.
class StagingIndicator extends StatelessWidget {
  const StagingIndicator({
    required this.environment,
    required this.child,
    super.key,
  });

  final AppEnvironment environment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (environment != AppEnvironment.staging) return child;
    return Column(
      children: [
        Material(
          color: PelinesColors.brandYellow,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(PelinesSpacing.xxs),
                child: Text(
                  'STAGING',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: PelinesColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
