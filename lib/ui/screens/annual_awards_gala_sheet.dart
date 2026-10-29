import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Opens the annual awards gala bottom sheet.
Future<void> showAnnualAwardsGala(
  BuildContext context, {
  required SeasonGalaSummary gala,
}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: AnnualAwardsGalaSheet(gala: gala),
    ),
  );
}

/// Full interactive Annual Awards Gala sheet celebrating season individual awards,
/// the Team of the Year (Once Ideal) 2D pitch, and club trophies.
class AnnualAwardsGalaSheet extends StatefulWidget {
  const AnnualAwardsGalaSheet({super.key, required this.gala});

  final SeasonGalaSummary gala;

  @override
  State<AnnualAwardsGalaSheet> createState() => _AnnualAwardsGalaSheetState();
}

class _AnnualAwardsGalaSheetState extends State<AnnualAwardsGalaSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SeasonGalaSummary gala = widget.gala;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _header(gala),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFFFD700),
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: const Color(0xFFFFD700),
            indicatorWeight: 3,
            dividerColor: Colors.white10,
            tabs: const <Widget>[
              Tab(
                icon: Icon(Icons.emoji_events, size: 18),
                text: 'Individual Awards',
              ),
              Tab(icon: Icon(Icons.groups, size: 18), text: 'Team of the Year'),
              Tab(icon: Icon(Icons.shield, size: 18), text: 'Club Honours'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _individualAwardsTab(gala),
                _teamOfTheYearTab(gala),
                _clubHonoursTab(gala),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(SeasonGalaSummary gala) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF1E1B4B),
            Color(0xFF0F172A),
            Color(0xFF172554),
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: <Color>[Color(0xFFFFDF00), Color(0xFFD97706)],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: Colors.black87,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'ANNUAL AWARDS GALA',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${gala.year}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  gala.seasonName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: INDIVIDUAL AWARDS
  // =========================================================================

  Widget _individualAwardsTab(SeasonGalaSummary gala) {
    if (gala.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Belum ada data penghargaan untuk musim ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        if (gala.ballonDor != null)
          _ballonDorHeroCard(gala.ballonDor!)
        else
          const SizedBox.shrink(),
        const SizedBox(height: 12),
        if (gala.goldenBoot != null)
          _standardAwardCard(
            award: gala.goldenBoot!,
            title: 'GOLDEN BOOT',
            subtitle: 'Top Scorer of the Season',
            icon: Icons.sports_soccer,
            accentColor: const Color(0xFFF59E0B),
          ),
        if (gala.goldenGlove != null) ...<Widget>[
          const SizedBox(height: 10),
          _standardAwardCard(
            award: gala.goldenGlove!,
            title: 'GOLDEN GLOVE',
            subtitle: 'Best Goalkeeper of the Season',
            icon: Icons.sports_handball,
            accentColor: const Color(0xFF06B6D4),
          ),
        ],
        if (gala.youngPlayer != null) ...<Widget>[
          const SizedBox(height: 10),
          _standardAwardCard(
            award: gala.youngPlayer!,
            title: 'BEST YOUNG PLAYER',
            subtitle: 'Rising Star (\u2264 21 Years Old)',
            icon: Icons.auto_awesome,
            accentColor: const Color(0xFF10B981),
          ),
        ],
        if (gala.mvp != null) ...<Widget>[
          const SizedBox(height: 10),
          _standardAwardCard(
            award: gala.mvp!,
            title: 'MOST VALUABLE PLAYER',
            subtitle: 'Highest Average Match Rating',
            icon: Icons.star,
            accentColor: const Color(0xFFA855F7),
          ),
        ],
        if (gala.managerOfTheYear != null) ...<Widget>[
          const SizedBox(height: 10),
          _managerAwardCard(gala.managerOfTheYear!),
        ],
      ],
    );
  }

  Widget _ballonDorHeroCard(PlayerAward award) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF2E2002),
            Color(0xFF1F1703),
            Color(0xFF120E02),
          ],
        ),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.2),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: award.playerId > 0
              ? () => showPlayerDetail(context, award.playerId)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFD700)
                                .withValues(alpha: 0.2),
                          ),
                          child: const Icon(
                            Icons.sports_soccer,
                            color: Color(0xFFFFD700),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'PLAYER OF THE YEAR',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Color(0xFFFFD700),
                              ),
                            ),
                            Text(
                              'Best Player of the League Season · 10+ appearances',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textDim,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.star, size: 12, color: Color(0xFFFFD700)),
                          SizedBox(width: 4),
                          Text(
                            'WINNER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFFFFD700)
                          .withValues(alpha: 0.25),
                      child: const Icon(
                        Icons.person,
                        size: 32,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            award.playerName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              if (award.positionId != null) ...<Widget>[
                                PositionBadge(positionId: award.positionId!),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                award.teamName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textDim,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (award.statSubtitle != null &&
                    award.statSubtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      award.statSubtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFE082),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _standardAwardCard({
    required PlayerAward award,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: award.playerId > 0
              ? () => showPlayerDetail(context, award.playerId)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.18),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        award.playerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          if (award.positionId != null) ...<Widget>[
                            PositionBadge(positionId: award.positionId!),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              award.teamName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (award.statSubtitle != null &&
                          award.statSubtitle!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          award.statSubtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textDim,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _managerAwardCard(PlayerAward award) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.assignment_ind,
                color: Color(0xFF818CF8),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'MANAGER OF THE YEAR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    award.playerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    award.teamName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textDim,
                    ),
                  ),
                  if (award.statSubtitle != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      award.statSubtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFA5B4FC),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 2: TEAM OF THE YEAR (ONCE IDEAL)
  // =========================================================================

  Widget _teamOfTheYearTab(SeasonGalaSummary gala) {
    final List<PlayerAward> tot = gala.teamOfTheYear;
    if (tot.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Team of the Year belum dihitung untuk musim ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim),
          ),
        ),
      );
    }

    // Split into 4-3-3 tactical lines:
    // GK (pos 1), DEF (pos 2-4), MID (pos 5-8), ATT (pos 9-11)
    final List<PlayerAward> gks = tot
        .where((PlayerAward p) => p.positionId == 1)
        .toList();
    final List<PlayerAward> defs = tot
        .where(
          (PlayerAward p) =>
              p.positionId != null && p.positionId! >= 2 && p.positionId! <= 4,
        )
        .toList();
    final List<PlayerAward> mids = tot
        .where(
          (PlayerAward p) =>
              p.positionId != null && p.positionId! >= 5 && p.positionId! <= 8,
        )
        .toList();
    final List<PlayerAward> atts = tot
        .where((PlayerAward p) => p.positionId != null && p.positionId! >= 9)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text(
              'ONCE IDEAL (4-3-3)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: Color(0xFFFFD700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${tot.length} Players Selected',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Mini 2D Football Pitch
        _pitchCard(gks: gks, defs: defs, mids: mids, atts: atts),
        const SizedBox(height: 16),
        const Text(
          'ROSTER XI TERBAIK',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDim,
          ),
        ),
        const SizedBox(height: 8),
        for (final PlayerAward p in tot) _totyPlayerRow(p),
      ],
    );
  }

  Widget _pitchCard({
    required List<PlayerAward> gks,
    required List<PlayerAward> defs,
    required List<PlayerAward> mids,
    required List<PlayerAward> atts,
  }) {
    return Container(
      height: 380,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF0F3B20),
            Color(0xFF134E27),
            Color(0xFF0F3B20),
          ],
        ),
        border: Border.all(color: Colors.white24, width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          // Pitch markings
          Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
          // Player rows
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Attackers line
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: atts
                      .map((PlayerAward p) => _pitchPlayerNode(p))
                      .toList(),
                ),
                // Midfielders line
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: mids
                      .map((PlayerAward p) => _pitchPlayerNode(p))
                      .toList(),
                ),
                // Defenders line
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: defs
                      .map((PlayerAward p) => _pitchPlayerNode(p))
                      .toList(),
                ),
                // Goalkeeper line
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: gks
                      .map((PlayerAward p) => _pitchPlayerNode(p))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pitchPlayerNode(PlayerAward player) {
    final String pos = PositionBadge.labelFor(player.positionId ?? 1);
    final String initial = player.playerName.isNotEmpty
        ? player.playerName.substring(0, 1)
        : '?';

    return InkWell(
      onTap: () => showPlayerDetail(context, player.playerId),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF1E293B),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pos,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              player.playerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            if (player.rating != null) ...<Widget>[
              const SizedBox(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  player.rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totyPlayerRow(PlayerAward player) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: InkWell(
        onTap: () => showPlayerDetail(context, player.playerId),
        child: Row(
          children: <Widget>[
            PositionBadge(positionId: player.positionId ?? 1),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    player.playerName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    player.teamName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (player.rating != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.star, size: 12, color: Color(0xFFFFD700)),
                    const SizedBox(width: 3),
                    Text(
                      player.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 3: CLUB HONOURS & RECAP
  // =========================================================================

  Widget _clubHonoursTab(SeasonGalaSummary gala) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        // Club trophies section
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'TROFI KLUB MUSIM INI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (gala.clubTrophies.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Tidak ada trofi yang dimenangkan klub musim ini. Tetap semangat untuk musim depan!',
                    style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                  ),
                )
              else
                for (final ClubTrophy trophy in gala.clubTrophies)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.workspace_premium,
                          color: Color(0xFFFFD700),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            trophy.tournamentName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CHAMPION',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // User club individual awards
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.military_tech, color: Color(0xFF60A5FA), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'PENGHARGAAN INDIVIDU KLUB ANDA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF60A5FA),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (gala.userClubAwards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada pemain klub Anda yang memenangkan penghargaan individu musim ini.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                  ),
                )
              else
                for (final PlayerAward ua in gala.userClubAwards)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.stars,
                          color: Color(0xFF60A5FA),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                ua.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF93C5FD),
                                ),
                              ),
                              Text(
                                ua.playerName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (ua.statSubtitle != null)
                          Text(
                            ua.statSubtitle!,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.textDim,
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints realistic football pitch line markings (touchlines, center line & circle, penalty boxes).
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Pitch border
    final Rect pitchRect = Rect.fromLTWH(
      8,
      8,
      size.width - 16,
      size.height - 16,
    );
    canvas.drawRect(pitchRect, linePaint);

    // Halfway line
    final double midY = size.height / 2;
    canvas.drawLine(Offset(8, midY), Offset(size.width - 8, midY), linePaint);

    // Center circle
    canvas.drawCircle(Offset(size.width / 2, midY), 36, linePaint);
    canvas.drawCircle(
      Offset(size.width / 2, midY),
      2.5,
      linePaint..style = PaintingStyle.fill,
    );
    linePaint.style = PaintingStyle.stroke;

    // Top penalty area (Opponent/Goal area)
    final double penaltyWidth = size.width * 0.52;
    final double penaltyLeft = (size.width - penaltyWidth) / 2;
    canvas.drawRect(Rect.fromLTWH(penaltyLeft, 8, penaltyWidth, 54), linePaint);

    // Bottom penalty area (Our keeper area)
    canvas.drawRect(
      Rect.fromLTWH(penaltyLeft, size.height - 62, penaltyWidth, 54),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
