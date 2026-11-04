import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/app_database.dart';

void main() {
  late Directory temporaryDirectory;
  late String activeDatabasePath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'srk-backup-restore-',
    );
    activeDatabasePath = '${temporaryDirectory.path}/active.db';
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('rejects a truncated/non-SQLite backup without changing active data',
      () async {
    final appDatabase = AppDatabase.forTesting(
      databasePath: activeDatabasePath,
    );
    final active = await appDatabase.database;
    await active.insert('parties', {
      'name': 'Keep this party',
    });

    final invalidBackup = File('${temporaryDirectory.path}/truncated.db');
    await invalidBackup.writeAsBytes([83, 81, 76, 105, 116, 101]);

    await expectLater(
      appDatabase.restoreBackup(invalidBackup.path),
      throwsA(isA<FormatException>()),
    );

    final rows = await active.query('parties');
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Keep this party');
    await appDatabase.close();
  });

  test('rejects a structurally incomplete current-version backup', () async {
    final appDatabase = AppDatabase.forTesting(
      databasePath: activeDatabasePath,
    );
    await appDatabase.database;

    final incompletePath = '${temporaryDirectory.path}/incomplete.db';
    final incomplete = await databaseFactory.openDatabase(incompletePath);
    await incomplete.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        setting_key TEXT NOT NULL,
        setting_value TEXT
      )
    ''');
    await incomplete.setVersion(34);
    await incomplete.close();

    await expectLater(
      appDatabase.restoreBackup(incompletePath),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('required application tables'),
        ),
      ),
    );

    // A rejected restore must leave the active database open and usable.
    final active = await appDatabase.database;
    expect(await active.rawQuery('PRAGMA integrity_check'),
        isNotEmpty);
    await appDatabase.close();
  });

  test('refuses to restore the active database file onto itself', () async {
    final appDatabase = AppDatabase.forTesting(
      databasePath: activeDatabasePath,
    );
    await appDatabase.database;

    await expectLater(
      appDatabase.restoreBackup(activeDatabasePath),
      throwsA(isA<StateError>()),
    );

    await appDatabase.close();
  });
}
