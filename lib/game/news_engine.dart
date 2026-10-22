import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/format.dart' as fmt;
import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/news_repository.dart';

/// Turns what happened on the pitch into stories, with no AI involved.
///
/// Each detector looks at real numbers (scores, power gaps, streaks, table
/// positions, goal tallies, transfer fees) and fills a pool of headline/body
/// templates. A story's `ref` is unique, so running the engine twice for the
/// same matchday never duplicates anything.
class NewsEngine {
  NewsEngine(this.db, this.repo);

  final Database db;
  final NewsRepository repo;

  /// Region of each continental cup. Cups missing here (Intercontinental Cup,
  /// Club World Cup...) are world stories.
  static const Map<int, String> _cupRegions = <int, String>{
    49: 'europe',
    51: 'europe',
    135: 'europe',
    54: 'europe',
    52: 'southAmerica',
    53: 'southAmerica',
    55: 'southAmerica',
    50: 'northAmerica',
    162: 'northAmerica',
    99: 'asia',
    164: 'asia',
    1650: 'asia',
    1651: 'asia',
    100: 'africa',
  };

  /// countries.confederation -> region key.
  static const Map<int, String> _confederations = <int, String>{
    1: 'northAmerica',
    2: 'africa',
    3: 'europe',
    4: 'southAmerica',
    5: 'asia',
  };

  static const Map<String, String> _regionNames = <String, String>{
    'europe': 'Europe',
    'southAmerica': 'South America',
    'northAmerica': 'North America',
    'asia': 'Asia',
    'africa': 'Africa',
  };

  // ---------------------------------------------------------------- public

  /// Stories for every match finished on [date].
  Future<void> onMatchday({
    required int seasonId,
    required String date,
    required int userLeagueId,
    required String userRegion,
  }) async {
    final _Ctx c = _Ctx(seasonId, date, userLeagueId, userRegion);
    final List<_Match> matches = await _matches(c);
    final List<NewsItem> out = <NewsItem>[];
    for (final _Match m in matches) {
      out.addAll(await _matchStories(c, m));
    }
    out.addAll(await _roundUps(c, matches));
    out.addAll(await _leagueStories(c, matches));
    out.addAll(await _groupStories(c, matches));
    out.addAll(await _transferStories(c));
    await repo.insertAll(out);
  }

  /// Season-opening stories so the feed is never empty on day one.
  Future<void> preview({
    required int seasonId,
    required String date,
    required int userLeagueId,
    required String userRegion,
  }) async {
    final _Ctx c = _Ctx(seasonId, date, userLeagueId, userRegion);
    final List<NewsItem> out = <NewsItem>[];

    final List<Map<String, Object?>> leagueTeams = await db.rawQuery(
      '''
      SELECT tm.team_id, tm.name, tm.power FROM teams tm
      WHERE tm.team_id IN (
        SELECT home_team_id FROM matches WHERE season_id = ? AND tournament_id = ?
      )
      ORDER BY tm.power DESC, tm.name
    ''',
      <Object?>[seasonId, userLeagueId],
    );
    if (leagueTeams.length >= 6) {
      final String lg = await _tourName(userLeagueId);
      final List<String> top = <String>[
        for (final Map<String, Object?> r in leagueTeams.take(3))
          r['name'] as String,
      ];
      final Map<String, Object?> dark = leagueTeams[1];
      out.add(
        NewsItem(
          ref: 'pre:league:$seasonId',
          seasonId: seasonId,
          date: date,
          scope: 'league',
          category: 'preview',
          headline: _t('pre:l:h', <String>[
            'Preview $lg: ${top[0]} start sebagai tim yang harus dikalahkan',
            '${top[0]} dijagokan jadi juara $lg',
            'Musim baru $lg: ${top[0]} memimpin daftar unggulan',
          ]),
          body:
              'Di atas kertas ${top[0]} adalah '
              'tim terkuat di divisi ini, dengan ${top[1]} dan ${top[2]} '
              'sebagai pesaing terdekat. ${dark['name']} jadi kuda hitam yang '
              'siap mengganggu. Di papan bawah, '
              '${leagueTeams.last['name']} dinilai paling rentan.',
          importance: 3,
          teamId: leagueTeams[0]['team_id'] as int,
        ),
      );
    }

    final List<Map<String, Object?>> cups = await db.rawQuery(
      '''
      SELECT tu.tournament_id, tu.name FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ? AND tu.organization = 2
    ''',
      <Object?>[seasonId],
    );
    for (final Map<String, Object?> cup in cups) {
      final int id = cup['tournament_id'] as int;
      final List<Map<String, Object?>> field = await db.rawQuery(
        '''
        SELECT tm.name, tm.power, tm.team_id FROM teams tm
        WHERE tm.team_id IN (
          SELECT home_team_id FROM matches WHERE season_id = ? AND tournament_id = ?
          UNION SELECT away_team_id FROM matches
          WHERE season_id = ? AND tournament_id = ?
        )
        ORDER BY tm.power DESC
      ''',
        <Object?>[seasonId, id, seasonId, id],
      );
      if (field.length < 2) continue;
      final String name = cup['name'] as String;
      final String scope = _scopeOf(c, id, 2);
      final Map<String, Object?> fav = field.first;
      out.add(
        NewsItem(
          ref: 'pre:cup:$seasonId:$id',
          seasonId: seasonId,
          date: date,
          scope: scope,
          category: 'preview',
          headline: _t('pre:c:$id', <String>[
            '$name kembali bergulir: ${fav['name']} tim yang harus dikalahkan',
            '$name: ${field.length} klub berebut kejayaan',
            'Kick-off $name sudah di depan mata',
          ]),
          body:
              '${field.length} klub akan berlaga di $name. '
              '${fav['name']} dinilai sebagai peserta terkuat, sementara '
              '${field.last['name']} datang sebagai tim dengan kekuatan '
              'paling rendah di kompetisi ini.',
          importance: 2,
          teamId: fav['team_id'] as int,
        ),
      );
    }

    // Start transfer coverage from "now", not from the bundled history.
    final int? maxTransfer = Sqflite.firstIntValue(
      await db.rawQuery('SELECT MAX(transfer_id) FROM player_transfers'),
    );
    out.add(
      NewsItem(
        ref: 'meta:transfers',
        seasonId: seasonId,
        date: date,
        scope: 'world',
        category: 'meta',
        headline: 'transfer baseline',
        body: '${maxTransfer ?? 0}',
        importance: 0,
      ),
    );
    await repo.insertAll(out);
  }

  // ----------------------------------------------------------- match items

  Future<List<NewsItem>> _matchStories(_Ctx c, _Match m) async {
    final List<NewsItem> out = <NewsItem>[];
    final String scope = _scopeOf(c, m.tournamentId, m.org);
    final bool knockout = m.org == 2 && m.groupId == null;
    final int bump = knockout ? 1 : 0;
    final String score = '${m.hg}-${m.ag}';
    final String? stage = knockout ? await _stage(c, m) : null;
    final String where = stage == null ? m.tourName : '${m.tourName} $stage';

    // Cup final -> champions.
    if (knockout && await _isFinal(c, m) && m.winnerId != 0) {
      final bool homeWon = m.winnerId == m.homeId;
      final String champ = homeWon ? m.home : m.away;
      final String beaten = homeWon ? m.away : m.home;
      final Map<String, Object?> run = await _cupRun(c, m.tournamentId, m.winnerId);
      out.add(
        NewsItem(
          ref: 'final:${c.seasonId}:${m.tournamentId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'trophy',
          headline: _t('final:${m.matchId}:h', <String>[
            '$champ dinobatkan jadi juara ${m.tourName}',
            '$champ angkat trofi ${m.tourName}',
            'Pesta untuk $champ: ${m.tourName} direbut',
          ]),
          body:
              '$champ mengalahkan $beaten $score di final ${m.tourName}. '
              'Sepanjang kompetisi mereka mencetak ${run['gf']} gol dan '
              'kebobolan ${run['ga']} dalam ${run['played']} laga, '
              'dengan ${run['wins']} kemenangan.',
          importance: 5,
          teamId: m.winnerId,
        ),
      );
    }

    final int winnerPower = m.winnerId == m.homeId ? m.hp : m.ap;
    final int loserPower = m.winnerId == m.homeId ? m.ap : m.hp;
    final String winner = m.winnerId == m.homeId ? m.home : m.away;
    final String loser = m.winnerId == m.homeId ? m.away : m.home;
    final int margin = (m.hg - m.ag).abs();

    // Upset: clearly weaker side wins.
    if (m.winnerId != 0 && loserPower - winnerPower >= 8) {
      out.add(
        NewsItem(
          ref: 'upset:${m.matchId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'upset',
          headline: _t('up:${m.matchId}:h', <String>[
            '$winner bikin kejutan, tundukkan $loser di $where',
            'Hasil mengejutkan: $loser tumbang oleh $winner',
            'Aksi pembunuh raksasa! $winner jungkalkan $loser',
            '$loser dipermalukan $winner, $score',
          ]),
          body: _t('up:${m.matchId}:b', <String>[
            '$winner sebenarnya tidak diunggulkan melawan $loser, '
                'tetapi justru pulang dengan kemenangan $score.',
            'Di atas kertas $loser lebih difavoritkan, namun '
                '$winner yang membawa pulang kemenangan dengan skor $score.',
          ]),
          importance: math.min(5, 3 + bump),
          teamId: m.winnerId,
        ),
      );
    }

    // Thrashing.
    if (margin >= 4) {
      out.add(
        NewsItem(
          ref: 'rout:${m.matchId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'rout',
          headline: _t('rt:${m.matchId}:h', <String>[
            '$winner pesta gol ke gawang $loser',
            '$winner lumat $loser $score',
            'Pertunjukan bintang lima! $winner hajar $loser',
            '$loser tak berdaya, $winner menang $score',
          ]),
          body:
              '$winner menang dengan selisih $margin gol di ${m.tourName}. '
              '${margin >= 5 ? 'Ini salah satu kekalahan terbesar musim ini. ' : ''}'
              '${winnerPower >= loserPower ? 'Perbedaan kualitas kedua tim terlihat jelas.' : 'Hasil ini di luar dugaan banyak pihak.'}',
          importance: math.min(5, 3 + bump),
          teamId: m.winnerId,
        ),
      );
    } else if (m.hg + m.ag >= 6) {
      out.add(
        NewsItem(
          ref: 'thriller:${m.matchId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'thriller',
          headline: _t('th:${m.matchId}:h', <String>[
            'Laga ${m.hg + m.ag} gol: ${m.home} bertemu ${m.away}',
            'Banjir gol: ${m.home} $score ${m.away}',
            'Lini belakang absen di laga ${m.home}-${m.away}',
          ]),
          body:
              '${m.hg + m.ag} gol tercipta dalam satu laga: ${m.home} dan ${m.away} '
              'saling balas serangan di $where dan berakhir $score.',
          importance: 3,
          teamId: m.winnerId == 0 ? null : m.winnerId,
        ),
      );
    } else if (m.hg == m.ag && m.hg >= 3) {
      out.add(
        NewsItem(
          ref: 'drawfest:${m.matchId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'thriller',
          headline: '${m.home} dan ${m.away} berbagi ${m.hg * 2} gol di laga seri $score',
          body:
              'Tak ada pemenang meski ${m.hg + m.ag} gol tercipta '
              'di $where.',
          importance: 2,
        ),
      );
    }

    // Hat-tricks and better.
    final List<Map<String, Object?>> scorers = await db.rawQuery(
      '''
      SELECT mp.player_id, mp.goals, mp.team_id, p.name,
             (SELECT SUM(x.goals) FROM match_players x
              JOIN matches mm ON mm.match_id = x.match_id
              WHERE x.player_id = mp.player_id AND mm.season_id = ?
                AND mm.tournament_id = ? AND substr(mm.date,1,10) <= ?) AS total
      FROM match_players mp JOIN players p ON p.player_id = mp.player_id
      WHERE mp.match_id = ? AND mp.goals >= 3
    ''',
      <Object?>[c.seasonId, m.tournamentId, c.date, m.matchId],
    );
    for (final Map<String, Object?> s in scorers) {
      final int goals = s['goals'] as int;
      final String name = s['name'] as String;
      final bool home = s['team_id'] == m.homeId;
      final String club = home ? m.home : m.away;
      final String opp = home ? m.away : m.home;
      final String haul = switch (goals) {
        3 => 'hat-trick',
        4 => 'empat gol',
        5 => 'lima gol',
        _ => '$goals gol',
      };
      out.add(
        NewsItem(
          ref: 'hat:${m.matchId}:${s['player_id']}',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'player',
          headline: _t('hat:${m.matchId}:h', <String>[
            '$name cetak $haul ke gawang $opp',
            '$name on fire: $haul untuk $club',
            'Bola pertandingan jadi milik $name saat $club kalahkan $opp',
          ]),
          body:
              '$name mencetak ${goals == 3 ? 'ketiga' : '$goals'} gol untuk '
              '$club ($score melawan $opp di $where). Itu membawa total golnya '
              'menjadi ${s['total']} di ${m.tourName} musim ini.',
          importance: math.min(5, 4 + bump),
          teamId: s['team_id'] as int,
          playerId: s['player_id'] as int,
        ),
      );
    }
    return out;
  }

  // -------------------------------------------------------------- round-ups

  Future<List<NewsItem>> _roundUps(_Ctx c, List<_Match> matches) async {
    final Map<int, List<_Match>> byTour = <int, List<_Match>>{};
    for (final _Match m in matches) {
      byTour.putIfAbsent(m.tournamentId, () => <_Match>[]).add(m);
    }
    final List<NewsItem> out = <NewsItem>[];
    for (final MapEntry<int, List<_Match>> e in byTour.entries) {
      final List<_Match> list = e.value;
      if (list.length < 3) continue;
      final int goals = list.fold<int>(0, (int s, _Match m) => s + m.hg + m.ag);
      final int homeWins = list.where((_Match m) => m.hg > m.ag).length;
      final int draws = list.where((_Match m) => m.hg == m.ag).length;
      final _Match top = list.reduce(
        (_Match a, _Match b) => (a.hg + a.ag) >= (b.hg + b.ag) ? a : b,
      );
      final String name = list.first.tourName;
      final double avg = goals / list.length;
      out.add(
        NewsItem(
          ref: 'wrap:${c.seasonId}:${e.key}:${c.date}',
          seasonId: c.seasonId,
          date: c.date,
          scope: _scopeOf(c, e.key, list.first.org),
          category: 'roundup',
          headline: _t('wrap:${e.key}:${c.date}:h', <String>[
            'Rangkuman $name: $goals gol dalam ${list.length} laga',
            'Ulasan pekan $name: ${avg >= 3 ? 'gol di mana-mana' : avg < 2 ? 'pertahanan unggul' : 'pekan yang seimbang'}',
            '$name: $homeWins kemenangan tuan rumah, $draws laga seri',
          ]),
          body:
              '${list.length} laga menghasilkan $goals gol '
              '(${avg.toStringAsFixed(1)} per laga). Tuan rumah menang '
              '$homeWins kali, dengan $draws laga berakhir seri. Laga paling seru '
              'adalah ${top.home} ${top.hg}-${top.ag} ${top.away}.',
          importance: 1,
        ),
      );
    }
    return out;
  }

  // ----------------------------------------------------------- league items

  Future<List<NewsItem>> _leagueStories(_Ctx c, List<_Match> matches) async {
    final List<_Match> mine = matches
        .where((_Match m) => m.tournamentId == c.leagueId)
        .toList();
    if (mine.isEmpty) return const <NewsItem>[];
    final List<NewsItem> out = <NewsItem>[];
    final List<_Row> table = await _table(c.seasonId, c.leagueId, c.date);
    if (table.length < 4) return out;
    final List<_Row> before = await _table(c.seasonId, c.leagueId, c.date, strictlyBefore: true);
    final int games = table.first.played;
    final int totalRounds = (table.length - 1) * 2;
    final int left = totalRounds - games;
    final String lg = mine.first.tourName;
    final Set<int> played = <int>{
      for (final _Match m in mine) ...<int>[m.homeId, m.awayId],
    };

    // Leader change.
    if (before.isNotEmpty && before.first.id != table.first.id && games >= 3) {
      out.add(
        NewsItem(
          ref: 'lead:${c.seasonId}:${c.leagueId}:${table.first.id}:$games',
          seasonId: c.seasonId,
          date: c.date,
          scope: 'league',
          category: 'table',
          headline: _t('lead:$games:${table.first.id}:h', <String>[
            '${table.first.name} naik ke puncak klasemen $lg',
            'Pemimpin baru: ${table.first.name} ambil alih singgasana',
            '${before.first.name} terguling, ${table.first.name} naik ke peringkat 1',
          ]),
          body:
              '${table.first.name} memimpin klasemen dengan ${table.first.pts} poin '
              'setelah $games laga, unggul ${table.first.pts - table[1].pts} poin dari '
              '${table[1].name}. ${before.first.name} turun ke '
              '${_ord(table.indexWhere((_Row r) => r.id == before.first.id) + 1)}.',
          importance: 4,
          teamId: table.first.id,
        ),
      );
    }

    // Title race / runaway leaders.
    final int gap = table.first.pts - table[1].pts;
    if (games >= totalRounds * 0.3 && games % 3 == 0) {
      if (gap <= 3) {
        out.add(
          NewsItem(
            ref: 'race:${c.seasonId}:${c.leagueId}:$games',
            seasonId: c.seasonId,
            date: c.date,
            scope: 'league',
            category: 'table',
            headline: _t('race:$games:h', <String>[
              'Persaingan juara memanas: ${table.first.name} dan ${table[1].name} hanya terpaut $gap poin',
              'Duel dua kuda? Hanya $gap poin pisahkan ${table.first.name} dan ${table[1].name}',
            ]),
            body:
                '$games pekan telah dimainkan, tersisa $left. ${table.first.name} '
                '(${table.first.pts} poin, selisih gol ${_gd(table.first)}) dikejar '
                '${table[1].name} (${table[1].pts} poin, selisih gol ${_gd(table[1])}).',
            importance: 4,
            teamId: table.first.id,
          ),
        );
      } else if (gap >= 7) {
        out.add(
          NewsItem(
            ref: 'runaway:${c.seasonId}:${c.leagueId}:$games',
            seasonId: c.seasonId,
            date: c.date,
            scope: 'league',
            category: 'table',
            headline:
                '${table.first.name} kabur $gap poin di puncak klasemen',
            body:
                '${table.first.name} sudah menang ${table.first.wins} dari $games laga dan '
                'unggul $gap poin atas ${table[1].name} dengan sisa $left pekan.',
            importance: 3,
            teamId: table.first.id,
          ),
        );
      }
    }

    // Title clinched.
    if (left >= 0 && table[1].pts + 3 * (totalRounds - table[1].played) < table.first.pts) {
      out.add(
        NewsItem(
          ref: 'champ:${c.seasonId}:${c.leagueId}',
          seasonId: c.seasonId,
          date: c.date,
          scope: 'league',
          category: 'trophy',
          headline: left == 0
              ? '${table.first.name} juara $lg!'
              : '${table.first.name} kunci gelar $lg, masih sisa $left pekan',
          body:
              '${table.first.name} mengumpulkan ${table.first.pts} poin '
              '${left == 0 ? '' : 'dengan sisa $left pekan, secara matematis '}'
              'tak terkejar oleh ${table[1].name}. Rekor: '
              '${table.first.wins}M ${table.first.draws}S ${table.first.losses}K, '
              '${table.first.gf} gol memasukkan, ${table.first.ga} kemasukan.',
          importance: 5,
          teamId: table.first.id,
        ),
      );
    }

    // Relegation fight and confirmed drops.
    final int spots = await _relegationSpots(c.leagueId);
    if (spots > 0 && table.length > spots + 2) {
      final int cut = table.length - spots;
      final _Row safe = table[cut - 1];
      final _Row first = table[cut];
      if (games >= totalRounds * 0.5 && games % 3 == 0 && safe.pts - first.pts <= 3) {
        out.add(
          NewsItem(
            ref: 'relfight:${c.seasonId}:${c.leagueId}:$games',
            seasonId: c.seasonId,
            date: c.date,
            scope: 'league',
            category: 'table',
            headline: _t('relfight:$games:h', <String>[
              'Perebutan zona aman: ${first.name} hanya ${safe.pts - first.pts} poin dari aman',
              'Papan bawah $lg ketat: ${safe.name} bertahan di atas ${first.name}',
            ]),
            body:
                '${first.name} berada di zona degradasi dengan ${first.pts} poin, '
                '${safe.pts - first.pts} poin di belakang ${safe.name} yang menempati '
                'posisi aman terakhir. Tersisa $left pekan.',
            importance: 3,
            teamId: first.id,
          ),
        );
      }
      for (final _Row r in table.skip(cut)) {
        if (r.pts + 3 * (totalRounds - r.played) < safe.pts) {
          out.add(
            NewsItem(
              ref: 'down:${c.seasonId}:${c.leagueId}:${r.id}',
              seasonId: c.seasonId,
              date: c.date,
              scope: 'league',
              category: 'table',
              headline: '${r.name} resmi terdegradasi dari $lg',
              body:
                  '${r.name} tak bisa lagi mengejar ${safe.name} dan akan bermain '
                  'di divisi lebih rendah musim depan setelah hanya mengumpulkan '
                  '${r.pts} poin dari ${r.played} laga.',
              importance: 4,
              teamId: r.id,
            ),
          );
        }
      }
    }

    // Streaks for clubs that played today.
    for (final int id in played) {
      final String name = table.firstWhere((_Row r) => r.id == id, orElse: () => table.first).name;
      final List<List<int>> form = await _form(c, c.leagueId, id);
      final int wins = _run(form, (List<int> g) => g[0] > g[1]);
      final int unbeaten = _run(form, (List<int> g) => g[0] >= g[1]);
      final int losses = _run(form, (List<int> g) => g[0] < g[1]);
      final int winless = _run(form, (List<int> g) => g[0] <= g[1]);
      final int sheets = _run(form, (List<int> g) => g[1] == 0);
      final int dry = _run(form, (List<int> g) => g[0] == 0);
      final int pos = table.indexWhere((_Row r) => r.id == id) + 1;
      void add(String key, int n, String headline, String body, int imp) {
        out.add(
          NewsItem(
            ref: 'streak:$key:${c.seasonId}:$id:$n',
            seasonId: c.seasonId,
            date: c.date,
            scope: 'league',
            category: 'form',
            headline: headline,
            body: body,
            importance: imp,
            teamId: id,
          ),
        );
      }

      if (<int>[4, 6, 8, 10, 12].contains(wins)) {
        add(
          'win',
          wins,
          _t('sw:$id:$wins:h', <String>[
            '$name raih $wins kemenangan beruntun',
            '$wins kemenangan berturut-turut untuk $name',
            'Tren kemenangan $name capai $wins laga',
          ]),
          '$name kini di ${_ord(pos)} $lg dan telah menang $wins laga liga '
              'beruntun, mencetak ${form.take(wins).fold<int>(0, (int s, List<int> g) => s + g[0])} gol '
              'dan kebobolan ${form.take(wins).fold<int>(0, (int s, List<int> g) => s + g[1])} gol di periode itu.',
          wins >= 6 ? 4 : 3,
        );
      } else if (<int>[6, 8, 10, 12].contains(unbeaten)) {
        add(
          'unb',
          unbeaten,
          '$name tak terkalahkan dalam $unbeaten laga',
          '$name belum kalah dalam $unbeaten laga liga dan kini berada di '
              '${_ord(pos)} klasemen.',
          3,
        );
      }
      if (<int>[3, 5, 7].contains(losses)) {
        add(
          'loss',
          losses,
          _t('sl:$id:$losses:h', <String>[
            '$name krisis setelah $losses kekalahan beruntun',
            'Tekanan makin berat, $name kalah lagi',
            '$losses kekalahan berturut-turut: $name dalam masalah',
          ]),
          '$name kalah $losses laga liga beruntun dan kini di '
              '${_ord(pos)} dari ${table.length} tim. Manajemen pasti mengamati dengan cermat.',
          losses >= 5 ? 4 : 3,
        );
      } else if (<int>[5, 7, 9].contains(winless) && losses < 3) {
        add(
          'wl',
          winless,
          '$name masih mencari kemenangan setelah $winless laga',
          '$name belum menang dalam $winless laga liga dan merosot ke '
              '${_ord(pos)}.',
          2,
        );
      }
      if (<int>[3, 5].contains(sheets)) {
        add(
          'cs',
          sheets,
          '$name jaga gawang tak bobol dalam $sheets laga beruntun',
          '$name tak kebobolan dalam $sheets laga liga, rekor '
              'pertahanan yang kokoh.',
          2,
        );
      }
      if (dry == 3) {
        add(
          'dry',
          dry,
          'Paceklik gol $name capai 3 laga',
          '$name gagal mencetak gol dalam tiga laga liga beruntun.',
          2,
        );
      }
    }

    // Player of the matchday.
    final List<Map<String, Object?>> stars = await db.rawQuery(
      '''
      SELECT p.name, p.player_id, mp.team_id, mp.goals, mp.assists, mp.rating
      FROM match_players mp
      JOIN players p ON p.player_id = mp.player_id
      JOIN matches m ON m.match_id = mp.match_id
      WHERE m.season_id = ? AND m.tournament_id = ? AND substr(m.date,1,10) = ?
        AND mp.minutes > 0
      ORDER BY mp.rating DESC, mp.goals DESC, mp.assists DESC LIMIT 1
    ''',
      <Object?>[c.seasonId, c.leagueId, c.date],
    );
    if (stars.isNotEmpty && ((stars.first['goals'] as int? ?? 0) + (stars.first['assists'] as int? ?? 0)) >= 1) {
      final Map<String, Object?> s = stars.first;
      final String club = table
          .firstWhere((_Row r) => r.id == s['team_id'], orElse: () => table.first)
          .name;
      final int g = s['goals'] as int? ?? 0;
      final int a = s['assists'] as int? ?? 0;
      out.add(
        NewsItem(
          ref: 'star:${c.seasonId}:${c.leagueId}:${c.date}',
          seasonId: c.seasonId,
          date: c.date,
          scope: 'league',
          category: 'player',
          headline: _t('star:${c.date}:h', <String>[
            '${s['name']} jadi pemain terbaik pekan ini',
            'Aksi bintang: ${s['name']} ($club) curi perhatian',
          ]),
          body:
              '${s['name']} dari $club tampil menonjol pekan ini dengan '
              '${g > 0 ? '$g gol' : ''}'
              '${g > 0 && a > 0 ? ' dan ' : ''}'
              '${a > 0 ? '$a assist' : ''}.',
          importance: 2,
          teamId: s['team_id'] as int,
          playerId: s['player_id'] as int,
        ),
      );
    }

    // Golden boot race.
    if (games >= 4 && games % 4 == 0) {
      final List<Map<String, Object?>> race = await db.rawQuery(
        '''
        SELECT p.name, mp.team_id, SUM(mp.goals) AS goals FROM match_players mp
        JOIN players p ON p.player_id = mp.player_id
        JOIN matches m ON m.match_id = mp.match_id
        WHERE m.season_id = ? AND m.tournament_id = ? AND substr(m.date,1,10) <= ?
        GROUP BY mp.player_id HAVING goals > 0
        ORDER BY goals DESC, p.name LIMIT 2
      ''',
        <Object?>[c.seasonId, c.leagueId, c.date],
      );
      if (race.length == 2) {
        final int a = race[0]['goals'] as int;
        final int b = race[1]['goals'] as int;
        out.add(
          NewsItem(
            ref: 'boot:${c.seasonId}:${c.leagueId}:$games',
            seasonId: c.seasonId,
            date: c.date,
            scope: 'league',
            category: 'player',
            headline: a == b
                ? '${race[0]['name']} dan ${race[1]['name']} sama-sama $a gol di daftar top skor'
                : '${race[0]['name']} pimpin perburuan sepatu emas dengan $a gol',
            body:
                '${race[0]['name']} mengemas $a gol liga, '
                '${a == b ? 'sama banyak dengan' : 'unggul ${a - b} gol dari'} '
                '${race[1]['name']}. $games pekan telah dimainkan.',
            importance: 3,
            playerId: null,
          ),
        );
      }
    }
    return out;
  }

  // ----------------------------------------------------------- group stages

  Future<List<NewsItem>> _groupStories(_Ctx c, List<_Match> matches) async {
    final Set<String> seen = <String>{};
    final List<NewsItem> out = <NewsItem>[];
    for (final _Match m in matches) {
      if (m.groupId == null) continue;
      if (!seen.add('${m.tournamentId}:${m.groupId}')) continue;
      final List<_Row> table = await _table(
        c.seasonId,
        m.tournamentId,
        c.date,
        groupId: m.groupId,
      );
      if (table.length < 3) continue;
      final _Row top = table.first;
      if (top.played < 2 || top.pts - table[1].pts < 2) continue;
      final String groupName = String.fromCharCode(64 + m.groupId!);
      out.add(
        NewsItem(
          ref: 'grp:${c.seasonId}:${m.tournamentId}:${m.groupId}:${top.played}',
          seasonId: c.seasonId,
          date: c.date,
          scope: _scopeOf(c, m.tournamentId, m.org),
          category: 'table',
          headline: _t('grp:${m.tournamentId}:${m.groupId}:${top.played}:h', <String>[
            '${top.name} kuasai Grup $groupName',
            '${top.name} pimpin Grup $groupName di ${m.tourName}',
          ]),
          body:
              '${top.name} punya ${top.pts} poin dari ${top.played} laga '
              '(selisih gol ${_gd(top)}), unggul ${top.pts - table[1].pts} poin dari '
              '${table[1].name}.',
          importance: 2,
          teamId: top.id,
        ),
      );
    }
    return out;
  }

  // -------------------------------------------------------------- transfers

  Future<List<NewsItem>> _transferStories(_Ctx c) async {
    final List<Map<String, Object?>> meta = await db.query(
      t.news,
      columns: <String>['body'],
      where: "ref = 'meta:transfers'",
      limit: 1,
    );
    if (meta.isEmpty) return const <NewsItem>[];
    final int since = int.tryParse(meta.first['body'] as String) ?? 0;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT pt.transfer_id, pt.value, pt.date, p.name AS player, p.player_id,
             p.power, ft.name AS from_name, tt.name AS to_name,
             pt.to_team_id, tt.country_id, ct.confederation
      FROM player_transfers pt
      JOIN players p ON p.player_id = pt.player_id
      LEFT JOIN teams ft ON ft.team_id = pt.from_team_id
      JOIN teams tt ON tt.team_id = pt.to_team_id
      LEFT JOIN countries ct ON ct.country_id = tt.country_id
      WHERE pt.transfer_id > ?
      ORDER BY pt.transfer_id
      LIMIT 40
    ''',
      <Object?>[since],
    );
    if (rows.isEmpty) return const <NewsItem>[];
    final List<NewsItem> out = <NewsItem>[];
    final int userCountry = await _userCountry(c.leagueId);
    int maxId = since;
    for (final Map<String, Object?> r in rows) {
      final int id = r['transfer_id'] as int;
      maxId = math.max(maxId, id);
      final int fee = (r['value'] as int?) ?? 0;
      if (fee < 1000000) continue;
      final String region = _confederations[r['confederation']] ?? '';
      final String scope = r['country_id'] == userCountry
          ? 'league'
          : (region == c.region ? 'region' : 'world');
      final String player = r['player'] as String;
      final String buyer = r['to_name'] as String;
      final String? seller = r['from_name'] as String?;
      final int imp = fee >= 30000000 ? 5 : fee >= 10000000 ? 4 : fee >= 3000000 ? 3 : 2;
      out.add(
        NewsItem(
          ref: 'tf:$id',
          seasonId: c.seasonId,
          date: c.date,
          scope: scope,
          category: 'transfer',
          headline: _t('tf:$id:h', <String>[
            '$buyer rekrut $player seharga ${fmt.money(fee)}',
            'Resmi! $player gabung $buyer',
            '$player pindah ke $buyer',
          ]),
          body:
              '${seller == null ? '$player tiba' : '$buyer menuntaskan perekrutan $player dari $seller'} '
              'dengan nilai ${fmt.money(fee)}. Pemain ini '
              '${imp >= 4 ? 'menjadi salah satu transfer terbesar bursa kali ini.' : 'diharapkan memperkuat skuad.'}',
          importance: imp,
          teamId: r['to_team_id'] as int,
          playerId: r['player_id'] as int,
        ),
      );
    }
    await db.update(
      t.news,
      <String, Object?>{'body': '$maxId'},
      where: "ref = 'meta:transfers'",
    );
    return out;
  }

  // --------------------------------------------------------------- helpers

  String _scopeOf(_Ctx c, int tournamentId, int org) {
    if (tournamentId == c.leagueId || org == 3) return 'league';
    final String? region = _cupRegions[tournamentId];
    if (region == null) return 'world';
    return region == c.region ? 'region' : 'world';
  }

  Future<List<_Match>> _matches(_Ctx c) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT m.match_id, m.tournament_id, m.home_team_id, m.away_team_id,
             m.home_goals, m.away_goals, m.winner_id, m.phase, m.group_id,
             th.name AS hn, ta.name AS an, th.power AS hp, ta.power AS ap,
             tu.name AS tn, tu.organization AS org
      FROM matches m
      JOIN teams th ON th.team_id = m.home_team_id
      JOIN teams ta ON ta.team_id = m.away_team_id
      JOIN tournaments tu ON tu.tournament_id = m.tournament_id
      WHERE m.season_id = ? AND substr(m.date,1,10) = ? AND m.status = ?
        AND m.home_goals IS NOT NULL AND m.away_goals IS NOT NULL
        AND m.tournament_id != 9999
    ''',
      <Object?>[c.seasonId, c.date, t.matchFinished],
    );
    return <_Match>[
      for (final Map<String, Object?> r in rows)
        _Match(
          matchId: r['match_id'] as int,
          tournamentId: r['tournament_id'] as int,
          homeId: r['home_team_id'] as int,
          awayId: r['away_team_id'] as int,
          hg: r['home_goals'] as int,
          ag: r['away_goals'] as int,
          winnerId: _winner(r),
          phase: (r['phase'] as int?) ?? 1,
          groupId: r['group_id'] as int?,
          home: r['hn'] as String,
          away: r['an'] as String,
          hp: (r['hp'] as int?) ?? 0,
          ap: (r['ap'] as int?) ?? 0,
          tourName: r['tn'] as String,
          org: (r['org'] as int?) ?? 1,
        ),
    ];
  }

  int _winner(Map<String, Object?> r) {
    final int hg = r['home_goals'] as int;
    final int ag = r['away_goals'] as int;
    if (hg == ag) return (r['winner_id'] as int?) ?? 0;
    return hg > ag ? r['home_team_id'] as int : r['away_team_id'] as int;
  }

  /// "the semi-finals", "the quarter-finals"... from how many ties the phase has.
  Future<String?> _stage(_Ctx c, _Match m) async {
    final int ties =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*) FROM (
              SELECT DISTINCT MIN(home_team_id, away_team_id) AS a,
                     MAX(home_team_id, away_team_id) AS b
              FROM matches WHERE season_id = ? AND tournament_id = ?
                AND phase = ? AND group_id IS NULL
            )
          ''',
            <Object?>[c.seasonId, m.tournamentId, m.phase],
          ),
        ) ??
        0;
    return switch (ties) {
      1 => 'final',
      2 => 'semifinal',
      4 => 'perempat final',
      8 => 'babak 16 besar',
      _ => null,
    };
  }

  Future<bool> _isFinal(_Ctx c, _Match m) async {
    final int ties =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM matches WHERE season_id = ? AND tournament_id = ? '
            'AND phase = ? AND group_id IS NULL',
            <Object?>[c.seasonId, m.tournamentId, m.phase],
          ),
        ) ??
        0;
    final int maxPhase =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT MAX(phase) FROM matches WHERE season_id = ? AND tournament_id = ?',
            <Object?>[c.seasonId, m.tournamentId],
          ),
        ) ??
        0;
    final int open =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM matches WHERE season_id = ? AND tournament_id = ? AND status != ?',
            <Object?>[c.seasonId, m.tournamentId, t.matchFinished],
          ),
        ) ??
        0;
    return ties == 1 && m.phase == maxPhase && open == 0;
  }

  Future<Map<String, Object?>> _cupRun(_Ctx c, int tournamentId, int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS played,
        SUM(CASE WHEN home_team_id = ?1 THEN home_goals ELSE away_goals END) AS gf,
        SUM(CASE WHEN home_team_id = ?1 THEN away_goals ELSE home_goals END) AS ga,
        SUM(CASE WHEN (home_team_id = ?1 AND home_goals > away_goals)
                   OR (away_team_id = ?1 AND away_goals > home_goals) THEN 1 ELSE 0 END) AS wins
      FROM matches WHERE season_id = ?2 AND tournament_id = ?3 AND status = ?4
        AND (home_team_id = ?1 OR away_team_id = ?1)
    ''',
      <Object?>[teamId, c.seasonId, tournamentId, t.matchFinished],
    );
    return rows.first;
  }

  Future<String> _tourName(int id) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      columns: <String>['name'],
      where: 'tournament_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? 'League' : rows.first['name'] as String;
  }

  Future<int> _relegationSpots(int tournamentId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      columns: <String>['relegation_spots'],
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tournamentId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : ((rows.first['relegation_spots'] as int?) ?? 0);
  }

  Future<int> _userCountry(int leagueId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournamentCountries,
      columns: <String>['country_id'],
      where: 'tournament_id = ?',
      whereArgs: <Object?>[leagueId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['country_id'] as int;
  }

  /// Table after [date] (or strictly before it). Pass [groupId] for a group.
  Future<List<_Row>> _table(
    int seasonId,
    int tournamentId,
    String date, {
    bool strictlyBefore = false,
    int? groupId,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT team_id, name, COUNT(*) AS played, SUM(pts) AS pts,
             SUM(w) AS w, SUM(d) AS d, SUM(l) AS l, SUM(gf) AS gf, SUM(ga) AS ga
      FROM (
        SELECT m.home_team_id AS team_id, th.name AS name,
          CASE WHEN m.home_goals > m.away_goals THEN 3 WHEN m.home_goals = m.away_goals THEN 1 ELSE 0 END AS pts,
          m.home_goals > m.away_goals AS w, m.home_goals = m.away_goals AS d,
          m.home_goals < m.away_goals AS l, m.home_goals AS gf, m.away_goals AS ga
        FROM matches m JOIN teams th ON th.team_id = m.home_team_id
        WHERE m.season_id = ?1 AND m.tournament_id = ?2 AND m.status = ?3
          AND substr(m.date,1,10) ${strictlyBefore ? '<' : '<='} ?4
          ${groupId == null ? '' : 'AND m.group_id = ?5'}
        UNION ALL
        SELECT m.away_team_id, ta.name,
          CASE WHEN m.away_goals > m.home_goals THEN 3 WHEN m.home_goals = m.away_goals THEN 1 ELSE 0 END,
          m.away_goals > m.home_goals, m.home_goals = m.away_goals,
          m.away_goals < m.home_goals, m.away_goals, m.home_goals
        FROM matches m JOIN teams ta ON ta.team_id = m.away_team_id
        WHERE m.season_id = ?1 AND m.tournament_id = ?2 AND m.status = ?3
          AND substr(m.date,1,10) ${strictlyBefore ? '<' : '<='} ?4
          ${groupId == null ? '' : 'AND m.group_id = ?5'}
      ) GROUP BY team_id
    ''',
      <Object?>[seasonId, tournamentId, t.matchFinished, date, ?groupId],
    );
    final List<_Row> table = <_Row>[
      for (final Map<String, Object?> r in rows)
        _Row(
          id: r['team_id'] as int,
          name: r['name'] as String,
          played: r['played'] as int,
          pts: (r['pts'] as int?) ?? 0,
          wins: (r['w'] as int?) ?? 0,
          draws: (r['d'] as int?) ?? 0,
          losses: (r['l'] as int?) ?? 0,
          gf: (r['gf'] as int?) ?? 0,
          ga: (r['ga'] as int?) ?? 0,
        ),
    ];
    table.sort((_Row a, _Row b) {
      if (b.pts != a.pts) return b.pts.compareTo(a.pts);
      if ((b.gf - b.ga) != (a.gf - a.ga)) {
        return (b.gf - b.ga).compareTo(a.gf - a.ga);
      }
      if (b.gf != a.gf) return b.gf.compareTo(a.gf);
      return a.name.compareTo(b.name);
    });
    return table;
  }

  /// [goalsFor, goalsAgainst] of a club's recent league games, newest first.
  Future<List<List<int>>> _form(_Ctx c, int tournamentId, int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT home_team_id, home_goals, away_goals FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND substr(date,1,10) <= ? AND (home_team_id = ? OR away_team_id = ?)
      ORDER BY date DESC, match_id DESC LIMIT 14
    ''',
      <Object?>[c.seasonId, tournamentId, t.matchFinished, c.date, teamId, teamId],
    );
    return <List<int>>[
      for (final Map<String, Object?> r in rows)
        r['home_team_id'] == teamId
            ? <int>[r['home_goals'] as int, r['away_goals'] as int]
            : <int>[r['away_goals'] as int, r['home_goals'] as int],
    ];
  }

  int _run(List<List<int>> form, bool Function(List<int>) test) {
    int n = 0;
    for (final List<int> g in form) {
      if (!test(g)) break;
      n++;
    }
    return n;
  }

  String _gd(_Row r) {
    final int d = r.gf - r.ga;
    return d > 0 ? '+$d' : '$d';
  }

  String _ord(int n) {
    return 'peringkat $n';
  }

  /// Deterministic pick from a template pool, seeded by [seed].
  String _t(String seed, List<String> options) =>
      options[seed.hashCode.abs() % options.length];

  /// Display name of a region key, for callers that need one.
  static String regionName(String key) => _regionNames[key] ?? key;
}

class _Ctx {
  const _Ctx(this.seasonId, this.date, this.leagueId, this.region);

  final int seasonId;
  final String date;
  final int leagueId;
  final String region;
}

class _Match {
  const _Match({
    required this.matchId,
    required this.tournamentId,
    required this.homeId,
    required this.awayId,
    required this.hg,
    required this.ag,
    required this.winnerId,
    required this.phase,
    required this.groupId,
    required this.home,
    required this.away,
    required this.hp,
    required this.ap,
    required this.tourName,
    required this.org,
  });

  final int matchId;
  final int tournamentId;
  final int homeId;
  final int awayId;
  final int hg;
  final int ag;
  final int winnerId;
  final int phase;
  final int? groupId;
  final String home;
  final String away;
  final int hp;
  final int ap;
  final String tourName;
  final int org;
}

class _Row {
  const _Row({
    required this.id,
    required this.name,
    required this.played,
    required this.pts,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.gf,
    required this.ga,
  });

  final int id;
  final String name;
  final int played;
  final int pts;
  final int wins;
  final int draws;
  final int losses;
  final int gf;
  final int ga;
}
