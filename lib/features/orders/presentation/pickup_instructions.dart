import 'package:flutter/widgets.dart';

import '../../../app/l10n/admin_localizations.dart';

/// Mirrors the customer checkout's generated arrival guidance, not Order.notes.
/// The location name comes from OrderDetail.location; no per-location lookup or
/// stored per-order instructions exist. See docs/ticket4-pickup-notes-contract.md.
String pickupInstructions(BuildContext context, String? locationName) {
  final name = locationName?.trim();
  return tr(
    context,
    'Arrive at {location} at your pickup time, head to the front counter, and let the team know you are picking up an online order.',
  ).replaceAll('{location}', name == null || name.isEmpty ? 'Pelines' : name);
}
