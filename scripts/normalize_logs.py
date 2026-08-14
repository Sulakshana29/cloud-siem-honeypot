#!/usr/bin/env python3
"""
Cowrie Log Normalizer
Reads raw Cowrie JSON logs and outputs normalized events for SIEM ingestion.
"""

import json
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path


# Events we care about — filter out noise
RELEVANT_EVENTS = {
    "cowrie.session.connect",
    "cowrie.login.failed",
    "cowrie.login.success",
    "cowrie.command.input",
    "cowrie.session.file_download",
    "cowrie.session.closed",
}


def normalize_event(raw: dict) -> dict | None:
    """
    Convert a raw Cowrie JSON event into a normalized SIEM-ready record.
    Returns None if the event should be skipped.
    """
    event_id = raw.get("eventid", "")

    if event_id not in RELEVANT_EVENTS:
        return None

    # Parse and re-emit timestamp in UTC ISO 8601
    raw_ts = raw.get("timestamp", "")
    try:
        ts = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
        normalized_ts = ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    except (ValueError, AttributeError):
        normalized_ts = raw_ts  # keep original if parse fails

    normalized = {
        "timestamp":    normalized_ts,
        "source":       "cowrie-honeypot",
        "event_type":   event_id,
        "session_id":   raw.get("session", ""),
        "src_ip":       raw.get("src_ip", ""),
        "src_port":     raw.get("src_port", 0),
        "dst_port":     raw.get("dst_port", 0),
        "username":     raw.get("username", ""),
        "password":     raw.get("password", ""),
        "command":      raw.get("input", ""),
        "message":      raw.get("message", ""),
        "sensor":       raw.get("sensor", ""),
    }

    # Add download-specific fields
    if event_id == "cowrie.session.file_download":
        normalized["file_url"]  = raw.get("url", "")
        normalized["file_sha"]  = raw.get("shasum", "")
        normalized["file_size"] = raw.get("outfile", "")

    return normalized


def parse_log_file(input_path: Path) -> list[dict]:
    """Parse a Cowrie JSON log file (one JSON object per line)."""
    results = []

    with open(input_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
                normalized = normalize_event(raw)
                if normalized:
                    results.append(normalized)
            except json.JSONDecodeError as e:
                print(f"[WARN] Line {line_num}: JSON parse error — {e}", file=sys.stderr)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Normalize Cowrie honeypot logs to structured JSON"
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Path to cowrie.json log file"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=None,
        help="Output file (default: stdout)"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Print summary statistics after parsing"
    )
    args = parser.parse_args()

    if not args.input.exists():
        print(f"[ERROR] Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    events = parse_log_file(args.input)

    # Output
    output_json = json.dumps(events, indent=2)

    if args.output:
        args.output.write_text(output_json, encoding="utf-8")
        print(f"[OK] Wrote {len(events)} events to {args.output}")
    else:
        print(output_json)

    # Optional stats
    if args.stats:
        from collections import Counter
        event_counts = Counter(e["event_type"] for e in events)
        ip_counts = Counter(e["src_ip"] for e in events if e["src_ip"])
        print("\n── Event type summary ──", file=sys.stderr)
        for ev, count in event_counts.most_common():
            print(f"  {ev:<40} {count}", file=sys.stderr)
        print("\n── Top 10 source IPs ──", file=sys.stderr)
        for ip, count in ip_counts.most_common(10):
            print(f"  {ip:<20} {count}", file=sys.stderr)


if __name__ == "__main__":
    main()
