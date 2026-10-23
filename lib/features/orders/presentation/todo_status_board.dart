import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/order_models.dart';
import 'order_preview_card.dart';

const todoStatuses = [
  OrderStatus.pending,
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.ready,
];

String todoStatusLabel(OrderStatus status) => switch (status) {
  OrderStatus.pending => 'Waiting',
  OrderStatus.confirmed => 'Confirmed',
  OrderStatus.preparing => 'Preparing',
  OrderStatus.ready => 'Ready',
  OrderStatus.delivered => 'Picked Up',
  _ => '',
};

(Color, Color) _boardColors(OrderStatus status) => switch (status) {
  OrderStatus.pending => (
    PelinesBoardColors.waitingText,
    PelinesBoardColors.waitingBackground,
  ),
  OrderStatus.confirmed => (
    PelinesBoardColors.confirmedText,
    PelinesBoardColors.confirmedBackground,
  ),
  OrderStatus.preparing => (
    PelinesBoardColors.preparingText,
    PelinesBoardColors.preparingBackground,
  ),
  OrderStatus.delivered => (PelinesColors.textPrimary, PelinesColors.border),
  _ => (PelinesBoardColors.readyText, PelinesBoardColors.readyBackground),
};

/// Snap a gesture to its starting page or one neighbour, including fast flings.
/// Keeping the existing eager scroll view preserves every column's vertical
/// scroll state and order widgets when the available width changes.
class _TodoPagePhysics extends ScrollPhysics {
  const _TodoPagePhysics({
    required this.extent,
    required this.startPage,
    this.userGesture,
    super.parent,
  });
  final double extent;
  final int Function() startPage;
  final bool Function()? userGesture;

  @override
  _TodoPagePhysics applyTo(ScrollPhysics? ancestor) => _TodoPagePhysics(
    extent: extent,
    startPage: startPage,
    userGesture: userGesture,
    parent: buildParent(ancestor),
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final start = startPage();
    final distance = position.pixels - start * extent;
    final direction = userGesture?.call() == false
        ? 0
        : velocity.abs() >= 300
        ? velocity.sign.toInt()
        : distance.abs() >= extent * .2
        ? distance.sign.toInt()
        : 0;
    final target = ((start + direction) * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// Four active states and, for To Do, a terminal pickup projection.
class TodoStatusBoard extends StatefulWidget {
  const TodoStatusBoard({
    required this.orders,
    this.pickedUpOrders = const [],
    this.showChannel = false,
    this.paged = true,
    super.key,
  });
  final List<OrderSummary> orders;
  final List<OrderSummary> pickedUpOrders;
  final bool showChannel;
  final bool paged;

  @override
  State<TodoStatusBoard> createState() => _TodoStatusBoardState();
}

class _TodoStatusBoardState extends State<TodoStatusBoard> {
  final _scroll = ScrollController();
  final _tabs = ScrollController();
  int _selected = 0;
  double _stride = 332;
  double _tabExtent = 1;
  int _boardStart = 0, _tabStart = 0;
  bool _single = false, _layoutPending = false;
  bool _boardGesture = false;
  int _layoutVersion = 0, _navigationVersion = 0;
  List<List<int>> _groups = [];
  String _tabLayout = '';
  int get _lastIndex => todoStatuses.length - (widget.paged ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackScroll);
  }

  void _trackScroll() {
    if (_single || _layoutPending) return;
    final index = (_scroll.offset / _stride).round().clamp(0, _lastIndex);
    if (index != _selected) {
      setState(() => _selected = index);
      _showTab(index);
    }
  }

  void _showTab(int index, {bool animate = true}) {
    if (!widget.paged) return;
    if (!_tabs.hasClients || _groups.isEmpty) return;
    final group = _groups.indexWhere((items) => items.contains(index));
    _tabStart = group;
    final target = (group * _tabExtent).clamp(
      0.0,
      _tabs.position.maxScrollExtent,
    );
    if ((_tabs.offset - target).abs() < .5) return;
    if (animate) {
      _tabs.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _tabs.jumpTo(target);
    }
  }

  Future<void> _go(int index) async {
    final version = ++_navigationVersion;
    _boardStart = index;
    _boardGesture = false;
    _showTab(index);
    await _scroll.animateTo(
      (index * _stride).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    if (mounted && version == _navigationVersion) {
      setState(() => _selected = index);
      _showTab(index);
    }
  }

  bool _boardNotification(ScrollNotification notification) {
    if (notification.depth != 0 || !_single || _layoutPending) return false;
    if (notification is ScrollStartNotification) {
      _boardGesture = notification.dragDetails != null;
      if (_boardGesture) {
        _boardStart = (_scroll.offset / _stride).round();
        ++_navigationVersion;
      }
    }
    if (notification is ScrollEndNotification) {
      final index = (_scroll.offset / _stride).round().clamp(0, _lastIndex);
      _boardGesture = false;
      _boardStart = index;
      if (index != _selected) setState(() => _selected = index);
      _showTab(index);
    }
    return false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final single = widget.paged && constraints.maxWidth < 608;
      final viewport = constraints.maxWidth - 32;
      final width = !widget.paged
          ? viewport.clamp(280.0, 340.0)
          : single
          ? viewport
          : ((constraints.maxWidth - 48) / 2).clamp(280.0, 340.0);
      final stride = single ? width : width + 16;
      if (_single != single || _stride != stride) {
        // Ignore completion callbacks for animations targeting the old width.
        ++_navigationVersion;
        _single = single;
        _stride = stride;
        _layoutPending = true;
        final version = ++_layoutVersion;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || version != _layoutVersion) return;
          if (_scroll.hasClients) {
            _scroll.jumpTo(
              (_selected * _stride).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
          _layoutPending = false;
          _boardStart = _selected;
        });
      }
      final statuses = [
        ...todoStatuses,
        if (widget.paged) OrderStatus.delivered,
      ];
      final grouped = {
        for (final status in statuses)
          status:
              (status == OrderStatus.delivered
                      ? widget.pickedUpOrders
                      : widget.orders)
                  .where(
                    (o) =>
                        o.status == status &&
                        (status != OrderStatus.delivered ||
                            o.fulfillmentType == FulfillmentType.pickup),
                  )
                  .toList(),
      };
      final labels = [
        for (final status in statuses)
          '${tr(context, todoStatusLabel(status))} · ${grouped[status]!.length}',
      ];
      final textStyle = Theme.of(context).textTheme.labelLarge!.copyWith(
        fontFamily: PelinesTypography.bodyFamily,
        fontWeight: FontWeight.w700,
      );
      final measured = <double>[];
      for (final label in labels) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        measured.add(painter.width);
        painter.dispose();
      }
      final groups = <List<int>>[];
      final threeWidth = (viewport - 16) / 3;
      final fiveWidth = (viewport - 32) / 5;
      final slots =
          !single && measured.every((width) => width + 16 <= fiveWidth)
          ? 5
          : measured.every((width) => width + 16 <= threeWidth)
          ? 3
          : 2;
      final equalWidth = (viewport - 8 * (slots - 1)) / slots;
      final widths = List<double>.filled(statuses.length, 0);
      for (var start = 0; start < statuses.length; start += slots) {
        final end = (start + slots).clamp(0, statuses.length);
        final group = [for (var i = start; i < end; i++) i];
        groups.add(group);
        for (final index in group) {
          widths[index] = equalWidth;
        }
      }
      _groups = groups;
      if (!widget.paged) {
        groups
          ..clear()
          ..add([0, 1, 2, 3]);
      }
      _tabExtent = viewport;
      final tabLayout = '$viewport/$groups';
      if (_tabLayout != tabLayout) {
        _tabLayout = tabLayout;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTab(_selected, animate: false);
        });
      }
      final board = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: widget.paged
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                : EdgeInsets.zero,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth != 0 || !widget.paged) return false;
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _tabStart = (_tabs.offset / _tabExtent).round();
                }
                return false;
              },
              child: SingleChildScrollView(
                key: const Key('todo-tabs-scroll'),
                controller: _tabs,
                padding: widget.paged
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                physics: widget.paged
                    ? _TodoPagePhysics(
                        extent: viewport,
                        startPage: () => _tabStart,
                        parent: const ClampingScrollPhysics(),
                      )
                    : null,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in groups)
                      SizedBox(
                        width: widget.paged ? viewport : null,
                        child: Row(
                          children: [
                            for (final index in group)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: widget.paged && index == group.last
                                      ? 0
                                      : 8,
                                ),
                                child: SizedBox(
                                  width: widget.paged ? widths[index] : null,
                                  child: Semantics(
                                    selected: _selected == index,
                                    child: OutlinedButton(
                                      key: Key(
                                        'todo-tab-${statuses[index].name}',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(48, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.padded,
                                        visualDensity: VisualDensity.standard,
                                        backgroundColor: _boardColors(
                                          statuses[index],
                                        ).$2,
                                        foregroundColor: _boardColors(
                                          statuses[index],
                                        ).$1,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: widget.paged
                                              ? PelinesSpacing.xs
                                              : PelinesSpacing.lg,
                                          vertical: 6,
                                        ),
                                        shape: const StadiumBorder(),
                                        side: BorderSide(
                                          color: _selected == index
                                              ? PelinesColors.textPrimary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      onPressed: () => _go(index),
                                      onFocusChange: (focused) {
                                        if (focused) _showTab(index);
                                      },
                                      child: Text(
                                        labels[index],
                                        textAlign: TextAlign.center,
                                        style:
                                            (widget.paged
                                                    ? textStyle
                                                    : const TextStyle())
                                                .copyWith(
                                                  fontWeight: _selected == index
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                ),
                                      ),
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
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: single ? 16 : 0),
              child: NotificationListener<ScrollNotification>(
                onNotification: _boardNotification,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: !single,
                  interactive: !single,
                  child: SingleChildScrollView(
                    key: const Key('todo-board-scroll'),
                    controller: _scroll,
                    physics: single
                        ? _TodoPagePhysics(
                            extent: stride,
                            startPage: () => _boardStart,
                            userGesture: () => _boardGesture,
                            parent: const ClampingScrollPhysics(),
                          )
                        : null,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(
                      single ? 0 : 16,
                      0,
                      single ? 0 : 16,
                      16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final status in statuses)
                          Container(
                            key: Key('todo-column-${status.name}'),
                            width: width,
                            margin: EdgeInsets.only(right: single ? 0 : 16),
                            decoration: BoxDecoration(
                              color: PelinesColors.mutedSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: PelinesColors.border),
                            ),
                            child: ListView(
                              primary: false,
                              key: PageStorageKey('todo-list-${status.name}'),
                              padding: const EdgeInsets.all(12),
                              children: [
                                Semantics(
                                  header: true,
                                  child: PelinesStateBadge(
                                    key: ValueKey(
                                      'todo-column-heading-${status.name}',
                                    ),
                                    foreground: _boardColors(status).$1,
                                    background: _boardColors(status).$2,
                                    dot: true,
                                    label:
                                        '${tr(context, status == OrderStatus.pending ? 'Waiting Approval' : todoStatusLabel(status)).toUpperCase()} · ${grouped[status]!.length}',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (grouped[status]!.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      tr(context, 'No active orders'),
                                    ),
                                  ),
                                for (final order in grouped[status]!)
                                  OrderPreviewCard(
                                    key: ValueKey(order.id),
                                    order: order,
                                    statusBoard: true,
                                    showChannel: widget.showChannel,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      // Enlarged headers may leave less room than the status labels need.
      // Keep the full labels and column scroll reachable without a Flex overflow.
      return widget.paged &&
              constraints.maxHeight < PelinesLayout.touchTarget * 5
          ? SingleChildScrollView(
              primary: false,
              child: SizedBox(
                height: PelinesLayout.touchTarget * 5,
                child: board,
              ),
            )
          : board;
    },
  );
}
