import 'package:trailbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings(
      {this.prereleaseUpdatesEnabled = false,
      this.poiGroups,
      this.poiHiddenKinds,
      this.seenNoteIds,
      this.stillValidSnoozes,
      this.officialTrailsEnabled = true,
      this.wayLayerEnabled = true,
      this.mapLegendOpen = false,
      this.navKeepScreenOn = true,
      this.pushToken,
      this.appearance,
      this.riderProfile,
      this.loopPlannerPrefs,
      this.navDefault,
      this.riderCalibration,
      // „Schon gesehen" ist die Vorgabe (#126): Jeder Flow-Test pumpt die
      // App auf die Karte, und mit `false` läge über jedem der Hinweis.
      // Tests für Hinweis und Tour geben ihre Einstellungen ausdrücklich mit.
      this.safetyNoteSeen = true,
      this.mapTourSeen = true,
      this.seenCoachTours = const {'split', 'trails', 'buddys'},
      // Ein Stand weit in der Zukunft: sonst läge über jedem Flow-Test
      // das Blatt „Neu in TrailBuddy" (#135).
      this.highlightsSeenVersion = '9999.0.0',
      this.seenHighlightIds = const {}});

  @override
  bool prereleaseUpdatesEnabled;

  @override
  List<String>? poiGroups;

  @override
  List<String>? poiHiddenKinds;

  @override
  List<String>? seenNoteIds;

  @override
  List<String>? stillValidSnoozes;

  @override
  Future<void> setStillValidSnoozes(List<String> entries) async {
    stillValidSnoozes = entries;
  }

  @override
  bool officialTrailsEnabled;

  @override
  bool wayLayerEnabled;

  @override
  Future<void> setWayLayerEnabled(bool value) async {
    wayLayerEnabled = value;
  }

  @override
  bool mapLegendOpen;

  @override
  Future<void> setMapLegendOpen(bool value) async {
    mapLegendOpen = value;
  }

  @override
  bool navKeepScreenOn;

  @override
  Future<void> setNavKeepScreenOn(bool value) async {
    navKeepScreenOn = value;
  }

  @override
  String? pushToken;

  @override
  String? appearance;

  @override
  String? riderProfile;

  @override
  Future<void> setRiderProfile(String value) async {
    riderProfile = value;
  }

  @override
  String? loopPlannerPrefs;

  @override
  Future<void> setLoopPlannerPrefs(String value) async {
    loopPlannerPrefs = value;
  }

  @override
  String? navDefault;

  @override
  Future<void> setNavDefault(String? value) async {
    navDefault = value;
  }

  @override
  String? riderCalibration;

  @override
  Future<void> setRiderCalibration(String? value) async {
    riderCalibration = value;
  }

  @override
  bool safetyNoteSeen;

  @override
  Future<void> setSafetyNoteSeen(bool value) async {
    safetyNoteSeen = value;
  }

  @override
  bool mapTourSeen;

  @override
  Set<String> seenCoachTours;

  @override
  String? highlightsSeenVersion;

  @override
  Future<void> setHighlightsSeenVersion(String value) async {
    highlightsSeenVersion = value;
  }

  @override
  Set<String> seenHighlightIds;

  @override
  Future<void> setSeenHighlightIds(Set<String> value) async {
    seenHighlightIds = value;
  }

  @override
  Future<void> setSeenCoachTours(Set<String> value) async {
    seenCoachTours = value;
  }

  @override
  Future<void> setMapTourSeen(bool value) async {
    mapTourSeen = value;
  }

  @override
  Future<void> setAppearance(String value) async {
    appearance = value;
  }

  @override
  Future<void> setPushToken(String? value) async {
    pushToken = value;
  }

  @override
  Future<void> setOfficialTrailsEnabled(bool value) async {
    officialTrailsEnabled = value;
  }

  @override
  Future<void> setSeenNoteIds(List<String> ids) async {
    seenNoteIds = ids;
  }

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) async {
    prereleaseUpdatesEnabled = value;
  }

  @override
  Future<void> setPoiGroups(List<String> groups) async {
    poiGroups = groups;
  }

  @override
  Future<void> setPoiHiddenKinds(List<String> kinds) async {
    poiHiddenKinds = kinds;
  }
}
