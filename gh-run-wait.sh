#!/usr/bin/env bash
# Wait for a GitHub Actions run to finish, polling with conditional requests.
#
# Usage: gh-run-wait <owner>/<repo> <run-id> [interval-seconds, default 30]
# Exit:  0 the run succeeded, 1 it finished any other way, 2 it can't be watched
#        (bad arguments, unknown run, no access).
#
# Why not `gh run watch`: each of its ticks spends about 3 REST requests (run, jobs,
# annotations), and every session on the machine shares one 5000/hour budget per
# GitHub user. At its 3s default one watcher burns 2-3k an hour; a deploy parked at an
# approval gate keeps that up for hours. Here an unchanged run answers 304 Not
# Modified, which GitHub doesn't count, so a long wait costs one request per change.
set -u

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: gh-run-wait <owner>/<repo> <run-id> [interval-seconds]" >&2
  exit 2
fi
repo=$1 run=$2 interval=${3:-30}
case $repo in */*) ;; *) echo "gh-run-wait: repo must be <owner>/<repo>" >&2; exit 2;; esac
case $run in '' | *[!0-9]*) echo "gh-run-wait: run id must be a number" >&2; exit 2;; esac
case $interval in '' | *[!0-9]* | 0) echo "gh-run-wait: interval must be a positive number" >&2; exit 2;; esac

# macOS has no `timeout`; a stalled call must not hold the wait open.
t() { perl -e 'alarm shift; exec @ARGV' 60 "$@"; }

header() { printf '%s\n' "$head" | grep -i -m1 "^$1:" | sed -E 's/^[^:]+: *//'; }

etag='' last=''
while :; do
  cond=()
  [ -n "$etag" ] && cond=(-H "If-None-Match: $etag")
  # -i puts the status line and headers first. On a 304 there's no body, so --jq fails
  # and gh exits 1: the status line, not the exit code, says what happened.
  # ${cond[@]+...}: bash 3.2 (macOS /bin/bash) calls an empty array unbound under -u.
  out=$(t gh api -i ${cond[@]+"${cond[@]}"} "repos/$repo/actions/runs/$run" \
    --jq '[.status, (.conclusion // ""), .html_url] | join(" ")' 2>/dev/null)
  head=$(printf '%s\n' "$out" | awk '{ sub(/\r$/, "") } /^$/ { exit } { print }')
  code=$(printf '%s\n' "$head" | head -1 | awk '{print $2}')

  case $code in
    304) ;;
    200)
      etag=$(header etag)
      body=$(printf '%s\n' "$out" | tail -1)
      read -r status conclusion url <<<"$body"
      [ "$status" != "$last" ] && echo "$(date -u +%H:%M:%SZ) $status" && last=$status
      if [ "$status" = completed ]; then
        echo "conclusion: ${conclusion:-none} $url"
        [ "$conclusion" = success ] && exit 0
        exit 1
      fi
      ;;
    403 | 429)
      # Rate limited: waiting out the limit is the only thing that doesn't make it
      # worse. Retry-After is the secondary limit's; the reset time the primary's.
      wait=$(header retry-after)
      if [ -z "$wait" ] && [ "$(header x-ratelimit-remaining)" = 0 ]; then
        wait=$(($(header x-ratelimit-reset) - $(date +%s) + 5))
        [ "$wait" -lt 5 ] && wait=5
      fi
      if [ -z "$wait" ]; then
        echo "gh-run-wait: HTTP $code, not a rate limit (no access?)" >&2
        exit 2
      fi
      echo "$(date -u +%H:%M:%SZ) rate limited, waiting ${wait}s" >&2
      sleep "$wait"
      continue
      ;;
    404 | 401)
      echo "gh-run-wait: HTTP $code for run $run in $repo" >&2
      exit 2
      ;;
    *) ;; # a timeout, a network error or a 5xx: try again next tick
  esac
  sleep "$interval"
done
