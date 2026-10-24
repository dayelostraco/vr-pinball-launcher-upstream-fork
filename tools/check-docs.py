"""Check repository-local Markdown links without network access or dependencies."""
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, text=True
).splitlines()
errors = []
checked = 0
for name in sorted(set(files)):
    # Vendored notices and historical implementation plans are retained verbatim.
    if not name.endswith(".md") or name.startswith(("licenses/", "docs/superpowers/")):
        continue
    path = root / name
    if not path.is_file():
        continue
    text = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8-sig"), flags=re.S)
    for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", text):
        target = match.group(1).strip("<>")
        parts = urlsplit(target)
        if parts.scheme or parts.netloc or not parts.path:
            continue
        resolved = (path.parent / unquote(parts.path)).resolve()
        if not resolved.exists():
            errors.append(f"{name}: missing link target {target}")
        checked += 1
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Documentation links: {checked} local targets passed.")
