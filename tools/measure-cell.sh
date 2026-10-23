#!/usr/bin/env bash
# Measure one hybrid-search vector cell (model, dimension, vector store)
# against this worktree's own container: reindex frus-data-jinks, time five
# paraphrase queries, append the cell to $RESULTS.
# Usage: tools/measure-cell.sh <model> <dimension> <vector-store>
# Needs the frus-data-jinks collection.xconf at $XCONF_SRC.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODEL="${1:?model}"
DIM="${2:?dim}"
STORE="${3:?store}"  # db|lucene
SERVER="$(grep -E '^EXISTDB_SERVER=' .env | cut -d= -f2-)"
XCONF_SRC="${XCONF_SRC:-/tmp/frus-collection.xconf.xml}"
XCONF_CELL=/tmp/frus-collection.xconf.cell.xml
RESULTS="${RESULTS:-$ROOT/build/semantic-search-workload-results.json}"

python3 - <<PY
from pathlib import Path
import re
text = Path("$XCONF_SRC").read_text()
text = re.sub(
    r'vector-store="[^"]*"',
    'vector-store="$STORE"',
    text,
    count=1,
)
text = re.sub(
    r'(<vector-field name="hsg-embedding"[^>]*?dimension=")[^"]*(")',
    r'\g<1>$DIM\2',
    text,
    count=1,
)
text = re.sub(
    r'(<vector-field name="hsg-embedding"[^>]*?model=")[^"]*(")',
    r'\g<1>$MODEL\2',
    text,
    count=1,
)
Path("$XCONF_CELL").write_text(text)
Path("/tmp/collection.xconf").write_text(text)
print("xconf cell written")
print([line.strip() for line in text.splitlines() if "vector-store" in line or "hsg-embedding" in line])
PY

# Upload xconf (basename must be collection.xconf)
xst --config .xstrc upload /tmp/collection.xconf /db/system/config/db/apps/frus-data-jinks/

# Patch EMBED_MODEL in a temp copy and upload
CELL_XQ=/tmp/search.xqm
MODEL="$MODEL" python3 - <<'PY'
from pathlib import Path
import os, re
model = os.environ["MODEL"]
p = Path("modules/templates/search.xqm")
text = p.read_text()
text2, n = re.subn(
    r'(declare variable \$srch:EMBED_MODEL as xs:string := ")[^"]*(";)',
    rf'\g<1>{model}\2',
    text,
    count=1,
)
assert n == 1, n
Path("/tmp/search.xqm").write_text(text2)
print("embed model patched to", model)
PY
xst --config .xstrc upload "$CELL_XQ" /db/apps/hsg-jinks/modules/templates/

# Reindex all (curl REST — xst clients can hit header timeouts on long reindexes)
t0=$(date +%s)
code=$(curl -sS -u 'admin:' --max-time 3600 -o /tmp/reindex-out.xml -w '%{http_code}' \
  -G --data-urlencode '_query=xquery version "3.1"; xmldb:reindex("/db/apps/frus-data-jinks", "all")' \
  "$SERVER/rest/db")
t1=$(date +%s)
REINDEX_S=$((t1 - t0))
echo "reindex_http=$code reindex_s=$REINDEX_S"
if [ "$code" != "200" ]; then
  echo "reindex failed:"; head -c 500 /tmp/reindex-out.xml; echo; exit 1
fi


# vector.dbx size (still present under store=lucene; note in report)
VDBX=0
if VDBX=$(docker compose -f .devcontainer/docker-compose.yml exec -T existdb wc -c /exist/data/vector.dbx 2>/dev/null | awk '{print $1}'); then
  :
else
  VDBX=0
fi
VDBX=${VDBX:-0}
echo "vector_dbx_bytes=$VDBX"

# Smoke 5 paraphrase queries (keyword + hybrid latency)
SERVER="$SERVER" python3 - <<'PY'
import json, os, time, urllib.parse, urllib.request
from pathlib import Path
qs = [
    "meeting between Reagan and Gorbachev in Iceland",
    "missile defense research program nicknamed Star Wars",
    "reducing medium-range nuclear weapons in Europe",
    "Soviet withdrawal from the war in Afghanistan",
    "discussions of human rights with Moscow",
]
base = os.environ["SERVER"] + "/apps/hsg-jinks/search"
rows = []
for q in qs:
    for mode in ("keyword", "hybrid"):
        url = f"{base}?q={urllib.parse.quote(q)}&within=documents&mode={mode}"
        t0 = time.time()
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=120) as r:
            code = r.status
            _ = r.read(256)
        ms = int((time.time() - t0) * 1000)
        rows.append({"q": q, "mode": mode, "http": code, "ms": ms})
        print(f"{mode} {ms}ms {code} :: {q[:60]}")
Path("/tmp/cell-query-latencies.json").write_text(json.dumps(rows, indent=2))
PY

# Append cell to results JSON
python3 - <<PY
import json
from pathlib import Path
p = Path("$RESULTS")
p.parent.mkdir(parents=True, exist_ok=True)
data = json.loads(p.read_text()) if p.exists() else {}
cell = {
  "model": "$MODEL",
  "dimension": int("$DIM"),
  "vector_store": "$STORE",
  "embedding": "local",
  "reindex_seconds": int("$REINDEX_S"),
  "vector_dbx_bytes": int("$VDBX" or 0),
  "query_latencies": json.loads(Path("/tmp/cell-query-latencies.json").read_text()),
  "notes": "FRUS sample frus1981-88v05; reindex mode=all"
}
data.setdefault("cells", []).append(cell)
p.write_text(json.dumps(data, indent=2) + "\n")
print("recorded cell", cell["model"], cell["vector_store"])
PY
