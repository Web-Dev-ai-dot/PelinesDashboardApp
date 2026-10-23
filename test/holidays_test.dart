import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/data/location_selection_store.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/holiday.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/presentation/holidays_section.dart';
import 'package:pelines_admin_app/features/locations/presentation/store_operations_screen.dart';
import 'package:pelines_admin_app/features/locations/providers/holidays_controller.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

Holiday holiday({
  String id = 'h1',
  String date = '2026-12-25',
  String status = 'closed',
  String open = '',
  String close = '',
}) => Holiday(
  id: id,
  name: 'Special day',
  date: date,
  status: status,
  customOpen: open,
  customClose: close,
  notes: '',
);
Map<String, dynamic> locationJson({
  String id = 'a',
  Map<String, dynamic>? extras,
  bool standard = true,
}) => {
  'id': id,
  'name': id == 'a' ? 'Tualatin' : 'Troutdale',
  'slug': id,
  'isActive': true,
  'isAcceptingOrders': true,
  'deliveryFeeCents': 0,
  'deliveryMinimumCents': 0,
  'hoursJson': standard
      ? {
          'mon': {'open': '10:00', 'close': '18:00'},
        }
      : null,
  'hoursExtrasJson': extras ?? {'holidays': []},
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-10-01T00:00:00.000Z',
};

class NoAuth extends AuthController {
  @override
  Future<AdminSession?> build() async => null;
}

class MemoryStore implements LocationSelectionStore {
  String? selected = 'a';
  @override
  Future<String?> readLocationId() async => selected;
  @override
  Future<void> writeLocationId(String id) async {
    selected = id;
  }

  @override
  Future<void> clearLocationId() async {
    selected = null;
  }
}

class Adapter implements HttpClientAdapter {
  Adapter({Map<String, dynamic>? initial}) {
    locations['a'] = initial ?? locationJson();
  }
  final locations = <String, Map<String, dynamic>>{};
  final patches = <RequestOptions>[];
  Completer<void>? hold;
  final started = Completer<void>();
  bool fail = false, timeout = false, apply = true, failReads = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final id = options.path.split('/').last;
    if (options.method == 'PATCH') {
      patches.add(options);
      if (!started.isCompleted) started.complete();
      await hold?.future;
      if (fail) {
        return ResponseBody.fromString(
          '{}',
          400,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }
      if (apply) {
        locations[id] = {
          ...locations[id]!,
          ...Map<String, dynamic>.from(options.data as Map),
          'updatedAt': '2026-10-02T00:00:00.000Z',
        };
      }
      if (timeout) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
    } else if (failReads) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(id == 'locations' ? locations.values.toList() : locations[id]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiLocationsRepository repository(Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
    ..httpClientAdapter = adapter;
  return ApiLocationsRepository(ApiClient(dio: dio));
}

ProviderContainer container(Adapter adapter) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    locationsRepositoryProvider.overrideWithValue(repository(adapter)),
    locationSelectionStoreProvider.overrideWithValue(MemoryStore()),
    authControllerProvider.overrideWith(NoAuth.new),
  ],
);
Future<ProviderContainer> pump(
  WidgetTester tester,
  Adapter adapter, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  bool locations = false,
  AdminNavigationController? navigation,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = container(adapter);
  addTearDown(c.dispose);
  await tester.runAsync(() => c.read(currentLocationProvider.future));
  final content = locations
      ? const StoreOperationsScreen(section: StoreOperationsSection.locations)
      : Consumer(
          builder: (context, ref, _) {
            final l = ref.watch(currentLocationProvider).value!;
            return Scaffold(
              body: SafeArea(
                child: ListView(
                  children: [HolidaysSection(key: ValueKey(l.id), location: l)],
                ),
              ),
            );
          },
        );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(language),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: navigation == null
            ? content
            : AdminNavigationShell(
                controller: navigation,
                path: '/app/store/locations',
                child: Navigator(
                  observers: [navigation],
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => content),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'validation: dates, duplicates, names, times and closed retained values',
    () {
      expect(validateHolidays([holiday()]), isNull);
      expect(validateHolidays([holiday(date: '2026-02-30')]), isNotNull);
      expect(validateHolidays([holiday(date: '2028-02-29')]), isNull);
      expect(
        validateHolidays([holiday(), holiday(id: 'h2')]),
        contains('one holiday'),
      );
      expect(validateHolidays([holiday().copyWith(name: ' ')]), isNotNull);
      for (final h in [
        holiday(status: 'open'),
        holiday(status: 'open', open: '18:00', close: '10:00'),
        holiday(status: 'open', open: '10:00', close: '10:00'),
        holiday(status: 'open', open: '25:00', close: '26:00'),
      ]) {
        expect(validateHolidays([h]), isNotNull);
      }
      expect(
        validateHolidays([
          holiday(status: 'open', open: '10:00', close: '18:00'),
        ]),
        isNull,
      );
      final h = holiday(
        status: 'open',
        open: '10:00',
        close: '18:00',
      ).copyWith(status: 'closed');
      expect(h.customOpen, '10:00');
      expect(h.customClose, '18:00');
      expect(validateHolidays([h]), isNull);
      expect(holidaysFromExtras(null), isEmpty);
      expect(
        () => holidaysFromExtras({'holidays': 'bad'}),
        throwsA(isA<UnsupportedHolidayFormat>()),
      );
    },
  );
  test(
    'API creates edits deletes holidays and preserves all other configuration',
    () async {
      final extras = {
        'closures': [
          {'id': 'closure', 'active': true},
        ],
        'pickupOverride': [
          {'day': 'Mon'},
        ],
        'unknown': {'keep': 1},
        'holidays': [
          {...holiday().toJson(), 'customField': 'keep'},
        ],
      };
      final a = Adapter(initial: locationJson(extras: extras));
      final repo = repository(a);
      final original = holidaysFromExtras(extras).first;
      final updated = original.copyWith(
        name: 'Updated',
        status: 'open',
        customOpen: '10:00',
        customClose: '15:00',
      );
      await repo.saveHolidays(
        locationId: 'a',
        originalUpdatedAt: DateTime.utc(2026, 10),
        holidays: [
          updated,
          holiday(id: 'h2', date: '2026-12-26'),
        ],
        canWrite: () => true,
      );
      final body = a.patches.single.data as Map;
      expect(body.keys, ['hoursExtrasJson']);
      final saved = body['hoursExtrasJson'] as Map;
      expect(saved['closures'], extras['closures']);
      expect(saved['pickupOverride'], extras['pickupOverride']);
      expect(saved['unknown'], extras['unknown']);
      expect((saved['holidays'] as List).first['customField'], 'keep');
      expect((saved['holidays'] as List).first['name'], 'Updated');
      await repo.saveHolidays(
        locationId: 'a',
        originalUpdatedAt: DateTime.utc(2026, 10, 2),
        holidays: [],
        canWrite: () => true,
      );
      expect(
        (a.patches.last.data as Map)['hoursExtrasJson']['holidays'],
        isEmpty,
      );
      expect(a.locations['a']!['hoursJson'], locationJson()['hoursJson']);
    },
  );
  test(
    'API never PATCHes duplicates stale data missing hours or changed context',
    () async {
      for (final mode in [
        'duplicate',
        'stale',
        'hours',
        'context',
        'malformed',
      ]) {
        final a = Adapter(
          initial: locationJson(
            standard: mode != 'hours',
            extras: mode == 'malformed' ? {'holidays': 'bad'} : null,
          ),
        );
        await expectLater(
          () => repository(a).saveHolidays(
            locationId: 'a',
            originalUpdatedAt: mode == 'stale'
                ? DateTime.utc(2026)
                : DateTime.utc(2026, 10),
            holidays: mode == 'duplicate'
                ? [holiday(), holiday(id: 'h2')]
                : [holiday()],
            canWrite: () => mode != 'context',
          ),
          throwsA(anything),
        );
        expect(a.patches, isEmpty, reason: mode);
      }
    },
  );
  for (final applied in [true, false]) {
    test('timeout reconciles applied=$applied without another PATCH', () async {
      final a = Adapter()
        ..timeout = true
        ..apply = applied;
      final c = container(a);
      addTearDown(c.dispose);
      final original = (await c.read(currentLocationProvider.future))!;
      await c
          .read(holidaysSaveProvider.notifier)
          .save(original: original, holidays: [holiday()]);
      expect(a.patches, hasLength(1));
      expect(c.read(holidaysSaveProvider).success, applied);
      expect(c.read(holidaysSaveProvider).reloadRequired, !applied);
    });
  }
  test(
    'controller refuses wrong location and duplicate concurrent writes',
    () async {
      final a = Adapter()..hold = Completer<void>();
      final c = container(a);
      addTearDown(c.dispose);
      final original = (await c.read(currentLocationProvider.future))!;
      final ctrl = c.read(holidaysSaveProvider.notifier);
      final first = ctrl.save(original: original, holidays: [holiday()]);
      await ctrl.save(original: original, holidays: [holiday()]);
      await a.started.future;
      expect(a.patches, hasLength(1));
      a.hold!.complete();
      await first;
      a.locations['b'] = locationJson(id: 'b');
      await c.read(locationsProvider.notifier).retry();
      await c.read(currentLocationProvider.future);
      await c
          .read(currentLocationProvider.notifier)
          .select(Location.fromJson(a.locations['b']!));
      await ctrl.save(original: original, holidays: [holiday()]);
      expect(a.patches, hasLength(1));
    },
  );
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['en', 'es']) {
        testWidgets('cards and modal responsive $width/$scale/$language', (
          tester,
        ) async {
          final a = Adapter(
            initial: locationJson(
              extras: {
                'holidays': [
                  holiday(
                    status: 'open',
                    open: '10:00',
                    close: '18:00',
                  ).toJson(),
                ],
              },
            ),
          );
          await pump(tester, a, width: width, scale: scale, language: language);
          expect(find.byType(TextFormField), findsNothing);
          await tap(tester, 'holiday-edit-h1');
          expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
          expect(
            width < 600 ? find.byType(BottomSheet) : find.byType(Dialog),
            findsOneWidget,
          );
          await enter(tester, 'holiday-0-notes', 'Updated notes');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('holidays-save')));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const Key('holidays-save'))).bottom,
            lessThanOrEqualTo(700),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('add opens empty form and untouched close never writes', (
    tester,
  ) async {
    final a = Adapter();
    await pump(tester, a);
    await tap(tester, 'add-holiday');
    expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
    expect(find.byKey(const Key('holiday-0-open-time')), findsNothing);
    expect(a.patches, isEmpty);
    await tap(tester, 'holiday-editor-close');
    expect(find.byKey(const Key('holiday-editor')), findsNothing);
    expect(a.patches, isEmpty);
  });
  testWidgets('create persists from modal before showing read-only card', (
    tester,
  ) async {
    final a = Adapter();
    await pump(tester, a);
    await tap(tester, 'add-holiday');
    await enter(tester, 'holiday-0-name', 'Special opening');
    await tap(tester, 'holiday-0-date');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(a.patches, isEmpty);
    expect(find.byKey(const Key('holiday-card-h1')), findsNothing);
    await tap(tester, 'holidays-save');
    expect(a.patches, hasLength(1));
    expect(find.byKey(const Key('holiday-editor')), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Special opening'), findsOneWidget);
    expect(find.text('Closed all day'), findsOneWidget);
    expect(find.text('--:--'), findsNothing);
  });
  testWidgets('edit real data persists and Open time draft survives Closed', (
    tester,
  ) async {
    final a = Adapter(
      initial: locationJson(
        extras: {
          'holidays': [
            holiday(status: 'open', open: '10:00', close: '18:00').toJson(),
          ],
        },
      ),
    );
    await pump(tester, a);
    await tap(tester, 'holiday-edit-h1');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('holiday-0-name')))
          .initialValue,
      'Special day',
    );
    Future<void> status(String label) async {
      await tap(tester, 'holiday-0-status');
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await status('Closed');
    expect(find.byKey(const Key('holiday-0-open-time')), findsNothing);
    expect(find.byKey(const Key('holiday-0-close-time')), findsNothing);
    await status('Open');
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    await tap(tester, 'holiday-0-open-time');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await enter(tester, 'holiday-0-name', 'Edited');
    await enter(tester, 'holiday-0-notes', 'Note');
    await tap(tester, 'holidays-save');
    expect(find.byKey(const Key('holiday-editor')), findsNothing);
    expect(find.text('Edited'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Closed all day'), findsNothing);
    expect(
      holidaysFromExtras(
        a.locations['a']!['hoursExtrasJson'] as Map<String, dynamic>,
      ).single.customOpen,
      '10:00',
    );
  });
  testWidgets('cancel dirty edit preserves saved card and branch', (
    tester,
  ) async {
    final a = Adapter()
      ..locations['b'] = locationJson(
        id: 'b',
        extras: {
          'holidays': [
            holiday(id: 'other').copyWith(name: 'Other branch').toJson(),
          ],
        },
      );
    a.locations['a'] = locationJson(
      extras: {
        'holidays': [holiday().toJson()],
      },
    );
    final c = await pump(tester, a);
    await tap(tester, 'holiday-edit-h1');
    await enter(tester, 'holiday-0-name', 'Not saved');
    await tap(tester, 'holiday-editor-cancel');
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(c.read(currentLocationProvider).value!.id, 'a');
    expect(find.byKey(const Key('holidays-unsaved')), findsOneWidget);
    await tap(tester, 'holiday-editor-close');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Special day'), findsOneWidget);
    expect(find.text('Not saved'), findsNothing);
    expect(a.patches, isEmpty);
    await tester.runAsync(
      () => c
          .read(currentLocationProvider.notifier)
          .select(Location.fromJson(a.locations['b']!)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Other branch'), findsOneWidget);
    expect(find.text('Special day'), findsNothing);
  });
  testWidgets('Back requests confirmation for modal draft', (tester) async {
    await pump(tester, Adapter());
    await tap(tester, 'add-holiday');
    await enter(tester, 'holiday-0-name', 'Draft');
    final scope = tester.widget<AdminPopScope<String>>(
      find.byType(AdminPopScope<String>),
    );
    final leave = scope.onRequestLeave!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await leave, false);
    expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
  });
  testWidgets('delete confirms and persists only after acceptance', (
    tester,
  ) async {
    final a = Adapter(
      initial: locationJson(
        extras: {
          'holidays': [holiday().toJson()],
        },
      ),
    );
    await pump(tester, a);
    await tap(tester, 'holiday-delete-h1');
    await tester.tap(find.byKey(const Key('holiday-delete-cancel')));
    await tester.pumpAndSettle();
    expect(a.patches, isEmpty);
    expect(find.byKey(const Key('holiday-card-h1')), findsOneWidget);
    await tap(tester, 'holiday-delete-h1');
    await tester.tap(find.byKey(const Key('holiday-delete-confirm')));
    await tester.pumpAndSettle();
    expect(a.patches, hasLength(1));
    expect(find.byKey(const Key('holiday-card-h1')), findsNothing);
    expect(find.text('No holidays configured.'), findsOneWidget);
  });
  testWidgets(
    'error keeps modal draft and saved card; busy blocks duplicates',
    (tester) async {
      final a =
          Adapter(
              initial: locationJson(
                extras: {
                  'holidays': [holiday().toJson()],
                },
              ),
            )
            ..hold = Completer<void>()
            ..fail = true;
      await pump(tester, a);
      await tap(tester, 'holiday-edit-h1');
      await enter(tester, 'holiday-0-name', 'Edited');
      await tester.ensureVisible(find.byKey(const Key('holidays-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('holidays-save')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('holidays-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('holiday-editor-close')))
            .onPressed,
        isNull,
      );
      a.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
      expect(find.byKey(const Key('holidays-error')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('holiday-0-name')))
            .initialValue,
        'Edited',
      );
      expect(a.patches, hasLength(1));
      await tap(tester, 'holiday-editor-cancel');
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Special day'), findsOneWidget);
      expect(find.text('Edited'), findsNothing);
    },
  );
  testWidgets('delete failure keeps informational card', (tester) async {
    final a = Adapter(
      initial: locationJson(
        extras: {
          'holidays': [holiday().toJson()],
        },
      ),
    )..fail = true;
    await pump(tester, a);
    await tap(tester, 'holiday-delete-h1');
    await tester.tap(find.byKey(const Key('holiday-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('holiday-card-h1')), findsOneWidget);
    expect(find.byKey(const Key('holidays-error')), findsOneWidget);
  });
  testWidgets(
    'duplicates and missing Open times remain in modal without writes',
    (tester) async {
      final a = Adapter(
        initial: locationJson(
          extras: {
            'holidays': [holiday().toJson(), holiday(id: 'h2').toJson()],
          },
        ),
      );
      await pump(tester, a);
      await tap(tester, 'holiday-edit-h1');
      await enter(tester, 'holiday-0-name', 'Edited');
      await tap(tester, 'holidays-save');
      expect(
        find.text('Each date can have only one holiday per location.'),
        findsOneWidget,
      );
      expect(a.patches, isEmpty);
    },
  );
  testWidgets('Open requires explicit valid times', (tester) async {
    final a = Adapter(
      initial: locationJson(
        extras: {
          'holidays': [holiday().toJson()],
        },
      ),
    );
    await pump(tester, a);
    await tap(tester, 'holiday-edit-h1');
    await tap(tester, 'holiday-0-status');
    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();
    await tap(tester, 'holidays-save');
    expect(
      find.text('Choose valid opening and closing times.'),
      findsOneWidget,
    );
    expect(a.patches, isEmpty);
  });
  testWidgets('conflict preserves draft and requires reload confirmation', (
    tester,
  ) async {
    final a = Adapter(
      initial: locationJson(
        extras: {
          'holidays': [holiday().toJson()],
        },
      ),
    );
    await pump(tester, a);
    await tap(tester, 'holiday-edit-h1');
    await enter(tester, 'holiday-0-name', 'Draft');
    a.locations['a'] = {
      ...a.locations['a']!,
      'updatedAt': '2026-10-03T00:00:00.000Z',
      'hoursExtrasJson': {
        'holidays': [holiday().copyWith(name: 'Changed elsewhere').toJson()],
      },
    };
    await tap(tester, 'holidays-save');
    expect(a.patches, isEmpty);
    expect(
      find.descendant(
        of: find.byKey(const Key('holiday-editor')),
        matching: find.text(
          'Store settings were changed elsewhere. Reload before saving.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('holidays-save')))
          .onPressed,
      isNull,
    );
    await tap(tester, 'holiday-editor-reload');
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
    await tap(tester, 'holiday-editor-reload');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('holiday-editor')), findsNothing);
    expect(find.text('Changed elsewhere'), findsOneWidget);
  });
  testWidgets(
    'cards sort only presentation and omit empty notes and Closed times',
    (tester) async {
      final first = holiday(id: 'late', date: '2026-12-25');
      final second = holiday(
        id: 'early',
        date: '2026-11-01',
        status: 'open',
        open: '10:00',
        close: '18:00',
      ).copyWith(notes: 'Useful note');
      final a = Adapter(
        initial: locationJson(
          extras: {
            'holidays': [first.toJson(), second.toJson()],
          },
        ),
      );
      await pump(tester, a);
      expect(
        tester.getTopLeft(find.byKey(const Key('holiday-card-early'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('holiday-card-late'))).dy,
        ),
      );
      expect(find.text('Useful note'), findsOneWidget);
      expect(find.text('Closed all day'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(a.patches, isEmpty);
      expect(
        (a.locations['a']!['hoursExtrasJson'] as Map)['holidays'].first['id'],
        'late',
      );
    },
  );
  for (final width in [390.0, 768.0]) {
    testWidgets(
      'navigation guard protects modal then allows location switch $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final a = Adapter()
          ..locations['b'] = locationJson(
            id: 'b',
            extras: {
              'holidays': [
                holiday(id: 'other').copyWith(name: 'Other branch').toJson(),
              ],
            },
          );
        final navigation = AdminNavigationController();
        final c = await pump(tester, a, width: width, navigation: navigation);
        await tap(tester, 'add-holiday');
        await enter(tester, 'holiday-0-name', 'Draft');
        final keep = navigation.leaveSection();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(await keep, false);
        expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
        expect(c.read(currentLocationProvider).value!.id, 'a');
        final discard = navigation.leaveSection();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(await discard, true);
        expect(find.byKey(const Key('holiday-editor')), findsNothing);
        await tester.runAsync(
          () => c
              .read(currentLocationProvider.notifier)
              .select(Location.fromJson(a.locations['b']!)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Other branch'), findsOneWidget);
        expect(a.patches, isEmpty);
      },
    );
  }
  testWidgets('Locations uses saved cards and add editor', (tester) async {
    await pump(tester, Adapter(), locations: true);
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-holiday')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tap(tester, 'add-holiday');
    expect(find.byKey(const Key('holiday-editor')), findsOneWidget);
    await tap(tester, 'holiday-editor-close');
    expect(find.byKey(const Key('holiday-editor')), findsNothing);
  });
  testWidgets('unsupported JSON disables editing safely', (tester) async {
    await pump(
      tester,
      Adapter(initial: locationJson(extras: {'holidays': 'invalid'})),
    );
    expect(
      find.text(
        'These holidays contain an unsupported format and cannot be edited safely.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('add-holiday')))
          .onPressed,
      isNull,
    );
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets('missing standard hours blocks modal save', (tester) async {
    await pump(tester, Adapter(initial: locationJson(standard: false)));
    await tap(tester, 'add-holiday');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('holidays-save')))
          .onPressed,
      isNull,
    );
  });
}
