# Lexmark Toner Info

Kleines Shell-Skript zum Auslesen von Drucker-, Toner- und Verbrauchsmaterialdaten eines Lexmark-Netzwerkdruckers.

Das Skript findet den Drucker über CUPS/IPP, fragt die Lexmark-Weboberfläche ab und schreibt die relevanten Werte als lesbare Textdatei sowie als JSON.

## Motivation

Beim Bestellen, Registrieren oder Recyceln von Tonerkartuschen werden mehrere ähnlich aussehende Nummern benötigt:

- die Seriennummer des Druckers
- die Seriennummer der Tonerkartusche
- das Tonermodell bzw. die Teilenummer
- eine bereinigte Toner-Seriennummer für den Lexmark-Recyclingprozess

Diese Werte sind in der Weboberfläche des Druckers vorhanden, aber nicht immer auf einen Blick leicht zu finden. Dieses Skript automatisiert die Abfrage und speichert die Daten reproduzierbar in Dateien.

Für Rücksendungen über das Lexmark Cartridge Collection Program verlangt Lexmark leider ebenfalls Werte wie die Drucker-Seriennummer und die Toner-Seriennummer. Die Drucker-Seriennummer wird auch bei der Registrierung eines Accounts für das Recyclingprogramm abgefragt. Die Lexmark-Seite ist hier:

https://www.lexmark.com/de_de/supplies-and-parts/reuse-and-recycling-program/cartridge-collection-program.html

Dieses Skript ist kein Teil des Lexmark-Programms. Es ist nur ein kleiner Helfer: Es liest Werte aus, die ohnehin bereits im Drucker vorhanden sind, und bereitet nebenbei die Toner-Seriennummer in der für das Rücksendeformular benötigten reinen Ziffernform auf. Diese Seriennummer ist der Wert, der mit `CAP` oder `SCAP` beginnt; `B242H00` ist das Tonermodell bzw. die Teilenummer.

Wichtig: Die IP-Adresse des Druckers ist nicht fest im Skript eingetragen. Der Drucker wird über die lokale CUPS/IPP-Konfiguration oder über IPP-Discovery gefunden.

## Funktionen

- findet einen erreichbaren Lexmark-Drucker über CUPS/IPP
- liest die Drucker-Seriennummer aus
- liest Tonermodell/Teilenummer, Toner-Seriennummer, Tonerstand und Restseiten aus
- liest Daten zum Belichtungskit aus
- erzeugt eine reine Ziffernform der Toner-Seriennummer für Lexmark-Recycling
- schreibt eine Textdatei und eine JSON-Datei

## Voraussetzungen

Das Skript ist für Linux-Systeme mit Bash gedacht. Benötigte Programme:

- `bash`
- `curl`
- `jq`
- `ipptool`
- optional, aber nützlich: `lpstat` und `ippfind`

Unter Debian/Ubuntu können die typischen Pakete so installiert werden:

```bash
sudo apt install cups-client cups-ipp-utils curl jq
```

Der Drucker muss eingeschaltet und im Netzwerk erreichbar sein. Wenn er in CUPS eingerichtet ist, kann das Skript ihn normalerweise ohne weitere Konfiguration finden.

## Verwendung

Standardlauf:

```bash
./lexmark_toner_info.sh
```

Dadurch entstehen im Projektverzeichnis diese Dateien:

- `drucker_daten.txt`
- `drucker_daten.json`

Optional kann ein eigener Basisname für die Ausgabedateien übergeben werden:

```bash
./lexmark_toner_info.sh meine_lexmark_daten
```

Dadurch entstehen:

- `meine_lexmark_daten.txt`
- `meine_lexmark_daten.json`

## Beispielausgabe

```text
Abfragezeit: 2026-05-24T13:16:15+02:00
Drucker: Lexmark MB2442adwe
Druckername: Lexmark MB2442adwe
Drucker-Seriennummer: 7017948261FW2
Hinweis: Das Lexmark-Recyclingprogramm fragt diese Drucker-Seriennummer auch bei der Account-Registrierung ab.

Schwarzer Toner: Black Toner
Toner-Modell/Teilenummer: B242H00
Toner-Seriennummer: CAP291847DBF
Toner-Seriennummer für Lexmark-Recycling (nur Ziffern): 291847
Tonerstand: 84 %
Restseiten: 3000
Tonerstatus: OK

Belichtungskit: Black Imaging Kit
Belichtungskit-Teilenummer: 36S0006
Belichtungskit-Seriennummer: CAD158473EF2
Belichtungskit-Stand: 83 %
Belichtungskit-Restseiten: 37400
Belichtungskit-Status: OK
```

## Recycling-Seriennummer

Für das Cartridge Collection Program erwartet Lexmark nur die Ziffern aus der Toner-Seriennummer. Das Skript behält deshalb die originale Toner-Seriennummer bei und erzeugt zusätzlich einen bereinigten Wert:

```text
CAP291847DBF -> 291847
```

Die originale Toner-Seriennummer bleibt in der Ausgabe erhalten. `B242H00` ist das Tonermodell bzw. die Teilenummer und wird nicht für den Recycling-Ziffernwert verwendet. Für das Belichtungskit wird keine separate Recycling-Seriennummer erzeugt.

Die Drucker-Seriennummer ist davon getrennt. Sie wird unverändert ausgegeben, weil Lexmark sie auch bei der Account-Registrierung für das Recyclingprogramm abfragt.

## Dateien

- `lexmark_toner_info.sh`: Skript zum Abfragen des Druckers und Schreiben der Ausgabedateien
- `drucker_daten.txt`: menschenlesbare Ausgabe
- `drucker_daten.json`: strukturierte Ausgabe zur Weiterverarbeitung

## Hinweise

Das Skript wurde unter Debian/Ubuntu entwickelt und ist aktuell auf die für diesen Anwendungsfall benötigten Lexmark-Daten fokussiert. Getestet wurde es mit einem Lexmark MB2442adwe. Andere Lexmark-Modelle können leicht andere Feldnamen oder Verbrauchsmaterialdaten liefern.

Der getestete Drucker verlangte keine Authentifizierung für die eingebettete Weboberfläche. Falls die Statusseiten durch Benutzername und Passwort geschützt sind, unterstützt das Skript derzeit keinen Login.

Wenn der Drucker für die Statusseite `HTTP 404` zurückgibt, während er noch startet, beendet sich das Skript mit einer klaren Fehlermeldung. In diesem Fall warten, bis der Drucker fertig gebootet hat, und den Befehl erneut ausführen.

Wenn kein Drucker gefunden wird, zuerst diese Befehle prüfen:

```bash
lpstat -v
ippfind
```

Der Drucker muss eingeschaltet sein, und sowohl IPP als auch die eingebettete Weboberfläche müssen erreichbar sein.
