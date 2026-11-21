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
    child: CustomPaint(size: Size.square(size), painter: _Portrait(config)),
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
const _strap = Color(0xFF493C3A);

class _Portrait extends CustomPainter {
  const _Portrait(this.config);

  final AvatarConfig config;

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
    canvas.drawRect(bounds, Paint()..color = _color(AvatarPart.background));
    _hairBehind(canvas, hair);
    _shape(
      canvas,
      Path()
        ..moveTo(5, 102)
        ..quadraticBezierTo(11, 80, 41, 79)
        ..lineTo(59, 79)
        ..quadraticBezierTo(89, 80, 95, 102),
      _jersey,
    );
    _oval(canvas, 50, 81, 23, 21, skin);
    _oval(canvas, 23, 54, 12, 19, skin);
    _oval(canvas, 77, 54, 12, 19, skin);
    _shape(
      canvas,
      Path()
        ..moveTo(26, 37)
        ..quadraticBezierTo(27, 23, 50, 23)
        ..quadraticBezierTo(73, 23, 74, 37)
        ..lineTo(75, 57)
        ..cubicTo(74, 74, 63, 85, 50, 86)
        ..cubicTo(37, 85, 26, 74, 25, 57),
      skin,
    );
    _hair(canvas, hair);
    _beard(canvas, hair);
    _face(canvas);
    _glasses(canvas);
    _headwear(canvas, wear, gear);
    canvas.restore();
  }

  void _hairBehind(Canvas c, Color hair) {
    switch (config[AvatarPart.hair]) {
      case 'long':
        _oval(c, 50, 52, 68, 75, hair);
      case 'braids':
        for (final x in [23.0, 77.0]) {
          for (final y in [59.0, 69.0, 79.0]) {
            _oval(c, x, y, 10, 14, hair);
          }
          _line(c, Offset(x - 4, 80), Offset(x + 4, 80), _jersey, 2);
        }
    }
  }

  void _hair(Canvas c, Color hair) {
    switch (config[AvatarPart.hair]) {
      case 'buzz':
        _oval(c, 50, 32, 51, 25, hair);
      case 'short':
        _shape(
          c,
          Path()
            ..moveTo(24, 47)
            ..quadraticBezierTo(18, 22, 39, 19)
            ..quadraticBezierTo(64, 12, 77, 29)
            ..lineTo(77, 47)
            ..lineTo(68, 35)
            ..quadraticBezierTo(50, 44, 39, 32)
            ..lineTo(28, 49),
          hair,
        );
      case 'curly':
        for (final (x, y) in [
          (29.0, 34.0),
          (36.0, 26.0),
          (47.0, 23.0),
          (58.0, 24.0),
          (69.0, 29.0),
          (75.0, 37.0),
        ]) {
          _oval(c, x, y, 22, 21, hair);
        }
      case 'long':
      case 'braids':
        _shape(
          c,
          Path()
            ..moveTo(23, 48)
            ..quadraticBezierTo(15, 17, 49, 17)
            ..quadraticBezierTo(80, 15, 79, 45)
            ..quadraticBezierTo(63, 39, 57, 26)
            ..quadraticBezierTo(43, 46, 23, 48),
          hair,
        );
    }
  }

  void _beard(Canvas c, Color hair) {
    switch (config[AvatarPart.beard]) {
      case 'stubble':
        _shape(c, _jaw(), hair.withValues(alpha: 0.28));
      case 'mustache':
        _oval(c, 45, 64, 12, 6, hair);
        _oval(c, 55, 64, 12, 6, hair);
      case 'full':
        _shape(c, _jaw()..quadraticBezierTo(50, 83, 27, 61), hair);
    }
  }

  Path _jaw() => Path()
    ..moveTo(27, 61)
    ..quadraticBezierTo(29, 84, 50, 87)
    ..quadraticBezierTo(71, 84, 73, 61)
    ..quadraticBezierTo(62, 78, 50, 77)
    ..quadraticBezierTo(38, 78, 27, 61);

  void _face(Canvas c) {
    final expression = config[AvatarPart.expression];
    for (final x in [39.0, 61.0]) {
      _line(
        c,
        Offset(x - 4, 45),
        Offset(x + 4, expression == 'focused' ? 47 : 44),
        _ink,
        2,
      );
      if ((expression == 'wink' && x == 61) || expression == 'laugh') {
        _curve(
          c,
          Offset(x - 4, 53),
          Offset(x, 47),
          Offset(x + 4, 53),
          _ink,
          2.5,
        );
      } else {
        _oval(c, x, 52, 5, 7, _ink);
      }
    }
    _curve(
      c,
      const Offset(47, 59),
      const Offset(50, 62),
      const Offset(53, 59),
      const Color(0xFF864A42),
      1.8,
    );
    final mouth = Path()..moveTo(40, 68);
    switch (expression) {
      case 'grin':
        mouth
          ..quadraticBezierTo(50, 71, 60, 66)
          ..quadraticBezierTo(55, 80, 40, 68);
        _shape(c, mouth, _ink);
        _curve(
          c,
          const Offset(43, 69),
          const Offset(50, 72),
          const Offset(57, 68),
          Colors.white,
          2,
        );
      case 'laugh':
        _oval(c, 50, 71, 15, 11, _ink);
        _oval(c, 50, 74, 7, 3, const Color(0xFFDF7D7D));
      case 'focused':
        _line(c, const Offset(45, 71), const Offset(56, 70), _ink, 2.4);
      default:
        _curve(
          c,
          const Offset(41, 68),
          const Offset(51, 79),
          const Offset(59, 67),
          _ink,
          2.5,
        );
    }
  }

  void _glasses(Canvas c) {
    switch (config[AvatarPart.glasses]) {
      case 'clear':
      case 'shades':
        final dark = config[AvatarPart.glasses] == 'shades';
        _line(c, const Offset(26, 50), const Offset(74, 50), _ink, 2);
        for (final x in [39.0, 61.0]) {
          final frame = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, 52), width: 19, height: 14),
            const Radius.circular(5),
          );
          if (dark) c.drawRRect(frame, Paint()..color = _ink);
          c.drawRRect(
            frame,
            Paint()
              ..color = _ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          if (dark) {
            _line(c, Offset(x - 5, 50), Offset(x + 2, 49), Colors.white54, 1.5);
          }
        }
      case 'goggles':
        final frame = RRect.fromRectAndRadius(
          const Rect.fromLTRB(28, 44, 72, 59),
          const Radius.circular(6),
        );
        c.drawRRect(frame, Paint()..color = _ink);
        c.drawRRect(
          frame.deflate(2.5),
          Paint()..color = const Color(0xFF82BCCC),
        );
        _line(
          c,
          const Offset(35, 49),
          const Offset(61, 48),
          Colors.white70,
          1.8,
        );
    }
  }

  void _headwear(Canvas c, String wear, Color gear) {
    switch (wear) {
      case 'trail':
      case 'fullface':
        if (wear == 'fullface') {
          _shape(
            c,
            Path()
              ..moveTo(15, 40)
              ..lineTo(21, 63)
              ..lineTo(38, 76)
              ..lineTo(62, 76)
              ..lineTo(79, 63)
              ..lineTo(85, 40)
              ..lineTo(81, 71)
              ..quadraticBezierTo(75, 85, 50, 87)
              ..quadraticBezierTo(25, 85, 19, 71),
            gear,
          );
          _line(c, const Offset(42, 81), const Offset(58, 81), _ink, 2);
        } else {
          _curve(
            c,
            const Offset(23, 35),
            const Offset(25, 62),
            const Offset(39, 77),
            _strap,
            2.6,
          );
        }
        _shape(
          c,
          Path()
            ..moveTo(13, 44)
            ..cubicTo(10, 20, 26, 9, 48, 9)
            ..cubicTo(70, 9, 82, 15, 85, 33)
            ..lineTo(92, 38)
            ..quadraticBezierTo(77, 41, 64, 37)
            ..lineTo(34, 38)
            ..quadraticBezierTo(23, 47, 13, 44),
          gear,
        );
        for (final x in [32.0, 47.0, 62.0]) {
          _line(c, Offset(x, 21), Offset(x - 6, 28), _ink, 3.3);
        }
        _curve(
          c,
          const Offset(21, 32),
          const Offset(27, 18),
          const Offset(39, 16),
          Colors.white54,
          2,
        );
      case 'cap':
        _shape(
          c,
          Path()
            ..moveTo(23, 36)
            ..quadraticBezierTo(20, 15, 47, 13)
            ..quadraticBezierTo(72, 13, 77, 32)
            ..lineTo(90, 37)
            ..quadraticBezierTo(84, 43, 57, 38)
            ..lineTo(38, 36)
            ..quadraticBezierTo(27, 40, 23, 36),
          gear,
        );
        _curve(
          c,
          const Offset(48, 14),
          const Offset(60, 19),
          const Offset(60, 34),
          Colors.white54,
          1.8,
        );
      case 'headband':
        _shape(
          c,
          Path()
            ..moveTo(23, 34)
            ..quadraticBezierTo(50, 29, 77, 34)
            ..lineTo(77, 42)
            ..quadraticBezierTo(50, 36, 23, 42),
          gear,
        );
    }
  }

  void _shape(Canvas c, Path path, Color color) =>
      c.drawPath(path..close(), Paint()..color = color);

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
  bool shouldRepaint(_Portrait oldDelegate) => oldDelegate.config != config;
}
