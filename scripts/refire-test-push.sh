#!/usr/bin/env bash
# Phase 3 push test (2026-08-03): fire send-push on nwqn at the tech test
# account, trying each plausible user_id format in turn. Run AFTER the
# installed PWA has been opened fresh (v496+ re-mints the subscription).
# Stops at the first variant that reports a delivery.
set -euo pipefail

URL='https://nwqnakoongrorbwnrqzc.supabase.co/functions/v1/send-push'
ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53cW5ha29vbmdyb3Jid25ycXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzNzczMjUsImV4cCI6MjA5ODk1MzMyNX0.TFFMlg9VjB0cyJwbgmVbeatFYQFaF1Ri0nrH0GwhHJs'

for uid in '+14804402314' '14804402314' '4804402314'; do
  echo "── user_id: $uid"
  curl -s -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "apikey: $ANON" \
    -H "Authorization: Bearer $ANON" \
    -d "{\"user_id\":\"$uid\",\"title\":\"Push test 💅\",\"body\":\"If you can read this, Phase 3 is done.\",\"url\":\"/app/\",\"tag\":\"phase3-test\"}"
  echo
done
