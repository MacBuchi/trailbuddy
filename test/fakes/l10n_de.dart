import 'package:flutter/widgets.dart';
import 'package:trailbuddy/l10n/l10n.dart';

/// Die deutschen Texte für Tests ohne Widget-Baum (#209): Pure Helfer, die
/// Text bauen, nehmen seit der Umstellung ein [AppLocalizations]. Deutsch,
/// weil die Tests deutsche Sätze prüfen — wie das Testgerät von `pumpApp`.
final l10nDe = lookupAppLocalizations(const Locale('de'));
