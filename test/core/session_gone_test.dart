// Eine verfallene Sitzung ist kein Fehlerbericht (W44, #428): GoTrue
// meldet sich selbst ab, und der Router führt zum Login.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trailbuddy/core/errors.dart';

void main() {
  test('refresh_token_not_found und session_not_found: Sitzung weg, nicht melden', () {
    for (final code in ['refresh_token_not_found', 'session_not_found']) {
      final error = AuthApiException('Invalid Refresh Token', statusCode: '400', code: code);
      expect(looksLikeSessionGone(error), isTrue, reason: code);
      expect(worthReporting(error), isFalse, reason: code);
    }
  });

  test('andere Auth-Fehler bleiben sichtbar', () {
    const other = AuthApiException('Invalid API key', statusCode: '401', code: 'bad_jwt');
    expect(looksLikeSessionGone(other), isFalse);
    expect(worthReporting(other), isTrue);
    expect(looksLikeSessionGone(Exception('refresh_token_not_found')), isFalse);
  });
}
