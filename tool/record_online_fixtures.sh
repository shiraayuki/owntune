#!/usr/bin/env bash
# Records the YouTube and SoundCloud responses in test/fixtures/online/ that
# the parser and source tests run against. Re-run only when a site changes
# its responses (and then fix the parsers). Requires curl and python3.
# Makes 4 YouTube requests and 5 or more SoundCloud requests (the home page,
# the page's scripts from the last to the first until one holds the
# client_id, then search, track, stream and playlist).
# `--soundcloud-only` records only SoundCloud (the YouTube fixtures stay as
# they are), `--scrub-only` re-applies the scrub to the committed files,
# without requests.
#
# The YouTube values must match lib/data/sources/youtube/innertube_clients.dart,
# the SoundCloud values lib/data/sources/soundcloud/soundcloud_api.dart.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/test/fixtures/online"
mkdir -p "$out"

if [[ "${1:-}" != "--scrub-only" && "${1:-}" != "--soundcloud-only" ]]; then

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

if [[ "${1:-}" != "--scrub-only" ]]; then

# SoundCloud: the same steps the app takes. The raw answers (with the real
# client_id and signed URLs) only live in a temporary folder; what lands in
# $out is trimmed and scrubbed below.
sc_ua='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
sc_api='https://api-v2.soundcloud.com'
# The patterns of soundcloud_api.dart.
sc_script_re='<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"'
sc_id_re='client_id\s*:\s*"([A-Za-z0-9]{32})"'
raw="$(mktemp -d)"
trap 'rm -rf "$raw"' EXIT
sc() { curl -sf -A "$sc_ua" "$@"; }

sc 'https://soundcloud.com/' > "$raw/home.html"

# The scripts from the last to the first, until one holds the client_id.
client_id=""
while IFS= read -r src; do
  sc "$src" > "$raw/script.js"
  client_id="$(python3 -I -c 'import re,sys; m=re.search(sys.argv[2], open(sys.argv[1], encoding="utf-8").read()); print(m.group(1) if m else "")' "$raw/script.js" "$sc_id_re")"
  [[ -n "$client_id" ]] && break
done < <(python3 -I -c 'import re,sys; [print(u) for u in reversed(re.findall(sys.argv[2], open(sys.argv[1], encoding="utf-8").read()))]' "$raw/home.html" "$sc_script_re")
[[ -n "$client_id" ]] || { echo "no client_id found in the SoundCloud scripts" >&2; exit 1; }

sc "$sc_api/search/tracks?q=linkin%20park%20numb&client_id=$client_id&limit=20&app_locale=en" > "$raw/search.json"

# A free track from that search: an unencrypted hls aac_160k transcoding that
# is not snipped, policy ALLOW or MONETIZE.
track_id="$(python3 -I - "$raw/search.json" <<'PY'
import json
import sys

for t in json.load(open(sys.argv[1], encoding="utf-8"))["collection"]:
    if t.get("kind") != "track" or t.get("policy") not in ("ALLOW", "MONETIZE"):
        continue
    for x in t.get("media", {}).get("transcodings", []):
        if (x["preset"] == "aac_160k" and x["format"]["protocol"] == "hls"
                and not x["snipped"]):
            print(t["id"])
            sys.exit(0)
sys.exit("no free track in the search")
PY
)"

sc "$sc_api/tracks/$track_id?client_id=$client_id&app_locale=en" > "$raw/track.json"

transcoding="$(python3 -I - "$raw/track.json" <<'PY'
import json
import sys

t = json.load(open(sys.argv[1], encoding="utf-8"))
x = next(x for x in t["media"]["transcodings"]
         if x["preset"] == "aac_160k" and x["format"]["protocol"] == "hls")
print(x["url"] + " " + t["track_authorization"])
PY
)"
sc "${transcoding%% *}?client_id=$client_id&track_authorization=${transcoding#* }" > "$raw/stream.json"

playlist="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$raw/stream.json")"
sc "$playlist" > "$raw/playlist.m3u8"

# Trim: the home page to its script tags, the script to ~200 characters
# around the client_id.
python3 -I - "$raw" "$out" "$sc_id_re" <<'PY'
import re
import shutil
import sys

raw, out, id_re = sys.argv[1:4]
home = open(f"{raw}/home.html", encoding="utf-8").read()
tags = re.findall(r"<script\b[^>]*\bsrc=[^>]*>", home)
open(f"{out}/soundcloud_home.html", "w", encoding="utf-8").write(
    "".join(f"{tag}</script>\n" for tag in tags))
script = open(f"{raw}/script.js", encoding="utf-8").read()
m = re.search(id_re, script)
open(f"{out}/soundcloud_script.js", "w", encoding="utf-8").write(
    script[max(0, m.start() - 100):m.end() + 100] + "\n")
for name in ("search.json", "track.json", "stream.json", "playlist.m3u8"):
    shutil.copy(f"{raw}/{name}", f"{out}/soundcloud_{name}")
PY

fi

# Nothing personal or signed may be committed (the repo is public): stream
# and preview URLs carry the caller's IP address, visitorData identifies
# the session. Replace them in every file, keep the structure.
python3 -I - "$out"/ytmusic_*.json "$out"/youtube_*.json "$out"/player_*.json <<'PY'
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

# SoundCloud: the client_id is only ever scraped at runtime and must never be
# committed. The track_authorization and every signed query string (the
# stream URLs on *.soundcloud.cloud, any query on *.sndcdn.com) go too.
python3 -I - "$out"/soundcloud_* <<'PY'
import json
import re
import sys

CLIENT_ID = re.compile(r'(client_id\s*[:=]\s*"?)[A-Za-z0-9]{32}')
AUTH = re.compile(r'("track_authorization"\s*:\s*)"[^"]*"')
QUERY = re.compile(
    r'(https://[\w.-]+\.(?:soundcloud\.cloud|sndcdn\.com)/[^\s"\'<>?]*)\?[^\s"\'<>]*')

for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    text = CLIENT_ID.sub(r"\1FIXTURECLIENTIDFIXTURECLIENTID00", text)
    text = AUTH.sub(r'\1"FIXTURE"', text)
    text = QUERY.sub(r"\1?fixture", text)
    if path.endswith(".json"):
        text = json.dumps(json.loads(text), ensure_ascii=False, separators=(",", ":"))
    open(path, "w", encoding="utf-8").write(text)
PY

echo "Online fixtures written to $out"
