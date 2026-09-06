import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StoredOrderAlerts {
  const StoredOrderAlerts({required this.knownIds, required this.unseenIds});

  final List<String> knownIds;
  final List<String> unseenIds;
}

abstract interface class OrderAlertStore {
  Future<StoredOrderAlerts?> read(String locationId);
  Future<void> write(String locationId, StoredOrderAlerts alerts);
}

class SharedPreferencesOrderAlertStore implements OrderAlertStore {
  static const String _prefix = 'pelines.order_alerts.';

  @override
  Future<StoredOrderAlerts?> read(String locationId) async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? raw = preferences.getString('$_prefix$locationId');
      if (raw == null) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final Object? known = decoded['known'];
      final Object? unseen = decoded['unseen'];
      if (known is! List<dynamic> || unseen is! List<dynamic>) return null;
      if (known.any((Object? id) => id is! String) ||
          unseen.any((Object? id) => id is! String)) {
        return null;
      }
      return StoredOrderAlerts(
        knownIds: known.cast<String>(),
        unseenIds: unseen.cast<String>(),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String locationId, StoredOrderAlerts alerts) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix$locationId',
      jsonEncode(<String, Object>{
        'known': alerts.knownIds,
        'unseen': alerts.unseenIds,
      }),
    );
  }
}
