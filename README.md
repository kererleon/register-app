<p align="center">
  <img src="assets/icon/register_icon.png" width="140" alt="Register">
</p>

<h1 align="center">Register</h1>

<p align="center">
  Eine moderne, inoffizielle App für das <b>Digitale Register</b> –<br>
  Noten, Hausaufgaben, Stundenplan und Absenzen an einem Ort.
</p>

<p align="center">
  <a href="https://github.com/kererleon/register-app/releases/latest"><b>⬇️ Neueste Version herunterladen</b></a>
</p>

---

## Funktionen

- **Heute** – laufende Stunde mit Restzeit, was heute und morgen fällig ist, nächste Tests auf einen Blick
- **Noten** – Durchschnitt pro Fach und gesamt, dazu die **Noten-Prognose**: welche Note du im nächsten Test brauchst, um auf 6, 7 oder 8 zu kommen
- **Test-Countdown & Lernplan** – Tests mit Countdown; ein Klick verteilt Lerneinheiten als Erinnerungen ins Register
- **Absenzen** – im Voraus melden, entschuldigen und löschen, mit **Fehlstunden-Ampel** bis zur 25-%-Grenze
- **Aufgaben verschieben** – auch Aufgaben von Lehrpersonen, als Erinnerung sichtbar auf allen Geräten und der Webseite
- **Kalender** – Wochenansicht mit Markierung der laufenden Stunde und Profilbildern der Lehrpersonen
- **Mitteilungen** – bei neuen Noten, Aufgaben, Benachrichtigungen und Supplenzen
- **Zwei Designs** – *Holo* (futuristisch, clean) und *Brainrot* (laut, bunt, Meme-Style), umschaltbar in den Einstellungen
- **Widgets für macOS** – Stundenplan, Tests & Aufgaben, Notendurchschnitt

## Installation

### Android
1. [**Register-Android.apk**](https://github.com/kererleon/register-app/releases/latest) auf dem Handy herunterladen
2. Datei öffnen und erlauben, dass der Browser **Apps aus unbekannten Quellen** installieren darf
3. Installieren – Updates werden einfach über die alte Version installiert

### Windows
1. [**Register-Setup.exe**](https://github.com/kererleon/register-app/releases/latest) herunterladen und starten
2. Falls SmartScreen warnt: *Weitere Informationen → Trotzdem ausführen*
3. Den Schritten folgen – Register landet im Startmenü (auf Wunsch auch auf dem Desktop), Administratorrechte sind nicht nötig
4. Deinstallieren über *Einstellungen → Apps*

Ohne Installation: **Register-Windows.zip** entpacken und `Register.exe` starten.

### iPhone & Mac
Für iOS und macOS gibt es keinen fertigen Download – Apple erlaubt das nur über den App Store.
Du kannst die App aber selbst mit Xcode bauen (siehe unten) und mit einer kostenlosen Apple-ID
auf deine eigenen Geräte installieren.

## Ohne Konto ausprobieren

Im **Demo-Modus** zeigt die App Beispieldaten:
Schule `Vinzentinum`, Benutzer `demo-user-6540`, beliebiges Passwort.

## Datenschutz

- Die App spricht nur mit dem Server deiner Schule (`*.digitalesregister.it`) und lädt Profilbilder von der öffentlichen Webseite der Schule.
- Zugangsdaten werden – wenn du „Angemeldet bleiben“ wählst – **nur verschlüsselt auf deinem Gerät** gespeichert.
- Es gibt keine Werbung, kein Tracking und keinen eigenen Server.

## Selbst bauen

Voraussetzungen: [Flutter](https://flutter.dev) (stable), für iOS/macOS zusätzlich Xcode, für Android das Android SDK.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Für iOS und macOS trägst du dein Apple-Entwicklerteam in eine lokale Datei ein, die nicht im Repository landet:

```bash
echo "DEVELOPMENT_TEAM = DEINE_TEAM_ID" > ios/Flutter/Team.xcconfig
cp ios/Flutter/Team.xcconfig macos/Runner/Configs/Team.xcconfig
```

Android-APK und Windows-Version baut GitHub Actions automatisch bei jedem Push auf `main` und veröffentlicht sie als Release.

## Herkunft & Lizenz

Register basiert auf der App [**digitales_register**](https://github.com/miDeb/digitales_register) von
Michael Debertol, die seit 2023 nicht mehr weiterentwickelt wird. Danke für die großartige Grundlage!

Diese App ist **kein offizielles Produkt** des Digitalen Registers und steht in keiner Verbindung zu dessen Betreiber.

Lizenziert unter der [GNU General Public License v3.0](LICENSE.txt).
