#!/usr/bin/env bash
# Guarded Netlify deploy (adapted from german-worksheets).
# Netlify limits deploys to 3 per minute and 100 per day (account-wide).
# Logs each successful deploy to .deploy-log and refuses/warns before limits.
#
# Usage:  ./deploy.sh           (deploys --prod)
#         ./deploy.sh --draft   (passes extra args through to `netlify deploy`)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/.deploy-log"
touch "$LOG"
now=$(date +%s)

awk -v cutoff=$((now-86400)) 'NF && $1>=cutoff' "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
min_count=$(awk -v c=$((now-60))  'NF && $1>=c' "$LOG" | wc -l | tr -d ' ')
day_count=$(awk 'NF' "$LOG" | wc -l | tr -d ' ')

echo "▶ Deploy budget — last 60s: ${min_count}/3   ·   last 24h: ${day_count}/100"

if [ "$min_count" -ge 3 ]; then
  newest=$(tail -n1 "$LOG")
  wait=$(( 60 - (now - newest) ))
  echo "⛔ Would exceed Netlify's 3-deploys/minute limit. Wait ~${wait}s and retry."
  exit 1
fi
if [ "$day_count" -ge 90 ]; then
  echo "⚠️  Approaching the 100-deploys/day limit (${day_count}/100). Deploy sparingly."
fi

# Filled in when the Netlify site is created (needed only for the 403 fallback).
SITE_ID=""

if [ "$#" -ne 0 ]; then
  echo "▶ Running: netlify deploy $*"
  netlify deploy "$@" && echo "$now" >> "$LOG" && echo "✅ Deployed and logged."
  exit $?
fi

echo "▶ Running: netlify deploy --prod"
if netlify deploy --prod; then
  echo "$now" >> "$LOG"; echo "✅ Deployed and logged."; exit 0
fi

if [ -z "$SITE_ID" ]; then
  echo "❌ --prod failed and SITE_ID not set; fill SITE_ID in deploy.sh for the draft→promote fallback."
  exit 1
fi
echo "⚠️  Direct --prod failed (likely 403). Falling back: draft → promote via API…"
did=$(netlify deploy --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('deploy_id',''))" 2>/dev/null)
if [ -z "$did" ]; then echo "❌ Draft deploy failed too — wait a few minutes and retry."; exit 1; fi
state=$(netlify api restoreSiteDeploy --data "{\"site_id\":\"$SITE_ID\",\"deploy_id\":\"$did\"}" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null)
if [ "$state" = "ready" ]; then
  echo "$now" >> "$LOG"; echo "✅ Promoted draft $did to production (state: ready). Logged."
else
  echo "❌ Promotion failed (state: '$state'). Try again later."; exit 1
fi
