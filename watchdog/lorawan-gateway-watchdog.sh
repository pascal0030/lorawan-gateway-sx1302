#!/usr/bin/env bash
# Restart the gateway container when the concentrator has stopped receiving.
#
# The packet forwarder keeps reporting a perfectly healthy server link even when
# the SX1302 has gone deaf: the RF front-end calibration is done once, inside
# lgw_start(), and a supply brown-out can invalidate it while the digital side
# keeps running. Nothing inside the container notices, and "--restart always"
# never fires because the process does not exit. So watch the stat reports from
# the outside and restart when no uplink has been heard for a while.
#
# A Docker HEALTHCHECK cannot do this job: the stat reports go to stdout (into
# Docker's log), not to a file the container can read back, and Docker does not
# restart a container just because it is unhealthy.
set -euo pipefail

# Defaults are deliberately conservative: a genuinely quiet gateway must not be
# restarted in a loop. A 4h window with a single uplink would still have caught
# the failure this was written for (43h of logs, one packet in all of them).
# If your sensors report often, shorten WINDOW or raise MIN_UPLINKS to notice
# sooner - but keep MIN_UPLINKS below the quietest stretch you expect, or one
# stray packet from a neighbour's network will mask a deaf receiver.
IMAGE="${IMAGE:-ghcr.io/pascal0030/lorawan-gateway-sx1302:latest}"
WINDOW="${WINDOW:-4h}"              # how far back to look
MIN_UPLINKS="${MIN_UPLINKS:-1}"     # restart if fewer than this many uplinks in WINDOW
MIN_REPORTS="${MIN_REPORTS:-400}"   # stat reports needed before judging (one per 30s)

CID=$(docker ps -q --filter "ancestor=$IMAGE" | head -1)
if [ -z "$CID" ]; then
  echo "watchdog: no running container for $IMAGE"
  exit 0
fi

logs=$(docker logs --since "$WINDOW" "$CID" 2>&1 || true)
reports=$(grep -c '"rxnb":' <<<"$logs" || true)
uplinks=$(grep -o '"rxnb":[0-9]*' <<<"$logs" | grep -vc '^"rxnb":0$' || true)

# Too few reports means the container has not been up for the whole window yet.
# Judging it now would restart it before it had a chance to hear anything.
if [ "$reports" -lt "$MIN_REPORTS" ]; then
  echo "watchdog: only $reports stat reports in $WINDOW, too early to judge"
  exit 0
fi

if [ "$uplinks" -lt "$MIN_UPLINKS" ]; then
  echo "watchdog: $uplinks uplinks in $WINDOW (need $MIN_UPLINKS) - restarting $CID"
  docker restart "$CID"
  exit 0
fi

echo "watchdog: $uplinks uplinks in $WINDOW, concentrator is hearing traffic"
