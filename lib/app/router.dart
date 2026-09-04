import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/admin_home_screen.dart';
import '../features/auth/models/admin_session.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/providers/auth_providers.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/historical_orders_screen.dart';
import '../features/orders/presentation/orders_calendar_screen.dart';
import '../features/menu/models/menu_models.dart';
import '../features/menu/presentation/menu_screens.dart';
import '../features/menu/presentation/product_form_screen.dart';
import '../features/menu/presentation/category_form_screen.dart';

enum AuthRouteStatus { loading, authenticated, unauthenticated }

String? authRedirect({
  required AuthRouteStatus status,
  required String location,
}) {
  final bool atLogin = location == '/login';
  return switch (status) {
    AuthRouteStatus.loading =>
      atLogin || location == '/loading' ? null : '/loading',
    AuthRouteStatus.authenticated =>
      location.startsWith('/app') ? null : '/app',
    AuthRouteStatus.unauthenticated => atLogin ? null : '/login',
  };
}

final routerProvider = Provider<GoRouter>((Ref ref) {
  final _RouterRefresh refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState routerState) {
      final AsyncValue<AdminSession?> auth = ref.read(authControllerProvider);
      final AuthRouteStatus status = auth.isLoading
          ? AuthRouteStatus.loading
          : auth.value != null
          ? AuthRouteStatus.authenticated
          : AuthRouteStatus.unauthenticated;
      return authRedirect(
        status: status,
        location: routerState.matchedLocation,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/loading',
        builder: (BuildContext context, GoRouterState state) =>
            const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: '/app',
        builder: (BuildContext context, GoRouterState state) =>
            const AdminHomeScreen(),
        routes: <RouteBase>[
          GoRoute(path: 'menu', builder: (_, _) => const MenuLandingScreen()),
          GoRoute(
            path: 'menu/:kind',
            builder: (_, state) => MenuCategoriesScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/new',
            builder: (_, state) => CategoryFormScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/:categoryId/edit',
            builder: (_, state) => CategoryFormScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
              categoryId: state.pathParameters['categoryId']!,
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/:categoryId',
            builder: (_, state) => MenuProductsScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
              categoryId: state.pathParameters['categoryId']!,
              categoryName: state.uri.queryParameters['name'] ?? 'Products',
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/:categoryId/products/new',
            builder: (_, state) => ProductFormScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
              categoryId: state.pathParameters['categoryId']!,
              categoryName: state.uri.queryParameters['category'] ?? 'Category',
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/:categoryId/products/:productId/edit',
            builder: (_, state) => ProductFormScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
              categoryId: state.pathParameters['categoryId']!,
              productId: state.pathParameters['productId']!,
              categoryName: state.uri.queryParameters['category'] ?? 'Category',
            ),
          ),
          GoRoute(
            path: 'menu/:kind/categories/:categoryId/products/:productId',
            builder: (_, state) => MenuProductDetailScreen(
              kind: MenuKind.fromJson(state.pathParameters['kind']),
              categoryId: state.pathParameters['categoryId']!,
              productId: state.pathParameters['productId']!,
              categoryName: state.uri.queryParameters['category'] ?? 'Category',
            ),
          ),
          GoRoute(
            path: 'orders/calendar',
            builder: (BuildContext context, GoRouterState state) =>
                const OrdersCalendarScreen(),
          ),
          GoRoute(
            path: 'orders/completed',
            builder: (BuildContext context, GoRouterState state) =>
                const HistoricalOrdersScreen(
                  kind: HistoricalOrdersKind.completed,
                ),
          ),
          GoRoute(
            path: 'orders/cancelled',
            builder: (BuildContext context, GoRouterState state) =>
                const HistoricalOrdersScreen(
                  kind: HistoricalOrdersKind.cancelled,
                ),
          ),
          GoRoute(
            path: 'orders/:id',
            builder: (BuildContext context, GoRouterState state) =>
                OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    _subscription = ref.listen<AsyncValue<AdminSession?>>(
      authControllerProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<AdminSession?>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
