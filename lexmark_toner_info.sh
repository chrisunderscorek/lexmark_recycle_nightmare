#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH=cd -- "$(dirname -- "$0")" && pwd)"
OUT_BASE="${1:-"$SCRIPT_DIR/drucker_daten"}"
OUT_BASE="${OUT_BASE%.txt}"
OUT_BASE="${OUT_BASE%.json}"
TXT_FILE="$OUT_BASE.txt"
JSON_FILE="$OUT_BASE.json"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Fehlendes Programm: $1" >&2
    exit 1
  fi
}

uri_host() {
  printf '%s\n' "$1" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://([^/@]+@)?(\[[^]]+\]|[^/:/?#]+).*#\2#; s#^\[##; s#\]$##'
}

collect_uris() {
  if command -v lpstat >/dev/null 2>&1; then
    lpstat -v 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(ipps?|https?)://' || true
  fi

  if command -v ippfind >/dev/null 2>&1; then
    ippfind 2>/dev/null || true
  fi
}

expand_ipp_uris() {
  while IFS= read -r uri; do
    [ -n "$uri" ] || continue

    case "$uri" in
      ipp://*|ipps://*) printf '%s\n' "$uri" ;;
    esac

    host="$(uri_host "$uri")"
    if [ -n "$host" ] && [ "$host" != "$uri" ]; then
      printf 'ipp://%s/ipp/print\n' "$host"
      printf 'ipps://%s/ipp/print\n' "$host"
    fi
  done | awk '!seen[$0]++'
}

ipp_value() {
  awk -v key="$1" '
    index($0, key " ") {
      sub(/^.* = /, "")
      print
      exit
    }
  '
}

find_lexmark_printer() {
  local uri attrs

  while IFS= read -r uri; do
    [ -n "$uri" ] || continue
    attrs="$(ipptool -tv "$uri" get-printer-attributes.test 2>/dev/null || true)"

    if printf '%s\n' "$attrs" | grep -Eiq 'printer-(name|make-and-model).*Lexmark'; then
      PRINTER_URI="$uri"
      IPP_ATTRS="$attrs"
      return 0
    fi
  done < <(collect_uris | expand_ipp_uris)

  echo "Kein erreichbarer Lexmark-Drucker per CUPS/IPP gefunden." >&2
  exit 1
}

require_cmd curl
require_cmd jq
require_cmd ipptool

PRINTER_URI=""
IPP_ATTRS=""
find_lexmark_printer

PRINTER_MODEL="$(printf '%s\n' "$IPP_ATTRS" | ipp_value 'printer-make-and-model')"
PRINTER_NAME="$(printf '%s\n' "$IPP_ATTRS" | ipp_value 'printer-name')"
SUPPLIES_URL="$(printf '%s\n' "$IPP_ATTRS" | ipp_value 'printer-supplies-info-uri')"
if [ -z "$SUPPLIES_URL" ]; then
  SUPPLIES_URL="$(printf '%s\n' "$IPP_ATTRS" | ipp_value 'printer-supply-info-uri')"
fi

WEB_BASE="$(printf '%s\n' "$SUPPLIES_URL" | sed -E 's#^(https?://[^/]+).*#\1#')"
if [ -z "$WEB_BASE" ] || [ "$WEB_BASE" = "$SUPPLIES_URL" ] && ! printf '%s' "$WEB_BASE" | grep -Eq '^https?://'; then
  HOST="$(uri_host "$PRINTER_URI")"
  WEB_BASE="http://$HOST"
fi

STATUS_URL="$WEB_BASE/webglue/rawcontent?c=Status"
if ! HTTP_RESPONSE="$(curl -sS --max-time 15 -w '\n%{http_code}' "$STATUS_URL")"; then
  echo "Druckerstatus konnte nicht abgerufen werden. Bitte Netzwerkverbindung und Weboberflaeche pruefen." >&2
  exit 1
fi

HTTP_STATUS="$(printf '%s\n' "$HTTP_RESPONSE" | tail -n 1)"
STATUS_JSON="$(printf '%s\n' "$HTTP_RESPONSE" | sed '$d')"

case "$HTTP_STATUS" in
  200)
    ;;
  404)
    echo "Drucker meldet HTTP-Error 404. Ggf. faehrt er noch hoch, bitte wiederholen." >&2
    exit 1
    ;;
  401|403)
    echo "Drucker meldet HTTP-Error $HTTP_STATUS. Die Weboberflaeche ist ggf. durch Authentifizierung geschuetzt; dieses Skript unterstuetzt derzeit keine Anmeldung." >&2
    exit 1
    ;;
  *)
    echo "Drucker meldet HTTP-Error $HTTP_STATUS beim Abruf der Statusseite." >&2
    exit 1
    ;;
esac

CAPTURED_AT="$(date -Iseconds)"

INFO_JSON="$(
  printf '%s\n' "$STATUS_JSON" | jq \
    --arg captured_at "$CAPTURED_AT" \
    --arg printer_model "$PRINTER_MODEL" \
    --arg printer_name "$PRINTER_NAME" \
    '
      def trim: gsub("^\\s+|\\s+$"; "");
      def digits_only: gsub("[^0-9]"; "");
      def supply_by_name($pattern):
        (.nodes.supplies // {})
        | to_entries
        | map(select(.key | test($pattern; "i")))
        | first
        | .value;

      (supply_by_name("^Black Toner$|Toner") // {}) as $toner |
      (supply_by_name("^Black Imaging Kit$|Imaging") // {}) as $imaging |
      {
        captured_at: $captured_at,
        printer: {
          name: ($printer_name // ""),
          model: ($printer_model // ""),
          serial_number: (.nodes.nodes.DeviceSerialNumberLxk.text.text // null)
        },
        toner: {
          name: ($toner.supplyName // $toner.text // null),
          part_number: (($toner.partNumber // "") | trim),
          serial_number: ($toner.serialNumber // null),
          serial_number_recycle_digits_only: (($toner.serialNumber // "") | trim | digits_only),
          level_percent: ($toner.percentFull // $toner.curlevel // null),
          pages_remaining: ($toner.pagesRemaining // null),
          status: ($toner.currentStatus // null)
        },
        imaging_kit: {
          name: ($imaging.supplyName // $imaging.text // null),
          part_number: (($imaging.partNumber // "") | trim),
          serial_number: ($imaging.serialNumber // null),
          level_percent: ($imaging.percentFull // $imaging.curlevel // null),
          pages_remaining: ($imaging.pagesRemaining // null),
          status: ($imaging.currentStatus // null)
        }
      }
    '
)"

printf '%s\n' "$INFO_JSON" > "$JSON_FILE"

printf '%s\n' "$INFO_JSON" | jq -r '
  def val($v): if $v == null or $v == "" then "-" else ($v | tostring) end;
  [
    "Abfragezeit: " + val(.captured_at),
    "Drucker: " + val(.printer.model),
    "Druckername: " + val(.printer.name),
    "Drucker-Seriennummer: " + val(.printer.serial_number),
    "Hinweis: Das Lexmark-Recyclingprogramm fragt diese Drucker-Seriennummer auch bei der Account-Registrierung ab.",
    "",
    "Schwarzer Toner: " + val(.toner.name),
    "Toner-Modell/Teilenummer: " + val(.toner.part_number),
    "Toner-Seriennummer: " + val(.toner.serial_number),
    "Toner-Seriennummer fuer Lexmark-Recycling (nur Ziffern): " + val(.toner.serial_number_recycle_digits_only),
    "Tonerstand: " + val(.toner.level_percent) + " %",
    "Restseiten: " + val(.toner.pages_remaining),
    "Tonerstatus: " + val(.toner.status),
    "",
    "Belichtungskit: " + val(.imaging_kit.name),
    "Belichtungskit-Teilenummer: " + val(.imaging_kit.part_number),
    "Belichtungskit-Seriennummer: " + val(.imaging_kit.serial_number),
    "Belichtungskit-Stand: " + val(.imaging_kit.level_percent) + " %",
    "Belichtungskit-Restseiten: " + val(.imaging_kit.pages_remaining),
    "Belichtungskit-Status: " + val(.imaging_kit.status)
  ] | .[]
' > "$TXT_FILE"

cat "$TXT_FILE"
printf '\nGespeichert: %s\nJSON: %s\n' "$TXT_FILE" "$JSON_FILE"
