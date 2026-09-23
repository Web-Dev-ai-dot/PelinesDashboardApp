import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../../features/locations/providers/locations_providers.dart';
import '../../features/locations/presentation/pelines_location_selector.dart';
import '../theme/pelines_tokens.dart';
import '../l10n/language_toggle.dart';

enum AdminDestination {
  orders('/app', 'Orders', Icons.receipt_long_outlined),
  analytics('/app/analytics', 'Analytics', Icons.analytics_outlined),
  calendar('/app/orders/calendar', 'Calendar', Icons.calendar_month_outlined),
  completed('/app/orders/completed', 'Completed', Icons.check_circle_outline),
  cancelled('/app/orders/cancelled', 'Cancelled', Icons.cancel_outlined),
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
  bool _expandRail = false;
  bool _collapseSidebar = false;
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
      // A full sidebar must leave at least 640 logical pixels for content.
      final tablet = constraints.maxWidth - 260 < 640;
      final rail = !compact && (tablet ? !_expandRail : _collapseSidebar);
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
                if (!compact)
                  SizedBox(
                    key: Key(rail ? 'admin-rail' : 'admin-sidebar'),
                    width: navWidth,
                    child: navigation(),
                  ),
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
                            child: widget.child,
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
    AdminDestination.operations,
    AdminDestination.promotions,
    AdminDestination.printing,
  ];
  final Map<String, bool> _open = {};

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
    }
  }

  Widget _destination(AdminDestination destination, {bool nested = false}) {
    final label = nested && destination == AdminDestination.account
        ? tr(context, 'My Profile')
        : destination.localizedLabel(context);
    if (widget.phone) {
      return _mobileRow(
        id: destination.name,
        label: destination == AdminDestination.orders
            ? tr(context, 'To Do')
            : label,
        icon: destination == AdminDestination.orders
            ? Icons.checklist_outlined
            : destination.icon,
        selected:
            widget.selected == destination &&
            (destination != AdminDestination.orders || !widget.upcoming),
        nested: nested,
        onTap: () => widget.onNavigate(destination),
      );
    }
    final selected = widget.selected == destination;
    final color = selected
        ? PelinesColors.brandPrimary
        : PelinesColors.textPrimary;
    final control = Semantics(
      selected: selected,
      button: true,
      label: widget.rail ? label : null,
      child: Material(
        color: selected && !nested
            ? PelinesColors.brandPrimarySoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(PelinesRadius.pill),
        child: InkWell(
          key: Key('nav-${destination.name}'),
          borderRadius: BorderRadius.circular(PelinesRadius.pill),
          onTap: widget.busy ? null : () => widget.onNavigate(destination),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.rail ? 0 : 12,
                vertical: 10,
              ),
              child: widget.rail
                  ? Icon(destination.icon, size: 18, color: color)
                  : Row(
                      children: [
                        if (!nested)
                          Icon(destination.icon, size: 18, color: color)
                        else
                          SizedBox(
                            width: 6,
                            child: selected
                                ? Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: PelinesColors.brandPrimary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              color: color,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: widget.rail ? Tooltip(message: label, child: control) : control,
    );
  }

  Widget _group(
    String id,
    String label,
    IconData icon,
    List<AdminDestination> children,
  ) {
    if (widget.phone) {
      final active = id == 'orders'
          ? widget.upcoming ||
                children
                    .where((d) => d != AdminDestination.orders)
                    .contains(widget.selected)
          : children.contains(widget.selected);
      final open = _open[id] ?? active;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: open,
            child: _mobileRow(
              id: 'group-$id',
              label: tr(context, label),
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
                    if (id != 'orders' ||
                        destination != AdminDestination.orders)
                      _destination(destination, nested: true),
                ],
              ),
            ),
        ],
      );
    }
    final active = children.contains(widget.selected);
    final open = _open[id] ?? active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: open,
          child: TextButton(
            key: Key('nav-group-$id'),
            onPressed: () => setState(() => _open[id] = !open),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: active
                  ? PelinesColors.brandPrimary
                  : PelinesColors.textPrimary,
              backgroundColor: active
                  ? PelinesColors.brandPrimarySoft
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, label),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
            padding: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: PelinesColors.border)),
            ),
            child: Column(
              children: [
                for (final destination in children)
                  _destination(destination, nested: true),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider).value?.email;
    return Material(
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
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/branding/pelines_logo.png',
                        key: const Key('admin-logo'),
                        height: 40,
                        width: 112,
                        fit: BoxFit.contain,
                        semanticLabel: 'Pelines Tequila and Mezcal',
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          key: const Key('admin-close-drawer'),
                          tooltip: tr(context, 'Close navigation'),
                          onPressed: widget.onClose,
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
                    onPressed: widget.onToggle,
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
                          height: widget.rail ? 32 : 64,
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
                        onChange: widget.onChangeLocation,
                      ),
                    ),
                    if (widget.rail) ...[
                      for (final destination in orders)
                        _destination(destination),
                      const Divider(),
                      _destination(AdminDestination.analytics),
                      const Divider(),
                      for (final destination in store)
                        _destination(destination),
                      const Divider(),
                      _destination(AdminDestination.account),
                    ] else ...[
                      if (widget.phone) _destination(AdminDestination.orders),
                      _group(
                        'orders',
                        'Orders',
                        Icons.receipt_long_outlined,
                        orders,
                      ),
                      _group(
                        'analytics',
                        'Analytics',
                        AdminDestination.analytics.icon,
                        [AdminDestination.analytics],
                      ),
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
                        onPressed: widget.busy ? null : widget.onSignOut,
                        icon: const Icon(Icons.logout, size: 18),
                      )
                    else
                      FilledButton(
                        key: const Key('admin-sign-out'),
                        onPressed: widget.busy ? null : widget.onSignOut,
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
