import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../../../app/theme/pelines_components.dart';
import '../../locations/providers/locations_providers.dart';
import '../application/analytics_export.dart';
import '../application/analytics_visualization_data.dart';
import '../providers/analytics_providers.dart';

final analyticsShareProvider =
    Provider<Future<ShareResult> Function(ShareParams)>(
      (ref) => SharePlus.instance.share,
    );

/// Async boundary for generation errors and scope changes before native sharing.
final analyticsCsvGenerationProvider =
    Provider<Future<AnalyticsCsv> Function(AnalyticsCsv Function())>(
      (ref) =>
          (build) => Future<AnalyticsCsv>(build),
    );

class AnalyticsExportAction extends ConsumerStatefulWidget {
  const AnalyticsExportAction({this.secondaryAction, super.key});
  final Widget? secondaryAction;
  @override
  ConsumerState<AnalyticsExportAction> createState() =>
      _AnalyticsExportActionState();
}

class _AnalyticsExportActionState extends ConsumerState<AnalyticsExportAction> {
  bool _busy = false;
  String? _error;

  String? unavailable() {
    final data = ref.read(analyticsDatasetProvider);
    final result = ref.read(analyticsResultProvider);
    final location = ref.read(currentLocationProvider);
    if (data.hasError ||
        result.hasError ||
        data.value?.refreshError != null ||
        location.hasError) {
      return 'Export unavailable. Refresh Analytics and try again.';
    }
    if (data.isLoading ||
        result.isLoading ||
        location.isLoading ||
        data.value?.isRefreshing == true) {
      return 'Loading Analytics…';
    }
    final dataset = data.value?.dataset;
    if (dataset == null ||
        result.value == null ||
        location.value == null ||
        dataset.locationId != location.value!.id) {
      return 'Export unavailable. Refresh Analytics and try again.';
    }
    if (!analyticsRangeIsCovered(dataset, result.value!.current.range)) {
      return 'Export unavailable: the selected period has incomplete coverage.';
    }
    return null;
  }

  Future<void> export(AnalyticsReport report) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final blocked = unavailable();
      if (blocked != null) {
        setState(() => _error = blocked);
        return;
      }
      final dataset = ref.read(analyticsDatasetProvider).value!.dataset;
      final result = ref.read(analyticsResultProvider).value!;
      final location = ref.read(currentLocationProvider).value!;
      final csv = await ref.read(analyticsCsvGenerationProvider)(
        () => buildAnalyticsCsv(
          report: report,
          dataset: dataset,
          result: result,
          locationId: location.id,
          locationName: location.name,
          locationSlug: location.slug,
        ),
      );
      if (!mounted) return;
      if (unavailable() != null ||
          !identical(
            dataset,
            ref.read(analyticsDatasetProvider).value?.dataset,
          ) ||
          !identical(result, ref.read(analyticsResultProvider).value) ||
          location.id != ref.read(currentLocationProvider).value?.id) {
        setState(() => _error = 'Analytics changed. Please export again.');
        return;
      }
      final box = context.findRenderObject() as RenderBox;
      await ref.read(analyticsShareProvider)(
        ShareParams(
          files: [XFile.fromData(csv.bytes, mimeType: 'text/csv')],
          fileNameOverrides: [csv.filename],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      // Dismissed/unavailable are not failures. Never claim a file was saved:
      // the destination app controls that outcome.
    } catch (_) {
      if (mounted) setState(() => _error = 'Export failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(analyticsDatasetProvider);
    ref.watch(analyticsResultProvider);
    ref.watch(currentLocationProvider);
    final blocked = unavailable();
    return Column(
      key: const Key('analytics-export'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PelinesSectionHeading(tr(context, 'Export / Reports')),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            'Download data for the selected location and date range.',
          ),
        ),
        const SizedBox(height: 16),
        _button(
          'orders',
          'Export Orders CSV',
          Icons.inventory_2_outlined,
          null,
        ),
        _button(
          'revenue',
          'Export Revenue CSV',
          Icons.attach_money,
          _busy || blocked != null
              ? null
              : () => export(AnalyticsReport.revenue),
        ),
        _button(
          'operational',
          'Export Operational Report CSV',
          Icons.cancel_outlined,
          _busy || blocked != null
              ? null
              : () => export(AnalyticsReport.operational),
        ),
        if (_busy) ...[
          const LinearProgressIndicator(),
          Text(tr(context, 'Preparing export…')),
        ],
        Text(tr(context, 'Orders CSV export is not available in this app.')),
        const SizedBox(height: 12),
        Text(
          tr(context, 'Exports respect the selected location and date range.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.secondaryAction != null) widget.secondaryAction!,
        if (_error ?? blocked case final String message)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(tr(context, message)),
            ),
          ),
      ],
    );
  }

  Widget _button(
    String name,
    String label,
    IconData icon,
    VoidCallback? onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton(
      key: Key('analytics-export-$name'),
      style: OutlinedButton.styleFrom(
        backgroundColor: PelinesColors.card,
        foregroundColor: PelinesColors.textPrimary,
        side: const BorderSide(color: PelinesColors.border),
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.pageCard),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, color: PelinesColors.brandPrimary),
          const SizedBox(width: 12),
          Expanded(child: Text(tr(context, label))),
          const SizedBox(width: 12),
          const Icon(
            Icons.download_outlined,
            color: PelinesColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}
