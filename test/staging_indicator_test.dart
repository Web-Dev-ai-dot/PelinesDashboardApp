import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/staging_indicator.dart';
import 'package:pelines_admin_app/core/config/app_config.dart';

void main() {
  for (final environment in AppEnvironment.values) {
    testWidgets('staging label visibility in ${environment.name}', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StagingIndicator(
            environment: environment,
            child: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('STAGING'),
        environment == AppEnvironment.staging ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Continue'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
