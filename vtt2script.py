#!/usr/bin/env python3
"""Turn a YouTube caption file (VTT / SRT / json3) into a clean transcript.

YouTube auto-captions are "rolling": each cue repeats and extends the previous
one, so a naive dump is 3-5x longer than the real speech. This collapses that.
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

TAG_RE = re.compile(r"<[^>]+>")
TS_RE = re.compile(
    r"(\d{1,2}:\d{2}:\d{2}[.,]\d{3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{3})"
)


def to_seconds(stamp: str) -> float:
    h, m, s = stamp.replace(",", ".").split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def fmt(seconds: float) -> str:
    total = int(seconds)
    h, m, s = total // 3600, (total % 3600) // 60, total % 60
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:d}:{s:02d}"


def clean(text: str) -> str:
    text = html.unescape(TAG_RE.sub("", text))
    return re.sub(r"\s+", " ", text).strip()


def parse_timed(path: Path):
    """Parse VTT or SRT into [(start_seconds, line), ...] in document order."""
    cues = []
    start = None
    buf = []

    def flush():
        if start is not None:
            for line in buf:
                if line:
                    cues.append((start, line))

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = TS_RE.search(raw)
        if match:
            flush()
            start, buf = to_seconds(match.group(1)), []
            continue
        stripped = raw.strip()
        if not stripped or stripped == "WEBVTT" or stripped.isdigit():
            continue
        if stripped.startswith(("NOTE", "STYLE", "Kind:", "Language:")):
            continue
        if start is not None:
            buf.append(clean(stripped))
    flush()
    return cues


def parse_json3(path: Path):
    data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    cues = []
    for event in data.get("events", []):
        segs = event.get("segs")
        if not segs:
            continue
        text = clean("".join(seg.get("utf8", "") for seg in segs))
        if text:
            cues.append((event.get("tStartMs", 0) / 1000.0, text))
    return cues


def collapse(cues):
    """Drop repeats and absorb rolling prefix-growth from auto-captions."""
    out = []
    for start, line in cues:
        if out:
            prev_start, prev = out[-1]
            if line == prev:
                continue
            # auto-captions re-emit the previous line with more words appended
            if line.startswith(prev):
                out[-1] = (prev_start, line)
                continue
            if prev.startswith(line):
                continue
        out.append((start, line))
    return out


def paragraphs(cues, gap=3.0, max_chars=420):
    """Group lines into readable blocks on long pauses or sentence ends."""
    blocks, current, started, last = [], [], None, None
    for start, line in cues:
        if started is None:
            started = start
        break_here = (
            current
            and (
                (last is not None and start - last >= gap)
                or sum(len(c) for c in current) >= max_chars
            )
        )
        if break_here:
            blocks.append((started, " ".join(current)))
            current, started = [], start
        current.append(line)
        last = start
    if current:
        blocks.append((started, " ".join(current)))
    return blocks


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("subtitle", type=Path, help="caption file (.vtt/.srt/.json3/.json)")
    ap.add_argument("-o", "--output", type=Path, help="write here instead of stdout")
    ap.add_argument("-t", "--timestamps", action="store_true", help="prefix [m:ss]")
    ap.add_argument("--title", default="", help="heading for the transcript")
    ap.add_argument("--url", default="", help="source URL to cite")
    ap.add_argument("--raw", action="store_true", help="no paragraph grouping")
    ap.add_argument("--gap", type=float, default=3.0, help="pause (s) that splits a block")
    args = ap.parse_args()

    if not args.subtitle.exists():
        sys.exit(f"no such caption file: {args.subtitle}")

    suffix = args.subtitle.suffix.lower()
    cues = parse_json3(args.subtitle) if suffix in (".json3", ".json") else parse_timed(args.subtitle)
    cues = collapse(cues)
    if not cues:
        sys.exit(f"no caption text found in {args.subtitle}")

    blocks = [(s, t) for s, t in cues] if args.raw else paragraphs(cues, gap=args.gap)

    lines = []
    if args.title:
        lines += [f"# {args.title}", ""]
    if args.url:
        lines += [f"來源：{args.url}", ""]
    for start, text in blocks:
        lines.append(f"**[{fmt(start)}]** {text}" if args.timestamps else text)
        lines.append("")

    result = "\n".join(lines).rstrip() + "\n"
    if args.output:
        args.output.write_text(result, encoding="utf-8")
        words = sum(len(t) for _, t in blocks)
        print(f"wrote {args.output}  ({len(blocks)} blocks, ~{words} chars)", file=sys.stderr)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
