import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
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
  bool _choosing = false;
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

  Future<void> export() async {
    if (_busy || _choosing) return;
    setState(() {
      _choosing = true;
      _error = null;
    });
    try {
      final report = await showModalBottomSheet<AnalyticsReport>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'Export / Reports'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final report in AnalyticsReport.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      key: Key('analytics-export-${report.name}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => Navigator.pop(context, report),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          tr(
                            context,
                            report == AnalyticsReport.revenue
                                ? 'Revenue Report'
                                : 'Operational Report',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (report == null || !mounted) return;
      setState(() {
        _choosing = false;
        _busy = true;
      });
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
          _choosing = false;
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('analytics-export'),
              style: PelinesControlStyles.button(PelinesButtonVariant.primary),
              onPressed: _busy || _choosing || blocked != null ? null : export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(
                tr(context, _busy ? 'Preparing export…' : 'Export / Reports'),
              ),
            ),
            if (widget.secondaryAction != null) widget.secondaryAction!,
          ],
        ),
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
}
