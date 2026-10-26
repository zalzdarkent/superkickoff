import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;

/// Service for seeding bundled club logos and syncing/fetching new club logos
/// via API (TheSportsDB) as Base64 strings saved directly to the SQLite database.
class ClubLogoService {
  const ClubLogoService();

  static const String _sportsDbBase =
      'https://www.thesportsdb.com/api/v1/json/123';

  /// Seeds bundled base64 logos from the asset JSON for any teams that don't have one yet.
  Future<int> seedDefaultLogos(Database db) async {
    try {
      final String raw = await rootBundle.loadString(
        'assets/data/default_club_logos.json',
      );
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final Batch batch = db.batch();
      int count = 0;
      for (final MapEntry<String, dynamic> entry in data.entries) {
        final int? teamId = int.tryParse(entry.key);
        final String? b64 = entry.value as String?;
        if (teamId != null && b64 != null && b64.isNotEmpty) {
          final String clean =
              b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64;
          batch.rawUpdate(
            'UPDATE ${t.teams} SET logo_base64 = ? WHERE team_id = ? AND (logo_base64 IS NULL OR LENGTH(logo_base64) = 0 OR logo_base64 LIKE "data:image%")',
            <Object?>[clean, teamId],
          );
          count++;
        }
      }
      await batch.commit(noResult: true);
      return count;
    } catch (e) {
      if (kDebugMode && !e.toString().contains('Binding has not yet been initialized')) {
        debugPrint('Failed to seed default club logos: $e');
      }
      return 0;
    }
  }

  /// Fetches a badge for a club from TheSportsDB API and saves it into SQLite as Base64.
  Future<String?> fetchAndSaveLogo(
    Database db,
    int teamId,
    String teamName,
  ) async {
    try {
      final String? badgeUrl = await _lookupBadgeUrl(teamName);
      if (badgeUrl == null || badgeUrl.isEmpty) return null;
      final Uint8List? bytes = await _downloadBytes(badgeUrl);
      if (bytes == null || bytes.isEmpty) return null;
      final String b64 = base64Encode(bytes);
      await db.rawUpdate(
        'UPDATE ${t.teams} SET logo_base64 = ? WHERE team_id = ?',
        <Object?>[b64, teamId],
      );
      return b64;
    } catch (e) {
      debugPrint('fetchAndSaveLogo error for $teamName: $e');
      return null;
    }
  }

  /// Syncs online logos for all teams in a given country (defaults to Indonesia)
  /// that currently lack a logo in the database.
  Future<int> syncMissingLogos(
    Database db, {
    int countryId = 94,
    void Function(int current, int total, String name)? onProgress,
  }) async {
    final List<Map<String, Object?>> missing = await db.rawQuery(
      'SELECT team_id, name FROM ${t.teams} WHERE country_id = ? AND (logo_base64 IS NULL OR LENGTH(logo_base64) = 0)',
      <Object?>[countryId],
    );
    int successCount = 0;
    for (int i = 0; i < missing.length; i++) {
      final int teamId = missing[i]['team_id'] as int;
      final String name = missing[i]['name'] as String;
      onProgress?.call(i + 1, missing.length, name);
      final String? result = await fetchAndSaveLogo(db, teamId, name);
      if (result != null) {
        successCount++;
      }
    }
    return successCount;
  }

  /// Syncs online logos for all division 1 clubs across Asian countries (confederation 5)
  /// that currently lack a logo in the database.
  Future<int> syncTopAsianLogos(
    Database db, {
    void Function(int current, int total, String name)? onProgress,
  }) async {
    final List<Map<String, Object?>> missing = await db.rawQuery(
      '''
      SELECT t.team_id, t.name, c.name AS country_name
      FROM ${t.teams} t
      JOIN ${t.countries} c ON c.country_id = t.country_id
      WHERE c.confederation = 5 AND t.division = 1
        AND (t.logo_base64 IS NULL OR LENGTH(t.logo_base64) = 0)
      ORDER BY c.name, t.power DESC
      ''',
    );
    int successCount = 0;
    for (int i = 0; i < missing.length; i++) {
      final int teamId = missing[i]['team_id'] as int;
      final String name = missing[i]['name'] as String;
      onProgress?.call(i + 1, missing.length, name);
      final String? result = await fetchAndSaveLogo(db, teamId, name);
      if (result != null) {
        successCount++;
      }
    }
    return successCount;
  }

  Future<String?> _lookupBadgeUrl(String name) async {
    // 1. Wikipedia PageImages API (with pilicense=any for official club crests)
    try {
      final String query = Uri.encodeComponent('$name football club');
      final Uri searchUri = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=$query&format=json',
      );
      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final HttpClientRequest req = await client.getUrl(searchUri);
      req.headers.set(
        'User-Agent',
        'SuperkickoffApp/1.0 (contact@superkickoff.com)',
      );
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode == 200) {
        final String body = await resp.transform(utf8.decoder).join();
        final Map<String, dynamic> json =
            jsonDecode(body) as Map<String, dynamic>;
        final List<dynamic>? searchResults =
            json['query']?['search'] as List<dynamic>?;
        if (searchResults != null && searchResults.isNotEmpty) {
          final String title = searchResults.first['title'] as String;
          if (!title.toLowerCase().contains('season') &&
              !title.toLowerCase().contains('list of')) {
            final Uri imgUri = Uri.parse(
              'https://en.wikipedia.org/w/api.php?action=query&titles=${Uri.encodeComponent(title)}&prop=pageimages&pilicense=any&pithumbsize=128&format=json',
            );
            final HttpClientRequest imgReq = await client.getUrl(imgUri);
            imgReq.headers.set(
              'User-Agent',
              'SuperkickoffApp/1.0 (contact@superkickoff.com)',
            );
            final HttpClientResponse imgResp = await imgReq.close();
            if (imgResp.statusCode == 200) {
              final String imgBody =
                  await imgResp.transform(utf8.decoder).join();
              final Map<String, dynamic> imgJson =
                  jsonDecode(imgBody) as Map<String, dynamic>;
              final Map<String, dynamic>? pages =
                  imgJson['query']?['pages'] as Map<String, dynamic>?;
              if (pages != null) {
                for (final dynamic page in pages.values) {
                  final String? thumb =
                      page['thumbnail']?['source'] as String?;
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

    // 2. Fallback to TheSportsDB API
    final String clean = name
        .replaceAll(
          RegExp(r'\s+(FC|United|City|1973)$', caseSensitive: false),
          '',
        )
        .trim();
    final List<String> queries = <String>[
      name,
      if (clean != name) clean,
      name.replaceAll('-', ' '),
    ];
    for (final String q in queries) {
      try {
        final Uri uri = Uri.parse(
          '$_sportsDbBase/searchteams.php?t=${Uri.encodeComponent(q)}',
        );
        final HttpClient client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 6);
        final HttpClientRequest request = await client.getUrl(uri);
        request.headers.set('User-Agent', 'Mozilla/5.0 Superkickoff/1.0');
        final HttpClientResponse response = await request.close();
        if (response.statusCode == 200) {
          final String body = await response.transform(utf8.decoder).join();
          final Map<String, dynamic> json =
              jsonDecode(body) as Map<String, dynamic>;
          final List<dynamic>? teams = json['teams'] as List<dynamic>?;
          if (teams != null && teams.isNotEmpty) {
            final dynamic first = teams.first;
            final String? badge = first['strBadge'] as String?;
            if (badge != null && badge.isNotEmpty) {
              return badge;
            }
          }
        }
      } catch (_) {}
    }
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
