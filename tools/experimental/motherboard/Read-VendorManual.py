"""Extract public vendor PDF evidence; never execute content from the document."""
import json
import re
import sys
from pathlib import Path
from pypdf import PdfReader

path = Path(sys.argv[1])
reader = PdfReader(path)
text = "\n".join(page.extract_text() or "" for page in reader.pages[:200])
path.with_suffix(".txt").write_text(text, encoding="utf-8")
plain = re.sub(r"\s+", " ", text)
excerpts = re.findall(
    r".{0,80}(?:support|compatib|Windows|silent|command.line|Live Update|BIOS|Norton|McAfee|antivirus|driver).{0,180}",
    plain, re.IGNORECASE,
)
targeted = re.findall(r".{0,100}(?:Live Update|silent|command.line|Norton|McAfee|antivirus).{0,250}", plain, re.IGNORECASE)
print(json.dumps({"pages": len(reader.pages), "excerpts": list(dict.fromkeys(targeted + excerpts))[:55]}))
