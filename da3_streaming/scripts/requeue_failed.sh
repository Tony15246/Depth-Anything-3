#!/bin/bash
# Collect all lane_*_failed.txt entries that still don't have a .done marker,
# write them into a new retry lane file, and emit a qsub command suggestion.
#
# Usage:
#   bash scripts/requeue_failed.sh
# Then inspect scripts/lanes/videos_retry_*.txt and submit one PBS job per file.

set -u

: "${OUT_BASE:=/scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results}"
: "${LANES_DIR:=/scratch/e1520508/Depth-Anything-3/da3_streaming/scripts/lanes}"

stamp=$(date +%Y%m%d_%H%M%S)
retry_all="${LANES_DIR}/videos_retry_${stamp}.txt"
> "${retry_all}"

if compgen -G "${OUT_BASE}/lane_*_failed.txt" > /dev/null; then
    cat "${OUT_BASE}"/lane_*_failed.txt | awk -F'\t' '{print $1}' | sort -u | \
    while IFS= read -r vid; do
        [[ -z "$vid" ]] && continue
        if [[ ! -f "${OUT_BASE}/${vid}.done" ]]; then
            echo "$vid" >> "${retry_all}"
        fi
    done
fi

n=$(wc -l < "${retry_all}")
if [[ $n -eq 0 ]]; then
    echo "No outstanding failed videos."
    rm -f "${retry_all}"
    exit 0
fi

echo "Wrote ${n} videos to ${retry_all}"
echo
echo "Suggested submit (single lane, small queue):"
echo "  cp '${retry_all}' '${LANES_DIR}/videos_lane_retry${stamp}.txt'"
echo "  qsub -v LANE=retry${stamp} ${LANES_DIR%/lanes}/submit_small.pbs"
