# TASK: Audit and Rebuild the Football Player Market Value System

Act as a senior football management game developer and football transfer-market economist.

Audit, repair, and improve the existing player Market Value (MV) system in this Flutter football manager game.

The current implementation produces unrealistic player market values, with some players reaching approximately $1 billion or more.

The objective is to create a realistic, dynamic, balanced, and explainable market valuation system inspired by real-world football transfer markets and football management games.

IMPORTANT:
- Inspect the existing codebase and SQLite database before making changes.
- Identify the actual root cause of excessive market values.
- Preserve existing players, clubs, competitions, player attributes, transfer histories, and saved games.
- Reuse existing systems wherever practical.
- Do not rebuild unrelated gameplay features.
- Do not reset the database.
- Do not arbitrarily assign a fixed market value based only on overall rating.
- Do not simply impose a hard maximum value on every player.
- Implement working code and automated tests.
- Run the tests and report actual results.

# PHASE 1: AUDIT THE EXISTING MARKET VALUE IMPLEMENTATION

Inspect the entire current player valuation and transfer economy implementation.

Identify:
1. Where player MV is initially generated.
2. Whether MV is stored in the database or calculated dynamically.
3. Whether player MV depends on overall rating, potential, age, position, attributes, reputation, or other factors.
4. Whether MV is recalculated every matchday, week, month, season, or transfer window.
5. Whether MV increases after player development.
6. Whether goals, assists, appearances, and match ratings influence MV.
7. Whether club reputation or league reputation affects MV.
8. Whether transfer fees influence subsequent MV calculations.
9. Whether transfer negotiations accidentally modify MV.
10. Whether contract duration, wages, release clauses, and player demand are considered.
11. Whether the system applies multiple multipliers repeatedly.
12. Whether the MV formula compounds the player's previous MV.
13. Whether integer overflow, floating-point errors, incorrect currency conversion, or unit inconsistencies exist.
14. Whether player potential is applied repeatedly instead of being treated as a bounded factor.
15. Whether player growth causes exponential market value inflation.
16. Whether generated youth players have unrealistic starting values.
17. Whether relegation, promotion, and club reputation changes are reflected correctly.
18. Whether old saved-game values are preserved or recalculated incorrectly.

Trace the full lifecycle from player creation to development, market valuation, transfer negotiations, and transfer completion.

Do not assume the problem is caused by a single multiplier. Identify the actual implementation errors before replacing the formula.

# PHASE 2: ESTABLISH CLEAR VALUE DEFINITIONS

Separate these concepts throughout the application:

1. Market Value:
   The estimated baseline value of a player's registration in the transfer market.

2. Transfer Fee:
   The actual agreed fee for a completed transfer.

3. Asking Price:
   The amount requested by the selling club.

4. Negotiated Transfer Price:
   The final amount agreed upon by the buying and selling clubs.

5. Wage:
   The player's recurring salary.

6. Release Clause:
   A contractual release amount, if applicable.

7. Loan Fee:
   The fee paid for a temporary transfer.

8. Player Development Value:
   An optional estimate of a player's future potential, distinct from current MV.

Do not use these values interchangeably.

A player with an MV of €50 million may attract an offer of €40 million, an asking price of €80 million, or a negotiated transfer fee of €65 million.

The actual price should depend on the circumstances of the transaction.

# PHASE 3: BUILD A BALANCED MARKET VALUE MODEL

Implement a centralized and deterministic player valuation service.

Use a combination of:
- A calibrated base-value curve.
- Overall rating.
- Age.
- Potential.
- Position.
- Current performance.
- Playing time.
- Club and league quality.
- Reputation.
- Contract situation.
- Injury history where relevant.
- Position-specific market demand.
- Market inflation.
- Development trajectory.

Do not simply multiply the previous market value by a collection of bonuses every time the player improves.

Calculate a target valuation from the current player state, then update the persisted value gradually toward that target.

This prevents uncontrolled compounding.

## A. Base Value

Create a configurable base-value curve derived from overall rating.

The curve must be nonlinear.

The difference in value between an average player and a good player should be meaningful, while the difference between elite players should not become mathematically explosive.

Use the existing OVR scale and inspect its distribution before calibrating the curve.

Do not assume that a particular OVR automatically guarantees a particular MV.

Two players with the same OVR can have different market values due to age, potential, performance, position, and market circumstances.

## B. Overall Rating

OVR should be a major factor, but not the only factor.

Requirements:
- Higher OVR should generally increase MV when other variables are comparable.
- Small OVR improvements must not produce disproportionate exponential price increases.
- OVR should use a bounded nonlinear relationship.
- OVR must not be multiplied by itself or used repeatedly in several overlapping bonuses.
- Changes in OVR should affect the target value, not directly compound the previous MV.

## C. Age Curve

Implement an age-dependent valuation curve.

Suggested configurable profiles:

- Ages 15–17: speculative value based on potential and development.
- Ages 18–21: high potential premium for promising players.
- Ages 22–25: peak development and growth period.
- Ages 26–28: prime playing years.
- Ages 29–31: gradual decline in future resale value.
- Ages 32–34: stronger age-related discount.
- Ages 35+: substantial reduction in expected future value, depending on ability and performance.

These are initial tuning profiles, not absolute rules.

The model must recognize that elite older players can retain considerable value.

Do not reduce a player's value to nearly zero simply because the player has passed a particular age.

## D. Potential

Potential represents the player's development ceiling or future ability, not a guaranteed future valuation.

Requirements:
- Higher potential should increase the value of young players.
- Potential premium should diminish as players approach their expected development ceiling.
- Potential alone must not make an inexperienced youth player worth hundreds of millions.
- Potential must not be applied repeatedly on every valuation update.
- Low-potential players with exceptional current ability must still retain appropriate value.

Use a bounded potential premium that interacts with age and current ability.

## E. Position

Support position-aware valuation.

Account for the player's primary position and, where the game has the required data, their actual role.

Use different calibration profiles for:
- Goalkeepers.
- Centre-backs.
- Full-backs and wing-backs.
- Defensive midfielders.
- Central and attacking midfielders.
- Wingers.
- Strikers.

Position should influence market demand without making any position universally overpriced.

Do not assume every striker is more valuable than every defender or goalkeeper.

## F. Current Performance

Consider performance over a rolling period rather than one match.

Potential inputs include:
- Appearances.
- Minutes played.
- Starts.
- Goals.
- Assists.
- Clean sheets.
- Position-appropriate defensive statistics.
- Match ratings.
- Contribution to team results.
- Performance in major competitions.
- International performances, if supported.

Use position-specific performance indicators.

For example, do not apply a striker's goal-scoring bonus to a centre-back in the same way.

Normalize statistics by minutes played where appropriate.

Use sample-size safeguards so a player who scores several goals in two appearances does not immediately receive an enormous MV increase.

Performance bonuses must be bounded and must not stack indefinitely.

## G. Club and League Reputation

Account for:
- League strength.
- Club reputation.
- Competition prestige.
- Quality of opponents.
- Visibility in major competitions.
- Club financial strength where relevant to transfer-market demand.

A player performing well in an elite league may command a higher MV than an otherwise comparable player performing in a smaller league.

However:
- Do not multiply the player's value by the full club reputation score.
- Do not make club reputation an unlimited multiplier.
- Do not make every player at a famous club automatically expensive.
- Do not undervalue exceptional players from smaller leagues.

Use normalized, bounded coefficients.

## H. Contract Situation

Distinguish between the player's underlying market value and the conditions affecting the transfer price.

A short remaining contract should generally reduce the selling club's negotiating leverage.

A long contract may allow the selling club to demand a higher transfer fee.

Requirements:
- Avoid making contract duration the dominant determinant of MV.
- Do not set MV to zero merely because a contract is expiring.
- Allow contract duration to influence asking price and negotiation outcomes more strongly than baseline MV.
- Handle free transfers correctly.
- Support release clauses where the game implements them.

## I. Injuries and Availability

Where reliable injury data exists:
- Consider recurring or long-term injuries.
- Avoid excessive discounts for minor short-term injuries.
- Reflect the impact of severe injuries on availability and market demand.
- Do not permanently penalize a player for a fully recovered injury without justification.

Keep injury-related adjustments bounded.

# PHASE 4: INITIAL MV CALIBRATION

Use the existing player database to understand the distribution of:
- OVR.
- Potential.
- Age.
- Position.
- Club reputation.
- League reputation.
- Current MV.

Create a calibration report before changing the model.

Recommended initial target ranges in euros:

| Player category | Approximate MV target |
|---|---:|
| Low-rated reserve or lower-division player | €10,000–€500,000 |
| Ordinary lower-division professional | €100,000–€2 million |
| Promising young player | €500,000–€10 million |
| Established player in a smaller league | €500,000–€10 million |
| Established player in a competitive mid-level league | €2–15 million |
| Important player at a strong mid-level club | €10–35 million |
| Established player at an elite-league club | €10–60 million |
| Elite regular or international player | €40–100 million |
| World-class player | €80–150 million |
| Exceptional global superstar | €120–200 million |
| Rare generational talent | €150–250 million or potentially higher |

These ranges are calibration references, not rigid rules.

They must be adjusted to the actual OVR distribution, currency, league structure, club reputation, and financial economy of the existing game.

Do not force every player into a predetermined bracket.

A €200 million valuation should be rare.

Values above €250 million should require exceptional circumstances, and values approaching €1 billion should not arise from ordinary player development or routine formula updates.

Do not apply a universal hard cap as the primary solution.

Instead, correct the valuation model so extreme values emerge only if explicitly justified by the configured game economy.

# PHASE 5: CONTROL MARKET VALUE GROWTH

Implement a stable valuation update mechanism.

The system should distinguish between:
- Target MV calculated from current player information.
- Persisted MV shown in the player profile.
- Transfer asking price.
- Actual negotiated transfer fee.

Recommended behavior:

1. Calculate the target MV from the current player state.
2. Compare the target with the existing persisted MV.
3. Apply a bounded adjustment toward the target.
4. Limit ordinary percentage changes per update.
5. Allow exceptional changes when supported by sustained performance, major development, or a significant injury.
6. Prevent repeated recalculation from applying the same bonus multiple times.
7. Avoid unnecessary recalculations when the player state has not materially changed.

Suggested starting tuning parameters:
- Routine valuation changes should usually remain within approximately 5–10% per valuation update.
- Exceptional updates may exceed this range when supported by significant evidence.
- Avoid automatic exponential growth from one update to the next.
- Use season-level and rolling performance information to prevent short-term statistical anomalies.

These percentages are configurable starting points, not real-world regulations.

Use a consistent valuation schedule, such as monthly or at meaningful season milestones.

Do not recalculate the entire database on every UI render or every button press.

# PHASE 6: MARKET DEMAND AND PLAYER NEGOTIATIONS

Market value and transfer price must be related but distinct.

Implement a configurable asking-price calculation based on:
- Baseline MV.
- Remaining contract duration.
- Player importance to the club.
- Squad depth.
- Whether the player is transfer-listed.
- Whether the player wants to leave.
- Club financial pressure.
- Interest from other clubs.
- Competition for the player's position.
- Buying club financial strength.
- Selling club financial strength.
- Transfer deadline pressure.
- Negotiation circumstances.

Use bounded adjustments.

A selling club may demand more than MV for an important player under a long contract.

A financially pressured club may accept less.

A player nearing contract expiry may be available for less than MV.

A free agent may have a nonzero MV even though no transfer fee is required.

Do not allow the same demand factor to be applied repeatedly.

## Negotiation Rules

- Clubs should not automatically accept any offer equal to MV.
- Asking price should not be identical to MV for every player.
- Offers below asking price may be negotiated.
- Offers should be compared against the selling club's valuation and circumstances.
- Financially weak clubs may be more willing to sell.
- Wealthy clubs should not automatically pay unlimited premiums.
- Player willingness, wage demands, squad role, and club reputation may influence negotiations.
- Transfer bonuses and add-ons should be accounted for separately from the guaranteed transfer fee.

Keep negotiations within a realistic and configurable range.

# PHASE 7: TRANSFER FEE AND MV FEEDBACK

A completed transfer can provide useful information about market demand, but its fee must not automatically become the player's new MV.

Requirements:
- Record the agreed transfer fee separately.
- Account for guaranteed fees and conditional add-ons separately.
- Distinguish loan fees from permanent transfer fees.
- Do not treat a loan fee as the player's full market value.
- Do not apply the same transfer fee as a permanent valuation bonus on every subsequent update.
- Do not let repeated high asking prices create market inflation.
- Do not let one exceptional transfer permanently inflate every player in the same league.
- Use comparable transactions only as a bounded calibration input where supported.

The market value should reflect the player and the broader market, not simply the last negotiated price.

# PHASE 8: YOUTH ACADEMY AND PLAYER DEVELOPMENT

Integrate the MV model with player development.

Requirements:
- Youth players should start with values appropriate to their current ability and potential.
- Potential should create a limited premium for promising young players.
- Players should not become extremely expensive solely because they have high potential.
- Actual development should gradually increase value.
- Consistent first-team performances should help young players gain value.
- Players who fail to develop should not automatically reach their potential-based valuation.
- Players with declining attributes should generally lose value over time.
- Development speed and MV growth must remain separate systems.

Prevent youth-generated market value inflation from accumulating over multiple seasons.

# PHASE 9: CLUB FINANCIAL ECONOMY

Audit the wider transfer economy to ensure that MV remains coherent with club finances.

Inspect:
- Club budgets.
- Transfer budgets.
- Wage budgets.
- Revenue.
- Prize money.
- Sponsorship income.
- Transfer income.
- Financial reputation.
- League-specific economic strength.

The objective is not to make all clubs equally wealthy.

Instead:
- Preserve meaningful differences between clubs and leagues.
- Ensure transfer fees remain proportionate to the economic scale of the game.
- Avoid a situation where ordinary clubs routinely pay hundreds of millions for average players.
- Avoid unlimited transfer spending unless explicitly intended by the game.
- Ensure MV inflation does not make transfers impossible or economically meaningless.

Do not modify unrelated financial systems unless necessary to correct the identified valuation problem.

# PHASE 10: CURRENCY AND NUMERIC SAFETY

Audit all currency representations.

Requirements:
- Identify the game's canonical currency.
- Keep internal values consistent.
- Separate currency conversion from player valuation.
- Avoid applying exchange rates more than once.
- Ensure database fields can represent all legitimate values.
- Prevent integer overflow.
- Avoid unintended truncation or precision errors.
- Format currency consistently in the UI.
- Use appropriate numeric types for large monetary values.
- Validate negative values and invalid numerical inputs.

Do not mix USD and EUR without explicit conversion.

Do not assume that a value displayed as 1 billion uses the same currency as the underlying stored value.

# PHASE 11: SAVE-GAME COMPATIBILITY AND DATA MIGRATION

Inspect existing saved-game data before migrating valuations.

Requirements:
- Preserve player identities and IDs.
- Preserve clubs and competitions.
- Preserve transfer histories.
- Preserve existing completed transfers.
- Preserve contract information.
- Preserve player attributes and potential.
- Preserve valid historical financial records.
- Recalculate only the fields that genuinely need migration.
- Avoid resetting the current season.
- Avoid deleting or recreating the database.

If existing market values are severely inflated:
1. Identify the affected records.
2. Calculate corrected target values.
3. Produce a preview of the old and proposed values.
4. Preserve original values or an audit record where practical.
5. Apply the migration safely.
6. Verify the resulting value distribution.

Do not overwrite completed transfer fees merely to make them match the new MV.

Use a reversible migration or backup strategy where practical.

# PHASE 12: AUTOMATED TESTS

Implement automated tests using the existing Flutter/Dart testing framework.

Test at least:

1. MV increases appropriately when OVR improves.
2. MV does not grow exponentially through repeated recalculation.
3. Two players with the same OVR can have different values due to age, potential, and performance.
4. Young high-potential players receive a reasonable premium.
5. Potential alone does not create billion-dollar valuations.
6. Older players experience a reasonable age-related valuation adjustment.
7. Exceptional older players can retain significant value.
8. Position-specific valuation works correctly.
9. Performance bonuses remain bounded.
10. Small statistical samples do not create extreme valuations.
11. League and club reputation adjustments remain bounded.
12. Contract duration affects transfer negotiations correctly.
13. MV is not set to zero solely because a contract expires.
14. Transfer fees do not automatically overwrite MV.
15. Loan fees do not become permanent transfer values.
16. Repeated valuation updates do not stack identical bonuses.
17. Identical inputs produce identical target valuations.
18. Currency conversions do not apply twice.
19. Numeric overflow and invalid values are handled safely.
20. Existing saved games remain loadable after migration.
21. Market values remain stable when player attributes do not change.
22. Ordinary players do not routinely reach hundreds of millions.
23. Billion-dollar valuations do not emerge from ordinary development.
24. Exceptional world-class players can still command premium valuations.

Add distribution-level tests using the actual player database where feasible.

Do not test only individual players. Validate the overall market economy.

# PHASE 13: MARKET DISTRIBUTION VALIDATION

Before and after implementing the new model, produce a report containing:

- Total number of players.
- Minimum MV.
- Median MV.
- Mean MV.
- 75th percentile.
- 90th percentile.
- 95th percentile.
- 99th percentile.
- Maximum MV.
- Number of players above €10 million.
- Number of players above €50 million.
- Number of players above €100 million.
- Number of players above €200 million.
- Number of players above €250 million.
- Number of players above €500 million.
- Number of players above €1 billion.

Break down the distribution by:
- Age group.
- OVR range.
- Potential range.
- Position.
- League.
- Club reputation.
- Player status, such as youth prospect, regular, star, or veteran.

Use these reports to determine whether the model is producing a healthy market distribution.

Do not claim the model is realistic solely because no player exceeds a particular value.

Check that the relative distribution is sensible and that exceptional values have explainable causes.

# PHASE 14: IMPLEMENTATION REQUIREMENTS

- Follow the existing Flutter/Dart architecture.
- Reuse existing models, services, and repositories where appropriate.
- Keep market valuation separate from transfer negotiations.
- Avoid unnecessary dependencies.
- Keep valuation parameters configurable.
- Add clear documentation for the formula.
- Avoid magic multipliers scattered throughout the codebase.
- Preserve compatibility with existing saves.
- Do not redesign unrelated UI.
- Ensure that all displayed values reflect the same canonical valuation data.
- Ensure that player profiles, transfer lists, scouting screens, and negotiation interfaces do not calculate conflicting MV values.

Implement actual changes rather than stopping after an audit report.

# ACCEPTANCE CRITERIA

The new system must:

1. Produce stable and explainable market values.
2. Use multiple player and market factors.
3. Prevent runaway exponential growth.
4. Distinguish MV from transfer fees and asking prices.
5. Reward genuine player development without excessive inflation.
6. Account for age, position, performance, potential, and market conditions.
7. Preserve meaningful differences between leagues and clubs.
8. Support elite players with genuinely high valuations.
9. Prevent ordinary player development from producing billion-dollar valuations.
10. Preserve existing game data and completed transfer histories.
11. Pass automated tests.
12. Produce before-and-after valuation reports.

# FINAL REPORT

After implementation, report:

1. Root cause of the original MV inflation.
2. Files modified.
3. Old valuation formula and its problems.
4. New valuation formula and its configurable parameters.
5. How age, OVR, potential, performance, and contracts affect MV.
6. How asking prices and negotiated transfer fees are calculated.
7. Database changes and migration details.
8. Before-and-after market value distribution.
9. Automated tests executed and their actual results.
10. Remaining limitations.

Do not claim success without running the tests and inspecting the resulting market distribution.