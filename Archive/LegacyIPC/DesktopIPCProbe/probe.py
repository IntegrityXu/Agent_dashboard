#!/usr/bin/env python3
"""Bounded observer of an EXISTING same-user Codex coordination socket.

Discovery only, pinned to the inspected desktop version. It never starts a
router, claims ownership, sends execution commands, answers approvals, or writes
read state. Only an explicitly designated disposable conversation is followed.
Raw messages and conversation text are never written to output or disk.
"""
import argparse
import hashlib
import json
import os
import plistlib
import socket
import stat
import struct
import time
import uuid
from pathlib import Path

SUPPORTED_BUILD = "21477"
VERSIONS = {"initialize": 0, "thread-owner-discovery": 1,
            "thread-stream-following-changed": 1}


def digest(value):
    return hashlib.sha256(str(value).encode()).hexdigest()[:12]


def emit(kind, **fields):
    print(json.dumps({"kind": kind, "monotonic": round(time.monotonic(), 3), **fields}), flush=True)


def shape(value, depth=0):
    if depth >= 3:
        return type(value).__name__
    if isinstance(value, dict):
        return {k: shape(v, depth + 1) for k, v in value.items()}
    if isinstance(value, list):
        return {"length": len(value), "lastShape": shape(value[-1], depth + 1) if value else None}
    return type(value).__name__


class Observer:
    def __init__(self, path, thread_id, seconds):
        uuid.UUID(thread_id)
        self.thread_id = thread_id
        self.deadline = time.monotonic() + seconds
        self.client_id = "initializing-client"
        self.buffer = bytearray()
        self.requests = {}
        self.hosts = ("local", "durable")
        self.snapshots = {}
        self.revisions = {}
        self.read_fingerprint = self.read_state_fingerprint()
        self.next_read_check = 0
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(1)
        for candidate, kind in [(path.parent, "directory"), (path, "socket")]:
            st = candidate.lstat()
            correct_type = stat.S_ISDIR(st.st_mode) if kind == "directory" else stat.S_ISSOCK(st.st_mode)
            if not correct_type or st.st_uid != os.getuid() or st.st_mode & 0o077:
                raise RuntimeError("unsafe socket ownership/type/permissions")
        self.socket.connect(str(path))

    def send(self, message):
        method = message.get("method")
        if message["type"] in ("request", "broadcast") and method not in VERSIONS:
            raise ValueError("Non-observation method refused")
        body = json.dumps(message, separators=(",", ":")).encode()
        self.socket.sendall(struct.pack("<I", len(body)) + body)

    def request(self, method, params):
        request_id = str(uuid.uuid4())
        self.requests[request_id] = (method, params.get("hostId"))
        self.send({"type": "request", "requestId": request_id,
                   "sourceClientId": self.client_id, "version": VERSIONS[method],
                   "method": method, "params": params, "timeoutMs": 3000})

    def follow(self, host, following):
        self.send({"type": "broadcast", "method": "thread-stream-following-changed",
                   "sourceClientId": self.client_id, "version": 1,
                   "params": {"conversationId": self.thread_id, "hostId": host, "following": following}})

    def run(self):
        try:
            self.request("initialize", {"clientType": "status-board-observer"})
            while time.monotonic() < self.deadline:
                if time.monotonic() >= self.next_read_check:
                    self.next_read_check = time.monotonic() + 1
                    fingerprint = self.read_state_fingerprint()
                    if fingerprint != self.read_fingerprint and self.client_id != "initializing-client":
                        self.read_fingerprint = fingerprint
                        emit("readStoreInvalidation")
                        self.follow("local", True)
                try:
                    chunk = self.socket.recv(65536)
                except socket.timeout:
                    continue
                if not chunk:
                    emit("disconnected")
                    break
                self.buffer.extend(chunk)
                while len(self.buffer) >= 4:
                    size = struct.unpack_from("<I", self.buffer)[0]
                    if not 0 < size <= 8 * 1024 * 1024:
                        raise ValueError("invalid or oversized frame")
                    if len(self.buffer) < 4 + size:
                        break
                    message = json.loads(self.buffer[4:4 + size])
                    del self.buffer[:4 + size]
                    self.handle(message)
        finally:
            if self.client_id != "initializing-client":
                for host in self.hosts:
                    try:
                        self.follow(host, False)
                    except OSError:
                        pass
            self.socket.close()
            emit("observerClosed")

    def handle(self, message):
        kind = message.get("type")
        if kind == "client-discovery-request":
            self.send({"type": "client-discovery-response", "requestId": message["requestId"], "response": {"canHandle": False}})
        elif kind == "response":
            method, host = self.requests.pop(message.get("requestId"), (None, None))
            if method is None:
                return
            success = message.get("resultType") == "success"
            emit("response", method=method, host=host, success=success)
            if method == "initialize" and success:
                self.client_id = message["result"]["clientId"]
                for host in self.hosts:
                    self.request("thread-owner-discovery", {"hostId": host, "conversationId": self.thread_id})
                    self.follow(host, True)
        elif kind == "broadcast":
            params = message.get("params", {})
            method = message.get("method")
            if params.get("conversationId", params.get("threadId")) != self.thread_id:
                return
            if method == "thread-stream-state-changed":
                if message.get("version") != 11:
                    raise RuntimeError("unsupported stream schema")
                change = params["change"]
                common = dict(host=params.get("hostId"), owner=digest(message.get("sourceClientId")), revision=change.get("revision"))
                if change["type"] == "snapshot":
                    state = change.get("conversationState", {})
                    self.snapshots[common["host"]] = state
                    self.revisions[common["host"]] = (common["owner"], common["revision"])
                    emit("snapshot", **common, schema=shape(state), summary=self.summary(state))
                elif change["type"] == "patches":
                    key = common["host"]
                    valid = self.revisions.get(key) == (common["owner"], change.get("baseRevision"))
                    if valid:
                        for patch in change.get("patches", []):
                            self.apply(self.snapshots[key], patch)
                        self.revisions[key] = (common["owner"], common["revision"])
                    else:
                        self.snapshots.pop(key, None)
                        self.revisions.pop(key, None)
                        self.follow(key, True)
                    emit("patches", **common, continuous=valid,
                         summary=self.summary(self.snapshots.get(key, {})),
                         baseRevision=change.get("baseRevision"), patches=[
                        {"op": p.get("op"), "path": p.get("path"), "valueShape": shape(p.get("value"))}
                        for p in change.get("patches", [])])
            elif method == "thread-read-state-changed":
                emit("readState", version=message.get("version"), hasUnreadTurn=params.get("hasUnreadTurn"), schema=shape(params))

    @staticmethod
    def read_state_fingerprint():
        # Discovery fallback: the private read store is an INVALIDATION hint only.
        # Never derive read/unread or account identity from migration membership.
        # Production must use a filesystem event watcher, not this bounded poll.
        try:
            path = Path.home() / ".codex/.codex-global-state.json"
            value = json.loads(path.read_text()).get("electron-thread-read-state-v1")
            return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
        except (OSError, ValueError):
            return None

    @staticmethod
    def apply(state, patch):
        path = patch["path"]
        if not path:
            raise ValueError("root patch requires fresh snapshot")
        target = state
        for key in path[:-1]:
            target = target[key]
        key = path[-1]
        if patch["op"] == "remove":
            if isinstance(target, list):
                target.pop(key)
            else:
                del target[key]
        elif patch["op"] in ("add", "replace"):
            if isinstance(target, list) and patch["op"] == "add":
                target.insert(key, patch.get("value"))
            else:
                target[key] = patch.get("value")
        else:
            raise ValueError("unsupported patch operation")

    @staticmethod
    def summary(state):
        history = state.get("turnHistory", {}).get("history", {})
        entities = history.get("entitiesByKey", {})
        turns = [entities[e["value"]] for island in history.get("islands", [])
                 for e in island.get("entries", []) if e.get("value") in entities]
        turns += state.get("turns", [])
        last = turns[-1] if turns else {}
        safe_status = lambda value: value if value in ("inProgress", "completed", "failed", "interrupted", "active", "idle", "notLoaded", "systemError", "needs_resume", "resumed", "resuming") else None
        requests = state.get("requests", [])
        return {"hasUnreadTurn": state.get("hasUnreadTurn"), "turnCount": len(turns),
                "lastTurn": {"id": digest(last.get("turnId")), "status": safe_status(last.get("status")),
                             "shape": shape(last), "itemTypes": [x.get("type") for x in last.get("items", [])]},
                "requests": [{"id": digest(r.get("id")), "method": r.get("method"), "shape": shape(r)} for r in requests],
                "runtime": shape(state.get("threadRuntimeStatus")),
                "runtimeType": safe_status((state.get("threadRuntimeStatus") or {}).get("type")),
                "resumeState": safe_status(state.get("resumeState")),
                "historyShape": shape(history.get("islands", [])), "newerBoundaries": [i.get("newerBoundary", {}).get("status") for i in history.get("islands", [])]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("thread_id")
    parser.add_argument("--seconds", type=int, default=15, choices=range(1, 301))
    args = parser.parse_args()
    with open("/Applications/ChatGPT.app/Contents/Info.plist", "rb") as f:
        version = plistlib.load(f)
    if version.get("CFBundleVersion") != SUPPORTED_BUILD:
        raise SystemExit("Unsupported desktop build; re-inspect protocol before connecting")
    Observer(Path.home() / ".codex/ipc/ipc.sock", args.thread_id, args.seconds).run()
