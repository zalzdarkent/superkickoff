import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Single access point for the SQLite game database.
///
/// The bundled asset [dbName] is copied into the app documents directory on
/// first launch (asset databases are read-only), then opened as a normal
/// writable SQLite database. It serves both as reference data (teams, players,
/// tournaments...) and as the save-game store (seasons, fixtures, results).
class AppDatabase {
  AppDatabase._();

  static const String dbName = 'superkickoff_2025.db';
  static Database? _db;

  /// Opens (and lazily installs) the database. Desktop platforms use
  /// [sqflite_common_ffi]; Android/iOS use the default sqflite bindings.
  static Future<Database> open() async {
    if (_db != null) return _db!;
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final Directory docs =
        await getApplicationDocumentsDirectory();
    final String target = p.join(docs.path, dbName);
    final File file = File(target);
    if (!file.existsSync()) {
      final ByteData asset = await rootBundle.load('assets/data/$dbName');
      final List<int> bytes = asset.buffer.asUint8List();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    _db = await databaseFactory.openDatabase(
      target,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    return _db!;
  }

  /// Test/dev helper: open an arbitrary file directly.
  static Future<Database> openFile(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Progress reported while the long career-generation runs.
  static final ValueNotifier<String> status =
      ValueNotifier<String>('Preparing database...');
}
