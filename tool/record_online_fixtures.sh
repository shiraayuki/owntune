#!/usr/bin/env bash
# Records the YouTube responses in test/fixtures/online/ that the parser and
# source tests run against. Re-run only when YouTube changes its responses
# (and then fix the parsers). Requires curl and python3. Makes 4 requests.
# `--scrub-only` re-applies the scrub to the committed files, without
# requests.
#
# The client values must match lib/data/sources/youtube/innertube_clients.dart.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/test/fixtures/online"
mkdir -p "$out"

if [[ "${1:-}" != "--scrub-only" ]]; then

vision_ua='Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'

curl -sf 'https://music.youtube.com/youtubei/v1/search?prettyPrint=false' \
  -H 'Content-Type: application/json' \
  -d '{"context":{"client":{"clientName":"WEB_REMIX","clientVersion":"1.20260707.12.00","hl":"en","gl":"US"}},"query":"linkin park numb","params":"EgWKAQIIAWoKEAoQAxAEEAkQBQ=="}' \
  > "$out/ytmusic_search.json"

curl -sf 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false' \
  -H 'Content-Type: application/json' \
  -d '{"context":{"client":{"clientName":"WEB","clientVersion":"2.20260708.00.00","hl":"en","gl":"US"}},"query":"linkin park numb","params":"EgIQAfABAQ=="}' \
  > "$out/youtube_search.json"

visitor="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["responseContext"]["visitorData"])' "$out/ytmusic_search.json")"

player() { # $1 = visitorData or empty
  local ctx='"clientName":"VISIONOS","clientVersion":"1.02","deviceMake":"Apple","deviceModel":"RealityDevice17,1","osName":"visionOS","osVersion":"26.5.23O471","hl":"en","gl":"US","userAgent":"'"$vision_ua"'"'
  local headers=(-H 'Content-Type: application/json' -H "User-Agent: $vision_ua"
    -H 'X-YouTube-Client-Name: 101' -H 'X-YouTube-Client-Version: 1.02'
    -H 'Origin: https://www.youtube.com')
  if [[ -n "$1" ]]; then
    ctx="$ctx,\"visitorData\":\"$1\""
    headers+=(-H "X-Goog-Visitor-Id: $1")
  fi
  curl -sf 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false' "${headers[@]}" \
    -d '{"context":{"client":{'"$ctx"'}},"videoId":"5qZQEq_C3vc","contentCheckOk":true,"racyCheckOk":true}'
}

player "$visitor" > "$out/player_ok.json"
player "" > "$out/player_login_required.json"

fi

# Nothing personal or signed may be committed (the repo is public): stream
# and preview URLs carry the caller's IP address, visitorData identifies
# the session. Replace them in every file, keep the structure.
python3 -I - "$out"/*.json <<'PY'
import json
import re
import sys

URL = re.compile(r"https?://[^\s\"]*googlevideo\.com[^\s\"]*")
IP = re.compile(r"([?&])ip=[^&\"]*")
HOST = re.compile(r"[\w.-]+\.googlevideo\.com")


def scrub(node):
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            if k == "visitorData" and isinstance(v, str):
                out[k] = "CgtGSVhUVVJFVklTSVQ%3D"
            elif k == "value" and node.get("key") == "visitor_data":
                out[k] = "CgtGSVhUVVJFVklTSVQ%3D"
            elif k == "url" and isinstance(v, str) and "googlevideo" in v and "itag" in node:
                out[k] = f"https://example.invalid/videoplayback?itag={node['itag']}"
            else:
                out[k] = scrub(v)
        return out
    if isinstance(node, list):
        return [scrub(v) for v in node]
    if isinstance(node, str):
        node = URL.sub("https://example.invalid/media", node)
        node = HOST.sub("example.invalid", node)
        return IP.sub(r"\1ip=0.0.0.0", node)
    return node


for path in sys.argv[1:]:
    data = scrub(json.load(open(path)))
    json.dump(data, open(path, "w"), ensure_ascii=False, separators=(",", ":"))
PY

echo "Online fixtures written to $out"
