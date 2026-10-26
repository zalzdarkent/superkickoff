import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Opens the pre-match tactical scouting dossier sheet.
Future<void> showTacticalAnalysisSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => const FractionallySizedBox(
      heightFactor: 0.88,
      child: TacticalAnalysisSheet(),
    ),
  );
}

class TacticalAnalysisSheet extends StatefulWidget {
  const TacticalAnalysisSheet({super.key});

  @override
  State<TacticalAnalysisSheet> createState() => _TacticalAnalysisSheetState();
}

class _TacticalAnalysisSheetState extends State<TacticalAnalysisSheet> {
  late Future<TacticalAnalysisReport?> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().upcomingOpponentTacticalReport();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: FutureBuilder<TacticalAnalysisReport?>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<TacticalAnalysisReport?> snap,
        ) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Menyusun dossier analisis taktik lawan...'),
                ],
              ),
            );
          }

          final TacticalAnalysisReport? report = snap.data;
          if (report == null) {
            return const Center(
              child: Text(
                'Tidak ada jadwal pertandingan mendatang untuk dianalisis.',
              ),
            );
          }

          return _content(context, report);
        },
      ),
    );
  }

  Widget _content(BuildContext context, TacticalAnalysisReport report) {
    final ClubStaff? analyst = report.analyst;
    final Team opp = report.opponent;

    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade700,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: <Widget>[
              CrestAvatar(team: opp, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      opp.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Divisi ${opp.division} · Kekuatan Tim ${opp.power}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'SCOUT INTEL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Analyst attribution card
                _analystCard(analyst, report.confidenceRating),
                const SizedBox(height: 14),

                // Tactical Style & Formation Card
                _tacticalStyleCard(report),
                const SizedBox(height: 14),

                // Danger Men
                if (report.dangerMen.isNotEmpty) ...<Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AppTheme.danger,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Pemain Kunci Lawan (Waspada)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final Player p in report.dangerMen)
                    _dangerManTile(context, p),
                  const SizedBox(height: 14),
                ],

                // Detected Vulnerabilities
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: AppTheme.warn,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Celah & Kelemahan Lawan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warn,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _vulnerabilitiesCard(report.vulnerabilities),
                const SizedBox(height: 14),

                // Tactical Blueprint / Counter-Strategies
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Rekomendasi Taktik Menang',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _counterTacticsCard(report.counterTactics),
                const SizedBox(height: 14),

                // Match Prediction
                _predictionCard(report.matchPrediction),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _analystCard(ClubStaff? analyst, int confidence) {
    if (analyst == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warn.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warn.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.info_outline, color: AppTheme.warn, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Belum Ada Analis Taktis di Klub',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.warn,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Akurasi data terbatas ($confidence%). Rekrut Lead Tactical Analyst di menu Fasilitas Klub untuk dossier lengkap dan akurasi tinggi.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.analytics_outlined,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  analyst.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < 5; i++)
                      Icon(
                        i < analyst.stars ? Icons.star : Icons.star_border,
                        size: 13,
                        color: Colors.amber,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      '${analyst.roleTitle} · $confidence% Akurasi Prediksi',
                      style: const TextStyle(
                        fontSize: 11,
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
    );
  }

  Widget _tacticalStyleCard(TacticalAnalysisReport report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  report.formation,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  report.predictedMentality,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.purpleAccent,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.sports_soccer, size: 16, color: AppTheme.textDim),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.tacticalStyle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            report.tacticalStyleDescription,
            style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _dangerManTile(BuildContext context, Player p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${p.power}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.danger,
            ),
          ),
        ),
        title: Text(
          p.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${PositionBadge.labelFor(p.positionId, profile: p.profile)} · Usia ${p.age} · POT ${p.potential}',
          style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textDim),
        onTap: () => showPlayerDetail(context, p.playerId),
      ),
    );
  }

  Widget _vulnerabilitiesCard(List<String> vulnerabilities) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String v in vulnerabilities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('• ', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      v,
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _counterTacticsCard(List<String> counterTactics) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String ct in counterTactics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.check_circle_outline, size: 15, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ct,
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _predictionCard(String prediction) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.insights, size: 20, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Kesimpulan & Prediksi Laga',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  prediction,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
