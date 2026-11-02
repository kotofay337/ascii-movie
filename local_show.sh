#!/usr/bin/env bash
# =============================================================================
# play-ascii-movie.sh — ASCII movie player for Linux console
# =============================================================================
# Requirements: bash 4+, coreutils (stty, sleep). No external deps.
#
# Usage:
#   ./play-ascii-movie.sh
#   ./play-ascii-movie.sh movie.txt
#   ./play-ascii-movie.sh -f movie.txt -s 20
# =============================================================================

set -u
shopt -s checkwinsize

# ---- defaults --------------------------------------------------------------
FPS=15
MOVIE_FILE=""

# ---- args ------------------------------------------------------------------
while (( $# > 0 )); do
    case "$1" in
        -f|--file)
            [[ $# -ge 2 ]] || { echo "Missing argument for $1" >&2; exit 1; }
            MOVIE_FILE="$2"; shift 2 ;;
        -s|--fps|--speed)
            [[ $# -ge 2 ]] || { echo "Missing argument for $1" >&2; exit 1; }
            FPS="$2"; shift 2 ;;
        -h|--help)
            cat <<'HELP'
Usage: play-ascii-movie.sh [-f MOVIE] [-s FPS]

  -f, --file MOVIE    Path to movie file (default: sw1.txt next to script)
  -s, --fps FPS       Playback speed, frames per second (default: 15)
  -h, --help          Show this help
HELP
            exit 0 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$MOVIE_FILE" ]]; then
                MOVIE_FILE="$1"; shift
            else
                echo "Unexpected argument: $1" >&2; exit 1
            fi ;;
    esac
done

[[ "$FPS" =~ ^[0-9]+$ ]] || FPS=15
(( FPS < 1 )) && FPS=1
(( FPS > 60 )) && FPS=60

# ---- resolve movie file ----------------------------------------------------
if [[ -z "$MOVIE_FILE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    MOVIE_FILE="$SCRIPT_DIR/sw1.txt"
fi

if [[ ! -f "$MOVIE_FILE" ]]; then
    printf 'Movie file not found: %s\n' "$MOVIE_FILE" >&2
    printf 'Usage: %s [-f MOVIE] [-s FPS]\n' "$0" >&2
    exit 1
fi

# ---- terminal save / restore ----------------------------------------------
SAVED_STTY=$(stty -g 2>/dev/null) || SAVED_STTY=""

cleanup() {
    printf '\033[?25h'                 # show cursor
    printf '\033[0m'                   # reset SGR
    [[ -n "$SAVED_STTY" ]] && stty "$SAVED_STTY" 2>/dev/null || true
    printf '\n'
}
trap cleanup EXIT INT TERM

# ---- cached terminal size --------------------------------------------------
_CACHED_LINES=0
_CACHED_COLS=0
_CACHE_AGE=0
_CACHE_MAX=60

get_size() {
    if (( _CACHED_LINES == 0 || _CACHE_AGE >= _CACHE_MAX )); then
        local sz
        sz=$(stty size 2>/dev/null) || sz="24 80"
        local l="${sz% *}"
        local c="${sz#* }"
        [[ "$l" =~ ^[0-9]+$ ]] || l=24
        [[ "$c" =~ ^[0-9]+$ ]] || c=80
        (( l < 5  )) && l=24
        (( c < 20 )) && c=80
        _CACHED_LINES=$l
        _CACHED_COLS=$c
        _CACHE_AGE=0
    fi
    _CACHE_AGE=$(( _CACHE_AGE + 1 ))
    T_LINES=$_CACHED_LINES
    T_COLS=$_CACHED_COLS
}

# ---- pass 1: total ticks ---------------------------------------------------
count_ticks() {
    local file=$1
    local total=0 n=0 line head trimmed v
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( n % 14 == 0 )); then
            head="${line:0:3}"
            head="${head#"${head%%[![:space:]]*}"}"
            head="${head%"${head##*[![:space:]]}"}"
            if [[ "$head" =~ ^[0-9]{1,3}$ ]]; then
                v=$(( 10#$head ))
                if (( v >= 1 && v <= 999 )); then
                    trimmed="${line#"${line%%[![:space:]]*}"}"
                    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
                    if (( ${#trimmed} <= 3 )); then
                        total=$(( total + v ))
                    fi
                fi
            fi
        fi
        n=$(( n + 1 ))
    done < "$file"
    echo "$total"
}

# ---- draw one frame --------------------------------------------------------
draw_frame() {
    local cur_pos=$1 total=$2
    shift 2
    local -a rows=("$@")
    local mh=13

    get_size
    local cols=$T_COLS lines=$T_LINES

    local off_x=$(( (cols - 67) / 2 ))
    (( off_x < 0 )) && off_x=0
    local off_y=$(( (lines - 1 - mh) / 2 ))
    (( off_y < 0 )) && off_y=0
    local bar_y=$(( lines - 1 ))

    if (( ${#rows[@]} > 0 )); then
        local i=0 row y max_len text
        for row in "${rows[@]}"; do
            y=$(( off_y + i ))
            if (( y >= 0 && y < lines )); then
                max_len=$(( cols - off_x ))
                if (( max_len > 0 )); then
                    text="$row"
                    (( ${#text} > max_len )) && text="${text:0:max_len}"
                    printf '\033[%d;%dH%s' $(( y + 1 )) $(( off_x + 1 )) "$text"
                fi
            fi
            i=$(( i + 1 ))
        done
    fi

    # timebar
    local bar_width=$(( cols - 4 ))
    (( bar_width < 10 )) && bar_width=10
    local bar_text
    printf -v bar_text '%*s' "$bar_width" ''
    bar_text="${bar_text// /.}"
    local denom=$(( total - 1 ))
    (( denom < 1 )) && denom=1
    local pos=$(( cur_pos * (bar_width - 1) / denom ))
    (( pos < 0 ))           && pos=0
    (( pos >= bar_width ))  && pos=$(( bar_width - 1 ))
    bar_text="${bar_text:0:$pos}o${bar_text:$(( pos + 1 ))}"
    bar_text=" <${bar_text}>"
    (( ${#bar_text} > cols )) && bar_text="${bar_text:0:$cols}"
    printf '\033[%d;1H%s' $(( bar_y + 1 )) "$bar_text"
}

# ---- main ------------------------------------------------------------------
total_ticks=$(count_ticks "$MOVIE_FILE")
if (( total_ticks == 0 )); then
    printf 'No frames parsed. Wrong file format?\n' >&2
    exit 1
fi

printf '\033[?25l'
printf '\033[2J\033[H'
printf 'Movie : %s\n'  "$MOVIE_FILE"
printf 'Ticks : %d\n'  "$total_ticks"
printf 'FPS   : %d\n'  "$FPS"
printf 'Starting in 2s... (Ctrl+C to stop)\n'
sleep 2
printf '\033[2J\033[H'

cur_pos=0
frame_delay=0
declare -a frame_rows
row_count=0
in_frame=0
counter=0

play_pending() {
    (( in_frame )) || return 0
    cur_pos=$(( cur_pos + frame_delay ))
    if (( ${#frame_rows[@]} > 0 )); then
        draw_frame "$cur_pos" "$total_ticks" "${frame_rows[@]}"
    fi
    if (( frame_delay > 0 )); then
        local ms=$(( 1000 * frame_delay / FPS ))
        if (( ms > 0 )); then
            local s=$(( ms / 1000 ))
            local r=$(( ms % 1000 ))
            sleep "${s}.$(printf '%03d' "$r")"
        fi
    fi
    return 0
}

# ---- pass 2: playback ------------------------------------------------------
while IFS= read -r line || [[ -n "$line" ]]; do
    delay=-1
    if (( counter % 14 == 0 )); then
        h="${line:0:3}"
        h="${h#"${h%%[![:space:]]*}"}"
        h="${h%"${h##*[![:space:]]}"}"
        if [[ "$h" =~ ^[0-9]{1,3}$ ]]; then
            delay=$(( 10#$h ))
        fi
    fi

    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    if (( ${#trimmed} <= 3 && delay >= 1 && delay <= 999 )); then
        play_pending
        frame_delay=$delay
        frame_rows=()
        row_count=0
        in_frame=1
    elif (( in_frame && row_count < 13 )); then
        row="${line%"${line##*[![:space:]]}"}"
        local_pad=$(( 67 - ${#row} ))
        if (( local_pad > 0 )); then
            printf -v sp '%*s' "$local_pad" ''
            row+="$sp"
        fi
        frame_rows+=("$row")
        row_count=$(( row_count + 1 ))
    fi

    counter=$(( counter + 1 ))
done < "$MOVIE_FILE"

play_pending

# ---- done ------------------------------------------------------------------
get_size
printf '\033[%d;1H' "$T_LINES"
printf '\n=== The End ===\n'
