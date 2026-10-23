import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/pelines_tokens.dart';
import 'admin_localizations.dart';
import 'locale_controller.dart';

class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({
    this.horizontalPadding = PelinesSpacing.lg,
    this.inline = false,
    this.segmentWidth,
    super.key,
  });
  final double horizontalPadding;
  final bool inline;
  final double? segmentWidth;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(localeProvider).languageCode;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: inline ? 0 : PelinesSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 160;
          final stacked =
              !inline &&
              constraints.maxWidth <
                  112 * MediaQuery.textScalerOf(context).scale(1);
          final label = tr(context, 'Language');
          final buttons = [
            for (final code in ['en', 'es'])
              Semantics(
                selected: language == code,
                label: code == 'en' ? 'English' : 'Español',
                child: TextButton(
                  key: Key('language-$code'),
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(
                      fontFamily: PelinesTypography.bodyFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    minimumSize: Size(
                      segmentWidth ?? PelinesLayout.touchTarget,
                      PelinesLayout.touchTarget,
                    ),
                    fixedSize: segmentWidth == null
                        ? null
                        : Size.fromWidth(segmentWidth!),
                    padding: const EdgeInsets.symmetric(
                      horizontal: PelinesSpacing.sm,
                    ),
                    shape: const StadiumBorder(),
                    animationDuration: const Duration(milliseconds: 180),
                    backgroundColor: language == code
                        ? PelinesColors.languageSelectedBackground
                        : Colors.transparent,
                    foregroundColor: language == code
                        ? PelinesColors.languageSelectedText
                        : PelinesColors.textPrimary,
                  ),
                  onPressed: () async {
                    try {
                      await ref.read(localeProvider.notifier).select(code);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            code == 'es'
                                ? 'No se pudo guardar el idioma en este dispositivo.'
                                : 'Could not save the language on this device.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(code.toUpperCase()),
                ),
              ),
          ];
          final pill = Container(
            key: const Key('language-pill'),
            padding: EdgeInsets.all(inline ? 2 : PelinesSpacing.xxs),
            decoration: BoxDecoration(
              color: PelinesColors.mutedSurface,
              borderRadius: BorderRadius.circular(PelinesRadius.pill),
            ),
            child: stacked
                ? Column(mainAxisSize: MainAxisSize.min, children: buttons)
                : Row(mainAxisSize: MainAxisSize.min, children: buttons),
          );
          if (inline) return Tooltip(message: label, child: pill);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Tooltip(
                    message: label,
                    child: Icon(
                      Icons.language,
                      color: PelinesColors.brandPrimary,
                      semanticLabel: compact ? label : null,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: PelinesSpacing.sm),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: PelinesSpacing.xs),
              Padding(
                padding: EdgeInsets.only(
                  left: compact || stacked ? 0 : 24 + PelinesSpacing.sm,
                ),
                child: pill,
              ),
            ],
          );
        },
      ),
    );
  }
}
