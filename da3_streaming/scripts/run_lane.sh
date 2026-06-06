#!/bin/bash
# Process one lane (a list of video ids) sequentially on a single GPU.
#
# Required env:
#   LANE           : lane index (matches lanes/videos_lane_<LANE>.txt)
# Optional env:
#   MAX_VIDEOS     : if set, stop after processing this many videos (for calibration)
#   OUT_BASE       : default /scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results
#   REPO_DIR       : default /scratch/e1520508/Depth-Anything-3/da3_streaming
#   LANES_DIR      : default $REPO_DIR/scripts/lanes
#   DISK_USE_LIMIT : default 95 ; if df% on OUT_BASE goes above, lane exits cleanly
#   CUDA_VISIBLE_DEVICES : already exported by caller, passed through to children

set -u
set -o pipefail

: "${LANE:?LANE env var required (lane index)}"
: "${OUT_BASE:=/scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results}"
: "${REPO_DIR:=/scratch/e1520508/Depth-Anything-3/da3_streaming}"
: "${LANES_DIR:=${REPO_DIR}/scripts/lanes}"
: "${DISK_USE_LIMIT:=95}"

LIST="${LANES_DIR}/videos_lane_${LANE}.txt"
if [[ ! -f "${LIST}" ]]; then
    echo "No lane list: ${LIST}" >&2
    exit 1
fi

mkdir -p "${OUT_BASE}/logs"
FAILED="${OUT_BASE}/lane_${LANE}_failed.txt"
PROCESS_ONE="${REPO_DIR}/scripts/process_one_video.sh"

job_tag="${PBS_JOBID:-shell$$}"
echo "[$(date +%FT%T)] lane=${LANE} job=${job_tag} gpu=${CUDA_VISIBLE_DEVICES:-?} list=${LIST}"
total=$(wc -l < "${LIST}")
echo "[$(date +%FT%T)] lane=${LANE} videos_in_list=${total} MAX_VIDEOS=${MAX_VIDEOS:-none}"

count=0
ok=0
fail=0
skip=0
while IFS= read -r VIDEO; do
    [[ -z "${VIDEO}" ]] && continue

    if [[ -n "${MAX_VIDEOS:-}" && "${count}" -ge "${MAX_VIDEOS}" ]]; then
        echo "[$(date +%FT%T)] lane=${LANE} MAX_VIDEOS=${MAX_VIDEOS} reached, stopping."
        break
    fi

    # Disk-full guard (check every 10 videos to keep overhead low).
    if (( count % 10 == 0 )); then
        use=$(df --output=pcent "${OUT_BASE}" | tail -1 | tr -d ' %')
        if [[ -n "${use}" && "${use}" -ge "${DISK_USE_LIMIT}" ]]; then
            echo "[$(date +%FT%T)] lane=${LANE} disk use ${use}% >= ${DISK_USE_LIMIT}%, exiting." >&2
            exit 3
        fi
    fi

    count=$((count + 1))
    if [[ -f "${OUT_BASE}/${VIDEO}.done" ]]; then
        skip=$((skip + 1))
        continue
    fi

    log_file="${OUT_BASE}/logs/${job_tag}_lane${LANE}_${VIDEO}.log"
    echo "[$(date +%FT%T)] lane=${LANE} (${count}/${total}) start ${VIDEO}"
    if "${PROCESS_ONE}" "${VIDEO}" >"${log_file}" 2>&1; then
        ok=$((ok + 1))
    else
        rc=$?
        fail=$((fail + 1))
        echo "${VIDEO}\trc=${rc}\tlog=${log_file}" >> "${FAILED}"
        echo "[$(date +%FT%T)] lane=${LANE} FAIL ${VIDEO} rc=${rc}, see ${log_file}" >&2
    fi
done < "${LIST}"

echo "[$(date +%FT%T)] lane=${LANE} DONE processed=${count} ok=${ok} skip=${skip} fail=${fail}"
