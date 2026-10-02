import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_detail_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

void main() {
  test('initializes null as empty and tracks dirty back to clean', () {
    final _NotesRepository repository = _NotesRepository(
      getResult: orderDetail(),
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    final subscription = container.listen(
      orderNotesProvider(repository.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final OrderNotesController controller = container.read(
      orderNotesProvider(repository.id).notifier,
    );

    controller.syncFromCanonical(null);
    expect(container.read(orderNotesProvider(repository.id)).draft, '');
    expect(container.read(orderNotesProvider(repository.id)).isDirty, isFalse);
    controller.edit('Draft');
    expect(container.read(orderNotesProvider(repository.id)).isDirty, isTrue);
    controller.edit('');
    expect(container.read(orderNotesProvider(repository.id)).isDirty, isFalse);
  });

  test('accepts 5000 characters and blocks more than 5000', () {
    final _NotesRepository repository = _NotesRepository(
      getResult: orderDetail(),
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    final subscription = container.listen(
      orderNotesProvider(repository.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final OrderNotesController controller = container.read(
      orderNotesProvider(repository.id).notifier,
    )..syncFromCanonical('');

    controller.edit('a' * 5000);
    expect(container.read(orderNotesProvider(repository.id)).canSave, isTrue);
    controller.edit('a' * 5001);
    expect(container.read(orderNotesProvider(repository.id)).isValid, isFalse);
    expect(container.read(orderNotesProvider(repository.id)).canSave, isFalse);
  });

  test(
    'clean polling adopts remote; dirty polling preserves draft and conflicts',
    () {
      final _NotesRepository repository = _NotesRepository(
        getResult: orderDetail(),
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderNotesProvider(repository.id),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final OrderNotesController controller = container.read(
        orderNotesProvider(repository.id).notifier,
      )..syncFromCanonical('Original');

      controller.syncFromCanonical('Remote');
      expect(container.read(orderNotesProvider(repository.id)).draft, 'Remote');
      controller.edit('Local draft');
      controller.syncFromCanonical('Remote');
      expect(
        container.read(orderNotesProvider(repository.id)).draft,
        'Local draft',
      );
      expect(
        container.read(orderNotesProvider(repository.id)).hasRemoteConflict,
        isFalse,
      );
      controller.syncFromCanonical('Other admin');
      final OrderNotesState state = container.read(
        orderNotesProvider(repository.id),
      );
      expect(state.draft, 'Local draft');
      expect(state.serverNotes, 'Other admin');
      expect(state.hasRemoteConflict, isTrue);
    },
  );

  for (final String draft in <String>['Saved text', '']) {
    test(
      'saves and reconciles ${draft.isEmpty ? 'an empty note' : 'text'}',
      () async {
        final _NotesRepository repository = _NotesRepository(
          patchResult: orderDetail(internalNotes: draft),
          getResult: orderDetail(internalNotes: draft),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        final subscription = container.listen(
          orderNotesProvider(repository.id),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final OrderNotesController controller = container.read(
          orderNotesProvider(repository.id).notifier,
        )..syncFromCanonical(draft.isEmpty ? 'Existing' : 'Original');
        controller.edit(draft);

        await controller.save();

        final OrderNotesState state = container.read(
          orderNotesProvider(repository.id),
        );
        expect(state.phase, OrderNotesPhase.saved);
        expect(state.isDirty, isFalse);
        expect(repository.sentNotes, <String>[draft]);
        expect(repository.getCalls, 1);
      },
    );
  }

  test('PATCH error preserves the dirty draft for manual retry', () async {
    final _NotesRepository repository = _NotesRepository(
      patchError: const ApiException(
        message: 'Access denied.',
        statusCode: 403,
      ),
      getResult: orderDetail(internalNotes: 'Original'),
    );
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    final subscription = container.listen(
      orderNotesProvider(repository.id),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final OrderNotesController controller = container.read(
      orderNotesProvider(repository.id).notifier,
    )..syncFromCanonical('Original');
    controller.edit('Draft');

    await controller.save();

    final OrderNotesState state = container.read(
      orderNotesProvider(repository.id),
    );
    expect(state.phase, OrderNotesPhase.error);
    expect(state.draft, 'Draft');
    expect(state.canSave, isTrue);
  });

  for (final (String remote, OrderNotesPhase phase, bool conflict)
      in <(String, OrderNotesPhase, bool)>[
        ('Draft', OrderNotesPhase.saved, false),
        ('Original', OrderNotesPhase.error, false),
        ('Third value', OrderNotesPhase.error, true),
      ]) {
    test(
      'timeout reconciliation adopts "$remote" without retrying PATCH',
      () async {
        final _NotesRepository repository = _NotesRepository(
          patchError: _networkError(),
          getResult: orderDetail(internalNotes: remote),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        final subscription = container.listen(
          orderNotesProvider(repository.id),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final OrderNotesController controller = container.read(
          orderNotesProvider(repository.id).notifier,
        )..syncFromCanonical('Original');
        controller.edit('Draft');

        await controller.save();

        final OrderNotesState state = container.read(
          orderNotesProvider(repository.id),
        );
        expect(state.phase, phase);
        expect(state.draft, 'Draft');
        expect(state.hasRemoteConflict, conflict);
        expect(repository.patchCalls, 1);
        expect(repository.getCalls, 1);
      },
    );
  }

  testWidgets('conflict requires Save anyway and Cancel preserves draft', (
    WidgetTester tester,
  ) async {
    final _NotesRepository repository = _NotesRepository(
      patchResult: orderDetail(internalNotes: 'Local draft'),
      getResult: orderDetail(internalNotes: 'Original'),
    );
    await _pumpDetail(tester, repository);
    final Finder field = await _showNotes(tester);
    await tester.enterText(field, 'Local draft');
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OrderDetailScreen)),
    );
    container
        .read(orderNotesProvider(repository.id).notifier)
        .syncFromCanonical('Other admin');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('save-internal-notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-internal-notes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-conflict-save')), findsOneWidget);
    expect(repository.patchCalls, 0);
    await tester.tap(find.byKey(const Key('notes-conflict-cancel')));
    await tester.pumpAndSettle();
    expect(repository.patchCalls, 0);
    expect(
      container.read(orderNotesProvider(repository.id)).draft,
      'Local draft',
    );

    await _showNotes(tester);
    await tester.ensureVisible(find.byKey(const Key('save-internal-notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-internal-notes')));
    await tester.pumpAndSettle();
    repository.getResult = orderDetail(internalNotes: 'Local draft');
    await tester.tap(find.byKey(const Key('notes-conflict-save')));
    await tester.pumpAndSettle();
    expect(repository.patchCalls, 1);
  });

  testWidgets('dirty back offers Stay and Discard without saving', (
    WidgetTester tester,
  ) async {
    final _NotesRepository repository = _NotesRepository(
      getResult: orderDetail(),
    );
    await _pumpDetail(tester, repository);
    final Finder field = await _showNotes(tester);
    await tester.enterText(field, 'Unsaved');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-stay')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-stay')));
    await tester.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    expect(repository.patchCalls, 0);

    await tester.ensureVisible(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsNothing);
    expect(repository.patchCalls, 0);
  });

  testWidgets('clean back leaves without a dialog', (
    WidgetTester tester,
  ) async {
    final _NotesRepository repository = _NotesRepository(
      getResult: orderDetail(),
    );
    await _pumpDetail(tester, repository);
    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-stay')), findsNothing);
    expect(find.byType(OrderDetailScreen), findsNothing);
  });

  testWidgets('Android system back protects a dirty draft', (
    WidgetTester tester,
  ) async {
    final _NotesRepository repository = _NotesRepository(
      getResult: orderDetail(),
    );
    await _pumpDetail(tester, repository);
    final Finder field = await _showNotes(tester);
    await tester.enterText(field, 'Unsaved');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unsaved-stay')), findsOneWidget);
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    expect(repository.patchCalls, 0);
  });
}

ProviderContainer _container(_NotesRepository repository) => ProviderContainer(
  overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
);

Future<void> _pumpDetail(
  WidgetTester tester,
  _NotesRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        initialRoute: '/detail',
        routes: <String, WidgetBuilder>{
          '/': (_) => const Scaffold(body: Text('Home')),
          '/detail': (_) => OrderDetailScreen(orderId: repository.id),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Finder> _showNotes(WidgetTester tester) async {
  final Element element = find
      .byKey(const Key('internal-notes-field'))
      .evaluate()
      .last;
  final Finder field = find.byElementPredicate(
    (Element candidate) => identical(candidate, element),
  );
  await tester.scrollUntilVisible(
    field,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  return field;
}

ApiException _networkError() => ApiException(
  message: 'The Pelines server timed out.',
  cause: DioException(
    requestOptions: RequestOptions(path: 'orders/id/internal-notes'),
    type: DioExceptionType.receiveTimeout,
  ),
);

class _NotesRepository implements OrdersRepository {
  _NotesRepository({
    this.patchResult,
    this.patchError,
    required this.getResult,
  });

  final OrderDetail? patchResult;
  final Object? patchError;
  OrderDetail getResult;
  int patchCalls = 0;
  int getCalls = 0;
  final List<String> sentNotes = <String>[];
  String get id => getResult.id;

  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) async {
    patchCalls++;
    sentNotes.add(internalNotes);
    if (patchError != null) throw patchError!;
    return patchResult!;
  }

  @override
  Future<OrderDetail> getOrderById(String id) async {
    getCalls++;
    return getResult;
  }

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async => <OrderSummary>[];

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) => throw UnimplementedError();
}
