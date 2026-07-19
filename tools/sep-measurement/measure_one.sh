#!/bin/bash
# measure_one.sh <rowY> <value> <exportName>
# Sets one SEP slider (by typed value), exports the ramp, resets to 0.
# Focus-guarded at every keystroke batch; exits 1 if focus can't be held.
set -u
SP="/private/tmp/claude-501/-Users-arthursoares-Github-framer/80576de9-4618-4bee-a0e3-43c857521e54/scratchpad"
ROWY="$1"; VALUE="$2"; NAME="$3"
FIELD_X=1454

guard() {
  for i in 1 2 3 4 5 6; do
    osascript -e 'tell application "Silver Efex Pro 3" to activate' >/dev/null
    sleep 1.2
    F=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
    [ "$F" = "Silver Efex Pro 3" ] && return 0
    sleep 2.5
  done
  echo "FOCUS-LOST"; return 1
}

set_value() {  # $1 = value
  guard || return 1
  "$SP/uiclick" click $FIELD_X "$ROWY" 2
  sleep 0.8
  guard || return 1
  "$SP/uiclick" typenum "$1"
  sleep 0.3
  "$SP/uiclick" key 36
  sleep 1.2
}

set_value "$VALUE" || exit 1

guard || exit 1
osascript -e 'tell application "System Events" to tell process "Silver Efex Pro 3" to click menu item "Save Image as..." of menu "File" of menu bar 1' >/dev/null
sleep 2.5
guard || exit 1
"$SP/uiclick" type "$NAME"
sleep 0.4
guard || exit 1
"$SP/uiclick" key 36
sleep 4

set_value "0" || exit 1

if [ -f "$SP/$NAME.tiff" ]; then echo "OK $NAME"; else echo "MISSING $NAME"; exit 1; fi
