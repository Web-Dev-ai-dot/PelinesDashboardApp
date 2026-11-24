import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/time/pelines_time.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';
import '../models/refund_amount.dart';
import '../providers/orders_providers.dart';
import 'order_parity_content.dart';
import 'order_ui_helpers.dart';

const int refundNoteMaxLength = 500;

/// U+2212 minus, matching the web dashboard's "−$5.00".
String refundedMoney(int cents) => '−${money(cents)}';

String refundReasonLabel(String reason) => switch (reason) {
  'requested_by_customer' => 'Requested by customer',
  'duplicate' => 'Duplicate',
  'fraudulent' => 'Fraudulent',
  'other' => 'Other',
  'order_cancelled' => 'Order cancelled',
  _ => reason,
};

/// Keyed lookup: plain "Duplicate" already means the verb elsewhere.
String _trReason(BuildContext context, String reason) {
  final String label = refundReasonLabel(reason);
  return AdminLocalizations.of(context)
      .text(label, key: 'Refund reason: $label');
}

/// Refund summary, "Issue Refund" action and history for the order detail
/// payment block. Renders nothing for orders that were never refundable.
class OrderRefundSection extends ConsumerWidget {
  const OrderRefundSection({
    required this.order,
    this.enabled = true,
    super.key,
  });

  final OrderDetail order;

  /// False while the order is read-only (location changed) or busy.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!order.supportsRefunds) return const SizedBox.shrink();
    final List<OrderRefund> history = newestRefundsFirst(order.refunds);
    final bool canRefund = order.canIssueRefund;
    final int refunded = order.refundedCents;
    if (!canRefund && history.isEmpty && refunded <= 0) {
      return const SizedBox.shrink();
    }
    final bool fully = order.isFullyRefunded;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      key: const Key('refund-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (refunded > 0) ...<Widget>[
          const SizedBox(height: PelinesSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PelinesStateBadge(
              key: const Key('refund-badge'),
              label: tr(
                context,
                fully ? 'Fully Refunded' : 'Partially Refunded',
              ),
              foreground: fully
                  ? PelinesColors.destructive
                  : PelinesColors.amberForeground,
              background: fully
                  ? PelinesColors.brandPrimarySoft
                  : PelinesColors.brandYellowSoft,
            ),
          ),
          const SizedBox(height: PelinesSpacing.xs),
          OrderInlineValueRow(
            key: const Key('refund-refunded'),
            label: Text(tr(context, 'Refunded')),
            value: Text(
              refundedMoney(refunded),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: PelinesColors.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!fully)
            Padding(
              padding: const EdgeInsets.only(top: PelinesSpacing.xxs),
              child: OrderInlineValueRow(
                key: const Key('refund-remaining'),
                label: Text(tr(context, 'Remaining refundable')),
                value: Text(
                  money(order.refundableCents ?? 0),
                  textAlign: TextAlign.end,
                ),
              ),
            ),
        ],
        if (canRefund) ...<Widget>[
          const SizedBox(height: PelinesSpacing.md),
          OutlinedButton.icon(
            key: const Key('refund-issue'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, PelinesLayout.touchTarget),
              foregroundColor: PelinesColors.destructive,
              side: const BorderSide(color: PelinesColors.destructive),
              shape: const StadiumBorder(),
            ),
            onPressed: enabled ? () => _openSheet(context) : null,
            icon: const Icon(Icons.replay, size: 18),
            label: Text(
              tr(
                context,
                refunded > 0 ? 'Issue Another Refund' : 'Issue Refund',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (history.isNotEmpty) ...<Widget>[
          const SizedBox(height: PelinesSpacing.lg),
          Text(
            tr(context, 'Refund history').toUpperCase(),
            style: PelinesTypography.smallLabel,
          ),
          const SizedBox(height: PelinesSpacing.xxs),
          for (int i = 0; i < history.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1),
            _RefundHistoryRow(refund: history[i], textTheme: text),
          ],
        ],
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final String template = tr(context, 'Refunded {amount}');
    final int? refundedCents = await showRefundSheet(context, order);
    if (refundedCents == null) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(template.replaceAll('{amount}', money(refundedCents))),
        ),
      );
  }
}

/// Newest first; entries without a date keep the API's (oldest-first) order
/// reversed.
List<OrderRefund> newestRefundsFirst(List<OrderRefund> refunds) {
  final List<(int, OrderRefund)> indexed = <(int, OrderRefund)>[
    for (int i = 0; i < refunds.length; i++) (i, refunds[i]),
  ];
  indexed.sort(((int, OrderRefund) a, (int, OrderRefund) b) {
    final DateTime? aAt = a.$2.createdAt;
    final DateTime? bAt = b.$2.createdAt;
    if (aAt != null && bAt != null) {
      final int byDate = bAt.compareTo(aAt);
      if (byDate != 0) return byDate;
    }
    return b.$1.compareTo(a.$1);
  });
  return <OrderRefund>[
    for (final (int, OrderRefund) entry in indexed) entry.$2,
  ];
}

class _RefundHistoryRow extends StatelessWidget {
  const _RefundHistoryRow({required this.refund, required this.textTheme});

  final OrderRefund refund;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final bool counted = refund.status.returnedMoney;
    final String? chip = switch (refund.status) {
      RefundStatus.failed => 'Failed',
      RefundStatus.canceled => 'Canceled',
      RefundStatus.pending || RefundStatus.requiresAction => 'Pending',
      _ => null,
    };
    final DateTime? createdAt = refund.createdAt;
    final String details = <String>[
      if (createdAt != null)
        DateFormat('MMM d, yyyy').format(PelinesTime.inPacific(createdAt)),
      _trReason(context, refund.reason),
      if (refund.viaStripe) tr(context, 'via Stripe'),
    ].join(' • ');
    final String? note = refund.note?.trim();
    return Padding(
      key: Key('refund-row-${refund.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: PelinesSpacing.xs,
            runSpacing: PelinesSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                refundedMoney(refund.amountCents),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: counted
                      ? PelinesColors.textPrimary
                      : PelinesColors.textSecondary,
                  decoration: counted ? null : TextDecoration.lineThrough,
                ),
              ),
              Text(
                '• $details',
                style: const TextStyle(color: PelinesColors.textSecondary),
              ),
              if (chip != null)
                PelinesStateBadge(
                  key: Key('refund-chip-${refund.id}'),
                  label: tr(context, chip),
                  foreground: chip == 'Pending'
                      ? PelinesColors.amberForeground
                      : PelinesColors.destructive,
                  background: chip == 'Pending'
                      ? PelinesColors.brandYellowSoft
                      : PelinesColors.brandPrimarySoft,
                ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...<Widget>[
            const SizedBox(height: PelinesSpacing.xxs),
            Text(
              '“$note”',
              style: textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: PelinesColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the refund form. Resolves to the refunded cents on success (the
/// order caches are already refreshed), or null when closed without refunding.
Future<int?> showRefundSheet(BuildContext context, OrderDetail order) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Dragging pops without consulting PopScope; the barrier and back button
    // do, so they are blocked while a refund is in flight.
    enableDrag: false,
    backgroundColor: PelinesColors.card,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => RefundSheet(order: order),
  );
}

enum _RefundMode { full, partial }

class RefundSheet extends ConsumerStatefulWidget {
  const RefundSheet({required this.order, super.key});

  final OrderDetail order;

  @override
  ConsumerState<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<RefundSheet> {
  // One key per opened sheet: a double-tap or retry of this form can never
  // refund twice, while a new sheet (a genuinely new refund) gets a new key.
  late final String _idempotencyKey = newIdempotencyKey();
  late final TextEditingController _amount = TextEditingController(
    text: centsToDollarInput(widget.order.refundableCents ?? 0),
  );
  final TextEditingController _note = TextEditingController();
  _RefundMode _mode = _RefundMode.full;
  RefundReason _reason = RefundReason.requestedByCustomer;
  bool _submitting = false;
  String? _error;

  int get _refundable => widget.order.refundableCents ?? 0;

  int? get _cents => _mode == _RefundMode.full
      ? _refundable
      : parseDollarsToCents(_amount.text);

  String? _amountError(BuildContext context) {
    final int? cents = _cents;
    if (cents == null) return tr(context, 'Enter an amount like 12.50');
    if (cents < 1) return tr(context, r'Amount must be at least $0.01');
    if (cents > _refundable) {
      return tr(
        context,
        'Max refundable is {amount}',
      ).replaceAll('{amount}', money(_refundable));
    }
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Synchronous guard: a second tap before the rebuild must not resubmit.
    if (_submitting) return;
    final int? cents = _cents;
    if (cents == null ||
        _amountError(context) != null ||
        _note.text.length > refundNoteMaxLength) {
      return;
    }
    final OrderRefundsRepository? repository = ref.read(
      orderRefundsRepositoryProvider,
    );
    if (repository == null) {
      setState(() => _error = tr(context, 'Refunds are not available.'));
      return;
    }
    _submitting = true;
    setState(() => _error = null);
    final String orderId = widget.order.id;
    try {
      final OrderDetail updated = await repository.issueRefund(
        orderId: orderId,
        amountCents: cents,
        reason: _reason,
        idempotencyKey: _idempotencyKey,
        note: _note.text,
      );
      if (!mounted) return;
      ref
          .read(orderMutationProvider(orderId).notifier)
          .adoptRefreshedOrder(updated);
      invalidateOrderAfterRefund(ref, orderId);
      Navigator.of(context).pop(cents);
    } on ApiException catch (error) {
      if (!mounted) return;
      // Unlock the sheet first: sign-out must never leave it undismissable.
      setState(() {
        _submitting = false;
        _error = error.message;
      });
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = tr(context, 'Refund failed. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrderDetail order = widget.order;
    final int? cents = _cents;
    final String? amountError = _amountError(context);
    final bool noteTooLong = _note.text.length > refundNoteMaxLength;
    final bool valid = amountError == null && !noteTooLong;
    final bool partial = _mode == _RefundMode.partial;
    final String? brand = order.cardBrand?.trim();
    final String? last4 = order.cardLast4?.trim();
    final String subtitle = <String>[
      tr(context, 'Order {number}').replaceAll('{number}', order.orderNumber),
      if (brand != null &&
          brand.isNotEmpty &&
          last4 != null &&
          last4.isNotEmpty)
        '${brand[0].toUpperCase()}${brand.substring(1)} •••• $last4',
    ].join(' · ');
    final String submitLabel = _submitting
        ? tr(context, 'Processing…')
        : valid && cents != null
        ? tr(
            context,
            'Process Refund ({amount})',
          ).replaceAll('{amount}', money(cents))
        : tr(context, 'Process Refund');

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          key: const Key('refund-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                tr(context, 'Refund Payment'),
                style: PelinesTypography.sectionTitle(
                  Theme.of(context).textTheme,
                )?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: PelinesSpacing.xxs),
              Text(
                subtitle,
                key: const Key('refund-subtitle'),
                style: const TextStyle(color: PelinesColors.textSecondary),
              ),
              const SizedBox(height: PelinesSpacing.lg),
              SegmentedButton<_RefundMode>(
                key: const Key('refund-mode'),
                showSelectedIcon: false,
                segments: <ButtonSegment<_RefundMode>>[
                  ButtonSegment<_RefundMode>(
                    value: _RefundMode.full,
                    label: Text(
                      tr(context, 'Full refund'),
                      key: const Key('refund-mode-full'),
                    ),
                  ),
                  ButtonSegment<_RefundMode>(
                    value: _RefundMode.partial,
                    label: Text(
                      tr(context, 'Partial refund'),
                      key: const Key('refund-mode-partial'),
                    ),
                  ),
                ],
                selected: <_RefundMode>{_mode},
                onSelectionChanged: _submitting
                    ? null
                    : (Set<_RefundMode> selection) => setState(() {
                        _mode = selection.first;
                        _error = null;
                        if (_mode == _RefundMode.full) {
                          _amount.text = centsToDollarInput(_refundable);
                        }
                      }),
              ),
              const SizedBox(height: PelinesSpacing.lg),
              _FieldLabel(tr(context, 'Amount')),
              TextField(
                key: const Key('refund-amount'),
                controller: _amount,
                enabled: partial && !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.$ ]')),
                ],
                autocorrect: false,
                onChanged: (_) => setState(() => _error = null),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                decoration: PelinesControlStyles.input().copyWith(
                  prefixText: r'$ ',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                partial && amountError != null
                    ? amountError
                    : tr(
                        context,
                        'Remaining refundable: {amount}',
                      ).replaceAll('{amount}', money(_refundable)),
                key: const Key('refund-amount-hint'),
                style: TextStyle(
                  fontSize: 13,
                  color: partial && amountError != null
                      ? PelinesColors.destructive
                      : PelinesColors.textSecondary,
                ),
              ),
              const SizedBox(height: PelinesSpacing.lg),
              _FieldLabel(tr(context, 'Reason')),
              DropdownButtonFormField<RefundReason>(
                key: const Key('refund-reason'),
                initialValue: _reason,
                isExpanded: true,
                decoration: PelinesControlStyles.input(),
                items: <DropdownMenuItem<RefundReason>>[
                  for (final RefundReason reason in RefundReason.values)
                    DropdownMenuItem<RefundReason>(
                      value: reason,
                      child: Text(
                        _trReason(context, reason.wireValue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (RefundReason? value) {
                        if (value != null) setState(() => _reason = value);
                      },
              ),
              if (_reason == RefundReason.fraudulent) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    'Stripe will also block this card from future payments.',
                  ),
                  key: const Key('refund-fraud-hint'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: PelinesColors.amberForeground,
                  ),
                ),
              ],
              const SizedBox(height: PelinesSpacing.lg),
              _FieldLabel(tr(context, 'Note (optional, staff only)')),
              TextField(
                key: const Key('refund-note'),
                controller: _note,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 5,
                maxLength: refundNoteMaxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: PelinesControlStyles.input(
                  hint: tr(context, 'e.g. Missing salsa on the order'),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: PelinesSpacing.sm),
                Container(
                  key: const Key('refund-error'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PelinesSpacing.md,
                    vertical: PelinesSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: PelinesColors.brandPrimarySoft,
                    borderRadius: BorderRadius.circular(PelinesRadius.card),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: PelinesColors.destructive),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: PelinesSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: PelinesSpacing.xs,
                runSpacing: PelinesSpacing.xs,
                children: <Widget>[
                  OutlinedButton(
                    key: const Key('refund-cancel'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, PelinesLayout.touchTarget),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: Text(tr(context, 'Cancel')),
                  ),
                  FilledButton(
                    key: const Key('refund-submit'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, PelinesLayout.touchTarget),
                      backgroundColor: PelinesColors.destructive,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: valid && !_submitting ? _submit : null,
                    child: PelinesButtonLabel(
                      busy: _submitting,
                      label: submitLabel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text.toUpperCase(), style: PelinesTypography.smallLabel),
  );
}
