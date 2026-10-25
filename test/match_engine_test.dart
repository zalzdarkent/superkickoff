import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/game/formation.dart';
import 'package:superkickoff/game/match_engine.dart';

/// Builds a balanced 16-man squad (1 GK, 5 DEF, 6 MID, 4 ATT).
List<Player> buildSquad(int seed) {
  final List<int> positions = <int>[
    1,
    2,
    2,
    2,
    2,
    3,
    7,
    7,
    7,
    7,
    8,
    8,
    10,
    10,
    10,
    11,
  ];
  return List<Player>.generate(positions.length, (int i) {
    final int position = positions[i];
    return Player(
      playerId: seed * 100 + i,
      name: 'Player $seed-$i',
      age: 24,
      positionId: position,
      power: 55 + (i % 20),
      potential: 70,
      fitness: 95,
      value: 1000000,
      salary: 10000,
      countryId: 141,
      squadStatus: 1,
      marketStatus: 1,
      statusId: 1,
      isCaptain: i == 0,
      shirtNumber: i + 1,
      stars: 3,
      skillA: 50,
      skillB: 50,
      height: 180,
      championships: null,
    );
  });
}

void main() {
  group('Lineup', () {
    test('picks eleven players in a valid 4-4-2 shape', () {
      final Lineup lineup = Lineup.best(buildSquad(1));
      expect(lineup.starters.length, 11);
      expect(lineup.substitutes.length, greaterThan(0));

      int group(int id) => Lineup.groupOf(
        lineup.starters.firstWhere((Player p) => p.playerId == id),
      );
      final Map<int, int> counts = <int, int>{};
      for (final Player p in lineup.starters) {
        final int g = group(p.playerId);
        counts[g] = (counts[g] ?? 0) + 1;
      }
      expect(counts[1], 1, reason: 'exactly one keeper');
      expect(counts[2], 4);
      expect(counts[3], 4);
      expect(counts[4], 2);
    });

    test('honours the selected formation', () {
      final Lineup lineup = Lineup.best(
        buildSquad(4),
        formation: Formation.f433,
      );
      final Map<int, int> counts = <int, int>{};
      for (final Player p in lineup.starters) {
        final int g = Lineup.groupOf(p);
        counts[g] = (counts[g] ?? 0) + 1;
      }
      expect(counts[1], 1);
      expect(counts[2], 4);
      expect(counts[3], 3);
      expect(counts[4], 3);
    });

    test('starts the players picked by the manager', () {
      final List<Player> squad = buildSquad(10);
      final List<int> picked = squad
          .take(11)
          .map((Player p) => p.playerId)
          .toList();
      final Lineup lineup = Lineup.best(squad, preferredIds: picked);
      expect(lineup.starters.length, 11);
      for (final int id in picked) {
        expect(
          lineup.starters.any((Player p) => p.playerId == id),
          isTrue,
          reason: 'picked player $id must start',
        );
      }
      expect(lineup.starters.where((Player p) => p.positionId == 1).length, 1);
    });

    test('excludes injured and suspended players', () {
      final List<Player> squad = buildSquad(2);
      final Player keeper = squad.first;
      final Player banned = squad[1];
      final List<Player> tweaked = <Player>[
        for (final Player p in squad)
          if (p.playerId == keeper.playerId)
            Player(
              playerId: p.playerId,
              name: p.name,
              age: p.age,
              positionId: p.positionId,
              power: p.power,
              potential: p.potential,
              fitness: 5,
              value: p.value,
              salary: p.salary,
              countryId: p.countryId,
              squadStatus: p.squadStatus,
              marketStatus: p.marketStatus,
              statusId: p.statusId,
              isCaptain: p.isCaptain,
              shirtNumber: p.shirtNumber,
              stars: p.stars,
              skillA: p.skillA,
              skillB: p.skillB,
              height: p.height,
              championships: p.championships,
            )
          else
            p,
      ];
      final Lineup lineup = Lineup.best(
        tweaked,
        bannedIds: <int>{banned.playerId},
      );
      expect(lineup.unavailableIds.contains(banned.playerId), isTrue);
      expect(
        lineup.starters.any((Player p) => p.playerId == banned.playerId),
        isFalse,
      );
      // Injured keeper is still selectable: nobody else can keep goal.
      expect(
        lineup.starters.any((Player p) => p.playerId == keeper.playerId),
        isTrue,
      );
    });
  });

  group('MatchEngine', () {
    test('produces a complete, deterministic result', () {
      MatchInput input() => MatchInput(
        homeSquad: buildSquad(3),
        awaySquad: buildSquad(4),
        capacityGeneral: 20000,
        capacityStand: 8000,
        capacityTerrace: 4000,
        capacityBoxes: 500,
        homePower: 70,
        refereeTemper: 3,
      );

      final MatchResult first = MatchEngine(random: Random(42))
          .simulate(input());
      final MatchResult second = MatchEngine(random: Random(42))
          .simulate(input());

      expect(first.homeGoals, second.homeGoals);
      expect(first.awayGoals, second.awayGoals);
      expect(first.homeGoals, inInclusiveRange(0, 12));
      expect(first.awayGoals, inInclusiveRange(0, 12));

      // Every starter appears in the per-player table.
      expect(first.playerRows.length, greaterThanOrEqualTo(22));
      final int minutes = first.playerRows
          .map((MatchPlayerRow row) => row.minutes)
          .fold(0, (int a, int b) => a + b);
      expect(minutes, greaterThanOrEqualTo(22 * 60));

      // Match statistics are internally consistent.
      expect(first.homeShots, greaterThanOrEqualTo(first.homeShotsOnTarget));
      expect(first.awayShots, greaterThanOrEqualTo(first.awayShotsOnTarget));
      expect(first.homeShotsOnTarget, greaterThanOrEqualTo(first.homeGoals));
      expect(first.awayShotsOnTarget, greaterThanOrEqualTo(first.awayGoals));
      expect(first.homePossession, inInclusiveRange(25, 75));
      expect(
        first.playerRows.every(
          (MatchPlayerRow row) => row.playerName.isNotEmpty,
        ),
        isTrue,
      );

      // Attendance is bounded by the stadium tiers.
      final int attendance =
          first.attendanceGeneral +
          first.attendanceStand +
          first.attendanceTerrace +
          first.attendanceBoxes;
      expect(attendance, lessThanOrEqualTo(32500));
      expect(first.revenue, greaterThanOrEqualTo(0));
    });

    test('records goal events consistent with the score', () {
      final MatchResult result = MatchEngine(random: Random(7)).simulate(
        MatchInput(
          homeSquad: buildSquad(5),
          awaySquad: buildSquad(6),
          capacityGeneral: 30000,
          capacityStand: 10000,
          capacityTerrace: 5000,
          capacityBoxes: 800,
          homePower: 80,
          refereeTemper: 2,
        ),
        recordEvents: true,
      );
      bool scoring(MatchEvent e) =>
          e.type == MatchEvent.goal ||
          e.type == MatchEvent.penaltyScored ||
          e.type == MatchEvent.ownGoal;

      // Own goals credit the opposite side, so flip their event side.
      bool creditsHome(MatchEvent e) =>
          e.type == MatchEvent.ownGoal ? !e.isHome : e.isHome;

      final int homeDisallowed = result.events
          .where(
            (MatchEvent e) =>
                e.type == MatchEvent.varGoalDisallowed && e.isHome,
          )
          .length;
      final int awayDisallowed = result.events
          .where(
            (MatchEvent e) =>
                e.type == MatchEvent.varGoalDisallowed && !e.isHome,
          )
          .length;
      final int homeScored =
          result.events
              .where((MatchEvent e) => scoring(e) && creditsHome(e))
              .length -
          homeDisallowed;
      final int awayScored =
          result.events
              .where((MatchEvent e) => scoring(e) && !creditsHome(e))
              .length -
          awayDisallowed;
      expect(homeScored, result.homeGoals);
      expect(awayScored, result.awayGoals);
      for (final MatchEvent event in result.events) {
        expect(event.minute, inInclusiveRange(1, 90));
      }
    });

    test('does not emit events when recording is disabled', () {
      final MatchResult result = MatchEngine(random: Random(9)).simulate(
        MatchInput(
          homeSquad: buildSquad(7),
          awaySquad: buildSquad(8),
          capacityGeneral: 1000,
          capacityStand: 500,
          capacityTerrace: 200,
          capacityBoxes: 50,
          homePower: 50,
        ),
        recordEvents: false,
      );
      expect(result.events, isEmpty);
    });

    test('shootout always produces a winner with alternating kicks', () {
      for (int seed = 1; seed <= 25; seed++) {
        final MatchPenaltyShootout shootout = MatchEngine(random: Random(seed))
            .penaltyShootout(
              MatchInput(
                homeSquad: buildSquad(3),
                awaySquad: buildSquad(4),
                capacityGeneral: 1000,
                capacityStand: 500,
                capacityTerrace: 200,
                capacityBoxes: 50,
                homePower: 70,
              ),
            );
        expect(
          shootout.homeScore == shootout.awayScore,
          isFalse,
          reason: 'a shootout can never end level',
        );
        expect(shootout.events.length, greaterThanOrEqualTo(6));
        expect(
          shootout.events.every(
            (MatchEvent e) =>
                e.type == MatchEvent.shootout &&
                (e.detail == null ||
                    e.detail!.startsWith('scored') ||
                    e.detail!.startsWith('missed')),
          ),
          isTrue,
        );
        // Kicks alternate home, away, home, away... unless the best-of-five
        // ends early, which always stops right after an away kick.
        final int fullRounds = shootout.events.length >= 10
            ? shootout.events.length - (shootout.events.length % 2)
            : shootout.events.length;
        for (int i = 0; i < fullRounds; i++) {
          expect(shootout.events[i].isHome, i.isEven);
        }
      }
    });

    test('shootout score matches the kick events', () {
      for (int seed = 1; seed <= 10; seed++) {
        final MatchPenaltyShootout shootout = MatchEngine(random: Random(seed))
            .penaltyShootout(
              MatchInput(
                homeSquad: buildSquad(11),
                awaySquad: buildSquad(12),
                capacityGeneral: 0,
                capacityStand: 0,
                capacityTerrace: 0,
                capacityBoxes: 0,
                homePower: 60,
              ),
            );
        int scored(bool home) => shootout.events
            .where(
              (MatchEvent e) =>
                  e.isHome == home &&
                  e.detail == 'scored ${e.detail!.split(' ').last}',
            )
            .length;
        expect(scored(true), shootout.homeScore);
        expect(scored(false), shootout.awayScore);
      }
    });

    test('VAR disallowed goals properly deduct goal and remove assist', () {
      bool foundDisallowed = false;
      for (int seed = 1; seed <= 500; seed++) {
        final MatchResult result = MatchEngine(random: Random(seed)).simulate(
          MatchInput(
            homeSquad: buildSquad(1),
            awaySquad: buildSquad(2),
            capacityGeneral: 10000,
            capacityStand: 5000,
            capacityTerrace: 2000,
            capacityBoxes: 500,
            homePower: 80,
          ),
          recordEvents: true,
        );
        final List<MatchEvent> disallowed = result.events
            .where((MatchEvent e) => e.type == MatchEvent.varGoalDisallowed)
            .toList();
        if (disallowed.isNotEmpty) {
          foundDisallowed = true;
          final int homeDisallowed = result.events
              .where(
                (MatchEvent e) =>
                    e.type == MatchEvent.varGoalDisallowed && e.isHome,
              )
              .length;
          final int awayDisallowed = result.events
              .where(
                (MatchEvent e) =>
                    e.type == MatchEvent.varGoalDisallowed && !e.isHome,
              )
              .length;
          final int homeNet =
              result.events
                  .where(
                    (MatchEvent e) =>
                        (e.type == MatchEvent.goal ||
                            e.type == MatchEvent.penaltyScored) &&
                        e.isHome,
                  )
                  .length -
              homeDisallowed +
              result.events
                  .where((MatchEvent e) => e.type == MatchEvent.ownGoal && !e.isHome)
                  .length;
          final int awayNet =
              result.events
                  .where(
                    (MatchEvent e) =>
                        (e.type == MatchEvent.goal ||
                            e.type == MatchEvent.penaltyScored) &&
                        !e.isHome,
                  )
                  .length -
              awayDisallowed +
              result.events
                  .where((MatchEvent e) => e.type == MatchEvent.ownGoal && e.isHome)
                  .length;
          expect(result.homeGoals, homeNet);
          expect(result.awayGoals, awayNet);

          // Total player goals should match final result goals
          final int totalPlayerGoals = result.playerRows.fold<int>(
            0,
            (int sum, MatchPlayerRow r) => sum + r.goals,
          );
          final int ownGoals = result.events
              .where((MatchEvent e) => e.type == MatchEvent.ownGoal)
              .length;
          expect(totalPlayerGoals + ownGoals, result.homeGoals + result.awayGoals);
          break;
        }
      }
      expect(foundDisallowed, isTrue);
    });
  });
}
