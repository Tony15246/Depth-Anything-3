#!/bin/bash
# One-shot progress dashboard.

: "${OUT_BASE:=/scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results}"
: "${LANES_DIR:=/scratch/e1520508/Depth-Anything-3/da3_streaming/scripts/lanes}"

if [[ ! -d "${LANES_DIR}" ]]; then
    echo "lanes dir not found: ${LANES_DIR}"
    exit 1
fi

# Only count primary lanes (0..99); lanes >= 100 are backfill subsets that
# duplicate videos already counted in their parent lane.
is_primary_lane() {
    local name="$1"
    [[ "$name" =~ ^[0-9]+$ ]] && (( name < 100 ))
}

total=0
for f in "${LANES_DIR}"/videos_lane_*.txt; do
    k=$(basename "$f" .txt | sed 's/videos_lane_//')
    is_primary_lane "$k" || continue
    n=$(wc -l < "${f}")
    total=$((total + n))
done

done_n=$(ls "${OUT_BASE}"/*.done 2>/dev/null | wc -l)
out_videos=$(find "${OUT_BASE}" -maxdepth 1 -mindepth 1 -type d ! -name logs ! -name "lane_*" 2>/dev/null | wc -l)
failed_files=$(ls "${OUT_BASE}"/lane_*_failed.txt 2>/dev/null)
failed_n=0
if [[ -n "${failed_files}" ]]; then
    failed_n=$(cat ${failed_files} 2>/dev/null | wc -l)
fi

echo "=== DA3 depth-collection progress @ $(date) ==="
echo "Output dir : ${OUT_BASE}"
printf "Progress   : %d / %d done  (%.1f%%)\n" "${done_n}" "${total}" \
       "$(awk -v d=${done_n} -v t=${total} 'BEGIN{ if (t==0) print 0; else print d*100/t}')"
echo "Output subdirs    : ${out_videos}"
echo "Failure entries   : ${failed_n}"
df -h "${OUT_BASE}" | tail -1
echo
echo "Lane-by-lane (primary 0..15):"
for f in $(ls "${LANES_DIR}"/videos_lane_*.txt | sort -V); do
    k=$(basename "$f" | sed 's/videos_lane_//; s/.txt//')
    is_primary_lane "$k" || continue
    n=$(wc -l < "${f}")
    # count done within this lane
    d=0
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        if [[ -f "${OUT_BASE}/${v}.done" ]]; then
            d=$((d + 1))
        fi
    done < "${f}"
    printf "  lane %-3s  %4d / %4d  (%5.1f%%)\n" "$k" "$d" "$n" \
        "$(awk -v d=$d -v t=$n 'BEGIN{ if (t==0) print 0; else print d*100/t}')"
done

# Also show backfill lanes if any exist (>=100), they share videos with primary lanes.
backfill_found=0
for f in $(ls "${LANES_DIR}"/videos_lane_*.txt | sort -V); do
    k=$(basename "$f" | sed 's/videos_lane_//; s/.txt//')
    if [[ "$k" =~ ^[0-9]+$ ]] && (( k >= 100 )); then
        if (( backfill_found == 0 )); then
            echo
            echo "Backfill lanes (subset of primary; videos also counted under primary):"
            backfill_found=1
        fi
        n=$(wc -l < "${f}")
        d=0
        while IFS= read -r v; do
            [[ -z "$v" ]] && continue
            if [[ -f "${OUT_BASE}/${v}.done" ]]; then
                d=$((d + 1))
            fi
        done < "${f}"
        printf "  lane %-3s  %4d / %4d  (%5.1f%%)\n" "$k" "$d" "$n" \
            "$(awk -v d=$d -v t=$n 'BEGIN{ if (t==0) print 0; else print d*100/t}')"
    fi
done

echo
echo "PBS jobs:"
qstat -u "$USER" 2>/dev/null | tail -n +1
