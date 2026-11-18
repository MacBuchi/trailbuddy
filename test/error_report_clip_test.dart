import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/core/errors.dart';
import 'package:trailbuddy/data/error_report_repository.dart';

void main() {
  group('clipStack', () {
    String frame(int i, {bool own = false}) => own
        ? '#$i      _Own.build (package:trailbuddy/features/x.dart:$i:1)'
        : '#$i      Element.rebuild (package:flutter/src/widgets/framework.dart:$i:7)';

    test('a short stack stays as it is', () {
      final stack = [frame(0), frame(1, own: true)].join('\n');
      expect(ErrorReportRepository.clipStack(stack, 4000), stack);
      expect(ErrorReportRepository.clipStack(null, 4000), isNull);
      expect(ErrorReportRepository.clipStack('  ', 4000), isNull);
    });

    test('keeps the head AND the own frames from behind the cut', () {
      // Hundert Framework-Frames, dann der eine eigene — so sah ein tiefer
      // Widget-Baum aus, und der Schnitt von hinten nahm genau ihn weg.
      final lines = [
        for (var i = 0; i < 100; i++) frame(i),
        frame(100, own: true),
      ];
      final clipped = ErrorReportRepository.clipStack(lines.join('\n'), 4000)!;
      expect(clipped.length, lessThanOrEqualTo(4000));
      expect(clipped, startsWith(frame(0)));
      expect(clipped, contains('Zeilen gekürzt, eigene davon:'));
      expect(clipped, contains('package:trailbuddy/features/x.dart:100:1'));
      // Gegenprobe: Der alte Schnitt von hinten hätte ihn verloren.
      expect(
        lines.join('\n').substring(0, 4000),
        isNot(contains('package:trailbuddy/')),
      );
    });

    test('without own frames it says how much is missing', () {
      final lines = [for (var i = 0; i < 100; i++) frame(i)];
      final clipped = ErrorReportRepository.clipStack(lines.join('\n'), 4000)!;
      expect(clipped.length, lessThanOrEqualTo(4000));
      expect(clipped, contains('Zeilen gekürzt'));
      expect(clipped, isNot(contains('eigene davon')));
    });
  });

  group('flutterErrorStack', () {
    test('puts library and context above the stack', () {
      final details = FlutterErrorDetails(
        exception: TypeError(),
        stack: StackTrace.fromString(
          '#0      AnimationController.stop (package:flutter/src/animation/animation_controller.dart:894:13)',
        ),
        library: 'scheduler library',
        context: ErrorDescription('during a scheduler callback'),
      );
      final stack = flutterErrorStack(details).toString();
      expect(
        stack.split('\n').first,
        'Phase: scheduler library · during a scheduler callback',
      );
      expect(stack, contains('#0      AnimationController.stop'));
    });

    test('without library and context the stack is untouched', () {
      final original = StackTrace.fromString(
        '#0      foo (package:x/y.dart:1:1)',
      );
      final details = FlutterErrorDetails(
        exception: Exception('x'),
        stack: original,
        library: null,
      );
      expect(flutterErrorStack(details), same(original));
    });
  });
}
