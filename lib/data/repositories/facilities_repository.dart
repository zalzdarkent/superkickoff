import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Repository managing club infrastructure (Training Ground & Medical Centre)
/// and professional coaching staff (Head Physio, Tactical Analyst, Head Scout).
class FacilitiesRepository {
  FacilitiesRepository(this.db);

  final Database db;

  // ---------------------------------------------------------------- Facilities

  /// Gets current facilities for [teamId], creating default level 1 if needed.
  Future<ClubFacilities> getFacilities(int teamId) async {
    await db.insert(
      t.teamFacilities,
      <String, Object?>{
        'team_id': teamId,
        'training_level': 1,
        'medical_level': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final List<Map<String, Object?>> rows = await db.query(
      t.teamFacilities,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return ClubFacilities(teamId: teamId, trainingLevel: 1, medicalLevel: 1);
    }
    return ClubFacilities.fromMap(rows.first);
  }

  /// Upgrades club training ground facility to the next level (up to 5).
  Future<String?> upgradeTrainingGround(int teamId) async {
    final ClubFacilities fac = await getFacilities(teamId);
    if (fac.isMaxTraining) {
      return 'Training Ground sudah berada di level maksimal (Level 5).';
    }

    final int cost = fac.nextTrainingCost;
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      columns: <String>['budget'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int budget = teamRows.isEmpty
        ? 0
        : ((teamRows.first['budget'] as int?) ?? 0);
    if (budget < cost) {
      return 'Anggaran tidak mencukupi. Biaya upgrade adalah \$${(cost / 1000000).toStringAsFixed(1)}M.';
    }

    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - cost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      await txn.update(
        t.teamFacilities,
        <String, Object?>{'training_level': fac.trainingLevel + 1},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
    });

    return null;
  }

  /// Upgrades club medical centre to the next level (up to 5).
  Future<String?> upgradeMedicalCentre(int teamId) async {
    final ClubFacilities fac = await getFacilities(teamId);
    if (fac.isMaxMedical) {
      return 'Medical Centre sudah berada di level maksimal (Level 5).';
    }

    final int cost = fac.nextMedicalCost;
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      columns: <String>['budget'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int budget = teamRows.isEmpty
        ? 0
        : ((teamRows.first['budget'] as int?) ?? 0);
    if (budget < cost) {
      return 'Anggaran tidak mencukupi. Biaya upgrade adalah \$${(cost / 1000000).toStringAsFixed(1)}M.';
    }

    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - cost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      await txn.update(
        t.teamFacilities,
        <String, Object?>{'medical_level': fac.medicalLevel + 1},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
    });

    return null;
  }

  // ------------------------------------------------------------- Staff Members

  /// Current staff hired by the club.
  Future<List<ClubStaff>> getStaff(int teamId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.teamStaff,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      orderBy: 'stars DESC',
    );
    return rows.map(ClubStaff.fromMap).toList();
  }

  /// Staff member by role ('head_physio', 'tactical_analyst', 'head_scout').
  Future<ClubStaff?> getStaffByRole(int teamId, String role) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.teamStaff,
      where: 'team_id = ? AND role = ?',
      whereArgs: <Object?>[teamId, role],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ClubStaff.fromMap(rows.first);
  }

  /// Available candidate list for recruitment.
  List<ClubStaff> availableStaffCandidates({String? role}) {
    final List<ClubStaff> all = <ClubStaff>[
      // Head Physios
      const ClubStaff(
        staffId: 101,
        teamId: 0,
        role: 'head_physio',
        name: 'Dr. Alessandro Rossi',
        stars: 4,
        salary: 28000,
        specialty: 'Rehabilitasi Otot & Pemulihan Stamina Cepat',
      ),
      const ClubStaff(
        staffId: 102,
        teamId: 0,
        role: 'head_physio',
        name: 'Dr. Hiroshi Tanaka',
        stars: 5,
        salary: 55000,
        specialty: 'Pencegahan Cedera Elit & Biomekanika Modern',
      ),
      const ClubStaff(
        staffId: 103,
        teamId: 0,
        role: 'head_physio',
        name: 'Dr. Mateo Silva',
        stars: 3,
        salary: 14000,
        specialty: 'Penanganan Kelelahan Laga & Kelenturan Pemain',
      ),
      const ClubStaff(
        staffId: 104,
        teamId: 0,
        role: 'head_physio',
        name: 'Dr. Liam O’Connor',
        stars: 2,
        salary: 7000,
        specialty: 'Pertolongan Pertama Lapangan & Fisioterapi Dasar',
      ),

      // Tactical Analysts
      const ClubStaff(
        staffId: 201,
        teamId: 0,
        role: 'tactical_analyst',
        name: 'Roberto De Luca',
        stars: 5,
        salary: 60000,
        specialty: 'Eksploitasi Celah Lawan & Blueprint Taktik Juara',
      ),
      const ClubStaff(
        staffId: 202,
        teamId: 0,
        role: 'tactical_analyst',
        name: 'Julian Brandt-Möller',
        stars: 4,
        salary: 32000,
        specialty: 'Pemetaan Pressing & Deteksi Ruang Kosong',
      ),
      const ClubStaff(
        staffId: 203,
        teamId: 0,
        role: 'tactical_analyst',
        name: 'David Mitchell',
        stars: 3,
        salary: 15000,
        specialty: 'Analisis Bola Mati & Transisi Serangan Balik',
      ),
      const ClubStaff(
        staffId: 204,
        teamId: 0,
        role: 'tactical_analyst',
        name: 'Lucas Fontaine',
        stars: 2,
        salary: 8000,
        specialty: 'Heatmap Posisi & Evaluasi Alur Pertandingan',
      ),

      // Head Scouts
      const ClubStaff(
        staffId: 301,
        teamId: 0,
        role: 'head_scout',
        name: 'Jean-Pierre Laurent',
        stars: 5,
        salary: 65000,
        specialty: 'Pencarian Wonderkid Global & Valuasi Presisi',
      ),
      const ClubStaff(
        staffId: 302,
        teamId: 0,
        role: 'head_scout',
        name: 'Carlos Valderrama-Rios',
        stars: 4,
        salary: 35000,
        specialty: 'Talenta Bakat Amerika Latin & Potensi Tinggi',
      ),
      const ClubStaff(
        staffId: 303,
        teamId: 0,
        role: 'head_scout',
        name: 'Kwesi Appiah',
        stars: 3,
        salary: 16000,
        specialty: 'Eksplorasi Talenta Fisik & Pemain Muda Berdaya Juang',
      ),
      const ClubStaff(
        staffId: 304,
        teamId: 0,
        role: 'head_scout',
        name: 'Kenji Sato',
        stars: 2,
        salary: 8000,
        specialty: 'Jaringan Scouting Regional Asia & Pekerja Keras',
      ),
    ];

    if (role != null) {
      return all.where((ClubStaff s) => s.role == role).toList();
    }
    return all;
  }

  /// Calculates upfront recruitment compensation fee for a candidate staff.
  int hiringFeeForStaff(ClubStaff candidate) => switch (candidate.stars) {
    1 => 100000,
    2 => 250000,
    3 => 650000,
    4 => 1600000,
    _ => 3200000,
  };

  /// Hires a new staff member for [teamId], replacing any incumbent in that role.
  Future<String?> hireStaff({
    required int teamId,
    required ClubStaff candidate,
    required String currentDate,
  }) async {
    final int fee = hiringFeeForStaff(candidate);
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      columns: <String>['budget'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int budget = teamRows.isEmpty
        ? 0
        : ((teamRows.first['budget'] as int?) ?? 0);
    if (budget < fee) {
      return 'Anggaran tidak mencukupi untuk merekrut ${candidate.name}. Biaya rekrutmen: \$${(fee / 1000).toStringAsFixed(0)}K.';
    }

    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - fee},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );

      // Remove existing staff in this role
      await txn.delete(
        t.teamStaff,
        where: 'team_id = ? AND role = ?',
        whereArgs: <Object?>[teamId, candidate.role],
      );

      await txn.insert(t.teamStaff, <String, Object?>{
        'team_id': teamId,
        'role': candidate.role,
        'name': candidate.name,
        'stars': candidate.stars,
        'salary': candidate.salary,
        'specialty': candidate.specialty,
        'hired_date': currentDate,
      });
    });

    return null;
  }

  /// Fires a staff member in [role].
  Future<void> fireStaff(int teamId, String role) async {
    await db.delete(
      t.teamStaff,
      where: 'team_id = ? AND role = ?',
      whereArgs: <Object?>[teamId, role],
    );
  }

  /// Calculates total weekly wages for all hired coaching/professional staff.
  Future<int> totalWeeklyStaffWages(int teamId) async {
    final List<ClubStaff> staff = await getStaff(teamId);
    return staff.fold<int>(0, (int sum, ClubStaff s) => sum + s.salary);
  }

  // --------------------------------------------------------- Tactical Analysis

  /// Compiles a comprehensive pre-match tactical report on [opponentTeamId].
  Future<TacticalAnalysisReport> generateTacticalReport({
    required int userTeamId,
    required int opponentTeamId,
  }) async {
    final ClubStaff? analyst = await getStaffByRole(
      userTeamId,
      'tactical_analyst',
    );
    final int analystStars = analyst?.stars ?? 0;

    // Load opponent team details
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      where: 'team_id = ?',
      whereArgs: <Object?>[opponentTeamId],
      limit: 1,
    );
    final Team opponent = teamRows.isNotEmpty
        ? Team.fromMap(teamRows.first)
        : Team(
            teamId: opponentTeamId,
            name: 'Opponent',
            abbreviation: 'OPP',
            countryId: 0,
            power: 70,
            value: 1000000,
            budget: 1000000,
            division: 1,
            stadiumId: 1,
            coachId: 1,
            foundedYear: 2000,
          );

    // Load opponent formation
    final List<Map<String, Object?>> tacticsRows = await db.query(
      t.teamTactics,
      where: 'team_id = ?',
      whereArgs: <Object?>[opponentTeamId],
      limit: 1,
    );
    final String formation = tacticsRows.isNotEmpty
        ? (tacticsRows.first['formation'] as String? ?? '4-4-2')
        : '4-4-2';

    // Load opponent squad players
    final List<Map<String, Object?>> playerRows = await db.rawQuery(
      '''
      SELECT p.* FROM ${t.players} p
      JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      ORDER BY p.power DESC
    ''',
      <Object?>[opponentTeamId, t.statusActive],
    );
    final List<Player> squad = playerRows.map(Player.fromMap).toList();

    // Key danger players (highest power attackers or playmakers)
    final List<Player> dangerMen = squad.take(2).toList();

    // Determine playstyle based on formation and team power
    final (String style, String desc, String mentality) = switch (formation) {
      '4-3-3' => (
        'High Press & Wing Overload',
        'Mengandalkan tempo tinggi dan tusukan cepat kedua winger untuk mengeksploitasi ruang di belakang fullback.',
        'Menyerang Agresif',
      ),
      '3-5-2' => (
        'Midfield Dominance & Wing-Back Surge',
        'Menguasai lini tengah dengan 3 gelandang tengah, namun meninggalkan celah lebar di sisi pertahanan luar.',
        'Penguasaan Bola',
      ),
      '4-2-3-1' => (
        'Fluid Playmaking & Box Infiltration',
        'Membangun serangan melalui gelandang serang sentral dengan pivot ganda pelindung lini belakang.',
        'Kombinasi Dinamis',
      ),
      '5-3-2' || '5-4-1' => (
        'Deep Defensive Block & Rapid Counters',
        'Sangat disiplin dan rapat di kotak penalti sendiri, siap melancarkan bola lambung cepat saat transisi.',
        'Bertahan & Kontra',
      ),
      _ => (
        'Direct Play & Balanced Structure',
        'Formasi klasik seimbang yang mengandalkan duel lini kedua dan umpan crossing langsung.',
        'Seimbang',
      ),
    };

    // Calculate vulnerabilities
    final List<String> vulnerabilities = <String>[];
    if (squad.isNotEmpty) {
      final Player gk = squad.firstWhere(
        (Player p) => p.positionId == 1,
        orElse: () => squad.last,
      );
      if (gk.power < opponent.power - 3) {
        vulnerabilities.add(
          'Kiper utama (${gk.name}, OVR ${gk.power}) rentan terhadap tembakan jarak jauh dan umpan silang akurat.',
        );
      }

      final List<Player> defenders = squad
          .where((Player p) => p.positionId >= 2 && p.positionId <= 4)
          .toList();
      if (defenders.length >= 4) {
        defenders.sort((Player a, Player b) => a.power.compareTo(b.power));
        final Player weakestDef = defenders.first;
        vulnerabilities.add(
          'Bek sisi pertahanan (${weakestDef.name}, OVR ${weakestDef.power}) sering kewalahan saat diserang 1-on-1.',
        );
      }

      final int tiredCount = squad.where((Player p) => p.fitness < 80).length;
      if (tiredCount >= 3) {
        vulnerabilities.add(
          '$tiredCount pilar tim lawan berada dalam kondisi kebugaran rendah (<80%). Stamina mereka akan habis di babak kedua.',
        );
      }
    }

    if (vulnerabilities.isEmpty) {
      vulnerabilities.add(
        'Lini pertahanan lawan cukup solid; manfaatkan transisi balik cepat dan set-piece.',
      );
    }

    // Tactical recommendations
    final List<String> counterTactics = <String>[];
    if (formation == '3-5-2') {
      counterTactics.add(
        'Mainkan bola-bola lebar lewat sayap untuk memanfaatkan ruang kosong di belakang wing-back lawan.',
      );
    } else if (formation == '4-3-3') {
      counterTactics.add(
        'Jaga garis pertahanan sedikit lebih dalam untuk mematikan kecepatan winger mereka.',
      );
    } else {
      counterTactics.add(
        'Gunakan pressing terarah di sepertiga akhir lapangan untuk memaksa kesalahan operan lawan.',
      );
    }

    if (analystStars >= 3) {
      counterTactics.add(
        'Fokuskan serangan pada sisi pertahanan terlemah lawan untuk membuka peluang tembakan bersih.',
      );
    }
    if (analystStars >= 4) {
      counterTactics.add(
        'Manfaatkan variasi umpan pendek kombinasi untuk memecah konsentrasi pivot pertahanan lawan.',
      );
    }

    final int confidence = analystStars == 0
        ? 35
        : math.min(98, 45 + analystStars * 11);

    final String prediction = opponent.power > 82
        ? 'Laga berat bertempo tinggi. Disiplin taktik dan efisiensi peluang akan menjadi penentu.'
        : opponent.power >= 70
            ? 'Pertarungan seimbang. Tim yang mendominasi duel lini tengah berpeluang besar menang.'
            : 'Peluang besar meraih poin penuh jika tim tampil dominan sejak menit awal.';

    return TacticalAnalysisReport(
      opponent: opponent,
      analyst: analyst,
      tacticalStyle: style,
      tacticalStyleDescription: desc,
      formation: formation,
      predictedMentality: mentality,
      dangerMen: dangerMen,
      vulnerabilities: vulnerabilities,
      counterTactics: counterTactics,
      matchPrediction: prediction,
      confidenceRating: confidence,
    );
  }
}
