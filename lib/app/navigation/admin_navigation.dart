import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../theme/pelines_tokens.dart';
import '../l10n/language_toggle.dart';

enum AdminDestination {
  orders('/app', 'Orders', Icons.receipt_long_outlined),
  calendar('/app/orders/calendar', 'Calendar', Icons.calendar_month_outlined),
  completed(
    '/app/orders/completed',
    'Completed Orders',
    Icons.check_circle_outline,
  ),
  cancelled('/app/orders/cancelled', 'Cancelled Orders', Icons.cancel_outlined),
  menu('/app/menu', 'Menu', Icons.restaurant_menu_outlined),
  operations(
    '/app/store-operations',
    'Store Operations',
    Icons.storefront_outlined,
  ),
  promotions('/app/promotions', 'Promotions', Icons.local_offer_outlined),
  printing('/app/printing', 'Printer Settings', Icons.print_outlined),
  account('/app/account', 'Account', Icons.person_outline);

  const AdminDestination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;

  static AdminDestination forPath(String path) {
    final normalized = Uri.parse(path).path;
    for (final destination in values.where((d) => d != orders)) {
      if (normalized == destination.path ||
          normalized.startsWith('${destination.path}/')) {
        return destination;
      }
    }
    return orders;
  }
}

/// Tracks both GoRouter pages and the imperative forms pushed above them.
class AdminNavigationController extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  final Map<Route<dynamic>, Future<bool> Function()> _guards = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }

  Future<bool> leaveSection() async {
    while (_routes.isNotEmpty) {
      final route = _routes.last;
      final guard = _guards[route];
      if (guard != null && !await guard()) return false;
      if (!_routes.contains(route)) continue;
      if (route.popDisposition == RoutePopDisposition.doNotPop) {
        // An unregistered PopScope must never be bypassed by a section change.
        await navigator?.maybePop();
        return false;
      }
      if (_routes.length == 1) return true;
      await navigator?.maybePop();
      if (_routes.contains(route)) return false;
    }
    return true;
  }
}

class _NavigationScope extends InheritedWidget {
  const _NavigationScope({
    required this.controller,
    required this.compact,
    required this.openDrawer,
    required super.child,
  });
  final AdminNavigationController controller;
  final bool compact;
  final VoidCallback openDrawer;
  static _NavigationScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NavigationScope>();
  @override
  bool updateShouldNotify(_NavigationScope oldWidget) =>
      compact != oldWidget.compact || controller != oldWidget.controller;
}

/// Retains PopScope's Back behavior and exposes the same async confirmation to
/// section navigation, which cannot safely use GoRouter.go before it resolves.
class AdminPopScope<T> extends StatefulWidget {
  const AdminPopScope({
    required this.canPop,
    required this.onPopInvokedWithResult,
    required this.child,
    super.key,
  });
  final bool canPop;
  final FutureOr<void> Function(bool, T?) onPopInvokedWithResult;
  final Widget child;
  @override
  State<AdminPopScope<T>> createState() => _AdminPopScopeState<T>();
}

class _AdminPopScopeState<T> extends State<AdminPopScope<T>> {
  AdminNavigationController? _controller;
  ModalRoute<dynamic>? _route;
  Future<bool>? _pending;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller?._guards.remove(_route);
    _controller = _NavigationScope.of(context)?.controller;
    _route = ModalRoute.of(context);
    if (_route != null) _controller?._guards[_route!] = _requestLeave;
  }

  Future<bool> _requestLeave() =>
      _pending ??= _leave().whenComplete(() => _pending = null);
  Future<bool> _leave() async {
    if (widget.canPop) return true;
    await widget.onPopInvokedWithResult(false, null);
    return !(_route?.isActive ?? false);
  }

  @override
  void dispose() {
    _controller?._guards.remove(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<T>(
    canPop: widget.canPop,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        widget.onPopInvokedWithResult(didPop, result);
      } else {
        unawaited(_requestLeave());
      }
    },
    child: widget.child,
  );
}

/// Adds the drawer action without replacing page titles, Back, or page actions.
class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminAppBar({this.title, this.leading, this.actions, super.key});
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) {
    final scope = _NavigationScope.of(context);
    final compact = scope?.compact == true;
    final route = ModalRoute.of(context);
    final back =
        leading ??
        (route?.impliesAppBarDismissal == true
            ? (route is PageRoute && route.fullscreenDialog
                  ? const CloseButton()
                  : const BackButton())
            : null);
    return AppBar(
      title: title,
      leadingWidth: compact && back != null ? 104 : null,
      leading: compact
          ? Row(
              children: [
                IconButton(
                  key: const Key('admin-open-drawer'),
                  tooltip: tr(context, 'Open navigation'),
                  onPressed: scope!.openDrawer,
                  icon: const Icon(Icons.view_sidebar_outlined),
                ),
                if (back != null) SizedBox(width: 48, child: back),
              ],
            )
          : leading,
      actions: actions,
    );
  }
}

Future<bool> confirmAdminSignOut(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:  Text(tr(context, 'Log out?')),
        content:  Text(
          tr(context, 'You will need to sign in again to access the dashboard.'),
        ),
        actions: [
          TextButton(
            key: const Key('logout-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child:  Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:  Text(tr(context, 'Log out')),
          ),
        ],
      ),
    ) ??
    false;

class AdminNavigationShell extends ConsumerStatefulWidget {
  const AdminNavigationShell({
    required this.controller,
    required this.path,
    required this.child,
    super.key,
  });
  final AdminNavigationController controller;
  final String path;
  final Widget child;
  @override
  ConsumerState<AdminNavigationShell> createState() =>
      _AdminNavigationShellState();
}

class _AdminNavigationShellState extends ConsumerState<AdminNavigationShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _busy = false;
  bool _expandRail = false;
  bool _collapseSidebar = false;
  Future<void> _navigate(AdminDestination destination) async {
    _scaffold.currentState?.closeDrawer();
    if (_busy || widget.path == destination.path) return;
    setState(() => _busy = true);
    try {
      if (await widget.controller.leaveSection() && mounted) {
        context.go(destination.path);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    _scaffold.currentState?.closeDrawer();
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await confirmAdminSignOut(context) || !mounted) return;
      if (!await widget.controller.leaveSection() || !mounted) return;
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < PelinesLayout.compactWidth;
      final tablet = constraints.maxWidth < 840;
      final rail = !compact && (tablet ? !_expandRail : _collapseSidebar);
      final navWidth = rail ? 120.0 : 232.0;
      Widget navigation() => _AdminDestinationList(
        rail: rail,
        selected: AdminDestination.forPath(widget.path),
        busy: _busy,
        onNavigate: _navigate,
        onSignOut: _signOut,
        onToggle: compact
            ? null
            : () => setState(() {
                if (tablet) {
                  _expandRail = !_expandRail;
                } else {
                  _collapseSidebar = !_collapseSidebar;
                }
              }),
      );
      return _NavigationScope(
        controller: widget.controller,
        compact: compact,
        openDrawer: () => _scaffold.currentState?.openDrawer(),
        child: Scaffold(
          key: _scaffold,
          drawer: compact
              ? Drawer(key: const Key('admin-drawer'), child: navigation())
              : null,
          body: Row(
            children: [
              if (!compact)
                SizedBox(
                  key: Key(rail ? 'admin-rail' : 'admin-sidebar'),
                  width: navWidth,
                  child: navigation(),
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      );
    },
  );
}

class _AdminDestinationList extends StatelessWidget {
  const _AdminDestinationList({
    required this.rail,
    required this.selected,
    required this.busy,
    required this.onNavigate,
    required this.onSignOut,
    this.onToggle,
  });
  final bool rail;
  final AdminDestination selected;
  final bool busy;
  final ValueChanged<AdminDestination> onNavigate;
  final VoidCallback onSignOut;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) => Material(
    color: PelinesColors.card,
    child: SafeArea(
      child: Column(
        children: [
          if (onToggle != null)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('admin-toggle-navigation'),
                tooltip: rail ? tr(context, 'Expand navigation') : tr(context, 'Collapse navigation'),
                onPressed: onToggle,
                icon: Icon(
                  rail ? Icons.view_sidebar_outlined : Icons.view_sidebar,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(PelinesSpacing.xs),
              children: [
                for (final destination in AdminDestination.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PelinesSpacing.xxs),
                    child: Semantics(
                      selected: selected == destination,
                      child: Material(
                        color: selected == destination
                            ? PelinesColors.brandPrimarySoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          PelinesRadius.control,
                        ),
                        child: InkWell(
                          key: Key('nav-${destination.name}'),
                          borderRadius: BorderRadius.circular(
                            PelinesRadius.control,
                          ),
                          onTap: busy ? null : () => onNavigate(destination),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.all(PelinesSpacing.sm),
                              child: rail
                                  ? Column(
                                      children: [
                                        Icon(
                                          destination.icon,
                                          color: PelinesColors.brandPrimary,
                                        ),
                                        const SizedBox(
                                          height: PelinesSpacing.xxs,
                                        ),
                                        Text(
                                          destination.label,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Icon(
                                          destination.icon,
                                          color: PelinesColors.brandPrimary,
                                        ),
                                        const SizedBox(
                                          width: PelinesSpacing.sm,
                                        ),
                                        Expanded(
                                          child: Text(
                                            destination.label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(key: Key('admin-sign-out-divider'), height: 1),
          const LanguageToggle(),
          Padding(
            padding: const EdgeInsets.all(PelinesSpacing.xs),
            child: TextButton(
              key: const Key('admin-sign-out'),
              onPressed: busy ? null : onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: PelinesColors.destructive,
              ),
              child: rail
                  ?  Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout),
                        Text(tr(context, 'Sign Out'), textAlign: TextAlign.center),
                      ],
                    )
                  :  Row(
                      children: [
                        Icon(Icons.logout),
                        SizedBox(width: PelinesSpacing.sm),
                        Expanded(child: Text(tr(context, 'Sign Out'))),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
