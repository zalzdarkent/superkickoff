# Task: International Football Calendar, National Teams & Call-Ups

## Project context

This task is for the existing Flutter/Dart football manager game. The
game already has club competitions, player squads, a season calendar,
match simulation, a SQLite database, transfer windows, and a fixture
scheduling system. Audit the actual repository and reuse its existing
architecture and data.

## Objective

Implement a complete international football system inspired by EA SPORTS
FC Career Mode and real-world national-team football.

The system must include:

-   FIFA international match windows and international friendlies.
-   National-team player selection and call-ups from club squads.
-   Mandatory player release during applicable international windows and
    final tournaments.
-   World Cup qualifying and final tournament.
-   Continental competitions and qualifiers, including UEFA EURO, UEFA
    Nations League, AFC Asian Cup, and other competitions supported by
    the game's data.
-   Southeast Asian international competitions, including the ASEAN
    Championship and FIFA ASEAN Cup.
-   International rankings, squad management, match results, and
    competition progression where supported by the existing game.
-   Coordination between international fixtures and club fixtures.
-   Player availability, travel, fatigue, injuries, and return to club
    duty.
-   A unified calendar that prevents impossible overlaps.

**Do not assume every competition follows the same format.** Competition
rules and calendars must be configurable by competition and edition. The
examples below are reference profiles; use the correct configured rules
for the relevant season and avoid hardcoding rules that may change.

## Phase 1 --- Audit before implementation

Inspect the existing project and database before changing code.

Audit:

1.  Player model fields for nationality, secondary nationality,
    international eligibility, age, position, OVR, potential, fitness,
    fatigue, injury, and current club.
2.  Whether players can represent national teams and whether
    national-team entities already exist.
3.  Club, league, competition, season, fixture, match-result, calendar,
    and save-game models.
4.  Existing fixture generator and global calendar.
5.  Match simulation and player-statistics persistence.
6.  Existing player availability and injury systems.
7.  Existing season progression and Continue/Advance Date behavior.
8.  Competition database and country/confederation associations.
9.  Existing transfer and registration systems.
10. Existing national-team or international competition code, if any.

Trace the complete lifecycle from international calendar generation to
call-up, player release, national-team match simulation, return to club
duty, and season progression.

Identify the smallest safe set of changes. Do not rewrite unrelated
systems, reset the database, or delete existing game data.

## Phase 2 --- International match calendar

Create a centralized, season-aware international calendar.

Support configurable calendar events such as:

-   FIFA international windows.
-   International friendly matches.
-   World Cup qualifying.
-   Continental championship qualifying.
-   Nations League matches.
-   Continental championship final tournaments.
-   World Cup final tournaments.
-   Regional tournaments.
-   Confederation or federation tournaments.
-   Play-offs.
-   Preparation camps and release/travel periods where the game models
    them.

Each calendar event should define, as appropriate:

-   Event ID and season/edition.
-   Start and end dates.
-   Governing body and confederation.
-   Event type.
-   Whether it is an official competition or a friendly window.
-   Maximum matches permitted per national team.
-   Eligible participating national teams.
-   Whether club player release is mandatory under the configured rules.
-   Player release start and return-to-club date.
-   Whether club fixtures should be avoided, postponed, or left
    unchanged under the competition rules.
-   Rest intervals between international matches.
-   Qualification or tournament dependencies.

Use FIFA's published International Match Calendar as a reference for
men's and women's calendar profiles. Do not hardcode one year's dates as
a permanent calendar. Store calendar profiles by season and allow future
editions to be configured.

As a reference for the men's calendar structure approved for 2025--2030,
FIFA describes windows in March, June, late September/early October, and
November; from 2026, the late September/early October window is 16 days
and can accommodate up to four matches. The exact dates and exceptions
must come from the configured edition rather than being assumed for
every year.

Official reference:
https://inside.fifa.com/tournament-organisation/international-match-calendars

## Phase 3 --- National-team and player eligibility model

Implement or extend national-team data structures without duplicating
players.

A national team should reference existing player records. Do not create
separate copies of players for international football.

Support, where the current game data allows:

-   Primary nationality.
-   Secondary nationality or eligible national associations.
-   Current national-team allegiance.
-   Eligibility status.
-   Senior, youth, and other representative levels if supported.
-   International caps, goals, appearances, and match history.
-   Call-up status.
-   Squad number and position/role in the national-team squad.

Eligibility rules must be explicit and configurable. Do not select a
player for a country solely because the player's club is located there.

If nationality or eligibility data is missing, do not invent it
silently. Use the best available existing fields, document limitations,
and provide a safe fallback.

If the game does not model nationality changes or complex eligibility
rules, implement a straightforward eligibility system first and leave
advanced eligibility changes behind a clear extension point.

## Phase 4 --- National-team selection and call-ups

Create a national-team selection service that selects suitable eligible
players from clubs.

The selection system should consider:

-   Player eligibility and nationality.
-   OVR/current ability.
-   Position and squad balance.
-   Current form.
-   Recent appearances and minutes.
-   Fitness, fatigue, and injury status.
-   Player age and development.
-   Existing national-team status and experience.
-   Competition importance.
-   Tactical formation and preferred roles.
-   The national team's playing style and manager preferences, if
    modeled.

Provide a configurable squad-size range. Use 23 players as a sensible
default profile for many senior tournaments, but allow the competition
configuration to specify another size. Do not hardcode 23 for every
event or era.

Ensure the squad has enough goalkeepers and coverage across defensive,
midfield, and attacking positions. Do not simply select the 23
highest-OVR players regardless of positions.

Support: - Preliminary selections where appropriate. - Final squad
selection. - Call-up notifications. - Replacement call-ups for injuries
or ineligibility. - Player withdrawal where appropriate. - National-team
captain and squad roles where supported. - Human-managed national-team
selection if the game has a national-team management mode. -
AI-controlled national teams when the user manages only a club.

The system must not call up the same player into two overlapping
national-team fixtures or incompatible representative squads.

## Phase 5 --- Club player release and availability

When a player is called up, update their availability for club matches
based on the configured release period.

Rules:

1.  During a configured mandatory release period, eligible players must
    be released to their national teams when selected, subject to the
    game's competition rules.
2.  For events outside a mandatory release period, use configurable
    rules rather than assuming clubs must release every player.
3.  Track when a player leaves the club, joins the national team, plays,
    travels back, and becomes available again.
4.  Prevent a player from appearing for their club and national team at
    overlapping times.
5.  Keep player contracts, club registration, and club ownership
    unchanged during international duty.
6.  Do not treat an international call-up as a club transfer or
    permanent squad removal.
7.  Preserve the player's club squad membership while marking them
    unavailable for the relevant dates.
8.  Return the player to club availability automatically after the
    configured release and travel period.

If a national-team fixture conflicts with a club fixture: - Apply the
relevant configured release/calendar rule. - Prefer rescheduling club
matches where the game rules require or allow it. - If a club match is
not postponed, ensure a called-up player cannot be selected in the club
match during overlapping duty. - Never silently delete either fixture. -
Record the reason for postponement or unavailability.

The system must distinguish a player being unavailable due to
international duty from injury, suspension, fatigue, or tactical
omission.

## Phase 6 --- International friendlies

Implement international friendlies as a distinct fixture type.

Requirements:

-   Schedule friendlies inside eligible international windows by
    default.
-   Allow configurable exceptions for events outside windows.
-   Generate opponents according to a reasonable selection policy, not
    unrestricted randomness.
-   Consider confederation, approximate team strength, travel, previous
    opponents, and tournament preparation where data exists.
-   Avoid repeatedly generating the same opponent in adjacent windows
    unless intentionally configured.
-   Support one or two matches in a standard short window, or the
    configured maximum for the relevant window.
-   Respect minimum rest between international matches.
-   Support neutral venues and home/away designation.
-   Store results as senior international match records.
-   Do not award competition points or tournament qualification unless
    the configured competition rules say so.
-   Update player caps and international statistics only once after a
    match is completed.

Friendly matches should not be inserted into league standings or club
competition tables.

## Phase 7 --- International competitions and configurable formats

Create reusable competition-format components for national teams. Do not
duplicate separate scheduling logic for every tournament.

Support these categories where relevant to the existing database:

### A. FIFA World Cup

Support: - Qualification by confederation. - Group stages or
league-style qualifying formats. - Configurable play-offs. - Final
tournament. - Group standings and tie-breakers. - Knockout rounds. -
Extra time and penalties when specified. - Squad submission deadlines
and replacement rules as configurable competition settings. - Tournament
progression based on actual results.

The number of teams, groups, matchdays, and qualification slots must be
edition-specific. For the 2026 men's World Cup, the reference format is
48 teams in 12 groups of four, followed by a 32-team knockout stage. Do
not assume this format applies to every historical or future edition.

Official reference:
https://www.fifa.com/tournaments/mens/worldcup/canadamexicousa2026

### B. UEFA EURO

Support: - Qualification groups and/or play-offs according to the
configured edition. - Final tournament. - Group-stage standings. -
Qualification to knockout rounds. - Tie-breakers and knockout
progression. - Extra time and penalties where required.

Do not hardcode one qualification or final-tournament format across all
editions.

### C. UEFA Nations League

Support: - League tiers/divisions. - Groups within each league. -
Home-and-away group fixtures when required by the edition. - Points and
tie-breakers. - Promotion and relegation. - Finals or final-four stages
when applicable. - Promotion/relegation play-offs where applicable. -
Relationship to EURO or World Cup qualification only when explicitly
configured by the relevant rules.

Do not treat the Nations League as a single knockout tournament or a
standard one-off friendly competition.

Official reference: https://www.uefa.com/uefanationsleague/

### D. AFC Asian Cup

Support: - Qualification rounds and groups. - Configurable qualification
slots. - Final tournament. - Group stage and knockout rounds. - Host
qualification rules where applicable. - Edition-specific team counts and
formats.

Do not hardcode a fixed number of teams or qualification groups across
all editions.

Official reference:
https://www.the-afc.com/en/national/afc_asian_cup.html

### E. Southeast Asian national-team competitions

Support separate configurable competitions for: - ASEAN Championship /
AFF Championship. - FIFA ASEAN Cup. - FIFA ASEAN Challenge Cup or other
divisions, if present in the relevant edition and game database. - SEA
Games men's football, if the game includes age restrictions and this
competition.

Do not merge the ASEAN Championship and FIFA ASEAN Cup into one
competition. They are separate competitions with separate calendars and
regulations.

The inaugural FIFA ASEAN Cup edition announced for 2026 uses two
divisions with 14 national sides in total, including ASEAN members and
guest teams. Treat that as an edition-specific reference profile, not a
permanent rule. Later editions must be configurable.

For the ASEAN Championship, use its own configured edition rules, group
format, home/away arrangements, and knockout structure. Do not assume it
uses the FIFA ASEAN Cup format.

Official references: - FIFA ASEAN Cup:
https://www.fifa.com/en/tournaments - ASEAN Football Federation:
https://www.aseanfootball.org/

### F. Other confederation competitions

Use the same configurable engine for other national-team competitions
already present in the game, such as: - Africa Cup of Nations. -
CONCACAF Gold Cup. - Copa América. - AFC or regional qualifiers. -
Intercontinental play-offs. - FIFA Series or equivalent invitational
tournaments.

Only implement competitions supported by the project's existing database
or explicitly required by the project. Avoid fabricating participants,
formats, or calendar dates.

## Phase 8 --- Qualification and tournament progression

Implement qualification as data-driven rules.

Support: - Automatic qualification for hosts where applicable. -
Qualification by group position. - Qualification by aggregate score in
two-legged ties. - Qualification by play-offs. - Best third-place teams
where the format requires them. - Confederation-specific allocation of
slots. - Promotion and relegation for league-based competitions. -
Replacement of withdrawn or disqualified teams where rules specify it.

The qualification engine must use completed results and configured
tie-breakers. It must never advance teams based on random selection when
results are available.

Prevent a national team from being entered twice into the same edition
or assigned to an incompatible group.

If qualification rules are incomplete in the current database, report
the missing configuration instead of inventing a supposedly official
rule.

## Phase 9 --- International match simulation and player statistics

Reuse the existing match engine wherever possible.

International fixtures must use the same underlying player identities
and core match simulation as club matches, while supporting
national-team tactics and squad selection.

Requirements: - Use the national team's selected lineup and eligible
substitutes. - Do not use club teammates or club tactics automatically
unless appropriate for the national team. - Respect injuries,
suspensions, fitness, fatigue, and eligibility. - Persist match events
and final scores. - Update international caps, goals, assists, clean
sheets, and other supported statistics. - Do not accidentally update
club competition appearances or club standings with international
results. - Prevent duplicate simulation when the game is reloaded or the
user advances the date repeatedly. - Ensure knockout matches determine a
winner when required. - Support extra time and penalties only when
specified.

## Phase 10 --- International fatigue, injuries, and return to club

International duty should have meaningful but balanced effects.

Implement or integrate: - Match fatigue. - Travel fatigue where
supported. - Injury risk based on minutes, fitness, workload, and
existing injury systems. - Recovery time after international matches. -
Return-to-club availability. - A distinction between being selected,
travelling, playing, and recovering.

Do not guarantee injuries after international duty. Injury risk should
be probabilistic and consistent with the existing match engine.

Avoid applying the same fatigue or injury effect twice if a match is
reprocessed or a save is reloaded.

If the game does not have travel simulation, use a simpler configurable
return/recovery period rather than inventing excessive complexity.

## Phase 11 --- Unified club and international calendar

Integrate national-team fixtures with the existing club calendar.

The calendar must include: - Domestic league matches. - Domestic cup
matches. - Continental club matches. - Club super cups and international
club competitions. - International windows. - National-team
friendlies. - Qualifiers. - National-team final tournaments. - Player
release and return dates. - Postponed fixtures.

Rules: - Never schedule the same team for two matches at the same
time. - Never allow a player to play overlapping club and international
matches. - Account for mandatory player-release periods. - Avoid club
fixtures during international windows where the configured calendar
requires it. - Do not automatically postpone all club matches just
because an international window exists; follow the configured calendar
and competition rules. - Reschedule affected matches safely and preserve
their fixture IDs and results. - Maintain reasonable rest periods. -
Report unresolved conflicts rather than silently discarding fixtures.

A national-team competition may span multiple calendar weeks. The
calendar must handle the complete tournament period, not just the
opening matchday.

## Phase 12 --- National-team management UI

Follow the existing design system. Do not redesign unrelated screens.

Provide appropriate screens or sections for:

1.  National-team calendar.
2.  Upcoming international windows.
3.  National-team competition overview.
4.  National-team squad and call-ups.
5.  Player international career and statistics.
6.  Upcoming fixtures and results.
7.  Qualifying standings.
8.  Tournament groups and knockout bracket.
9.  Notifications for selected players.
10. Club player availability due to international duty.

If the game only supports managing a club, national teams can be
AI-managed in the background. The user should still be able to see
international schedules, call-ups of their club's players, results, and
player availability.

If national-team management is an existing feature, integrate these
screens with it instead of creating a parallel management system.

## Phase 13 --- Database design and migrations

Inspect the current SQLite schema first.

Reuse existing entities where practical. Introduce migrations only when
necessary.

Potential data concepts include: - National teams. - National-team
competition editions. - International calendar windows. - International
fixtures. - National-team squads and call-ups. - Player eligibility. -
International appearances and statistics. - Player release and return
periods. - Qualification groups and standings. - Tournament rounds and
bracket progression.

These are conceptual entities, not a requirement to create a separate
table for every item. Fit the implementation to the existing schema.

Requirements: - Preserve existing player and club IDs. - Preserve
existing competitions and completed results. - Avoid duplicate player
records. - Use foreign keys and indexes where appropriate. - Use
transactions for multi-step operations. - Make fixture generation
idempotent. - Prevent duplicate call-ups and duplicate international
appearances. - Keep historical international records associated with the
correct player, national team, competition, and edition. - Make
migrations safe for existing saves. - Do not reset the database.

## Phase 14 --- Automated tests

Add tests using the project's existing Flutter/Dart testing framework.

At minimum, test:

1.  A player is eligible only for configured national teams.
2.  A player is not called up solely because their club is in a
    particular country.
3.  National-team squads have valid position coverage.
4.  Squad size follows the competition configuration.
5.  The same player is not called up into overlapping fixtures.
6.  Mandatory release rules work for configured windows.
7.  Optional friendlies outside release windows follow configured rules.
8.  A called-up player cannot play an overlapping club match.
9.  Players return to club availability after their release period.
10. International friendlies do not affect club standings.
11. International results update international statistics exactly once.
12. Qualification standings and tie-breakers work correctly.
13. Tournament progression follows completed results.
14. Nations League promotion and relegation work when configured.
15. EURO, World Cup, Asian Cup, and regional competitions can use
    different formats.
16. ASEAN Championship and FIFA ASEAN Cup remain separate competitions.
17. Postponements preserve fixture identity and results.
18. Calendar conflicts are detected and reported.
19. Reloading a save does not duplicate call-ups, fixtures, or player
    statistics.
20. Existing saves remain loadable after database migration.
21. International duty affects player availability and fatigue without
    double application.
22. Edition-specific competition formats can change without modifying
    core scheduling code.

## Phase 15 --- Implementation workflow

Follow this sequence:

1.  Audit the repository and database.
2.  Report the current architecture and missing pieces briefly.
3.  Identify the root causes and minimum necessary changes.
4.  Implement the national-team data model and eligibility handling.
5.  Implement the international calendar.
6.  Implement call-up and player-release workflows.
7.  Integrate international fixtures with the match engine.
8.  Implement configurable competition formats and qualification
    progression.
9.  Integrate international duty with the global club calendar.
10. Add UI integration consistent with the existing app.
11. Add safe database migrations.
12. Add automated tests.
13. Run tests and fix regressions.
14. Validate existing competition data and saved-game compatibility.
15. Report actual implementation and test results.

Do not stop after writing an implementation plan. Continue with actual
code changes using the available development tools unless a genuine
blocker requires clarification.

## Acceptance criteria

The task is complete when:

-   International windows are generated from a season-aware calendar.
-   Eligible players can be called up from their actual clubs without
    creating duplicate player records.
-   Call-ups respect eligibility, position coverage, squad-size
    configuration, and player availability.
-   Player release and return-to-club periods are tracked correctly.
-   Club and national-team fixtures cannot overlap for the same player.
-   Friendlies, qualifiers, and final tournaments are distinct
    competition types.
-   Different national competitions use their own configurable formats.
-   FIFA World Cup, UEFA EURO, UEFA Nations League, AFC Asian Cup, ASEAN
    Championship, and FIFA ASEAN Cup can be represented without
    conflating their rules.
-   Tournament progression and qualification use actual results.
-   International statistics are persisted exactly once.
-   The unified calendar handles postponements and conflicts safely.
-   Existing club systems and saves continue to work.
-   Automated tests pass, and any unsupported rules or unresolved issues
    are documented.

## Final report

Provide: 1. Current architecture and root causes discovered. 2. Files
changed. 3. Database migrations. 4. International calendar and release
rules implemented. 5. National-team selection logic. 6. Competition
formats implemented. 7. Club-calendar integration. 8. Automated tests
executed and actual results. 9. Save-game compatibility results. 10.
Limitations and remaining work.

Never claim a test passed unless it was actually executed successfully.
