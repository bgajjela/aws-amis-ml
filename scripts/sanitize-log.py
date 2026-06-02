#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Dimenpoint

import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sanitize-log.py <src> <dst>", file=sys.stderr)
        return 2

    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    text = src.read_text(encoding="utf-8", errors="replace")

    patterns = [
        (r"github\.com=[^\s\"']+", "github.com=***"),
        (r"AUTHORIZATION:\s*basic\s+\S+", "AUTHORIZATION: basic ***"),
        (r"(?i)(authToken:\s*)(.+)", r"\1***"),
        (r"(?i)(token[:=]\s*)(\S+)", r"\1***"),
        (r"\b(AKIA|ASIA)[0-9A-Z]{16}\b", "***AWS_ACCESS_KEY_ID***"),
        (r"arn:aws:[^\s\"']+", "***AWS_ARN***"),
    ]

    for pattern, repl in patterns:
        text = re.sub(pattern, repl, text)

    dst.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
