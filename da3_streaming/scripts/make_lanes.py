#!/usr/bin/env python3
"""Split videos under rgb_mp4/ into N lanes balanced by total frame count.

Each lane is a text file listing video IDs (no extension / no _front suffix), one per line.
The greedy multi-way partition picks the lightest lane next for each (videos sorted by
descending frame count) to minimize the makespan.

Usage:
    python scripts/make_lanes.py --lanes 19 \\
        --video_dir /scratch/e1520508/rgb_mp4 \\
        --out_dir   /scratch/e1520508/Depth-Anything-3/da3_streaming/scripts/lanes
"""
import argparse
import glob
import heapq
import os
import sys
import cv2


def video_id_from_path(p: str) -> str:
    base = os.path.basename(p)
    if base.endswith("_front.mp4"):
        return base[: -len("_front.mp4")]
    if base.endswith(".mp4"):
        return base[:-4]
    return base


def count_frames(path: str) -> int:
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return -1
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lanes", type=int, required=True, help="Number of lanes to create.")
    ap.add_argument(
        "--video_dir",
        type=str,
        default="/scratch/e1520508/rgb_mp4",
        help="Directory containing *_front.mp4 files.",
    )
    ap.add_argument(
        "--out_dir",
        type=str,
        default="/scratch/e1520508/Depth-Anything-3/da3_streaming/scripts/lanes",
        help="Where to write videos_lane_<k>.txt files.",
    )
    ap.add_argument(
        "--min_frames",
        type=int,
        default=121,
        help="Videos with strictly fewer than this many frames go to too_short.txt instead "
             "of any lane (the model needs at least one full chunk for stable multi-chunk SIM3).",
    )
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.video_dir, "*.mp4")))
    if not files:
        print(f"No mp4 files found in {args.video_dir}", file=sys.stderr)
        sys.exit(1)
    print(f"Found {len(files)} mp4 files; scanning frame counts...")

    entries = []   # list of (id, frames)
    too_short = []
    broken = []
    for i, f in enumerate(files):
        n = count_frames(f)
        vid = video_id_from_path(f)
        if n < 0:
            broken.append(vid)
            continue
        if n < args.min_frames:
            too_short.append((vid, n))
            continue
        entries.append((vid, n))
        if (i + 1) % 200 == 0:
            print(f"  scanned {i+1}/{len(files)}", flush=True)

    total_frames = sum(n for _, n in entries)
    print(
        f"Eligible videos: {len(entries)}, total frames: {total_frames}, "
        f"too_short: {len(too_short)}, broken: {len(broken)}"
    )

    os.makedirs(args.out_dir, exist_ok=True)

    # Greedy LPT: sort by frames desc, assign next to lane with current smallest load.
    entries.sort(key=lambda x: -x[1])
    heap = [(0, k, []) for k in range(args.lanes)]   # (load, lane_idx, videos)
    heapq.heapify(heap)
    for vid, n in entries:
        load, k, vids = heapq.heappop(heap)
        vids.append((vid, n))
        heapq.heappush(heap, (load + n, k, vids))

    lanes = sorted([heapq.heappop(heap) for _ in range(args.lanes)], key=lambda x: x[1])
    loads = [load for load, _, _ in lanes]
    print(
        f"Lane loads: min={min(loads)}, max={max(loads)}, "
        f"spread={max(loads) - min(loads)} frames ({(max(loads) - min(loads)) / max(1, max(loads)):.1%})"
    )

    for load, k, vids in lanes:
        path = os.path.join(args.out_dir, f"videos_lane_{k}.txt")
        with open(path, "w") as f:
            for vid, _ in vids:
                f.write(vid + "\n")
        print(f"  lane {k:2d}: {len(vids):4d} videos, {load:8d} frames -> {path}")

    if too_short:
        p = os.path.join(args.out_dir, "too_short.txt")
        with open(p, "w") as f:
            for vid, n in too_short:
                f.write(f"{vid}\t{n}\n")
        print(f"Wrote {len(too_short)} too_short videos to {p}")

    if broken:
        p = os.path.join(args.out_dir, "broken.txt")
        with open(p, "w") as f:
            for vid in broken:
                f.write(vid + "\n")
        print(f"Wrote {len(broken)} broken videos to {p}")


if __name__ == "__main__":
    main()
