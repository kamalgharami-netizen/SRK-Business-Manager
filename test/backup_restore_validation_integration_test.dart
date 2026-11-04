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
      'party_type': 'customer',
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

  test('rejects a backup from a different business without changing active data',
      () async {
    final appDatabase = AppDatabase.forTesting(
      databasePath: activeDatabasePath,
    );
    final active = await appDatabase.database;
    await active.insert('parties', {
      'name': 'Local business party',
      'party_type': 'customer',
    });
    await appDatabase.close();

    final foreignBackupPath = '${temporaryDirectory.path}/foreign-business.db';
    await File(activeDatabasePath).copy(foreignBackupPath);
    final foreignBackup = await databaseFactory.openDatabase(foreignBackupPath);
    await foreignBackup.update(
      'app_settings',
      {'setting_value': '11111111-1111-4111-8111-111111111111'},
      where: 'setting_key = ?',
      whereArgs: ['database_scope'],
    );
    await foreignBackup.close();

    await expectLater(
      appDatabase.restoreBackup(foreignBackupPath),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('different business'),
      )),
    );

    final reopened = await appDatabase.database;
    final parties = await reopened.query('parties');
    expect(parties, hasLength(1));
    expect(parties.single['name'], 'Local business party');
    await appDatabase.close();
  });

  test('rejects a backup created by a newer database schema', () async {
    final appDatabase = AppDatabase.forTesting(
      databasePath: activeDatabasePath,
    );
    final active = await appDatabase.database;
    await active.insert('parties', {
      'name': 'Keep current schema data',
      'party_type': 'customer',
    });
    await appDatabase.close();

    final newerBackupPath = '${temporaryDirectory.path}/newer-schema.db';
    await File(activeDatabasePath).copy(newerBackupPath);
    final newerBackup = await databaseFactory.openDatabase(newerBackupPath);
    await newerBackup.setVersion(35);
    await newerBackup.close();

    await expectLater(
      appDatabase.restoreBackup(newerBackupPath),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('newer than this app supports'),
      )),
    );

    final reopened = await appDatabase.database;
    final parties = await reopened.query('parties');
    expect(parties, hasLength(1));
    expect(parties.single['name'], 'Keep current schema data');
    await appDatabase.close();
  });
