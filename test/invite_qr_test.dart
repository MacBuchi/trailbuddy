// Der Einladung-QR (#496): was im QR steht, und ob das Ziel tatsächlich
// da ist. Der QR trägt keine Version — die Installationsseite entscheidet,
// was geladen wird.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trailbuddy/core/app_colors.dart';
import 'package:trailbuddy/core/app_info.dart';
import 'package:trailbuddy/core/app_theme.dart';
import 'package:trailbuddy/core/widgets/trailbuddy_logo.dart';
import 'package:trailbuddy/features/friends/invite_qr.dart';
import 'package:trailbuddy/l10n/l10n.dart';

void main() {
  test('der QR nennt die Installationsseite mit dem Namen', () {
    expect(AppInfo.inviteUrl('Jan'),
        'https://macbuchi.github.io/trailbuddy/install.html?invite=Jan');
    expect(AppInfo.inviteUrl('Müller & Co'),
        contains('invite=M%C3%BCller%20%26%20Co'),
        reason: 'Umlaute und Sonderzeichen müssen im QR kodierbar bleiben');
    expect(AppInfo.inviteUrl(null),
        'https://macbuchi.github.io/trailbuddy/install.html');
    expect(AppInfo.inviteUrl('  '),
        'https://macbuchi.github.io/trailbuddy/install.html');
  });

  test('die Seite, die der QR öffnet, liegt im Web-Ordner', () {
    // Kein Test-Netz hier: geprüft wird nur, dass das Ziel existiert und
    // denselben invite-Parameter versteht wie AppInfo.inviteUrl.
    final html = File('web/install.html').readAsStringSync();
    expect(AppInfo.installUrl.endsWith('/install.html'), isTrue);
    expect(File('web/install.html').existsSync(), isTrue, reason: 'QR-Ziel fehlt im Pages-Deploy');
    expect(html, contains('invite'), reason: 'Die Seite liest den Einladungs-Namen nicht');
    expect(html, contains('api.github.com'), reason: 'ohne ReleaseAbruf gibt es keinen direkten APK-Link');
    expect(html, contains('/Android/'), reason: 'ohne Android ist die APK kein Weg — die Seite muss das sagen');
    expect(html, contains('schon installiert'), reason: 'Scanner mit App brauchen den SuchHinweis, nicht die APK');
  });

  test('das Logo deckt nur so viel ab, dass der Code lesbar bleibt', () {
    // Die Fehlerkorrektur H ersetzt etwa 30 % der Codewörter. Das Logo liegt
    // in der Mitte und malt Module zu — bleibt es darüber, scannt nichts mehr.
    final codeSide = qrCodeSide - 2 * qrQuietZone;
    final coverage = (qrLogoSide * qrLogoSide) / (codeSide * codeSide);
    expect(coverage, lessThan(0.15), reason: 'Logo bedeckt ${(coverage * 100).toStringAsFixed(1)} %');
  });

  testWidgets('der Dialog zeigt QR, Logo, Adresse und den Text-Knopf', (tester) async {
    var shared = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      theme: buildAppTheme(AppColors.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showInviteDialog(context, username: 'Jan', shareText: () async => shared++),
            child: const Text('Einladung'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Einladung'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(TrailBuddyMark), findsOneWidget);
    expect(find.text(AppInfo.inviteUrl('Jan')), findsOneWidget);
    await tester.tap(find.text('Text teilen'));
    await tester.pumpAndSettle();
    expect(shared, 1, reason: 'der Knopf muss die Einladung wirklich teilen');
    expect(find.byType(QrImageView), findsNothing, reason: 'der Dialog schließt sich');
  });
}
