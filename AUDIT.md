# MASTER TASK: Complete Football Manager Fixture Scheduling and Competition System Overhaul

Act as a senior football management game developer specializing in football competition regulations, fixture scheduling algorithms, Flutter/Dart architecture, SQLite database integrity, and automated testing.

Your task is to audit, repair, and improve the entire fixture scheduling system in the existing football manager game project.

The current game has irregular fixture schedules. Home and away assignments, match ordering, competition formats, and potentially fixture consistency need to be audited and corrected.

The goal is to create a reliable, realistic, deterministic, and competition-aware scheduling system inspired by real-world football management games such as Football Manager and EA SPORTS FC Career Mode.

IMPORTANT:
- Inspect the existing project and database before making changes.
- Preserve the current game architecture, UI, competition database, clubs, players, and save games.
- Reuse existing implementations when they are correct.
- Do not rewrite unrelated features.
- Do not delete or recreate the existing database.
- Do not assume every competition follows the same rules.
- Implement actual working code, not merely a proposal or pseudocode.
- Run the available tests and report the actual results.

---

# PHASE 1: COMPLETE PROJECT AUDIT

Before implementing anything, inspect the entire relevant codebase.

Identify:
1. The Flutter/Dart application architecture.
2. Existing competition, club, season, match, and fixture models.
3. SQLite database schema, relationships, indexes, and constraints.
4. Existing fixture generation algorithms.
5. Match simulation and match result persistence.
6. Season progression and the Continue/Advance Date mechanism.
7. League standings and tie-breaking rules.
8. Domestic cup progression.
9. Continental competition qualification and progression.
10. Promotion and relegation systems.
11. Transfer window and season calendar integration.
12. Existing scheduling, postponement, and rescheduling mechanisms.
13. Any random opponent selection or fixture generation triggered during season progression.
14. Existing hardcoded assumptions about league sizes, competition formats, and match dates.

Trace the complete flow from season initialization to fixture generation, match simulation, result persistence, standings updates, and season completion.

Identify the actual causes of irregular scheduling.

Produce a concise audit summary, then proceed with implementation without waiting for additional approval unless an essential decision is genuinely blocked.

# PHASE 2: BUILD A CENTRALIZED COMPETITION CONFIGURATION SYSTEM

Create or improve a centralized configuration system that defines the rules for each competition.

Each competition should support configuration for:

- Competition type.
- Competition format.
- Number of participating clubs.
- Season start and end dates.
- Matchday or round structure.
- Single or double round-robin.
- League phase or traditional group stage.
- Single-match or two-legged knockout.
- Home and away requirements.
- Neutral-venue matches.
- Number of knockout legs.
- Extra time and penalty shootouts.
- Aggregate-score rules.
- Away-goals rule, enabled only when explicitly required.
- Qualification and elimination rules.
- Matchday intervals.
- Minimum rest periods.
- International breaks and unavailable dates.
- Postponement and rescheduling behavior.
- Competition-specific restrictions.
- Final match scheduling.
- Promotion and relegation rules where applicable.

Use the existing database and domain models wherever practical.

Avoid hardcoding the same competition rules repeatedly across unrelated services.

Different competitions must be able to use different formats without requiring changes to the core fixture-generation algorithm.

If competition regulations vary by season, support season-specific configurations.

Do not invent rules for competitions whose regulations are unknown. Inspect existing data and implementations, then document any remaining assumptions.

# PHASE 3: DOMESTIC LEAGUE FIXTURE GENERATION

Implement a mathematically correct round-robin scheduling system.

Support:
- Single round-robin.
- Double round-robin.
- Even and odd numbers of participating clubs.
- BYE rounds when required.
- Configurable home-away orientation.
- Complete fixture generation before the season starts.

## Double Round-Robin Rules

For a league with N clubs:

- Every pair of clubs must meet exactly twice.
- Each pair must have one home fixture and one away fixture.
- Each club must play N - 1 opponents in each half of the season.
- The second half of the season should reverse the home and away assignments of the first half.
- No duplicate fixtures.
- No missing opponent pairings.
- No club should play more than once in the same competition round.
- Every generated fixture must belong to the correct competition and season.

For an even number of clubs:

- Matches per club: 2 × (N - 1).
- Number of rounds: 2 × (N - 1).
- Total league matches: N × (N - 1).
- Home matches per club: N - 1.
- Away matches per club: N - 1.

For an odd number of clubs:

- Use a BYE slot.
- Each club must face every other club twice in a double round-robin.
- Correctly handle rounds where a club does not play.
- Home and away totals may differ by one when an equal distribution is mathematically impossible.

Use a proven algorithm such as the circle method.

Do not select opponents independently or randomly during season progression.

## Required League Validation Cases

For a double round-robin league:

| Clubs | Rounds | Matches | Home per club | Away per club |
|---:|---:|---:|---:|---:|
| 20 | 38 | 380 | 19 | 19 |
| 18 | 34 | 306 | 17 | 17 |
| 12 | 22 | 132 | 11 | 11 |
| 10 | 18 | 90 | 9 | 9 |
| 8 | 14 | 56 | 7 | 7 |

Treat these values as mandatory automated test cases.

# PHASE 4: HOME-AWAY BALANCING AND FIXTURE SEQUENCING

A mathematically correct fixture list can still feel unrealistic if home and away matches are poorly distributed.

Implement a scheduling optimizer that evaluates the sequence of home and away assignments.

Prioritize the following objectives:

1. Equal total home and away matches whenever mathematically possible.
2. No more than two consecutive home matches when feasible.
3. No more than two consecutive away matches when feasible.
4. Balanced home-away distribution across five consecutive matches.
5. Avoid excessive home-away imbalance at the beginning of the season.
6. Avoid excessive home-away imbalance at the end of the season.
7. Avoid repeating the same opponent in consecutive league rounds.
8. Preserve the home-away reversal between the first and second halves of a double round-robin.
9. Avoid impossible or contradictory fixture assignments.

These are optimization objectives rather than universal football regulations.

If all preferences cannot be satisfied simultaneously, prioritize hard competition rules and total home-away balance, then minimize the remaining scheduling penalties.

Implement a scoring function or another suitable optimization approach rather than relying on arbitrary random swapping.

Use deterministic tie-breaking so identical inputs produce identical fixture lists.

For leagues with shared stadiums or clubs from the same city, support optional restrictions to avoid simultaneous home matches when the relevant data exists.

# PHASE 5: DOMESTIC CUP COMPETITIONS

Support competition-specific domestic cup formats.

Implement:
- Single-match knockout.
- Two-legged knockout.
- Multi-round knockout tournaments.
- Preliminary rounds.
- Byes.
- Different numbers of entrants.
- Quarter-finals, semi-finals, and finals.
- Optional third-place matches if supported by the competition.
- Neutral venues.
- Extra time and penalty shootouts.
- Correct winner progression.

A knockout tournament must never generate league-style return fixtures unless the competition configuration explicitly requires two legs.

For a single-match tie:
- Generate exactly one fixture.
- Determine the winner according to the competition rules.
- Advance the winner to the next round.

For a two-legged tie:
- Generate exactly two fixtures for the same pair of clubs.
- Reverse home and away assignments for the second leg.
- Calculate aggregate scores correctly.
- Apply the competition's actual tie-breaking rules.
- Do not automatically apply the away-goals rule.

If the number of entrants does not fit the bracket size, implement byes or preliminary rounds correctly.

Never create duplicate ties or advance a club twice.

# PHASE 6: CONTINENTAL COMPETITIONS AND UEFA-STYLE FORMATS

Support both traditional competition formats and modern league-phase formats.

Examples include:
- UEFA Champions League.
- UEFA Europa League.
- UEFA Conference League.
- AFC Champions League Elite.
- AFC Champions League Two.
- AFC Challenge League.
- Other continental competitions already present in the game database.

Do not assume all AFC and UEFA competitions use identical rules.

Read the existing competition database and implement formats according to the relevant competition configuration.

## A. UEFA-Style League Phase

Support the following configurable format profiles for the relevant 36-club editions:

Champions League:
- 36 participating clubs.
- 8 distinct opponents per club.
- 4 home matches.
- 4 away matches.

Europa League:
- 36 participating clubs.
- 8 distinct opponents per club.
- 4 home matches.
- 4 away matches.

Conference League:
- 36 participating clubs.
- 6 distinct opponents per club.
- 3 home matches.
- 3 away matches.

These are competition-specific reference profiles, not universal assumptions for all seasons or tournaments.

Requirements:
- Generate the complete opponent list before scheduling matchdays.
- Never repeat an opponent within the same league phase.
- Respect association restrictions where required.
- Respect competition-specific opponent-selection and seeding rules where supported.
- Ensure home-away totals match the competition format.
- Prevent a club from appearing twice in the same round.
- Generate valid fixtures for all participating clubs.
- Validate the complete fixture list before saving it.
- Keep the league-phase table and standings logic consistent with the generated matches.

Do not generate opponents independently on each matchday.

If the current game has qualification, seeding, or opponent-selection rules already implemented, preserve and integrate them.

## B. Traditional Group Stage

Support groups with configurable numbers of clubs.

For a group of G clubs:
- Single round-robin: G - 1 matches per club.
- Double round-robin: 2 × (G - 1) matches per club.
- Generate each opponent pairing exactly once or twice, according to the configured format.
- Apply BYE rounds if necessary.
- Support group-specific standings and qualification rules.

## C. Continental Knockout Stages

Support:
- Two-legged rounds.
- Single-match finals.
- Configurable neutral venues.
- Extra time and penalties.
- Aggregate scores.
- Correct advancement to subsequent rounds.
- Competition-specific rules for each round.

Do not automatically make every knockout round a two-legged tie.

# PHASE 7: SUPER CUPS AND SPECIAL CLUB COMPETITIONS

Support the correct scheduling structure for:
- Domestic super cups.
- UEFA Super Cup.
- FIFA Intercontinental Cup.
- FIFA Club World Cup.
- Other special tournaments already implemented in the game.

Use a separate competition configuration for each tournament.

## Single-Match Finals

A single-match final must:
- Have exactly one fixture.
- Support a neutral venue.
- Use extra time and penalties when specified by competition rules.
- Produce exactly one winner.
- Never generate a return fixture automatically.

## FIFA Club World Cup-Style Format

For competitions using a group stage followed by knockout rounds:
- Generate the configured number of groups.
- Assign participating clubs according to the tournament format.
- Generate the correct number of group fixtures.
- Support single round-robin groups where required.
- Apply the correct qualification rules.
- Generate the knockout bracket from qualified clubs.
- Use single-match knockout fixtures when specified by the tournament format.
- Schedule the final as one match.

## FIFA Intercontinental Cup-Style Format

Implement a configurable multi-stage bracket.

Do not treat the tournament as a conventional domestic league or automatically generate a home-and-away match for every pair.

Use the existing competition rules and data to determine:
- Which clubs enter at each stage.
- Which clubs receive byes.
- Which matches are played at neutral venues.
- Which winners advance.
- How the final is scheduled.

# PHASE 8: UNIFIED GLOBAL FOOTBALL CALENDAR

Create or improve a centralized calendar that combines all fixtures from all competitions.

A club may participate in:
- Domestic league.
- Domestic cup.
- Continental competition.
- Domestic super cup.
- International club competition.
- Other tournaments supported by the game.

All these fixtures must be coordinated through one scheduling system.

## Mandatory Rules

- A club must never be scheduled for two matches at the same time.
- A club must never be assigned conflicting fixtures on the same matchday unless the existing game explicitly supports separate dates and times.
- Schedule matches according to competition calendars.
- Enforce configurable minimum rest periods.
- Prefer at least 72 hours between matches when practical.
- Avoid unavailable dates and configured international breaks.
- Avoid scheduling matches on dates blocked by other competitions.
- Avoid excessive fixture congestion.
- Preserve valid competition ordering and knockout dependencies.
- Maintain consistent season dates.
- Ensure every scheduled match belongs to the correct competition and season.

Do not silently discard fixtures when conflicts occur.

When a conflict is detected:
1. Attempt to find an alternative valid date.
2. Recheck all affected club calendars.
3. Preserve competition-specific constraints.
4. Record the rescheduling reason.
5. Report unresolved conflicts.

The system must distinguish between:
- Competition round number.
- Calendar date.
- Actual kickoff time.
- Fixture status.
- Match completion status.

Do not use a single global matchday counter as the only representation of every competition's schedule.

# PHASE 9: POSTPONEMENTS AND RESCHEDULING

Implement safe handling of postponed fixtures.

Requirements:
- Preserve the original fixture identity.
- Preserve the competition and season association.
- Change the scheduled date without duplicating the fixture.
- Do not regenerate the entire competition when one fixture is postponed.
- Prevent conflicts with other matches involving the same clubs.
- Recalculate affected calendar conflicts.
- Preserve completed results.
- Update standings only when the match is actually completed.
- Ensure knockout progression waits for the relevant match result.
- Ensure league completion checks account for postponed fixtures.

A postponed match must not accidentally count as both played and scheduled.

# PHASE 10: SEASON PROGRESSION AND MATCH SIMULATION

Separate fixture generation from match simulation.

The fixture system decides:
- Which clubs play.
- Which club is the home team.
- Which club is the away team.
- Which competition the match belongs to.
- When the match is scheduled.

The simulation system decides:
- Match events.
- Goals.
- Cards.
- Injuries.
- Final score.
- Match statistics.

The simulation system must not create new opponents or regenerate fixtures.

When the player advances the game:
1. Find fixtures that are due.
2. Validate that both clubs are eligible to play.
3. Verify that the fixture has not already been completed.
4. Simulate the match once.
5. Persist the result.
6. Update standings and statistics.
7. Advance knockout competitions when appropriate.
8. Update the calendar.
9. Preserve fixture identity and history.

Repeatedly pressing Continue or reloading the save must never duplicate completed matches or alter the scheduled opponents.

Use database transactions to prevent partially persisted results and inconsistent competition states.

# PHASE 11: DATABASE INTEGRITY AND MIGRATIONS

Inspect the current SQLite database schema before changing it.

Preserve existing data and saved games.

Requirements:
- Reuse existing tables and columns wherever practical.
- Introduce migrations only when necessary.
- Do not drop tables containing existing game data.
- Do not reset the entire database.
- Add appropriate indexes and unique constraints.
- Validate foreign-key relationships.
- Prevent duplicate fixture generation.
- Persist competition configuration where appropriate.
- Preserve existing match results and statistics.
- Preserve player, club, competition, and season relationships.
- Ensure interrupted fixture generation can be rolled back safely.

If existing fixtures are malformed:
- Detect the affected competitions.
- Identify the exact integrity violations.
- Repair only what can be safely reconstructed.
- Preserve completed match results.
- Do not overwrite valid fixtures unnecessarily.
- Report cases requiring manual intervention.

Use transactions for multi-step fixture generation and database updates.

# PHASE 12: AUTOMATED FIXTURE VALIDATION

Implement a dedicated fixture validator.

The validator must check:

## League Validation
- Correct number of fixtures.
- Correct number of rounds.
- Complete opponent coverage.
- No duplicate pairings beyond the configured number of meetings.
- Correct home-away reversal.
- Correct home-away totals.
- No club playing twice in one competition round.
- Correct handling of odd-numbered leagues.
- No invalid club references.

## League-Phase Validation
- Correct number of participating clubs.
- Correct number of opponents per club.
- No repeated opponents.
- Correct home-away totals.
- No duplicate or missing fixtures.
- No invalid association pairings where restrictions apply.

## Knockout Validation
- Correct number of legs.
- Correct pairing between legs.
- Correct home-away reversal for two-legged ties.
- Correct aggregate calculations.
- Correct winner determination.
- No duplicate advancement.
- No missing bracket participants.

## Global Calendar Validation
- No overlapping matches for the same club.
- No impossible competition dependencies.
- Correct match dates.
- Appropriate rest periods where possible.
- No duplicate fixture IDs.
- No completed fixture simulated twice.
- No invalid season or competition references.

Validation must produce actionable error messages identifying:
- Competition.
- Season.
- Fixture.
- Club.
- Round.
- Nature of the violation.

Do not merely return a generic boolean when the fixture list is invalid.

# PHASE 13: AUTOMATED TEST SUITE

Add unit tests and integration tests using the project's existing testing framework.

At minimum, test:

1. A 20-club double round-robin league.
2. An 18-club double round-robin league.
3. A 12-club double round-robin league.
4. An 8-club double round-robin league.
5. An odd-numbered league.
6. Single round-robin scheduling.
7. Double round-robin home-away reversal.
8. Consecutive home-away balancing.
9. No duplicate fixtures.
10. No missing opponent pairings.
11. UEFA-style league-phase opponent uniqueness.
12. Correct home-away distribution for continental league phases.
13. Single-match knockout progression.
14. Two-legged knockout progression.
15. Aggregate-score calculations.
16. Extra time and penalties when required.
17. Neutral-venue finals.
18. Byes in knockout brackets.
19. Postponed fixtures.
20. Rescheduling conflicts.
21. Global calendar conflicts.
22. Saving and reloading a game.
23. Repeated Continue operations.
24. Interrupted fixture generation.
25. Existing saved-game compatibility.

Include property-based or randomized-input tests where practical, but use fixed seeds and deterministic assertions.

The tests must verify the mathematical correctness of fixture generation, not merely that the application runs without crashing.

# PHASE 14: PERFORMANCE AND ARCHITECTURE

The fixture system must remain efficient as the number of clubs and competitions grows.

Requirements:
- Avoid unnecessary full-database scans.
- Use indexes for fixture lookups.
- Avoid regenerating complete schedules unnecessarily.
- Keep scheduling logic out of UI widgets.
- Keep fixture generation separate from match simulation.
- Use clear service or repository boundaries consistent with the existing architecture.
- Avoid unnecessary dependencies.
- Do not block the UI with expensive scheduling operations.
- Maintain predictable behavior when loading and saving games.

Prefer straightforward, maintainable algorithms over premature complexity.

# PHASE 15: BACKWARD COMPATIBILITY

The project already contains competition data and potentially existing saves.

Do not assume a fresh installation.

Requirements:
- Preserve existing club and player IDs.
- Preserve existing competition IDs.
- Preserve valid historical match results.
- Preserve completed fixtures.
- Preserve league standings when they are already valid.
- Migrate existing data safely.
- Do not reset the current season without a valid reason.
- Do not delete existing competitions to simplify implementation.
- Document any migration that cannot preserve every existing field.

If an existing competition has a format that the new system cannot identify, report the issue and use a safe, explicit fallback rather than silently changing its rules.

# PHASE 16: IMPLEMENTATION WORKFLOW

Follow this workflow:

1. Inspect the repository and database schema.
2. Trace the existing fixture-generation flow.
3. Identify root causes.
4. Define the minimum required architectural changes.
5. Implement or repair fixture generation.
6. Implement home-away balancing.
7. Implement competition-specific scheduling.
8. Integrate the unified calendar.
9. Implement fixture validation.
10. Add database migrations if needed.
11. Add automated tests.
12. Run the tests.
13. Validate existing competition data.
14. Fix regressions.
15. Report the results.

Do not stop after producing an audit report or implementation plan.

Proceed with actual implementation using the tools available in the current development environment.

Do not modify unrelated UI or gameplay features unless a change is necessary for fixture integrity.

# FINAL ACCEPTANCE CRITERIA

The implementation is considered successful only when:

- Domestic leagues have complete and mathematically correct fixture lists.
- Home and away matches are balanced whenever possible.
- Return fixtures reverse home and away assignments.
- Competition formats are configured independently.
- Knockout competitions progress correctly.
- Continental league phases do not repeat opponents.
- Finals do not receive accidental return fixtures.
- The global calendar prevents conflicting matches.
- Postponements do not corrupt the season.
- Fixture generation is deterministic and idempotent.
- Existing completed match results are preserved.
- Reloading and advancing the game does not duplicate fixtures.
- Database migrations preserve existing data.
- Automated tests pass.
- Remaining limitations are explicitly documented.

# FINAL REPORT

After implementation, provide:

1. Root causes of the irregular scheduling.
2. Files modified.
3. Changes to the database schema.
4. Algorithms implemented.
5. Competition formats supported.
6. Automated tests executed and their actual results.
7. Validation results for existing competitions.
8. Any unresolved issues.
9. Any remaining manual steps required.

Be precise about what was actually implemented and tested. Never claim that tests passed unless they were executed successfully.