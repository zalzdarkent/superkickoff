import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/country_names.dart';
import '../../data/models/models.dart';
import '../theme.dart';

/// Shared small widgets used across screens.

class LoadingButtonContent extends StatelessWidget {
  const LoadingButtonContent({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const ButtonLoadingIndicator(),
        const SizedBox(width: 8),
        child,
      ],
    );
  }
}

class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: IconTheme.of(context).color,
    ),
  );
}

/// Club crest image or rounded placeholder built from the club colors + abbreviation.
class CrestAvatar extends StatelessWidget {
  const CrestAvatar({
    super.key,
    required Team this.team,
    this.radius = 18,
  })  : teamId = null,
        name = null,
        abbreviation = null,
        logoBase64 = null;

  const CrestAvatar.raw({
    super.key,
    required this.teamId,
    required this.name,
    required this.abbreviation,
    this.logoBase64,
    this.radius = 18,
  }) : team = null;

  final Team? team;
  final int? teamId;
  final String? name;
  final String? abbreviation;
  final String? logoBase64;
  final double radius;

  int get effectiveTeamId => team?.teamId ?? teamId ?? 0;
  String get effectiveName => team?.name ?? name ?? '';
  String get effectiveAbbreviation => team?.abbreviation ?? abbreviation ?? '';
  String? get effectiveLogoBase64 => team?.logoBase64 ?? logoBase64;

  @override
  Widget build(BuildContext context) {
    final String? b64 = effectiveLogoBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final String cleanB64 =
            b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64;
        final Uint8List bytes = base64Decode(cleanB64.trim());
        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image.memory(
            bytes,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _buildPlaceholder(),
          ),
        );
      } catch (_) {
        return _buildPlaceholder();
      }
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final Color primary = _colorFor(effectiveTeamId);
    final String abbr = effectiveAbbreviation;
    final String tName = effectiveName;
    final String initials = abbr.isNotEmpty
        ? abbr.toUpperCase()
        : (tName.length >= 2
            ? tName.substring(0, 2).toUpperCase()
            : tName.toUpperCase());
    return CircleAvatar(
      radius: radius,
      backgroundColor: primary,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }

  static Color _colorFor(int id) {
    final List<Color> palette = <Color>[
      const Color(0xFFE11D48),
      const Color(0xFF2563EB),
      const Color(0xFF22C55E),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF97316),
      const Color(0xFFEC4899),
    ];
    return palette[id % palette.length];
  }
}

/// Tournament / League crest badge or rounded placeholder with trophy icon.
class TournamentAvatar extends StatelessWidget {
  const TournamentAvatar({
    super.key,
    this.tournament,
    this.tournamentId,
    this.name,
    this.logoBase64,
    this.radius = 18,
  });

  final Tournament? tournament;
  final int? tournamentId;
  final String? name;
  final String? logoBase64;
  final double radius;

  int get effectiveTournamentId =>
      tournament?.tournamentId ?? tournamentId ?? 0;
  String get effectiveName => tournament?.name ?? name ?? '';
  String? get effectiveLogoBase64 => tournament?.logoBase64 ?? logoBase64;

  @override
  Widget build(BuildContext context) {
    final String? b64 = effectiveLogoBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        final String cleanB64 =
            b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64;
        final Uint8List bytes = base64Decode(cleanB64.trim());
        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image.memory(
            bytes,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _buildPlaceholder(),
          ),
        );
      } catch (_) {
        return _buildPlaceholder();
      }
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.surfaceCard,
      child: Icon(
        Icons.emoji_events_outlined,
        size: radius * 1.1,
        color: AppTheme.accent,
      ),
    );
  }
}

/// 0-5 star rating display.
class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.size = 12});

  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= value ? Icons.star : Icons.star_border,
            size: size,
            color: i <= value ? Colors.amber : Colors.grey,
          ),
      ],
    );
  }
}

/// Position badge with color by position type.
class PositionBadge extends StatelessWidget {
  const PositionBadge({super.key, required this.positionId, this.profile});

  final int positionId;

  /// Preferred foot from the database ('D' right, 'I' left). Used to tell
  /// full-backs and wingers apart.
  final String? profile;

  /// Compact label shown in the UI.
  static String labelFor(int positionId, {String? profile}) {
    final bool left = (profile ?? 'D').toUpperCase() == 'I';
    return switch (positionId) {
      1 => 'GK',
      2 || 3 => 'CB',
      4 => left ? 'LB' : 'RB',
      5 => 'CDM',
      6 => 'CAM',
      7 => 'CM',
      8 || 9 => left ? 'LW' : 'RW',
      10 => 'ST',
      11 => 'CF',
      _ => '?',
    };
  }

  @override
  Widget build(BuildContext context) {
    final int type = positionId == 1
        ? 1
        : (positionId <= 4 ? 2 : (positionId <= 7 ? 3 : 4));
    final Color color = switch (type) {
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFF3B82F6),
      3 => const Color(0xFF22C55E),
      _ => const Color(0xFFEF4444),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        labelFor(positionId, profile: profile),
        style: TextStyle(
          color: color.withAlpha(255),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Fitness bar 0-100.
class FitnessBar extends StatelessWidget {
  const FitnessBar({super.key, required this.value, this.width = 42});

  final int value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color color = value > 70
        ? Colors.green
        : value > 40
        ? Colors.orange
        : Colors.red;
    return SizedBox(
      width: width,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value / 100),
        duration: const Duration(milliseconds: 250),
        builder: (BuildContext context, double v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: Colors.grey.shade800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text('$value', style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

/// Card with a bold section title.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                ?trailing,
                ?action,
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Full-width stat chip row used on the overview.
class StatChips extends StatelessWidget {
  const StatChips({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items,
    );
  }
}

Column statChip(String label, String value, {IconData? icon, Color? color}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ],
    );

/// Country flag image badge (via flagcdn) with emoji / ISO code fallback.
class CountryFlagAvatar extends StatelessWidget {
  const CountryFlagAvatar({
    super.key,
    this.iso2,
    this.countryId,
    this.name,
    this.width = 28,
    this.height = 20,
    this.borderRadius = 4,
  });

  final Object? iso2;
  final int? countryId;
  final String? name;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final String? url = countryFlagUrl(
      iso2,
      countryId: countryId,
      name: name,
    );
    final Widget fallback = _buildFallback();
    if (url == null) return fallback;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _buildFallback() {
    final String emoji = countryFlag(iso2, countryId: countryId, name: name);
    final String code = countryFlagCode(
      iso2,
      countryId: countryId,
      name: name,
    ).toUpperCase();
    final String label = emoji.isNotEmpty
        ? emoji
        : (code.length >= 2 ? code.substring(0, 2) : '🏳️');
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: height * 0.58,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
