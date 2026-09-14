import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog.dart';

/// One catalog for app-owned UI text. Never apply this to customer/product data.
class AdminLocalizations {
  const AdminLocalizations(this.locale);
  final Locale locale;
  static const delegate = _AdminLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('es')];
  static AdminLocalizations of(BuildContext context) =>
      Localizations.of<AdminLocalizations>(context, AdminLocalizations) ??
      const AdminLocalizations(Locale('en'));

  String text(String source, {String? key}) {
    if (locale.languageCode != 'es') return source;
    return spanishCatalog[key] ?? spanishCatalog[source] ?? source;
  }
}

String tr(BuildContext context, String source) =>
    AdminLocalizations.of(context).text(source);

class _AdminLocalizationsDelegate
    extends LocalizationsDelegate<AdminLocalizations> {
  const _AdminLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['en', 'es'].contains(locale.languageCode);
  @override
  Future<AdminLocalizations> load(Locale locale) =>
      SynchronousFuture(AdminLocalizations(locale));
  @override
  bool shouldReload(_AdminLocalizationsDelegate old) => false;
}
