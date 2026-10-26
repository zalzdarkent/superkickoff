import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/models.dart';

/// Shared small widgets used across screens.

/// Club crest image or rounded placeholder built from the club colors + abbreviation.
class CrestAvatar extends StatelessWidget {
  const CrestAvatar({super.key, required this.team, this.radius = 18});

  final Team team;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? logoBase64 = team.logoBase64;
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(logoBase64);
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
    final Color primary = _colorFor(team.teamId);
    final String initials = team.abbreviation.isNotEmpty
        ? team.abbreviation.toUpperCase()
        : (team.name.length >= 2
            ? team.name.substring(0, 2).toUpperCase()
            : team.name.toUpperCase());
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
        : (positionId <= 4 ? 2 : (positionId <= 8 ? 3 : 4));
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
