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

cat > "$STAGE/Bitte zuerst lesen.txt" <<'TXT'
PDF Shrink — Installation
=========================

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


Wenn etwas klemmt
-----------------
"... ist beschädigt und kann nicht geöffnet werden"
    Schritt 2 wurde übersprungen oder der Pfad stimmt nicht.
    Liegt die App woanders, den Pfad im Befehl anpassen.

"Ghostscript fehlt"
    Schritt 3 fehlt. Nach der Installation die App neu starten.

Beim ersten Öffnen einer PDF aus Dokumente, Schreibtisch oder
Downloads fragt macOS nach Zugriff — das ist normal, bitte erlauben.
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
