import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/print_job.dart';

class PrintJobStore {
  PrintJobStore(this.database);
  final Database database;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  PrintJob _read(Map<String, Object?> row) => PrintJob.fromJson(
    jsonDecode(row['document'] as String) as Map<String, dynamic>,
  );
  Map<String, Object?> _row(PrintJob job) => {
    'id': job.id,
    'location_id': job.locationId,
    'order_id': job.orderId,
    'purpose': job.purpose.name,
    'status': job.status.name,
    'printer_id': job.printerId,
    'created_at': job.createdAt.toIso8601String(),
    'document': jsonEncode(job.toJson()),
  };

  /// Transaction + unique index enforce dedupe even across concurrent callers.
  Future<PrintJob> insert(PrintJob job) async {
    final result = await database.transaction((tx) async {
      if (job.purpose == PrintPurpose.initial) {
        final existing = await tx.query(
          'jobs',
          where: "location_id = ? AND order_id = ? AND purpose = 'initial'",
          whereArgs: [job.locationId, job.orderId],
          limit: 1,
        );
        if (existing.isNotEmpty) return _read(existing.first);
      }
      await tx.insert('jobs', _row(job));
      return job;
    });
    _notify();
    return result;
  }

  Future<PrintJob?> findInitial(String locationId, String orderId) async {
    final rows = await database.query(
      'jobs',
      where: "location_id = ? AND order_id = ? AND purpose = 'initial'",
      whereArgs: [locationId, orderId],
      limit: 1,
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  Future<PrintJob?> get(String id) async {
    final rows = await database.query('jobs', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _read(rows.first);
  }

  Future<List<PrintJob>> list({
    String? locationId,
    PrintJobStatus? status,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (locationId != null) {
      clauses.add('location_id = ?');
      args.add(locationId);
    }
    if (status != null) {
      clauses.add('status = ?');
      args.add(status.name);
    }
    final rows = await database.query(
      'jobs',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, rowid ASC',
    );
    return rows.map(_read).toList();
  }

  Future<bool> update(PrintJob job, {required PrintJobStatus expected}) async {
    final count = await database.update(
      'jobs',
      _row(job),
      where: 'id = ? AND status = ?',
      whereArgs: [job.id, expected.name],
    );
    if (count > 0) _notify();
    return count == 1;
  }

  /// Called exactly once per queue lifetime, before any worker starts.
  Future<void> recover() async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        'jobs',
        where: 'status = ?',
        whereArgs: ['sending'],
      );
      for (final row in rows) {
        final job = _read(row).transition(
          PrintJobStatus.unknown,
          error: 'App stopped during send. Delivery is unknown; no automatic retry.',
        );
        await tx.update(
          'jobs',
          _row(job),
          where: 'id = ?',
          whereArgs: [job.id],
        );
      }
    });
    _notify();
  }

  Future<void> dispose() => _changes.close();
}
