import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/printer_settings.dart';

class PrinterSettingsStore {
  PrinterSettingsStore(this.database);
  final Database database;
  Future<PrinterSettings> read(String locationId) async {
    final rows = await database.query(
      'settings',
      where: 'location_id = ?',
      whereArgs: [locationId],
    );
    return rows.isEmpty
        ? PrinterSettings(locationId: locationId)
        : PrinterSettings.fromJson(
            jsonDecode(rows.first['document'] as String)
                as Map<String, dynamic>,
          );
  }

  Future<List<PrinterSettings>> list() async =>
      (await database.query('settings'))
          .map(
            (row) => PrinterSettings.fromJson(
              jsonDecode(row['document'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<void> save(PrinterSettings settings) async {
    if (settings.locationId.isEmpty ||
        settings.printerId.isEmpty ||
        settings.scheduledLeadMinutes < 0 ||
        settings.scheduledLeadMinutes > 1440) {
      throw ArgumentError('Invalid printer settings.');
    }
    await database.transaction((tx) async {
      // One enabled location on this tablet. Other locations retain preferences.
      if (settings.enabled) {
        for (final row in await tx.query('settings')) {
          final other = PrinterSettings.fromJson(
            jsonDecode(row['document'] as String) as Map<String, dynamic>,
          );
          if (other.locationId != settings.locationId && other.enabled) {
            await tx.update(
              'settings',
              {'document': jsonEncode(other.copyWith(enabled: false).toJson())},
              where: 'location_id = ?',
              whereArgs: [other.locationId],
            );
          }
        }
      }
      await tx.insert('settings', {
        'location_id': settings.locationId,
        'document': jsonEncode(settings.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
