#!/usr/bin/env python3
import argparse
import base64
import json
import subprocess
import sys


def git(repo_dir, *args, text=True):
    return subprocess.run(
        ["git", "-C", repo_dir, *args], check=True, capture_output=True, text=text
    ).stdout


def gh_api(method, path, payload):
    result = subprocess.run(
        ["gh", "api", "--method", method, path, "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"gh api {method} {path} failed:\n{result.stderr}{result.stdout}")
    return json.loads(result.stdout)


def changed_entries(repo_dir):
    raw = git(repo_dir, "diff-tree", "-r", "-z", "--no-renames", "--raw", "HEAD^", "HEAD")
    fields = raw.split("\0")
    for meta, path in zip(fields[0::2], fields[1::2]):
        if not meta:
            continue
        _, new_mode, _, new_sha, status = meta.lstrip(":").split(" ")
        yield path, new_mode, new_sha, status


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_dir")
    parser.add_argument("--repo", required=True, help="owner/name on GitHub")
    parser.add_argument("--branch", required=True)
    args = parser.parse_args()

    parent = git(args.repo_dir, "rev-parse", "HEAD^").strip()
    base_tree = git(args.repo_dir, "rev-parse", "HEAD^^{tree}").strip()
    message = git(args.repo_dir, "log", "-1", "--format=%B", "HEAD")
    api = f"repos/{args.repo}/git"

    tree = []
    for path, mode, sha, status in changed_entries(args.repo_dir):
        if status == "D":
            tree.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
            continue
        content = git(args.repo_dir, "cat-file", "blob", sha, text=False)
        blob = gh_api("POST", f"{api}/blobs", {
            "content": base64.b64encode(content).decode(),
            "encoding": "base64",
        })
        tree.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print(f"{status} {path}")

    new_tree = gh_api("POST", f"{api}/trees", {"base_tree": base_tree, "tree": tree})
    commit = gh_api("POST", f"{api}/commits", {
        "message": message,
        "tree": new_tree["sha"],
        "parents": [parent],
    })
    gh_api("PATCH", f"{api}/refs/heads/{args.branch}", {"sha": commit["sha"], "force": False})
    print(f"{args.branch} -> {commit['sha']} (verified: {commit['verification']['verified']})")


if __name__ == "__main__":
    main()
