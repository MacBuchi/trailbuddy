import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/widgets/letter_avatar.dart';
import '../../core/widgets/motion.dart';
import '../../data/providers.dart';
import '../../models/friendship.dart';
import '../coach/coach.dart';
import '../../l10n/l10n.dart';
import '../help/help_link.dart';
import '../help/tab_tours.dart';
import '../help/tour_examples.dart';
import '../profile/profile_providers.dart';
import '../trails/trail_providers.dart';
import 'buddy_alias.dart';
import 'buddy_alias_dialog.dart';
import 'connect_summary.dart';
import 'friend_providers.dart';
import 'message_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchController = TextEditingController();
  List<ProfileSearchResult> _results = [];
  bool _searching = false;
  bool _searched = false;
  ({String name, ConnectSummary summary})? _connected;

  /// Der erste angenommene Buddy — seinen Verlauf öffnet die Vorführung
  /// „Nachrichten" (#34).
  String? _firstBuddyId;
  VoidCallback? _unregisterScene;

  @override
  void initState() {
    super.initState();
    _unregisterScene = ref.read(coachRegistryProvider).registerScene(BuddysCoach.chat, () async {
      final id = _firstBuddyId;
      if (id == null || !mounted) return () {};
      final router = GoRouter.of(context);
      final path = '/friends/chat/$id';
      router.go(path);
      // Zurück nur, wenn der Verlauf noch vorne ist.
      return () {
        if (router.routerDelegate.currentConfiguration.uri.path == path) {
          router.go('/friends');
        }
      };
    });
  }

  @override
  void dispose() {
    _unregisterScene?.call();
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await ref.read(friendRepositoryProvider).search(query);
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e, stackTrace) {
      logError('Buddy-Suche', e, stackTrace);
      if (mounted) _showMessage(friendlyError(context.l10n, e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Einladung teilen; wo das System-Teilen nicht verfügbar ist
  /// (z. B. Desktop-Browser), landet der Text in der Zwischenablage.
  Future<void> _invite() async {
    final username = ref.read(myProfileProvider).valueOrNull?.username;
    final text = AppInfo.inviteText(context.l10n, username);
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      if (result.status == ShareResultStatus.unavailable) {
        throw StateError('share unavailable');
      }
    } catch (_) {
      // Kein Fehlerfall: Desktop-Browser haben kein System-Teilen.
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _showMessage(context.l10n.buddysInviteCopied);
    }
  }

  /// Annehmen — und danach sagen, was sich auf der Karte tut (Konzept 6):
  /// „14 Trails gemeinsam, 8 neu von Jan, 5 neu für Jan". Erst nach dem
  /// Annehmen, nie davor. Kommen die Zahlen nicht (Neuladen gescheitert),
  /// bleibt es beim Annehmen; die Liste zeigt den Buddy ohnehin.
  ///
  /// Seit Design 1k eine Karte oben in der Liste statt einer Leiste: Sie
  /// bleibt, bis man sie schließt oder den Reiter verlässt — eine Leiste
  /// war nach acht Sekunden weg, und mit ihr die Zahlen.
  Future<void> _accept(FriendshipEntry f) async {
    final uid = ref.read(currentUserIdProvider) ?? '';
    final name = f.otherUsername(uid);
    final summary = await ref.read(friendshipsProvider.notifier).accept(f.id);
    if (!mounted || summary == null) return;
    setState(() => _connected = (name: name, summary: summary));
  }

  Future<void> _sendRequest(ProfileSearchResult result) async {
    try {
      await ref.read(friendshipsProvider.notifier).sendRequest(result.id);
      if (!mounted) return;
      _showMessage(context.l10n.buddysRequestSent(result.username));
      setState(
          () => _results = _results.where((r) => r.id != result.id).toList());
    } catch (e, stackTrace) {
      logError('Freundschaftsanfrage', e, stackTrace);
      // Unique-Verletzung = Paar existiert schon — die häufigste Ursache.
      if (!mounted) return;
      _showMessage(context.l10n.buddysRequestFailed);
    }
  }

  Future<void> _confirmRemove(FriendshipEntry f, String shownName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.buddysRemoveTitle(shownName)),
        content: Text(context.l10n.buddysRemoveBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.buddysRemoveConfirm)),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(friendshipsProvider.notifier).remove(f.id);
    }
  }


  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final friendshipsAsync = ref.watch(friendshipsProvider);
    final friendships = friendshipsAsync.valueOrNull ?? [];

    final incoming = friendships.where((f) => f.isIncomingFor(uid)).toList();
    final outgoing = friendships.where((f) => f.isOutgoingFor(uid)).toList();
    final accepted = friendships.where((f) => f.isAccepted).toList();
    _firstBuddyId = accepted.firstOrNull?.otherId(uid);
    final names = ref.watch(buddyNamesViewProvider);
    // „n gemeinsam" aus dem, was ohnehin geladen ist (Konzept 12: nur
    // zählen, was ich sehe). Ohne Trails steht die Zeile ohne Zahl da.
    final shared = switch (ref.watch(trailsProvider).valueOrNull) {
      final trails? => sharedTrailCounts(trails, uid),
      null => null,
    };

    final requestedIds = {
      for (final f in friendships) ...[f.requesterId, f.addresseeId]
    };

    // Das Beispiel (#136) nur während der Tour und nur ohne JEDEN Buddy.
    final example = ref.watch(coachExamplesProvider) && accepted.isEmpty && !friendshipsAsync.isLoading;
    return TabTourStarter(
      script: buddysTourScript,
      child: Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(l.buddysTitle,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        actions: [
          CoachAnchor(
            id: BuddysCoach.invite,
            child: IconButton(
              key: const ValueKey('invite-button'),
              onPressed: _invite,
              icon: const Icon(Icons.share),
              tooltip: l.buddysInvite,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendshipsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            CoachAnchor(
              id: BuddysCoach.search,
              child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: l.buddysSearchLabel,
                      hintText: l.buddysSearchHint,
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.line),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 56,
                  child: _searching
                      ? const Center(
                          child: SizedBox.square(
                              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton.outlined(
                          onPressed: _search,
                          icon: const Icon(Icons.search),
                          tooltip: l.buddysSearchTooltip,
                          style: IconButton.styleFrom(
                            backgroundColor: palette.surface,
                            side: BorderSide(color: palette.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                ),
              ],
            )),
            if (_searched) ...[
              const SizedBox(height: 8),
              if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l.buddysSearchEmpty),
                )
              else
                for (final result in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: LetterAvatar(name: result.username, colorKey: result.id),
                    title: Text(result.username,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: result.displayName != null
                        ? Text(result.displayName!)
                        : null,
                    trailing: requestedIds.contains(result.id)
                        ? Text(l.buddysAlreadyLinked)
                        : FilledButton(
                            onPressed: () => _sendRequest(result),
                            child: Text(l.buddysRequest),
                          ),
                  ),
            ],
            if (_connected case final c?) ...[
              const SizedBox(height: 16),
              _ConnectedCard(
                name: c.name,
                summary: c.summary,
                onClose: () => setState(() => _connected = null),
              ),
            ],
            // Die offenen Anfragen als EIN Anker (#136), an dich und von dir.
            if (incoming.isNotEmpty || outgoing.isNotEmpty)
              CoachAnchor(
                id: BuddysCoach.requests,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            if (incoming.isNotEmpty) ...[
              _SectionLabel(l.buddysIncomingHeader(incoming.length)),
              for (final f in incoming)
                _RequestCard(
                  name: f.otherUsername(uid),
                  colorKey: f.otherId(uid),
                  // Wer anfragt, darf drei Nachrichten dazulegen — und
                  // wer angefragt wird, zurückfragen (Patch 021).
                  message: MessageButton(otherId: f.otherId(uid)),
                  primary: FilledButton(
                    onPressed: () => _accept(f),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l.buddysAccept),
                  ),
                  cancel: _SquareIconButton(
                    onPressed: () => ref.read(friendshipsProvider.notifier).remove(f.id),
                    icon: Icons.close,
                    tooltip: l.buddysDecline,
                  ),
                ),
            ],
            if (outgoing.isNotEmpty) ...[
              _SectionLabel(l.buddysOutgoingHeader(outgoing.length)),
              for (final f in outgoing)
                _RequestCard(
                  name: f.otherUsername(uid),
                  colorKey: f.otherId(uid),
                  subtitle: l.buddysPending,
                  message: MessageButton(otherId: f.otherId(uid)),
                  cancel: _SquareIconButton(
                    onPressed: () => ref.read(friendshipsProvider.notifier).remove(f.id),
                    icon: Icons.close,
                    tooltip: l.buddysWithdraw,
                  ),
                ),
            ],
                  ],
                ),
              ),
            _SectionLabel(accepted.isEmpty ? l.buddysMineHeader : l.buddysMineHeaderCount(accepted.length)),
            if (friendshipsAsync.isLoading && friendships.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CenteredTrailLoader(),
              )
            else if (example)
              const ExampleBuddyTile()
            else if (accepted.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.buddysEmpty),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _invite,
                icon: const Icon(Icons.share),
                label: Text(l.buddysInvite),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 4),
              const HelpLinkButton(),
            ] else
              for (final (i, f) in accepted.indexed)
                _BuddyRow(
                  coach: i == 0,
                  id: f.otherId(uid),
                  username: f.otherUsername(uid),
                  alias: names.aliasOf(f.otherId(uid)),
                  shared: shared?[f.otherId(uid)] ?? (shared == null ? null : 0),
                  onRemove: () => _confirmRemove(f, names.of(f.otherId(uid), f.otherUsername(uid))),
                ),
          ],
        ),
      ),
    ));
  }
}

/// Abschnitt in Versalien mit Anzahl („ANFRAGEN AN DICH · 1").
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppPalette.of(context).muted)),
      );
}

/// „MIT JAN VERBUNDEN" mit drei Zahlen (Design 1k). Für den
/// Bildschirmleser der ganze Satz — dieselbe Aussage, die bis 0.39.0 in
/// der Leiste stand.
class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.name, required this.summary, required this.onClose});

  final String name;
  final ConnectSummary summary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    Widget number(int n, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text('$n',
                  style: AppFonts.numbers(theme.textTheme.headlineSmall).copyWith(color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
            ],
          ),
        );
    return Container(
      key: const ValueKey('connect-summary'),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.brandMark, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ConnectMergeMark(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.buddysConnectedTitle(name).toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: AppFonts.display,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: palette.accentText)),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                tooltip: l.commonClose,
              ),
            ],
          ),
          Semantics(
            label: summary.sentence(l, name),
            excludeSemantics: true,
            child: summary.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(summary.sentence(l, name),
                        style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted)),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      number(summary.shared, l.buddysConnectedShared, palette.text),
                      number(summary.newFromBuddy, l.buddysConnectedNewFrom(name), palette.buddyText),
                      number(summary.newForBuddy, l.buddysConnectedNewFor(name), palette.accentText),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Stand der Verbunden-Animation bei [t] (0…1 über 3 s, Design 1s): wie
/// weit die beiden Spuren noch auseinander liegen (1 → 0 zwischen 15 und
/// 55 %) und wie groß der Punkt ist (0, ab 55 % auf 1,25, dann 1). Pur,
/// damit der Test ohne Pixel prüfen kann.
({double apart, double dot}) connectMergeAt(double t) {
  const merge = Cubic(0.6, 0, 0.2, 1);
  final m = ((t - 0.15) / 0.4).clamp(0.0, 1.0);
  final apart = 1 - merge.transform(m);
  final double dot;
  if (t <= 0.55) {
    dot = 0;
  } else if (t <= 0.75) {
    dot = 1.25 * Curves.easeOut.transform(((t - 0.55) / 0.2).clamp(0.0, 1.0));
  } else {
    // Geklemmt wie im Splash: Gleitkomma landet sonst knapp über 1.
    dot = 1.25 - 0.25 * Curves.easeOut.transform(((t - 0.75) / 0.25).clamp(0.0, 1.0));
  }
  return (apart: apart, dot: dot);
}

/// Zwei Spuren werden eine, dann der Punkt (Design 1s) — einmal, wenn die
/// Karte „Mit … verbunden" erscheint. Bei reduzierter Bewegung steht das
/// Endbild. Reine Zier: Die Aussage trägt der Satz daneben.
class ConnectMergeMark extends StatefulWidget {
  const ConnectMergeMark({super.key, this.size = 36});

  final double size;

  static const duration = Duration(seconds: 3);

  @override
  State<ConnectMergeMark> createState() => _ConnectMergeMarkState();
}

class _ConnectMergeMarkState extends State<ConnectMergeMark> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: ConnectMergeMark.duration);
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        key: const ValueKey('connect-merge'),
        dimension: widget.size,
        child: CustomPaint(
          painter: _MergePainter(_controller, mine: p.brandMark, buddy: p.buddyText, dot: p.text),
        ),
      ),
    );
  }
}

class _MergePainter extends CustomPainter {
  _MergePainter(this.animation, {required this.mine, required this.buddy, required this.dot})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color mine;
  final Color buddy;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final s = connectMergeAt(animation.value);
    Paint line(Color c) => Paint()
      ..color = c
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    // Die Spur des Buddys zuerst: Zusammen ist es EINE Spur, und die
    // trägt die Marke — wie der Punkt am Ende des Logos.
    final dx = 28 * s.apart;
    canvas.drawLine(Offset(50 + dx, 18), Offset(50 + dx, 80), line(buddy));
    canvas.drawLine(Offset(50 - dx, 18), Offset(50 - dx, 84), line(mine));
    if (s.dot > 0) canvas.drawCircle(const Offset(50, 84), 8 * s.dot, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_MergePainter old) => old.mine != mine || old.buddy != buddy || old.dot != dot;
}

/// Eine Anfrage als Karte: Avatar, Name, rechts die Knöpfe.
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.name,
    required this.colorKey,
    required this.cancel,
    this.primary,
    this.subtitle,
    this.message,
  });

  final String name;
  final String colorKey;
  final Widget cancel;
  final Widget? primary;
  final String? subtitle;
  final Widget? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.line),
        ),
        child: Row(
          children: [
            LetterAvatar(name: name, colorKey: colorKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: palette.muted)),
                ],
              ),
            ),
            ?message,
            if (primary != null) ...[primary!, const SizedBox(width: 8)],
            cancel,
          ],
        ),
      ),
    );
  }
}

/// Quadratischer Randknopf, 44 dp (Handschuh).
class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.onPressed, required this.icon, required this.tooltip});

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IconButton.outlined(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: palette.text,
        side: BorderSide(color: palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Ein Buddy: oben Alias oder Name, darunter „14 gemeinsam" und — mit
/// Alias — der Name. Rechts Alias, Nachrichten und Entfernen; einen
/// Chevron wie im Entwurf gibt es nicht, weil es keine Seite je Buddy
/// gibt — der Verlauf ist die Sprechblase.
class _BuddyRow extends StatelessWidget {
  const _BuddyRow({
    required this.id,
    required this.username,
    required this.alias,
    required this.shared,
    required this.onRemove,
    this.coach = false,
  });

  /// Die erste Zeile — die Buddys-Tour (#136) zeigt auf sie und ihren Stift.
  final bool coach;
  final String id;
  final String username;
  final String? alias;
  final int? shared;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          LetterAvatar(name: alias ?? username, colorKey: id, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mit Alias steht er oben und der Name darunter — genau
                // dafür ist er da: wissen, wer „klabuster 2" eigentlich
                // ist.
                Text(alias ?? username,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Wrap(
                  children: [
                    if (alias != null) Text(username, style: muted),
                    if (alias != null && shared != null) Text(' · ', style: muted),
                    if (shared != null) Text(context.l10n.buddysSharedCount(shared!), style: muted),
                  ],
                ),
              ],
            ),
          ),
          coach
              ? CoachAnchor(id: BuddysCoach.alias, child: AliasButton(friendId: id, username: username))
              : AliasButton(friendId: id, username: username),
          coach
              ? CoachAnchor(id: BuddysCoach.message, child: MessageButton(otherId: id))
              : MessageButton(otherId: id),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.person_remove_outlined, color: palette.muted),
            tooltip: context.l10n.buddysRemoveTooltip,
          ),
        ],
      ),
    );
    return coach ? CoachAnchor(id: BuddysCoach.row, child: row) : row;
  }
}

Key messageButtonKey(String otherId) => ValueKey('message-button-$otherId');

/// Der Weg in den Verlauf mit einem Buddy (#34) — mit Zahl, solange
/// Ungelesenes da ist.
class MessageButton extends ConsumerWidget {
  const MessageButton({super.key, required this.otherId});

  final String otherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadMessagesProvider)[otherId] ?? 0;
    final icon = Icon(Icons.chat_bubble_outline, color: AppPalette.of(context).muted);
    return IconButton(
      key: messageButtonKey(otherId),
      tooltip: unread == 0 ? context.l10n.buddysMessages : context.l10n.buddysUnread(unread),
      onPressed: () => context.go('/friends/chat/$otherId'),
      icon: unread == 0 ? icon : Badge(label: Text('$unread'), child: icon),
    );
  }
}
