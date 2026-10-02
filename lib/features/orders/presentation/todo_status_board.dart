import 'package:flutter/material.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_order_badges.dart';
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
  _ => '',
};

/// One loaded Today snapshot, four persistent columns. Tabs only scroll.
class TodoStatusBoard extends StatefulWidget {
  const TodoStatusBoard({required this.orders, super.key});
  final List<OrderSummary> orders;

  @override
  State<TodoStatusBoard> createState() => _TodoStatusBoardState();
}

class _TodoStatusBoardState extends State<TodoStatusBoard> {
  final _scroll = ScrollController();
  int _selected = 0;
  double _stride = 332;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackScroll);
  }

  void _trackScroll() {
    final index = (_scroll.offset / _stride).round().clamp(0, 3);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 32).clamp(280.0, 340.0);
      _stride = width + 16;
      final grouped = {
        for (final status in todoStatuses)
          status: widget.orders.where((o) => o.status == status).toList(),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final (index, status) in todoStatuses.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Semantics(
                      selected: _selected == index,
                      child: OutlinedButton(
                        key: Key('todo-tab-${status.name}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          side: BorderSide(
                            color: _selected == index
                                ? PelinesColors.textPrimary
                                : PelinesColors.border,
                            width: _selected == index ? 2 : 1,
                          ),
                        ),
                        onPressed: () async {
                          await _scroll.animateTo(
                            (index * _stride).clamp(
                              0,
                              _scroll.position.maxScrollExtent,
                            ),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                          if (mounted) setState(() => _selected = index);
                        },
                        child: PelinesOrderBadges.status(
                          status: status,
                          label:
                              '${tr(context, todoStatusLabel(status))} · ${grouped[status]!.length}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              interactive: true,
              child: SingleChildScrollView(
                key: const Key('todo-board-scroll'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final status in todoStatuses)
                      Container(
                        key: Key('todo-column-${status.name}'),
                        width: width,
                        margin: const EdgeInsets.only(right: 16),
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
                              child: PelinesOrderBadges.status(
                                status: status,
                                label:
                                    '${tr(context, status == OrderStatus.pending ? 'Waiting Approval' : todoStatusLabel(status)).toUpperCase()} · ${grouped[status]!.length}',
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (grouped[status]!.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(tr(context, 'No active orders')),
                              ),
                            for (final order in grouped[status]!)
                              OrderPreviewCard(
                                key: ValueKey(order.id),
                                order: order,
                                statusBoard: true,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
