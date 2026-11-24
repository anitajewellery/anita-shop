# walk run: v1.9 frosted top strip + name verdict
#!/usr/bin/env bash
# Scripted walk of the Anita Jewellery CUSTOMER app on the emulator.
# v1.7 checks: card names wrap to 2 lines (03-shop, Kiyang card), back-press step 06b, details-tab save rule (12-details-tab)
# No login in this app - the walk covers the full customer journey:
# home -> shop/search -> product -> first-booking details sheet -> saved/details tabs -> notification-tap simulation (v1.3) + gallery build (v1.4).
# Every tap is located fresh from a uiautomator dump; steps log what they see.
set -u
PKG=com.anitajewellery.shop
SHOTS="$GITHUB_WORKSPACE/shots"
mkdir -p "$SHOTS"
exec > >(tee -a "$SHOTS/walk.log") 2>&1

shot() { adb exec-out screencap -p > "$SHOTS/$1.png"; echo "shot: $1"; }
save_dump() { dump_ui; cp /tmp/ui.xml "$SHOTS/dump-$1.xml" 2>/dev/null; }

dump_ui() {
  adb shell uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1
  adb pull /data/local/tmp/ui.xml /tmp/ui.xml >/dev/null 2>&1
}

has_text() { dump_ui; grep -q "text=\"$1\"" /tmp/ui.xml; }

visible_texts() {
  python3 - <<'PY'
import re
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    print("(no dump)")
    raise SystemExit
ts = [m.group(1) for m in re.finditer(r'text="([^"]+)"', xml)]
print("visible texts:", " | ".join(ts[:40]))
PY
}

center_of() {
  python3 - "$1" "${2:-exact}" <<'PY'
import re, sys
want, mode = sys.argv[1], sys.argv[2]
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)
for m in re.finditer(r'text="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
    t = (m.group(1).replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
         .replace('&quot;', '"').replace('&apos;', "'"))
    if (mode == 'exact' and t == want) or (mode == 'contains' and want in t):
        print((int(m.group(2)) + int(m.group(4))) // 2, (int(m.group(3)) + int(m.group(5))) // 2)
        break
PY
}

tap_text() {
  dump_ui
  C=$(center_of "$1" "${2:-exact}")
  if [ -n "$C" ]; then echo "tap text '$1' at $C"; adb shell input tap $C; else echo "NOT FOUND (text): $1"; visible_texts; fi
  sleep 2
}

tap_field() {
  dump_ui
  C=$(python3 - "$1" <<'PY'
import re, sys
n = int(sys.argv[1])
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)
fields = [m for m in re.finditer(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)]
if n < len(fields):
    m = fields[n]
    print((int(m.group(1)) + int(m.group(3))) // 2, (int(m.group(2)) + int(m.group(4))) // 2)
PY
)
  if [ -n "$C" ]; then echo "tap field $1 at $C"; adb shell input tap $C; else echo "NOT FOUND (field): $1"; visible_texts; fi
  sleep 2
}

# Tap the node whose content-desc matches $1 (icon buttons like the heart).
tap_desc() {
  dump_ui
  C=$(python3 - "$1" <<'PY'
import re, sys
want = sys.argv[1]
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)
for m in re.finditer(r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
    if m.group(1) == want:
        print((int(m.group(2)) + int(m.group(4))) // 2, (int(m.group(3)) + int(m.group(5))) // 2)
        break
PY
)
  if [ -n "$C" ]; then echo "tap desc '$1' at $C"; adb shell input tap $C; else echo "NOT FOUND (desc): $1"; visible_texts; fi
  sleep 2
}

type() { adb shell input text "$1"; sleep 1; }
hide_keyboard() { adb shell input keyevent 111; sleep 1; }

ANR_STREAK=0
dismiss_system_dialogs() {
  for _ in 1 2 3; do
    dump_ui
    if grep -q "isn't responding" /tmp/ui.xml; then
      ANR_STREAK=$((ANR_STREAK+1))
      if [ "$ANR_STREAK" -ge 3 ] && grep -q "Pixel Launcher" /tmp/ui.xml; then
        echo "launcher ANR persists - tapping Close app (launcher restarts)"
        C=$(center_of "Close app")
        if [ -n "$C" ]; then adb shell input tap $C; fi
        ANR_STREAK=0
        sleep 5
      else
        echo "system ANR dialog present - tapping Wait (streak $ANR_STREAK)"
        C=$(center_of "Wait")
        if [ -n "$C" ]; then adb shell input tap $C; fi
        sleep 3
      fi
    else
      ANR_STREAK=0
      break
    fi
  done
}

echo "== install =="
adb install -r "$GITHUB_WORKSPACE/app.apk"
# v1.1 asks for the notification permission on first open (Android 13+);
# grant it up front so the walk is not blocked by the system dialog.
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null || true
adb shell am start -n $PKG/.MainActivity
sleep 6
dismiss_system_dialogs

echo "== wait for the catalogue (live feed) =="
LOADED=0
for i in $(seq 1 15); do
  dismiss_system_dialogs
  if has_text "The Collection"; then echo "catalogue loaded after ~$((i*4))s"; LOADED=1; break; fi
  echo "waiting for catalogue... $i"
  sleep 4
done
save_dump home
shot 01-home
if [ "$LOADED" != "1" ]; then echo "WALK ABORTED: catalogue never loaded"; visible_texts; exit 0; fi

echo "== home, scrolled =="
adb shell input swipe 540 1800 540 700 400
sleep 2
shot 02-home-scrolled
adb shell input swipe 540 700 540 1800 400
sleep 2

echo "== shop tab + search =="
tap_text "SHOP"
sleep 3
shot 03-shop
tap_field 0; type "Kullu"
hide_keyboard
sleep 2
save_dump search
shot 04-search
# Round-1 polish check: nonsense search -> the new empty state, then clear via the x button.
type "zzqq"
shot 04b-empty-search
tap_desc "Clear search"
sleep 1
if has_text "Kullu khokhor"; then echo "CLEAR OK - grid restored"; else echo "CLEAR MISS - grid not restored"; visible_texts; fi

echo "== open a product =="
tap_text "Kullu khokhor" contains
sleep 3
save_dump product
shot 05-product
# Round-1 polish check: scroll the product page to the related-pieces rail, then back to the top.
adb shell input swipe 540 1800 540 700 400; sleep 1
adb shell input swipe 540 1800 540 700 400; sleep 1
shot 05b-product-related
adb shell input swipe 540 700 540 1800 400; sleep 1
adb shell input swipe 540 700 540 1800 400; sleep 1

echo "== favourite this piece (heart) =="
tap_desc "Favourite"
shot 06-favourited
# Back-navigation check (v1.6): system back from a product must return to the
# shop grid, NOT exit the app. Then reopen the product for the booking steps.
adb shell input keyevent 4; sleep 2
save_dump backnav
shot 06b-back-from-product
tap_text "Kullu khokhor" contains
sleep 3

echo "== book: first-booking details sheet =="
tap_text "Book on WhatsApp"
sleep 3
save_dump sheet
shot 07-details-sheet
# Fill without ESC: ESC can reach the sheet dialog and dismiss it.
# BACK hides only the keyboard while it is open.
tap_field 0; type "Emulator%sTest"
adb shell input keyevent 4; sleep 1
tap_field 1; type 9876543210
adb shell input keyevent 4; sleep 1
tap_field 2; type "Imphal%sTest%sAddress"
adb shell input keyevent 4; sleep 2
save_dump filled
shot 08-details-filled
if has_text "Your details"; then echo "sheet still open after filling - good"; else echo "SHEET CLOSED EARLY"; fi
tap_text "Save & continue to WhatsApp"
sleep 5
shot 09-after-book-tap

echo "== return to the app (relaunch; WhatsApp/browser may be on top) =="
adb shell am start -n $PKG/.MainActivity
sleep 4
dismiss_system_dialogs
# The relaunched task may still show the product page (no dock there):
# one BACK returns to the tabs - only when the product page is really showing.
if has_text "Book on WhatsApp"; then echo "on product page - BACK to tabs"; adb shell input keyevent 4; sleep 2; fi
save_dump back-home
shot 10-back

echo "== saved tab (the favourited piece should be listed) =="
tap_text "SAVED"
sleep 2
save_dump saved
shot 11-saved

echo "== details tab (saved details should be pre-filled) =="
tap_text "DETAILS"
sleep 2
save_dump details
shot 12-details-tab

echo "== notification tap: launch with a product code extra (what an FCM tap delivers) =="
adb shell am force-stop $PKG
sleep 1
adb shell am start -n $PKG/.MainActivity --es code AJ-710091
sleep 5
save_dump notif-tap
shot 13-notif-tap-product
if has_text "Book on WhatsApp"; then echo "NOTIF TAP OK - product page opened from the code extra"; else echo "NOTIF TAP MISS - product page not shown"; visible_texts; fi

echo "== walk done =="
ls -la "$SHOTS"
