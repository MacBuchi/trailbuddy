// Fehlertolerante Suche über Namen, lokal und ohne Abhängigkeit (#66) —
// aus PilzBuddy übernommen (`foldSpeciesName`, `nearContainsDistance`,
// dort #395). Die App wird im Funkloch benutzt; ein Suchdienst wäre dort
// tot, und es geht um ein paar hundert Namen.
//
// Zwei Schritte, wie dort: erst Teiltreffer über die gefaltete Form, und
// NUR wenn der leer ausgeht, der Tippfehler-Ausgleich über den
// Editierabstand. Die Oberfläche sagt dann, dass sie rät.

/// Ein Name auf seinen Kern gebracht: klein geschrieben, ohne
/// Umlaut-Schreibweise, ohne Binde-, Leer- und Satzzeichen.
///
/// „ä" und „ae" fallen zusammen, und beide auf „a": Wer unterwegs ohne
/// Umlaut tippt, schreibt mal „Rosskopf Sued" und mal „Rosskopf Sud",
/// und beide meinen „Roßkopf Süd". Die gefaltete Form wird nie angezeigt,
/// sie ist nur der Schlüssel, und die Eingabe geht durch dieselbe Mühle.
String foldSearchText(String text) {
  final folded = text
      .toLowerCase()
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('ß', 'ss')
      .replaceAll('ae', 'a')
      .replaceAll('oe', 'o')
      .replaceAll('ue', 'u')
      .replaceAll('ss', 's');
  final buffer = StringBuffer();
  for (final unit in folded.codeUnits) {
    final isLetter = unit >= 0x61 && unit <= 0x7a;
    final isDigit = unit >= 0x30 && unit <= 0x39;
    if (isLetter || isDigit) buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

/// Wie viele Änderungen der Tippfehler-Ausgleich bei einer gefalteten
/// Eingabe dieser Länge zulässt: unter vier Zeichen keine (−1: gar nicht
/// raten — „ab" läge in der Nähe von allem), bis sieben eine, darüber
/// zwei. Dieselben Stufen wie in PilzBuddy.
int searchTypoTolerance(int length) => length < 4 ? -1 : (length <= 7 ? 1 : 2);

/// Der kleinste Editierabstand zwischen [needle] und **irgendeinem**
/// Teilstück von [hay] — nicht der der ganzen Wörter: „roskopf" gegen
/// „rosskopfsudtrail" ist eine Änderung, nicht zehn. Nullzeile (freier
/// Start) und Minimum über die letzte Zeile (freies Ende), sonst die
/// gewöhnliche Levenshtein-Rechnung.
int nearContainsDistance(String needle, String hay) {
  if (needle.isEmpty) return 0;
  var previous = List<int>.generate(needle.length + 1, (i) => i);
  var best = previous[needle.length];
  final current = List<int>.filled(needle.length + 1, 0);
  for (var j = 1; j <= hay.length; j++) {
    current[0] = 0;
    for (var i = 1; i <= needle.length; i++) {
      final substitution =
          previous[i - 1] + (needle[i - 1] == hay[j - 1] ? 0 : 1);
      final insertion = current[i - 1] + 1;
      final deletion = previous[i] + 1;
      var value = substitution < insertion ? substitution : insertion;
      if (deletion < value) value = deletion;
      current[i] = value;
    }
    if (current[needle.length] < best) best = current[needle.length];
    previous = List<int>.of(current);
  }
  return best;
}
