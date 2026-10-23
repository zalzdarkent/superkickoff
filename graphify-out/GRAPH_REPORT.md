# Graph Report - superkickoff  (2026-10-23)

## Corpus Check
- 138 files · ~98,855 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 52 file(s) not represented in the graph (top: .xcconfig 8, (none) 7, .xml 7)

## Summary
- 1862 nodes · 2495 edges · 76 communities (60 shown, 16 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.9)
- Token cost: 1,200 input · 850 output

## Community Hubs (Navigation)
- Core Data Models
- Career State & Flow Management
- Match Simulation Engine
- SQLite Database Schema & Tables
- Repository Interfaces & Storage
- Match & Transfer News Generation
- Season & Fixture Generation
- Career Onboarding & Setup UI
- SQLite Database Initialization & Connection
- Squad & Lineup Repository
- Match Screen & Live Animation
- Tournament Awards & Prize Pool Engine
- iOS & macOS Flutter Runner
- Standings & League Table UI
- Club Hub & Youth Academy
- Tactical Formations & Squad Lineup UI
- App Entry & Live Match Session
- Season History & Competition Stats UI
- Home Dashboard & Tab Navigation
- Linux Desktop Runner & Engine
- Season Persistence & Progression
- Transfer Market & Scouting UI
- Player Profile & Contract Sheet
- Career Flow End-to-End Tests
- Inbox & Notification Messages UI
- Home Screen Drawer & Filtering
- Indonesian Teams & Awards Tests
- Tournament Knockout Bracket UI
- Windows Native Window Implementation
- Windows Flutter Controller
- Player Training & Fitness Sheet
- Main App & Overview Cards
- Common Reusable UI Widgets
- Fixtures Schedule & Matchday UI
- News Feed & Activity Log UI
- Tactical Formations Engine
- Training Drills & Conditioning Logic
- Reference Data & League Lookup
- Scouting Network & Staff Repository
- Continental Competitions Integration Tests
- Windows Native Application Entry
- Database Schema Migration Tools
- Transfer & Loan Repository
- Fixture Scheduling & Scroll Tests
- UI Theme & Design System
- Win32 Window Lifecycle & Sizing
- Web App Manifest & Metadata
- Prize & Revenue Repository
- Sponsorship & Scouting Integration Tests
- Win32 DPI & Event Handling
- User Messaging & Inbox Repository
- Sponsorship Contracts Repository
- Match Engine Unit Tests
- News Feed Storage Repository
- News Engine Unit Tests
- Windows Plugin Registrant
- Core Formatting Utilities
- Geometry Point Types
- Geometry Size Types
- Android Application Native Runner
- Countries & Database Schema Concept
- News System Concept & Repository
- Competition & Season Generator Concept
- Sponsorship System Concept
- Transfer Market System Concept
- Career Service & Core Loop Concept
- Tactics & Formation Concept
- Match Simulation Engine Concept
- League Table Widget State
- Project Documentation & Overview

## God Nodes (most connected - your core abstractions)
1. `CareerProvider` - 80 edges
2. `_` - 44 edges
3. `Win32Window` - 21 edges
4. `main()` - 11 edges
5. `FlutterWindow` - 10 edges
6. `_MyApplication` - 7 edges
7. `WindowClassRegistrar` - 7 edges
8. `AppDelegate` - 5 edges
9. `Team` - 5 edges
10. `Tournament` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Core Gameplay Loop` --conceptually_related_to--> `CareerProvider`  [INFERRED]
  PRD_Superkickoff_Clone.md → lib/state/career_provider.dart
- `Sponsorship & Club Finance System` --conceptually_related_to--> `SponsorshipRepository`  [INFERRED]
  PRD_Superkickoff_Clone.md → lib/data/repositories/sponsorship_repository.dart
- `Tactics & Formation System` --conceptually_related_to--> `Formation`  [INFERRED]
  PRD_Superkickoff_Clone.md → lib/game/formation.dart
- `Offline-First SQLite Architecture` --conceptually_related_to--> `AppDatabase`  [INFERRED]
  PRD_Superkickoff_Clone.md → lib/data/db/app_database.dart
- `Database Schema Specification` --conceptually_related_to--> `countries`  [INFERRED]
  PRD_Superkickoff_Clone.md → lib/data/db/schema.dart

## Import Cycles
- None detected.

## Communities (76 total, 16 thin omitted)

### Community 0 - "Core Data Models"
Cohesion: 0.01
Nodes (243): abbreviation, age, aggregateFor, appearanceBonus, appearances, assistBonus, assists, atMaxCapacity (+235 more)

### Community 1 - "Career State & Flow Management"
Cohesion: 0.01
Nodes (154): FixtureMatch, ManagerProfile, acceptCounterOffer, acceptLoanOffer, acceptSaleOffer, activeSponsorships, allCountries, allMarketPlayers (+146 more)

### Community 2 - "Match Simulation Engine"
Cohesion: 0.02
Nodes (106): Player, assist, assists, _attackerInjuryBias, attackOn, attendanceBoxes, attendanceGeneral, attendanceStand (+98 more)

### Community 3 - "SQLite Database Schema & Tables"
Cohesion: 0.02
Nodes (82): academyProspects, awardMvp, awardTopScorer, awardYoungPlayer, careerHistory, coaches, coachTransfers, competitionPrizeAwards (+74 more)

### Community 4 - "Repository Interfaces & Storage"
Cohesion: 0.03
Nodes (53): _ageAndRetire, _applyPromotionRelegation, _awardCompetitionPrizes, _competitionProfile, completeSeason, _cupTournaments, db, _engine (+45 more)

### Community 5 - "Match & Transfer News Generation"
Cohesion: 0.03
Nodes (58): ag, ap, away, awayId, _confederations, _Ctx, _cupRegions, _cupRun (+50 more)

### Community 6 - "Season & Fixture Generation"
Cohesion: 0.04
Nodes (48): Season, addInternationalCups, all, away, _ChampionsFeed, _championsFeeds, _championsOf, _continentalQualifiers (+40 more)

### Community 7 - "Career Onboarding & Setup UI"
Cohesion: 0.04
Nodes (45): allCountries, _bottomBar, build, _clubStep, countries, _CountrySheet, _CountrySheetState, createState (+37 more)

### Community 8 - "SQLite Database Initialization & Connection"
Cohesion: 0.04
Nodes (32): AppDatabase, assetRevision, beginSession, close, _db, dbName, ensureLocalTables, finishSession (+24 more)

### Community 9 - "Squad & Lineup Repository"
Cohesion: 0.05
Nodes (43): _academyName, allMarketPlayers, applyMatchFatigue, buyMarketPlayer, clearLineup, clubOverview, db, _ensureTacticsTable (+35 more)

### Community 10 - "Match Screen & Live Animation"
Cohesion: 0.05
Nodes (35): build, _celebrationBanner, color, ConfettiOverlay, _ConfettiOverlayState, _ConfettiPainter, _ConfettiParticle, _controller (+27 more)

### Community 11 - "Tournament Awards & Prize Pool Engine"
Cohesion: 0.05
Nodes (40): PrizeRepository, _, _addTo, amount, awards, basePool, championBonus, CompetitionKind (+32 more)

### Community 12 - "iOS & macOS Flutter Runner"
Cohesion: 0.06
Nodes (14): Cocoa, Flutter, FlutterMacOS, Foundation, AppDelegate, SceneDelegate, RunnerTests, RegisterGeneratedPlugins() (+6 more)

### Community 13 - "Standings & League Table UI"
Cohesion: 0.05
Nodes (33): CompetitionStats, _buildLegend, _cell, color, createState, emptyHint, game, _gdWidth (+25 more)

### Community 14 - "Club Hub & Youth Academy"
Cohesion: 0.07
Nodes (35): YouthAcademyState, CareerProvider, _academy, _academyTab, build, _busy, ClubHubSheet, _ClubHubSheetState (+27 more)

### Community 15 - "Tactical Formations & Squad Lineup UI"
Cohesion: 0.06
Nodes (30): _bench, _benchChip, build, createState, didChangeDependencies, _formationTab, _getSortedPlayers, group (+22 more)

### Community 16 - "App Entry & Live Match Session"
Cohesion: 0.07
Nodes (16): _BootGate, build, main, LiveMatchSession, _awayColor, build, MatchStatsSheet, _percent (+8 more)

### Community 17 - "Season History & Competition Stats UI"
Cohesion: 0.06
Nodes (28): _body, build, _cell, _competition, _competitionId, _competitions, _competitionSelector, createState (+20 more)

### Community 18 - "Home Dashboard & Tab Navigation"
Cohesion: 0.07
Nodes (18): _body, build, createState, game, _index, _leaveCareer, _nextMatchCard, onOpenInbox (+10 more)

### Community 19 - "Linux Desktop Runner & Engine"
Cohesion: 0.09
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 20 - "Season Persistence & Progression"
Cohesion: 0.07
Nodes (29): addMatches, addSeasonTeams, ageSquad, allSeasons, archiveSeasonTournament, _awardsFromRows, careerHistory, clubAwards (+21 more)

### Community 21 - "Transfer Market & Scouting UI"
Cohesion: 0.07
Nodes (26): allPlayers, _allPlayersTab, createState, _deployScoutDialog, dispose, error, _future, _listedTab (+18 more)

### Community 22 - "Player Profile & Contract Sheet"
Cohesion: 0.09
Nodes (22): _bonus, build, _content, _contractTab, createState, dispose, _future, _historyTab (+14 more)

### Community 23 - "Career Flow End-to-End Tests"
Cohesion: 0.13
Nodes (12): db, firstInt, main, tempDir, fx, main, main, db (+4 more)

### Community 24 - "Inbox & Notification Messages UI"
Cohesion: 0.09
Nodes (17): build, InboxScreen, InboxTab, _messageDialog, _offerActions, _openMessage, _showAcademyIntakeSheet, _showContractDialog (+9 more)

### Community 25 - "Home Screen Drawer & Filtering"
Cohesion: 0.13
Nodes (19): HomeScreen, _HomeScreenState, _FilterDrawer, _FilterDrawerState, MarketTab, _MarketTabState, _TransferHistory, _TransferHistoryState (+11 more)

### Community 26 - "Indonesian Teams & Awards Tests"
Cohesion: 0.19
Nodes (7): main, _budget, main, rows, main, main, main

### Community 27 - "Tournament Knockout Bracket UI"
Cohesion: 0.11
Nodes (18): KnockoutTie, Team, Tournament, build, champion, firstPhase, firstRoundMatches, knockoutRoundName (+10 more)

### Community 28 - "Windows Native Window Implementation"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 29 - "Windows Flutter Controller"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 30 - "Player Training & Fitness Sheet"
Cohesion: 0.12
Nodes (15): TrainingState, build, _busy, _content, createState, _focus, _future, initState (+7 more)

### Community 31 - "Main App & Overview Cards"
Cohesion: 0.11
Nodes (17): SuperkickoffApp, MiniStandingsCard, OverviewTab, _ChampionColumn, _KnockoutBracketSheet, _MatchCard, _RoundColumn, _PlayerMarketCard (+9 more)

### Community 32 - "Common Reusable UI Widgets"
Cohesion: 0.11
Nodes (16): action, build, child, _colorFor, items, labelFor, positionId, profile (+8 more)

### Community 33 - "Fixtures Schedule & Matchday UI"
Cohesion: 0.12
Nodes (14): build, createState, _currentWeekKey, didChangeDependencies, _fixtureRow, fixtures, FixturesTab, _FixturesTabState (+6 more)

### Community 34 - "News Feed & Activity Log UI"
Cohesion: 0.12
Nodes (15): NewsItem, build, createState, _feed, _feeds, game, item, lead (+7 more)

### Community 35 - "Tactical Formations Engine"
Cohesion: 0.12
Nodes (14): all, defenders, f343, f352, f4231, f433, f442, f532 (+6 more)

### Community 36 - "Training Drills & Conditioning Logic"
Cohesion: 0.13
Nodes (12): cost, description, fitnessGain, fromKey, isFitness, label, maxPlayers, positionIds (+4 more)

### Community 37 - "Reference Data & League Lookup"
Cohesion: 0.13
Nodes (14): allCountries, countryById, db, internationalCups, leagueRegion, leaguesForCountry, nationalCup, playableCountries (+6 more)

### Community 38 - "Scouting Network & Staff Repository"
Cohesion: 0.14
Nodes (12): availableScoutsToHire, db, deployScout, fireScout, hiredScouts, hireScout, hiringCostForStars, pendingWonderkids (+4 more)

### Community 39 - "Continental Competitions Integration Tests"
Cohesion: 0.18
Nodes (7): db, dir, main, refs, db, main, tempDir

### Community 40 - "Windows Native Application Entry"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 41 - "Database Schema Migration Tools"
Cohesion: 0.28
Nodes (7): drop_legacy_objects(), main(), rebuild_indexes(), rebuild_triggers_and_views(), rename_columns(), rename_tables(), translate_reference_data()

### Community 42 - "Transfer & Loan Repository"
Cohesion: 0.17
Nodes (10): completeLoan, completeTransfer, createOffer, db, getOffer, loanEndYear, pendingOffersForTeam, _todayIso (+2 more)

### Community 43 - "Fixture Scheduling & Scroll Tests"
Cohesion: 0.17
Nodes (10): CareerPlan, countryId, db, FakeCareerProvider, generator, main, plan, seasonFixtures (+2 more)

### Community 44 - "UI Theme & Design System"
Cohesion: 0.17
Nodes (9): accent, accentDim, AppTheme, build, danger, surface, surfaceCard, textDim (+1 more)

### Community 46 - "Win32 Window Lifecycle & Sizing"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 47 - "Web App Manifest & Metadata"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 48 - "Prize & Revenue Repository"
Cohesion: 0.20
Nodes (7): awardsForTeam, db, overrides, paidAwards, pay, totalPrizeIncome, _weights

### Community 49 - "Sponsorship & Scouting Integration Tests"
Cohesion: 0.20
Nodes (6): ScoutingRepository, db, dir, main, scouting, sponsorships

### Community 51 - "User Messaging & Inbox Repository"
Cohesion: 0.22
Nodes (7): db, insert, latest, markRead, MessageRepository, _todayIso, unreadCount

### Community 52 - "Sponsorship Contracts Repository"
Cohesion: 0.25
Nodes (6): activeSponsorships, availableOffers, db, evaluateSeasonTargets, payWeekly, signSponsorship

### Community 53 - "Match Engine Unit Tests"
Cohesion: 0.29
Nodes (3): buildSquad, main, positions

### Community 54 - "News Feed Storage Repository"
Cohesion: 0.33
Nodes (4): db, feed, hasRef, insertAll

### Community 55 - "News Engine Unit Tests"
Cohesion: 0.33
Nodes (3): db, dir, main

### Community 57 - "Core Formatting Utilities"
Cohesion: 0.50
Nodes (3): money, shortDate, substring

### Community 58 - "Geometry Point Types"
Cohesion: 0.50
Nodes (3): Point, x, y

### Community 59 - "Geometry Size Types"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 61 - "Countries & Database Schema Concept"
Cohesion: 0.67
Nodes (3): countries, Country, Database Schema Specification

### Community 62 - "News System Concept & Repository"
Cohesion: 0.67
Nodes (3): NewsRepository, NewsEngine, News & Notification Engine

### Community 63 - "Competition & Season Generator Concept"
Cohesion: 0.67
Nodes (3): SeasonRepository, SeasonGenerator, Competitions & Fixture Generation Engine

## Knowledge Gaps
- **1348 isolated node(s):** `money`, `shortDate`, `substring`, `dbName`, `assetRevision` (+1343 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1469 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Country` connect `Countries & Database Schema Concept` to `Core Data Models`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **What connects `money`, `shortDate`, `substring` to the rest of the system?**
  _1348 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Core Data Models` be split into smaller, more focused modules?**
  _Cohesion score 0.008097165991902834 - nodes in this community are weakly interconnected._
- **Why does `countries` connect `Countries & Database Schema Concept` to `SQLite Database Schema & Tables`?**
  _High betweenness centrality (0.082) - this node is a cross-community bridge._
- **Should `Career State & Flow Management` be split into smaller, more focused modules?**
  _Cohesion score 0.012578616352201259 - nodes in this community are weakly interconnected._
- **Should `Match Simulation Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.018691588785046728 - nodes in this community are weakly interconnected._
- **Should `SQLite Database Schema & Tables` be split into smaller, more focused modules?**
  _Cohesion score 0.024096385542168676 - nodes in this community are weakly interconnected._