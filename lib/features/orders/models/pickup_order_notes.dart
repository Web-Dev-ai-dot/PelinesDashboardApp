import 'order_models.dart';

/// Web checkout contract verified on staging, 2026-10-02:
/// [isCatering ? '' : `Included items (forks, napkins, etc.): ${include ? 'yes' : 'no'}`,
///  customerNote.trim()].filter(Boolean).join('\n').
/// See docs/ticket4-pickup-notes-contract.md for producer evidence and limits.
/// Only the first, exact generated line is consumed; customer text is untouched.
class PickupOrderNotes {
  const PickupOrderNotes({this.includeUtensils, this.customerNotes});

  final bool? includeUtensils;
  final String? customerNotes;

  factory PickupOrderNotes.fromOrder(OrderDetail order) {
    final notes = order.notes;
    if (notes == null ||
        order.source != 'web' ||
        order.orderType != OrderType.online ||
        order.fulfillmentType != FulfillmentType.pickup) {
      return PickupOrderNotes(customerNotes: notes);
    }
    final newline = notes.indexOf('\n');
    final firstLine = newline < 0 ? notes : notes.substring(0, newline);
    final bool? utensils = switch (firstLine) {
      'Included items (forks, napkins, etc.): yes' => true,
      'Included items (forks, napkins, etc.): no' => false,
      _ => null,
    };
    return PickupOrderNotes(
      includeUtensils: utensils,
      customerNotes: utensils == null
          ? notes
          : newline < 0
          ? null
          : notes.substring(newline + 1),
    );
  }
}
