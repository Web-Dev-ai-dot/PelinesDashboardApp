import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_components.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../providers/modifier_providers.dart';
import '../providers/catering_actions.dart';
import 'modifier_form_screen.dart';
import 'menu_screens.dart';

/// Same per-entity saves as the standalone editors; never joins product Save.
class CateringInlineAddons extends ConsumerStatefulWidget {
  const CateringInlineAddons({
    required this.contextKey,
    required this.onStateChanged,
    this.productBusy = false,
    super.key,
  });
  final ModifierContext contextKey;
  final void Function(bool dirty, bool busy) onStateChanged;
  final bool productBusy;
  @override
  ConsumerState<CateringInlineAddons> createState() => _InlineState();
}

class _InlineState extends ConsumerState<CateringInlineAddons> {
  final Map<String, (bool, bool)> states = {};
  final Map<String, int> revisions = {};
  final Set<String> newOptions = {};
  bool newGroup = false;
  (bool, bool) lastReport = (false, false);
  void report(String id, bool dirty, bool busy) {
    if (!mounted) return;
    states[id] = (dirty, busy);
    final next = (
      states.values.any((v) => v.$1),
      states.values.any((v) => v.$2),
    );
    if (next != lastReport) {
      lastReport = next;
      widget.onStateChanged(next.$1, next.$2);
    }
  }

  void reset(String id) {
    setState(() {
      revisions.update(id, (v) => v + 1, ifAbsent: () => 1);
    });
    report(id, false, false);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.contextKey;
    final mutation = ref.watch(modifierMutationProvider(key));
    final groups = ref.watch(modifierGroupsProvider(key));
    final query = (
      locationId: key.locationId,
      locationSlug: key.locationSlug,
      kind: key.kind,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, 'Add-ons')),
        Text(
          tr(
            context,
            'Add-on saves are independent. Cancel or Close does not undo saved add-ons.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (mutation.message != null)
          Semantics(
            liveRegion: true,
            child: Text(tr(context, mutation.message!)),
          ),
        const SizedBox(height: 12),
        if (groups.hasError)
          Text(
            tr(
              context,
              'Add-ons could not be refreshed. Existing drafts are retained.',
            ),
          ),
        // Product writes and independent add-on writes cannot overlap.
        AbsorbPointer(
          absorbing:
              widget.productBusy ||
              mutation.isBusy ||
              states.entries.any(
                (e) => e.key.startsWith('delete-') && e.value.$2,
              ),
          child: groups.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Column(
              children: [
                Text(e.toString()),
                TextButton(
                  onPressed: () => ref.invalidate(modifierGroupsProvider(key)),
                  child: Text(tr(context, 'Try again')),
                ),
              ],
            ),
            data: (values) {
              // Drop deleted entities only. Other entity drafts retain their keys.
              final live = <String>{
                for (final g in values) ...[
                  'group-${g.id}',
                  'delete-${g.id}',
                  for (final o in g.options) ...[
                    'option-${o.id}',
                    'delete-${o.id}',
                  ],
                ],
                'new-group',
                for (final g in newOptions)
                  if (values.any((v) => v.id == g)) 'new-option-$g',
              };
              final removed = states.keys
                  .where((id) => !live.contains(id))
                  .toList();
              if (removed.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  for (final id in removed) {
                    report(id, false, false);
                  }
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: PelinesCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ModifierGroupForm(
                              key: ValueKey(
                                'group-${group.id}-${revisions['group-${group.id}'] ?? 0}',
                              ),
                              contextKey: key,
                              initial: group,
                              trailing: CateringDeleteButton(
                                compact: true,
                                query: query,
                                categoryId: key.categoryId,
                                productId: key.productId,
                                entity: CateringEntity.group,
                                id: group.id,
                                name: group.name,
                                onBusyChanged: (b) =>
                                    report('delete-${group.id}', false, b),
                                onSettled: () =>
                                    ref.invalidate(modifierGroupsProvider(key)),
                              ),
                              inline: true,
                              onStateChanged: (d, b) =>
                                  report('group-${group.id}', d, b),
                              onSaved: () =>
                                  report('group-${group.id}', false, false),
                              onCancel: () => reset('group-${group.id}'),
                            ),
                            if (group.options.isNotEmpty ||
                                newOptions.contains(group.id))
                              const SizedBox(height: PelinesSpacing.md),

                            for (final option in group.options) ...[
                              ModifierOptionForm(
                                key: ValueKey(
                                  'option-${option.id}-${revisions['option-${option.id}'] ?? 0}',
                                ),
                                contextKey: key,
                                group: group,
                                initial: option,
                                inline: true,
                                trailing: CateringDeleteButton(
                                  compact: true,
                                  query: query,
                                  categoryId: key.categoryId,
                                  productId: key.productId,
                                  groupId: group.id,
                                  entity: CateringEntity.option,
                                  id: option.id,
                                  name: option.name,
                                  onBusyChanged: (b) =>
                                      report('delete-${option.id}', false, b),
                                  onSettled: () => ref.invalidate(
                                    modifierGroupsProvider(key),
                                  ),
                                ),
                                onStateChanged: (d, b) =>
                                    report('option-${option.id}', d, b),
                                onSaved: () =>
                                    report('option-${option.id}', false, false),
                                onCancel: () => reset('option-${option.id}'),
                              ),
                              const SizedBox(height: PelinesSpacing.md),
                            ],
                            if (newOptions.contains(group.id)) ...[
                              ModifierOptionForm(
                                key: ValueKey(
                                  'new-option-${group.id}-${revisions['new-option-${group.id}'] ?? 0}',
                                ),
                                contextKey: key,
                                group: group,
                                inline: true,
                                onStateChanged: (d, b) =>
                                    report('new-option-${group.id}', d, b),
                                onSaved: () {
                                  setState(() => newOptions.remove(group.id));
                                  reset('new-option-${group.id}');
                                },
                                onCancel: () {
                                  setState(() => newOptions.remove(group.id));
                                  reset('new-option-${group.id}');
                                },
                              ),
                              const SizedBox(height: PelinesSpacing.md),
                            ],
                            OutlinedButton.icon(
                              onPressed:
                                  mutation.isBusy ||
                                      newOptions.contains(group.id)
                                  ? null
                                  : () => setState(
                                      () => newOptions.add(group.id),
                                    ),
                              icon: const Icon(Icons.add),
                              label: Text(tr(context, 'Add option')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (newGroup)
                    ModifierGroupForm(
                      key: ValueKey('new-group-${revisions['new-group'] ?? 0}'),
                      contextKey: key,
                      inline: true,
                      onStateChanged: (d, b) => report('new-group', d, b),
                      onSaved: () {
                        setState(() => newGroup = false);
                        reset('new-group');
                      },
                      onCancel: () {
                        setState(() => newGroup = false);
                        reset('new-group');
                      },
                    ),
                  OutlinedButton.icon(
                    onPressed: mutation.isBusy || newGroup
                        ? null
                        : () => setState(() => newGroup = true),
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, 'Add add-on group')),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
