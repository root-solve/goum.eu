#!/usr/bin/env python3
"""Scan www/mp3 and expose a live playlist JSON API (with MP3 durations)."""

from __future__ import annotations

import json
import os
import re
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from mutagen.mp3 import MP3

MP3_DIR = Path(os.environ.get("MP3_DIR", "/mp3"))
PORT = int(os.environ.get("PORT", "8080"))
CONTACT_MAIL = os.environ.get("CONTACT_MAIL", "").strip()
CONTACT_PHONE = os.environ.get("CONTACT_PHONE", "").strip()
YOUTUBE_URL = os.environ.get("YOUTUBE_URL", "").strip()
DOMAIN = os.environ.get("DOMAIN", "goum.eu").strip() or "goum.eu"
SITE_URL = os.environ.get("SITE_URL", "").strip() or f"https://{DOMAIN}"

# 72-2026 Le_coup...-mix_1.mp3  |  01-2007-Europe-mix_1_retake_2025.mp3
FILENAME_RE = re.compile(
    r"^(?P<num>\d+)-(?P<year>\d{4})[-\s]+(?P<body>.+)\.mp3$",
    re.IGNORECASE,
)
MIX_RE = re.compile(r"-mix[_\s]?(?P<mix>\d+)", re.IGNORECASE)
RETAKE_RE = re.compile(r"retake[_\s]?(?P<retake>\d{4})", re.IGNORECASE)
FEAT_RE = re.compile(
    r"\(feat\.?\s*(?P<feat>[^)]+)\)",
    re.IGNORECASE,
)

# path -> (mtime, size, track_dict)
_CACHE: dict[str, tuple[float, int, dict]] = {}


def humanize(raw: str) -> str:
    text = raw.replace("_", " ")
    text = re.sub(r"\s+", " ", text).strip(" -_")
    return text


def format_duration(seconds: float | None) -> str | None:
    if seconds is None or seconds < 0:
        return None
    total = int(round(seconds))
    m, s = divmod(total, 60)
    if m >= 60:
        h, m = divmod(m, 60)
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def read_duration(path: Path) -> float | None:
    try:
        info = MP3(path).info
        length = getattr(info, "length", None)
        if length is None:
            return None
        return float(length)
    except Exception as exc:
        print(f"[tracks] duration fail {path.name}: {exc}")
        return None


def parse_filename(name: str) -> dict:
    match = FILENAME_RE.match(name)
    if not match:
        return {
            "num": None,
            "year": None,
            "title": humanize(Path(name).stem),
            "mix": None,
            "retake": None,
            "feat": None,
            "label": humanize(Path(name).stem),
            "file": name,
            "url": "/mp3/" + urllib.parse.quote(name),
        }

    num = int(match.group("num"))
    year = int(match.group("year"))
    body = match.group("body")

    mix_m = MIX_RE.search(body)
    mix = int(mix_m.group("mix")) if mix_m else None
    title_part = body[: mix_m.start()] if mix_m else body

    feat_m = FEAT_RE.search(title_part) or FEAT_RE.search(body)
    feat = humanize(feat_m.group("feat")) if feat_m else None
    if feat_m and feat_m.start() < len(title_part):
        title_part = title_part[: feat_m.start()] + title_part[feat_m.end() :]

    retake_m = RETAKE_RE.search(body)
    retake = int(retake_m.group("retake")) if retake_m else None

    title = humanize(title_part)
    label_bits = [str(year), str(num).zfill(2) if num < 10 else str(num), title]
    if feat:
        label_bits.append(f"(feat. {feat})")
    if mix is not None:
        label_bits.append(f"mix {mix}")
    if retake:
        label_bits.append(f"retake {retake}")

    return {
        "num": num,
        "year": year,
        "title": title,
        "mix": mix,
        "retake": retake,
        "feat": feat,
        "label": " - ".join(label_bits),
        "file": name,
        "url": "/mp3/" + urllib.parse.quote(name),
    }


def build_track(path: Path) -> dict:
    track = parse_filename(path.name)
    duration = read_duration(path)
    track["duration"] = round(duration, 3) if duration is not None else None
    track["duration_label"] = format_duration(duration)
    if track["duration_label"]:
        track["label"] = f"{track['label']} - {track['duration_label']}"
    return track


def _is_safe_mp3(path: Path) -> bool:
    """Only real .mp3 files contained under MP3_DIR (no symlink escape)."""
    try:
        if not path.is_file() or path.is_symlink():
            return False
        if path.suffix.lower() != ".mp3" or path.name.startswith("."):
            return False
        if "/" in path.name or "\\" in path.name or path.name in (".", ".."):
            return False
        root = MP3_DIR.resolve(strict=True)
        resolved = path.resolve(strict=True)
        return resolved.is_relative_to(root)
    except OSError:
        return False


def list_tracks() -> list[dict]:
    if not MP3_DIR.is_dir():
        return []

    seen: set[str] = set()
    tracks: list[dict] = []

    for path in MP3_DIR.iterdir():
        if not _is_safe_mp3(path):
            continue

        key = path.name
        seen.add(key)
        try:
            stat = path.stat()
        except OSError:
            continue

        cached = _CACHE.get(key)
        if cached and cached[0] == stat.st_mtime and cached[1] == stat.st_size:
            tracks.append(cached[2])
            continue

        track = build_track(path)
        _CACHE[key] = (stat.st_mtime, stat.st_size, track)
        tracks.append(track)

    for key in list(_CACHE):
        if key not in seen:
            del _CACHE[key]

    tracks.sort(
        key=lambda t: (
            t["num"] is None,
            -(t["num"] or 0),
            -(t["year"] or 0),
            t["file"],
        )
    )
    return tracks


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"[tracks] {self.address_string()} {fmt % args}")

    def _send(self, code: int, payload: dict, cache: str = "no-store") -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if path in ("/", "/tracks", "/api/tracks"):
            started = time.perf_counter()
            tracks = list_tracks()
            elapsed = (time.perf_counter() - started) * 1000
            print(f"[tracks] listed {len(tracks)} in {elapsed:.1f}ms")
            self._send(200, {"count": len(tracks), "tracks": tracks})
            return
        if path in ("/site", "/api/site"):
            yt = None
            if YOUTUBE_URL.startswith("https://") and "\n" not in YOUTUBE_URL:
                try:
                    parsed = urllib.parse.urlparse(YOUTUBE_URL)
                    if parsed.scheme == "https" and parsed.netloc and not parsed.username:
                        yt = YOUTUBE_URL
                except ValueError:
                    yt = None
            mail = (
                CONTACT_MAIL
                if re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", CONTACT_MAIL)
                else None
            )
            phone = (
                CONTACT_PHONE
                if CONTACT_PHONE and not re.search(r"[\r\n]", CONTACT_PHONE)
                else None
            )
            self._send(
                200,
                {
                    "domain": DOMAIN,
                    "site_url": SITE_URL,
                    "contact_mail": mail,
                    "contact_phone": phone,
                    "youtube_url": yt,
                },
            )
            return
        if path in ("/health", "/api/health"):
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not found"})


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[tracks] listening on :{PORT}, scanning {MP3_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
