import 'package:flutter/material.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public privacy policy of Pelines (the same page the customer app links to).
final Uri privacyPolicyUri = Uri.https(
  'pelinesmexicanrestaurant.com',
  '/privacy',
);

Future<void> openPrivacyPolicy(BuildContext context) async {
  var opened = false;
  try {
    opened = await launchUrl(
      privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, 'The privacy policy could not be opened.')),
      ),
    );
  }
}

class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('privacy-policy-link'),
    onPressed: () => openPrivacyPolicy(context),
    child: Text(tr(context, 'Privacy Policy')),
  );
}
