import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_controller.dart';

class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(localeProvider).languageCode;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(builder: (context, constraints) {
        final buttons = [for (final code in ['en', 'es'])
          Semantics(selected: language == code, label: code == 'en' ? 'English' : 'Español',
            child: TextButton(
              key: Key('language-$code'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: language == code ? Theme.of(context).colorScheme.primaryContainer : null,
                foregroundColor: language == code ? Theme.of(context).colorScheme.onPrimaryContainer : null,
              ),
              onPressed: () async {
                try {
                  await ref.read(localeProvider.notifier).select(code);
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(
                    code == 'es' ? 'No se pudo guardar el idioma en este dispositivo.' : 'Could not save the language on this device.')));
                }
              },
              child: Text(code.toUpperCase()),
            ),
          ),
        ];
        return constraints.maxWidth < 112 * MediaQuery.textScalerOf(context).scale(1)
            ? Column(mainAxisSize: MainAxisSize.min, children: buttons)
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons);
      }),
    );
  }
}
