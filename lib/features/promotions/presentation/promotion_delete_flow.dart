import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../models/discount.dart';
import '../../locations/models/location.dart';
import '../providers/promotions_providers.dart';

/// Shared confirmation and controller flow; callers guard repeat dialogs.
Future<bool> deletePromotionWithConfirmation({
  required BuildContext context,
  required WidgetRef ref,
  required Discount discount,
  required Location location,
  DateTime? originalUpdatedAt,
}) async {
  if (ref.read(promotionMutationProvider).isBusy ||
      (discount.locationId != null && discount.locationId != location.id)) {
    return false;
  }
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            tr(
              context,
              discount.locationId == null
                  ? 'Delete global promotion'
                  : 'Delete discount code?',
            ),
          ),
          content: Text(
            '${discount.code}\n\n${tr(context, discount.locationId == null ? 'This promotion will no longer be available for future use at all locations. This action cannot be undone.' : 'Customers will no longer be able to use this discount code.')}',
          ),
          actions: [
            TextButton(
              key: const Key('promotion-delete-cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(context, 'Cancel')),
            ),
            FilledButton(
              key: const Key('promotion-delete-confirm'),
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(context, 'Delete')),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;
  await ref
      .read(promotionMutationProvider.notifier)
      .delete(
        discountId: discount.id,
        locationId: location.id,
        originalUpdatedAt: originalUpdatedAt ?? discount.updatedAt,
        global: discount.locationId == null,
      );
  if (!context.mounted) return false;
  final result = ref.read(promotionMutationProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        tr(
          context,
          result.message ??
              (result.phase == PromotionMutationPhase.success
                  ? 'Promotion deleted.'
                  : 'The promotion could not be deleted.'),
        ),
      ),
    ),
  );
  return result.phase == PromotionMutationPhase.success;
}
