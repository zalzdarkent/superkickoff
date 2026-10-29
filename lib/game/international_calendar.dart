import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

/// Central international calendar service.
///
/// Implements season-aware FIFA International Match Windows and tournament windows.
/// Adheres to FIFA's 2025-2030 approved calendar structure while allowing edition-based
/// rules and future extensions.
class InternationalCalendarService {
  InternationalCalendarService(this.db);

  final Database db;

  /// Generates the standard FIFA international windows and summer tournament window
  /// for a given career season.
  Future<List<InternationalWindow>> generateWindowsForSeason(
    int seasonId,
    int startYear,
  ) async {
    final List<InternationalWindow> windows = <InternationalWindow>[];

    // Streamlined International Calendar:
    // 1 window in 1st half of season (October) + 1 window in 2nd half (March) + Summer Tournament (June/July)
    windows.addAll(<InternationalWindow>[
      InternationalWindow(
        windowId: 'win_${seasonId}_oct',
        seasonId: seasonId,
        name: 'FIFA Window (October $startYear)',
        windowType: InternationalWindowType.fifaWindow,
        startDate: '$startYear-10-06',
        endDate: '$startYear-10-14',
        releaseStartDate: '$startYear-10-05',
        returnDate: '$startYear-10-15',
        isMandatoryRelease: true,
        maxMatches: 2,
        clubFixturesAllowed: false,
      ),
      InternationalWindow(
        windowId: 'win_${seasonId}_mar',
        seasonId: seasonId,
        name: 'FIFA Window (March ${startYear + 1})',
        windowType: InternationalWindowType.fifaWindow,
        startDate: '${startYear + 1}-03-23',
        endDate: '${startYear + 1}-03-31',
        releaseStartDate: '${startYear + 1}-03-22',
        returnDate: '${startYear + 1}-04-01',
        isMandatoryRelease: true,
        maxMatches: 2,
        clubFixturesAllowed: false,
      ),
      InternationalWindow(
        windowId: 'win_${seasonId}_summer',
        seasonId: seasonId,
        name: 'Summer Tournament Window (${startYear + 1})',
        windowType: InternationalWindowType.finalTournament,
        startDate: '${startYear + 1}-06-11',
        endDate: '${startYear + 1}-07-19',
        releaseStartDate: '${startYear + 1}-06-01',
        returnDate: '${startYear + 1}-07-20',
        isMandatoryRelease: true,
        maxMatches: 7,
        clubFixturesAllowed: false,
      ),
    ]);

    // Persist to database
    for (final InternationalWindow win in windows) {
      await db.insert(
        t.internationalWindows,
        win.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    return windows;
  }

  /// Automatically synchronizes existing saved seasons to the streamlined 3-window calendar
  /// (removes redundant legacy windows like sep/nov/jun from ongoing saves).
  Future<void> syncStreamlinedWindowsForSeason(int seasonId, int startYear) async {
    final List<InternationalWindow> current = await windowsForSeason(seasonId);
    if (current.length > 3) {
      await db.delete(
        t.internationalWindows,
        where: 'season_id = ? AND window_id NOT IN (?, ?, ?)',
        whereArgs: <Object?>[
          seasonId,
          'win_${seasonId}_oct',
          'win_${seasonId}_mar',
          'win_${seasonId}_summer',
        ],
      );
      // Re-generate to ensure all 3 core windows are present
      await generateWindowsForSeason(seasonId, startYear);
    }
  }

  /// Returns all international windows for [seasonId].
  Future<List<InternationalWindow>> windowsForSeason(int seasonId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.internationalWindows,
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      orderBy: 'start_date ASC',
    );
    return rows.map(InternationalWindow.fromMap).toList();
  }

  /// Finds the international window that covers [date].
  Future<InternationalWindow?> windowForDate(int seasonId, String date) async {
    final List<InternationalWindow> windows = await windowsForSeason(seasonId);
    for (final InternationalWindow win in windows) {
      if (win.containsDate(date)) return win;
    }
    return null;
  }

  /// Finds the international window that holds player release for [date].
  Future<InternationalWindow?> windowForReleaseDate(int seasonId, String date) async {
    final List<InternationalWindow> windows = await windowsForSeason(seasonId);
    for (final InternationalWindow win in windows) {
      if (win.isPlayerReleased(date)) return win;
    }
    return null;
  }

  /// Checks if [date] falls within any mandatory release period for [seasonId].
  Future<bool> isMandatoryReleaseDate(int seasonId, String date) async {
    final InternationalWindow? win = await windowForReleaseDate(seasonId, date);
    return win != null && win.isMandatoryRelease;
  }

  /// Computes all dates where clubs must avoid fixtures due to international windows
  /// (including release start dates through return dates).
  Future<List<DateTime>> mandatoryUnavailableDates(int seasonId) async {
    final List<InternationalWindow> windows = await windowsForSeason(seasonId);
    final Set<DateTime> dates = <DateTime>{};
    for (final InternationalWindow win in windows) {
      if (!win.isMandatoryRelease && win.clubFixturesAllowed) continue;
      final DateTime? start = DateTime.tryParse(win.releaseStartDate);
      final DateTime? end = DateTime.tryParse(win.returnDate);
      if (start == null || end == null) continue;
      for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        dates.add(DateTime(d.year, d.month, d.day));
      }
    }
    return dates.toList()..sort();
  }
}
