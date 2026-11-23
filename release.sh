#!/bin/bash
# Packt eine weitergebbare ZIP-Datei für Apple Silicon.
#
# Bewusst mit ditto statt zip: ditto erhält die Bundle-Struktur, Symlinks und
# die Code-Signatur. Ein normales "zip" beschädigt die Signatur, die App startet
# beim Empfänger dann auch nach dem Entfernen der Quarantäne nicht.
set -e
cd "$(cd "$(dirname "$0")" && pwd)"

APP="PDF Shrink.app"
STAGE="dist/PDF Shrink"

echo "→ frisch bauen"
./build.sh --no-install >/dev/null

# Version aus dem gebauten Bundle lesen, damit Dateiname und App nie auseinanderlaufen
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/PDF Shrink" | tr ' ' '-')"
ZIP="dist/PDF-Shrink-$VERSION-$ARCH.zip"

echo "→ Paket zusammenstellen"
rm -rf dist
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP"

cat > "$STAGE/Bitte zuerst lesen - Read me first.txt" <<'TXT'
PDF Shrink — Installation
=========================
(English below)

Voraussetzung: Mac mit Apple Silicon (M1 oder neuer), macOS 14 oder neuer.

1. "PDF Shrink.app" in den Ordner "Programme" ziehen.

   Wichtig: erst verschieben, dann starten. Solange die App im
   entpackten Download-Ordner liegt, kennt macOS sie noch nicht
   richtig — PDFs, die man dann aufs Icon zieht, kommen unter
   Umständen nicht an.

2. Terminal öffnen (Spotlight mit cmd+Leertaste, "Terminal" eingeben)
   und diese Zeile einfügen, dann Enter:

   xattr -dr com.apple.quarantine "/Applications/PDF Shrink.app"

   Das hebt die macOS-Sperre für Programme ohne Apple-Entwickler-
   zertifikat auf. Ohne diesen Schritt meldet macOS, die App sei
   beschädigt — sie ist es nicht, sie ist nur nicht kostenpflichtig
   bei Apple registriert.

3. Ghostscript installieren — das erledigt die eigentliche
   Komprimierung. Ebenfalls im Terminal:

   brew install ghostscript

   Falls "brew" nicht gefunden wird, zuerst Homebrew einrichten:
   https://brew.sh

4. App starten. PDFs ins Fenster ziehen oder auf das Dock-Icon legen,
   Kompressionsstufe wählen, fertig. Das Ergebnis lässt sich neben dem
   Original speichern oder über "Speichern unter ..." ablegen.
   Das Original wird nie verändert oder überschrieben.

   Die Oberfläche lässt sich oben rechts zwischen Deutsch und
   Englisch umschalten.

Wenn etwas klemmt
-----------------
"... ist beschädigt und kann nicht geöffnet werden"
    Schritt 2 wurde übersprungen oder der Pfad stimmt nicht.
    Liegt die App woanders, den Pfad im Befehl anpassen.

"Ghostscript fehlt"
    Schritt 3 fehlt. Nach der Installation die App neu starten.

Beim ersten Öffnen einer PDF aus Dokumente, Schreibtisch oder
Downloads fragt macOS nach Zugriff — das ist normal, bitte erlauben.


PDF Shrink — Installation
=========================

Requirements: Mac with Apple Silicon (M1 or newer), macOS 14 or newer.

1. Move "PDF Shrink.app" into your Applications folder.

   Important: move it first, launch it second. While the app sits in
   the unzipped download folder macOS does not know it properly, and
   PDFs dropped onto its icon may not arrive.

2. Open Terminal (Spotlight with cmd+space, type "Terminal"), paste
   this line and press Enter:

   xattr -dr com.apple.quarantine "/Applications/PDF Shrink.app"

   This lifts the macOS block on apps without an Apple developer
   certificate. Without it macOS claims the app is damaged — it is
   not, it is simply not registered with Apple, which costs money.

3. Install Ghostscript, which does the actual compression. Also in
   Terminal:

   brew install ghostscript

   If "brew" is not found, set up Homebrew first: https://brew.sh

4. Launch the app. Drop PDFs into the window or onto the dock icon,
   pick a compression level, done. Save the result next to the
   original or via "Save as ...". The original is never modified
   or overwritten.

   Use the switch in the top right to change the interface between
   German and English.

If something goes wrong
-----------------------
"... is damaged and can't be opened"
    Step 2 was skipped, or the path is wrong. If the app lives
    somewhere else, adjust the path in the command.

"Ghostscript missing"
    Step 3 is missing. Restart the app after installing.

The first time you open a PDF from Documents, Desktop or Downloads,
macOS asks for access — that is normal, please allow it.
TXT

echo "→ ZIP packen"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

echo "→ prüfen"
VERIFY="$(mktemp -d)"
ditto -x -k "$ZIP" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/PDF Shrink/$APP" \
  && echo "   Signatur nach dem Entpacken intakt"
lipo -archs "$VERIFY/PDF Shrink/$APP/Contents/MacOS/PDF Shrink" | sed 's/^/   Architektur: /'
rm -rf "$VERIFY"

echo
echo "Fertig: $PWD/$ZIP  ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
echo "Diese eine Datei weitergeben."
