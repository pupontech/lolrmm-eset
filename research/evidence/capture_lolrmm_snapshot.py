from collections import Counter
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
from urllib.request import Request, urlopen

URL = "https://lolrmm.io/api/rmm_tools.json"
CAPTURED_UTC_DATE = datetime.now(timezone.utc).date().isoformat()
OUT = Path(__file__).with_name(f"lolrmm-rmm_tools-{CAPTURED_UTC_DATE}.json")

if OUT.exists():
    raise SystemExit(f"Refusing to overwrite existing evidence snapshot: {OUT}")

request = Request(URL, headers={"User-Agent": "LOLRMM-ESET-Phase0-Research/1.0"})
with urlopen(request, timeout=30) as response:
    if response.status != 200:
        raise SystemExit(f"Unexpected HTTP status: {response.status}")
    body = response.read()

records = json.loads(body)
if not isinstance(records, list) or any(not isinstance(record, dict) for record in records):
    raise SystemExit("Expected a JSON array containing only object records")

with OUT.open("xb") as snapshot:
    snapshot.write(body)

print(f"url={URL}")
print("status=200")
print(f"captured_utc_date={CAPTURED_UTC_DATE}")
print(f"records={len(records)}")
print(f"category_counts={dict(Counter(str(record.get('Category')) for record in records))}")
print(f"bytes={len(body)}")
print(f"sha256={sha256(body).hexdigest()}")
print(f"snapshot={OUT}")
