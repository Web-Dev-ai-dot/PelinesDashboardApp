import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/models/promotion_code_generator.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

import 'promotions_layout_test.dart' as h;

class CreateRepo extends h.Repo {
  CreateRepo() : super([]);
  int creates = 0;
  Object? createError;
  bool apply = true;
  Completer<void>? hold;
  Map<String, dynamic>? body;
  @override
  Future<Discount> createPromotion(Map<String, dynamic> input) async {
    creates++;
    body = {...input};
    await hold?.future;
    final row = Discount.fromJson({
      ...input,
      'id': 'created',
      'timesRedeemed': 0,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });
    if (apply) current = [row];
    if (createError != null) throw createError!;
    return row;
  }
}

String code(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('promotion-code')))
    .controller!
    .text;
Future<void> open(WidgetTester tester, {bool generated = true}) =>
    h.tap(tester, generated ? 'generate-promotion-code' : 'add-promotion');
Future<void> value(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.byKey(const Key('promotion-value')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('promotion-value')), text);
  await tester.pumpAndSettle();
}

void main() {
  test('secure local candidates are variable and respect code constraints', () {
    final codes = List.generate(128, (_) => generatePromotionCode());
    expect(codes.toSet(), hasLength(128));
    for (final c in codes) {
      expect(c, matches(RegExp(r'^[A-HJ-NP-Z2-9]{12}$')));
    }
  });
  for (final generated in [true, false]) {
    for (final width in [320.0, 390.0, 800.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final lang in ['en', 'es']) {
          testWidgets(
            'shared create page generated=$generated $width $scale $lang',
            (tester) async {
              final repo = CreateRepo();
              await h.pump(
                tester,
                repo,
                width: width,
                scale: scale,
                lang: lang,
              );
              expect(
                tester
                    .widget<OutlinedButton>(
                      find.byKey(const Key('generate-promotion-code')),
                    )
                    .onPressed,
                isNotNull,
              );
              await open(tester, generated: generated);
              expect(find.byType(PromotionFormScreen), findsOneWidget);
              expect(find.byType(AlertDialog), findsNothing);
              expect(code(tester).isNotEmpty, generated);
              expect(
                tester
                    .widget<TextField>(find.byKey(const Key('promotion-code')))
                    .decoration!
                    .hintText,
                generated
                    ? isNull
                    : (lang == 'en' ? 'Example: LUNCH10' : 'Ejemplo: LUNCH10'),
              );
              expect(
                find.text(
                  lang == 'en'
                      ? 'Create discount code'
                      : 'Crear código de descuento',
                ),
                findsOneWidget,
              );
              expect(
                find.byKey(const Key('promotion-date-pair-column')),
                findsOneWidget,
              );
              expect(find.byKey(const Key('promotion-value')), findsOneWidget);
              expect(
                find.byKey(const Key('promotion-minimum')),
                findsOneWidget,
              );
              expect(find.byKey(const Key('promotion-usage')), findsOneWidget);
              await h.tap(tester, 'promotion-form-save');
              expect(repo.creates, 0);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
  for (final generated in [true, false]) {
    for (final control in [
      'promotion-form-cancel',
      'promotion-form-close',
      'back',
    ]) {
      testWidgets('$control leaves without creating generated=$generated', (
        tester,
      ) async {
        final repo = CreateRepo();
        final result = await h.pump(tester, repo);
        await open(tester, generated: generated);
        if (!generated) {
          await tester.enterText(
            find.byKey(const Key('promotion-code')),
            'MANUAL',
          );
          await tester.pumpAndSettle();
        }
        if (control == 'back') {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await h.tap(tester, control);
        }
        await tester.tap(find.byKey(const Key('promotion-discard-confirm')));
        await tester.pumpAndSettle();
        expect(repo.creates, 0);
        expect(find.byType(PromotionsScreen), findsOneWidget);
        expect(result.c.read(currentLocationProvider).value!.id, 'a');
      });
    }
  }
  testWidgets('repeated Generate taps open only one page', (tester) async {
    final repo = CreateRepo();
    await h.pump(tester, repo);
    final press = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('generate-promotion-code')),
        )
        .onPressed!;
    press();
    press();
    await tester.pumpAndSettle();
    expect(find.byType(PromotionFormScreen), findsOneWidget);
    await h.tap(tester, 'promotion-form-close');
    await tester.tap(find.byKey(const Key('promotion-discard-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(PromotionFormScreen), findsNothing);
    expect(find.byType(PromotionsScreen), findsOneWidget);
    expect(repo.creates, 0);
  });
  testWidgets('generation remains stable across rebuilds and can regenerate', (
    tester,
  ) async {
    final result = await h.pump(tester, CreateRepo());
    await open(tester);
    final first = code(tester);
    result.c.read(promotionsProvider.notifier).adoptCanonical([]);
    await tester.pumpAndSettle();
    expect(code(tester), first);
    await h.tap(tester, 'promotion-regenerate-code');
    expect(code(tester), isNot(first));
  });
  for (final generated in [true, false]) {
    testWidgets(
      'user editable code saves with existing POST generated=$generated',
      (tester) async {
        final repo = CreateRepo();
        final result = await h.pump(tester, repo);
        await open(tester, generated: generated);
        await tester.enterText(
          find.byKey(const Key('promotion-code')),
          'MY_CUSTOM',
        );
        await value(tester, '15');
        await h.tap(tester, 'promotion-form-save');
        expect(repo.creates, 1);
        expect(repo.body!['code'], 'MY_CUSTOM');
        expect(repo.body!['value'], 15);
        expect(repo.body!['locationId'], 'a');
        expect(find.byType(PromotionsScreen), findsOneWidget);
        expect(result.c.read(promotionsProvider).value!.single.id, 'created');
        expect(find.text('MY_CUSTOM'), findsOneWidget);
      },
    );
  }
  testWidgets('duplicate error permits new code without losing draft fields', (
    tester,
  ) async {
    final repo = CreateRepo()
      ..apply = false
      ..createError = const ApiException(
        message: 'A promotion with this code already exists.',
        statusCode: 409,
      );
    await h.pump(tester, repo, lang: 'es');
    await open(tester);
    final first = code(tester);
    await value(tester, '17');
    await tester.enterText(find.byKey(const Key('promotion-minimum')), '5.99');
    await h.tap(tester, 'promotion-form-save');
    expect(find.byKey(const Key('promotion-save-error')), findsOneWidget);
    expect(
      find.text('Ya existe una promoción con este código.'),
      findsOneWidget,
    );
    await h.tap(tester, 'promotion-regenerate-code');
    expect(code(tester), isNot(first));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('promotion-value')))
          .controller!
          .text,
      '17',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('promotion-minimum')))
          .controller!
          .text,
      '5.99',
    );
    expect(repo.creates, 1);
    expect(find.byKey(const Key('promotion-save-error')), findsNothing);
    repo.apply = true;
    repo.createError = null;
    await h.tap(tester, 'promotion-form-save');
    expect(repo.creates, 2);
    expect(find.byType(PromotionsScreen), findsOneWidget);
  });
  testWidgets(
    'global scope is real null; ambiguous create reconciles without retry',
    (tester) async {
      final repo = CreateRepo()
        ..createError = ApiException(
          message: 'Timeout',
          cause: DioException(
            requestOptions: RequestOptions(path: 'discounts'),
            type: DioExceptionType.receiveTimeout,
          ),
        );
      final result = await h.pump(tester, repo);
      await open(tester);
      await value(tester, '20');
      await tester.ensureVisible(find.byKey(const ValueKey('Location-local')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('Location-local')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All locations').last);
      await tester.pumpAndSettle();
      await h.tap(tester, 'promotion-form-save');
      expect(repo.creates, 1);
      expect(repo.body!['locationId'], isNull);
      expect(find.byType(PromotionsScreen), findsOneWidget);
      expect(result.c.read(currentLocationProvider).value!.id, 'a');
    },
  );
  for (final generated in [true, false]) {
    for (final status in [403, 409, 500]) {
      testWidgets(
        'server rejection $status stays on form generated=$generated',
        (tester) async {
          final repo = CreateRepo()
            ..apply = false
            ..createError = ApiException(
              message: 'Rejected',
              statusCode: status,
            );
          await h.pump(tester, repo);
          await open(tester, generated: generated);
          if (!generated) {
            await tester.enterText(
              find.byKey(const Key('promotion-code')),
              'MANUAL',
            );
          }
          await value(tester, '10');
          await h.tap(tester, 'promotion-form-save');
          expect(repo.creates, 1);
          expect(find.byType(PromotionFormScreen), findsOneWidget);
          expect(find.text('Rejected'), findsOneWidget);
        },
      );
    }
  }
  testWidgets('create guards duplicate submits and branch changes', (
    tester,
  ) async {
    final repo = CreateRepo()..hold = Completer<void>();
    final result = await h.pump(tester, repo);
    await open(tester);
    await value(tester, '10');
    await tester.ensureVisible(find.byKey(const Key('promotion-form-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('promotion-form-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.creates, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('promotion-form-save')))
          .onPressed,
      isNull,
    );
    repo.hold!.complete();
    await tester.pumpAndSettle();
    await open(tester);
    await value(tester, '10');
    (result.c.read(currentLocationProvider.notifier) as h.Current).replace(
      h.location('b'),
    );
    await tester.pumpAndSettle();
    await h.tap(tester, 'promotion-form-save');
    expect(repo.creates, 1);
    expect(find.byType(PromotionFormScreen), findsOneWidget);
  });
}
