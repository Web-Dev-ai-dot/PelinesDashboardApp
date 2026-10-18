import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/locations/providers/locations_providers.dart';
import '../../features/locations/presentation/pelines_location_selector.dart';
import '../../features/locations/presentation/pelines_location_context.dart';
import '../theme/pelines_tokens.dart';
import '../l10n/language_toggle.dart';
import 'navigation_preferences.dart';

enum AdminDestination {
  orders('/app', 'Orders', Icons.receipt_long_outlined),
  analytics('/app/analytics', 'Analytics', Icons.analytics_outlined),
  calendar('/app/orders/calendar', 'Calendar', Icons.calendar_month_outlined),
  completed('/app/orders/completed', 'Completed', Icons.check_circle_outline),
  cancelled('/app/orders/cancelled', 'Cancelled', Icons.cancel_outlined),
  menu('/app/menu/catering', 'Catering Menu', Icons.room_service_outlined),
  regularMenu(
    '/app/menu/store',
    'Regular Menu',
    Icons.restaurant_menu_outlined,
  ),
  operations('/app/store/locations', 'Locations', Icons.storefront_outlined),
  promotions('/app/promotions', 'Promotions', Icons.local_offer_outlined),
  pickup(
    '/app/store/pickup-settings',
    'Pickup Settings',
    Icons.shopping_bag_outlined,
  ),
  delivery(
    '/app/store/delivery-settings',
    'Delivery Settings',
    Icons.local_shipping_outlined,
  ),
  printing('/app/printing', 'Printer Settings', Icons.print_outlined),
  account('/app/account', 'Account', Icons.person_outline);

  const AdminDestination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;

  String localizedLabel(BuildContext context) =>
      AdminLocalizations.of(context).text(label, key: 'navigation.$name');

  static AdminDestination forPath(String path) {
    final normalized = Uri.parse(path).path;
    for (final destination in values.where((d) => d != orders)) {
      if (normalized == destination.path ||
          normalized.startsWith('${destination.path}/')) {
        return destination;
      }
    }
    if (normalized == '/app/menu' || normalized.startsWith('/app/menu/')) {
      return menu;
    }
    if (normalized == '/app/store-operations' ||
        normalized.startsWith('/app/store-operations/')) {
      return operations;
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
    required this.contentWidth,
    required super.child,
  });
  final AdminNavigationController controller;
  final bool compact;
  final VoidCallback openDrawer;
  final double contentWidth;
  static _NavigationScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NavigationScope>();
  @override
  bool updateShouldNotify(_NavigationScope oldWidget) =>
      compact != oldWidget.compact ||
      controller != oldWidget.controller ||
      contentWidth != oldWidget.contentWidth;
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

/// Page heading below the shell topbar. Back and page actions stay on the
/// original Navigator, so drafts and deep links retain their existing guards.
class AdminSectionScaffold extends ConsumerWidget {
  const AdminSectionScaffold({
    required this.appBar,
    required this.body,
    this.showLocation = true,
    super.key,
  });
  final AdminAppBar appBar;
  final Widget body;
  final bool showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showLocation) return Scaffold(appBar: appBar, body: body);
    final current = ref.watch(currentLocationProvider);
    // AsyncValue may retain the previous branch while loading or on error.
    final location = current.isLoading || current.hasError
        ? null
        : current.value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              key: const Key('persistent-section-header'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final text = appBar.title;
                  final heading = Semantics(
                    header: true,
                    child: text is Text && text.data != null
                        ? Text(
                            text.data!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PelinesTypography.pageTitle(
                              Theme.of(context).textTheme,
                              width: constraints.maxWidth,
                            ),
                          )
                        : text ?? const SizedBox.shrink(),
                  );
                  final title = Row(
                    children: [
                      if (appBar.leading != null) appBar.leading!,
                      Expanded(child: heading),
                      ...?appBar.actions,
                    ],
                  );
                  final contextLine = location == null
                      ? null
                      : PelinesLocationContext(
                          location: location,
                          // Two compact lines on phones. Enlarged text needs
                          // natural height to retain the complete address.
                          maxLines:
                              constraints.maxWidth < 600 &&
                                  MediaQuery.textScalerOf(context).scale(14) <=
                                      14
                              ? 2
                              : null,
                        );
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: PelinesLayout.pagePadding(
                        constraints.maxWidth,
                      ),
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        title,
                        if (contextLine != null) ...[
                          const SizedBox(height: 6),
                          contextLine,
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Compact pill action shared by section headers; the caller owns readiness.
class AdminHeaderRefresh extends StatelessWidget {
  const AdminHeaderRefresh({required this.onPressed, super.key});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr(context, 'Refresh'),
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(),
        foregroundColor: PelinesColors.textPrimary,
      ),
      child: Icon(Icons.refresh, semanticLabel: tr(context, 'Refresh')),
    ),
  );
}

class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminAppBar({
    this.title,
    this.leading,
    this.actions,
    this.subtitle,
    super.key,
  });
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final String? subtitle;
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 80 : 108);
  @override
  Widget build(BuildContext context) {
    final scope = _NavigationScope.of(context);
    final width = scope?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final text = title;
    final heading = text is Text && text.data != null
        ? Text(
            text.data!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PelinesTypography.pageTitle(
              Theme.of(context).textTheme,
              width: width,
            ),
            semanticsLabel: text.semanticsLabel,
          )
        : text;
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: PelinesLayout.pagePadding(width),
      leading: leading,
      title: subtitle == null
          ? heading
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ?heading,
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: PelinesColors.textSecondary),
                ),
              ],
            ),
      actions: actions,
    );
  }
}

Future<bool> confirmAdminSignOut(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'Log out?')),
        content: Text(
          tr(
            context,
            'You will need to sign in again to access the dashboard.',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('logout-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'Cancel')),
          ),
          FilledButton(
            key: const Key('logout-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'Log out')),
          ),
        ],
      ),
    ) ??
    false;

class AdminNavigationShell extends ConsumerStatefulWidget {
  static bool hasLocationContext(BuildContext context) =>
      _NavigationScope.of(context) != null;
  const AdminNavigationShell({
    required this.controller,
    required this.path,
    required this.child,
    this.upcoming = false,
    super.key,
  });
  final AdminNavigationController controller;
  final String path;
  final Widget child;
  final bool upcoming;
  @override
  ConsumerState<AdminNavigationShell> createState() =>
      _AdminNavigationShellState();
}

class _AdminNavigationShellState extends ConsumerState<AdminNavigationShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _busy = false;
  Future<void> _changeLocation() async {
    _scaffold.currentState?.closeDrawer();
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await widget.controller.leaveSection() || !mounted) return;
      await showPelinesLocationPicker(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(AdminDestination destination) async {
    _scaffold.currentState?.closeDrawer();
    if (_busy || (widget.path == destination.path && !widget.upcoming)) return;
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

  Future<void> _openUpcoming() async {
    _scaffold.currentState?.closeDrawer();
    if (_busy || (widget.path == '/app' && widget.upcoming)) return;
    setState(() => _busy = true);
    try {
      if (await widget.controller.leaveSection() && mounted) {
        context.go('/app?view=upcoming');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < PelinesLayout.compactWidth;
      // Default to a rail below 900px to leave room for tablet content. A saved
      // manual choice overrides this default at every permanent-panel width.
      final tablet = constraints.maxWidth - 260 < 640;
      final rail =
          !compact && (ref.watch(navigationCollapsedProvider) ?? tablet);
      final navWidth = rail ? 76.0 : 260.0;
      Widget navigation() => _AdminDestinationList(
        rail: rail,
        phone: compact,
        upcoming: widget.upcoming,
        onUpcoming: _openUpcoming,
        onClose: () => _scaffold.currentState?.closeDrawer(),
        selected: AdminDestination.forPath(widget.path),
        busy: _busy,
        onNavigate: _navigate,
        onSignOut: _signOut,
        onChangeLocation: _changeLocation,
        onToggle: compact
            ? null
            : () => unawaited(
                ref.read(navigationCollapsedProvider.notifier).select(!rail),
              ),
      );
      return _NavigationScope(
        controller: widget.controller,
        compact: compact,
        contentWidth: (constraints.maxWidth - (compact ? 0 : navWidth)).clamp(
          0,
          1400,
        ),
        openDrawer: () => _scaffold.currentState?.openDrawer(),
        child: Scaffold(
          key: _scaffold,
          drawer: compact
              ? Drawer(
                  key: const Key('admin-drawer'),
                  width: 280,
                  backgroundColor: PelinesColors.card,
                  shape: const RoundedRectangleBorder(),
                  child: navigation(),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (!compact) SizedBox(width: navWidth, child: navigation()),
                Expanded(
                  child: Column(
                    children: [
                      _AdminTopBar(
                        compact: compact,
                        openDrawer: () => _scaffold.currentState?.openDrawer(),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            // Keep the nested route's BlockSemantics inside
                            // content so it cannot hide the persistent nav.
                            child: Semantics(
                              container: true,
                              explicitChildNodes: true,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({required this.compact, required this.openDrawer});
  final bool compact;
  final VoidCallback openDrawer;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('admin-topbar'),
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    decoration: const BoxDecoration(
      color: PelinesColors.card,
      border: Border(bottom: BorderSide(color: PelinesColors.border)),
    ),
    child: Row(
      children: [
        if (compact)
          IconButton(
            key: const Key('admin-open-drawer'),
            tooltip: tr(context, 'Open navigation'),
            onPressed: openDrawer,
            icon: const Icon(Icons.menu_rounded, size: 20),
          ),
        const Spacer(),
        const LanguageToggle(inline: true, horizontalPadding: 0),
      ],
    ),
  );
}

class _ShellLocationContext extends ConsumerWidget {
  const _ShellLocationContext({
    required this.compact,
    required this.busy,
    required this.onChange,
    this.phone = false,
  });
  final bool compact, busy;
  final bool phone;
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(currentLocationProvider);
    final locations = ref.watch(locationsProvider);
    final loading = location.isLoading || locations.isLoading;
    final error = location.hasError || locations.hasError;
    final name = loading
        ? tr(context, 'Loading locations...')
        : error
        ? tr(context, 'Locations could not be loaded.')
        : location.value?.name ?? tr(context, 'Choose a location');
    void retry() {
      ref.invalidate(currentLocationProvider);
      unawaited(ref.read(locationsProvider.notifier).retry());
    }

    final action = busy || loading
        ? null
        : error
        ? retry
        : onChange;
    final selector = PelinesLocationSelector(
      locationName:
          phone &&
              !loading &&
              !error &&
              location.value != null &&
              !name.toLowerCase().startsWith('pelines')
          ? 'Pelines $name'
          : name,
      onPressed: action,
      compact: compact,
      shell: true,
      mobileCard: phone,
      subtitle: phone && !loading && !error
          ? locationCityState(location.value?.address)
          : null,
    );
    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          selector,
          if (!phone)
            if (location.value?.address case final String address)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
                child: Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: PelinesColors.textSecondary),
                ),
              ),
        ],
      );
    }
    return selector;
  }
}

class _AdminDestinationList extends ConsumerStatefulWidget {
  const _AdminDestinationList({
    required this.rail,
    required this.selected,
    required this.busy,
    required this.onNavigate,
    required this.onSignOut,
    required this.onChangeLocation,
    required this.phone,
    required this.upcoming,
    required this.onUpcoming,
    required this.onClose,
    this.onToggle,
  });
  final bool rail, busy;
  final bool phone, upcoming;
  final VoidCallback onUpcoming, onClose;
  final AdminDestination selected;
  final ValueChanged<AdminDestination> onNavigate;
  final VoidCallback onSignOut, onChangeLocation;
  final VoidCallback? onToggle;
  @override
  ConsumerState<_AdminDestinationList> createState() =>
      _AdminDestinationListState();
}

class _AdminDestinationListState extends ConsumerState<_AdminDestinationList> {
  static const orders = [
    AdminDestination.orders,
    AdminDestination.calendar,
    AdminDestination.completed,
    AdminDestination.cancelled,
  ];
  static const store = [
    AdminDestination.menu,
    AdminDestination.regularMenu,
    AdminDestination.operations,
    AdminDestination.promotions,
    AdminDestination.pickup,
    AdminDestination.delivery,
    AdminDestination.printing,
  ];
  final Map<String, bool> _open = {};
  final Map<String, FocusNode> _menuFocus = {};
  final Map<String, FocusNode> _firstItemFocus = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_dismissFlyout);
  }

  // Hover need not steal focus from the page. Still allow Escape to dismiss
  // its overlay even when keyboard focus remains outside the menu.
  bool _dismissFlyout(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _menus.values.any((menu) => menu.isOpen)) {
      _closeMenus();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_dismissFlyout);
    for (final node in _menuFocus.values) {
      node.dispose();
    }
    for (final node in _firstItemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  // A 36px painted row inside a 48px hit area; large text grows naturally.
  Widget _mobileRow({
    required String id,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    IconData? chevron,
    bool nested = false,
    bool destructive = false,
  }) {
    final color = destructive
        ? Colors.white
        : selected
        ? PelinesColors.brandPrimary
        : PelinesColors.textPrimary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key(destructive ? 'admin-sign-out' : 'nav-$id'),
        onTap: widget.busy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Ink(
              key: Key('nav-surface-$id'),
              decoration: BoxDecoration(
                color: destructive
                    ? PelinesColors.brandPrimary
                    : selected && !nested
                    ? PelinesColors.brandPrimarySoft
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (nested) ...[
                      SizedBox(
                        width: 6,
                        child: selected
                            ? Icon(Icons.circle, size: 6, color: color)
                            : null,
                      ),
                      const SizedBox(width: 8),
                    ] else if (icon != null) ...[
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        textAlign: destructive
                            ? TextAlign.center
                            : TextAlign.start,
                        style: TextStyle(
                          fontSize: nested ? 13 : 14,
                          height: 1.25,
                          color: color,
                          fontWeight: selected || destructive
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (chevron != null) ...[
                      const SizedBox(width: 8),
                      Icon(chevron, size: 16, color: color),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _AdminDestinationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        widget.upcoming != oldWidget.upcoming) {
      _open.clear();
      _closeMenus();
    }
  }

  final Map<String, MenuController> _menus = {};

  void _closeMenus({String? except}) {
    for (final entry in _menus.entries) {
      if (entry.key != except && entry.value.isOpen) entry.value.close();
    }
  }

  bool _active(String id, List<AdminDestination> children) => id == 'orders'
      ? widget.upcoming ||
            children
                .where((d) => d != AdminDestination.orders)
                .contains(widget.selected)
      : children.contains(widget.selected);

  Widget _railIcon(
    String id,
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap, {
    FocusNode? focusNode,
  }) => MergeSemantics(
    child: Semantics(
      key: Key('nav-semantics-$id'),
      label: label,
      selected: selected,
      child: IconButton(
        focusNode: focusNode,
        key: Key('nav-$id'),
        tooltip: label,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: selected
              ? PelinesColors.brandPrimarySoft
              : Colors.transparent,
          foregroundColor: selected
              ? PelinesColors.brandPrimary
              : PelinesColors.textPrimary,
        ),
        onPressed: widget.busy ? null : onTap,
        icon: Icon(icon, size: 20),
      ),
    ),
  );

  Widget _destination(AdminDestination destination, {bool nested = false}) {
    final todo = destination == AdminDestination.orders;
    final label = todo
        ? tr(context, 'To Do')
        : destination == AdminDestination.account
        ? tr(context, 'My Profile')
        : destination.localizedLabel(context);
    final selected =
        widget.selected == destination && (!todo || !widget.upcoming);
    void navigate() {
      _closeMenus();
      widget.onNavigate(destination);
    }

    if (widget.rail) {
      return _railIcon(
        destination.name,
        label,
        todo ? Icons.checklist_outlined : destination.icon,
        selected,
        navigate,
      );
    }
    return _mobileRow(
      id: destination.name,
      label: label,
      icon: todo ? Icons.checklist_outlined : destination.icon,
      selected: selected,
      nested: nested,
      onTap: navigate,
    );
  }

  Widget _flyoutItem(
    String id,
    String label,
    bool active,
    VoidCallback navigate, {
    FocusNode? focusNode,
  }) => Semantics(
    selected: active,
    child: MenuItemButton(
      focusNode: focusNode,
      key: Key('nav-$id'),
      onPressed: widget.busy
          ? null
          : () {
              _closeMenus();
              navigate();
            },
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: active
            ? PelinesColors.brandPrimary
            : PelinesColors.textPrimary,
        backgroundColor: active
            ? PelinesColors.brandPrimarySoft
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: SizedBox(width: 232, child: Text(label, softWrap: true)),
    ),
  );

  Widget _group(
    String id,
    String label,
    IconData icon,
    List<AdminDestination> children,
  ) {
    final active = _active(id, children);
    final translated = tr(context, label);
    if (widget.rail) {
      final controller = _menus.putIfAbsent(id, MenuController.new);
      final focusNode = _menuFocus.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'navigation-$id'),
      );
      final firstFocus = _firstItemFocus.putIfAbsent(id, FocusNode.new);
      return MenuAnchor(
        controller: controller,
        childFocusNode: focusNode,
        useRootOverlay: true,
        alignmentOffset: const Offset(12, 0),
        style: const MenuStyle(
          alignment: Alignment.topRight,
          backgroundColor: WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(8),
          side: WidgetStatePropertyAll(BorderSide(color: PelinesColors.border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        onOpen: () => _closeMenus(except: id),
        menuChildren: [
          Semantics(
            key: Key('nav-flyout-$id'),
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                width: 232,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translated,
                      style: const TextStyle(
                        color: PelinesColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: PelinesColors.border),
                  ],
                ),
              ),
            ),
          ),
          if (id == 'orders')
            _flyoutItem(
              'upcoming',
              tr(context, 'Upcoming'),
              widget.upcoming,
              widget.onUpcoming,
              focusNode: firstFocus,
            ),
          for (final destination in children)
            if (destination != AdminDestination.orders)
              _flyoutItem(
                destination.name,
                destination == AdminDestination.account
                    ? tr(context, 'My Profile')
                    : destination.localizedLabel(context),
                widget.selected == destination,
                () => widget.onNavigate(destination),
                focusNode: id != 'orders' && destination == children.first
                    ? firstFocus
                    : null,
              ),
        ],
        builder: (context, controller, child) => MouseRegion(
          onEnter: widget.busy ? null : (_) => controller.open(),
          child: _railIcon('group-$id', translated, icon, active, () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && controller.isOpen) firstFocus.requestFocus();
              });
            }
          }, focusNode: focusNode),
        ),
      );
    }
    final open = _open[id] ?? active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: open,
          child: _mobileRow(
            id: 'group-$id',
            label: translated,
            icon: icon,
            selected: active,
            chevron: open ? Icons.expand_less : Icons.expand_more,
            onTap: () => setState(() => _open[id] = !open),
          ),
        ),
        if (open)
          Container(
            key: Key('nav-submenu-$id'),
            margin: const EdgeInsets.only(left: 26),
            padding: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: PelinesColors.border)),
            ),
            child: Column(
              children: [
                if (id == 'orders')
                  _mobileRow(
                    id: 'upcoming',
                    label: tr(context, 'Upcoming'),
                    selected: widget.upcoming,
                    nested: true,
                    onTap: widget.onUpcoming,
                  ),
                for (final destination in children)
                  if (destination != AdminDestination.orders)
                    _destination(destination, nested: true),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider).value?.email;
    return Material(
      key: widget.phone
          ? null
          : Key(widget.rail ? 'admin-rail' : 'admin-sidebar'),
      color: PelinesColors.card,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: PelinesColors.border)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (widget.phone)
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 60),
                        child: Image.asset(
                          'assets/branding/pelines_logo.png',
                          key: const Key('admin-logo'),
                          height: 48,
                          width: 136,
                          fit: BoxFit.contain,
                          semanticLabel: 'Pelines Tequila and Mezcal',
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 8,
                        child: IconButton(
                          key: const Key('admin-close-drawer'),
                          tooltip: tr(context, 'Close navigation'),
                          onPressed: widget.onClose,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.onToggle != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const Key('admin-toggle-navigation'),
                    tooltip: tr(
                      context,
                      widget.rail ? 'Expand navigation' : 'Collapse navigation',
                    ),
                    onPressed: () {
                      _closeMenus();
                      widget.onToggle?.call();
                    },
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      widget.rail
                          ? Icons.view_sidebar_outlined
                          : Icons.view_sidebar,
                      size: 18,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  key: const Key('admin-navigation-list'),
                  padding: widget.phone
                      ? const EdgeInsets.symmetric(horizontal: 12)
                      : const EdgeInsets.all(12),
                  children: [
                    if (!widget.phone)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: widget.rail ? 4 : 16,
                        ),
                        child: Image.asset(
                          'assets/branding/pelines_logo.png',
                          key: const Key('admin-logo'),
                          height: widget.rail ? 32 : 72,
                          fit: BoxFit.contain,
                          semanticLabel: 'Pelines Tequila and Mezcal',
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: widget.phone ? 8 : 12,
                      ),
                      child: _ShellLocationContext(
                        compact: widget.rail,
                        phone: widget.phone,
                        busy: widget.busy,
                        onChange: () {
                          _closeMenus();
                          widget.onChangeLocation();
                        },
                      ),
                    ),
                    ...[
                      _destination(AdminDestination.orders),
                      _group(
                        'orders',
                        'Orders',
                        Icons.receipt_long_outlined,
                        orders,
                      ),
                      _destination(AdminDestination.analytics),
                      _group(
                        'store',
                        'Store',
                        Icons.storefront_outlined,
                        store,
                      ),
                      _group(
                        'account',
                        'Account',
                        AdminDestination.account.icon,
                        [AdminDestination.account],
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(key: Key('admin-sign-out-divider'), height: 1),
              Padding(
                padding: widget.phone
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                    : EdgeInsets.all(widget.rail ? 8 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.rail && email != null)
                      Tooltip(
                        message: email,
                        child: Semantics(
                          label: email,
                          child: const SizedBox(
                            height: 48,
                            child: Icon(Icons.person_outline, size: 20),
                          ),
                        ),
                      ),
                    if (!widget.rail && email != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: widget.phone ? 4 : 12),
                        child: Tooltip(
                          message: email,
                          child: Text(
                            email,
                            key: const Key('admin-user-email'),
                            maxLines: widget.phone ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: PelinesColors.textSecondary,
                                  fontSize: widget.phone ? 11 : null,
                                ),
                          ),
                        ),
                      ),
                    if (widget.phone)
                      _mobileRow(
                        id: 'sign-out',
                        label: tr(context, 'Sign Out'),
                        selected: false,
                        destructive: true,
                        onTap: widget.onSignOut,
                      )
                    else if (widget.rail)
                      IconButton.filled(
                        key: const Key('admin-sign-out'),
                        tooltip: tr(context, 'Sign Out'),
                        onPressed: widget.busy
                            ? null
                            : () {
                                _closeMenus();
                                widget.onSignOut();
                              },
                        icon: const Icon(Icons.logout, size: 18),
                      )
                    else
                      FilledButton(
                        key: const Key('admin-sign-out'),
                        onPressed: widget.busy
                            ? null
                            : () {
                                _closeMenus();
                                widget.onSignOut();
                              },
                        child: Text(
                          tr(context, 'Sign Out'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
