import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/promotions/data/promotions_repository.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/models/promotion_write.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

void main() {
  group('validation and parsing', () {
    test('normalizes code and produces exact create body', () {
      final PromotionWriteResult result = _draft(
        code: ' summer_10 ',
        valueText: '10',
        minimumText: '15.50',
        usageLimitText: '100',
        unlimited: false,
        startDate: DateTime(2026, 9, 5),
        endDate: DateTime(2026, 9, 30),
      ).validate('location-a', now: DateTime.utc(2026, 9, 5, 12));
      expect(result.body, <String, dynamic>{
        'code': 'SUMMER_10',
        'type': 'percent',
        'value': 10,
        'minSubtotalCents': 1550,
        'startsAt': '2026-09-05T07:00:00.000Z',
        'endsAt': '2026-10-01T06:59:59.999Z',
        'usageLimit': 100,
        'locationId': 'location-a',
        'appliesTo': 'both',
        'isActive': true,
      });
      for (final String forbidden in <String>[
        'id',
        'timesRedeemed',
        'createdAt',
        'updatedAt',
      ]) {
        expect(result.body, isNot(contains(forbidden)));
      }
    });

    for (final String code in <String>[
      '',
      '   ',
      'HAS SPACE',
      'BAD!',
      List<String>.filled(41, 'A').join(),
    ]) {
      test('rejects invalid code "$code"', () {
        expect(_draft(code: code).validate('location-a').isValid, false);
      });
    }

    for (final String value in <String>['0', '101', '10.5']) {
      test('rejects invalid percentage $value', () {
        expect(_draft(valueText: value).validate('location-a').isValid, false);
      });
    }

    test('money parser is decimal deterministic', () {
      expect(parseMoneyCents('5', allowZero: false), 500);
      expect(parseMoneyCents('5.5', allowZero: false), 550);
      expect(parseMoneyCents('5.50', allowZero: false), 550);
      expect(parseMoneyCents('0.99', allowZero: false), 99);
      for (final String value in <String>['0', '-1', '1.234', 'abc']) {
        expect(parseMoneyCents(value, allowZero: false), isNull);
      }
      expect(parseMoneyCents('0', allowZero: true), 0);
    });

    test('fixed, minimum, usage and location validation', () {
      expect(
        _draft(
          type: 'fixed',
          valueText: '5.50',
        ).validate('location-a').body?['value'],
        550,
      );
      expect(
        _draft(minimumText: '1.234').validate('location-a').isValid,
        false,
      );
      expect(
        _draft(
          unlimited: false,
          usageLimitText: '0',
        ).validate('location-a').isValid,
        false,
      );
      expect(
        _draft(
          unlimited: false,
          usageLimitText: '1.5',
        ).validate('location-a').isValid,
        false,
      );
      expect(_draft().validate('').isValid, false);
    });

    test('same day is valid and reverse range is rejected', () {
      final DateTime day = DateTime(2026, 9, 5);
      final PromotionWriteResult same = _draft(
        startDate: day,
        endDate: day,
      ).validate('location-a', now: DateTime.utc(2026, 9, 5, 12));
      expect(same.isValid, true);
      expect(same.body!['startsAt'], '2026-09-05T07:00:00.000Z');
      expect(same.body!['endsAt'], '2026-09-06T06:59:59.999Z');
      expect(
        _draft(
          startDate: day,
          endDate: day.subtract(const Duration(days: 1)),
        ).validate('location-a').isValid,
        false,
      );
    });
  });

  group('Pacific dates', () {
    test('past end dates are blocked at Pacific midnight, including edits', () {
      final day = DateTime(2026, 9, 5);
      final draft = _draft(endDate: day);
      expect(
        draft
            .validate('location-a', now: DateTime.utc(2026, 9, 6, 6, 59, 59))
            .isValid,
        true,
      );
      final expired = draft.validate(
        'location-a',
        now: DateTime.utc(2026, 9, 6, 7),
      );
      expect(expired.isValid, false);
      expect(
        expired.message,
        'End date cannot be in the past. Choose today or a future date.',
      );
      expect(
        _draft(endDate: DateTime(2026, 9, 7))
            .validate('location-a', now: DateTime.utc(2026, 9, 6, 7))
            .isValid,
        true,
      );
      expect(
        _draft()
            .validate('location-a', now: DateTime.utc(2026, 9, 6, 7))
            .isValid,
        true,
      );
      final existing = Discount.fromJson(
        _json()..['endsAt'] = '2026-09-06T06:59:59.999Z',
      );
      expect(
        PromotionDraft.fromDiscount(existing)
            .validate('location-a', now: DateTime.utc(2026, 9, 6, 7))
            .isValid,
        false,
      );
    });
    test('PDT and PST use different real offsets', () {
      expect(
        pacificStartOfDayUtc(DateTime(2026, 9, 5)).toIso8601String(),
        '2026-09-05T07:00:00.000Z',
      );
      expect(
        pacificEndOfDayUtc(DateTime(2026, 9, 5)).toIso8601String(),
        '2026-09-06T06:59:59.999Z',
      );
      expect(
        pacificStartOfDayUtc(DateTime(2026, 1, 10)).toIso8601String(),
        '2026-01-10T08:00:00.000Z',
      );
      expect(
        pacificEndOfDayUtc(DateTime(2026, 1, 10)).toIso8601String(),
        '2026-01-11T07:59:59.999Z',
      );
    });

    test('UTC round-trip returns the selected Pacific calendar day', () {
      final DateTime selected = DateTime(2026, 9, 5);
      expect(pacificCalendarDate(pacificStartOfDayUtc(selected)), selected);
      expect(pacificCalendarDate(pacificEndOfDayUtc(selected)), selected);
    });
  });

  group('partial patch', () {
    final Map<String, dynamic> canonical = <String, dynamic>{
      'code': 'SAVE10',
      'type': 'percent',
      'value': 10,
      'minSubtotalCents': 0,
      'startsAt': null,
      'endsAt': null,
      'usageLimit': null,
      'appliesTo': 'both',
      'isActive': true,
    };
    final Map<String, dynamic> alternatives = <String, dynamic>{
      'code': 'NEWCODE',
      'type': 'fixed',
      'value': 500,
      'minSubtotalCents': 2500,
      'startsAt': '2026-09-05T07:00:00.000Z',
      'endsAt': '2026-10-01T06:59:59.999Z',
      'usageLimit': 50,
      'appliesTo': 'regular',
      'isActive': false,
    };
    for (final String field in alternatives.keys) {
      test('$field-only edit emits only $field', () {
        final Map<String, dynamic> desired = <String, dynamic>{
          ...canonical,
          field: alternatives[field],
          'locationId': 'location-a',
        };
        expect(partialPromotionPatch(canonical, desired), <String, dynamic>{
          field: alternatives[field],
        });
      });
    }

    test('multiple edits produce one exact set without location', () {
      expect(
        partialPromotionPatch(canonical, <String, dynamic>{
          ...canonical,
          'code': 'NEWCODE',
          'value': 20,
          'isActive': false,
          'locationId': 'other',
        }),
        <String, dynamic>{'code': 'NEWCODE', 'value': 20, 'isActive': false},
      );
    });
  });

  test('repository uses POST and PATCH bodies exactly', () async {
    final List<RequestOptions> requests = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(requestOptions: options, data: _json()),
          );
        },
      ),
    );
    final ApiPromotionsRepository repository = ApiPromotionsRepository(
      ApiClient(dio: dio),
    );
    await repository.createPromotion(<String, dynamic>{
      'code': 'NEW',
      'locationId': 'location-a',
    });
    await repository.updatePromotion('discount-id', <String, dynamic>{
      'value': 20,
    });
    expect(requests[0].method, 'POST');
    expect(requests[0].path, 'discounts');
    expect(requests[0].data, <String, dynamic>{
      'code': 'NEW',
      'locationId': 'location-a',
    });
    expect(requests[1].method, 'PATCH');
    expect(requests[1].path, 'discounts/discount-id');
    expect(requests[1].data, <String, dynamic>{'value': 20});
  });

  test('create location change sends no POST', () async {
    final _WriteRepository repository = _WriteRepository(<Discount>[]);
    final ProviderContainer container = _container(
      repository,
      locationId: 'location-b',
    );
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(promotionFormMutationProvider.notifier)
        .create(
          locationId: 'location-a',
          body: _draft().validate('location-a').body!,
        );
    expect(repository.createCalls, 0);
  });

  test('edit conflict sends no PATCH', () async {
    final Discount canonical = _discount(updatedAt: DateTime.utc(2026, 9, 6));
    final _WriteRepository repository = _WriteRepository(<Discount>[canonical]);
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container.read(promotionsProvider.future);
    await container
        .read(promotionFormMutationProvider.notifier)
        .edit(
          discountId: canonical.id,
          locationId: 'location-a',
          originalUpdatedAt: DateTime.utc(2026, 9, 5),
          desired: _draft().validate('location-a').body!,
        );
    expect(repository.updateCalls, 0);
    expect(
      container.read(promotionFormMutationProvider).phase,
      PromotionFormPhase.conflict,
    );
  });

  test('edit location change sends no PATCH', () async {
    final Discount canonical = _discount();
    final _WriteRepository repository = _WriteRepository(<Discount>[canonical]);
    final ProviderContainer container = _container(
      repository,
      locationId: 'location-b',
    );
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(promotionFormMutationProvider.notifier)
        .edit(
          discountId: canonical.id,
          locationId: 'location-a',
          originalUpdatedAt: canonical.updatedAt,
          desired: _draft(code: 'NEWCODE').validate('location-a').body!,
        );
    expect(repository.getCalls, 0);
    expect(repository.updateCalls, 0);
  });

  for (final ({String name, List<Discount> result, bool success}) scenario
      in <({String name, List<Discount> result, bool success})>[
        (
          name: 'applied',
          result: <Discount>[_discount(code: 'NEWCODE')],
          success: true,
        ),
        (name: 'not applied', result: <Discount>[_discount()], success: false),
        (name: 'removed', result: <Discount>[], success: false),
        (
          name: 'scope changed',
          result: <Discount>[_discount(code: 'NEWCODE', locationId: null)],
          success: false,
        ),
      ]) {
    test('edit timeout ${scenario.name} does not retry PATCH', () async {
      final Discount before = _discount();
      final _WriteRepository repository = _WriteRepository(
        <Discount>[before],
        afterWrite: scenario.result,
        updateError: _timeout(),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container.read(promotionsProvider.future);
      await container
          .read(promotionFormMutationProvider.notifier)
          .edit(
            discountId: before.id,
            locationId: 'location-a',
            originalUpdatedAt: before.updatedAt,
            desired: _draft(code: 'NEWCODE').validate('location-a').body!,
          );
      expect(repository.updateCalls, 1);
      expect(
        container.read(promotionFormMutationProvider).phase,
        scenario.success
            ? PromotionFormPhase.success
            : PromotionFormPhase.error,
      );
    });
  }

  for (final bool created in <bool>[true, false]) {
    test(
      'create timeout ${created ? 'matches' : 'does not match'} without retry',
      () async {
        final Discount result = _discount(code: created ? 'SAVE10' : 'OTHER');
        final _WriteRepository repository = _WriteRepository(
          <Discount>[],
          afterWrite: <Discount>[result],
          createError: _timeout(),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        await container
            .read(promotionFormMutationProvider.notifier)
            .create(
              locationId: 'location-a',
              body: _draft().validate('location-a').body!,
            );
        expect(repository.createCalls, 1);
        expect(
          container.read(promotionFormMutationProvider).phase,
          created ? PromotionFormPhase.success : PromotionFormPhase.error,
        );
      },
    );
  }

  testWidgets(
    'create form shows fixed location, switches type, validates and guards discard',
    (WidgetTester tester) async {
      final ProviderContainer container = _container(
        _WriteRepository(<Discount>[]),
      );
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PromotionFormScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tualatin'), findsOneWidget);
      expect(find.text('Percentage'), findsOneWidget);
      expect(find.text('Regular & Catering'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Code'),
        'BAD CODE',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Discount'), '10');
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('promotion-validation-error')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    },
  );

  testWidgets('edit shows usage claimed and global scope', (
    WidgetTester tester,
  ) async {
    final Discount local = _discount();
    final _WriteRepository repository = _WriteRepository(<Discount>[local]);
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container.read(promotionsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PromotionFormScreen(discountId: 'discount-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Usage claimed'), findsOneWidget);
    expect(find.textContaining('created but not completed'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('promotion-form-save')).first,
          )
          .onPressed,
      isNull,
    );

    repository.current = <Discount>[_discount(locationId: null)];
    container
        .read(promotionsProvider.notifier)
        .adoptCanonical(repository.current);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PromotionFormScreen(discountId: 'discount-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('All locations'), findsWidgets);
    expect(
      find.text('This promotion cannot be edited from mobile.'),
      findsNothing,
    );
  });
}

PromotionDraft _draft({
  String code = 'SAVE10',
  String type = 'percent',
  String valueText = '10',
  String minimumText = '0',
  DateTime? startDate,
  DateTime? endDate,
  String usageLimitText = '',
  bool unlimited = true,
}) => PromotionDraft(
  code: code,
  type: type,
  valueText: valueText,
  appliesTo: 'both',
  minimumText: minimumText,
  startDate: startDate,
  endDate: endDate,
  usageLimitText: usageLimitText,
  unlimited: unlimited,
  isActive: true,
);

ProviderContainer _container(
  _WriteRepository repository, {
  String locationId = 'location-a',
}) => ProviderContainer(
  overrides: [
    promotionsRepositoryProvider.overrideWithValue(repository),
    currentLocationProvider.overrideWith(
      () => _LocationController(_location(locationId)),
    ),
  ],
);

class _LocationController extends CurrentLocationController {
  _LocationController(this.value);
  final Location value;
  @override
  Future<Location?> build() async => value;
}

class _WriteRepository implements PromotionsRepository {
  @override
  Future<void> deletePromotion(String id) => throw UnimplementedError();

  _WriteRepository(
    this.current, {
    this.afterWrite,
    this.createError,
    this.updateError,
  });
  List<Discount> current;
  final List<Discount>? afterWrite;
  final Object? createError;
  final Object? updateError;
  int createCalls = 0;
  int updateCalls = 0;
  int getCalls = 0;
  @override
  Future<List<Discount>> getDiscounts() async {
    getCalls++;
    return List<Discount>.of(current);
  }

  @override
  Future<Discount> createPromotion(Map<String, dynamic> body) async {
    createCalls++;
    if (afterWrite != null) current = List<Discount>.of(afterWrite!);
    if (createError != null) throw createError!;
    return current.single;
  }

  @override
  Future<Discount> updatePromotion(
    String id,
    Map<String, dynamic> patch,
  ) async {
    updateCalls++;
    if (afterWrite != null) current = List<Discount>.of(afterWrite!);
    if (updateError != null) throw updateError!;
    return current.single;
  }

  @override
  Future<Discount> setActive(String id, bool isActive) =>
      updatePromotion(id, <String, dynamic>{'isActive': isActive});
}

Location _location(String id) => Location(
  id: id,
  name: 'Tualatin',
  slug: 'tualatin',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Discount _discount({
  String code = 'SAVE10',
  String? locationId = 'location-a',
  DateTime? updatedAt,
}) => Discount.fromJson(
  _json()
    ..['code'] = code
    ..['locationId'] = locationId
    ..['updatedAt'] = (updatedAt ?? DateTime.utc(2026, 9, 5)).toIso8601String(),
);

Map<String, dynamic> _json() => <String, dynamic>{
  'id': 'discount-id',
  'code': 'SAVE10',
  'type': 'percent',
  'value': 10,
  'minSubtotalCents': 0,
  'startsAt': null,
  'endsAt': null,
  'usageLimit': null,
  'timesRedeemed': 0,
  'locationId': 'location-a',
  'appliesTo': 'both',
  'isActive': true,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-09-05T00:00:00.000Z',
};

ApiException _timeout() => ApiException(
  message: 'timeout',
  cause: DioException(
    requestOptions: RequestOptions(path: 'discounts'),
    type: DioExceptionType.receiveTimeout,
  ),
);
