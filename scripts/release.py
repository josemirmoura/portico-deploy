#!/usr/bin/env python3
"""Static-site atomic releases for an unprivileged, per-project runner."""
import argparse
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import tempfile
from datetime import datetime, timezone

BASE = Path("/opt/portico-deploy/apps")
PROJECT = re.compile(r"^[a-z][a-z0-9-]{1,20}$")
SHA = re.compile(r"^[0-9a-f]{40}$")
MAX_MEMBERS = 20000
MAX_BYTES = 2 * 1024**3


def validate_name(project, sha):
    if not PROJECT.fullmatch(project) or not SHA.fullmatch(sha):
        raise ValueError("Invalid project or commit SHA")


def _safe_member(member):
    raw = member.name
    parts = raw.split("/")
    if raw.startswith("/") or "\\" in raw or ".." in parts:
        raise ValueError("Unsafe archive path")
    rel = PurePosixPath(raw)
    if str(rel) == ".":
        if member.isdir():
            return None
        raise ValueError("Unexpected root file")
    if not (member.isfile() or member.isdir()):
        raise ValueError("Links and special files are forbidden")
    return Path(*rel.parts)


def unpack(archive, target):
    total = count = 0
    with tarfile.open(archive, mode="r:gz") as tf:
        for member in tf:
            count += 1
            if count > MAX_MEMBERS:
                raise ValueError("Too many archive members")
            rel = _safe_member(member)
            if rel is None:
                continue
            dest = target / rel
            if member.isdir():
                dest.mkdir(parents=True, exist_ok=True)
                continue
            total += member.size
            if total > MAX_BYTES:
                raise ValueError("Archive exceeds maximum expanded size")
            dest.parent.mkdir(parents=True, exist_ok=True)
            # No overwrite, including duplicate file names in an archive.
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
            try:
                with os.fdopen(fd, "wb") as out:
                    src = tf.extractfile(member)
                    if src is None:
                        raise ValueError("Missing archived file data")
                    with src:
                        shutil.copyfileobj(src, out, length=1024 * 1024)
            except Exception:
                dest.unlink(missing_ok=True)
                raise
    if count == 0:
        raise ValueError("Empty archive")


def _target(link):
    if not link.is_symlink():
        return None
    return os.readlink(link)


def _swap(link, destination):
    temp = link.with_name(".new-" + link.name)
    if temp.exists() or temp.is_symlink():
        raise RuntimeError("Stale temporary link")
    os.symlink(destination, temp)
    os.replace(temp, link)


def _audit(root, action, sha):
    with (root / "deploy-events.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "action": action, "sha": sha}) + "\n")


def publish(root, sha, archive):
    if not SHA.fullmatch(sha):
        raise ValueError("Invalid SHA")
    root = Path(root)
    if root.is_symlink():
        raise ValueError("Project root is a symlink")
    if not root.is_dir():
        raise ValueError("Project directory must be provisioned first")
    releases = root / "releases"
    if releases.is_symlink() or not releases.is_dir():
        raise ValueError("Invalid releases root")
    with (root / ".deploy.lock").open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        final = releases / sha
        if final.exists() or final.is_symlink():
            raise ValueError("SHA already deployed; replay blocked")
        current = root / "current"
        if current.exists() and not current.is_symlink():
            raise ValueError("Current is not a symlink")
        old_target = _target(current)
        if old_target is not None:
            if not old_target.startswith("releases/") or not SHA.fullmatch(old_target[9:]):
                raise ValueError("Invalid active release link")
            if not (root / old_target).is_dir():
                raise ValueError("Active release directory missing")
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as temp:
            stage = Path(temp)
            # Static assets must be readable by the existing web server without
            # giving that service write access to the runner project.
            stage.chmod(0o755)
            old_umask = os.umask(0o022)
            try:
                unpack(archive, stage)
            finally:
                os.umask(old_umask)
            if not any(stage.iterdir()):
                raise ValueError("No extracted files")
            # Atomic rename after full extraction; everything remains inside releases.
            os.rename(stage, final)
        current = root / "current"
        previous = root / "previous"
        if current.exists() and not current.is_symlink():
            raise ValueError("Current is not a symlink")
        if old_target is not None:
            _swap(previous, old_target)
        _swap(current, "releases/" + sha)
        _audit(root, "deploy", sha)
        return final


def rollback(root):
    root = Path(root)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Invalid project root")
    with (root / ".deploy.lock").open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        previous = root / "previous"
        old = _target(previous)
        current = root / "current"
        now = _target(current)
        if now is None or not now.startswith("releases/") or not SHA.fullmatch(now[9:]):
            raise ValueError("No valid current release")
        if old is None:
            # First deploy failed: restore pre-deploy empty state.
            current.unlink()
            _audit(root, "rollback-to-empty", now[9:])
            return "empty"
        if not old.startswith("releases/") or not SHA.fullmatch(old[9:]):
            raise ValueError("Invalid previous release")
        if not (root / old).is_dir():
            raise ValueError("Previous release is missing")
        _swap(current, old)
        _swap(previous, now)
        _audit(root, "rollback", old[9:])
        return old


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--sha")
    action.add_argument("--rollback", action="store_true")
    parser.add_argument("--archive")
    opts = parser.parse_args()
    if not PROJECT.fullmatch(opts.project):
        parser.error("Unsafe project name")
    root = BASE / opts.project
    if opts.rollback:
        if opts.archive:
            parser.error("No archive with rollback")
        print("Rollback:", rollback(root))
    else:
        if not opts.archive:
            parser.error("Archive required")
        print("Deployed:", publish(root, opts.sha, opts.archive))


if __name__ == "__main__":
    main()
