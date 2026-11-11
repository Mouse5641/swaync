#!/bin/bash
# swaync (run-on: action): при кліку на сповіщення перейти до вікна-джерела.
# Якщо вікна-джерела немає (системні сповіщення: notify-send, Bluetooth,
# яскравість, Waybar Lyrics тощо) — нічого не робить.

LOG="${XDG_RUNTIME_DIR:-/tmp}/swaync-focus.log"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }

app="${SWAYNC_APP_NAME:-}"
entry="${SWAYNC_DESKTOP_ENTRY:-}"
log "action app='$app' entry='$entry' summary='${SWAYNC_SUMMARY:-}'"

# Офісний чат (lchat): вікно може бути відкладене на special:lchat,
# тому показуємо його через lchat_toggle з ~/.config/hypr/lchat.lua
if [ "${app,,}" = "lchat" ]; then
    log "lchat: показую накладку чату"
    [ -n "${SWAYNC_FOCUS_DRY_RUN:-}" ] && exit 0
    hyprctl eval 'lchat_toggle()' >/dev/null 2>&1
    exit 0
fi

# Явно службові джерела — пропускаємо одразу
case "${app,,}" in
    notify-send|libnotify|waybar|"waybar lyrics"|hypridle|hyprland|swaync|bluetooth|network*|brightness*|volume*|system*)
        log "skip: службове джерело"
        exit 0
        ;;
esac

# Ключі для пошуку вікна: desktop-entry та варіанти app-name (усе в нижньому регістрі)
keys=()
add_key() {
    local k="${1,,}"
    [ "${#k}" -lt 3 ] && return
    case "$k" in desktop|browser|app|application|window) return ;; esac
    keys+=("$k")
}
add_key "$entry"
add_key "${entry%.desktop}"
add_key "$app"
add_key "${app// /}"
add_key "${app// /-}"
add_key "${app%% *}"

if [ "${#keys[@]}" -eq 0 ]; then
    log "skip: немає ключів"
    exit 0
fi

keys_json=$(printf '%s\n' "${keys[@]}" | jq -R . | jq -sc 'unique')

# Шукаємо вікно: точний збіг класу (3) > клас містить ключ (2) > ключ містить клас (1).
# Серед рівних — те, що було у фокусі найпізніше.
addr=$(hyprctl clients -j | jq -r --argjson ks "$keys_json" '
    [ .[]
      | select(.mapped and .class != "")
      | (.class | ascii_downcase) as $cl
      | (.initialClass | ascii_downcase) as $il
      | ([ $ks[] | . as $k
           | if ($cl == $k or $il == $k) then 3
             elif (($cl | contains($k)) or ($il | contains($k))) then 2
             elif (($cl | length) >= 3 and (($k | contains($cl)) or ($k | contains($il)))) then 1
             else 0 end
         ] | max) as $score
      | select($score > 0)
      | { address, score: $score, fh: .focusHistoryID, class }
    ]
    | sort_by(-.score, .fh)
    | .[0] // empty
    | "\(.address) \(.class) \(.score)"')

if [ -z "$addr" ]; then
    log "skip: вікно для ${keys_json} не знайдено"
    exit 0
fi

read -r address class score <<< "$addr"
log "focus: $class ($address, score $score)"
[ -n "${SWAYNC_FOCUS_DRY_RUN:-}" ] && exit 0   # для тестування без перемикання
hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
