// TrailBuddy: Kopie von PilzBuddys `lib/features/coach/coach.dart`
// (Stand 0d2a533, #596) für #132 — Plan `docs/konzept-onboarding.md` 3.2.
// „Kopieren, nicht teilen" (CLAUDE.md): Das Review ist ein `diff` gegen
// PilzBuddy, der nur diese Anpassungen zeigt:
//
// - Ring, Finger-Punkt, Kreis und Ärmel in der Marke (`AppColors.brand`)
//   statt Waldgrün — Grün hieße hier S0, Lime heißt „hier, für dich".
// - Blase und Startseite auf `AppPalette.surface` mit Rand `line`, Radius
//   12; Titel in Barlow Condensed (`titleLarge`), Zähler in JetBrains Mono
//   (`AppFonts.numbers`).
// - Die Kontur der Hand fast schwarz (`AppColors.onBrand`) statt
//   Pilzbraun — die Hand gehört zur Marke, nicht zu den Pilz-Buddys.
// - `reduceMotion(context)` aus `motion.dart` statt
//   `MediaQuery.disableAnimationsOf` — dieselbe Regel wie jede andere
//   Animation der App, und ohne `MediaQuery` wirft sie nicht.
// - `_revealOffscreen` prüft zusätzlich das Fenster der Liste, nicht nur
//   den Bildschirm (#134): Im Zerlege-Blatt endet die Liste über festen
//   Knöpfen, eine Zeile knapp darunter blieb sonst verdeckt.
// - `minRoom` 260 statt 240: Der größere Titel braucht die 20 px.
// - EINE Erweiterung: `CoachStep.illustration`, ein Widget unter dem
//   Blasentext. Trail-Linien sind Engine-Polylinien, keine Widgets; der
//   Schritt „Farbe heißt Schwierigkeit" kann nichts aussparen und zeigt
//   stattdessen eine gezeichnete Mini-Legende.
// - Die Texte der Maschine (Knöpfe, Zähler, „nicht zu sehen") aus den
//   ARB-Dateien (#209), und `CoachStep.id`: Die Skripte bauen ihre Texte
//   aus `AppLocalizations`, Vorführungen finden Schritte einer Tour über
//   die `id` statt über den Titel, der je Sprache ein anderer ist.
//
// Der Kommentar darunter ist PilzBuddys, unverändert.
//
// Die Hinweis-Maschine (#596): zeigt am ECHTEN Bildschirm, wie etwas
// geht — mit Aussparung, Ring, Sprechblase und, bei Gesten, einem
// animierten Finger.
//
// **Warum eine Maschine für die ganze App und nicht die alte Kartentour
// weiter.** Die Tour (#350) kannte nur Löcher auf der Karte, vergrößert
// und rund — gebaut für einzelne runde Knöpfe. Seit die Werkzeuge in
// EINER Leiste sitzen (1.133.0), schnitt sie Stücke aus der Leiste und
// ragte in den Nachbarknopf (Screenshots aus der PWA, 2026-09-24). Und
// sie konnte nur zeigen, WO ein Knopf ist, nie was dahinter kommt; der
// Betreiber wollte ausdrücklich, dass etwa der lange Druck das
// KONTEXTMENÜ öffnet und dessen Einträge erklärt, „sonst verweist
// einfach fast alles auf die Karte".
//
// Vier Dinge, die man wissen muss:
//
// - **Die Ebene liegt über allem** (`MaterialApp.builder`, `app.dart`):
//   über dem Navigator, also auch über Dialogen und Blättern. Nur so kann
//   sie im Kontextmenü (`showGeneralDialog`) und im Ebenen-Blatt
//   hervorheben. Sie schluckt jeden Tipp — eine Vorführung löst nie
//   etwas aus.
// - **Anker und Szenen haben Kennungen**, und wer sie besitzt, meldet
//   sie an: `CoachAnchor(id: 'map.layers', …)` um den Knopf, eine Szene
//   `map.contextMenu` beim Karten-Screen. Das Skript sagt WAS geöffnet
//   wird, der Screen weiß WIE. Eine Szene gibt ihren Schließer zurück;
//   die Maschine schließt, sobald ein Schritt eine andere Szene will,
//   und am Ende immer. Übrig bleibt nichts, und das Menü meldet dabei
//   `null` — also keine Aktion.
// - **Gemessen wird über die ganze Transformation**
//   (`getTransformTo`), nicht über `localToGlobal & size`: Die
//   Knopfleiste steckt in einem `FittedBox(scaleDown)`, und ein Blatt
//   fährt animiert herein. Gemessen wird bei jedem Bild.
// - **Die Aussparung hat die Form des Elements**, der Ring sagt, welches
//   gemeint ist. Eine vergrößerte runde Aussparung je Knopf war genau
//   der Fehler der alten Tour.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/widgets/motion.dart';
import '../../l10n/l10n.dart';

/// Wie der Finger vorführt, was zu tun ist.
enum CoachGesture { none, tap, longPress, swipe }

/// Ein Schritt.
class CoachStep {
  const CoachStep({
    this.id,
    required this.title,
    required this.text,
    this.lit = const [],
    this.ring,
    this.scene,
    this.gesture = CoachGesture.none,
    this.requires = const [],
    this.unless = const [],
    this.scrollIn,
    this.art,
    this.chainTitle,
    this.startLabel,
    this.illustration,
  });

  /// TrailBuddy (#209): eine feste Kennung, über die eine Vorführung den
  /// Schritt einer Tour übernimmt — der Titel ist je Sprache ein anderer.
  /// Nur an Schritten, die jemand übernimmt, nötig; eindeutig je Skript.
  final String? id;

  final String title;
  final String text;

  /// Was ausgespart wird (Anker-Kennungen). Leer heißt: nur abdunkeln.
  final List<String> lit;

  /// Worum der Ring liegt. `null` heißt: um alles Ausgesparte; eine
  /// leere Liste heißt: kein Ring (etwa, wenn der Finger zeigt).
  final List<String>? ring;

  /// Welche Szene dieser Schritt braucht (ein Menü, ein Blatt). Schritte
  /// mit derselben Szene teilen sie; ein Wechsel schließt die alte.
  final String? scene;

  /// Ein Finger auf der Mitte von Ring bzw. Aussparung.
  final CoachGesture gesture;

  /// Anker, ohne die der Schritt wegfällt — etwa die erste Zeile einer
  /// leeren Liste oder die Bilder einer Art ohne Bilder. Geprüft wird,
  /// wenn der Schritt dran ist; ohne die Angabe wartete die Maschine rund
  /// zwei Sekunden auf etwas, das nie kommt. Gehört ein Anker zu einer
  /// Szene, die dieser Schritt erst öffnet, steht er hier NICHT — der ist
  /// beim Prüfen noch gar nicht da.
  final List<String> requires;

  /// Das Gegenstück: Der Schritt fällt weg, sobald einer dieser Anker da
  /// ist. So steht neben „Stift am ersten Buddy" ein Ersatzschritt „erst
  /// einen Buddy finden", und genau einer von beiden läuft.
  final List<String> unless;

  /// Ein Anker um eine LANGE Liste, in der das Ziel erst beim Scrollen
  /// gebaut wird (`ListView` baut nur, was fast im Bild ist). Solange das
  /// Ziel fehlt, scrollt die Maschine diese Liste weiter — etwa zum
  /// Ampel-Schalter weit unten im Profil.
  final String? scrollIn;

  /// Macht den Schritt zur STARTSEITE einer Tour: eine Karte mit Bild
  /// und zwei Sätzen, WOFÜR der Bereich gut ist — die Bedienung kommt
  /// danach (Betreiber, 2026-09-25: „zu jeder Tour eine Startseite …
  /// schön liebevoll gestaltet"). Sie verlangt eine Wahl: loslegen oder
  /// „Nicht jetzt"; ein Tipp daneben tut nichts.
  final WidgetBuilder? art;

  /// Die Überschrift, wenn diese Tour an eine andere anschließt
  /// („Weiter mit den Spots?") — dort ist sie eine Frage.
  final String? chainTitle;

  /// Der Knopf zum Loslegen, falls nicht „Zeig's mir".
  final String? startLabel;

  /// TrailBuddy: ein Bild unter dem Blasentext — für Dinge, die man nicht
  /// aussparen kann, weil sie keine Widgets sind (die Trail-Linien der
  /// Karte zeichnet die Engine). Es scrollt mit dem Text.
  final Widget? illustration;

  bool get isIntro => art != null;
}

/// Ein Ablauf aus Schritten.
class CoachScript {
  const CoachScript({
    required this.id,
    required this.steps,
    this.endLink,
    this.examples = false,
  });

  final String id;
  final List<CoachStep> steps;

  /// Zeigen die Reiter BEISPIELE, wo eigene Daten fehlen? Eine Tour über
  /// die Spot-Liste ohne einen Spot erklärte sonst nur das Suchfeld
  /// (Betreiber, 2026-09-25: „er sollte ja dennoch einen Eindruck
  /// bekommen"). Siehe `features/help/tour_examples.dart`.
  ///
  /// Nur für Skripte, die mit einer Startseite beginnen: Die Beispiele
  /// erscheinen, sobald die Tour läuft, also ein Bild NACH dem Start —
  /// die Startseite gibt ihnen dieses Bild, bevor der erste Schritt nach
  /// seinen Ankern fragt.
  final bool examples;

  /// Ein Weg weiter im LETZTEN Schritt, etwa in die Kurzanleitung:
  /// (Beschriftung, Route).
  final (String, String)? endLink;
}

extension CoachScriptSteps on CoachScript {
  /// Die Schritte ohne Startseite — für Vorführungen, die einen Teil
  /// einer Tour übernehmen und selbst keine Startseite brauchen.
  List<CoachStep> get tourSteps => [
        for (final s in steps)
          if (!s.isIntro) s,
      ];
}

/// Öffnet eine Szene und gibt zurück, wie sie wieder zu schließen ist.
///
/// **Szenen lassen sich schachteln**, über den Schrägstrich in der
/// Kennung: `pilze.detail/report` ist der Meldedialog AUF der Artseite
/// `pilze.detail`. Die äußere bleibt offen, solange ein Schritt eine
/// innere will, und geschlossen wird von innen nach außen.
typedef CoachSceneOpener = Future<VoidCallback> Function();

/// Wer was anbietet: Anker (Widgets) und Szenen (Menüs, Blätter).
///
/// Kein Zustand im Riverpod-Sinn — hier ändert sich nichts, worauf ein
/// Widget warten müsste; die Überlagerung misst ohnehin je Bild.
class CoachRegistry {
  final _anchors = <String, GlobalKey>{};
  final _scenes = <String, CoachSceneOpener>{};

  GlobalKey? anchor(String id) => _anchors[id];

  CoachSceneOpener? scene(String id) => _scenes[id];

  /// Meldet eine Szene an; der Rückgabewert meldet sie wieder ab.
  VoidCallback registerScene(String id, CoachSceneOpener open) {
    _scenes[id] = open;
    return () {
      if (_scenes[id] == open) _scenes.remove(id);
    };
  }

  void _addAnchor(String id, GlobalKey key) => _anchors[id] = key;

  void _removeAnchor(String id, GlobalKey key) {
    if (_anchors[id] == key) _anchors.remove(id);
  }
}

final coachRegistryProvider = Provider<CoachRegistry>((ref) => CoachRegistry());

/// Macht [child] für Hinweise auffindbar.
///
/// Der Schlüssel entsteht HIER, nicht beim Aufrufer: Ein globaler
/// `GlobalKey` überlebte einen Neuaufbau und zeigte dann auf ein
/// abgehängtes Element — dieselbe Lehre wie bei der ersten Kartentour.
class CoachAnchor extends ConsumerStatefulWidget {
  const CoachAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<CoachAnchor> createState() => _CoachAnchorState();
}

class _CoachAnchorState extends ConsumerState<CoachAnchor> {
  final _key = GlobalKey();
  late final CoachRegistry _registry = ref.read(coachRegistryProvider);

  @override
  void initState() {
    super.initState();
    _registry._addAnchor(widget.id, _key);
  }

  @override
  void didUpdateWidget(CoachAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _registry._removeAnchor(old.id, _key);
      _registry._addAnchor(widget.id, _key);
    }
  }

  @override
  void dispose() {
    _registry._removeAnchor(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Ein laufender Ablauf.
class CoachRun {
  const CoachRun(this.script, this.index,
      {List<int>? shown, this.chained = false})
      : _shown = shown;
  final CoachScript script;
  final int index;

  /// Schließt diese Tour an eine andere an? Dann fragt ihre Startseite
  /// („Weiter mit …?", „Später"), und der Weg in die Kurzanleitung am
  /// Ende entfällt — die Kette geht ja weiter.
  final bool chained;

  /// Welche Schritte laufen werden — die übrigen fallen weg (`requires`,
  /// `unless`). Danach richten sich Zähler und „Los geht's": Folgt nur
  /// noch ein Ersatzschritt, der wegfällt, ist DIESER der letzte.
  final List<int>? _shown;

  List<int> get _steps =>
      _shown ?? [for (var i = 0; i < script.steps.length; i++) i];

  CoachStep get step => script.steps[index];
  bool get isLast => _steps.last <= index;

  /// „2 von 3", gezählt über die Schritte, die laufen — ohne die
  /// Startseite, die ist keiner.
  int get position => _counted.where((i) => i <= index).length;
  int get count => _counted.length;
  Iterable<int> get _counted => _steps.where((i) => !script.steps[i].isIntro);

  (String, String)? get endLink => chained ? null : script.endLink;
}

class CoachNotifier extends Notifier<CoachRun?> {
  /// Die offenen Szenen, außen zuerst.
  final _open = <_OpenScene>[];

  /// Was der laufende Schritt braucht, als Kette von außen nach innen.
  List<String> _wanted = const [];

  VoidCallback? _onDone;
  VoidCallback? _onDecline;
  bool _chained = false;

  /// Vorgemerkte Starts (`reserve`): Zählt als belegt, damit in der Zeit
  /// zwischen Tipp und Start keine andere Tour dazwischenkommt.
  int _reserved = 0;

  @override
  CoachRun? build() => null;

  /// Läuft etwas, oder steht ein Start unmittelbar bevor?
  bool get busy => state != null || _reserved > 0;

  /// Merkt einen Start vor, der erst nach einem Seitenwechsel kommt —
  /// sonst startete dort in der Zwischenzeit die Tour des Reiters.
  void reserve() => _reserved++;

  /// Startet [script]. [onDone] läuft beim Ende — durchgesehen ODER
  /// übersprungen: Wer abbricht, hat entschieden.
  ///
  /// [onDecline] läuft stattdessen, wenn auf der Startseite „Nicht
  /// jetzt" (bzw. „Später") gewählt wird: Das ist KEIN Gesehen — die Tour
  /// fragt in der nächsten Sitzung wieder (Betreiber: „jedes Mal").
  void start(CoachScript script,
      {VoidCallback? onDone, VoidCallback? onDecline, bool chained = false}) {
    if (_reserved > 0) _reserved--;
    _setScene(null);
    _onDone = onDone;
    _onDecline = onDecline;
    _chained = chained;
    _go(CoachRun(script, 0));
  }

  /// „Nicht jetzt" auf der Startseite.
  void decline() {
    if (state == null) return;
    _setScene(null);
    state = null;
    final declined = _onDecline;
    _onDone = null;
    _onDecline = null;
    declined?.call();
  }

  /// Gibt eine Vormerkung zurück, aus der nichts wurde.
  void release() {
    if (_reserved > 0) _reserved--;
  }

  void next() {
    final run = state;
    if (run == null) return;
    if (run.isLast) {
      finish();
      return;
    }
    _go(CoachRun(run.script, run.index + 1));
  }

  void finish() {
    if (state == null) return;
    _setScene(null);
    state = null;
    final done = _onDone;
    _onDone = null;
    _onDecline = null;
    done?.call();
  }

  bool _present(String id) {
    final box = ref
        .read(coachRegistryProvider)
        .anchor(id)
        ?.currentContext
        ?.findRenderObject();
    return box is RenderBox && box.hasSize && !box.size.isEmpty;
  }

  bool _runs(CoachStep step) =>
      step.requires.every(_present) && !step.unless.any(_present);

  void _go(CoachRun run) {
    // Ein Anker ohne Fläche zählt als fehlend: Ein Abschnitt ohne Inhalt
    // steht oft als `SizedBox.shrink` da, und eine Aussparung der Größe
    // null wäre ein Schritt über nichts.
    final steps = run.script.steps;
    var index = run.index;
    while (index < steps.length && !_runs(steps[index])) {
      index++;
    }
    if (index >= steps.length) {
      finish();
      return;
    }
    // Neu gerechnet bei JEDEM Schritt: Eine Szene kann Anker bringen.
    final shown = [
      for (var i = 0; i < steps.length; i++)
        if (i == index || (i != index && _runs(steps[i]))) i,
    ];
    final next =
        CoachRun(run.script, index, shown: shown, chained: _chained);
    _setScene(next.step.scene);
    state = next;
  }

  static List<String> _chain(String? id) {
    if (id == null) return const [];
    final parts = id.split('/');
    return [for (var i = 1; i <= parts.length; i++) parts.take(i).join('/')];
  }

  void _setScene(String? wanted) {
    final chain = _chain(wanted);
    var keep = 0;
    while (keep < _open.length &&
        keep < chain.length &&
        _open[keep].id == chain[keep]) {
      keep++;
    }
    // Von innen nach außen: erst der Dialog, dann die Seite darunter.
    while (_open.length > keep) {
      _open.removeLast().shut();
    }
    _wanted = chain;
    _openMissing();
  }

  /// Öffnet die nächste fehlende Szene der Kette — eine nach der anderen,
  /// die innere erst, wenn die äußere steht.
  void _openMissing() {
    if (_open.length >= _wanted.length) return;
    if (_open.isNotEmpty && !_open.last.ready) return;
    final id = _wanted[_open.length];
    final opener = ref.read(coachRegistryProvider).scene(id);
    // Noch nicht angemeldet: Ihr Besitzer ist vielleicht noch gar nicht
    // gebaut (ein Reiter, der nie offen war, eine Seite, die gerade
    // hereinfährt). Die Überlagerung fragt je Bild nach
    // ([retryScenes]).
    if (opener == null) return;
    final scene = _OpenScene(id);
    _open.add(scene);
    unawaited(opener().then((close) {
      scene.opened(close);
      if (!scene.closed) _openMissing();
    }));
  }

  /// Je Bild aus der Überlagerung — siehe [_openMissing].
  void retryScenes() {
    if (state != null) _openMissing();
  }
}

class _OpenScene {
  _OpenScene(this.id);
  final String id;
  VoidCallback? _close;
  bool closed = false;

  bool get ready => _close != null;

  void opened(VoidCallback close) {
    if (closed) {
      close(); // der Schritt ist schon vorbei
    } else {
      _close = close;
    }
  }

  void shut() {
    closed = true;
    _close?.call();
    _close = null;
  }
}

final coachProvider =
    NotifierProvider<CoachNotifier, CoachRun?>(CoachNotifier.new);

/// Soll ein Reiter gerade Beispiele zeigen ([CoachScript.examples])?
final coachExamplesProvider = Provider<bool>((ref) =>
    ref.watch(coachProvider.select((run) => run?.script.examples ?? false)));

/// Blendet [child] für den Bildschirmleser aus, solange eine Tour läuft.
///
/// Darunter nimmt nichts einen Tipp an — die Überlagerung schluckt ihn —,
/// und TalkBack soll nicht auf Knöpfe führen, die nichts tun. Gehört um
/// den Inhalt UNTER der Überlagerung (`app.dart`). `BlockSemantics` in
/// der Überlagerung selbst reichte nicht: Es wirkt nicht über die Grenze
/// zum Navigator (im Test gesehen).
class CoachSemanticsGate extends ConsumerWidget {
  const CoachSemanticsGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ExcludeSemantics(
        excluding: ref.watch(coachProvider) != null,
        child: child,
      );
}

/// Die Überlagerung. Gehört ÜBER den Navigator (`app.dart`).
class CoachOverlay extends ConsumerStatefulWidget {
  const CoachOverlay({
    super.key,
    required this.onNavigate,
    this.backButtonDispatcher,
  });

  /// Für den Weg weiter im letzten Schritt ([CoachScript.endLink]) — die
  /// Überlagerung liegt über dem Router und kennt ihn nicht selbst.
  final void Function(String route) onNavigate;

  /// Der Zurück-Verteiler des Routers. **Zurück beendet die Tour, nicht
  /// die App**: Die Überlagerung liegt ÜBER dem Router, und der bekäme
  /// die Taste sonst zuerst — auf der Karte hieße das, PilzBuddy zu
  /// verlassen. Solange eine Tour läuft, meldet sie sich hier mit
  /// Vorrang an, danach wieder ab (ein Abfangen, das stehen bleibt,
  /// sperrte den Nutzer in der App ein).
  final BackButtonDispatcher? backButtonDispatcher;

  @override
  ConsumerState<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends ConsumerState<CoachOverlay>
    with SingleTickerProviderStateMixin {
  /// Treibt Ring, Finger und das Nachmessen: Ein Blatt fährt animiert
  /// herein, und die Aussparung soll ihm folgen.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  final _box = GlobalKey();
  List<Rect> _lit = const [];
  List<Rect> _ring = const [];
  CoachRun? _measured;

  /// Wie viele Bilder das Ziel des Schritts schon fehlt. Nach rund zwei
  /// Sekunden sagt die Blase es ([_targetLost]).
  ///
  /// **Bis 1.208.x ging die Tour dann von selbst weiter.** Auf einem
  /// Gerät, das ein Blatt langsamer öffnet als der Test, sah das aus wie
  /// ein übersprungener Schritt (Feldmeldung 2026-09-25). Ein sichtbarer
  /// Hinweis ist ehrlicher als ein stiller Sprung, und „Weiter" bleibt
  /// ja da.
  int _missingFrames = 0;
  static const _maxMissingFrames = 120;
  bool _targetLost = false;

  /// Wann der laufende Schritt erschien (Zeit des Takts). Tipps davor
  /// zählen nicht: Nach „Weiter" steht die neue Blase woanders, und ein
  /// zweiter Tipp oder ein nachwackelnder Finger landete sonst auf IHREM
  /// „Weiter" — ein Schritt, den man nie gesehen hat.
  Duration _stepShownAt = Duration.zero;
  CoachRun? _stepRun;
  static const _tapGuard = Duration(milliseconds: 400);

  Duration get _now => _clock.lastElapsedDuration ?? Duration.zero;

  /// Führt [action] nur aus, wenn der Schritt lange genug steht.
  void _guarded(VoidCallback action) {
    if (_now - _stepShownAt < _tapGuard) return;
    action();
  }

  ChildBackButtonDispatcher? _back;

  Future<bool> _onBack() {
    // Auf der Startseite heißt Zurück „Nicht jetzt", danach „aufhören".
    final notifier = ref.read(coachProvider.notifier);
    if (ref.read(coachProvider)?.step.isIntro ?? false) {
      notifier.decline();
    } else {
      notifier.finish();
    }
    return SynchronousFuture(true);
  }

  void _listenBack(bool running) {
    if (running && _back == null) {
      final root = widget.backButtonDispatcher;
      if (root == null) return;
      _back = root.createChildBackButtonDispatcher()
        ..addCallback(_onBack)
        ..takePriority();
    } else if (!running && _back != null) {
      _back!.removeCallback(_onBack);
      widget.backButtonDispatcher?.forget(_back!);
      _back = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _clock.addListener(_measure);
  }

  @override
  void dispose() {
    _listenBack(false);
    _clock.dispose();
    super.dispose();
  }

  List<Rect> _rectsOf(List<String> ids) {
    final registry = ref.read(coachRegistryProvider);
    final overlay = _box.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || !overlay.attached) return const [];
    final out = <Rect>[];
    for (final id in ids) {
      final box = registry.anchor(id)?.currentContext?.findRenderObject();
      // Ohne Fläche zählt er als fehlend — eine Aussparung der Größe null
      // wäre ein Schritt über nichts (etwa der Bildstreifen einer Art
      // ohne Bilder).
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.isEmpty) {
        continue;
      }
      out.add(MatrixUtils.transformRect(
          box.getTransformTo(overlay), Offset.zero & box.size));
    }
    return out;
  }

  void _measure() {
    final run = ref.read(coachProvider);
    if (run == null || !mounted) return;
    ref.read(coachProvider.notifier).retryScenes();
    final step = run.step;
    final lit = _rectsOf(step.lit);
    final ring = step.ring == null ? lit : _rectsOf(step.ring!);
    final complete = lit.length == step.lit.length &&
        (step.ring == null || ring.length == step.ring!.length);
    if (!complete && step.scrollIn != null && _missingFrames.isEven) {
      _scrollOn(step.scrollIn!);
    }
    if (!complete) {
      if (++_missingFrames > _maxMissingFrames && !_targetLost) {
        setState(() => _targetLost = true);
      }
    } else {
      _missingFrames = 0;
      if (_targetLost) setState(() => _targetLost = false);
    }
    if (complete && run != _measured) _revealOffscreen(step.lit, lit);
    if (run == _measured && _same(lit, _lit) && _same(ring, _ring)) return;
    setState(() {
      _measured = run;
      _lit = complete ? lit : const [];
      _ring = complete ? ring : const [];
    });
  }

  /// Scrollt die Liste unter [id] ein Stück weiter, damit sie das Ziel
  /// baut. Jedes zweite Bild, damit dazwischen gebaut werden kann; am
  /// Ende der Liste läuft die übliche Frist ab ([_maxMissingFrames]).
  void _scrollOn(String id) {
    final context = ref.read(coachRegistryProvider).anchor(id)?.currentContext;
    if (context == null) return;
    ScrollableState? list;
    void visit(Element element) {
      if (list != null) return;
      if (element is StatefulElement &&
          element.state is ScrollableState &&
          (element.state as ScrollableState).position.axis == Axis.vertical) {
        list = element.state as ScrollableState;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    final position = list?.position;
    if (position == null || !position.hasContentDimensions) return;
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo(math.min(position.maxScrollExtent,
        position.pixels + position.viewportDimension * 0.9));
  }

  /// Holt ein Ziel ins Bild, das in seiner Liste außerhalb liegt — im
  /// Spot-Blatt stehen die Eintrage-Knöpfe unter einer langen
  /// Fundliste. Einmal je Schritt; danach misst jedes Bild nach, und die
  /// Aussparung fährt mit.
  void _revealOffscreen(List<String> ids, List<Rect> rects) {
    final screen = Offset.zero & (_box.currentContext?.size ?? Size.zero);
    final registry = ref.read(coachRegistryProvider);
    for (var i = 0; i < rects.length && i < ids.length; i++) {
      final context = registry.anchor(ids[i])?.currentContext;
      final scrollable = context == null ? null : Scrollable.maybeOf(context);
      // TrailBuddy: sichtbar heißt im Bild UND im Fenster seiner Liste.
      // Eine Liste über festen Knöpfen (das Zerlege-Blatt) endet über dem
      // Bildrand; eine Zeile knapp darunter läge im Bild, aber unter den
      // Knöpfen — und bliebe verdeckt.
      final bounds = screen.intersect(_viewportOf(scrollable) ?? screen);
      if (bounds.contains(rects[i].topLeft) &&
          bounds.contains(rects[i].bottomRight - const Offset(1, 1))) {
        continue;
      }
      if (context == null || scrollable == null) continue;
      // Weit oben, damit darunter Platz für die Blase bleibt.
      unawaited(Scrollable.ensureVisible(context,
          alignment: 0.15, duration: const Duration(milliseconds: 300)));
    }
  }

  /// Das Fenster einer Liste in Koordinaten der Überlagerung (TrailBuddy).
  Rect? _viewportOf(ScrollableState? scrollable) {
    final box = scrollable?.context.findRenderObject();
    final overlay = _box.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || overlay is! RenderBox) return null;
    return MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size);
  }

  static bool _same(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i].topLeft - b[i].topLeft).distance > 0.5 ||
          (a[i].width - b[i].width).abs() > 0.5 ||
          (a[i].height - b[i].height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(coachProvider);
    _listenBack(run != null);
    if (run == null) {
      if (_clock.isAnimating) _clock.stop();
      _measured = null;
      _lit = const [];
      _ring = const [];
      return const SizedBox.shrink();
    }
    if (!_clock.isAnimating) _clock.repeat();
    if (run != _stepRun) {
      _stepRun = run;
      _stepShownAt = _now;
      _missingFrames = 0;
      _targetLost = false;
    }
    // Solange der Schritt nicht vermessen ist, wird nur abgedunkelt —
    // keine Aussparung an einer geratenen Stelle. Das dauert ein Bild,
    // bei einer Szene so lange, bis sie steht.
    final measured = _measured == run;
    final lit = measured ? _lit : const <Rect>[];
    final ring = measured ? _ring : const <Rect>[];
    final still = reduceMotion(context);
    return Positioned.fill(
      child: LayoutBuilder(
        key: _box,
        builder: (context, constraints) => GestureDetector(
          // Schluckt, was es abdunkelt, und jeder Tipp geht weiter: Ein
          // Tipp, der durchfiele, löste genau das aus, was der Schritt
          // gerade erst erklärt. Für den Bildschirmleser gibt es „Weiter"
          // in der Blase, dieser Tipp bleibt ihm verborgen.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          // Auf der Startseite tut ein Tipp daneben nichts: Sie verlangt
          // eine Wahl.
          onTap: run.step.isIntro
              ? null
              : () => _guarded(ref.read(coachProvider.notifier).next),
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: CoachPainter(
                      lit: lit,
                      ring: ring,
                      // „Animationen entfernen": Der Ring steht, statt zu
                      // pulsieren — gesucht wird er ja nicht.
                      pulse: still ? 0 : _clock.value,
                    ),
                  ),
                ),
                if (measured && run.step.gesture != CoachGesture.none)
                  _finger(run.step.gesture, ring.isNotEmpty ? ring : lit,
                      constraints.biggest, still: still),
                if (run.step.isIntro)
                  _intro(context, run, still: still)
                else
                  _bubble(context, run, lit, ring, constraints.biggest),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _finger(CoachGesture gesture, List<Rect> rects, Size size,
      {required bool still}) {
    final target = rects.isEmpty
        ? size.center(Offset.zero)
        : rects.reduce((a, b) => a.expandToInclude(b)).center;
    return Positioned(
      left: target.dx - 60,
      top: target.dy - 60,
      width: 120,
      height: 120,
      child: IgnorePointer(
        child: CustomPaint(
          // Bei „Animationen entfernen" steht die Hand im Moment, der
          // die Geste ausmacht — dasselbe Bild wie in „Entdecken".
          painter: FingerPainter(
              gesture: gesture,
              t: still ? gestureStillFrame(gesture) : _clock.value),
        ),
      ),
    );
  }

  /// Die Startseite einer Tour: mittig, mit Bild, Wozu und der Wahl.
  Widget _intro(BuildContext context, CoachRun run, {required bool still}) {
    final theme = Theme.of(context);
    final step = run.step;
    final notifier = ref.read(coachProvider.notifier);
    final title =
        run.chained ? (step.chainTitle ?? step.title) : step.title;
    return Positioned.fill(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                key: const ValueKey('coach-intro'),
                elevation: 8,
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                color: AppPalette.of(context).surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: AppPalette.of(context).line)),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nur der Inhalt scrollt, die Wahl bleibt immer im
                        // Bild — auf einem kurzen Schirm lag „Tour starten"
                        // sonst unter dem Rand (im Test so gesehen).
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                // Das Bild schrumpft mit dem Schirm, statt
                                // den Text zu verdrängen. „Animationen
                                // entfernen": Es steht still.
                                SizedBox(
                                  height: (MediaQuery.sizeOf(context).height *
                                          0.2)
                                      .clamp(80.0, 150.0),
                                  child: FittedBox(
                                    child: TickerMode(
                                      enabled: !still,
                                      child: ExcludeSemantics(
                                          child: step.art!(context)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(title,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall),
                                const SizedBox(height: 10),
                                Text(step.text,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              key: const ValueKey('coach-intro-later'),
                              onPressed: () => _guarded(notifier.decline),
                              child: Text(run.chained
                                  ? context.l10n.coachLater
                                  : context.l10n.coachNotNow),
                            ),
                            FilledButton(
                              key: const ValueKey('coach-intro-start'),
                              onPressed: () => _guarded(notifier.next),
                              child: Text(run.chained
                                  ? context.l10n.coachNext
                                  : step.startLabel ?? context.l10n.coachShowMe),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, CoachRun run, List<Rect> lit,
      List<Rect> ring, Size size) {
    final all = [...lit, ...ring];
    final union = all.isEmpty ? null : all.reduce((a, b) => a.expandToInclude(b));
    // Auf die andere Seite des Hervorgehobenen: Eine Sprechblase über dem,
    // was sie erklärt, ist eine Sprechblase über nichts. Bei einer Geste
    // bleibt dazu Platz für den Finger.
    // Die Hand ragt gut 90 px schräg unter ihr Ziel.
    final pad = run.step.gesture == CoachGesture.none ? 20.0 : 84.0;
    final spaceAbove = union == null ? size.height : union.top;
    final spaceBelow = union == null ? size.height : size.height - union.bottom;
    final below = spaceBelow >= spaceAbove;
    // Mindestens so hoch, dass Titel, Zähler und Knöpfe passen — der
    // Text scrollt, die Knöpfe nie (bei 360×640 waren 157 und 210 zu
    // wenig: Im Test ist die Schrift breit, die Knöpfe brechen in zwei
    // Zeilen um).
    // TrailBuddy: 260 statt 240 — der Titel steht in `titleLarge` (22 statt
    // 16 px), und im Zerlege-Blatt fehlten auf 360×740 sonst 2 px (#134).
    const minRoom = 260.0;
    final free = (below ? spaceBelow : spaceAbove) - pad - 24;
    // Passt sie weder darüber noch darunter — ein hohes, schmales Ziel
    // wie die Knopfleiste auf einem kleinen Schirm —, steht sie DANEBEN.
    // Bis 1.205.0 ragte sie dort oben aus dem Bild (360×640, im Test erst
    // gesehen, als er prüfte, dass die Blase im Bild liegt).
    final leftRoom = union == null ? 0.0 : union.left - 24;
    final rightRoom = union == null ? 0.0 : size.width - union.right - 24;
    final side = union != null &&
            free < minRoom &&
            math.max(leftRoom, rightRoom) >= 200
        ? (leftRoom >= rightRoom ? AxisDirection.left : AxisDirection.right)
        : null;
    final room = side != null ? size.height : math.max(free, minRoom);
    final pointAt = ring.isNotEmpty
        ? ring.reduce((a, b) => a.expandToInclude(b)).center
        : union?.center;
    final step = run.step;
    final link = run.isLast ? run.endLink : null;
    final placement = _BubblePlacement();
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _BubbleLayout(
          target: union,
          pointAt: pointAt,
          side: side,
          below: below,
          pad: pad,
          insets: MediaQuery.paddingOf(context),
          placement: placement,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room),
          child: CustomPaint(
            // Der Pfeil zeigt auf den Ring — dann ist klar, worüber der
            // Text spricht, auch wenn mehreres ausgespart ist.
            painter: pointAt == null
                ? null
                : _ArrowPainter(
                    placement: placement,
                    towardsX: pointAt.dx - 16,
                    up: below,
                    // Die Flächenfarbe der Blase, sonst hätte der Pfeil
                    // einen anderen Ton (TrailBuddy: `surface`).
                    colour: AppPalette.of(context).surface),
            child: Card(
              key: const ValueKey('coach-bubble'),
              elevation: 6,
              margin: EdgeInsets.zero,
              color: AppPalette.of(context).surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppPalette.of(context).line)),
              child: Semantics(
                // Ein neuer Schritt wird angesagt — der Bildschirmleser
                // liest sonst nur, was man antippt, und die Blase kommt
                // ohne Tipp.
                container: true,
                liveRegion: true,
                child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    // Nur der Text scrollt, Zähler und Knöpfe bleiben
                    // immer sichtbar (so schon in der alten Tour).
                    Flexible(
                      child: SingleChildScrollView(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.text),
                          if (step.illustration != null) ...[
                            const SizedBox(height: 10),
                            step.illustration!,
                          ],
                        ],
                      )),
                    ),
                    if (_targetLost) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.coachTargetLost,
                        key: const ValueKey('coach-target-lost'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(context.l10n.coachPosition(run.position, run.count),
                        style: AppFonts.numbers(Theme.of(context)
                                .textTheme
                                .bodySmall)
                            .copyWith(color: AppPalette.of(context).muted)),
                    const SizedBox(height: 4),
                    // `Wrap`, keine `Row`: Deutsche Beschriftungen sind
                    // lang (in der alten Tour 50–81 px Überlauf gemessen).
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        if (link != null)
                          TextButton(
                            onPressed: () => _guarded(() {
                              ref.read(coachProvider.notifier).finish();
                              widget.onNavigate(link.$2);
                            }),
                            child: Text(link.$1),
                          )
                        else if (!run.isLast)
                          TextButton(
                            onPressed: () => _guarded(
                                ref.read(coachProvider.notifier).finish),
                            child: Text(context.l10n.coachSkip),
                          ),
                        FilledButton(
                          onPressed: () =>
                              _guarded(ref.read(coachProvider.notifier).next),
                          child: Text(run.isLast
                              ? context.l10n.coachDone
                              : context.l10n.coachNext),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abdunkelung mit Aussparungen und pulsierendem Ring.
///
/// Öffentlich, damit ein Test beides gegen die ECHTEN Maße der Widgets
/// halten kann (`tester.getRect`).
class CoachPainter extends CustomPainter {
  const CoachPainter({required this.lit, required this.ring, this.pulse = 0});

  final List<Rect> lit;
  final List<Rect> ring;
  final double pulse;

  static const radius = Radius.circular(12);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xA6000000));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final r in lit) {
      // Knapp um das Element, nicht vergrößert: Mehr Rand griffe in den
      // Nachbarknopf — der Fehler der alten Tour.
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(2), radius), clear);
    }
    canvas.restore();
    if (ring.isEmpty) return;
    final r = ring.reduce((a, b) => a.expandToInclude(b));
    final grow = 3 + 4 * math.sin(pulse * math.pi);
    final rrect = RRect.fromRectAndRadius(r.inflate(grow), radius);
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.brand);
  }

  @override
  bool shouldRepaint(CoachPainter old) =>
      old.pulse != pulse || old.lit != lit || old.ring != ring;
}

/// Wo der Finger in einem Durchlauf gerade ist. Rein und öffentlich, damit
/// ein Test den Ablauf prüfen kann, ohne Pixel zu lesen: Gedrückt wird
/// AUF dem Ziel, und nur dort.
@immutable
class FingerMotion {
  const FingerMotion({
    required this.tipShift,
    required this.lift,
    required this.pressed,
    required this.progress,
    required this.opacity,
  });

  /// Wie weit die Kuppe vom Ziel weg ist — nur beim Wischen nicht null.
  final Offset tipShift;

  /// 0 = auf dem Schirm, 1 = abgehoben.
  final double lift;

  final bool pressed;

  /// 0…1: wie weit die Geste ist (Kreis beim langen Druck, Welle beim
  /// Tipp, Strecke beim Wischen).
  final double progress;

  final double opacity;

  /// Halbe Wischstrecke.
  static const swipeReach = 40.0;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _in(double v) => Curves.easeOutCubic.transform(v);

  /// Drei Phasen je Geste: herankommen, drücken, abheben. Zwischen den
  /// Durchläufen ist die Hand weg — sonst sähe der Neustart aus wie ein
  /// Sprung.
  factory FingerMotion.of(CoachGesture gesture, double t) {
    final (down, up) = switch (gesture) {
      CoachGesture.tap => (0.3, 0.45),
      CoachGesture.longPress => (0.15, 0.85),
      CoachGesture.swipe => (0.2, 0.75),
      CoachGesture.none => (1.0, 1.0),
    };
    final lift = t < down
        ? 1 - _in(_seg(t, 0, down))
        : t < up
            ? 0.0
            : _in(_seg(t, up, math.min(1, up + 0.2)));
    final opacity = _seg(t, 0, 0.1) * (1 - _seg(t, 0.88, 1));
    return switch (gesture) {
      CoachGesture.tap => FingerMotion(
          tipShift: Offset.zero,
          lift: lift,
          pressed: t >= down && t < up,
          // Die Welle läuft über das Loslassen hinaus aus.
          progress: _seg(t, down, 0.75),
          opacity: opacity,
        ),
      CoachGesture.swipe => FingerMotion(
          // Von rechts nach links, wie man durch Bilder blättert.
          tipShift: Offset(
              swipeReach -
                  2 * swipeReach * Curves.easeInOut.transform(_seg(t, 0.25, up)),
              0),
          lift: lift,
          pressed: t >= down && t < up,
          progress: _seg(t, 0.25, up),
          opacity: opacity,
        ),
      _ => FingerMotion(
          tipShift: Offset.zero,
          lift: lift,
          pressed: t >= down && t < up,
          progress: _seg(t, down, up),
          opacity: opacity,
        ),
    };
  }
}

/// Die Geste als kleines, stehendes Bild — auf den Karten in
/// „Entdecken" (#596). Derselbe Maler wie in der Vorführung, angehalten
/// im Moment, der die Geste ausmacht: beim Tipp die Welle, beim langen
/// Druck der halb volle Kreis, beim Wischen die halbe Strecke. Stehend,
/// weil eine Liste voller laufender Hände unruhig wäre.
class GesturePreview extends StatelessWidget {
  const GesturePreview({super.key, required this.gesture, this.size = 44});

  final CoachGesture gesture;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GesturePreviewPainter(gesture)),
      );
}

/// Der Moment, der eine Geste ausmacht — für das stehende Bild in
/// „Entdecken" und für die Vorführung, wenn im System „Animationen
/// entfernen" an ist: beim Tipp die Welle, beim langen Druck der halb
/// volle Kreis, beim Wischen die halbe Strecke.
double gestureStillFrame(CoachGesture gesture) => switch (gesture) {
      CoachGesture.longPress => 0.6,
      CoachGesture.swipe => 0.55,
      _ => 0.4,
    };

class _GesturePreviewPainter extends CustomPainter {
  const _GesturePreviewPainter(this.gesture);

  final CoachGesture gesture;

  @override
  void paint(Canvas canvas, Size size) {
    final t = gestureStillFrame(gesture);
    // Die Hand ragt von der Kuppe gut 0,8 ihrer Länge nach rechts unten;
    // die Kuppe sitzt deshalb oben links im Kasten.
    canvas.save();
    canvas.translate(size.width * 0.32, size.height * 0.26);
    canvas.scale(size.width / 150);
    FingerPainter(gesture: gesture, t: t).paint(canvas, Size.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GesturePreviewPainter old) => old.gesture != gesture;
}

/// Die Hand, die vorführt (Betreiber, 2026-09-24: „der Finger könnte
/// etwas besser sein" — die erste Fassung waren zwei abgerundete
/// Rechtecke).
///
/// Gezeichnet, nicht als Bild: Sie folgt so dem Ziel pixelgenau und
/// braucht kein Asset. Im Stil der Pilz-Buddys — warmes Weiß, weiche
/// braune Kontur, ein grüner Ärmel —, damit sie zur App gehört und nicht
/// nach Betriebssystem aussieht. Ausgestreckter Zeigefinger mit Nagel,
/// die übrigen Finger eingerollt, der Daumen angelegt; schräg von unten
/// rechts, so wie eine rechte Hand auf den Schirm kommt.
class FingerPainter extends CustomPainter {
  const FingerPainter({required this.gesture, required this.t});

  final CoachGesture gesture;

  /// 0…1, ein Durchlauf.
  final double t;

  static const _skin = Color(0xFFFFF6EC);
  static const _nail = Color(0xFFF6DCCB);
  static const _edge = AppColors.onBrand;

  @override
  void paint(Canvas canvas, Size size) {
    final motion = FingerMotion.of(gesture, t);
    if (motion.opacity <= 0) return;
    final target = size.center(Offset.zero);
    final tip = target + motion.tipShift;
    _paintTrace(canvas, target, tip, motion);

    canvas.saveLayer(null,
        Paint()..color = Colors.white.withValues(alpha: motion.opacity));
    // Abgehoben schwebt die Hand zum Betrachter hin: etwas größer, etwas
    // weiter weg vom Ziel, mit längerem Schatten. Gedrückt wird sie eine
    // Spur kleiner — daran sieht man die Berührung.
    final scale = motion.pressed ? 0.94 : 1 + 0.1 * motion.lift;
    canvas.translate(tip.dx + 12 * motion.lift, tip.dy + 18 * motion.lift);
    canvas.rotate(-0.45);
    canvas.scale(scale);
    _paintHand(canvas, elevation: motion.pressed ? 2 : 3 + 5 * motion.lift);
    canvas.restore();
  }

  /// Was die Geste auf dem Schirm hinterlässt — UNTER der Hand.
  void _paintTrace(
      Canvas canvas, Offset target, Offset tip, FingerMotion motion) {
    final p = motion.progress;
    final dot = Paint()..color = AppColors.brand;
    switch (gesture) {
      case CoachGesture.longPress when motion.pressed:
        // Der Kreis füllt sich — so lange dauert „lange".
        canvas.drawCircle(
            tip, 26, Paint()..color = Colors.white.withValues(alpha: 0.35));
        canvas.drawArc(
            Rect.fromCircle(center: tip, radius: 26),
            -math.pi / 2,
            2 * math.pi * p,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round
              ..color = AppColors.brand);
        canvas.drawCircle(tip, 7, dot);
      case CoachGesture.tap when p > 0 && p < 1:
        canvas.drawCircle(
            tip,
            10 + 26 * p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.white.withValues(alpha: 0.7 * (1 - p)));
        if (motion.pressed) canvas.drawCircle(tip, 7, dot);
      case CoachGesture.swipe when motion.pressed:
        final start = target + const Offset(FingerMotion.swipeReach, 0);
        canvas.drawLine(
            start,
            tip,
            Paint()
              ..strokeWidth = 12
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: 0.4));
        canvas.drawCircle(tip, 7, dot);
      default:
        break;
    }
  }

  /// Die Hand in eigenen Maßen: Kuppe bei (0, 0), der Zeigefinger läuft
  /// nach unten.
  ///
  /// **Von hinten nach vorn gemalt, jede Fläche mit eigener Kontur** —
  /// so verdeckt jedes Teil die Linien dahinter, und es gibt keine Linie,
  /// die man nicht sehen dürfte. Die Fassung davor malte EINEN Umriss und
  /// ritzte Trennlinien hinein; die liefen in die Handfläche, und der
  /// Daumen lag als Wurst quer darüber (Betreiber mit einem Zeige-Icon
  /// als Vorlage, 2026-09-25). Die Reihenfolge: eingerollte Finger vom
  /// kleinen her, dann der Zeigefinger, der Daumen, und zuletzt die
  /// Handfläche OHNE Kontur — sie deckt die unteren Enden der Finger zu,
  /// die in ihr verschwinden. Den Außenrand zieht danach der Umriss aller
  /// Teile.
  void _paintHand(Canvas canvas, {required double elevation}) {
    RRect box(double l, double t, double r, double b, double radius) =>
        RRect.fromLTRBR(l, t, r, b, Radius.circular(radius));

    final finger = box(-9, 0, 9, 60, 9);
    // Treppab nach außen, jeder etwas kleiner — so liegen die Knöchel
    // einer echten Faust. Hinten zuerst: der kleine Finger.
    final curls = [
      box(30, 51, 43, 76, 6.5),
      box(19, 45, 33, 74, 7),
      box(7, 39, 22, 72, 7.5),
    ];
    // Der Daumen steht links schräg nach oben ab, mit einer Kerbe zum
    // Zeigefinger — nicht quer über der Hand.
    final thumb = (Path()..addRRect(box(-7, -34, 7, 6, 7))).transform(
        (Matrix4.translationValues(-6, 80, 0)..rotateZ(-0.36)).storage);
    final palm = Path()..addRRect(box(-11, 55, 43, 94, 14));
    final cuff = box(-10, 84, 42, 102, 6);

    var outline = Path()..addRRect(finger);
    for (final part in [
      palm,
      thumb,
      for (final c in curls) Path()..addRRect(c),
    ]) {
      outline = Path.combine(PathOperation.union, outline, part);
    }

    final skin = Paint()..color = _skin;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = _edge.withValues(alpha: 0.85);
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = _edge.withValues(alpha: 0.45);

    canvas.drawShadow(
        Path.combine(PathOperation.union, outline, Path()..addRRect(cuff)),
        Colors.black,
        elevation,
        false);
    // Der Ärmel ganz hinten — die Hand liegt darauf, sichtbar bleibt der
    // Bund.
    canvas.drawRRect(cuff, Paint()..color = AppColors.brand);
    canvas.drawRRect(cuff, edge);
    for (final c in curls) {
      canvas.drawRRect(c, skin);
      canvas.drawRRect(c, edge);
    }
    canvas.drawRRect(finger, skin);
    canvas.drawRRect(finger, edge);
    canvas.drawPath(thumb, skin);
    canvas.drawPath(thumb, edge);
    canvas.drawPath(palm, skin);
    canvas.drawPath(outline, edge);

    // Nagel und Gelenkfalten: Erst sie machen aus der Form einen Finger.
    final nail = box(-5, 3, 5, 15, 4.5);
    canvas.drawRRect(nail, Paint()..color = _nail);
    canvas.drawRRect(nail, fine);
    canvas.drawLine(const Offset(-4, 23), const Offset(4, 23), fine);
    canvas.drawLine(const Offset(-4, 36), const Offset(4, 36), fine);
  }

  @override
  bool shouldRepaint(FingerPainter old) => old.t != t || old.gesture != gesture;
}

/// Wo die Blase gelandet ist — das Layout schreibt, der Pfeil liest es im
/// selben Bild.
class _BubblePlacement {
  bool shifted = false;
}

/// Setzt die Blase neben ihr Ziel und schiebt sie ins Bild, wenn sie
/// dort hinausragte.
///
/// **Erst messen, dann schieben.** Eine Regel VOR dem Messen („reicht
/// der Platz nicht, an den Rand") schob die Blase auch dann auf das Ziel,
/// wenn sie in Wirklichkeit gepasst hätte — sie ist meist kürzer als ihre
/// Obergrenze. Ohne Schieben ragte sie auf der Artseite unten aus dem
/// Bild, und „Weiter" war nicht zu erreichen (#596, beides im Test).
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout({
    required this.target,
    required this.pointAt,
    required this.side,
    required this.below,
    required this.pad,
    required this.insets,
    required this.placement,
  });

  final Rect? target;
  final Offset? pointAt;

  /// Neben das Ziel statt darüber oder darunter; `null` heißt senkrecht.
  final AxisDirection? side;
  final bool below;
  final double pad;
  final EdgeInsets insets;
  final _BubblePlacement placement;

  static const _margin = 16.0;

  static const _gap = 8.0;

  double _width(Size size) => switch ((side, target)) {
        (AxisDirection.left, final t?) => t.left - _margin - _gap,
        (AxisDirection.right, final t?) => size.width - t.right - _margin - _gap,
        _ => size.width - 2 * _margin,
      };

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = _width(constraints.biggest);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight:
          math.max(0, constraints.maxHeight - insets.vertical - 2 * _margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final t = target;
    final lowest = insets.top + _margin;
    final highest =
        math.max(lowest, size.height - insets.bottom - _margin - child.height);
    if (side != null && t != null) {
      // Auf Höhe dessen, was gemeint ist; ohne Pfeil, der zeigt nur
      // senkrecht.
      placement.shifted = true;
      final centre = pointAt?.dy ?? t.center.dy;
      return Offset(
        side == AxisDirection.left ? _margin : t.right + _gap,
        (centre - child.height / 2).clamp(lowest, highest),
      );
    }
    final wanted = t == null
        ? size.height / 3
        : below
            ? t.bottom + pad
            : t.top - pad - child.height;
    final y = wanted.clamp(lowest, highest);
    placement.shifted = (y - wanted).abs() > 0.5;
    return Offset(_margin, y);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.target != target ||
      old.pointAt != pointAt ||
      old.side != side ||
      old.below != below ||
      old.pad != pad ||
      old.insets != insets;
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.placement,
    required this.towardsX,
    required this.up,
    required this.colour,
  });

  /// Geschoben zeigt der Pfeil nicht mehr auf sein Ziel — dann keiner.
  final _BubblePlacement placement;

  /// Wohin, in Koordinaten dieses Kastens.
  final double towardsX;

  /// Pfeil oben (Blase unter dem Ziel) oder unten.
  final bool up;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (placement.shifted) return;
    final x = towardsX.clamp(24.0, size.width - 24.0);
    final path = Path();
    if (up) {
      path
        ..moveTo(x - 10, 1)
        ..lineTo(x, -11)
        ..lineTo(x + 10, 1);
    } else {
      path
        ..moveTo(x - 10, size.height - 1)
        ..lineTo(x, size.height + 11)
        ..lineTo(x + 10, size.height - 1);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.placement != placement ||
      old.towardsX != towardsX ||
      old.up != up ||
      old.colour != colour;
}
