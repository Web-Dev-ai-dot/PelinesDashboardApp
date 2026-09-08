import 'package:sqflite/sqflite.dart';

Future<Database> openPrintingDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final selected = factory ?? databaseFactory;
  final databasePath =
      path ?? '${await selected.getDatabasesPath()}/pelines_printing.db';
  return selected.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA synchronous = FULL');
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE jobs (id TEXT PRIMARY KEY, location_id TEXT NOT NULL, '
          'order_id TEXT NOT NULL, purpose TEXT NOT NULL, status TEXT NOT NULL, '
          'printer_id TEXT NOT NULL, created_at TEXT NOT NULL, document TEXT NOT NULL)',
        );
        await db.execute(
          "CREATE UNIQUE INDEX initial_job ON jobs(location_id, order_id) WHERE purpose = 'initial'",
        );
        await db.execute(
          'CREATE INDEX pending_jobs ON jobs(status, created_at)',
        );
        await db.execute(
          'CREATE TABLE settings (location_id TEXT PRIMARY KEY, document TEXT NOT NULL)',
        );
      },
    ),
  );
}
