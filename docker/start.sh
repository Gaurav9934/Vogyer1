#!/bin/bash
set -euo pipefail

#############################################
# VOYAGER 1 — 24/7 YouTube live stream
# "1 LIGHT-DAY FROM EARTH — Journey Into Interstellar Space"
#
# Facts (NASA / JPL, Nov 2026):
#   Milestone      : Voyager 1 reached ONE LIGHT-DAY from Earth on
#                    2026-11-18 at 10:16:07 UTC (5:16:07 AM EST) — the
#                    first spacecraft ever to do so.
#   Light-day      : 25,902,068,371 km (about 16.1 billion miles)
#   Signal delay   : ~24 h one way, ~48 h round trip
#   Launch         : 1977-09-05 (Kennedy Space Center)
#   Interstellar   : since August 2012
#   Speed          : ~17 km/s (~38,000 mph) relative to the Sun
#   Instruments    : 2 of 10 still on (magnetometer, plasma wave);
#                    LECP switched off 2026-04-17 to save power
#   Power          : RTG loses ~4 W per year; transmitter ~22 W; ~160 bps
#
# LIVE NUMBERS: the "distance now" on screen is a MODEL (labelled est.):
#   Voyager's heliocentric distance grows at the Sun-relative speed, and
#   Earth's real orbital position is subtracted every second. It is
#   calibrated to land exactly on 1 light-day at the NASA milestone time,
#   and it reproduces NASA's May 2024 figure (162.7 AU) to within 0.1 pct.
#   Recalibrate any time via the VOY_* variables below.
#
# NOTE: drawtext treats the percent sign as an escape character, so this
# script writes "percent" / "PCT" instead of the symbol everywhere on screen.
#############################################

#############################################
# Validate Environment Variables
#############################################
if [ -z "${VIDEO_URL:-}" ]; then
    echo "ERROR: VIDEO_URL is not set"
    echo "One or more Voyager / deep-space video clips, comma-separated:"
    echo "url1,url2,url3. A static image (jpg/png) is also accepted as a"
    echo "'slide' and will be shown for IMAGE_SLIDE_SECONDS."
    exit 1
fi
if [ -z "${YOUTUBE_STREAM_KEY:-}" ]; then
    echo "ERROR: YOUTUBE_STREAM_KEY is not set"
    exit 1
fi
if [ -z "${AUDIO_URL:-}" ]; then
    echo "ERROR: AUDIO_URL is not set"
    echo "Background music/ambience track(s), comma-separated for multiple:"
    echo "url1,url2,url3"
    exit 1
fi

# Subscriber count + live viewer count are optional.
SHOW_STATS=true
if [ -z "${YOUTUBE_API_KEY:-}" ] || [ -z "${YOUTUBE_CHANNEL_ID:-}" ]; then
    echo "NOTICE: YOUTUBE_API_KEY / YOUTUBE_CHANNEL_ID not set — subscriber/viewer stats will be hidden."
    SHOW_STATS=false
fi

# ---------------------------------------------------------------
# Voyager 1 mission data (all overridable).
# Sources: NASA / JPL news release (Nov 19, 2026), NASA Science
# "What Is a Light-Day", NPR, JPL instrument updates (Apr 2026).
# ---------------------------------------------------------------
VOY_LIGHTDAY_UTC="${VOY_LIGHTDAY_UTC:-2026-11-18 10:16:07}"
VOY_LAUNCH_UTC="${VOY_LAUNCH_UTC:-1977-09-05 12:56:00}"
VOY_LIGHTDAY_KM="${VOY_LIGHTDAY_KM:-25902068371}"
VOY_SPEED_KMS="${VOY_SPEED_KMS:-16.95}"
# Voyager 1 direction in ecliptic coordinates (deg) — used only for the
# Earth-orbit correction in the distance model.
VOY_ECL_LON="${VOY_ECL_LON:-256.3}"
VOY_ECL_LAT="${VOY_ECL_LAT:-35.1}"
VOY_INSTR_ON="${VOY_INSTR_ON:-2}"
VOY_INSTR_TOTAL="${VOY_INSTR_TOTAL:-10}"
VOY_EVENTS_FILE="${VOY_EVENTS_FILE:-voyager_events.txt}"

LD_EPOCH_S=$(date -u -d "$VOY_LIGHTDAY_UTC" +%s)
LAUNCH_EPOCH_S=$(date -u -d "$VOY_LAUNCH_UTC" +%s)

fmt_int() {
    echo "$1" | rev | sed 's/\(...\)/\1,/g' | rev | sed 's/^,//'
}

# Human-readable strings derived once from the values above.
LD_DATE_SHORT=$(date -u -d "@$LD_EPOCH_S" +'%b %-d')
LD_UTC_HM=$(date -u -d "@$LD_EPOCH_S" +'%H:%M')
LD_IST_12=$(TZ=Asia/Kolkata date -d "@$LD_EPOCH_S" +'%-I:%M %p')
LD_EST_12=$(TZ=America/New_York date -d "@$LD_EPOCH_S" +'%-I:%M %p')
LD_UTC_FULL=$(date -u -d "@$LD_EPOCH_S" +'%b %d · %H:%M')
LD_IST_FULL=$(TZ=Asia/Kolkata date -d "@$LD_EPOCH_S" +'%b %d · %I:%M %p')
LD_EST_FULL=$(TZ=America/New_York date -d "@$LD_EPOCH_S" +'%b %d · %I:%M %p')
LD_HEARD_FULL=$(date -u -d "@$((LD_EPOCH_S + 86400))" +'%b %d · ~%H:%M UTC')
LD_KM_B=$(awk -v k="$VOY_LIGHTDAY_KM" 'BEGIN{printf "%.1f", k/1e9}')
LD_MI_B=$(awk -v k="$VOY_LIGHTDAY_KM" 'BEGIN{printf "%.1f", k*0.621371/1e9}')
LD_AU=$(awk -v k="$VOY_LIGHTDAY_KM" 'BEGIN{printf "%d", k/149597870.7 + 0.5}')
SPEED_KMS_R=$(awk -v v="$VOY_SPEED_KMS" 'BEGIN{printf "%d", v + 0.5}')
SPEED_KMH_FMT=$(fmt_int "$(awk -v v="$VOY_SPEED_KMS" 'BEGIN{printf "%d", int(v*3600/100 + 0.5)*100}')")
SPEED_MPH_FMT=$(fmt_int "$(awk -v v="$VOY_SPEED_KMS" 'BEGIN{printf "%d", int(v*2236.936/1000 + 0.5)*1000}')")

# ---------------------------------------------------------------
# Feed label honesty: there is no live camera on Voyager 1. The video
# is NASA animation / artist concepts. Set VIDEO_FEED_LABEL only if you
# want a different caption.
# ---------------------------------------------------------------
VIDEO_FEED_LABEL="${VIDEO_FEED_LABEL:-VOYAGER 1 · ANIMATION}"

# ---------------------------------------------------------------
# Network-failure fallback image (shown as a slide if a clip is unreachable).
# ---------------------------------------------------------------
FALLBACK_IMAGE_URL="${FALLBACK_IMAGE_URL:-}"

# ---------------------------------------------------------------
# Optional photo(s) for the status card, comma-separated. If unset
# (default), the script DRAWS a gold Golden Record disc instead, so
# no download is needed.
# ---------------------------------------------------------------
VOY_PANEL_IMAGE_URLS="${VOY_PANEL_IMAGE_URLS:-}"

# ---------------------------------------------------------------
# Video crop zoom/pan (use if the source video has UI chrome baked in).
# VIDEO_ZOOM (>1 crops tighter), VIDEO_PAN_X / VIDEO_PAN_Y (-1..1).
# ---------------------------------------------------------------
VIDEO_ZOOM="${VIDEO_ZOOM:-1.0}"
VIDEO_PAN_X="${VIDEO_PAN_X:-0}"
VIDEO_PAN_Y="${VIDEO_PAN_Y:-0}"

echo "========================================"
echo "Starting 24/7 YouTube Stream (Voyager 1 — 1 Light-Day)"
echo "Milestone         : ${LD_UTC_FULL} UTC"
echo "Output Resolution : 1280x720 (720p — sized for a 2-core CI runner)"
echo "FPS               : 30"
echo "========================================"

FONT="font.ttf"
# Deep-space navy panels, cyan "signal" structure, Golden-Record gold
# highlights, red live indicator.
ACCENT="0x4FD8FF"
GOLD="0xF5B942"
RED="0xFF3B30"
PANEL_BG="0x03060F"
ASSET_DIR="panel_assets"
INFO_FILE="mission_info.txt"
SLOT=6            # seconds each headline is shown
FACT_SLOT=8       # seconds each fun fact is shown
TICKER_SPEED=110  # pixels/second for the bottom ticker scroll
CHANNEL_NAME="Voyager 1 Live · 1 Light-Day From Earth"
SHADOW="shadowcolor=black@0.6:shadowx=1:shadowy=1"
HEADLINE_FONTSIZE=21
HEADLINE_LINE_SPACING=9
HEADLINE_LINE_H=$((HEADLINE_FONTSIZE + HEADLINE_LINE_SPACING))
FACT_FONTSIZE=16
FACT_LINE_SPACING=7
FACT_LINE_H=$((FACT_FONTSIZE + FACT_LINE_SPACING))

# ---------------------------------------------------------------
# Layout: video centered, one panel on each side.
# ---------------------------------------------------------------
PANEL_W=333
CENTER_X0=$PANEL_W
CENTER_W=$((1280 - PANEL_W * 2))
RIGHT_X0=$((1280 - PANEL_W))
TEXT_INSET=33
RTEXT_INSET=$((RIGHT_X0 + 33))
PANEL_TEXT_W=$((PANEL_W - 66))

# ---------------------------------------------------------------
# Center strip: 3 stacked bands —
#   Row 1 - Voyager video/animation
#   Row 2 - VOYAGER 1 STATUS card (distance, signal, age, speed)
#   Row 3 - ROAD TO 200 AU progress bar
# ---------------------------------------------------------------
VIDEO_ROW_H=340
INFO_ROW_H=190
GRAPH_ROW_H=$((720 - VIDEO_ROW_H - INFO_ROW_H))
ROW1_Y=0
ROW2_Y=$((VIDEO_ROW_H))
ROW3_Y=$((VIDEO_ROW_H + INFO_ROW_H))
MTEXT_INSET=$((CENTER_X0 + 30))
MVALUE_X=$((MTEXT_INSET + 150))

VIEWER_MIN_TO_SHOW=10

#############################################
# Auto-restart on failure
#############################################
MAX_RETRIES=5
RETRY_DELAY=5
IMAGE_SLIDE_SECONDS="${IMAGE_SLIDE_SECONDS:-25}"

mkdir -p "$ASSET_DIR"

# PIDs of background helpers (initialised so the EXIT trap is always safe)
CLOCK_PID=""
VOYSTATUS_PID=""
SUBS_PID=""
VIEWERS_PID=""
TRIVIA_PID=""
trap 'for p in "$CLOCK_PID" "$VOYSTATUS_PID" "$SUBS_PID" "$VIEWERS_PID" "$TRIVIA_PID"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done' EXIT

#############################################
# Background audio (one or more tracks, looped)
#############################################
IFS=',' read -ra RAW_AUDIO_URLS <<< "$AUDIO_URL"
AUDIO_LOCAL_FILES=()
audio_i=0
for au in "${RAW_AUDIO_URLS[@]}"; do
    au="${au#"${au%%[![:space:]]*}"}"
    au="${au%"${au##*[![:space:]]}"}"
    [ -z "$au" ] && continue
    audio_i=$((audio_i + 1))
    dest="bg_audio_track_${audio_i}"
    echo "Downloading background audio track ${audio_i}..."
    if curl -sL --fail -o "$dest" "$au" && [ -s "$dest" ]; then
        AUDIO_LOCAL_FILES+=("$dest")
        echo "  OK ($(du -h "$dest" | cut -f1))"
    else
        echo "  WARNING: failed to download track ${audio_i} — skipping it."
    fi
done

NUM_AUDIO=${#AUDIO_LOCAL_FILES[@]}
AUDIO_AVAILABLE=false
if [ "$NUM_AUDIO" -gt 0 ]; then
    AUDIO_AVAILABLE=true
    echo "Loaded $NUM_AUDIO background audio track(s); rotating across videos."
else
    echo "WARNING: no background audio tracks downloaded — stream will run with silent audio instead."
fi
AUDIO_COUNTER=0

#############################################
# Optional photo(s) for the status card
#############################################
PANEL_IMAGE_LOCAL_FILES=()
PANEL_IMAGES_AVAILABLE=false
if [ -n "$VOY_PANEL_IMAGE_URLS" ]; then
    IFS=',' read -ra PANEL_IMAGE_URLS <<< "$VOY_PANEL_IMAGE_URLS"
    pimg_i=0
    for piu in "${PANEL_IMAGE_URLS[@]}"; do
        piu="${piu#"${piu%%[![:space:]]*}"}"
        piu="${piu%"${piu##*[![:space:]]}"}"
        [ -z "$piu" ] && continue
        pimg_i=$((pimg_i + 1))
        dest="panel_img_${pimg_i}.jpg"
        echo "Downloading panel image ${pimg_i} ($(basename "$piu"))..."
        if curl -sL --fail -o "$dest" "$piu" && [ -s "$dest" ]; then
            PANEL_IMAGE_LOCAL_FILES+=("$dest")
            echo "  OK ($(du -h "$dest" | cut -f1))"
        else
            echo "  WARNING: failed to download panel image ${pimg_i} — skipping it."
        fi
    done
fi
NUM_PANEL_IMAGES=${#PANEL_IMAGE_LOCAL_FILES[@]}
if [ "$NUM_PANEL_IMAGES" -gt 0 ]; then
    PANEL_IMAGES_AVAILABLE=true
    echo "Loaded $NUM_PANEL_IMAGES panel image(s)."
else
    echo "NOTICE: no panel image — using the procedurally drawn Golden Record disc."
fi
PANEL_IMAGE_COUNTER=0

#############################################
# Coordinate-label marker dot
#############################################
DOT_MARKER="dot_marker.png"
GOLD_R=245; GOLD_G=185; GOLD_B=66
DOT_VF="format=rgba,geq=r=(if(lte(hypot(X-10\,Y-10)\,5)\,${GOLD_R}\,if(lte(hypot(X-10\,Y-10)\,8)\,255\,0))):g=(if(lte(hypot(X-10\,Y-10)\,5)\,${GOLD_G}\,if(lte(hypot(X-10\,Y-10)\,8)\,255\,0))):b=(if(lte(hypot(X-10\,Y-10)\,5)\,${GOLD_B}\,if(lte(hypot(X-10\,Y-10)\,8)\,255\,0))):a=(if(lte(hypot(X-10\,Y-10)\,8)\,255\,0))"
ffmpeg -y -f lavfi -i "color=c=black@0.0:s=20x20" -vf "$DOT_VF" -frames:v 1 "$DOT_MARKER" -loglevel error
if [ ! -s "$DOT_MARKER" ]; then
    echo "WARNING: geq-based marker generation failed — using a blank 1x1 fallback."
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" | base64 -d > "$DOT_MARKER"
fi

#############################################
# Background clock writer (UTC wall clock)
#############################################
date -u +'%d %b %Y  •  %H:%M:%S UTC' > "$ASSET_DIR/clock.txt"
(
    while true; do
        date -u +'%d %b %Y  •  %H:%M:%S UTC' > "$ASSET_DIR/clock.txt.tmp"
        mv -f "$ASSET_DIR/clock.txt.tmp" "$ASSET_DIR/clock.txt"
        sleep 1
    done
) &
CLOCK_PID=$!

#############################################
# Static panel data text (read with textfile so no escaping is needed)
#############################################
printf '%s' "~${SPEED_KMS_R} km/s · ${SPEED_KMH_FMT} km/h"          > "$ASSET_DIR/voy_speed_val.txt"
printf '%s' "100 AU"                                                > "$ASSET_DIR/voy_bar_left.txt"
printf '%s' "200 AU"                                                > "$ASSET_DIR/voy_bar_right.txt"
printf '%s' "${LD_UTC_FULL} UTC"                                    > "$ASSET_DIR/voy_t_utc.txt"
printf '%s' "${LD_IST_FULL}"                                        > "$ASSET_DIR/voy_t_ist.txt"
printf '%s' "${LD_EST_FULL}"                                        > "$ASSET_DIR/voy_t_est.txt"
printf '%s' "${LD_HEARD_FULL}"                                      > "$ASSET_DIR/voy_t_heard.txt"
printf '%s' "Magnetometer + Plasma Wave"                            > "$ASSET_DIR/voy_instr_caption.txt"

#############################################
# Background VOYAGER STATUS writer — one python process, once a second:
#   voy_dist.txt     Earth-Voyager distance (est.)
#   voy_light.txt    one-way light time  24h 02m 11s
#   voy_since.txt    T+6d 04h 12m 09s since the 1 light-day moment
#   voy_age.txt      mission age since launch
#   voy_sunau.txt    distance from the Sun in AU (est.)
#   next_event.txt   next entry from voyager_events.txt
# Also has a "snapshot" mode used for the progress bar.
#############################################
printf ' ' > "$ASSET_DIR/voy_dist.txt"
printf ' ' > "$ASSET_DIR/voy_light.txt"
printf ' ' > "$ASSET_DIR/voy_since.txt"
printf ' ' > "$ASSET_DIR/voy_age.txt"
printf ' ' > "$ASSET_DIR/voy_sunau.txt"
printf ' ' > "$ASSET_DIR/next_event.txt"

if [ ! -f "$VOY_EVENTS_FILE" ]; then
    cat > "$VOY_EVENTS_FILE" << 'VEOF'
# UTC time, event text (one per line). Edit freely; re-read every second.
2027-02-14 12:00,37 years since Pale Blue Dot
2027-08-20 14:29,Voyager 2 launched 50 yrs ago
2027-09-05 12:56,Voyager 1 turns 50 years old
VEOF
else
    echo "Using curated events: $VOY_EVENTS_FILE"
fi

cat > voyager_status.py << 'PYEOF'
import sys
import os
import time
import math
import calendar
import datetime

mode = sys.argv[1]
asset_dir = sys.argv[2]
anchor_s = float(sys.argv[3])      # unix time Voyager 1 hit 1 light-day
ld_km = float(sys.argv[4])         # 1 light-day in km
speed = float(sys.argv[5])         # km/s relative to the Sun
lon = math.radians(float(sys.argv[6]))
lat = math.radians(float(sys.argv[7]))
launch_s = float(sys.argv[8])
events_file = sys.argv[9]

AU = 149597870.7
C = 299792.458
J2000 = 946728000.0

U = (math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))

def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

def earth_vec(t):
    # Low-precision Earth position (heliocentric, ecliptic plane), km.
    n = (t - J2000) / 86400.0
    g = math.radians((357.528 + 0.9856003 * n) % 360.0)
    lam_sun = (280.460 + 0.9856474 * n + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)) % 360.0
    r = 1.00014 - 0.01671 * math.cos(g) - 0.00014 * math.cos(2 * g)
    L = math.radians(lam_sun + 180.0)
    return (r * AU * math.cos(L), r * AU * math.sin(L), 0.0)

# Calibrate Voyager's heliocentric distance so Earth-Voyager distance is
# exactly one light-day at the NASA milestone time.
_e0 = earth_vec(anchor_s)
_ue = dot(U, _e0)
R0 = _ue + math.sqrt(max(0.0, _ue * _ue - dot(_e0, _e0) + ld_km * ld_km))

def sun_km(t):
    return R0 + speed * (t - anchor_s)

def dist_km(t):
    e = earth_vec(t)
    R = sun_km(t)
    return math.sqrt(max(0.0, R * R - 2.0 * R * dot(U, e) + dot(e, e)))

def age(now_s):
    a = datetime.datetime.utcfromtimestamp(launch_s)
    b = datetime.datetime.utcfromtimestamp(now_s)
    y = b.year - a.year
    m = b.month - a.month
    d = b.day - a.day
    if (b.hour, b.minute, b.second) < (a.hour, a.minute, a.second):
        d -= 1
    if d < 0:
        m -= 1
        pm = b.month - 1 if b.month > 1 else 12
        py = b.year if b.month > 1 else b.year - 1
        d += calendar.monthrange(py, pm)[1]
    if m < 0:
        y -= 1
        m += 12
    return y, m, d

if mode == "snapshot":
    now = time.time()
    sun_au = sun_km(now) / AU
    frac = max(0.0, min(1.0, (sun_au - 100.0) / 100.0))
    print(round(frac, 4), round(sun_au, 1))
    sys.exit(0)

def write(name, text):
    tmp = f"{asset_dir}/{name}.tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, f"{asset_dir}/{name}.txt")

def load_events():
    out = []
    try:
        with open(events_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "," not in line:
                    continue
                ts, text = line.split(",", 1)
                try:
                    dt = datetime.datetime.strptime(ts.strip(), "%Y-%m-%d %H:%M")
                    dt = dt.replace(tzinfo=datetime.timezone.utc)
                except ValueError:
                    continue
                out.append((dt.timestamp(), text.strip()))
    except OSError:
        pass
    return sorted(out)

while True:
    try:
        now = time.time()

        d = dist_km(now)
        write("voy_dist", f"{d:,.0f} km (est.)")

        lt = int(d / C)
        write("voy_light", f"{lt // 3600}h {(lt % 3600) // 60:02d}m {lt % 60:02d}s")

        dd = now - anchor_s
        a = int(abs(dd))
        days, rem = divmod(a, 86400)
        hrs, rem = divmod(rem, 3600)
        mins, secs = divmod(rem, 60)
        sign = "T-" if dd < 0 else "T+"
        write("voy_since", f"{sign}{days}d {hrs:02d}h {mins:02d}m {secs:02d}s")

        y, m, dy = age(now)
        write("voy_age", f"{y} yr {m} mo {dy} d")

        write("voy_sunau", f"NOW · {sun_km(now) / AU:.1f} AU FROM SUN (est.)")

        nxt = "More Voyager milestones ahead"
        for ts, text in load_events():
            if ts > now:
                nxt = text
                break
        if len(nxt) > 30:
            nxt = nxt[:29] + "…"
        write("next_event", nxt)
    except Exception:
        pass
    time.sleep(1)
PYEOF
VOY_PY_ARGS=("$ASSET_DIR" "$LD_EPOCH_S" "$VOY_LIGHTDAY_KM" "$VOY_SPEED_KMS" "$VOY_ECL_LON" "$VOY_ECL_LAT" "$LAUNCH_EPOCH_S" "$VOY_EVENTS_FILE")
(
    python3 voyager_status.py loop "${VOY_PY_ARGS[@]}" \
        2>/tmp/voyager_status_err.log || echo "WARNING: voyager status writer stopped — $(tail -1 /tmp/voyager_status_err.log 2>/dev/null)"
) &
VOYSTATUS_PID=$!

#############################################
# Background subscriber-count writer
#############################################
printf ' ' > "$ASSET_DIR/subs.txt"
if [ "$SHOW_STATS" = true ]; then
    (
        WARNED_ONCE=false
        while true; do
            RESP=$(curl -s "https://www.googleapis.com/youtube/v3/channels?part=statistics&id=${YOUTUBE_CHANNEL_ID}&key=${YOUTUBE_API_KEY}" || true)
            COUNT=$(echo "$RESP" | grep -o '"subscriberCount"[^"]*"[0-9]*"' | grep -oE '[0-9]+' || true)
            if [ -n "$COUNT" ]; then
                FORMATTED=$(echo "$COUNT" | rev | sed 's/\(...\)/\1,/g' | rev | sed 's/^,//')
                printf '%s subscribers' "$FORMATTED" > "$ASSET_DIR/subs.txt.tmp"
                mv -f "$ASSET_DIR/subs.txt.tmp" "$ASSET_DIR/subs.txt"
                WARNED_ONCE=false
            elif [ "$WARNED_ONCE" = false ]; then
                echo "WARNING: could not parse subscriberCount from API response. Raw response:"
                echo "$RESP"
                WARNED_ONCE=true
            fi
            sleep 60
        done
    ) &
    SUBS_PID=$!
fi

#############################################
# Background live-viewer-count writer
#############################################
printf ' ' > "$ASSET_DIR/viewers.txt"
if [ "$SHOW_STATS" = true ]; then
    (
        LIVE_VIDEO_ID=""
        while true; do
            if [ -z "$LIVE_VIDEO_ID" ]; then
                SEARCH_RESP=$(curl -s "https://www.googleapis.com/youtube/v3/search?part=id&channelId=${YOUTUBE_CHANNEL_ID}&eventType=live&type=video&key=${YOUTUBE_API_KEY}" || true)
                LIVE_VIDEO_ID=$(echo "$SEARCH_RESP" | grep -o '"videoId": *"[^"]*"' | head -1 | sed -E 's/.*"videoId": *"([^"]*)".*/\1/' || true)
            fi
            if [ -n "$LIVE_VIDEO_ID" ]; then
                VRESP=$(curl -s "https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails&id=${LIVE_VIDEO_ID}&key=${YOUTUBE_API_KEY}" || true)
                VIEWERS=$(echo "$VRESP" | grep -o '"concurrentViewers": *"[0-9]*"' | grep -o '[0-9]*' || true)
                if [ -n "$VIEWERS" ] && [ "$VIEWERS" -ge "$VIEWER_MIN_TO_SHOW" ]; then
                    printf '%s watching now' "$VIEWERS" > "$ASSET_DIR/viewers.txt.tmp"
                    mv -f "$ASSET_DIR/viewers.txt.tmp" "$ASSET_DIR/viewers.txt"
                elif [ -n "$VIEWERS" ]; then
                    printf ' ' > "$ASSET_DIR/viewers.txt.tmp"
                    mv -f "$ASSET_DIR/viewers.txt.tmp" "$ASSET_DIR/viewers.txt"
                else
                    LIVE_VIDEO_ID=""
                    printf ' ' > "$ASSET_DIR/viewers.txt"
                fi
            fi
            sleep 30
        done
    ) &
    VIEWERS_PID=$!
fi

#############################################
# Static panel text (unchanged across videos)
#############################################
printf 'V O Y A G E R   1'                   > "$ASSET_DIR/title1.txt"
printf '1   L I G H T - D A Y'               > "$ASSET_DIR/title2.txt"
printf 'M I S S I O N   U P D A T E'         > "$ASSET_DIR/header.txt"
printf 'LIVE · INTERSTELLAR SPACE'           > "$ASSET_DIR/eyebrow.txt"
printf 'SUBSCRIBE for live deep-space updates' > "$ASSET_DIR/cta.txt"

#############################################
# "ASK VOYAGER" trivia CTA — alternates with the subscribe prompt in the
# same on-screen slot (see build_final_filter).
#############################################
DEFAULT_TRIVIA=(
    "ASK VOYAGER: how far? ~1 light-day, ${LD_KM_B}B km."
    "ASK VOYAGER: when? ${LD_DATE_SHORT}, ${LD_UTC_HM} UTC."
    "ASK VOYAGER: how fast? ~${SPEED_KMS_R} km per second."
    "ASK VOYAGER: signal delay? ~24 h one way."
    "ASK VOYAGER: how old? Launched Sep 5, 1977."
    "ASK VOYAGER: still working? Yes, 2 instruments."
    "ASK VOYAGER: Golden Record? A message from Earth."
    "ASK VOYAGER: one light-year? ~18,000 years away."
    "ASK VOYAGER: power? Loses ~4 watts every year."
)
TRIVIA_FILE="${TRIVIA_FILE:-trivia.txt}"
if [ -f "$TRIVIA_FILE" ]; then
    echo "Using curated trivia pool: $TRIVIA_FILE"
    TRIVIA_POOL=()
    while IFS= read -r line; do
        [ -n "$(echo "$line" | tr -d '[:space:]')" ] && TRIVIA_POOL+=("$line")
    done < "$TRIVIA_FILE"
else
    TRIVIA_POOL=("${DEFAULT_TRIVIA[@]}")
fi
printf '%s' "${TRIVIA_POOL[0]}" > "$ASSET_DIR/cta_trivia.txt"
(
    ti=0
    n=${#TRIVIA_POOL[@]}
    while true; do
        sleep 240
        ti=$(((ti + 1) % n))
        printf '%s' "${TRIVIA_POOL[$ti]}" > "$ASSET_DIR/cta_trivia.txt.tmp"
        mv -f "$ASSET_DIR/cta_trivia.txt.tmp" "$ASSET_DIR/cta_trivia.txt"
    done
) &
TRIVIA_PID=$!
printf 'DID YOU KNOW'                        > "$ASSET_DIR/fact_label.txt"
printf 'THE SCIENCE'                         > "$ASSET_DIR/instr_label.txt"
printf 'ONE LIGHT-DAY'                       > "$ASSET_DIR/instr_title.txt"

#############################################
# Default headline / fact pools
# (NO percent signs — drawtext would treat them as escapes.)
#############################################
DEFAULT_HEADLINES=(
    "Voyager 1 reached ONE LIGHT-DAY from Earth on ${LD_DATE_SHORT}, 2026 at ${LD_UTC_HM} UTC, the first spacecraft ever to do so."
    "That moment was ${LD_IST_12} in India (IST) and ${LD_EST_12} US Eastern on ${LD_DATE_SHORT}."
    "A light-day is the distance light travels in 24 hours: about ${LD_KM_B} billion km (${LD_MI_B} billion miles)."
    "A command to Voyager 1 now takes about a day to arrive, and the reply takes another day: a 48-hour round trip."
    "Launched on Sept 5, 1977, Voyager 1 took more than 49 years to reach one light-day."
    "Voyager 1 entered interstellar space in August 2012 and is the most distant human-made object."
    "It travels at about ${SPEED_KMS_R} km per second (${SPEED_MPH_FMT} mph) relative to the Sun."
    "Only ${VOY_INSTR_ON} of its ${VOY_INSTR_TOTAL} science instruments still run: the magnetometer and the plasma wave detector."
    "Its low-energy particle instrument was switched off on April 17, 2026 to save power."
    "Its nuclear power source loses about 4 watts every year, so engineers switch systems off to keep it alive."
    "Voyager 1 transmits with about 22 watts, sending data at roughly 160 bits per second."
    "NASA listens to Voyager 1 every day and sends commands about once a week."
    "At this speed, one light-year is about 18,000 years away, and the nearest star about 73,000 years."
    "Voyager 1 carries the Golden Record, a message from humanity built to last over a billion years."
)

DEFAULT_FACTS=(
    "Voyager 1 launched on September 5, 1977 from Kennedy Space Center, Florida."
    "Voyager 2 launched first, on August 20, 1977, but Voyager 1 flew the faster route."
    "Voyager 1 flew past Jupiter in 1979 and Saturn in November 1980."
    "Voyager 1 took the Pale Blue Dot photo of Earth in February 1990."
    "Voyager 1 crossed the heliopause into interstellar space in August 2012."
    "One light-day is about ${LD_AU} times the Earth-Sun distance."
    "Radio waves move at light speed, so every command takes about a day each way."
    "Its signal reaches Earth as a tiny fraction of a trillionth of a watt."
    "The Golden Record holds 115 images, music, and greetings in 55 languages."
    "In about 40,000 years Voyager 1 will pass near the star Gliese 445."
    "Its onboard computers have only about 70 kilobytes of memory in total."
    "Crossing a light-day changes nothing physically: it is a milestone of distance and time."
)

#############################################
# build_labels_chain — generic coordinate-callout feature; works on any
# center-strip video via <basename>.labels.txt (x,y,text per line).
#############################################
build_labels_chain() {
    local url="$1"
    local base
    base="${url##*/}"
    base="${base%.*}"
    local i idx

    LABELS_CHAIN=""
    LABELS_OUT="[base]"

    local labels_file="${base}.labels.txt"
    if [ ! -f "$labels_file" ]; then
        return 0
    fi

    local xs=() ys=() texts=()
    while IFS=',' read -r x y text; do
        x="$(echo "$x" | tr -d '[:space:]')"
        y="$(echo "$y" | tr -d '[:space:]')"
        text="$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ "$x" =~ ^[0-9]+$ ]] || continue
        [[ "$y" =~ ^[0-9]+$ ]] || continue
        [ -z "$text" ] && continue
        xs+=("$x"); ys+=("$y"); texts+=("$text")
    done < "$labels_file"

    local n=${#xs[@]}
    if [ "$n" -eq 0 ]; then
        echo "NOTICE: $labels_file had no valid lines — skipping labels for this video."
        return 0
    fi
    echo "Using coordinate labels: $labels_file ($n label(s))"

    local BOX_H=42
    local V_OFFSET=70
    local H_OFFSET=40
    local ACCENT_W=4
    local BOX_GAP=10
    local LABEL_FONTSIZE=18
    local LABEL_PAD_L=14
    local LABEL_PAD_R=16
    local AVG_CHAR_W=10
    local BOX_W_MIN=110
    local BOX_W_MAX=260
    local placed_x=() placed_y=() placed_w=()
    local k collision tries

    local split_outs=""
    for ((i = 1; i <= n; i++)); do split_outs+="[dm${i}]"; done
    LABELS_CHAIN+="[1:v]fps=30,split=${n}${split_outs};"

    local prev="base"
    for ((i = 0; i < n; i++)); do
        idx=$((i + 1))
        local x="${xs[$i]}" y="${ys[$i]}" text="${texts[$i]}"
        printf '%s' "$text" > "$ASSET_DIR/label${idx}.txt"

        local box_w=$(( ${#text} * AVG_CHAR_W + ACCENT_W + LABEL_PAD_L + LABEL_PAD_R ))
        [ "$box_w" -lt "$BOX_W_MIN" ] && box_w=$BOX_W_MIN
        [ "$box_w" -gt "$BOX_W_MAX" ] && box_w=$BOX_W_MAX

        local box_y=$((y - V_OFFSET))
        if [ "$box_y" -lt 20 ]; then
            box_y=$((y + V_OFFSET - BOX_H))
        fi
        local box_x=$((x + H_OFFSET))
        if [ $((box_x + box_w)) -gt $((RIGHT_X0 - 10)) ]; then
            box_x=$((x - H_OFFSET - box_w))
        fi
        [ "$box_x" -lt $((CENTER_X0 + 10)) ] && box_x=$((CENTER_X0 + 10))

        tries=0
        while :; do
            collision=false
            for ((k = 0; k < ${#placed_x[@]}; k++)); do
                local px="${placed_x[$k]}" py="${placed_y[$k]}" pw="${placed_w[$k]}"
                if [ $((box_x)) -lt $((px + pw + BOX_GAP)) ] && \
                   [ $((box_x + box_w + BOX_GAP)) -gt $((px)) ] && \
                   [ $((box_y)) -lt $((py + BOX_H + BOX_GAP)) ] && \
                   [ $((box_y + BOX_H + BOX_GAP)) -gt $((py)) ]; then
                    collision=true
                    break
                fi
            done
            [ "$collision" = false ] && break
            box_y=$((box_y + BOX_H + BOX_GAP))
            if [ $((box_y + BOX_H)) -gt 700 ]; then
                box_y=20
            fi
            tries=$((tries + 1))
            [ "$tries" -gt 12 ] && break
        done
        placed_x+=("$box_x")
        placed_y+=("$box_y")
        placed_w+=("$box_w")

        local seg_y_top seg_y_bot
        if [ "$box_y" -gt "$y" ]; then
            seg_y_top=$y; seg_y_bot=$box_y
        else
            seg_y_top=$box_y; seg_y_bot=$y
        fi
        local seg_h=$((seg_y_bot - seg_y_top))
        [ "$seg_h" -lt 2 ] && seg_h=2

        local h_left h_w
        if [ "$box_x" -gt "$x" ]; then
            h_left=$x; h_w=$((box_x - x))
        else
            h_left=$box_x; h_w=$((x - box_x))
        fi
        [ "$h_w" -lt 2 ] && h_w=2

        local n1="lbl${idx}_dot" n2="lbl${idx}_v" n3="lbl${idx}_h" n4="lbl${idx}_bg" n5="lbl${idx}_bar" n6="lbl${idx}_outline" n7="lbl${idx}_txt"

        LABELS_CHAIN+="[${prev}]drawbox=x=${x}:y=${seg_y_top}:w=2:h=${seg_h}:color=${ACCENT}@0.85:t=fill[${n2}];"
        LABELS_CHAIN+="[${n2}]drawbox=x=${h_left}:y=${box_y}:w=${h_w}:h=2:color=${ACCENT}@0.85:t=fill[${n3}];"
        LABELS_CHAIN+="[${n3}]drawbox=x=${box_x}:y=${box_y}:w=${box_w}:h=${BOX_H}:color=black@0.78:t=fill[${n4}];"
        LABELS_CHAIN+="[${n4}]drawbox=x=${box_x}:y=${box_y}:w=${ACCENT_W}:h=${BOX_H}:color=${GOLD}:t=fill[${n5}];"
        LABELS_CHAIN+="[${n5}]drawbox=x=${box_x}:y=${box_y}:w=${box_w}:h=${BOX_H}:color=${ACCENT}@0.5:t=1[${n6}];"
        LABELS_CHAIN+="[${n6}]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/label${idx}.txt:fontcolor=white:fontsize=${LABEL_FONTSIZE}:x=$((box_x + ACCENT_W + LABEL_PAD_L)):y=$((box_y + (BOX_H - LABEL_FONTSIZE) / 2)):${SHADOW}[${n7}];"
        LABELS_CHAIN+="[${n7}][dm${idx}]overlay=x=$((x - 8)):y=$((y - 8)):shortest=1[${n1}];"

        prev="$n1"
    done

    LABELS_OUT="[${prev}]"
    echo "Drew $n label(s) from $labels_file"
}

#############################################
# prepare_video_content — per-video overrides
# (<basename>.headlines.txt / .facts.txt / .science.txt), then rebuilds
# BASE_CHAIN / FACT_END for the video about to stream.
#############################################
prepare_video_content() {
    local url="$1"
    local base
    base="${url##*/}"
    base="${base%.*}"
    local i idx

    if [ "$PANEL_IMAGES_AVAILABLE" = true ]; then
        MID_PANEL_IMG="${PANEL_IMAGE_LOCAL_FILES[$((PANEL_IMAGE_COUNTER % NUM_PANEL_IMAGES))]}"
        PANEL_IMAGE_COUNTER=$((PANEL_IMAGE_COUNTER + 1))
        echo "Status card panel image this video: $MID_PANEL_IMG"
    fi

    RAW_LINES=()
    if [ -f "${base}.headlines.txt" ]; then
        echo "Using curated headlines: ${base}.headlines.txt"
        while IFS= read -r line; do
            [ -n "$(echo "$line" | tr -d '[:space:]')" ] && RAW_LINES+=("$line")
        done < "${base}.headlines.txt"
    fi
    if [ "${#RAW_LINES[@]}" -eq 0 ]; then
        local pool=()
        if [ -f "$INFO_FILE" ]; then
            while IFS= read -r line; do
                [ -n "$(echo "$line" | tr -d '[:space:]')" ] && pool+=("$line")
            done < "$INFO_FILE"
        fi
        [ "${#pool[@]}" -eq 0 ] && pool=("${DEFAULT_HEADLINES[@]}")
        while IFS= read -r line; do
            RAW_LINES+=("$line")
        done < <(printf '%s\n' "${pool[@]}" | shuf)
    fi

    FACTS=()
    if [ -f "${base}.facts.txt" ]; then
        echo "Using curated facts: ${base}.facts.txt"
        while IFS= read -r line; do
            [ -n "$(echo "$line" | tr -d '[:space:]')" ] && FACTS+=("$line")
        done < "${base}.facts.txt"
    fi
    if [ "${#FACTS[@]}" -eq 0 ]; then
        local fpool=()
        if [ -f "facts.txt" ]; then
            while IFS= read -r line; do
                [ -n "$(echo "$line" | tr -d '[:space:]')" ] && fpool+=("$line")
            done < "facts.txt"
        fi
        [ "${#fpool[@]}" -eq 0 ] && fpool=("${DEFAULT_FACTS[@]}")
        while IFS= read -r line; do
            FACTS+=("$line")
        done < <(printf '%s\n' "${fpool[@]}" | shuf)
    fi

    if [ -f "${base}.science.txt" ]; then
        head -n 1 "${base}.science.txt" > "$ASSET_DIR/instr_sub.txt"
    else
        printf 'Light covers %s billion km in 24 hours' "$LD_KM_B" > "$ASSET_DIR/instr_sub.txt"
    fi
    fold -s -w 26 "$ASSET_DIR/instr_sub.txt" > "$ASSET_DIR/instr_sub.wrapped.txt"

    N=${#RAW_LINES[@]}
    CYCLE=$((N * SLOT))
    echo "This video: $N headline(s), rotation cycle ${CYCLE}s"

    for i in "${!RAW_LINES[@]}"; do
        idx=$((i + 1))
        echo "${RAW_LINES[$i]}" | fold -s -w 25 > "$ASSET_DIR/headline${idx}.txt"
    done

    MAX_HEADLINE_LINES=1
    for i in "${!RAW_LINES[@]}"; do
        idx=$((i + 1))
        lines=$(grep -c '' "$ASSET_DIR/headline${idx}.txt")
        [ "$lines" -gt "$MAX_HEADLINE_LINES" ] && MAX_HEADLINE_LINES=$lines
    done
    echo "Longest headline wraps to $MAX_HEADLINE_LINES line(s)."

    HEADLINE_Y=230
    PROGRESS_Y=$((HEADLINE_Y + MAX_HEADLINE_LINES * HEADLINE_LINE_H + 40))
    DOTS_Y=$((PROGRESS_Y + 20))

    TICKER_STRING=""
    for i in "${!RAW_LINES[@]}"; do
        TICKER_STRING+="${RAW_LINES[$i]}     •     "
    done
    printf '%s' "$TICKER_STRING" > "$ASSET_DIR/ticker.txt"

    FACT_N=${#FACTS[@]}
    FACT_CYCLE=$((FACT_N * FACT_SLOT))
    local max_fact_lines=1
    for i in "${!FACTS[@]}"; do
        idx=$((i + 1))
        echo "${FACTS[$i]}" | fold -s -w 24 > "$ASSET_DIR/fact${idx}.txt"
        lines=$(grep -c '' "$ASSET_DIR/fact${idx}.txt")
        [ "$lines" -gt "$max_fact_lines" ] && max_fact_lines=$lines
    done
    MAX_FACT_LINES=$max_fact_lines

    RSTAT_Y=19
    RDIV1_Y=$((RSTAT_Y + 4 * 20 + 6))
    RINSTR_LABEL_Y=$((RDIV1_Y + 20))
    RINSTR_TITLE_Y=$((RINSTR_LABEL_Y + 22))
    RINSTR_SUB_Y=$((RINSTR_TITLE_Y + 30))
    RDIV2_Y=$((RINSTR_SUB_Y + 44 + 16))
    RFACT_LABEL_Y=$((RDIV2_Y + 14))
    RFACT_TEXT_Y=$((RFACT_LABEL_Y + 24))

    #########################################
    # Live geometry for THIS moment (refreshes each video rotation):
    #   BAR_FRAC  progress of Voyager's distance from the Sun, 100 -> 200 AU
    #   SUN_AU    current distance from the Sun (est.)
    #########################################
    BAR_FRAC=""
    SUN_AU=""
    read -r BAR_FRAC SUN_AU < <(python3 voyager_status.py snapshot "${VOY_PY_ARGS[@]}" 2>/dev/null) || true
    BAR_FRAC="${BAR_FRAC:-0.72}"
    SUN_AU="${SUN_AU:-172.5}"
    echo "Voyager geometry: ${SUN_AU} AU from the Sun, road-to-200-AU progress ${BAR_FRAC}"

    #########################################
    # Rebuild BASE_CHAIN for this video's content
    #########################################
    CHAIN="color=c=black:s=1280x720[canvas];"
    local ZOOM_W ZOOM_H
    ZOOM_W=$(awk -v w="$CENTER_W" -v z="$VIDEO_ZOOM" 'BEGIN{printf "%d", w*z}')
    ZOOM_H=$(awk -v h="$VIDEO_ROW_H" -v z="$VIDEO_ZOOM" 'BEGIN{printf "%d", h*z}')
    CHAIN+="[0:v]fps=30,scale=${ZOOM_W}:${ZOOM_H}:force_original_aspect_ratio=increase,crop=${CENTER_W}:${VIDEO_ROW_H}:x='(in_w-out_w)/2+(in_w-out_w)/2*${VIDEO_PAN_X}':y='(in_h-out_h)/2+(in_h-out_h)/2*${VIDEO_PAN_Y}'[vidfit];"
    CHAIN+="[canvas][vidfit]overlay=${CENTER_X0}:${ROW1_Y}:shortest=1[base];"

    build_labels_chain "$url"
    CHAIN+="$LABELS_CHAIN"

    # ---------------- Broadcast-style corner brackets on the video ----------------
    local BR_L=26 BR_T=3 BR_M=10
    local VX0=$CENTER_X0
    local VX1=$((CENTER_X0 + CENTER_W))
    local VY0=0
    local VY1=$VIDEO_ROW_H
    CHAIN+="${LABELS_OUT}drawbox=x=$((VX0 + BR_M)):y=$((VY0 + BR_M)):w=${BR_L}:h=${BR_T}:color=${ACCENT}@0.9:t=fill[br1];"
    CHAIN+="[br1]drawbox=x=$((VX0 + BR_M)):y=$((VY0 + BR_M)):w=${BR_T}:h=${BR_L}:color=${ACCENT}@0.9:t=fill[br2];"
    CHAIN+="[br2]drawbox=x=$((VX1 - BR_M - BR_L)):y=$((VY0 + BR_M)):w=${BR_L}:h=${BR_T}:color=${ACCENT}@0.9:t=fill[br3];"
    CHAIN+="[br3]drawbox=x=$((VX1 - BR_M - BR_T)):y=$((VY0 + BR_M)):w=${BR_T}:h=${BR_L}:color=${ACCENT}@0.9:t=fill[br4];"
    CHAIN+="[br4]drawbox=x=$((VX0 + BR_M)):y=$((VY1 - BR_M - BR_T)):w=${BR_L}:h=${BR_T}:color=${ACCENT}@0.9:t=fill[br5];"
    CHAIN+="[br5]drawbox=x=$((VX0 + BR_M)):y=$((VY1 - BR_M - BR_L)):w=${BR_T}:h=${BR_L}:color=${ACCENT}@0.9:t=fill[br6];"
    CHAIN+="[br6]drawbox=x=$((VX1 - BR_M - BR_L)):y=$((VY1 - BR_M - BR_T)):w=${BR_L}:h=${BR_T}:color=${ACCENT}@0.9:t=fill[br7];"
    CHAIN+="[br7]drawbox=x=$((VX1 - BR_M - BR_T)):y=$((VY1 - BR_M - BR_L)):w=${BR_T}:h=${BR_L}:color=${ACCENT}@0.9:t=fill[br8];"

    local BR_DOT=3
    CHAIN+="[br8]drawbox=x=$((VX0 + BR_M - 1)):y=$((VY0 + BR_M - 1)):w=${BR_DOT}:h=${BR_DOT}:color=${GOLD}:t=fill[brdot1];"
    CHAIN+="[brdot1]drawbox=x=$((VX1 - BR_M - 2)):y=$((VY0 + BR_M - 1)):w=${BR_DOT}:h=${BR_DOT}:color=${GOLD}:t=fill[brdot2];"
    CHAIN+="[brdot2]drawbox=x=$((VX0 + BR_M - 1)):y=$((VY1 - BR_M - 2)):w=${BR_DOT}:h=${BR_DOT}:color=${GOLD}:t=fill[brdot3];"
    CHAIN+="[brdot3]drawbox=x=$((VX1 - BR_M - 2)):y=$((VY1 - BR_M - 2)):w=${BR_DOT}:h=${BR_DOT}:color=${GOLD}:t=fill[brdot4];"
    local VMID_X=$((VX0 + CENTER_W / 2))
    CHAIN+="[brdot4]drawbox=x=$((VMID_X - 1)):y=${VY0}:w=2:h=8:color=${ACCENT}@0.7:t=fill[brtick1];"
    CHAIN+="[brtick1]drawbox=x=$((VMID_X - 1)):y=$((VY1 - 8)):w=2:h=8:color=${ACCENT}@0.7:t=fill[br8b];"
    local CAPTION_W=$(( ${#VIDEO_FEED_LABEL} * 8 + 30 ))
    [ "$CAPTION_W" -lt 150 ] && CAPTION_W=150
    CHAIN+="[br8b]drawbox=x=${VX0}:y=$((VY1 - 34)):w=${CAPTION_W}:h=34:color=black@0.55:t=fill[brcap1];"
    CHAIN+="[brcap1]drawtext=fontfile=${FONT}:text='${VIDEO_FEED_LABEL}':fontcolor=white@0.9:fontsize=13:x=$((VX0 + 14)):y=$((VY1 - 22)):${SHADOW}[brcap2];"
    local prev="brcap2"

    local CARD_PAD=10
    local CARD_X0=$((CENTER_X0 + CARD_PAD))
    local CARD_W=$((CENTER_W - CARD_PAD * 2))

    # ---------------- Row 2: VOYAGER 1 STATUS card ----------------
    local CM3_Y0=$((ROW2_Y + CARD_PAD))
    local CM3_Y1=$((ROW3_Y - CARD_PAD))
    CHAIN+="[${prev}]drawbox=x=${CARD_X0}:y=${CM3_Y0}:w=${CARD_W}:h=$((CM3_Y1 - CM3_Y0)):color=${PANEL_BG}@0.7:t=fill[cm3card];"
    CHAIN+="[cm3card]drawbox=x=${CARD_X0}:y=${CM3_Y0}:w=${CARD_W}:h=$((CM3_Y1 - CM3_Y0)):color=${ACCENT}@0.35:t=1[cm3border];"

    local CM3_LABEL_Y=$((CM3_Y0 + 20))
    local CM3_LINE1_Y=$((CM3_LABEL_Y + 30))
    local CM3_LINE2_Y=$((CM3_LINE1_Y + 26))
    local CM3_LINE3_Y=$((CM3_LINE2_Y + 26))
    local CM3_LINE4_Y=$((CM3_LINE3_Y + 26))
    local CM3_LINE5_Y=$((CM3_LINE4_Y + 26))

    CHAIN+="[cm3border]drawbox=x=$((MTEXT_INSET - 2)):y=$((CM3_LABEL_Y - 2)):w=6:h=6:color=${ACCENT}:t=fill[cm3z];"
    CHAIN+="[cm3z]drawtext=fontfile=${FONT}:text='VOYAGER 1 STATUS':fontcolor=${ACCENT}@0.9:fontsize=13:x=$((MTEXT_INSET + 14)):y=$((CM3_LABEL_Y - 6))[cm3z2];"
    CHAIN+="[cm3z2]drawbox=x=${MTEXT_INSET}:y=$((CM3_LABEL_Y + 14)):w=$((CARD_W - 40)):h=1:color=white@0.15:t=fill[cm3a];"
    CHAIN+="[cm3a]drawtext=fontfile=${FONT}:text='DISTANCE (est.)':fontcolor=white@0.55:fontsize=13:x=${MTEXT_INSET}:y=${CM3_LINE1_Y}[cm3b];"
    CHAIN+="[cm3b]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_dist.txt:reload=1:fontcolor=white:fontsize=14:x=${MVALUE_X}:y=${CM3_LINE1_Y}[cm3c];"
    CHAIN+="[cm3c]drawtext=fontfile=${FONT}:text='ONE-WAY SIGNAL':fontcolor=white@0.55:fontsize=13:x=${MTEXT_INSET}:y=${CM3_LINE2_Y}[cm3d];"
    CHAIN+="[cm3d]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_light.txt:reload=1:fontcolor=${GOLD}:fontsize=14:x=${MVALUE_X}:y=${CM3_LINE2_Y}[cm3e];"
    CHAIN+="[cm3e]drawtext=fontfile=${FONT}:text='SINCE LIGHT-DAY':fontcolor=white@0.55:fontsize=13:x=${MTEXT_INSET}:y=${CM3_LINE3_Y}[cm3f];"
    CHAIN+="[cm3f]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_since.txt:reload=1:fontcolor=white:fontsize=14:x=${MVALUE_X}:y=${CM3_LINE3_Y}[cm3g];"
    CHAIN+="[cm3g]drawtext=fontfile=${FONT}:text='MISSION AGE':fontcolor=white@0.55:fontsize=13:x=${MTEXT_INSET}:y=${CM3_LINE4_Y}[cm3h];"
    CHAIN+="[cm3h]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_age.txt:reload=1:fontcolor=white:fontsize=14:x=${MVALUE_X}:y=${CM3_LINE4_Y}[cm3i];"
    CHAIN+="[cm3i]drawtext=fontfile=${FONT}:text='SPEED':fontcolor=white@0.55:fontsize=13:x=${MTEXT_INSET}:y=${CM3_LINE5_Y}[cm3j];"
    CHAIN+="[cm3j]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_speed_val.txt:fontcolor=${GOLD}:fontsize=14:x=${MVALUE_X}:y=${CM3_LINE5_Y}[cm3final];"
    prev="cm3final"

    # ---------------- Center strip: framed disc (photo or drawn Golden Record) ----------------
    local MID_X0=$((MTEXT_INSET + 400))
    local MID_AVAIL_W=$(((CARD_X0 + CARD_W - 14) - MID_X0))
    local MID_TOP=$((CM3_LABEL_Y + 14 + 14))
    local MID_BOTTOM=$((CM3_Y1 - 16))
    local MID_AVAIL_H=$((MID_BOTTOM - MID_TOP))
    if [ "$MID_AVAIL_W" -ge 90 ] && [ "$MID_AVAIL_H" -ge 90 ]; then
        local MTHUMB=$MID_AVAIL_W
        [ "$MID_AVAIL_H" -lt "$MTHUMB" ] && MTHUMB=$MID_AVAIL_H
        [ "$MTHUMB" -gt 130 ] && MTHUMB=130
        local MTX=$((MID_X0 + (MID_AVAIL_W - MTHUMB) / 2))
        local MTY=$((MID_TOP + (MID_AVAIL_H - MTHUMB) / 2))
        CHAIN+="[${prev}]drawbox=x=$((MTX - 4)):y=$((MTY - 4)):w=$((MTHUMB + 8)):h=$((MTHUMB + 8)):color=black@0.6:t=fill[mthumbbg];"
        CHAIN+="[mthumbbg]drawbox=x=$((MTX - 4)):y=$((MTY - 4)):w=$((MTHUMB + 8)):h=$((MTHUMB + 8)):color=${GOLD}@0.5:t=1[mthumbborder];"
        if [ "$PANEL_IMAGES_AVAILABLE" = true ]; then
            CHAIN+="[3:v]fps=30,scale=${MTHUMB}:${MTHUMB}:force_original_aspect_ratio=increase,crop=${MTHUMB}:${MTHUMB}[mimg];"
        else
            # Procedural Golden Record: a gold disc with concentric grooves,
            # a blue label area and a centre hole (decorative).
            local MC=$((MTHUMB / 2))
            local MR=$((MTHUMB / 2 - 3))
            local M_DIST="hypot(X-${MC}\,Y-${MC})"
            local M_G="(0.62+0.38*sin(${M_DIST}*1.7))"
            local M_R="if(lte(${M_DIST}\,${MR})\,if(lte(${M_DIST}\,${MR}*0.3)\,30\,245*${M_G})\,0)"
            local M_GG="if(lte(${M_DIST}\,${MR})\,if(lte(${M_DIST}\,${MR}*0.3)\,80\,185*${M_G})\,0)"
            local M_B="if(lte(${M_DIST}\,${MR})\,if(lte(${M_DIST}\,${MR}*0.3)\,110\,66*${M_G})\,0)"
            local M_A="if(lte(${M_DIST}\,${MR})\,if(lte(${M_DIST}\,${MR}*0.06)\,0\,255)\,0)"
            # r=1: the disc is static, so render it at 1 fps (overlay
            # repeats the last frame) to keep geq cheap on a 2-core runner.
            CHAIN+="color=c=black@0:s=${MTHUMB}x${MTHUMB}:r=1[disc_src];"
            CHAIN+="[disc_src]format=rgba,geq=r='${M_R}':g='${M_GG}':b='${M_B}':a='${M_A}'[mimg];"
        fi
        CHAIN+="[mthumbborder][mimg]overlay=x=${MTX}:y=${MTY}:shortest=1[mthumbfinal];"
        prev="mthumbfinal"
    fi

    # ---------------- Row 3: ROAD TO 200 AU progress (distance from the Sun) ----------------
    local CM4_Y0=$((ROW3_Y + CARD_PAD))
    local CM4_Y1=$((680 - CARD_PAD))
    CHAIN+="[${prev}]drawbox=x=${CARD_X0}:y=${CM4_Y0}:w=${CARD_W}:h=$((CM4_Y1 - CM4_Y0)):color=${PANEL_BG}@0.7:t=fill[cm4card];"
    CHAIN+="[cm4card]drawbox=x=${CARD_X0}:y=${CM4_Y0}:w=${CARD_W}:h=$((CM4_Y1 - CM4_Y0)):color=${GOLD}@0.3:t=1[cm4border];"

    local CM4_LABEL_Y=$((CM4_Y0 + 20))
    local CM4_BAR_Y=$((CM4_LABEL_Y + 22))
    local CM4_BAR_H=18
    local CM4_BAR_X=$((MTEXT_INSET - 4))
    local CM4_BAR_W=$((CARD_W - 40))

    # Filled by Voyager's distance from the Sun between 100 and 200 AU
    # (computed by voyager_status.py, refreshed each video rotation).
    local CM4_FILL_W
    CM4_FILL_W=$(awk -v w="$CM4_BAR_W" -v f="$BAR_FRAC" 'BEGIN{printf "%d", w*f}')
    [ "$CM4_FILL_W" -gt "$CM4_BAR_W" ] && CM4_FILL_W=$CM4_BAR_W
    [ "$CM4_FILL_W" -lt 0 ] && CM4_FILL_W=0

    CHAIN+="[cm4border]drawbox=x=$((MTEXT_INSET - 2)):y=$((CM4_LABEL_Y - 2)):w=6:h=6:color=${RED}:t=fill:enable='lt(mod(t\,1.2)\,0.75)'[cm4a];"
    CHAIN+="[cm4a]drawtext=fontfile=${FONT}:text='ROAD TO 200 AU · FROM THE SUN':fontcolor=white@0.75:fontsize=13:x=$((MTEXT_INSET + 14)):y=$((CM4_LABEL_Y - 6))[cm4b];"
    CHAIN+="[cm4b]drawbox=x=${CM4_BAR_X}:y=${CM4_BAR_Y}:w=${CM4_BAR_W}:h=${CM4_BAR_H}:color=black@0.4:t=fill[cm4barbg];"
    CHAIN+="[cm4barbg]drawbox=x=${CM4_BAR_X}:y=${CM4_BAR_Y}:w=${CM4_BAR_W}:h=${CM4_BAR_H}:color=white@0.2:t=1[cm4barborder];"
    CHAIN+="[cm4barborder]drawbox=x=${CM4_BAR_X}:y=${CM4_BAR_Y}:w=${CM4_FILL_W}:h=${CM4_BAR_H}:color=${ACCENT}@0.85:t=fill[cm4fillraw];"
    prev="cm4fillraw"
    CHAIN+="[${prev}]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_bar_left.txt:fontcolor=white@0.8:fontsize=13:x=${CM4_BAR_X}:y=$((CM4_BAR_Y + CM4_BAR_H + 12)):${SHADOW}[cm4day];"
    CHAIN+="[cm4day]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_sunau.txt:reload=1:fontcolor=${GOLD}:fontsize=13:x='${CM4_BAR_X}+${CM4_BAR_W}/2-text_w/2':y=$((CM4_BAR_Y + CM4_BAR_H + 12)):${SHADOW}[cm4mid];"
    CHAIN+="[cm4mid]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_bar_right.txt:fontcolor=white@0.8:fontsize=13:x='${CM4_BAR_X}+${CM4_BAR_W}-text_w':y=$((CM4_BAR_Y + CM4_BAR_H + 12)):${SHADOW}[cm4base];"
    prev="cm4base"

    # ---------------- Left panel: story / headlines ----------------
    CHAIN+="[${prev}]drawbox=x=0:y=0:w=${PANEL_W}:h=720:color=${PANEL_BG}@0.94:t=fill[p1];"
    CHAIN+="[p1]drawbox=x=${PANEL_W}:y=0:w=3:h=720:color=${ACCENT}@0.75:t=fill[p2];"
    CHAIN+="[p2]drawbox=x=0:y=0:w=${PANEL_W}:h=10:color=${ACCENT}@0.18:t=fill[p2g];"
    CHAIN+="[p2g]drawbox=x=0:y=0:w=${PANEL_W}:h=3:color=${ACCENT}@0.95:t=fill[p3];"

    CHAIN+="[p3]drawbox=x=27:y=28:w=11:h=11:color=${RED}:t=fill:enable='lt(mod(t\,1)\,0.6)'[p4];"
    CHAIN+="[p4]drawtext=fontfile=${FONT}:text='LIVE':fontcolor=white:fontsize=30:x=44:y=19[p5];"
    CHAIN+="[p5]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/eyebrow.txt:fontcolor=${ACCENT}@0.9:fontsize=13:x=${TEXT_INSET}-text_w+280:y=39[p6];"

    CHAIN+="[p6]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/title1.txt:fontcolor=white:fontsize=22:x=${TEXT_INSET}:y=95:${SHADOW}[p7];"
    CHAIN+="[p7]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/title2.txt:fontcolor=${GOLD}:fontsize=16:x=${TEXT_INSET}:y=123:${SHADOW}[p8];"
    CHAIN+="[p8]drawbox=x=${TEXT_INSET}:y=153:w=${PANEL_TEXT_W}:h=2:color=white@0.3:t=fill[p9];"

    CHAIN+="[p9]drawbox=x=${TEXT_INSET}:y=171:w=8:h=8:color=${ACCENT}:t=fill[p10];"
    CHAIN+="[p10]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/header.txt:fontcolor=${ACCENT}:fontsize=14:x=$((TEXT_INSET + 16)):y=168[p11];"
    CHAIN+="[p11]drawtext=fontfile=${FONT}:text='NEXT\: ':fontcolor=white@0.45:fontsize=12:x=${TEXT_INSET}:y=191[p11b];"
    CHAIN+="[p11b]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/next_event.txt:reload=1:fontcolor=${GOLD}@0.9:fontsize=12:x=$((TEXT_INSET + 42)):y=191[p11c];"

    local prev="p11c"
    for i in "${!RAW_LINES[@]}"; do
        idx=$((i + 1))
        local start=$((i * SLOT))
        local end=$((start + SLOT))
        local nxt="h${idx}"
        local ALPHA="if(between(mod(t\,${CYCLE})\,${start}\,${end})\,if(lt(mod(t\,${CYCLE})-${start}\,0.6)\,(mod(t\,${CYCLE})-${start})/0.6\,if(gt(mod(t\,${CYCLE})-${start}\,${SLOT}-0.6)\,(${end}-mod(t\,${CYCLE}))/0.6\,1))\,0)"
        CHAIN+="[${prev}]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/headline${idx}.txt:fontcolor=white:fontsize=${HEADLINE_FONTSIZE}:line_spacing=${HEADLINE_LINE_SPACING}:x=${TEXT_INSET}:y=${HEADLINE_Y}:alpha='${ALPHA}':${SHADOW}[${nxt}];"
        prev="$nxt"
    done

    CHAIN+="[${prev}]drawtext=fontfile=${FONT}:text='STORY PROGRESS':fontcolor=white@0.35:fontsize=9:x=${TEXT_INSET}:y=$((PROGRESS_Y - 15))[pgcap];"
    CHAIN+="[pgcap]drawbox=x=${TEXT_INSET}:y=${PROGRESS_Y}:w=${PANEL_TEXT_W}:h=2:color=white@0.15:t=fill[pg1];"
    CHAIN+="[pg1]drawbox=x=${TEXT_INSET}:y=${PROGRESS_Y}:w='${PANEL_TEXT_W}*(mod(t\,${SLOT}))/${SLOT}':h=2:color=${ACCENT}:t=fill[pg2];"
    prev="pg2"

    for i in "${!RAW_LINES[@]}"; do
        idx=$((i + 1))
        local x=$((TEXT_INSET + i * 17))
        local nxt="db${idx}"
        CHAIN+="[${prev}]drawbox=x=${x}:y=${DOTS_Y}:w=7:h=7:color=white@0.3:t=fill[${nxt}];"
        prev="$nxt"
    done

    local last=$((N - 1))
    for i in "${!RAW_LINES[@]}"; do
        idx=$((i + 1))
        local x=$((TEXT_INSET + i * 17))
        local start=$((i * SLOT))
        local end=$((start + SLOT))
        local ENABLE="between(mod(t\,${CYCLE})\,${start}\,${end})"
        if [ "$i" -eq "$last" ]; then
            CHAIN+="[${prev}]drawbox=x=${x}:y=${DOTS_Y}:w=7:h=7:color=${ACCENT}:t=fill:enable='${ENABLE}'[pdotend];"
            prev="pdotend"
        else
            local nxt="da${idx}"
            CHAIN+="[${prev}]drawbox=x=${x}:y=${DOTS_Y}:w=7:h=7:color=${ACCENT}:t=fill:enable='${ENABLE}'[${nxt}];"
            prev="$nxt"
        fi
    done

    # ---------------- Left panel: animated "DEEP SPACE LINK" bar graph (decorative) ----------------
    local GRAPH_LABEL_Y=$((DOTS_Y + 40))
    local GRAPH_BASE_Y=$((GRAPH_LABEL_Y + 160))
    local BAR_COUNT=14
    local BAR_W=13
    local BAR_GAP=6
    local BAR_MINH=8
    local BAR_MAXH=100

    CHAIN+="[${prev}]drawbox=x=$((TEXT_INSET - 2)):y=$((GRAPH_LABEL_Y - 2)):w=6:h=6:color=${ACCENT}:t=fill:enable='lt(mod(t\,1.4)\,0.9)'[sa1];"
    CHAIN+="[sa1]drawtext=fontfile=${FONT}:text='DEEP SPACE LINK · illustrative':fontcolor=white@0.55:fontsize=11:x=$((TEXT_INSET + 14)):y=$((GRAPH_LABEL_Y - 8))[sa2];"
    CHAIN+="[sa2]drawtext=fontfile=${FONT}:text='VOYAGER 1 SIGNAL':fontcolor=${GOLD}:fontsize=16:x=${TEXT_INSET}:y=$((GRAPH_LABEL_Y + 10)):${SHADOW}[sa3];"
    prev="sa3"

    local bi bx h_expr y_expr bnxt
    for ((bi = 0; bi < BAR_COUNT; bi++)); do
        bx=$((TEXT_INSET + bi * (BAR_W + BAR_GAP)))
        h_expr="clip(60+38*sin(2*PI*t/3.1+${bi}*0.55)+18*sin(2*PI*t/1.6+${bi}*0.9)\,${BAR_MINH}\,${BAR_MAXH})"
        y_expr="${GRAPH_BASE_Y}-(${h_expr})"
        bnxt="sabar${bi}"
        CHAIN+="[${prev}]drawbox=x=${bx}:y='${y_expr}':w=${BAR_W}:h='${h_expr}':color=${ACCENT}@0.8:t=fill[${bnxt}];"
        prev="$bnxt"
    done
    CHAIN+="[${prev}]drawbox=x=${TEXT_INSET}:y=${GRAPH_BASE_Y}:w=${PANEL_TEXT_W}:h=1:color=white@0.2:t=fill[sabase];"
    prev="sabase"

    # ---------------- Right panel: stats + science + facts ----------------
    CHAIN+="[${prev}]drawbox=x=${RIGHT_X0}:y=0:w=${PANEL_W}:h=720:color=${PANEL_BG}@0.94:t=fill[r1];"
    CHAIN+="[r1]drawbox=x=$((RIGHT_X0 - 3)):y=0:w=3:h=720:color=${ACCENT}@0.75:t=fill[r2];"
    CHAIN+="[r2]drawbox=x=${RIGHT_X0}:y=0:w=${PANEL_W}:h=10:color=${ACCENT}@0.18:t=fill[r2g];"
    CHAIN+="[r2g]drawbox=x=${RIGHT_X0}:y=0:w=${PANEL_W}:h=3:color=${ACCENT}@0.95:t=fill[r3];"

    CHAIN+="[r3]drawtext=fontfile=${FONT}:text='Data · NASA / JPL':fontcolor=white@0.85:fontsize=13:x=${RTEXT_INSET}:y=${RSTAT_Y}[r4];"
    CHAIN+="[r4]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/clock.txt:reload=1:fontcolor=${GOLD}:fontsize=14:x=${RTEXT_INSET}:y=$((RSTAT_Y + 20))[r5];"
    CHAIN+="[r5]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/subs.txt:reload=1:fontcolor=white@0.75:fontsize=13:x=${RTEXT_INSET}:y=$((RSTAT_Y + 40))[r6];"
    CHAIN+="[r6]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/viewers.txt:reload=1:fontcolor=white@0.75:fontsize=13:x=${RTEXT_INSET}:y=$((RSTAT_Y + 60))[r7];"

    CHAIN+="[r7]drawbox=x=${RTEXT_INSET}:y=${RDIV1_Y}:w=${PANEL_TEXT_W}:h=2:color=white@0.15:t=fill[r8];"

    CHAIN+="[r8]drawbox=x=${RTEXT_INSET}:y=${RINSTR_LABEL_Y}:w=8:h=8:color=${ACCENT}:t=fill[r9];"
    CHAIN+="[r9]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/instr_label.txt:fontcolor=${ACCENT}:fontsize=14:x=$((RTEXT_INSET + 16)):y=$((RINSTR_LABEL_Y - 3))[r10];"
    CHAIN+="[r10]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/instr_title.txt:fontcolor=white:fontsize=20:x=${RTEXT_INSET}:y=${RINSTR_TITLE_Y}:${SHADOW}[r11];"
    CHAIN+="[r11]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/instr_sub.wrapped.txt:fontcolor=white@0.75:fontsize=14:line_spacing=6:x=${RTEXT_INSET}:y=${RINSTR_SUB_Y}[r12];"

    CHAIN+="[r12]drawbox=x=${RTEXT_INSET}:y=${RDIV2_Y}:w=${PANEL_TEXT_W}:h=2:color=${GOLD}@0.4:t=fill[r13];"
    CHAIN+="[r13]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/fact_label.txt:fontcolor=${GOLD}@0.9:fontsize=12:x=${RTEXT_INSET}:y=${RFACT_LABEL_Y}[r14];"
    prev="r14"
    for i in "${!FACTS[@]}"; do
        idx=$((i + 1))
        local start=$((i * FACT_SLOT))
        local end=$((start + FACT_SLOT))
        local nxt="f${idx}"
        local FALPHA="if(between(mod(t\,${FACT_CYCLE})\,${start}\,${end})\,if(lt(mod(t\,${FACT_CYCLE})-${start}\,0.6)\,(mod(t\,${FACT_CYCLE})-${start})/0.6\,if(gt(mod(t\,${FACT_CYCLE})-${start}\,${FACT_SLOT}-0.6)\,(${end}-mod(t\,${FACT_CYCLE}))/0.6\,1))\,0)"
        CHAIN+="[${prev}]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/fact${idx}.txt:fontcolor=white@0.9:fontsize=${FACT_FONTSIZE}:line_spacing=${FACT_LINE_SPACING}:x=${RTEXT_INSET}:y=${RFACT_TEXT_Y}:alpha='${FALPHA}'[${nxt}];"
        prev="$nxt"
    done

    # ---------------- Right panel: LIGHT-DAY MILESTONE readings ----------------
    local RREAD_DIV_Y=$((RFACT_TEXT_Y + MAX_FACT_LINES * FACT_LINE_H + 16))
    local RREAD_LABEL_Y=$((RREAD_DIV_Y + 14))
    local RREAD_LINE1_Y=$((RREAD_LABEL_Y + 22))
    local RREAD_LINE2_Y=$((RREAD_LINE1_Y + 20))
    local RREAD_LINE3_Y=$((RREAD_LINE2_Y + 20))
    local RREAD_LINE4_Y=$((RREAD_LINE3_Y + 20))
    local RGRAPH_LABEL_Y=$((RREAD_LINE4_Y + 30))

    CHAIN+="[${prev}]drawbox=x=${RTEXT_INSET}:y=${RREAD_DIV_Y}:w=${PANEL_TEXT_W}:h=2:color=white@0.15:t=fill[rr0];"
    CHAIN+="[rr0]drawtext=fontfile=${FONT}:text='LIGHT-DAY MILESTONE':fontcolor=${GOLD}@0.9:fontsize=12:x=${RTEXT_INSET}:y=${RREAD_LABEL_Y}[rr0b];"
    CHAIN+="[rr0b]drawtext=fontfile=${FONT}:text='UTC':fontcolor=white@0.55:fontsize=12:x=${RTEXT_INSET}:y=${RREAD_LINE1_Y}[rr0c];"
    CHAIN+="[rr0c]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_t_utc.txt:fontcolor=white:fontsize=13:x=$((RTEXT_INSET + 80)):y=${RREAD_LINE1_Y}[rr1];"
    CHAIN+="[rr1]drawtext=fontfile=${FONT}:text='INDIA (IST)':fontcolor=white@0.55:fontsize=12:x=${RTEXT_INSET}:y=${RREAD_LINE2_Y}[rr1b];"
    CHAIN+="[rr1b]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_t_ist.txt:fontcolor=${GOLD}:fontsize=13:x=$((RTEXT_INSET + 80)):y=${RREAD_LINE2_Y}[rr2];"
    CHAIN+="[rr2]drawtext=fontfile=${FONT}:text='US EAST':fontcolor=white@0.55:fontsize=12:x=${RTEXT_INSET}:y=${RREAD_LINE3_Y}[rr2b];"
    CHAIN+="[rr2b]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_t_est.txt:fontcolor=white:fontsize=13:x=$((RTEXT_INSET + 80)):y=${RREAD_LINE3_Y}[rr2c];"
    CHAIN+="[rr2c]drawtext=fontfile=${FONT}:text='HEARD':fontcolor=white@0.55:fontsize=12:x=${RTEXT_INSET}:y=${RREAD_LINE4_Y}[rr2d];"
    CHAIN+="[rr2d]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_t_heard.txt:fontcolor=white:fontsize=13:x=$((RTEXT_INSET + 80)):y=${RREAD_LINE4_Y}[rr3];"
    prev="rr3"

    # ---------------- Right panel: science-instruments gauge ----------------
    local PIE_LABEL_Y=$((RGRAPH_LABEL_Y))
    local PIE_TOP=$((PIE_LABEL_Y + 18))
    local PIE_AVAIL_H=$((640 - PIE_TOP))
    local PIE_SIZE=$PIE_AVAIL_H
    [ "$PIE_SIZE" -gt "$PANEL_TEXT_W" ] && PIE_SIZE=$PANEL_TEXT_W
    [ "$PIE_SIZE" -gt 130 ] && PIE_SIZE=130
    local PIE_CX=$((PIE_SIZE / 2))
    local PIE_CY=$((PIE_SIZE / 2))
    local PIE_R=$((PIE_SIZE / 2 - 4))
    local PIE_X=$((RTEXT_INSET + (PANEL_TEXT_W - PIE_SIZE) / 2))
    local PIE_Y=$PIE_TOP

    local PIE_PCT_NOW=$((VOY_INSTR_ON * 100 / VOY_INSTR_TOTAL))
    [ "$PIE_PCT_NOW" -gt 100 ] && PIE_PCT_NOW=100
    [ "$PIE_PCT_NOW" -lt 0 ] && PIE_PCT_NOW=0
    local PIE_DIST="hypot(X-${PIE_CX}\,Y-${PIE_CY})"
    local PIE_THETA="mod(atan2(Y-${PIE_CY}\,X-${PIE_CX})+PI/2+2*PI\,2*PI)"
    local PIE_FILL_ANGLE="(2*PI*${PIE_PCT_NOW}/100)"
    local PIE_R_EXPR="if(lte(${PIE_DIST}\,${PIE_R})\,if(lte(${PIE_THETA}\,${PIE_FILL_ANGLE})\,${GOLD_R}\,22)\,0)"
    local PIE_G_EXPR="if(lte(${PIE_DIST}\,${PIE_R})\,if(lte(${PIE_THETA}\,${PIE_FILL_ANGLE})\,${GOLD_G}\,34)\,0)"
    local PIE_B_EXPR="if(lte(${PIE_DIST}\,${PIE_R})\,if(lte(${PIE_THETA}\,${PIE_FILL_ANGLE})\,${GOLD_B}\,52)\,0)"
    local PIE_A_EXPR="if(lte(${PIE_DIST}\,${PIE_R})\,255\,0)"

    CHAIN+="[${prev}]drawbox=x=$((RTEXT_INSET - 2)):y=$((PIE_LABEL_Y - 2)):w=6:h=6:color=${ACCENT}:t=fill[rgp1];"
    CHAIN+="[rgp1]drawtext=fontfile=${FONT}:text='SCIENCE INSTRUMENTS ON':fontcolor=white@0.55:fontsize=11:x=$((RTEXT_INSET + 14)):y=$((PIE_LABEL_Y - 8))[rgp2];"
    CHAIN+="color=c=black@0:s=${PIE_SIZE}x${PIE_SIZE}:r=1[pie_src];"
    CHAIN+="[pie_src]format=rgba,geq=r='${PIE_R_EXPR}':g='${PIE_G_EXPR}':b='${PIE_B_EXPR}':a='${PIE_A_EXPR}'[pie_img];"
    CHAIN+="[rgp2][pie_img]overlay=x=${PIE_X}:y=${PIE_Y}:shortest=1[rgp3];"
    CHAIN+="[rgp3]drawtext=fontfile=${FONT}:text='${VOY_INSTR_ON} / ${VOY_INSTR_TOTAL}':fontcolor=white:fontsize=18:x=$((PIE_X + PIE_SIZE / 2 - 20)):y=$((PIE_Y + PIE_SIZE / 2 - 10)):${SHADOW}[rgp4];"
    CHAIN+="[rgp4]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/voy_instr_caption.txt:fontcolor=white@0.5:fontsize=11:x=${RTEXT_INSET}:y=$((PIE_Y + PIE_SIZE + 12))[rgbase];"
    prev="rgbase"

    BASE_CHAIN="$CHAIN"
    FACT_END="$prev"
}

#############################################
# build_final_filter — CTA / ticker / watermark
#############################################
build_final_filter() {
    local total_duration="$1"
    local tail="$BASE_CHAIN"

    local CTA_CYCLE=240
    local CTA_SHOW=8
    local CTA_ALPHA="if(between(mod(t\,${CTA_CYCLE})\,0\,${CTA_SHOW})\,if(lt(mod(t\,${CTA_CYCLE})\,0.6)\,mod(t\,${CTA_CYCLE})/0.6\,if(gt(mod(t\,${CTA_CYCLE})\,${CTA_SHOW}-0.6)\,(${CTA_SHOW}-mod(t\,${CTA_CYCLE}))/0.6\,1))\,0)"
    local CTA_ENABLE="between(mod(t\,${CTA_CYCLE})\,0\,${CTA_SHOW})"
    # Alternate the subscribe CTA with the "ASK VOYAGER" trivia CTA every
    # other cycle, so the periodic call-to-action isn't the same line
    # each time.
    local CTA_EVEN="eq(mod(trunc(t/${CTA_CYCLE})\,2)\,0)"
    local CTA_ODD="eq(mod(trunc(t/${CTA_CYCLE})\,2)\,1)"

    local CTA_W=540
    local CTA_X=$((CENTER_X0 + (CENTER_W - CTA_W) / 2))
    local CTA_Y=640

    tail+="[${FACT_END}]drawbox=x=${CTA_X}:y=${CTA_Y}:w=${CTA_W}:h=43:color=black@0.75:t=fill:enable='${CTA_ENABLE}'[cta_bg];"
    tail+="[cta_bg]drawbox=x=${CTA_X}:y=${CTA_Y}:w=4:h=43:color=${ACCENT}:t=fill:enable='${CTA_ENABLE}'[cta_bar];"
    tail+="[cta_bar]drawbox=x=$((CTA_X + 22)):y=$((CTA_Y + 16)):w=11:h=11:color=${RED}:t=fill:enable='${CTA_ENABLE}'[cta_dot];"
    tail+="[cta_dot]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/cta.txt:fontcolor=white:fontsize=18:x=$((CTA_X + 40)):y=$((CTA_Y + 13)):alpha='${CTA_ALPHA}':enable='${CTA_EVEN}'[cta_sub0];"
    tail+="[cta_sub0]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/cta_trivia.txt:reload=1:fontcolor=${GOLD}:fontsize=18:x=$((CTA_X + 40)):y=$((CTA_Y + 13)):alpha='${CTA_ALPHA}':enable='${CTA_ODD}'[cta_final];"

    tail+="[cta_final]drawbox=x=0:y=680:w=1280:h=40:color=black@0.85:t=fill[tk1];"
    tail+="[tk1]drawbox=x=0:y=680:w=1280:h=2:color=${ACCENT}@0.9:t=fill[tk2];"
    tail+="[tk2]drawtext=fontfile=${FONT}:textfile=${ASSET_DIR}/ticker.txt:fontcolor=white:fontsize=17:borderw=2:bordercolor=black@0.6:y=695:x='w-mod(t*${TICKER_SPEED}\,text_w+w)'[tk3];"
    tail+="[tk3]drawbox=x=0:y=680:w=120:h=40:color=black@0.9:t=fill[tk4];"
    tail+="[tk4]drawbox=x=0:y=682:w=113:h=38:color=${RED}:t=fill[tk5];"
    tail+="[tk5]drawtext=fontfile=${FONT}:text='LIVE NOW':fontcolor=white:fontsize=15:x=13:y=695[tk6];"

    # Corner chip mirroring the LIVE NOW chip on the opposite side.
    tail+="[tk6]drawbox=x=1160:y=680:w=120:h=40:color=black@0.9:t=fill[tk7];"
    tail+="[tk7]drawbox=x=1163:y=682:w=113:h=38:color=${ACCENT}:t=fill[tk8];"
    tail+="[tk8]drawtext=fontfile=${FONT}:text='V G R   1':fontcolor=black:fontsize=15:x=1196:y=695[tk9];"

    tail+="[tk9]drawtext=fontfile=${FONT}:text='${CHANNEL_NAME}':fontcolor=white@0.45:fontsize=14:borderw=1.5:bordercolor=black@0.7:x=(w-text_w)/2:y=657:enable='not(${CTA_ENABLE})'[final]"

    echo "$tail"
}

#############################################
# is_image_url / get_image_local_path
#############################################
is_image_url() {
    local u="${1%%\?*}"
    local ext="${u##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
        jpg|jpeg|png|gif|bmp|webp) return 0 ;;
        *) return 1 ;;
    esac
}

get_image_local_path() {
    local url="$1"
    local base="${url##*/}"
    base="${base%%\?*}"
    local dest="img_cache_${base}"
    if [ ! -s "$dest" ]; then
        echo "Downloading image slide: $base" >&2
        if ! curl -sL --fail -o "$dest" "$url"; then
            rm -f "$dest"
            return 1
        fi
    fi
    echo "$dest"
    return 0
}

#############################################
# run_video — retry logic, image-slide handling, audio/panel-image
# inputs, ffmpeg invocation.
#############################################
run_video() {
    local url="$1"
    local attempt=1

    local is_image=false
    local stream_source="$url"
    if is_image_url "$url"; then
        is_image=true
        local local_img
        if ! local_img=$(get_image_local_path "$url"); then
            echo "WARNING: failed to download image slide '$url' — skipping it."
            return 1
        fi
        stream_source="$local_img"
        echo "Image slide: $url -> $stream_source"
    else
        if ! curl -sI --fail --max-time 10 "$url" >/dev/null 2>&1; then
            echo "WARNING: '$url' did not respond to a reachability check."
            if [ -n "$FALLBACK_IMAGE_URL" ]; then
                echo "Falling back to FALLBACK_IMAGE_URL for this rotation: $FALLBACK_IMAGE_URL"
                local fallback_local
                if fallback_local=$(get_image_local_path "$FALLBACK_IMAGE_URL"); then
                    url="$FALLBACK_IMAGE_URL"
                    is_image=true
                    stream_source="$fallback_local"
                else
                    echo "WARNING: fallback image also failed to download — proceeding with normal retries against the original URL."
                fi
            else
                echo "  (set FALLBACK_IMAGE_URL to skip straight to a fallback slide instead of retrying.)"
            fi
        fi
    fi

    prepare_video_content "$url"

    local duration
    if [ "$is_image" = true ]; then
        duration="$IMAGE_SLIDE_SECONDS"
        echo "Static image slide — showing for ${duration}s, locked to 30fps."
    else
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$url" 2>/dev/null || echo "")
        duration=${duration%.*}
        [[ "$duration" =~ ^[0-9]+$ ]] || duration=""
        if [ -n "$duration" ]; then
            echo "Probed duration: ${duration}s"
        else
            echo "Could not probe duration — continuing without it."
        fi
    fi

    local filter
    filter=$(build_final_filter "$duration")

    local AUDIO_INPUT_ARGS=()
    local AUDIO_MAP="2:a"
    if [ "$AUDIO_AVAILABLE" = true ]; then
        local this_audio="${AUDIO_LOCAL_FILES[$((AUDIO_COUNTER % NUM_AUDIO))]}"
        AUDIO_COUNTER=$((AUDIO_COUNTER + 1))
        echo "Background audio for this video: $this_audio"
        AUDIO_INPUT_ARGS=(-stream_loop -1 -i "$this_audio")
    else
        AUDIO_INPUT_ARGS=(-f lavfi -i "anullsrc=r=48000:cl=stereo")
    fi

    local PANEL_IMG_INPUT_ARGS=()
    if [ "$PANEL_IMAGES_AVAILABLE" = true ]; then
        PANEL_IMG_INPUT_ARGS=(-loop 1 -framerate 30 -i "$MID_PANEL_IMG")
    fi

    while [ "$attempt" -le "$MAX_RETRIES" ]; do
        echo "----------------------------------------"
        echo "Streaming (attempt ${attempt}/${MAX_RETRIES}):"
        echo "$url"
        echo "----------------------------------------"

        local MAIN_INPUT_ARGS=()
        local EXTRA_OUTPUT_ARGS=()
        if [ "$is_image" = true ]; then
            MAIN_INPUT_ARGS=(-loop 1 -framerate 30 -i "$stream_source")
            EXTRA_OUTPUT_ARGS=(-t "$duration")
        else
            MAIN_INPUT_ARGS=(-reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 -re -i "$stream_source")
        fi

        set +e
        ffmpeg \
        -hide_banner \
        -loglevel info \
        "${MAIN_INPUT_ARGS[@]}" \
        -loop 1 -framerate 30 -i "$DOT_MARKER" \
        "${AUDIO_INPUT_ARGS[@]}" \
        "${PANEL_IMG_INPUT_ARGS[@]}" \
        -filter_complex "$filter" \
        -map "[final]" \
        -map "$AUDIO_MAP" \
        -r 30 \
        -s 1280x720 \
        -c:v libx264 \
        -preset ultrafast \
        -tune zerolatency \
        -threads 2 \
        -profile:v high \
        -level 4.1 \
        -pix_fmt yuv420p \
        -b:v 3000k \
        -maxrate 3000k \
        -bufsize 6000k \
        -g 60 \
        -keyint_min 60 \
        -sc_threshold 0 \
        -c:a aac \
        -b:a 128k \
        -ar 48000 \
        -ac 2 \
        -shortest \
        "${EXTRA_OUTPUT_ARGS[@]}" \
        -f flv \
        "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}"
        local exit_code=$?
        set -e

        if [ "$exit_code" -eq 0 ]; then
            echo "Video finished normally."
            return 0
        fi

        echo "WARNING: ffmpeg exited with code ${exit_code} (attempt ${attempt}/${MAX_RETRIES})."
        attempt=$((attempt + 1))
        if [ "$attempt" -le "$MAX_RETRIES" ]; then
            echo "Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        else
            echo "ERROR: Max retries reached for this video. Moving on."
        fi
    done
    return 1
}

#############################################
# Stream loop
#############################################
IFS=',' read -ra RAW_URLS <<< "$VIDEO_URL"
URLS=()
for u in "${RAW_URLS[@]}"; do
    u="${u#"${u%%[![:space:]]*}"}"
    u="${u%"${u##*[![:space:]]}"}"
    [ -n "$u" ] && URLS+=("$u")
done
NUM_URLS=${#URLS[@]}
if [ "$NUM_URLS" -eq 0 ]; then
    echo "ERROR: VIDEO_URL contained no valid entries after parsing"
    exit 1
fi

if [ "$NUM_URLS" -gt 1 ]; then
    mapfile -t URLS < <(printf '%s\n' "${URLS[@]}" | shuf)
    echo "Shuffled playback order for this run:"
    for u in "${URLS[@]}"; do
        echo "  - $u"
    done
fi

while true; do
    for ((i = 0; i < NUM_URLS; i++)); do
        url="${URLS[$i]}"
        run_video "$url"
        echo "Loading next video..."
        echo ""
    done
done
