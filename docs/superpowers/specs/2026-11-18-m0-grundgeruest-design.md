# M0: Grundgerüst – Design

Stand: 2026-11-18 · Gesamtplan siehe `CLAUDE.md`

## Absicht

M0 beweist, dass die gesamte Kette funktioniert, bevor es Features gibt: Code auf einem Linux-Laptop ohne Mac schreiben → in der Cloud für iOS bauen → per Sideload auf dem iPhone starten. Weil iOS lokal weder gebaut noch getestet werden kann, ist diese Kette das größte Risiko des Projekts. Es soll geklärt sein, solange die App noch leer ist und Fehler leicht zu finden sind.

Rust (flutter_rust_bridge + `lofty`) kommt bereits in M0 dazu. Grund: Tags zuverlässig zu schreiben (M3) erfordert praktisch ohnehin Rust, und der Rust-Build für iOS in der CI ist der fehleranfälligste Teil der Kette.

## Ziele

- Flutter-Projekt `owntune` mit den Plattformen iOS, Android und Linux.
- Rust-Kern in `rust/`, angebunden über flutter_rust_bridge v2, inklusive eines einfachen Aufrufs, dessen Ergebnis in der App sichtbar ist.
- Öffentliches GitHub-Repo mit Actions-Workflows:
  - **Linux-Job** (bei jedem Push/PR): `flutter analyze`, `flutter test`, `cargo test` und `cargo clippy` für den Rust-Kern, Android-APK bauen.
  - **macOS-Job** (nur bei Versions-Tags `v*` und manuell auslösbar – geändert am 2026-11-18, weil die Wartezeit auf macOS-Runner den Entwicklungsfluss bremst; täglich wird unter Linux bzw. im Android-Emulator entwickelt): `flutter build ios --release --no-codesign`, daraus eine unsignierte `.ipa` packen (`Payload/Runner.app` → zip) und als Artifact hochladen.
- Lokale Entwicklungsumgebung auf dem Laptop: Flutter, Rust (rustup), CMake und Ninja, sodass `flutter run -d linux` funktioniert.
- `CLAUDE.md` an den echten Stand anpassen (Befehle, Ordner, Codegen-Schritte).

**Fertig, wenn:** Die leere App startet unter Linux, zeigt das Ergebnis des Rust-Aufrufs an, und dieselbe App, aus der CI-`.ipa` per SideStore/iloader installiert, startet auf dem iPhone und zeigt dasselbe Ergebnis.

## Nicht-Ziele

- Keine Features aus M1+ (kein Import, keine Datenbank, kein Audio). drift, Riverpod, just_audio usw. werden erst mit dem Meilenstein hinzugefügt, der sie braucht.
- Kein lokales Android-SDK und kein Emulator in M0; Android wird nur in der CI gebaut. Das lokale Emulator-Setup kommt später.
- Kein Signieren, kein TestFlight, keine Store-Veröffentlichung.

## Anti-Ziele

- Eine CI, die „grün“ ist, deren `.ipa` aber auf dem iPhone nicht startet oder den Rust-Aufruf nicht ausführen kann. Erfolg wird auf dem echten Gerät gemessen, nicht am CI-Status.
- Plattformspezifische Sonderwege, die nur auf einem Ziel funktionieren. Der Rust-Aufruf muss auf Linux, Android (Build) und iOS über denselben Dart-Code laufen.

## Rahmenbedingungen

- Entwicklungsrechner: Arch-basiertes Linux (Omarchy), kein Mac. Vorhanden: git, GitHub-CLI (eingeloggt), clang, GTK3, libmpv. Fehlend: Flutter, Rust, CMake, Ninja, Java, Android-SDK.
- Repo öffentlich → GitHub-Actions-Minuten (inkl. macOS) kostenlos; iOS-Build darf deshalb bei jedem Push auf `main` laufen.
- Installation aufs iPhone erfolgt manuell durch den Nutzer per SideStore/iloader mit kostenloser Apple-ID.

## Ansätze

**Rust-Zeitpunkt** (vom Nutzer entschieden: A)
- **A – Rust in M0:** komplexere CI, aber das Risiko „Rust auf iOS über die Cloud“ wird geklärt, solange die App leer ist. **Gewählt.**
- B – Rust später: schnelleres M0, aber das größte Risiko wandert in M1/M3, mitten in Feature-Code.

**Rust-Anbindung** (meine Entscheidung)
- **flutter_rust_bridge v2 mit seiner Standard-Build-Integration (cargokit):** Rust wird bei `flutter build` für jede Plattform automatisch mitgebaut; kein separater Build-Schritt für vorgefertigte Bibliotheken. **Gewählt.**
- Vorgebaute Rust-Bibliotheken je Plattform, die die CI separat erzeugt und einbindet: mehr Kontrolle, aber deutlich mehr eigener Build-Code. Ohne Not nicht sinnvoll.

**Repo-Sichtbarkeit** (vom Nutzer entschieden: öffentlich)
- **Öffentlich:** keine Minutenkosten, iOS-Build bei jedem Push. **Gewählt.**
- Privat: Code bleibt privat, aber nur ca. 200 effektive macOS-Minuten pro Monat im Freikontingent.

## Entscheidungen

Vom Nutzer:
- Rust-Kern schon in M0.
- Öffentliches GitHub-Repo, Workflows über GitHub Actions.

Meine Entscheidungen (vom Nutzer nicht widersprochen):
- flutter_rust_bridge v2 mit Standard-Integration; Rust-Crate in `rust/`.
- Android-Plattform wird angelegt und nur in der CI gebaut (APK), lokal kein Android-SDK.
- Vorläufige Bundle-ID / Application-ID: `dev.owntune.app`.
- Repo heißt `owntune`, liegt unter dem eingeloggten GitHub-Account, Hauptzweig `main`.
- Werkzeuge werden erst nach Freigabe dieses Designs installiert.

Bei der Ausarbeitung von mir festgelegt:
- Der Rust-Kern bindet `lofty` bereits als Abhängigkeit ein, und der Testaufruf nutzt es (z. B. gibt er die Liste der von `lofty` unterstützten Formate oder eine Versionsinfo zurück). So ist nicht nur „Rust auf iOS“, sondern genau die Bibliothek, die später gebraucht wird, auf allen Zielen bewiesen.
- Von flutter_rust_bridge generierter Dart- und Rust-Code wird eingecheckt. Die CI prüft, dass er zum aktuellen Rust-Code passt, damit sie den Codegen nicht als Pflichtschritt vor jedem Build braucht.
- Die App-Oberfläche in M0 ist ein einziger Bildschirm mit App-Name und dem Ergebnis des Rust-Aufrufs; mehr nicht.

## Dem Umsetzenden überlassen

- Installationsweg für Flutter auf Arch (offizielles Git-Checkout, AUR-Paket oder fvm); Hauptsache stabiler Kanal und reproduzierbar.
- Konkrete Versionen von Flutter, flutter_rust_bridge, `lofty` und den Actions; aktuelle stabile Versionen wählen und festschreiben.
- iOS-Mindestversion: Flutter-Standard, sofern nichts dagegen spricht.
- Caching in der CI (Flutter-SDK, Cargo, Pods), solange die Workflows korrekt bleiben.
- Ob und wie ein Dart-Test den Rust-Aufruf auf dem Linux-Runner mit der echten nativen Bibliothek prüft; mindestens ein Rust-Unit-Test für die Kernfunktion und ein Widget-Test für den Startbildschirm.
