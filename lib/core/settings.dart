import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'errors.dart';

/// Gerätelokale Einstellungen — alles, was auf *diesem* Gerät gilt und
/// nicht ins Konto gehört.
///
/// Bewusst schmal: Was die Nutzerin überallhin begleiten soll (Profil,
/// Freigaben), steht in Supabase und wird dort von RLS geschützt. Hier
/// liegt nur, was ohne Konto und ohne Netz beantwortbar sein muss.
///
/// Als Schnittstelle, damit Tests sie wie die Repositories mit einer Fake
/// belegen können (`test/fakes/fake_settings.dart`) — ein echter
/// SharedPreferences-Kanal existiert im Widget-Test nicht.
abstract interface class Settings {
  /// Bekommt dieses Gerät auch Vorabversionen angeboten?
  ///
  /// Standardmäßig NEIN, und das ist der ganze Sinn der Trennung: JEDER
  /// Versions-Bump baut ein Release, aber als Prerelease — für die Nutzer
  /// unsichtbar, weil `/releases/latest` grundsätzlich keine Prereleases
  /// liefert. Wer den Schalter umlegt, hebt genau diesen Schutz für sich
  /// auf und bekommt Zwischenstände, die niemand abgenommen hat.
  ///
  /// Gerätelokal wie alle Schalter hier: Es ist eine Einstellung dieses
  /// Telefons, keine des Kontos — auf dem Zweitgerät will man denselben
  /// Menschen nicht zwangsweise im Vorab-Kanal haben.
  bool get prereleaseUpdatesEnabled;

  Future<void> setPrereleaseUpdatesEnabled(bool value);

  /// Die eingeschalteten Orte-Gruppen der Karte (`PoiGroup.name`), oder
  /// null, solange nie etwas umgelegt wurde — dann gilt die Vorgabe.
  /// Leer heißt „alles aus", nicht „Vorgabe".
  List<String>? get poiGroups;

  Future<void> setPoiGroups(List<String> groups);

  /// Einzeln abgewählte Arten innerhalb der Gruppen (`PoiKind.name`) —
  /// der Detailfilter. Leer oder null: alle Arten einer Gruppe sichtbar.
  List<String>? get poiHiddenKinds;

  Future<void> setPoiHiddenKinds(List<String> kinds);

  /// Hinweise (`TrailNote.id`), die auf diesem Gerät schon im Trail-Blatt
  /// zu sehen waren — sie heben den Trail nicht mehr hervor (#7).
  List<String>? get seenNoteIds;

  Future<void> setSeenNoteIds(List<String> ids);

  /// Angaben, zu denen „Noch gültig?" (#119) nach „Weiß nicht" eine Weile
  /// nicht fragt: je Eintrag `<Kennung>|<bis>`. Gerätelokal wie die
  /// gelesenen Hinweise — der Server erfährt nicht, wer was offen ließ.
  List<String>? get stillValidSnoozes;

  Future<void> setStillValidSnoozes(List<String> entries);

  /// Das Fahrerprofil der Routing-Engine (docs/konzept-routing.md 2.1):
  /// `RiderProfile.name`, null heißt Vorgabe Bio-Bike. Gerätelokal wie
  /// alles hier — viele fahren beides, und das Zweitgerät darf anders
  /// stehen.
  String? get riderProfile;

  Future<void> setRiderProfile(String value);

  /// Die Regler des Rundenplaners (#158 Schritt 5, Konzept-Routing 2.3)
  /// von der letzten Planung, kodiert von `LoopPrefs`; null heißt die
  /// Vorgaben. Gerätelokal wie das Profil.
  String? get loopPlannerPrefs;

  Future<void> setLoopPlannerPrefs(String value);

  /// Was das Navi-Symbol an einem Trail tut (#176): `external` (Navi-App),
  /// `direct` oder `fun` (Weg in TrailBuddy); null heißt: fragen.
  /// Gerätelokal wie das Profil.
  String? get navDefault;

  Future<void> setNavDefault(String? value);

  /// Die gelernten Werte des Zeitmodells je Profil (Schritt 6,
  /// Konzept-Routing 2.1), kodiert von `RiderCalibrations`; null heißt
  /// die Vorgaben. Gerätelokal — gelernt wird nur aus eigenen Fahrten,
  /// und die verlassen das Gerät nie.
  String? get riderCalibration;

  Future<void> setRiderCalibration(String? value);

  /// Die zuletzt vom Host gelesenen Manifeste von Karte und Wegen (#155),
  /// als JSON. Ohne Empfang nennt der MapLibre-Stil damit trotzdem die
  /// Online-Archive, und MapLibre liefert, was in seinem Zwischenspeicher
  /// liegt („Gesehenes bleibt liegen"). Null heißt: noch nie geholt.
  String? get seenMapManifest;

  Future<void> setSeenMapManifest(String value);

  String? get seenWaysManifest;

  Future<void> setSeenWaysManifest(String value);

  /// Ist die Ebene „Offizielle Trails" an (#13)? Vorgabe: an
  /// (Entscheidung des Betreibers, Konzept offizielle Trails 2.5).
  bool get officialTrailsEnabled;

  Future<void> setOfficialTrailsEnabled(bool value);

  /// Ist die Ebene „Wege" an (#212: Forstweg-Güte und Pfad-Schwierigkeit
  /// aus OSM)? Vorgabe: an (Betreiber, 2026-10-08).
  bool get wayLayerEnabled;

  Future<void> setWayLayerEnabled(bool value);

  /// Sind die Höhenlinien an (#271)? Vorgabe: aus — sie liest Höhenkacheln
  /// und rechnet je Stillstand der Karte.
  bool get contourLayerEnabled;

  Future<void> setContourLayerEnabled(bool value);

  /// Ist die Legende auf der Karte aufgeklappt (#182)? Vorgabe: zu.
  bool get mapLegendOpen;

  Future<void> setMapLegendOpen(bool value);

  /// Bleibt der Bildschirm in der Folgeansicht der Navigation an (#232,
  /// Konzept-Routing 9.4)? Vorgabe: an (Betreiber, 2026-10-08).
  bool get navKeepScreenOn;

  Future<void> setNavKeepScreenOn(bool value);

  /// Das FCM-Token, mit dem dieses Gerät in `push_devices` steht — oder
  /// null, solange niemand Push eingeschaltet hat (#34).
  ///
  /// Gemerkt wird NUR das Token, nicht „an/aus": Ob dieses Gerät
  /// Meldungen bekommt, steht in `push_devices`; ein zweites Flag hier
  /// liefe beim ersten Abmelden auseinander. Gebraucht wird es zum
  /// Austragen und für die Testnachricht.
  String? get pushToken;

  Future<void> setPushToken(String? value);

  /// „Erscheinungsbild": `system`, `light` oder `dark` (`ThemeMode.name`),
  /// oder null, solange nie etwas gewählt wurde — dann wie das System.
  String? get appearance;

  Future<void> setAppearance(String value);

  /// Hat dieses Gerät den Sicherheitshinweis (#131) schon einmal
  /// bestätigt? Einmal je Installation — ein Hinweis, den man täglich
  /// wegklickt, wird zur Tapete. Nachlesbar bleibt er in der
  /// Kurzanleitung und unter „Über TrailBuddy".
  bool get safetyNoteSeen;

  Future<void> setSafetyNoteSeen(bool value);

  /// Hat dieses Gerät die Karten-Tour (#132) gesehen — durchgesehen oder
  /// übersprungen? Gerätelokal; nach einer Neuinstallation läuft sie
  /// wieder, und das ist angenommen.
  bool get mapTourSeen;

  Future<void> setMapTourSeen(bool value);

  /// Die Touren außerhalb der Karte, die dieses Gerät gesehen hat
  /// (`split`, ab #136 `trails` und `buddys`). Durchgesehen oder
  /// übersprungen — „Nicht jetzt" zählt nicht.
  Set<String> get seenCoachTours;

  Future<void> setSeenCoachTours(Set<String> value);

  /// Die App-Version, deren Neuheiten dieses Gerät zuletzt gezeigt bekam
  /// (#135) — oder null, solange nie etwas gemerkt wurde.
  String? get highlightsSeenVersion;

  Future<void> setHighlightsSeenVersion(String value);

  /// Einträge in „Entdecken", die schon angesehen wurden (der Neu-Punkt).
  Set<String> get seenHighlightIds;

  Future<void> setSeenHighlightIds(Set<String> value);
}

/// Umsetzung auf SharedPreferences (Android: XML im App-Verzeichnis).
class PrefsSettings implements Settings {
  const PrefsSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _prereleaseUpdatesEnabledKey = 'prerelease_updates_enabled';

  @override
  bool get prereleaseUpdatesEnabled =>
      _prefs.getBool(_prereleaseUpdatesEnabledKey) ?? false;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) =>
      _prefs.setBool(_prereleaseUpdatesEnabledKey, value);

  static const _poiGroupsKey = 'poi_groups';

  @override
  List<String>? get poiGroups => _prefs.getStringList(_poiGroupsKey);

  @override
  Future<void> setPoiGroups(List<String> groups) =>
      _prefs.setStringList(_poiGroupsKey, groups);

  static const _poiHiddenKindsKey = 'poi_hidden_kinds';

  @override
  List<String>? get poiHiddenKinds => _prefs.getStringList(_poiHiddenKindsKey);

  @override
  Future<void> setPoiHiddenKinds(List<String> kinds) =>
      _prefs.setStringList(_poiHiddenKindsKey, kinds);

  static const _seenNoteIdsKey = 'seen_note_ids';

  @override
  List<String>? get seenNoteIds => _prefs.getStringList(_seenNoteIdsKey);

  @override
  Future<void> setSeenNoteIds(List<String> ids) =>
      _prefs.setStringList(_seenNoteIdsKey, ids);

  static const _stillValidSnoozesKey = 'still_valid_snoozes';

  @override
  List<String>? get stillValidSnoozes => _prefs.getStringList(_stillValidSnoozesKey);

  @override
  Future<void> setStillValidSnoozes(List<String> entries) =>
      _prefs.setStringList(_stillValidSnoozesKey, entries);

  static const _officialTrailsEnabledKey = 'official_trails_enabled';

  @override
  bool get officialTrailsEnabled =>
      _prefs.getBool(_officialTrailsEnabledKey) ?? true;

  static const _wayLayerEnabledKey = 'way_layer_enabled';

  @override
  bool get wayLayerEnabled => _prefs.getBool(_wayLayerEnabledKey) ?? true;

  @override
  Future<void> setWayLayerEnabled(bool value) => _prefs.setBool(_wayLayerEnabledKey, value);

  static const _contourLayerEnabledKey = 'contour_layer_enabled';

  @override
  bool get contourLayerEnabled => _prefs.getBool(_contourLayerEnabledKey) ?? false;

  @override
  Future<void> setContourLayerEnabled(bool value) => _prefs.setBool(_contourLayerEnabledKey, value);

  static const _mapLegendOpenKey = 'map_legend_open';

  @override
  bool get mapLegendOpen => _prefs.getBool(_mapLegendOpenKey) ?? false;

  @override
  Future<void> setMapLegendOpen(bool value) => _prefs.setBool(_mapLegendOpenKey, value);

  static const _navKeepScreenOnKey = 'nav_keep_screen_on';

  @override
  bool get navKeepScreenOn => _prefs.getBool(_navKeepScreenOnKey) ?? true;

  @override
  Future<void> setNavKeepScreenOn(bool value) => _prefs.setBool(_navKeepScreenOnKey, value);

  static const _pushTokenKey = 'push_token';

  @override
  String? get pushToken => _prefs.getString(_pushTokenKey);

  @override
  Future<void> setPushToken(String? value) => value == null
      ? _prefs.remove(_pushTokenKey)
      : _prefs.setString(_pushTokenKey, value);

  @override
  Future<void> setOfficialTrailsEnabled(bool value) =>
      _prefs.setBool(_officialTrailsEnabledKey, value);

  static const _riderProfileKey = 'rider_profile';

  @override
  String? get riderProfile => _prefs.getString(_riderProfileKey);

  @override
  Future<void> setRiderProfile(String value) => _prefs.setString(_riderProfileKey, value);

  static const _loopPlannerPrefsKey = 'loop_planner_prefs';

  @override
  String? get loopPlannerPrefs => _prefs.getString(_loopPlannerPrefsKey);

  @override
  Future<void> setLoopPlannerPrefs(String value) => _prefs.setString(_loopPlannerPrefsKey, value);

  static const _navDefaultKey = 'nav_default';

  @override
  String? get navDefault => _prefs.getString(_navDefaultKey);

  @override
  Future<void> setNavDefault(String? value) =>
      value == null ? _prefs.remove(_navDefaultKey) : _prefs.setString(_navDefaultKey, value);

  static const _riderCalibrationKey = 'rider_calibration';

  @override
  String? get riderCalibration => _prefs.getString(_riderCalibrationKey);

  @override
  Future<void> setRiderCalibration(String? value) => value == null
      ? _prefs.remove(_riderCalibrationKey)
      : _prefs.setString(_riderCalibrationKey, value);

  static const _seenMapManifestKey = 'seen_map_manifest';

  @override
  String? get seenMapManifest => _prefs.getString(_seenMapManifestKey);

  @override
  Future<void> setSeenMapManifest(String value) => _prefs.setString(_seenMapManifestKey, value);

  static const _seenWaysManifestKey = 'seen_ways_manifest';

  @override
  String? get seenWaysManifest => _prefs.getString(_seenWaysManifestKey);

  @override
  Future<void> setSeenWaysManifest(String value) => _prefs.setString(_seenWaysManifestKey, value);

  static const _appearanceKey = 'appearance';

  @override
  String? get appearance => _prefs.getString(_appearanceKey);

  @override
  Future<void> setAppearance(String value) =>
      _prefs.setString(_appearanceKey, value);

  // Ohne Suffix (#126, Plan Abschnitt 5): Sollen alle den Hinweis noch
  // einmal sehen, bekommt der Schlüssel `_2` — siehe CLAUDE.md.
  static const _safetyNoteSeenKey = 'safety_note_seen';

  @override
  bool get safetyNoteSeen => _prefs.getBool(_safetyNoteSeenKey) ?? false;

  @override
  Future<void> setSafetyNoteSeen(bool value) =>
      _prefs.setBool(_safetyNoteSeenKey, value);

  static const _mapTourSeenKey = 'map_tour_seen';

  @override
  bool get mapTourSeen => _prefs.getBool(_mapTourSeenKey) ?? false;

  @override
  Future<void> setMapTourSeen(bool value) => _prefs.setBool(_mapTourSeenKey, value);

  static const _seenCoachToursKey = 'seen_coach_tours';

  @override
  Set<String> get seenCoachTours => (_prefs.getStringList(_seenCoachToursKey) ?? const []).toSet();

  // Sortiert geschrieben: dieselbe Menge ergibt dieselbe Liste.
  @override
  Future<void> setSeenCoachTours(Set<String> value) =>
      _prefs.setStringList(_seenCoachToursKey, value.toList()..sort());

  static const _highlightsSeenVersionKey = 'highlights_seen_version';

  @override
  String? get highlightsSeenVersion => _prefs.getString(_highlightsSeenVersionKey);

  @override
  Future<void> setHighlightsSeenVersion(String value) =>
      _prefs.setString(_highlightsSeenVersionKey, value);

  static const _seenHighlightIdsKey = 'seen_highlight_ids';

  @override
  Set<String> get seenHighlightIds => (_prefs.getStringList(_seenHighlightIdsKey) ?? const []).toSet();

  @override
  Future<void> setSeenHighlightIds(Set<String> value) =>
      _prefs.setStringList(_seenHighlightIdsKey, value.toList()..sort());
}

/// Wird in `main()` mit den geladenen Einstellungen überschrieben, in Tests
/// vom Harness (`test/fakes/test_app.dart`).
///
/// Absichtlich synchron statt `FutureProvider`: Ein Schalter, der erst
/// nach dem ersten Frame gilt, ist einen Frame lang falsch — bei einer
/// Kartenquelle sichtbar als Griff nach Kacheln, die es ohne Netz nicht
/// gibt.
final settingsProvider = Provider<Settings>((ref) {
  throw StateError('settingsProvider muss überschrieben werden — '
      'siehe main() und test/fakes/test_app.dart');
});

/// Ein gerätelokal gemerkter An/Aus-Schalter.
///
/// **Warum ein Notifier und kein `StateProvider`.** Ein StateProvider
/// lässt sich von überall mit `.notifier).state = x` setzen, und das
/// Merken wäre dann ein zweiter Schritt, den man vergessen kann — die
/// Sorte Fehler, die erst beim übernächsten App-Start auffällt. Hier
/// gibt es nur [set], und das tut beides.
///
/// Der Zustand springt sofort, das Merken läuft nach, ein Fehler dabei
/// wird nur protokolliert — ein Schalter, der sich nicht merken lässt,
/// soll trotzdem umlegen.
class RememberedFlag extends Notifier<bool> {
  RememberedFlag({
    required this.read,
    required this.write,
    required this.label,
  });

  final bool Function(Settings settings) read;
  final Future<void> Function(Settings settings, bool value) write;

  /// Der Kontext für `logError`, etwa „Vorab-Kanal merken".
  final String label;

  @override
  bool build() => read(ref.read(settingsProvider));

  void set(bool value) {
    state = value;
    unawaited(write(ref.read(settingsProvider), value)
        .catchError((Object e, StackTrace s) => logError(label, e, s)));
  }
}
