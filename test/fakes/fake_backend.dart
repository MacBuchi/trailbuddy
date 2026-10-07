// In-Memory-Backend für Szenario-Tests: bildet Supabase-Tabellen und die
// RLS-Freigaberegeln aus supabase/schema.sql nach, damit komplette
// App-Abläufe ohne Netz und ohne Emulator in `flutter test` laufen.
//
// Wichtig: Die echten Freigaberegeln erzwingt der Server (RLS). Die Fakes
// spiegeln sie nur, damit die UI-Reaktion darauf testbar ist — sie ersetzen
// keinen RLS-Test (dafür gibt es den Schema Check gegen die Datenbank).
//
// Die Trail-Tabellen liegen in `fake_trails.dart`; dieser Fake trägt nur
// Konto, Profil, Buddys, Aliase und Feedback.
import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trailbuddy/data/app_config_repository.dart';
import 'package:trailbuddy/data/auth_repository.dart';
import 'package:trailbuddy/data/feedback_repository.dart';
import 'package:trailbuddy/data/friend_repository.dart';
import 'package:trailbuddy/data/profile_repository.dart';
import 'package:trailbuddy/data/push_repository.dart';
import 'package:trailbuddy/models/friendship.dart';
import 'package:trailbuddy/models/profile.dart';

class FakeUser {
  FakeUser({
    required this.id,
    required this.email,
    required this.password,
    required this.username,
    this.avatar = 0,
    this.emailConfirmed = true,
  });

  final String id;
  // Nicht final: der Passwort-Reset bzw. der E-Mail-Wechsel ändern sie
  // wirklich, damit Tests den Effekt prüfen können und nicht nur den
  // Aufruf.
  String email;
  String password;
  // Nicht final: „Benutzername ändern" — gleiche Begründung.
  String username;
  int avatar;

  /// Bestandsnutzer sind alle bestätigt (Autoconfirm), deshalb Vorgabe true.
  bool emailConfirmed;
}

class FakeFriendshipRow {
  FakeFriendshipRow({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    this.status = 'pending',
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  String status; // 'pending' | 'accepted'
}

class FakeBackend {
  final users = <FakeUser>[];
  final friendships = <FakeFriendshipRow>[];

  /// Aliase: (Besitzer, Buddy) → Alias. Die Policies (nur der Besitzer,
  /// nur für bestätigte Buddys) und das Löschen beim Entfernen stehen im
  /// Freund-Fake.
  final aliases = <({String owner, String friend}), String>{};

  final feedback = <Map<String, dynamic>>[];

  /// `push_devices`: Token → Konto (Patch 008). Ein Token gehört zu genau
  /// einem Konto, wie die Tabelle.
  final pushDevices = <String, String>{};

  /// Adressen, für die ein Reset-Code angefordert wurde — auch solche ohne
  /// Konto, denn die App darf beide Fälle nicht unterscheiden.
  final passwordResets = <String>[];

  /// Der Code, den der Fake in der „Mail" verschickt. Fest statt zufällig,
  /// damit Tests ihn kennen; echt sind es sechs Ziffern von GoTrue.
  static const resetCode = '123456';

  /// Bewusst ein ANDERER Code als [resetCode]: Echt sind Bestätigung
  /// (`OtpType.signup`) und Reset (`OtpType.recovery`) zwei Paar Schuhe.
  /// Mit einem gemeinsamen Code käme ein Screen, der versehentlich die
  /// falsche Repository-Methode ruft, im Test trotzdem durch.
  static const signupCode = '654321';

  /// Spiegelt „Confirm email" im Supabase-Dashboard. Tests, die den
  /// Bestätigungs-Weg prüfen, schalten es an.
  bool requireEmailConfirmation = false;

  /// Adressen, an die eine Bestätigungsmail rausging (auch erneut).
  final confirmationMails = <String>[];

  /// Wie oft dieselbe Adresse eine Bestätigungsmail bekommen darf, bevor
  /// GoTrues Rate Limit greift. Vorgabe hoch genug, dass bestehende Tests
  /// nichts davon merken; der Rate-Limit-Test setzt sie herunter.
  int confirmationMailLimit = 100;

  /// Dasselbe für den Passwort-Reset. GoTrues Mail-Limit gilt projektweit
  /// für ALLE Mail-Sorten, nicht je Vorlage.
  int passwordResetMailLimit = 100;

  /// Antwortet das Gateway gar nicht? Dasselbe wie fehlender Empfang, nur
  /// ging die Geduld dem Gateway aus und nicht unserem Client (504).
  bool passwordResetTimesOut = false;

  /// Ein echter Fehler aus dem Reset — der MUSS gemeldet werden, sonst
  /// sähe niemand, wenn der Weg wirklich kaputt ist.
  bool passwordResetFails = false;

  /// Steht für eine Passwort-Prüfung des Servers: bekannte Passwörter
  /// lehnt er mit `weak_password` ab.
  final weakPasswords = <String>{'passwort123'};

  /// Kein Empfang: Abfragen scheitern wie im Funkloch.
  bool offline = false;

  /// Für Fakes außerhalb dieser Datei: dasselbe Funkloch.
  void failIfOffline() {
    if (offline) throw const SocketException('kein Netz (Fake)');
  }

  String? currentUserId;
  final _authEvents = StreamController<AuthState>.broadcast();
  var _nextId = 0;

  Stream<AuthState> get authEvents => _authEvents.stream;

  String _newId(String prefix) => '$prefix-${++_nextId}';

  void dispose() => _authEvents.close();

  FakeUser addUser({
    required String username,
    String? email,
    String password = 'geheim123',
    int avatar = 0,
    bool emailConfirmed = true,
  }) {
    final user = FakeUser(
      id: _newId('user'),
      email: email ?? '$username@example.org',
      password: password,
      username: username,
      avatar: avatar,
      emailConfirmed: emailConfirmed,
    );
    users.add(user);
    return user;
  }

  String addFriendship(
    String requesterId,
    String addresseeId, {
    String status = 'accepted',
  }) {
    final row = FakeFriendshipRow(
      id: _newId('friendship'),
      requesterId: requesterId,
      addresseeId: addresseeId,
      status: status,
    );
    friendships.add(row);
    return row.id;
  }

  /// Test-Setup: Nutzer direkt anmelden, ohne den Login-Screen zu bedienen.
  void signInAs(String userId) => currentUserId = userId;

  FakeUser userById(String id) => users.firstWhere((u) => u.id == id);

  /// Wie der unique-Index `profiles_username_lower_key`: Vergeben ist ein
  /// Name auch, wenn er nur anders geschrieben ist.
  bool usernameTaken(String username) => users
      .any((u) => u.username.toLowerCase() == username.toLowerCase());

  /// Wie oft „andere Geräte abmelden" widerrufen hat — einzelne fremde
  /// Sitzungen modelliert der Fake nicht, aber der Effekt muss prüfbar
  /// sein und die eigene Sitzung unangetastet bleiben.
  int otherSessionsRevoked = 0;

  /// Der laufende E-Mail-Wechsel — wie in echt („Secure email change")
  /// mit ZWEI Codes, je einem pro Postfach. Erst wenn beide eingelöst
  /// sind, wird die Adresse wirklich umgestellt.
  String? pendingEmailChange;
  final emailChangeOldCode = '111222';
  final emailChangeNewCode = '333444';
  bool emailChangeOldConfirmed = false;
  bool emailChangeNewConfirmed = false;

  /// Wie die SQL-Funktion `are_friends`: nur akzeptierte Freundschaften.
  bool areFriends(String a, String b) => friendships.any((f) =>
      f.status == 'accepted' &&
      ((f.requesterId == a && f.addresseeId == b) ||
          (f.requesterId == b && f.addresseeId == a)));

  void setCurrentUser(FakeUser? user, AuthChangeEvent event) {
    currentUserId = user?.id;
    _authEvents.add(AuthState(event, user == null ? null : sessionFor(user)));
  }

  Session sessionFor(FakeUser user) => Session(
        accessToken: 'fake-token-${user.id}',
        tokenType: 'bearer',
        user: User(
          id: user.id,
          appMetadata: const {},
          userMetadata: {'username': user.username},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.backend);

  final FakeBackend backend;

  @override
  Session? get currentSession => backend.currentUserId == null
      ? null
      : backend.sessionFor(backend.userById(backend.currentUserId!));

  @override
  String? get currentUserId => backend.currentUserId;

  @override
  Stream<AuthState> get onAuthStateChange => backend.authEvents;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final user = backend.users
        .where((u) => u.email == email && u.password == password)
        .firstOrNull;
    if (user == null) {
      throw const AuthException('Invalid login credentials', statusCode: '400');
    }
    // Wie GoTrue mit Bestätigungspflicht: eigener Fehlercode, damit die
    // App nicht „E-Mail oder Passwort falsch" behauptet.
    if (!user.emailConfirmed) {
      throw const AuthException('Email not confirmed',
          statusCode: '400', code: 'email_not_confirmed');
    }
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    if (backend.usernameTaken(username)) {
      // Wie in echt: der Profil-Trigger scheitert am unique-Benutzernamen —
      // auch über Groß-/Kleinschreibung hinweg.
      throw const AuthException('Database error saving new user',
          statusCode: '500');
    }
    final user = backend.addUser(
        username: username,
        email: email,
        password: password,
        emailConfirmed: !backend.requireEmailConfirmation);
    if (backend.requireEmailConfirmation) {
      // Wie echt: Konto ja, Sitzung nein — erst die Bestätigung öffnet es.
      backend.confirmationMails.add(email);
      return true;
    }
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
    return false;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    final sent = backend.confirmationMails.where((m) => m == email).length;
    if (sent >= backend.confirmationMailLimit) {
      throw const AuthApiException(
          'For security purposes, you can only request this after 60 seconds.',
          statusCode: '429', code: 'over_email_send_rate_limit');
    }
    backend.confirmationMails.add(email);
  }

  @override
  Future<void> confirmEmailWithCode({
    required String email,
    required String code,
  }) async {
    final user = backend.users.where((u) => u.email == email).firstOrNull;
    if (user == null || code != FakeBackend.signupCode) {
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    // Wie echt: verifyOTP bestätigt UND meldet an.
    user.emailConfirmed = true;
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<void> signOut() async =>
      backend.setCurrentUser(null, AuthChangeEvent.signedOut);

  @override
  String? get currentEmail {
    final uid = backend.currentUserId;
    return uid == null ? null : backend.userById(uid).email;
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final uid = backend.currentUserId;
    if (uid == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    final user = backend.userById(uid);
    // Wie in echt: erst die frische Anmeldung — das falsche Passwort
    // scheitert, BEVOR irgendetwas angestoßen wird.
    if (user.password != currentPassword) {
      throw const AuthException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
    }
    if (backend.users
        .any((u) => u.email.toLowerCase() == newEmail.toLowerCase())) {
      throw const AuthException(
          'A user with this email address has already been registered',
          statusCode: '422',
          code: 'email_exists');
    }
    backend.pendingEmailChange = newEmail;
    backend.emailChangeOldConfirmed = false;
    backend.emailChangeNewConfirmed = false;
  }

  @override
  Future<void> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    final uid = backend.currentUserId;
    final pending = backend.pendingEmailChange;
    if (uid == null || pending == null) {
      throw const AuthException('Kein laufender Adresswechsel.');
    }
    final user = backend.userById(uid);
    // Wie gemessen: je Postfach ein eigener Code; erst BEIDE zusammen
    // vollziehen den Wechsel. Ein falscher Code ist otp_expired — wie
    // bei Reset und Registrierung.
    if (email == user.email && code == backend.emailChangeOldCode) {
      backend.emailChangeOldConfirmed = true;
    } else if (email == pending && code == backend.emailChangeNewCode) {
      backend.emailChangeNewConfirmed = true;
    } else {
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    if (backend.emailChangeOldConfirmed && backend.emailChangeNewConfirmed) {
      user.email = pending;
      backend.pendingEmailChange = null;
      // Wie in echt: der zweite Code bringt eine frische Sitzung mit —
      // das SDK feuert ein Auth-Event, und die Profil-Kachel hört
      // darauf (Read-after-write der neuen Adresse).
      backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
    }
  }

  @override
  Future<void> signOutOtherDevices() async {
    // Andere Sitzungen modelliert der Fake nicht einzeln — der Zähler
    // hält fest, DASS widerrufen wurde, und die eigene Sitzung bleibt
    // unangetastet (kein setCurrentUser, kein Event).
    backend.otherSessionsRevoked++;
  }

  /// Nimmt jede Adresse an — auch unbekannte. Genau so verhält sich
  /// Supabase, damit die Antwort kein Konto-Orakel wird.
  @override
  Future<void> sendPasswordResetCode(String email) async {
    if (backend.passwordResetTimesOut) {
      throw AuthRetryableFetchException(statusCode: '504');
    }
    if (backend.passwordResetFails) {
      throw const AuthApiException('Password recovery requires an email',
          statusCode: '400', code: 'validation_failed');
    }
    final sent = backend.passwordResets.where((m) => m == email).length;
    if (sent >= backend.passwordResetMailLimit) {
      throw const AuthApiException(
          'For security purposes, you can only request this after 24 seconds.',
          statusCode: '429', code: 'over_email_send_rate_limit');
    }
    backend.passwordResets.add(email);
  }

  /// Spiegelt die echte Reihenfolge: `verifyOTP` meldet die Sitzung mit
  /// `passwordRecovery` an, erst `updateUser` setzt das Passwort und meldet
  /// `userUpdated`. Der Router hängt an genau diesem Unterschied — hier
  /// beides zu verschmelzen würde den Test am Kernpunkt vorbeiführen.
  @override
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final user = backend.users.where((u) => u.email == email).firstOrNull;
    if (user == null || code != FakeBackend.resetCode) {
      // Wie GoTrue: derselbe Fehler für falschen Code und unbekannte
      // Adresse — sonst wäre auch das ein Konto-Orakel.
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    backend.setCurrentUser(user, AuthChangeEvent.passwordRecovery);
    if (backend.weakPasswords.contains(newPassword)) {
      throw const AuthException('Password is known to be weak and easy to '
          'guess, please choose a different one.',
          statusCode: '422', code: 'weak_password');
    }
    user.password = newPassword;
    backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
  }

  /// Spiegelt „Secure password change": Ohne das aktuelle Passwort geht
  /// nichts, denn die echte Methode meldet sich damit zuerst neu an. Der
  /// Fake kann diese Härtung nur behaupten — bewiesen wird sie nur gegen
  /// echtes GoTrue.
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final uid = backend.currentUserId;
    if (uid == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    final user = backend.userById(uid);
    if (user.password != currentPassword) {
      throw const AuthException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
    }
    if (newPassword == currentPassword) {
      throw const AuthException('New password should be different',
          statusCode: '422', code: 'same_password');
    }
    if (backend.weakPasswords.contains(newPassword)) {
      throw const AuthException('Password is known to be weak and easy to '
          'guess, please choose a different one.',
          statusCode: '422', code: 'weak_password');
    }
    user.password = newPassword;
    backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
  }

  /// Bildet die Kaskade aus `supabase/schema.sql` nach: alle Tabellen hängen
  /// per `on delete cascade` an profiles, profiles an auth.users. Echt räumt
  /// deshalb eine einzige Zeile alles ab — hier muss es von Hand passieren,
  /// damit Tests den tatsächlichen Effekt prüfen können und nicht nur, dass
  /// die Methode aufgerufen wurde.
  @override
  Future<void> deleteAccount() async {
    final uid = backend.currentUserId;
    if (uid == null) return;
    backend.friendships
        .removeWhere((f) => f.requesterId == uid || f.addresseeId == uid);
    backend.aliases.removeWhere((k, _) => k.owner == uid || k.friend == uid);
    backend.feedback.removeWhere((f) => f['user_id'] == uid);
    backend.users.removeWhere((u) => u.id == uid);
    backend.setCurrentUser(null, AuthChangeEvent.signedOut);
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.backend);

  final FakeBackend backend;

  FakeUser get _me => backend.userById(backend.currentUserId!);

  @override
  Future<Profile> fetchMyProfile() async => Profile(
        id: _me.id,
        username: _me.username,
        avatar: _me.avatar,
      );

  @override
  Future<void> updateAvatar(int avatar) async => _me.avatar = avatar;

  @override
  Future<void> updateUsername(String username) async {
    // Wie in echt: die unique-Verletzung kommt als PostgREST-Fehler mit
    // SQLSTATE 23505, nicht als Auth-Fehler — und sie greift über
    // Groß-/Kleinschreibung hinweg. Der eigene alte Name zählt nicht als
    // Kollision.
    if (backend.users.any((u) =>
        u.id != _me.id &&
        u.username.toLowerCase() == username.toLowerCase())) {
      throw const PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"profiles_username_lower_key"',
          code: '23505');
    }
    _me.username = username;
  }
}

class FakeFriendRepository implements FriendRepository {
  FakeFriendRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  /// Wie `search_profiles`: Benutzername als Teiltreffer, E-Mail nur
  /// EXAKT — sonst wäre die Suche ein Adressverzeichnis.
  @override
  Future<List<ProfileSearchResult>> search(String query) async {
    backend.failIfOffline();
    final q = query.trim().toLowerCase();
    return [
      for (final u in backend.users)
        if (u.id != _uid &&
            (u.username.toLowerCase().contains(q) ||
                u.email.toLowerCase() == q))
          ProfileSearchResult(id: u.id, username: u.username, avatar: u.avatar),
    ];
  }

  @override
  Future<List<FriendshipEntry>> fetchFriendships() async {
    backend.failIfOffline();
    return [
      for (final f in backend.friendships)
        if (f.requesterId == _uid || f.addresseeId == _uid)
          FriendshipEntry(
            id: f.id,
            status: f.status,
            requesterId: f.requesterId,
            addresseeId: f.addresseeId,
            requesterUsername: backend.userById(f.requesterId).username,
            addresseeUsername: backend.userById(f.addresseeId).username,
            requesterAvatar: backend.userById(f.requesterId).avatar,
            addresseeAvatar: backend.userById(f.addresseeId).avatar,
          ),
    ];
  }

  @override
  Future<void> sendRequest(String addresseeId) async {
    backend.failIfOffline();
    if (backend.friendships.any((f) =>
        (f.requesterId == _uid && f.addresseeId == addresseeId) ||
        (f.requesterId == addresseeId && f.addresseeId == _uid))) {
      // Wie in echt: unique-Constraint auf dem Freundschafts-Paar.
      throw StateError('duplicate friendship');
    }
    backend.addFriendship(_uid, addresseeId, status: 'pending');
  }

  @override
  Future<void> accept(String friendshipId) async {
    backend.failIfOffline();
    backend.friendships.firstWhere((f) => f.id == friendshipId).status =
        'accepted';
  }

  @override
  Future<void> remove(String friendshipId) async {
    backend.failIfOffline();
    final gone = backend.friendships.where((f) => f.id == friendshipId);
    for (final f in gone) {
      // Trigger `friendships_delete_aliases`: die Aliase beider Seiten
      // gehen mit.
      backend.aliases.removeWhere((k, _) =>
          (k.owner == f.requesterId && k.friend == f.addresseeId) ||
          (k.owner == f.addresseeId && k.friend == f.requesterId));
    }
    backend.friendships.removeWhere((f) => f.id == friendshipId);
  }

  /// Policy `fa_select`: nur, was ICH vergeben habe.
  @override
  Future<Map<String, String>> fetchAliases() async {
    backend.failIfOffline();
    return {
      for (final e in backend.aliases.entries)
        if (e.key.owner == _uid) e.key.friend: e.value,
    };
  }

  /// `fa_insert`/`fa_update`: nur für bestätigte Buddys; Check 1–40.
  @override
  Future<void> setAlias(String friendId, String alias) async {
    backend.failIfOffline();
    final key = (owner: _uid, friend: friendId);
    final text = alias.trim();
    if (text.isEmpty) {
      backend.aliases.remove(key);
      return;
    }
    if (!backend.areFriends(_uid, friendId)) {
      throw StateError('RLS: fa_insert (kein bestätigter Buddy)');
    }
    if (text.length > kAliasMaxLength) throw StateError('Check verletzt: alias');
    backend.aliases[key] = text;
  }
}

class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion, String? clientId}) async {
    backend.failIfOffline();
    // `client_id unique` (Patch 018): Der Server antwortet 23505, das
    // Repository liest es als „stand schon" — hier gleich ohne zweite Zeile.
    if (clientId != null && backend.feedback.any((f) => f['client_id'] == clientId)) return;
    backend.feedback.add({
      'user_id': backend.currentUserId,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
      'client_id': clientId,
    });
  }
}

/// Das Geräteregister für Push (#34). Die Tests prüfen, DASS ein Gerät
/// eingetragen wird und dass eine Testnachricht hinausgeht — nicht, wie
/// eine Benachrichtigung aussieht.
class FakePushRepository implements PushRepository {
  FakePushRepository(this.backend);

  final FakeBackend backend;

  /// Die Token, für die eine Testnachricht angefordert wurde.
  final tests = <String>[];

  Object? failNextRegister;

  @override
  Future<void> register(String token) async {
    final error = failNextRegister;
    if (error != null) {
      failNextRegister = null;
      throw error;
    }
    backend.pushDevices[token] = backend.currentUserId!;
  }

  @override
  Future<void> unregister(String token) async {
    backend.pushDevices.remove(token);
  }

  @override
  Future<void> sendTest(String token) async {
    if (backend.pushDevices[token] != backend.currentUserId) {
      // Genau das, was die Edge Function über die RLS entscheidet: Ein
      // fremdes Token geht niemanden etwas an.
      throw StateError('unknown device');
    }
    tests.add(token);
  }
}

class FakeAppConfigRepository implements AppConfigRepository {
  FakeAppConfigRepository({this.minimumSupportedVersion, this.fails = false});

  final String? minimumSupportedVersion;

  /// Abruf scheitern lassen — der Fall, in dem die App trotzdem starten muss.
  final bool fails;

  @override
  Future<String?> fetchMinimumSupportedVersion() async {
    if (fails) throw Exception('kein Netz');
    return minimumSupportedVersion;
  }
}
