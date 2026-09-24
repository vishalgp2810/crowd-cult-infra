import json
from pathlib import Path
p = Path("/opt/crowd-cult/crowd-cult-backend/config/development.json")
d = json.loads(p.read_text())
d["DATABASE"]["DB_HOST"] = "localhost"
p.write_text(json.dumps(d, indent=2) + "\n")
print("ok", d["DATABASE"]["DB_HOST"], d["DATABASE"]["DB_PORT"])
