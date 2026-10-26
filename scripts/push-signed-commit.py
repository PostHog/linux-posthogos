#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys


def git(repo_dir, *args):
    return subprocess.run(
        ["git", "-C", repo_dir, *args], check=True, capture_output=True, text=True
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_dir")
    parser.add_argument("--repo", required=True, help="owner/name on GitHub")
    parser.add_argument("--branch", required=True)
    args = parser.parse_args()

    head = git(args.repo_dir, "rev-parse", "HEAD").strip()
    parent = git(args.repo_dir, "rev-parse", "HEAD^").strip()
    tree = git(args.repo_dir, "rev-parse", "HEAD^{tree}").strip()
    message = git(args.repo_dir, "log", "-1", "--format=%B", "HEAD")
    api = f"repos/{args.repo}/git"

    staging_tag = f"signed-commit-staging/{head}"
    git(args.repo_dir, "push", "origin", f"{head}:refs/tags/{staging_tag}")
    try:
        commit = gh_api("POST", f"{api}/commits", {
            "message": message,
            "tree": tree,
            "parents": [parent],
        })
        gh_api("PATCH", f"{api}/refs/heads/{args.branch}", {"sha": commit["sha"], "force": False})
    finally:
        git(args.repo_dir, "push", "origin", f":refs/tags/{staging_tag}")
    print(f"{args.branch} -> {commit['sha']} (verified: {commit['verification']['verified']})")


if __name__ == "__main__":
    main()
