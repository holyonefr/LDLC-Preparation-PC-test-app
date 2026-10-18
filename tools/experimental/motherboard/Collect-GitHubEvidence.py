"""Collect the actual run/job state and small JSON evidence emitted by this workflow."""
import argparse
import base64
import json
import gzip
import subprocess
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("run_id", type=int)
parser.add_argument("--repo", default="holyonefr/LDLC-Preparation")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
base = f"repos/{args.repo}"


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


run = api(f"{base}/actions/runs/{args.run_id}")
report = {"run": {k: run[k] for k in ("id", "head_sha", "status", "conclusion", "html_url")}, "jobs": []}
for job in api(f"{base}/actions/runs/{args.run_id}/jobs")["jobs"]:
    check = job["check_run_url"].rsplit("/", 1)[1]
    pages = []
    for page in range(1, 101):
        values = api(f"{base}/check-runs/{check}/annotations?per_page=100&page={page}")
        pages.append(values)
        if len(values) < 100:
            break
    else:
        raise RuntimeError("Annotation pagination limit exceeded")
    chunks = defaultdict(list)
    evidence = []
    legacy = []
    for annotation in (item for page in pages for item in page):
        title, message = annotation["title"], annotation["message"]
        if title == "OEM evidence chunk":
            part = json.loads(message)
            chunks[part["Id"]].append(part)
        elif title in {"OEM experiment tests", "OEM official source", "OEM real inventory", "OEM real download"}:
            try:
                legacy.append({"kind": title, "data": json.loads(message)})
            except json.JSONDecodeError:
                # Older runs contain long truncated lines. They are not valid evidence JSON.
                legacy.append({"kind": title, "error": "truncated legacy annotation"})
    incomplete = []
    for group in chunks.values():
        group.sort(key=lambda x: x["Index"])
        if len(group) != group[0]["Count"] or [x["Index"] for x in group] != list(range(len(group))):
            incomplete.append({"kind": group[0]["Kind"], "expected": group[0]["Count"], "received": len(group)})
            continue
        raw = base64.b64decode("".join(x["Data"] for x in group), validate=True)
        if group[0].get("Codec") == "gzip-base64":
            raw = gzip.decompress(raw)
        evidence.append({"id": group[0]["Id"], "kind": group[0]["Kind"], "data": json.loads(raw.decode("utf-8"))})
    report["jobs"].append({k: job[k] for k in ("id", "name", "status", "conclusion", "steps")})
    report["jobs"][-1].update(evidence=evidence, incomplete=incomplete, legacy=legacy if not chunks or incomplete else [])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps({"run": report["run"], "jobs": [{"id": j["id"], "conclusion": j["conclusion"], "records": len(j["evidence"])} for j in report["jobs"]]}))
