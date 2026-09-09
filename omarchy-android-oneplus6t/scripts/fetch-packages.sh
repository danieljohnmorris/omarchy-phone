#!/bin/bash
# Download the architecture-independent Omarchy packages into work/opkgs/ so
# phone-setup.sh can install them. Reads scripts/omarchy-packages.txt and
# resolves the current filename for each name from the repo database, so this
# keeps working as Omarchy releases new versions.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=${OMARCHY_REPO:-https://pkgs.omarchy.org/x86_64}
OUT="$HERE/../work/opkgs"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

echo "== reading $REPO/omarchy.db"
curl -sfL -o "$TMP/db.tar.gz" "$REPO/omarchy.db"
mkdir -p "$TMP/db" && tar -xzf "$TMP/db.tar.gz" -C "$TMP/db"

# name<TAB>arch<TAB>filename for every package in the database. The fields must
# be read as "the line after the %KEY%" marker; a plain grep also matches
# dependency lists in unrelated packages.
python3 - "$TMP/db" "$TMP/index" <<'PY'
import os, sys
db, out = sys.argv[1], sys.argv[2]
rows = []
for d in os.listdir(db):
    p = os.path.join(db, d, "desc")
    if not os.path.exists(p):
        continue
    lines = open(p).read().splitlines()
    f = {}
    for i, l in enumerate(lines):
        if l.startswith("%") and i + 1 < len(lines):
            f[l.strip("%")] = lines[i + 1]
    if "NAME" in f:
        rows.append("\t".join((f["NAME"], f.get("ARCH", "?"), f.get("FILENAME", "?"))))
open(out, "w").write("\n".join(rows))
PY

missing=""
while read -r name; do
  row=$(awk -F'\t' -v n="$name" '$1==n {print; exit}' "$TMP/index")
  if [ -z "$row" ]; then missing="$missing $name"; continue; fi
  arch=$(printf '%s' "$row" | cut -f2)
  file=$(printf '%s' "$row" | cut -f3)
  if [ "$arch" != "any" ]; then
    # Omarchy labelled these x86_64 from 4.0.3 even though several contain no
    # compiled code at all. Fetch and let repack-noarch.sh decide: it relabels
    # the portable ones and refuses anything with real binaries.
    if [ -f "$OUT/${file%-*.pkg.tar.zst}-any.pkg.tar.zst" ]; then
      echo "  have $name (repacked as any)"; continue
    fi
    echo "  try  $file ($arch, checking whether it is really portable)"
    curl -sfL -o "$TMP/$file" "$REPO/$file" || { missing="$missing $name"; continue; }
    if "$HERE/repack-noarch.sh" "$TMP/$file" >/dev/null 2>&1; then
      mv "$TMP/${file%-*.pkg.tar.zst}-any.pkg.tar.zst" "$OUT/"
      echo "       relabelled as any"
    else
      echo "       genuinely $arch, unavailable on this device"
    fi
    continue
  fi
  if [ -f "$OUT/$file" ]; then echo "  have $file"; continue; fi
  echo "  get  $file"
  curl -sfL -o "$OUT/$file" "$REPO/$file"
done < <(grep -vE '^\s*#|^\s*$' "$HERE/omarchy-packages.txt")

[ -n "$missing" ] && echo "NOT IN REPO:$missing"
echo "== $(ls "$OUT" | wc -l | tr -d ' ') packages in $OUT"
