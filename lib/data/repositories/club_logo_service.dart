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
          batch.rawUpdate(
            'UPDATE ${t.teams} SET logo_base64 = ? WHERE team_id = ? AND (logo_base64 IS NULL OR LENGTH(logo_base64) = 0)',
            <Object?>[b64, teamId],
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

  Future<String?> _lookupBadgeUrl(String name) async {
    final String clean = name
        .replaceAll(
          RegExp(r'\s+(FC|United|City|1973)$', caseSensitive: false),
          '',
        )
        .trim();
    final List<String> queries = <String>[name, if (clean != name) clean];
    for (final String q in queries) {
      try {
        final Uri uri = Uri.parse(
          '$_sportsDbBase/searchteams.php?t=${Uri.encodeComponent(q)}',
        );
        final HttpClient client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
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
