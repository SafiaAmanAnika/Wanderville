"""Read-only comparison against the exact client in the supplied archive."""

import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
manifest = json.loads((root / "docs/CLIENT_SHA256.json").read_text())
client = root / "code/client"
actual = {
    p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in client.rglob("*")
    if p.is_file()
}
changed = [name for name, digest in manifest.items() if actual.get(name) != digest]
added = sorted(set(actual) - set(manifest))
if changed or added:
    print(json.dumps({"changed_or_missing": changed, "added": added}, indent=2))
    raise SystemExit(1)
print(f"PASS: all {len(actual)} client files are byte-for-byte unchanged.")
