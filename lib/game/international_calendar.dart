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

    // Reference FIFA Men's International Match Calendar (2025-2030)
    if (startYear < 2026) {
      // 2025 Calendar: 5 standard 9-day windows (up to 2 matches each) + summer
      windows.addAll(<InternationalWindow>[
        InternationalWindow(
          windowId: 'win_${seasonId}_sep',
          seasonId: seasonId,
          name: 'FIFA Window (September $startYear)',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '$startYear-09-01',
          endDate: '$startYear-09-09',
          releaseStartDate: '$startYear-08-31',
          returnDate: '$startYear-09-10',
          isMandatoryRelease: true,
          maxMatches: 2,
          clubFixturesAllowed: false,
        ),
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
          windowId: 'win_${seasonId}_nov',
          seasonId: seasonId,
          name: 'FIFA Window (November $startYear)',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '$startYear-11-10',
          endDate: '$startYear-11-18',
          releaseStartDate: '$startYear-11-09',
          returnDate: '$startYear-11-19',
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
          windowId: 'win_${seasonId}_jun',
          seasonId: seasonId,
          name: 'FIFA Window (June ${startYear + 1})',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '${startYear + 1}-06-01',
          endDate: '${startYear + 1}-06-09',
          releaseStartDate: '${startYear + 1}-05-31',
          returnDate: '${startYear + 1}-06-10',
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
    } else {
      // 2026+ Calendar: Combined 16-day autumn window (up to 4 matches) + Nov + Mar + Jun
      windows.addAll(<InternationalWindow>[
        InternationalWindow(
          windowId: 'win_${seasonId}_autumn',
          seasonId: seasonId,
          name: 'FIFA Extended Window (Sep/Oct $startYear)',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '$startYear-09-21',
          endDate: '$startYear-10-06',
          releaseStartDate: '$startYear-09-20',
          returnDate: '$startYear-10-07',
          isMandatoryRelease: true,
          maxMatches: 4,
          clubFixturesAllowed: false,
        ),
        InternationalWindow(
          windowId: 'win_${seasonId}_nov',
          seasonId: seasonId,
          name: 'FIFA Window (November $startYear)',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '$startYear-11-09',
          endDate: '$startYear-11-17',
          releaseStartDate: '$startYear-11-08',
          returnDate: '$startYear-11-18',
          isMandatoryRelease: true,
          maxMatches: 2,
          clubFixturesAllowed: false,
        ),
        InternationalWindow(
          windowId: 'win_${seasonId}_mar',
          seasonId: seasonId,
          name: 'FIFA Window (March ${startYear + 1})',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '${startYear + 1}-03-22',
          endDate: '${startYear + 1}-03-30',
          releaseStartDate: '${startYear + 1}-03-21',
          returnDate: '${startYear + 1}-03-31',
          isMandatoryRelease: true,
          maxMatches: 2,
          clubFixturesAllowed: false,
        ),
        InternationalWindow(
          windowId: 'win_${seasonId}_jun',
          seasonId: seasonId,
          name: 'FIFA Window (June ${startYear + 1})',
          windowType: InternationalWindowType.fifaWindow,
          startDate: '${startYear + 1}-06-07',
          endDate: '${startYear + 1}-06-15',
          releaseStartDate: '${startYear + 1}-06-06',
          returnDate: '${startYear + 1}-06-16',
          isMandatoryRelease: true,
          maxMatches: 2,
          clubFixturesAllowed: false,
        ),
        InternationalWindow(
          windowId: 'win_${seasonId}_summer',
          seasonId: seasonId,
          name: 'Summer Tournament Window (${startYear + 1})',
          windowType: InternationalWindowType.finalTournament,
          startDate: '${startYear + 1}-06-18',
          endDate: '${startYear + 1}-07-26',
          releaseStartDate: '${startYear + 1}-06-10',
          returnDate: '${startYear + 1}-07-27',
          isMandatoryRelease: true,
          maxMatches: 7,
          clubFixturesAllowed: false,
        ),
      ]);
    }

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

  /// Computes all dates where top clubs must avoid fixtures due to mandatory international windows.
  Future<List<DateTime>> mandatoryUnavailableDates(int seasonId) async {
    final List<InternationalWindow> windows = await windowsForSeason(seasonId);
    final Set<DateTime> dates = <DateTime>{};
    for (final InternationalWindow win in windows) {
      if (!win.isMandatoryRelease) continue;
      final DateTime? start = DateTime.tryParse(win.startDate);
      final DateTime? end = DateTime.tryParse(win.endDate);
      if (start == null || end == null) continue;
      for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        dates.add(DateTime(d.year, d.month, d.day));
      }
    }
    return dates.toList()..sort();
  }
}
