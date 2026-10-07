# kaiseki's look for ZFSBootMenu's two main screens (boot environments, snapshots). Sourced from /etc/profile in
# the image, after ZFSBootMenu's own libraries, so the functions here replace its draw_be and draw_snapshots.
# The keys and what they do are ZFSBootMenu's; only the presentation changes: no borders or preview pane, a centred
# column under the wordmark, kernel version and date on each row, key hints on one line at the bottom, and a
# countdown bar before the default boot environment starts. Everything else (kernels, pool status, help, logs)
# keeps ZFSBootMenu's own layout in kaiseki's colours.
# Colours are the 16 console colours, remapped to Tokyo Night by the early-setup hook. Widths are counted by hand:
# this runs in the C locale, where ${#text} counts the bytes of a non-ASCII character.

KZ_TTY=${control_term:-/dev/tty}
KZ_D=$'\033[90m'; KZ_W=$'\033[97m'; KZ_T=$'\033[37m'; KZ_B=$'\033[34m'; KZ_Y=$'\033[33m'; KZ_N=$'\033[0m'
KZ_LW=60                                            # width of the list column
KZ_DOT=$'\xc2\xb7'                                   # the separator between a row's two details (two bytes, one column)

kz_geom() {      # $1: be | snap
  local r c; read -r r c < <(stty size < "${KZ_TTY}" 2>/dev/null); KZ_ROWS=${r:-50}; KZ_COLS=${c:-160}
  KZ_FW=$(( KZ_LW + 2 ))                             # fzf's width: the list column and its two-column gutter
  KZ_FL=$(( (KZ_COLS - KZ_FW) / 2 )); (( KZ_FL < 0 )) && KZ_FL=0
  if [ "$1" = snap ]; then KZ_LOGO=small; KZ_LOGO_ROW=$(( KZ_ROWS * 20 / 100 )); KZ_LOGO_ROWS=5
  else KZ_LOGO=large; KZ_LOGO_ROW=$(( KZ_ROWS * 32 / 100 )); KZ_LOGO_ROWS=7; fi
  (( KZ_LOGO_ROW < 1 )) && KZ_LOGO_ROW=1
  KZ_SUB_ROW=$(( KZ_LOGO_ROW + KZ_LOGO_ROWS + 1 ))
  if [ "$1" = snap ]; then KZ_TOP=$(( KZ_SUB_ROW + 6 )); else KZ_TOP=$(( KZ_SUB_ROW + 4 )); fi   # last row above the list
  KZ_BOTTOM=4                                       # rows left free under fzf: the hints line is drawn there
  KZ_HINT_ROW=$(( KZ_ROWS - 2 ))
}
kz_at() { printf '\033[%d;%dH%s' "$1" "$2" "$3"; }
kz_centre() { kz_at "$1" $(( (KZ_COLS - $3) / 2 + 1 )) "$2"; }     # row, text, its width in columns
kz_image() {     # the rendered wordmark onto the framebuffer; fails where that cannot be done
  local img=/usr/share/kaiseki/logo-$KZ_LOGO.bgra sys=/sys/class/graphics/fb0 lw lh vw vh stride cell x0 y0 r
  [ -r "$img" ] && [ -w /dev/fb0 ] && read -r lw lh < "${img%.bgra}.dim" || return 1
  IFS=, read -r vw vh < "$sys/virtual_size" || return 1; stride=$(cat "$sys/stride")
  [ "$(cat "$sys/bits_per_pixel")" = 32 ] && (( lw <= vw )) || return 1
  cell=$(( vh / KZ_ROWS )); x0=$(( (vw - lw) / 2 )); y0=$(( (KZ_LOGO_ROW - 1) * cell + (KZ_LOGO_ROWS * cell - lh) / 2 )); (( y0 >= 0 )) || return 1
  for (( r = 0; r < lh; r++ )); do
    dd if="$img" of=/dev/fb0 bs=65536 iflag=skip_bytes,count_bytes oflag=seek_bytes conv=notrunc status=none \
       skip=$(( r * lw * 4 )) count=$(( lw * 4 )) seek=$(( (y0 + r) * stride + x0 * 4 )) 2>/dev/null || return 1
  done
}
# What surrounds the list: wordmark, subtitle and (snapshots) column titles. Called once fzf has drawn its first
# frame, and for the countdown. $1: be | snap, $2: subtitle
kz_chrome() {
  local mode=$1 sub=$2
  if [ "$mode" = countdown ]; then kz_geom be; else kz_geom "$mode"; fi
  {
    printf '\0337'
    kz_image || kz_centre $(( KZ_LOGO_ROW + KZ_LOGO_ROWS / 2 )) $'\033[32mk a i s e k i\033[0m' 13
    kz_centre "$KZ_SUB_ROW" "${KZ_T}${sub}${KZ_N}" "${#sub}"
    if [ "$mode" = snap ]; then
      local x=$(( KZ_FL + 3 )) rule; printf -v rule '%*s' "$KZ_LW" ''
      kz_at $(( KZ_TOP - 1 )) "$x" "${KZ_D}NAME$(printf '%*s' $(( KZ_LW - 4 - 14 )) '')USED ${KZ_DOT} CREATED${KZ_N}"
      kz_at "$KZ_TOP" "$x" "${KZ_D}${rule// /-}${KZ_N}"
      kz_hints "$KZ_HINT_ROW" enter duplicate ^x "clone & promote" ^c clone ^d diff ^n "new snapshot" ^r "roll back" esc back
    elif [ "$mode" = countdown ]; then kz_hints "$KZ_HINT_ROW" enter "boot now" esc menu
    else kz_hints "$KZ_HINT_ROW" enter boot e "edit cmdline" ^s snapshots ^d "set default" ^p "pool status" ^r recovery
    fi
    printf '\0338'
  } > "${KZ_TTY}"
}
kz_hints() {     # row, then "key label" pairs -> one line centred on the screen, keys bright, labels dim
  local row=$1 out= plain= k l; shift
  while (( $# )); do k=$1; l=$2; shift 2; out+="${KZ_W}${k}${KZ_N} ${KZ_D}${l}${KZ_N}   "; plain+="$k $l   "; done
  printf '\033[%d;1H\033[2K' "$row"; kz_centre "$row" "$out" $(( ${#plain} - 3 ))
}
kz_row() {       # left text, right text -> one list row of width KZ_LW; the right text stays dim on the current row
  local plain=${2//$KZ_DOT/.} pad; pad=$(( KZ_LW - ${#1} - ${#plain} )); (( pad < 1 )) && pad=1
  printf '%s%*s%s' "$1" "$pad" '' "${2:+${KZ_D}$2${KZ_N}}"
}
kz_track() {     # row, column: the countdown bar's empty track, a dark strip painted on the framebuffer
  local sys=/sys/class/graphics/fb0 vw vh stride cw ch px line r y0 x0
  [ -w /dev/fb0 ] && IFS=, read -r vw vh < "$sys/virtual_size" && [ "$(cat "$sys/bits_per_pixel")" = 32 ] || return 1
  stride=$(cat "$sys/stride"); cw=$(( vw / KZ_COLS )); ch=$(( vh / KZ_ROWS ))
  printf -v line '%*s' $(( KZ_LW * cw )) ''; px=$'\x3b\x28\x24\xff'; line=${line// /$px}
  y0=$(( ($1 - 1) * ch )); x0=$(( ($2 - 1) * cw ))
  for (( r = 0; r < ch; r++ )); do
    printf '%s' "$line" | dd of=/dev/fb0 bs=65536 oflag=seek_bytes conv=notrunc status=none seek=$(( (y0 + r) * stride + x0 * 4 )) 2>/dev/null || return 1
  done
}
kz_fzf() {       # the options both screens share; the caller adds its own
  printf '\033[0m\033[2J\033[H' > "${KZ_TTY}"       # fzf never paints its margins: wipe the previous screen's wordmark and text
  ${FUZZYSEL} --ansi --no-clear --cycle --color=16 --layout=reverse-list --no-tac --no-input --info=hidden --no-separator --no-scrollbar \
    --border=none --no-preview --pointer ' ' --marker '*' --gap 1 --gap-line ' ' --delimiter $'\t' --with-nth 2 \
    --color 'fg:8,bg:-1,current-fg:15,current-bg:-1,hl:8,hl+:15,gutter:-1,header:8,marker:3,pointer:15' \
    --margin "${KZ_TOP},${KZ_FL},${KZ_BOTTOM},${KZ_FL}" "$@"
}
kz_kernel() { local k; IFS=$'\t' read -r _ k _ <<< "$(select_kernel "$1" 2>/dev/null)"; k=${k##*/}; k=${k#vmlinuz-}; [[ $k =~ ^[0-9]+(\.[0-9]+)* ]] && echo "${BASH_REMATCH[0]}" || echo "-"; }

# ---- boot environments ---------------------------------------------------------------------------------------------
kz_be_lines() {  # $1: file of boot environments -> "name<TAB>display" lines, default first
  local be right n=0
  while read -r be; do
    [ -n "$be" ] || continue
    if [ "$be" = "$BOOTFS" ]; then right="$(kz_kernel "$be") ${KZ_DOT} default"
    else right="$(kz_kernel "$be") ${KZ_DOT} $(date -d "@$(zfs get -Hp -o value creation "$be")" +%Y-%m-%d 2>/dev/null)"; fi
    printf '%s\t%s\n' "$be" "$(kz_row "$be" "$right")"
  done < <( { grep -Fx -- "$BOOTFS" "$1"; grep -Fxv -- "$BOOTFS" "$1" | tac; } 2>/dev/null )
  printf '%s\t%s\n' "@recovery" "$(kz_row "Recovery shell" "")" "@firmware" "$(kz_row "UEFI firmware settings" "")"
}
kz_countdown() { # once per start: the same screen with a bar; returns 0 to boot the default, 1 to open the menu
  local secs=${KAISEKI_ZBM_TIMEOUT:-10} lines=$1 n=0 key bar rest x row track start total now
  [ -n "$BOOTFS" ] && (( secs > 0 )) && [ ! -e "${BASE}/kaiseki-countdown-done" ] || return 1
  : > "${BASE}/kaiseki-countdown-done"
  kz_geom be; x=$(( KZ_FL + 3 ))
  {
    printf '\033[2J\033[?25l'
    while IFS=$'\t' read -r _ row; do   # the rows where fzf will draw them: first one current
      if (( n == 0 )); then kz_at $(( KZ_TOP + 1 + n * 2 )) "$x" "${KZ_W}${row}${KZ_N}"; else kz_at $(( KZ_TOP + 1 + n * 2 )) "$x" "${KZ_D}${row}${KZ_N}"; fi
      n=$(( n + 1 ))
    done <<< "$lines"
  } > "${KZ_TTY}"
  kz_chrome countdown "ZFS boot environments"
  row=$(( KZ_TOP + 1 + n * 2 + 1 ))
  if kz_track "$row" "$x"; then track=; else track=:; fi   # without a framebuffer the track is a row of colons
  kz_now() { local t=${EPOCHREALTIME/[.,]/}; echo "${t:-$(( SECONDS * 1000000 ))}"; }   # microseconds
  start=$(kz_now); total=$(( secs * 1000000 ))
  while now=$(kz_now); (( now - start < total )); do    # by the clock: a key wait that returns early must not shorten it
    printf -v bar '%*s' $(( KZ_LW * (now - start) / total )) ''; printf -v rest '%*s' $(( KZ_LW - ${#bar} )) ''
    { kz_at "$row" "$x" $'\033[44m'"${bar}${KZ_N}${track:+${KZ_D}${rest// /:}${KZ_N}}"
      kz_at $(( row + 2 )) "$x" "${KZ_D}Booting ${BOOTFS} in $(( secs - (now - start) / 1000000 ))s ${KZ_N}"; } > "${KZ_TTY}"
    if IFS= read -rsn1 -t 0.25 key < "${KZ_TTY}"; then
      [ -z "$key" ] && return 0                     # Enter: boot now
      while IFS= read -rsn1 -t 0.05 _ < "${KZ_TTY}"; do :; done   # the rest of an escape sequence, if any
      return 1
    fi
    (( $(kz_now) - now < 200000 )) && sleep 0.2
  done
  return 0
}
draw_be() {
  local env=$1 lines selected key be expects
  [ -r "${env}" ] || { zerror "environment file ${env} is missing"; return 130; }
  kz_geom be; lines=$(kz_be_lines "${env}")
  if kz_countdown "$lines"; then echo "enter,${BOOTFS}"; return 0; fi
  kz_geom be
  expects="--expect=alt-e,alt-k,alt-d,alt-s,alt-c,alt-r,alt-p,alt-w,alt-j,alt-o,alt-x,alt-t,right"
  # shellcheck disable=SC2086
  selected=$(kz_fzf -0 ${expects} ${expects//alt-/ctrl-} ${expects//alt-/ctrl-alt-} --expect=e \
      --bind "start:execute-silent(/libexec/kaiseki-chrome be 'ZFS boot environments')" <<< "$lines") || return 1
  { read -r key; IFS=$'\t' read -r be _; } <<< "${selected}"
  case "${be}" in     # the two entries that are not boot environments act on Enter only; other keys apply to the default
    @recovery) [ -z "${key}" ] && { echo "mod-r,${BOOTFS}"; return 0; }; be=${BOOTFS} ;;
    @firmware) [ -z "${key}" ] && { tput clear > "${KZ_TTY}"; /bin/firmware-setup > "${KZ_TTY}" 2>&1; sleep 3; tput clear > "${KZ_TTY}"; return 1; }; be=${BOOTFS} ;;
  esac
  [ "${key}" = e ] && key=ctrl-e
  selected=$(printf '%s\n%s\n' "${key}" "${be}" | csv_cat)
  echo "${selected}"; zdebug "selected: ${selected}"
  return 0        # (zdebug's own status is non-zero below debug log level, and the caller reads ours as "cancelled")
}

# ---- snapshots -----------------------------------------------------------------------------------------------------
kz_when() { local now; now=$(date +%s); if (( now - $1 < 86400 )) && [ "$(date -d "@$1" +%d)" = "$(date +%d)" ]; then date -d "@$1" +%H:%M; else date -d "@$1" '+%b %d'; fi; }
draw_snapshots() {
  local benv=$1 sort_key lines= name used created right selected expects warn
  [ -n "${benv}" ] || { zerror "benv is undefined"; return 130; }
  sort_key=$(get_sort_key); kz_geom snap
  while IFS=$'\t' read -r name used created; do
    [ -n "$name" ] || continue
    right="${used} ${KZ_DOT} $(kz_when "$created")"
    lines+="${name}"$'\t'"$(kz_row "@${name#*@}" "$right")"$'\n'
  done < <(zfs list -t snapshot -Hp -o name,used,creation -S "${sort_key}" "${benv}" 2>/dev/null |
           awk -F'\t' '{ u = $2; s = "BKMGT"; i = 1; while (u >= 1024 && i < 5) { u /= 1024; i++ }; printf "%s\t%.3g%s\t%s\n", $1, u, substr(s, i, 1), $3 }')
  [ -n "$lines" ] || lines="No snapshots available"$'\t'"$(kz_row "No snapshots yet" "")"$'\n'
  warn="${KZ_Y}!${KZ_N} ${KZ_D}Rolling back destroys newer snapshots. Clone to a new"$'\n'"  boot environment instead.${KZ_N}"
  expects="--expect=alt-x,alt-c,alt-j,alt-o,alt-n,alt-r,left,right"
  # shellcheck disable=SC2086
  selected=$(HELP_SECTION=snapshot-management kz_fzf --multi 2 ${expects} ${expects//alt-/ctrl-} ${expects//alt-/ctrl-alt-} \
      --bind "alt-d:execute[ /libexec/zfsbootmenu-diff {+1} ]" --bind "ctrl-d:execute[ /libexec/zfsbootmenu-diff {+1} ]" \
      --header "${warn}" \
      --bind "start:execute-silent(/libexec/kaiseki-chrome snap 'snapshots of ${benv}')" <<< "${lines%$'\n'}") || return 1
  selected=$(cut -f1 <<< "${selected}" | csv_cat)
  echo "${selected}"; zdebug "selected: ${selected}"
  return 0        # (zdebug's own status is non-zero below debug log level, and the caller reads ours as "cancelled")
}
