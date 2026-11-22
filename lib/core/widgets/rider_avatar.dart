import 'package:flutter/material.dart';

import '../../models/avatar_config.dart';
import 'letter_avatar.dart';

/// The name is normally visible next to the portrait.
class RiderAvatar extends StatelessWidget {
  const RiderAvatar({
    super.key,
    required this.name,
    required this.config,
    this.colorKey,
    this.size = 40,
  });

  final String name;
  final AvatarConfig? config;
  final String? colorKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = config;
    if (avatar == null) {
      return LetterAvatar(name: name, colorKey: colorKey, size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: AvatarPortrait(config: avatar, size: size),
    );
  }
}

class AvatarPortrait extends StatelessWidget {
  const AvatarPortrait({super.key, required this.config, required this.size});

  final AvatarConfig config;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _Portrait(config, compact: size <= 32),
    ),
  );
}

const _palettes = <AvatarPart, Map<String, Color>>{
  AvatarPart.skin: {
    'porcelain': Color(0xFFF7D8C3),
    'fair': Color(0xFFF0C0A0),
    'warm': Color(0xFFDFA375),
    'tan': Color(0xFFBF815D),
    'brown': Color(0xFF9C623F),
    'deep': Color(0xFF714633),
  },
  AvatarPart.background: {
    'sand': Color(0xFFF1DDC0),
    'sky': Color(0xFFB9DCE5),
    'rose': Color(0xFFF0BBC2),
    'lavender': Color(0xFFDAD0F0),
    'slate': Color(0xFFBCCDCB),
  },
  AvatarPart.hairColor: {
    'black': Color(0xFF272527),
    'brown': Color(0xFF543527),
    'blond': Color(0xFFDAAB58),
    'auburn': Color(0xFF9F4735),
    'gray': Color(0xFFB6AEB0),
  },
  AvatarPart.gearColor: {
    'charcoal': Color(0xFF37434D),
    'blue': Color(0xFF325C9A),
    'red': Color(0xFFB9483E),
    'white': Color(0xFFF0EEE5),
    'ochre': Color(0xFFDBA335),
  },
};

/// Also used for the editor swatches so the preview and controls agree.
Color? avatarSwatch(AvatarPart part, String option) => _palettes[part]?[option];

const _ink = Color(0xFF292328);
const _jersey = Color(0xFF33434A);
const _jerseyLight = Color(0xFF51666D);
const _strap = Color(0xFF493C3A);

class _Portrait extends CustomPainter {
  const _Portrait(this.config, {required this.compact});

  final AvatarConfig config;
  final bool compact;

  Color _color(AvatarPart part) => avatarSwatch(part, config[part])!;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final skin = _color(AvatarPart.skin);
    final hair = _color(AvatarPart.hairColor);
    final gear = _color(AvatarPart.gearColor);
    final wear = config[AvatarPart.headwear];

    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    canvas.clipRect(bounds);
    final background = _color(AvatarPart.background);
    canvas.drawRect(bounds, Paint()..color = background);
    if (!compact) {
      _oval(canvas, 50, 48, 82, 83, _lighten(background, 0.22));
    }
    _hairBehind(canvas, hair);
    _body(canvas, skin);
    _head(canvas, skin);
    _hair(canvas, hair);
    _beard(canvas, hair, skin);
    _face(canvas, skin);
    _glasses(canvas);
    _headwear(canvas, wear, gear);
    canvas.restore();
  }

  void _body(Canvas c, Color skin) {
    _shape(
      c,
      Path()
        ..moveTo(1, 104)
        ..cubicTo(7, 89, 20, 83, 38, 81)
        ..quadraticBezierTo(50, 78, 62, 81)
        ..cubicTo(82, 83, 94, 91, 99, 104),
      _jersey,
    );
    if (!compact) {
      _shape(
        c,
        Path()
          ..moveTo(2, 102)
          ..quadraticBezierTo(10, 87, 29, 83)
          ..quadraticBezierTo(23, 92, 25, 102),
        _jerseyLight,
      );
      _shape(
        c,
        Path()
          ..moveTo(98, 102)
          ..quadraticBezierTo(90, 87, 71, 83)
          ..quadraticBezierTo(77, 92, 75, 102),
        _jerseyLight,
      );
    }
    _shape(
      c,
      Path()
        ..moveTo(35, 82)
        ..quadraticBezierTo(50, 78, 65, 82)
        ..quadraticBezierTo(63, 94, 50, 94)
        ..quadraticBezierTo(37, 94, 35, 82),
      _ink,
    );
    _shape(
      c,
      Path()
        ..moveTo(39, 76)
        ..quadraticBezierTo(50, 73, 61, 76)
        ..lineTo(61, 84)
        ..quadraticBezierTo(58, 90, 50, 90)
        ..quadraticBezierTo(42, 90, 39, 84),
      _shade(skin, 0.23),
    );
  }

  void _head(Canvas c, Color skin) {
    final shadow = _shade(skin, 0.24);
    for (final x in [24.0, 76.0]) {
      _oval(c, x, 55, 13, 17, skin);
      if (!compact) _oval(c, x, 55, 5, 9, shadow);
    }
    _shape(
      c,
      Path()
        ..moveTo(26, 39)
        ..cubicTo(26, 26, 36, 21, 50, 21)
        ..cubicTo(64, 21, 74, 26, 74, 39)
        ..quadraticBezierTo(76, 51, 74, 61)
        ..cubicTo(73, 73, 61, 84, 50, 85)
        ..cubicTo(39, 84, 27, 73, 26, 61)
        ..quadraticBezierTo(24, 50, 26, 39),
      skin,
    );
    if (!compact) {
      final cheek = Color.lerp(skin, const Color(0xFFD67970), 0.28)!;
      _oval(c, 34, 62, 9, 4, cheek);
      _oval(c, 66, 62, 9, 4, cheek);
    }
  }

  void _hairBehind(Canvas c, Color hair) {
    switch (config[AvatarPart.hair]) {
      case 'long':
        _shape(
          c,
          Path()
            ..moveTo(50, 17)
            ..cubicTo(76, 15, 86, 34, 84, 56)
            ..quadraticBezierTo(84, 73, 93, 83)
            ..quadraticBezierTo(78, 94, 63, 82)
            ..lineTo(39, 83)
            ..quadraticBezierTo(20, 95, 7, 84)
            ..quadraticBezierTo(17, 74, 16, 55)
            ..cubicTo(14, 30, 27, 18, 50, 17),
          hair,
        );
      case 'braids':
        for (final side in [-1.0, 1.0]) {
          final x = 50 + side * 26;
          for (var section = 0; section < 3; section++) {
            _oval(
              c,
              x + side * section * 1.5,
              60 + section * 10.0,
              compact ? 14.0 - section : 13.0 - section,
              15,
              section.isEven ? hair : _lighten(hair, 0.15),
            );
          }
          final end = x + side * 3;
          _line(
            c,
            Offset(end - 4, 83),
            Offset(end + 4, 83),
            const Color(0xFFBD8768),
            compact ? 2.8 : 2,
          );
        }
      case 'bun':
        _oval(c, 66, 15, 23, 21, _shade(hair, 0.2));
        if (!compact) {
          _curve(
            c,
            const Offset(61, 12),
            const Offset(69, 8),
            const Offset(73, 15),
            _lighten(hair, 0.28),
            2,
          );
        }
      case 'ponytail':
        _shape(
          c,
          Path()
            ..moveTo(72, 32)
            ..cubicTo(95, 36, 92, 54, 89, 65)
            ..quadraticBezierTo(86, 78, 94, 86)
            ..cubicTo(77, 86, 77, 73, 78, 65)
            ..quadraticBezierTo(80, 45, 68, 43),
          hair,
        );
        _line(c, const Offset(75, 38), const Offset(80, 43), _jerseyLight, 3.8);
    }
  }

  void _hair(Canvas c, Color hair) {
    switch (config[AvatarPart.hair]) {
      case 'buzz':
        _shape(
          c,
          Path()
            ..moveTo(24, 43)
            ..quadraticBezierTo(22, 18, 49, 18)
            ..quadraticBezierTo(77, 18, 76, 43)
            ..quadraticBezierTo(68, 34, 66, 29)
            ..quadraticBezierTo(48, 35, 34, 29)
            ..quadraticBezierTo(30, 39, 24, 43),
          hair,
        );
      case 'short':
        _shape(
          c,
          Path()
            ..moveTo(24, 48)
            ..cubicTo(14, 26, 34, 14, 55, 15)
            ..quadraticBezierTo(75, 14, 80, 31)
            ..quadraticBezierTo(81, 43, 74, 49)
            ..quadraticBezierTo(74, 37, 66, 32)
            ..quadraticBezierTo(52, 43, 37, 33)
            ..quadraticBezierTo(33, 43, 24, 48),
          hair,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(30, 30),
            const Offset(45, 19),
            const Offset(65, 22),
            _lighten(hair, 0.23),
            2.5,
          );
        }
      case 'curly':
        for (final (x, y) in [
          (25.0, 40.0),
          (29.0, 34.0),
          (36.0, 26.0),
          (47.0, 23.0),
          (58.0, 24.0),
          (69.0, 29.0),
          (75.0, 37.0),
        ]) {
          _oval(c, x, y, 20, y > 35 ? 19 : 23, hair);
          if (!compact && y < 35) {
            _curve(
              c,
              Offset(x - 4, y - 3),
              Offset(x, y - 8),
              Offset(x + 4, y - 4),
              _lighten(hair, 0.25),
              2,
            );
          }
        }
      case 'long':
      case 'braids':
        _shape(
          c,
          Path()
            ..moveTo(23, 48)
            ..quadraticBezierTo(15, 17, 49, 17)
            ..quadraticBezierTo(80, 15, 79, 45)
            ..quadraticBezierTo(66, 42, 56, 27)
            ..quadraticBezierTo(44, 46, 23, 48),
          hair,
        );
        if (!compact && config[AvatarPart.hair] == 'long') {
          final highlight = _lighten(hair, 0.22);
          _curve(
            c,
            const Offset(21, 48),
            const Offset(18, 70),
            const Offset(25, 80),
            highlight,
            2.8,
          );
          _curve(
            c,
            const Offset(80, 48),
            const Offset(80, 69),
            const Offset(86, 83),
            highlight,
            2.8,
          );
        }
      case 'sidePart':
        _shape(
          c,
          Path()
            ..moveTo(23, 46)
            ..cubicTo(17, 26, 28, 16, 43, 16)
            ..quadraticBezierTo(55, 12, 61, 21)
            ..quadraticBezierTo(81, 18, 80, 46)
            ..quadraticBezierTo(68, 39, 62, 26)
            ..quadraticBezierTo(49, 38, 32, 34)
            ..quadraticBezierTo(30, 42, 23, 46),
          hair,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(29, 28),
            const Offset(46, 31),
            const Offset(57, 23),
            _lighten(hair, 0.25),
            2.4,
          );
        }
      case 'undercut':
        _shape(
          c,
          Path()
            ..moveTo(25, 46)
            ..cubicTo(18, 27, 29, 18, 51, 17)
            ..quadraticBezierTo(71, 17, 78, 29)
            ..lineTo(77, 45)
            ..lineTo(69, 38)
            ..lineTo(31, 38),
          hair.withValues(alpha: 0.55),
        );
        _shape(
          c,
          Path()
            ..moveTo(26, 36)
            ..cubicTo(23, 25, 39, 21, 46, 15)
            ..quadraticBezierTo(58, 8, 66, 17)
            ..quadraticBezierTo(72, 19, 77, 29)
            ..quadraticBezierTo(58, 38, 26, 36),
          hair,
        );
      case 'fringe':
        _shape(
          c,
          Path()
            ..moveTo(23, 44)
            ..cubicTo(20, 22, 36, 15, 51, 16)
            ..quadraticBezierTo(77, 15, 79, 41)
            ..quadraticBezierTo(68, 38, 62, 45)
            ..quadraticBezierTo(54, 39, 46, 46)
            ..quadraticBezierTo(42, 42, 38, 44)
            ..quadraticBezierTo(31, 39, 23, 44),
          hair,
        );
      case 'bun':
      case 'ponytail':
        _shape(
          c,
          Path()
            ..moveTo(23, 47)
            ..cubicTo(18, 28, 34, 16, 48, 16)
            ..cubicTo(66, 13, 83, 26, 78, 46)
            ..quadraticBezierTo(70, 43, 69, 36)
            ..quadraticBezierTo(60, 34, 55, 26)
            ..quadraticBezierTo(44, 36, 32, 36)
            ..quadraticBezierTo(29, 44, 23, 47),
          hair,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(30, 29),
            const Offset(40, 20),
            const Offset(52, 20),
            _lighten(hair, 0.24),
            2.2,
          );
        }
      case 'mohawk':
        _shape(
          c,
          Path()
            ..moveTo(36, 40)
            ..quadraticBezierTo(32, 23, 44, 15)
            ..lineTo(43, 8)
            ..quadraticBezierTo(51, 12, 55, 5)
            ..lineTo(57, 13)
            ..quadraticBezierTo(72, 21, 63, 38)
            ..quadraticBezierTo(52, 31, 36, 40),
          hair,
        );
    }
  }

  void _beard(Canvas c, Color hair, Color skin) {
    final style = config[AvatarPart.beard];
    switch (style) {
      case 'stubble':
        _shape(
          c,
          Path()
            ..moveTo(27, 61)
            ..cubicTo(31, 74, 43, 77, 50, 77)
            ..cubicTo(58, 77, 69, 74, 73, 61)
            ..cubicTo(70, 76, 58, 85, 50, 85)
            ..cubicTo(42, 85, 30, 76, 27, 61),
          Color.lerp(skin, _shade(hair, 0.42), compact ? 0.48 : 0.36)!,
        );
      case 'mustache':
        _mustache(c, hair);
      case 'handlebar':
        _mustache(c, hair);
        for (final side in [-1.0, 1.0]) {
          final curl = Path()
            ..moveTo(50 + side * 9, 66)
            ..quadraticBezierTo(50 + side * 21, 68, 50 + side * 21, 61)
            ..quadraticBezierTo(50 + side * 21, 57, 50 + side * 17, 58)
            ..quadraticBezierTo(50 + side * 15, 59, 50 + side * 17, 61);
          c.drawPath(curl, _stroke(hair, compact ? 4.5 : 3.6));
        }
      case 'goatee':
        _shape(
          c,
          Path()
            ..moveTo(41, 74)
            ..quadraticBezierTo(46, 77, 50, 74)
            ..quadraticBezierTo(54, 77, 59, 74)
            ..quadraticBezierTo(58, 83, 50, 89)
            ..quadraticBezierTo(42, 83, 41, 74),
          hair,
        );
      case 'chinstrap':
        final strap = Path()
          ..moveTo(27, 61)
          ..cubicTo(29, 71, 40, 83, 50, 83)
          ..cubicTo(60, 83, 71, 71, 73, 61);
        c.drawPath(strap, _stroke(hair, compact ? 5.5 : 4.5));
      case 'full':
      case 'shortBoxed':
      case 'long':
        final outline = Path()
          ..moveTo(25, 55)
          ..quadraticBezierTo(30, 66, 37, 68)
          ..quadraticBezierTo(42, 62, 50, 63)
          ..quadraticBezierTo(58, 62, 63, 68)
          ..quadraticBezierTo(70, 66, 75, 55);
        switch (style) {
          case 'shortBoxed':
            outline
              ..quadraticBezierTo(73, 75, 63, 83)
              ..quadraticBezierTo(50, 86, 37, 83)
              ..quadraticBezierTo(27, 75, 25, 55);
          case 'long':
            outline
              ..cubicTo(76, 79, 67, 91, 50, 97)
              ..cubicTo(33, 91, 24, 79, 25, 55);
          default:
            outline
              ..cubicTo(77, 75, 64, 89, 50, 91)
              ..cubicTo(36, 89, 23, 75, 25, 55);
        }
        _shape(c, outline, hair);
        _shape(
          c,
          Path()
            ..moveTo(41, 67)
            ..quadraticBezierTo(50, 65, 59, 67)
            ..quadraticBezierTo(62, 71, 58, 75)
            ..quadraticBezierTo(50, 78, 42, 75)
            ..quadraticBezierTo(38, 71, 41, 67),
          skin,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(30, 68),
            const Offset(32, 80),
            const Offset(43, 84),
            _lighten(hair, 0.22),
            2,
          );
        }
    }
  }

  void _mustache(Canvas c, Color hair) {
    _shape(
      c,
      Path()
        ..moveTo(34, 61)
        ..quadraticBezierTo(38, 66, 43, 62)
        ..quadraticBezierTo(47, 59, 50, 62)
        ..quadraticBezierTo(53, 59, 57, 62)
        ..quadraticBezierTo(62, 66, 66, 61)
        ..quadraticBezierTo(64, 71, 56, 67)
        ..quadraticBezierTo(51, 65, 50, 65)
        ..quadraticBezierTo(49, 65, 44, 67)
        ..quadraticBezierTo(36, 71, 34, 61),
      hair,
    );
  }

  void _face(Canvas c, Color skin) {
    final expression = config[AvatarPart.expression];
    final focused = expression == 'focused';
    for (final x in [39.0, 61.0]) {
      final winks = expression == 'wink' && x == 61;
      if (!compact) {
        final tilt = focused ? (x < 50 ? 2.5 : -2.5) : 0.0;
        final brow = winks ? 43.0 : 45.0;
        _curve(
          c,
          Offset(x - 5, brow - tilt),
          Offset(x, brow - (focused ? 1 : 4)),
          Offset(x + 5, brow + tilt),
          _shade(_color(AvatarPart.hairColor), 0.25),
          2.2,
        );
      }
      if (winks || expression == 'laugh') {
        _curve(
          c,
          Offset(x - 5, winks ? 52 : 54),
          Offset(x, winks ? 55 : 46),
          Offset(x + 5, winks ? 51 : 54),
          _ink,
          compact ? 3.5 : 2.5,
        );
      } else if (compact) {
        _oval(c, x, 52, 6.5, focused ? 5 : 8, _ink);
      } else {
        _openEye(c, x, narrowed: focused || expression == 'grin');
      }
    }
    if (!compact) {
      _shape(
        c,
        Path()
          ..moveTo(50, 51)
          ..quadraticBezierTo(50, 55, 53, 57)
          ..quadraticBezierTo(57, 60, 51, 62)
          ..quadraticBezierTo(48, 62, 46, 60)
          ..quadraticBezierTo(50, 59, 50, 55),
        _shade(skin, 0.19),
      );
      _curve(
        c,
        const Offset(47, 60),
        const Offset(50, 63),
        const Offset(54, 60),
        _shade(skin, 0.37),
        1.8,
      );
    }
    final mouth = Path()..moveTo(40, 68);
    switch (expression) {
      case 'grin':
        mouth
          ..quadraticBezierTo(50, 71, 60, 66)
          ..quadraticBezierTo(55, 80, 40, 68);
        _shape(c, mouth, _ink);
        if (!compact) {
          _shape(
            c,
            Path()
              ..moveTo(44, 69)
              ..quadraticBezierTo(51, 70, 56, 68.5)
              ..quadraticBezierTo(54, 73, 50, 73)
              ..quadraticBezierTo(47, 73, 44, 69),
            const Color(0xFFFFEDE0),
          );
        }
      case 'laugh':
        mouth
          ..quadraticBezierTo(50, 71, 60, 68)
          ..quadraticBezierTo(58, 77, 50, 77)
          ..quadraticBezierTo(42, 77, 40, 68);
        _shape(c, mouth, _ink);
        if (!compact) _oval(c, 50, 74, 7, 3, const Color(0xFFDF7D7D));
      case 'focused':
        _curve(
          c,
          const Offset(44, 71),
          const Offset(50, 68),
          const Offset(56, 70),
          _ink,
          compact ? 3.6 : 2.4,
        );
      case 'wink':
        _curve(
          c,
          const Offset(43, 70),
          const Offset(52, 76),
          const Offset(59, 66),
          _ink,
          compact ? 3.5 : 2.5,
        );
      default:
        _curve(
          c,
          const Offset(41, 68),
          const Offset(51, 79),
          const Offset(59, 67),
          _ink,
          compact ? 3.5 : 2.5,
        );
    }
  }

  void _openEye(Canvas c, double x, {required bool narrowed}) {
    final lid = narrowed ? 48.5 : 46.5;
    _shape(
      c,
      Path()
        ..moveTo(x - 5.5, 52)
        ..quadraticBezierTo(x, lid, x + 5.5, 52)
        ..quadraticBezierTo(x, 57, x - 5.5, 52),
      const Color(0xFFFFEEE0),
    );
    _oval(c, x + 0.6, 51.8, 5.5, narrowed ? 5 : 6.5, _ink);
    _oval(c, x - 0.4, 50.6, 1.6, 1.6, const Color(0xFFFFEEE0));
    _curve(
      c,
      Offset(x - 5.5, 52),
      Offset(x, lid),
      Offset(x + 5.5, 52),
      _ink,
      1.6,
    );
  }

  void _glasses(Canvas c) {
    switch (config[AvatarPart.glasses]) {
      case 'clear':
        _clearGlasses(c);
      case 'shades':
        _sportGlasses(c);
      case 'goggles':
        _goggles(c);
    }
  }

  void _clearGlasses(Canvas c) {
    final frameWidth = compact ? 3.2 : 2.3;
    _curve(
      c,
      const Offset(47.5, 50),
      const Offset(50, 47),
      const Offset(52.5, 50),
      _ink,
      frameWidth,
    );
    for (final side in [-1.0, 1.0]) {
      final center = 50 + side * 12;
      _line(
        c,
        Offset(50 + side * 28, 48),
        Offset(center + side * 9, 50),
        _ink,
        frameWidth,
      );
      final frame = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center, 52), width: 19, height: 15),
        const Radius.circular(5.5),
      );
      c.drawRRect(frame, Paint()..color = const Color(0x26D7ECF4));
      c.drawRRect(frame, _stroke(_ink, frameWidth));
    }
  }

  void _sportGlasses(Canvas c) {
    final frameWidth = compact ? 3.2 : 2.3;
    _line(c, const Offset(22, 49), const Offset(29, 46), _ink, frameWidth);
    _line(c, const Offset(71, 46), const Offset(78, 49), _ink, frameWidth);
    final shield = Path()
      ..moveTo(27, 47)
      ..quadraticBezierTo(36, 41, 50, 43)
      ..quadraticBezierTo(64, 41, 73, 47)
      ..lineTo(71, 55)
      ..lineTo(58, 59)
      ..lineTo(52, 53)
      ..quadraticBezierTo(50, 51, 48, 53)
      ..lineTo(42, 59)
      ..lineTo(29, 55)
      ..close();
    final mirror = const LinearGradient(
      colors: [Color(0xFFD79D54), Color(0xFFA84640), Color(0xFF623445)],
    );
    c.drawPath(
      shield,
      Paint()..shader = mirror.createShader(shield.getBounds()),
    );
    c.drawPath(
      shield,
      _stroke(_ink, frameWidth)..strokeJoin = StrokeJoin.round,
    );
  }

  void _goggles(Canvas c) {
    for (final left in [16.0, 74.0]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 45, 10, 11),
          const Radius.circular(3),
        ),
        Paint()..color = _strap,
      );
    }
    final shield = Path()
      ..moveTo(23, 47)
      ..quadraticBezierTo(24, 40, 37, 40)
      ..quadraticBezierTo(50, 38, 63, 40)
      ..quadraticBezierTo(76, 40, 77, 47)
      ..lineTo(75, 55)
      ..quadraticBezierTo(74, 59, 69, 60)
      ..lineTo(61, 63)
      ..quadraticBezierTo(58, 64, 55, 60)
      ..lineTo(52, 55)
      ..quadraticBezierTo(50, 51, 48, 55)
      ..lineTo(45, 60)
      ..quadraticBezierTo(42, 64, 39, 63)
      ..lineTo(31, 60)
      ..quadraticBezierTo(26, 59, 25, 55)
      ..close();
    final lens = switch (config[AvatarPart.goggleTint]) {
      'clear' => Paint()..color = const Color(0x29D7ECF4),
      'smoke' => Paint()..color = const Color(0x80416378),
      _ =>
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF6872E0), Color(0xFF51D8DD), Color(0xFF3156A4)],
            stops: [0.05, 0.45, 1],
          ).createShader(shield.getBounds()),
    };
    c.drawPath(shield, lens);
    c.drawPath(
      shield,
      _stroke(_ink, compact ? 4.6 : 3.7)..strokeJoin = StrokeJoin.round,
    );
  }

  void _headwear(Canvas c, String wear, Color gear) {
    switch (wear) {
      case 'trail':
      case 'fullface':
        if (wear == 'fullface') {
          final chin = Path()
            ..moveTo(14, 37)
            ..quadraticBezierTo(23, 35, 24, 47)
            ..quadraticBezierTo(25, 59, 37, 68)
            ..quadraticBezierTo(50, 74, 63, 68)
            ..quadraticBezierTo(75, 59, 76, 47)
            ..quadraticBezierTo(77, 35, 86, 37)
            ..quadraticBezierTo(87, 60, 81, 73)
            ..cubicTo(74, 84, 60, 88, 50, 89)
            ..cubicTo(40, 88, 26, 84, 19, 73)
            ..quadraticBezierTo(13, 60, 14, 37);
          _shape(c, chin, gear);
          _shape(
            c,
            Path()
              ..moveTo(32, 75)
              ..quadraticBezierTo(50, 79, 68, 75)
              ..quadraticBezierTo(63, 82, 50, 83)
              ..quadraticBezierTo(37, 82, 32, 75),
            _shade(gear, 0.72),
          );
        } else {
          _curve(
            c,
            const Offset(22, 39),
            const Offset(23, 63),
            const Offset(39, 77),
            _strap,
            compact ? 3.8 : 2.6,
          );
        }
        _shape(
          c,
          Path()
            ..moveTo(13, 43)
            ..cubicTo(10, 24, 23, 11, 43, 9)
            ..cubicTo(64, 6, 82, 16, 85, 32)
            ..lineTo(92, 35)
            ..quadraticBezierTo(94, 38, 89, 40)
            ..quadraticBezierTo(77, 42, 66, 37)
            ..quadraticBezierTo(46, 34, 32, 39)
            ..quadraticBezierTo(21, 47, 13, 43),
          gear,
        );
        _curve(
          c,
          const Offset(66, 36),
          const Offset(80, 42),
          const Offset(89, 38),
          _shade(gear, 0.7),
          compact ? 4.2 : 3,
        );
        for (final x in [37.0, 58.0]) {
          _curve(
            c,
            Offset(x, 20),
            Offset(x - 4, 21),
            Offset(x - 8, 27),
            _shade(gear, 0.82),
            compact ? 4.8 : 4,
          );
        }
        if (!compact) {
          _curve(
            c,
            const Offset(20, 30),
            const Offset(24, 20),
            const Offset(33, 17),
            _lighten(gear, 0.52),
            2.6,
          );
        }
      case 'cap':
        _shape(
          c,
          Path()
            ..moveTo(23, 36)
            ..cubicTo(20, 23, 31, 15, 47, 15)
            ..quadraticBezierTo(70, 13, 76, 32)
            ..quadraticBezierTo(89, 33, 92, 39)
            ..quadraticBezierTo(81, 46, 60, 39)
            ..quadraticBezierTo(37, 34, 26, 38)
            ..quadraticBezierTo(23, 38, 23, 36),
          gear,
        );
        _curve(
          c,
          const Offset(59, 37),
          const Offset(81, 44),
          const Offset(89, 39),
          _shade(gear, 0.65),
          compact ? 4.5 : 3,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(48, 17),
            const Offset(57, 21),
            const Offset(59, 33),
            _lighten(gear, 0.46),
            2,
          );
        }
      case 'headband':
        _shape(
          c,
          Path()
            ..moveTo(23, 34)
            ..quadraticBezierTo(50, 29, 77, 34)
            ..quadraticBezierTo(80, 38, 77, 43)
            ..quadraticBezierTo(50, 37, 23, 43)
            ..quadraticBezierTo(20, 38, 23, 34),
          gear,
        );
        if (!compact) {
          _curve(
            c,
            const Offset(26, 39),
            const Offset(50, 34),
            const Offset(74, 39),
            _lighten(gear, 0.44),
            1.8,
          );
        }
    }
  }

  void _shape(Canvas c, Path path, Color color) =>
      c.drawPath(path..close(), Paint()..color = color);

  Color _lighten(Color color, double amount) =>
      Color.lerp(color, const Color(0xFFFFEEE0), amount)!;

  Color _shade(Color color, double amount) => Color.lerp(color, _ink, amount)!;

  void _oval(Canvas c, double x, double y, double w, double h, Color color) =>
      c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: h),
        Paint()..color = color,
      );

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  void _line(Canvas c, Offset a, Offset b, Color color, double width) =>
      c.drawLine(a, b, _stroke(color, width));

  void _curve(
    Canvas c,
    Offset a,
    Offset mid,
    Offset b,
    Color color,
    double width,
  ) => c.drawPath(
    Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy),
    _stroke(color, width),
  );

  @override
  bool shouldRepaint(_Portrait oldDelegate) =>
      oldDelegate.config != config || oldDelegate.compact != compact;
}
