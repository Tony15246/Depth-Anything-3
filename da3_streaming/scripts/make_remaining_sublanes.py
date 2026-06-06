#!/usr/bin/env python3
"""Generate sublane files for the still-undone videos in a set of primary lanes.

For each primary lane file (videos_lane_<N>.txt), collect videos whose
.done marker is missing in $OUT_BASE, and round-robin-split them into
`--splits` sublanes named videos_lane_<start_idx>.txt, ..., starting at
the requested numeric index.

Usage:
    python scripts/make_remaining_sublanes.py \\
        --primary 8,9,10,11,12,13,14,15 \\
        --start_idx 200 --splits 8 \\
        --skip_first 30
"""
import argparse
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--primary", type=str, required=True,
                    help="Comma-separated primary lane indices, e.g. 8,9,10,11,12,13,14,15")
    ap.add_argument("--start_idx", type=int, required=True,
                    help="Numeric index for the first new sublane (e.g. 200).")
    ap.add_argument("--splits", type=int, required=True,
                    help="Number of sublanes to produce. Videos are round-robin distributed.")
    ap.add_argument("--skip_first", type=int, default=0,
                    help="Skip the first N lines of each primary lane (medium is processing "
                         "from the start, so the head is likely already done or in-progress).")
    ap.add_argument("--lanes_dir", type=str,
                    default="/scratch/e1520508/Depth-Anything-3/da3_streaming/scripts/lanes")
    ap.add_argument("--out_base", type=str,
                    default="/scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results")
    args = ap.parse_args()

    primary_lanes = [int(x) for x in args.primary.split(",")]
    remaining = []  # ordered list of video ids, tail-half of each primary lane
    for lane in primary_lanes:
        path = os.path.join(args.lanes_dir, f"videos_lane_{lane}.txt")
        if not os.path.exists(path):
            print(f"WARNING: missing {path}", file=sys.stderr)
            continue
        with open(path) as f:
            lines = [ln.strip() for ln in f if ln.strip()]
        for v in lines[args.skip_first:]:
            done = os.path.exists(os.path.join(args.out_base, f"{v}.done"))
            if not done:
                remaining.append((lane, v))
    if not remaining:
        print("Nothing to do; no undone videos found.", file=sys.stderr)
        sys.exit(2)

    # Round-robin split into N sublanes; this interleaves across primary lanes
    # so each sublane sees a mix of remaining work.
    splits = [[] for _ in range(args.splits)]
    for i, (lane, v) in enumerate(remaining):
        splits[i % args.splits].append(v)

    print(f"Found {len(remaining)} undone videos across primary lanes "
          f"{args.primary} (after skipping first {args.skip_first} lines each).")
    print(f"Writing {args.splits} sublanes starting at index {args.start_idx}:")
    for i, vids in enumerate(splits):
        idx = args.start_idx + i
        out = os.path.join(args.lanes_dir, f"videos_lane_{idx}.txt")
        with open(out, "w") as f:
            for v in vids:
                f.write(v + "\n")
        print(f"  lane {idx}: {len(vids)} videos -> {out}")


if __name__ == "__main__":
    main()
