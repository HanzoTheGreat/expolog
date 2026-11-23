ExpoLog

Ein lokaler, verschlüsselter Begleiter für Expositionstherapie (Angst- und Zwangsstörungen) sowie langfristige Verlaufsdokumentation.

Wichtiger Hinweis: ExpoLog ist ein rein persönliches Protokoll- und Dokumentationswerkzeug und kein Medizinprodukt. Die App speichert ausschließlich eigene Eingaben, stoppt Zeitintervalle und stellt Verläufe unverändert grafisch dar. Sie berechnet keine klinischen Scores, trifft keine diagnostischen Aussagen, gibt keine Therapieempfehlungen und ersetzt weder Psychotherapie noch ärztliche Behandlung.

Leitprinzipien

100 % offline & lokal verschlüsselt: Alle Daten liegen in einer SQLCipher-Datenbank (expolog.db) direkt auf dem Gerät. Keine Cloud, keine Accounts, keine Telemetrie.

Keine Bewertungs- oder Gamification-Fallen: Keine Streaks, keine automatischen Scores, keine beruhigenden Texte während laufender Übungen.

Diskret im Alltag: Der Android-Hintergrund-Timer zeigt in der Statusleiste ausschließlich neutrale Statusmeldungen („Timer aktiv“ / „Check-in fällig“) ohne Themennamen oder klinische Begriffe.

Aktueller Funktionsumfang

Katalog (Ruhephasen-Pflege): Kategorien mit Farbcodierung, konkrete Themen/Auslöser (inkl. Kernbefürchtung und typischer Reaktion) sowie strikt themengebundene Sicherheitsverhalten/Ersatzhandlungen mit Archivierungsfunktion.

Live-Exposition: Minimaler Ablenkungs-Modus mit frei wählbarer Skala (0–10 oder 0–100), Check-in-Intervallen, haptischem Hintergrund-Ping unter Android (Foreground-Service mit WakeLock), neutralen Markern für Vermeidung/Sicherheitsverhalten, Crash-Recovery sowie Abschluss-Abgleich zur Erwartungsverletzung.

Alltags-Aufschub-Timer: 1-Tap-Timer (5 / 10 / 15 min) für akute Kontroll-, Rückversicherungs- oder Vermeidungsimpulse.

Überlagerte Verlaufskurven: Normierte Darstellung (0–100 %) mehrerer Durchgänge desselben Themas übereinander.

Zoombarer Zeitstrahl: 1D-Horizontal-Zoom über Wochen bis Jahre mit fixierter Kontext-Spur (Klinik, Medikation, Therapie, Lebensereignisse), aufklappbaren Kategorie-Bündeln, unscharfen Zeiträumen (Tag / Monat / Quartal / Jahr), Sicherheitsverhalten-Badges und Expositions-Markern im Detail-Zoom.

Vorzeige-Modus: Sperrt Bearbeitungsfunktionen und Navigation in andere App-Bereiche per Passphrase/PIN für Gespräche im therapeutischen oder klinischen Setting.

Tech-Stack

UI: Flutter (Android & Linux)

Core & Persistenz: Rust + flutter_rust_bridge + SQLite (rusqlite mit bundled-sqlcipher-vendored-openssl)

Hintergrund-Timer (Android): Nativer Kotlin-Foreground-Service über MethodChannel

Lokal bauen

Voraussetzungen: Flutter SDK, Rust Toolchain (cargo), für SQLCipher/OpenSSL auf dem Host zusätzlich perl, make und ein C-Compiler; für Android zusätzlich Android SDK/NDK.

# Rust-Unit-Tests ausführen
cargo test --manifest-path rust/Cargo.toml

# Flutter-Abhängigkeiten laden und prüfen
flutter pub get
flutter analyze

# Linux-Desktop starten
flutter run -d linux

# Android-Release-APK bauen
flutter build apk --release


Lizenz

Copyright (c) 2026 HanzoTheGreat

Dieses Projekt steht unter der PolyForm Noncommercial License 1.0.0 (PolyForm-Noncommercial-1.0.0) – den vollständigen Lizenztext findest du in LICENSE.md sowie unter https://polyformproject.org/licenses/noncommercial/1.0.0.

Private, therapeutische und gemeinnützige Nutzung, Weitergabe und Veränderung sind frei erlaubt; jede kommerzielle Nutzung oder Monetarisierung ist untersagt.