import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;

/// Service for seeding bundled tournament/league logos and fetching missing logos
/// via Wikipedia / TheSportsDB as Base64 strings saved directly to SQLite tournaments.
class LeagueLogoService {
  const LeagueLogoService();

  static const String _sportsDbBase =
      'https://www.thesportsdb.com/api/v1/json/123';

  /// Seeds bundled base64 league logos from the asset JSON for any tournaments that lack one.
  Future<int> seedDefaultLogos(Database db) async {
    try {
      final String raw = await rootBundle.loadString(
        'assets/data/default_league_logos.json',
      );
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final Batch batch = db.batch();
      int count = 0;
      for (final MapEntry<String, dynamic> entry in data.entries) {
        final int? tournamentId = int.tryParse(entry.key);
        final String? b64 = entry.value as String?;
        if (tournamentId != null && b64 != null && b64.isNotEmpty) {
          batch.rawUpdate(
            'UPDATE ${t.tournaments} SET logo_base64 = ? WHERE tournament_id = ? AND (logo_base64 IS NULL OR LENGTH(logo_base64) = 0)',
            <Object?>[b64, tournamentId],
          );
          count++;
        }
      }
      await batch.commit(noResult: true);
      return count;
    } catch (e) {
      if (kDebugMode &&
          !e.toString().contains('Binding has not yet been initialized')) {
        debugPrint('Failed to seed default league logos: $e');
      }
      return 0;
    }
  }

  /// Fetches a tournament badge from Wikipedia / TheSportsDB and saves it to SQLite.
  Future<String?> fetchAndSaveLogo(
    Database db,
    int tournamentId,
    String tournamentName,
  ) async {
    try {
      final String? badgeUrl = await _lookupBadgeUrl(tournamentName);
      if (badgeUrl == null || badgeUrl.isEmpty) return null;
      final Uint8List? bytes = await _downloadBytes(badgeUrl);
      if (bytes == null || bytes.isEmpty) return null;
      final String b64 = base64Encode(bytes);
      await db.rawUpdate(
        'UPDATE ${t.tournaments} SET logo_base64 = ? WHERE tournament_id = ?',
        <Object?>[b64, tournamentId],
      );
      return b64;
    } catch (e) {
      debugPrint('fetchAndSaveLogo error for league $tournamentName: $e');
      return null;
    }
  }

  /// Syncs online logos for all tournaments that currently lack a logo in the database.
  Future<int> syncMissingLogos(
    Database db, {
    void Function(int current, int total, String name)? onProgress,
  }) async {
    final List<Map<String, Object?>> missing = await db.rawQuery(
      'SELECT tournament_id, name FROM ${t.tournaments} WHERE logo_base64 IS NULL OR LENGTH(logo_base64) = 0',
    );
    int successCount = 0;
    for (int i = 0; i < missing.length; i++) {
      final int tournamentId = missing[i]['tournament_id'] as int;
      final String name = missing[i]['name'] as String;
      onProgress?.call(i + 1, missing.length, name);
      final String? result = await fetchAndSaveLogo(db, tournamentId, name);
      if (result != null) {
        successCount++;
      }
    }
    return successCount;
  }

  Future<String?> _lookupBadgeUrl(String name) async {
    final List<String> queries = <String>[
      name,
      '$name league',
      '$name tournament',
      '$name football',
    ];

    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);

    for (final String q in queries) {
      try {
        final Uri searchUri = Uri.parse(
          'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(q)}&format=json',
        );
        final HttpClientRequest req = await client.getUrl(searchUri);
        req.headers.set('User-Agent', 'SuperkickoffApp/1.0 (contact@superkickoff.com)');
        final HttpClientResponse resp = await req.close();
        if (resp.statusCode == 200) {
          final String body = await resp.transform(utf8.decoder).join();
          final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
          final List<dynamic>? searchResults = json['query']?['search'] as List<dynamic>?;
          if (searchResults != null && searchResults.isNotEmpty) {
            final String title = searchResults.first['title'] as String;
            if (!title.toLowerCase().contains('season') && !title.toLowerCase().contains('list of')) {
              final Uri imgUri = Uri.parse(
                'https://en.wikipedia.org/w/api.php?action=query&titles=${Uri.encodeComponent(title)}&prop=pageimages&pilicense=any&pithumbsize=128&format=json',
              );
              final HttpClientRequest imgReq = await client.getUrl(imgUri);
              imgReq.headers.set('User-Agent', 'SuperkickoffApp/1.0 (contact@superkickoff.com)');
              final HttpClientResponse imgResp = await imgReq.close();
              if (imgResp.statusCode == 200) {
                final String imgBody = await imgResp.transform(utf8.decoder).join();
                final Map<String, dynamic> imgJson = jsonDecode(imgBody) as Map<String, dynamic>;
                final Map<String, dynamic>? pages = imgJson['query']?['pages'] as Map<String, dynamic>?;
                if (pages != null) {
                  for (final dynamic page in pages.values) {
                    final String? thumb = page['thumbnail']?['source'] as String?;
                    if (thumb != null && thumb.isNotEmpty) {
                      return thumb;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: TheSportsDB
    try {
      final Uri uri = Uri.parse(
        '$_sportsDbBase/searchleagues.php?s=${Uri.encodeComponent(name)}',
      );
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'SuperkickoffApp/1.0 (contact@superkickoff.com)');
      final HttpClientResponse response = await request.close();
      if (response.statusCode == 200) {
        final String body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
        final List<dynamic>? leagues = json['leagues'] as List<dynamic>?;
        if (leagues != null && leagues.isNotEmpty) {
          final String? badge = leagues.first['strBadge'] as String?;
          if (badge != null && badge.isNotEmpty) return badge;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 Superkickoff/1.0');
      final HttpClientResponse response = await request.close();
      if (response.statusCode == 200) {
        final BytesBuilder builder = BytesBuilder();
        await for (final List<int> chunk in response) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      }
    } catch (_) {}
    return null;
  }
}
