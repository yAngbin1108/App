#!/usr/bin/env python3
"""Push changed files through the GitHub Git Data API (works when github.com:443 is blocked)."""
import base64, json, os, sys, urllib.request, urllib.error

REPO = os.environ.get("GH_REPO", "yAngbin1108/App")
BRANCH = os.environ.get("GH_BRANCH", "main")
TOKEN = os.environ["GITHUB_TOKEN"]
API = "https://api.github.com"


def call(method, path, payload=None):
    url = API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print("HTTP", e.code, path, body[:500], file=sys.stderr)
        raise


def main():
    message = sys.argv[1]
    files = sys.argv[2:]
    ref = call("GET", f"/repos/{REPO}/git/ref/heads/{BRANCH}")
    head = ref["object"]["sha"]
    commit = call("GET", f"/repos/{REPO}/git/commits/{head}")
    base_tree = commit["tree"]["sha"]

    entries = []
    for f in files:
        with open(f, "rb") as fh:
            content = base64.b64encode(fh.read()).decode()
        blob = call("POST", f"/repos/{REPO}/git/blobs", {"content": content, "encoding": "base64"})
        entries.append({"path": f, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        print("blob", f, blob["sha"][:8])

    tree = call("POST", f"/repos/{REPO}/git/trees",
                {"base_tree": base_tree, "tree": entries})
    new = call("POST", f"/repos/{REPO}/git/commits",
               {"message": message, "tree": tree["sha"], "parents": [head]})
    call("PATCH", f"/repos/{REPO}/git/refs/heads/{BRANCH}",
         {"sha": new["sha"], "force": False})
    print("pushed", new["sha"][:10])


if __name__ == "__main__":
    main()