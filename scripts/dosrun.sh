#!/bin/sh
# dosrun.sh DIR BATCH [minutes]: runs BATCH (a file in DIR) in DOSBox-X with
# DIR as drive D, the 1988 Microsoft tools (MIT, from the pinned MS-DOS
# repository) as drive T, and no screen. BATCH writes its own logs to D:.
set -eu
DIR=$(cd "$1" && pwd); BAT=$2; MIN=${3:-10}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS="$ROOT/upstream/msdos/v4.0/src/TOOLS"
CONF=$(mktemp --suffix=.conf)
cat > "$CONF" <<EOF
[sdl]
output=surface
[dosbox]
memsize=16
quit warning=false
startbanner=false
[cpu]
core=dynamic
cputype=auto
cycles=max
[dos]
ver=3.3
[autoexec]
mount d "$DIR"
mount t "$TOOLS"
D:
CALL D:\\$BAT
exit
EOF
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout --kill-after=10s ${MIN}m \
  dosbox-x -conf "$CONF" -nopromptfolder -silent > "$DIR/dosbox.out" 2>&1 || true
rm -f "$CONF"
