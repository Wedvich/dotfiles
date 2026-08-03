#!/usr/bin/env bash
#
# Claude Code statusLine — Claude-specific situational awareness.
# Pure function of stdin (model, effort, context_window, rate_limits), so
# concurrent sessions never cross-contaminate: each invocation sees only its
# own session's payload.
#
# Layout (whole line gray; absolute context tokens turn yellow above 150k):
#   Opus 4.8 (high)  <ctx> 187k (19%)  <lim> 24% (5h) 41% (7d)
#
# Missing-data policy (hybrid): effort omits its parens when absent; context
# and rate-limit values that haven't arrived yet hold their slot with a gray "–".

set -o pipefail

input=$(cat)

# Extract everything in one jq pass. Humanisation and rounding happen here
# (float-friendly); bash only assembles and colours the result. Fields are
# joined with U+001F (unit separator) so empty values stay positional — unlike
# tab, read does not coalesce a non-whitespace delimiter.
read_fields() {
	jq -r '
		def human:
			if . == null or . == "" then ""
			elif . >= 1000000 then ((. / 100000 | round / 10 | tostring) + "M")
			elif . >= 1000 then ((. / 1000 | round | tostring) + "k")
			else (. | tostring) end;
		def pct:
			if . == null then "" else ([(. | round), 100] | min | tostring) end;
		[
			(.model.display_name // "" | tostring | sub(" *\\([^)]*[Cc]ontext\\)$"; "")),
			(.effort.level // "" | tostring),
			(.context_window.total_input_tokens // "" | tostring),
			(.context_window.total_input_tokens | human),
			(.context_window.used_percentage | pct),
			(.rate_limits.five_hour.used_percentage | pct),
			(.rate_limits.seven_day.used_percentage | pct)
		] | join("")
	' <<<"$input"
}

IFS=$'\037' read -r model effort tok_raw tok_human ctx_pct h5 d7 < <(read_fields)

GRAY=$'\033[38;5;247m'
RST=$'\033[0m'
YEL=$'\033[33m'
ICON_CTX=$'\U000F01BC'   # nf-md-database
ICON_LIM=$'\U000F078C'   # nf-md-timer-sand-full

line="${GRAY}${model}"
[[ -n $effort ]] && line+=" (${effort})"

line+=" · ${ICON_CTX} "
if [[ -z $tok_human ]]; then
	line+="–"
else
	if [[ -n $tok_raw && $tok_raw -gt 150000 ]]; then
		line+="${RST}${YEL}${tok_human}${RST}${GRAY}"
	else
		line+="${tok_human}"
	fi
	[[ -n $ctx_pct ]] && line+=" (${ctx_pct}%)"
fi

line+=" · ${ICON_LIM} "
# A maxed-out window is the one thing worth interrupting the gray for.
fmt_pct() {
	[[ -z $1 ]] && { printf '–'; return; }
	if [[ $1 == 100 ]]; then
		printf '%s' "${RST}${YEL}${1}%${RST}${GRAY}"
	else
		printf '%s%%' "$1"
	fi
}
line+="$(fmt_pct "$h5") (5h) $(fmt_pct "$d7") (7d)"

line+="${RST}"
printf '%s' "$line"
