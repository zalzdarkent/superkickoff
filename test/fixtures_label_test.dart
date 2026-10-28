import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/state/career_provider.dart';
import 'package:superkickoff/ui/screens/knockout_bracket_sheet.dart';

void main() {
  test('labels knockout rounds from the bracket size', () {
    expect(knockoutRoundName(1, 6), 'Round of 64');
    expect(knockoutRoundName(2, 6), 'Round of 32');
    expect(knockoutRoundName(5, 6), 'Semi-finals');
    expect(knockoutRoundName(1, 4), 'Round of 16');
    expect(knockoutRoundName(2, 4), 'Quarter-finals');
    expect(knockoutRoundName(3, 4), 'Semi-finals');
    expect(knockoutRoundName(4, 4), 'Final');
    expect(knockoutRoundName(1, 2), 'Semi-finals');
    expect(knockoutRoundName(1, 1), 'Final');
    expect(knockoutTotalRounds(const <FixtureMatch>[]), 1);

    // ACL Elite-style with byes: 2 ties in phase 1, 4 ties in phase 2
    final List<FixtureMatch> aclMatches = <FixtureMatch>[
      // Phase 1 (2 ties, 4 matches two-legged)
      FixtureMatch.fromMap(<String, Object?>{'match_id': 1, 'tournament_id': 99, 'phase': 1, 'leg': 1, 'home_team_id': 1, 'away_team_id': 2, 'stadium_id': 1}),
      FixtureMatch.fromMap(<String, Object?>{'match_id': 2, 'tournament_id': 99, 'phase': 1, 'leg': 2, 'home_team_id': 2, 'away_team_id': 1, 'stadium_id': 2}),
      FixtureMatch.fromMap(<String, Object?>{'match_id': 3, 'tournament_id': 99, 'phase': 1, 'leg': 1, 'home_team_id': 3, 'away_team_id': 4, 'stadium_id': 3}),
      FixtureMatch.fromMap(<String, Object?>{'match_id': 4, 'tournament_id': 99, 'phase': 1, 'leg': 2, 'home_team_id': 4, 'away_team_id': 3, 'stadium_id': 4}),
      // Phase 2 (4 ties, 8 matches two-legged)
      for (int i = 0; i < 4; i++) ...<FixtureMatch>[
        FixtureMatch.fromMap(<String, Object?>{'match_id': 10 + i * 2, 'tournament_id': 99, 'phase': 2, 'leg': 1, 'home_team_id': 10 + i, 'away_team_id': 20 + i, 'stadium_id': 1}),
        FixtureMatch.fromMap(<String, Object?>{'match_id': 11 + i * 2, 'tournament_id': 99, 'phase': 2, 'leg': 2, 'home_team_id': 20 + i, 'away_team_id': 10 + i, 'stadium_id': 2}),
      ],
    ];
    expect(knockoutTotalRounds(aclMatches), 4);
  });

  test('labels fixtures with their competition names', () {
    final CareerProvider game = CareerProvider()
      ..league = Tournament.fromMap(<String, Object?>{
        'tournament_id': 1,
        'name': 'League',
        'organization': DbOrg.orgLeague,
      })
      ..cups = <Tournament>[
        Tournament.fromMap(<String, Object?>{
          'tournament_id': 2,
          'name': 'FA Cup',
          'organization': DbOrg.orgNationalCup,
        }),
        Tournament.fromMap(<String, Object?>{
          'tournament_id': 3,
          'name': 'AFC Champions League',
          'organization': DbOrg.orgInternational,
        }),
      ];

    FixtureMatch fixture(int tournamentId) =>
        FixtureMatch.fromMap(<String, Object?>{
          'match_id': tournamentId,
          'tournament_id': tournamentId,
          'home_team_id': 1,
          'away_team_id': 2,
          'stadium_id': 1,
        });

    expect(game.competitionLabel(fixture(1)), 'League');
    expect(game.competitionLabel(fixture(2)), 'FA Cup');
    expect(game.competitionLabel(fixture(3)), 'AFC Champions League');
  });

  testWidgets('knockout bracket scrolls a long opening round', (
    WidgetTester tester,
  ) async {
    final Map<int, Team> teams = <int, Team>{
      for (int id = 1; id <= 64; id++)
        id: Team.fromMap(<String, Object?>{
          'team_id': id,
          'name': 'Club $id',
          'country_id': 1,
          'stadium_id': 1,
          'coach_id': 1,
        }),
    };
    final List<FixtureMatch> matches = List<FixtureMatch>.generate(
      32,
      (int index) => FixtureMatch.fromMap(<String, Object?>{
        'match_id': index + 1,
        'tournament_id': 1,
        'phase': 1,
        'status': DbMatch.matchFinished,
        'home_team_id': index * 2 + 1,
        'away_team_id': index * 2 + 2,
        'stadium_id': 1,
        'home_goals': 1,
        'away_goals': 0,
        'winner_id': index * 2 + 1,
      }),
    );
    final Tournament tournament = Tournament.fromMap(<String, Object?>{
      'tournament_id': 1,
      'name': 'Cup',
      'organization': DbOrg.orgNationalCup,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: FilledButton(
              onPressed: () => showKnockoutBracket(
                context,
                tournament: tournament,
                matches: matches,
                teams: teams,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
