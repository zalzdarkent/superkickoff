import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/message_repository.dart';

/// Configuration rules for a league or country's transfer windows.
class CountryTransferWindowRule {
  const CountryTransferWindowRule({
    required this.countryId,
    required this.countryName,
    required this.summerStartMonth,
    required this.summerStartDay,
    required this.summerEndMonth,
    required this.summerEndDay,
    required this.winterStartMonth,
    required this.winterStartDay,
    required this.winterEndMonth,
    required this.winterEndDay,
    this.allowFreeAgentsOutside = true,
  });

  final int countryId;
  final String countryName;
  final int summerStartMonth;
  final int summerStartDay;
  final int summerEndMonth;
  final int summerEndDay;
  final int winterStartMonth;
  final int winterStartDay;
  final int winterEndMonth;
  final int winterEndDay;
  final bool allowFreeAgentsOutside;

  String summerStartDate(int startYear) =>
      '${startYear.toString().padLeft(4, '0')}-'
      '${summerStartMonth.toString().padLeft(2, '0')}-'
      '${summerStartDay.toString().padLeft(2, '0')}';

  String summerEndDate(int startYear) =>
      '${startYear.toString().padLeft(4, '0')}-'
      '${summerEndMonth.toString().padLeft(2, '0')}-'
      '${summerEndDay.toString().padLeft(2, '0')}';

  String winterStartDate(int startYear) =>
      '${(startYear + (winterStartMonth >= 7 ? 0 : 1)).toString().padLeft(4, '0')}-'
      '${winterStartMonth.toString().padLeft(2, '0')}-'
      '${winterStartDay.toString().padLeft(2, '0')}';

  String winterEndDate(int startYear) =>
      '${(startYear + 1).toString().padLeft(4, '0')}-'
      '${winterEndMonth.toString().padLeft(2, '0')}-'
      '${winterEndDay.toString().padLeft(2, '0')}';
}

/// Realistic Transfer Window Engine for EA FC / Football Manager style career mode.
///
/// Features:
/// - Exactly two major windows per season: Summer (pre/early season) and Winter (mid-season).
/// - No automatic third window at season-end.
/// - Distinct registration calendars configured per country/league.
/// - Destination club's registration window controls transfer execution.
/// - Out-of-window agreements become Scheduled Transfers for the next valid registration window.
/// - Free agents registration according to league rules.
/// - Notifications for Window Opening, Deadline Day, and Window Closure.
class TransferWindowManager {
  TransferWindowManager(this.db, {MessageRepository? messages})
      : _messages = messages ?? MessageRepository(db);

  final Database db;
  final MessageRepository _messages;

  /// Curated country calendar presets.
  static const Map<int, CountryTransferWindowRule> countryRules = <int, CountryTransferWindowRule>{
    // Indonesia: Summer July 1 - Aug 31, Winter Dec 15 - Jan 15 (Emergency free agent allowed)
    94: CountryTransferWindowRule(
      countryId: 94,
      countryName: 'Indonesia',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 8,
      summerEndDay: 31,
      winterStartMonth: 12,
      winterStartDay: 15,
      winterEndMonth: 1,
      winterEndDay: 15,
      allowFreeAgentsOutside: true,
    ),
    // England: Summer July 1 - Sep 1, Winter Jan 1 - Jan 31
    44: CountryTransferWindowRule(
      countryId: 44,
      countryName: 'England',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 1,
      winterStartMonth: 1,
      winterStartDay: 1,
      winterEndMonth: 1,
      winterEndDay: 31,
      allowFreeAgentsOutside: false,
    ),
    // Spain: Summer July 1 - Sep 1, Winter Jan 1 - Jan 31
    65: CountryTransferWindowRule(
      countryId: 65,
      countryName: 'Spain',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 1,
      winterStartMonth: 1,
      winterStartDay: 1,
      winterEndMonth: 1,
      winterEndDay: 31,
      allowFreeAgentsOutside: false,
    ),
    // Italy: Summer July 1 - Sep 1, Winter Jan 2 - Jan 31
    106: CountryTransferWindowRule(
      countryId: 106,
      countryName: 'Italy',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 1,
      winterStartMonth: 1,
      winterStartDay: 2,
      winterEndMonth: 1,
      winterEndDay: 31,
      allowFreeAgentsOutside: false,
    ),
    // Germany: Summer July 1 - Sep 1, Winter Jan 1 - Feb 1
    80: CountryTransferWindowRule(
      countryId: 80,
      countryName: 'Germany',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 1,
      winterStartMonth: 1,
      winterStartDay: 1,
      winterEndMonth: 2,
      winterEndDay: 1,
      allowFreeAgentsOutside: false,
    ),
    // France: Summer July 1 - Sep 1, Winter Jan 1 - Jan 31
    75: CountryTransferWindowRule(
      countryId: 75,
      countryName: 'France',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 1,
      winterStartMonth: 1,
      winterStartDay: 1,
      winterEndMonth: 1,
      winterEndDay: 31,
      allowFreeAgentsOutside: false,
    ),
    // Saudi Arabia: Summer July 1 - Sep 15, Winter Jan 1 - Jan 30
    10: CountryTransferWindowRule(
      countryId: 10,
      countryName: 'Saudi Arabia',
      summerStartMonth: 7,
      summerStartDay: 1,
      summerEndMonth: 9,
      summerEndDay: 15,
      winterStartMonth: 1,
      winterStartDay: 1,
      winterEndMonth: 1,
      winterEndDay: 30,
      allowFreeAgentsOutside: true,
    ),
  };

  /// Fallback rule for countries without custom presets.
  static CountryTransferWindowRule defaultRule(int countryId) =>
      CountryTransferWindowRule(
        countryId: countryId,
        countryName: 'Default',
        summerStartMonth: 7,
        summerStartDay: 1,
        summerEndMonth: 8,
        summerEndDay: 31,
        winterStartMonth: 1,
        winterStartDay: 1,
        winterEndMonth: 1,
        winterEndDay: 31,
        allowFreeAgentsOutside: true,
      );

  /// Ensure both Summer and Winter transfer windows exist for all clubs in [seasonId].
  /// Exactly two windows are generated: no third window at season end.
  Future<void> ensureWindowsForSeason(int seasonId, int startYear) async {
    // 1. Collect all distinct country_ids in this season
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT DISTINCT tm.country_id
      FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[seasonId],
    );

    final Set<int> countryIds = <int>{
      ...countryRules.keys,
      for (final Map<String, Object?> r in rows)
        if (r['country_id'] != null) r['country_id'] as int,
    };
    if (countryIds.isEmpty) countryIds.add(94); // Default to Indonesia if empty

    for (final int countryId in countryIds) {
      final CountryTransferWindowRule rule =
          countryRules[countryId] ?? defaultRule(countryId);

      // Summer Window
      final String summerStart = rule.summerStartDate(startYear);
      final String summerEnd = rule.summerEndDate(startYear);
      await db.insert(
        t.transferWindows,
        <String, Object?>{
          'season_id': seasonId,
          'country_id': countryId,
          'tournament_id': 0,
          'window_type': 'summer',
          'start_date': summerStart,
          'end_date': summerEnd,
          'is_open': 0,
          'allow_free_agents_outside': rule.allowFreeAgentsOutside ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // Winter Window
      final String winterStart = rule.winterStartDate(startYear);
      final String winterEnd = rule.winterEndDate(startYear);
      await db.insert(
        t.transferWindows,
        <String, Object?>{
          'season_id': seasonId,
          'country_id': countryId,
          'tournament_id': 0,
          'window_type': 'winter',
          'start_date': winterStart,
          'end_date': winterEnd,
          'is_open': 0,
          'allow_free_agents_outside': rule.allowFreeAgentsOutside ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Get all transfer windows for [seasonId].
  Future<List<TransferWindow>> windowsForSeason(int seasonId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.transferWindows,
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      orderBy: 'start_date ASC',
    );
    return rows.map(TransferWindow.fromMap).toList();
  }

  /// Resolve countryId for a team.
  Future<int> countryForTeam(int teamId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.teams,
      columns: <String>['country_id'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    return rows.isEmpty ? 94 : ((rows.first['country_id'] as int?) ?? 94);
  }

  /// Get transfer windows for a specific country in [seasonId].
  Future<List<TransferWindow>> windowsForCountry(
    int seasonId,
    int countryId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.transferWindows,
      where: 'season_id = ? AND country_id = ?',
      whereArgs: <Object?>[seasonId, countryId],
      orderBy: 'start_date ASC',
    );
    return rows.map(TransferWindow.fromMap).toList();
  }

  /// Checks if registration window is OPEN on [date] for [teamId] (Destination Club's rule).
  Future<bool> isWindowOpenForTeam(
    int seasonId,
    int teamId,
    String date,
  ) async {
    final int countryId = await countryForTeam(teamId);
    final List<TransferWindow> windows = await windowsForCountry(
      seasonId,
      countryId,
    );
    for (final TransferWindow w in windows) {
      if (w.isWindowOpen(date)) return true;
    }
    return false;
  }

  /// Returns currently active window for [teamId], or null if closed.
  Future<TransferWindow?> activeWindowForTeam(
    int seasonId,
    int teamId,
    String date,
  ) async {
    final int countryId = await countryForTeam(teamId);
    final List<TransferWindow> windows = await windowsForCountry(
      seasonId,
      countryId,
    );
    for (final TransferWindow w in windows) {
      if (w.isWindowOpen(date)) return w;
    }
    return null;
  }

  /// Returns the next valid registration window for [teamId] that will open on or after [date].
  /// If the current season's winter window has already passed, projects the next season's Summer window!
  Future<TransferWindow> nextRegistrationWindowForTeam(
    int seasonId,
    int teamId,
    String date,
  ) async {
    final int countryId = await countryForTeam(teamId);
    final List<TransferWindow> windows = await windowsForCountry(
      seasonId,
      countryId,
    );

    // Look for upcoming window in current season
    for (final TransferWindow w in windows) {
      if (date.compareTo(w.startDate) <= 0) {
        return w;
      }
      if (w.isWindowOpen(date)) {
        return w;
      }
    }

    // If past all windows this season, project the next season's Summer window
    final CountryTransferWindowRule rule =
        countryRules[countryId] ?? defaultRule(countryId);
    final DateTime currentDt = DateTime.tryParse(date) ?? DateTime.now();
    final int nextStartYear = currentDt.year + (currentDt.month >= 6 ? 1 : 0);

    return TransferWindow(
      windowId: 0,
      seasonId: seasonId + 1,
      countryId: countryId,
      windowType: 'summer',
      startDate: rule.summerStartDate(nextStartYear),
      endDate: rule.summerEndDate(nextStartYear),
      isOpen: false,
      allowFreeAgentsOutside: rule.allowFreeAgentsOutside,
    );
  }

  /// Checks if a free agent can be registered on [date] for [teamId].
  /// Allowed if:
  /// 1. The window is currently open, OR
  /// 2. League configuration explicitly permits free agent signing outside the window.
  Future<bool> canRegisterFreeAgent(
    int seasonId,
    int teamId,
    String date,
  ) async {
    if (await isWindowOpenForTeam(seasonId, teamId, date)) return true;
    final int countryId = await countryForTeam(teamId);
    final List<TransferWindow> windows = await windowsForCountry(
      seasonId,
      countryId,
    );
    if (windows.isNotEmpty && windows.first.allowFreeAgentsOutside) {
      return true;
    }
    return false;
  }

  /// Check date transitions and dispatch notifications to user club.
  Future<void> checkAndSendNotifications({
    required int seasonId,
    required int userTeamId,
    required String previousDate,
    required String currentDate,
  }) async {
    final int countryId = await countryForTeam(userTeamId);
    final List<TransferWindow> windows = await windowsForCountry(
      seasonId,
      countryId,
    );

    for (final TransferWindow w in windows) {
      // 1. Window Opening
      if (previousDate.compareTo(w.startDate) < 0 &&
          currentDate.compareTo(w.startDate) >= 0 &&
          currentDate.compareTo(w.endDate) <= 0) {
        await _messages.insert(
          title: '${w.displayName} Dibuka!',
          body:
              'Jendela transfer (${w.displayName}) resmi dibuka mulai ${w.startDate} hingga ${w.endDate}. '
              'Anda sekarang dapat mendaftarkan pemain baru secara langsung.',
          teamId: userTeamId,
          sender: 'Transfer Desk',
          date: currentDate,
        );
      }

      // 2. Deadline Day
      if (w.isDeadlineDay(currentDate) && !w.isDeadlineDay(previousDate)) {
        await _messages.insert(
          title: 'DEADLINE DAY: ${w.displayName}',
          body:
              'Hari ini adalah hari terakhir jendela transfer! Penutupan deadline hari ini pada pukul 23:59. '
              'Selesaikan kesepakatan pemain Anda sebelum jendela resmi ditutup.',
          teamId: userTeamId,
          sender: 'Transfer Desk',
          date: currentDate,
        );
      }

      // 3. Window Closure
      if (previousDate.compareTo(w.endDate) <= 0 &&
          currentDate.compareTo(w.endDate) > 0) {
        await _messages.insert(
          title: '${w.displayName} Resmi Ditutup',
          body:
              'Jendela transfer telah resmi ditutup. '
              'Semua kesepakatan baru yang dibuat mulai sekarang akan dijadwalkan untuk periode registrasi berikutnya.',
          teamId: userTeamId,
          sender: 'Transfer Desk',
          date: currentDate,
        );
      }
    }
  }
}
