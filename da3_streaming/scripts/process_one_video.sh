#!/bin/bash
# Process a single dashcam video: extract frames -> run DA3 -> stage outputs -> mark .done.
#
# Inputs (env or args):
#   $1                : video id (e.g. 0010bc54). The actual file is $VIDEO_DIR/${id}_front.mp4.
#   VIDEO_DIR         : default /scratch/e1520508/rgb_mp4
#   OUT_BASE          : default /scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results
#   REPO_DIR          : default /scratch/e1520508/Depth-Anything-3/da3_streaming
#   BATCH_CONFIG      : default $REPO_DIR/configs/batch_config.yaml
#   TMP_BASE          : default ${TMPDIR:-/tmp}
#   FRAME_WIDTH       : default 640 (input to DA3 will then resize to 560x308)
#
# Exit codes:
#   0 success (or already done)
#   1 invalid usage / missing video
#   2 frame extraction failed
#   3 inference failed
#   4 staging outputs failed

set -u
set -o pipefail

VIDEO_ID="${1:-}"
if [[ -z "${VIDEO_ID}" ]]; then
    echo "Usage: $0 <video_id>" >&2
    exit 1
fi

: "${VIDEO_DIR:=/scratch/e1520508/rgb_mp4}"
: "${OUT_BASE:=/scratch/Projects/CFP-04/CFP04-CF-039/e1520508_depth_results}"
: "${REPO_DIR:=/scratch/e1520508/Depth-Anything-3/da3_streaming}"
: "${BATCH_CONFIG:=${REPO_DIR}/configs/batch_config.yaml}"
: "${TMP_BASE:=${TMPDIR:-/tmp}}"
: "${FRAME_WIDTH:=640}"

SRC="${VIDEO_DIR}/${VIDEO_ID}_front.mp4"
DONE_MARK="${OUT_BASE}/${VIDEO_ID}.done"
OUT_DIR="${OUT_BASE}/${VIDEO_ID}"
WORK="${TMP_BASE}/da3_${VIDEO_ID}_$$"

if [[ -f "${DONE_MARK}" ]]; then
    echo "[$(date +%T)] [${VIDEO_ID}] already done, skipping."
    exit 0
fi

if [[ ! -f "${SRC}" ]]; then
    echo "[$(date +%T)] [${VIDEO_ID}] source missing: ${SRC}" >&2
    exit 1
fi

mkdir -p "${WORK}/frames" "${OUT_BASE}"
trap 'rm -rf "${WORK}"' EXIT

echo "[$(date +%T)] [${VIDEO_ID}] extracting frames -> ${WORK}/frames"
python "${REPO_DIR}/extract_frames.py" "${SRC}" -o "${WORK}/frames" -w "${FRAME_WIDTH}" \
    >"${WORK}/extract.log" 2>&1
nfr=$(ls "${WORK}/frames" 2>/dev/null | wc -l)
if [[ "${nfr}" -lt 1 ]]; then
    echo "[$(date +%T)] [${VIDEO_ID}] frame extraction failed (${nfr} frames)" >&2
    cat "${WORK}/extract.log" >&2 || true
    exit 2
fi
echo "[$(date +%T)] [${VIDEO_ID}] extracted ${nfr} frames"

echo "[$(date +%T)] [${VIDEO_ID}] running DA3 inference"
python "${REPO_DIR}/da3_streaming.py" \
    --image_dir "${WORK}/frames" \
    --config   "${BATCH_CONFIG}" \
    --output_dir "${WORK}/out" \
    --no_save_pcd \
    --no_include_image \
    --include_conf \
    --depth_dtype float16 \
    --conf_dtype  float16 \
    >"${WORK}/infer.log" 2>&1
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "[$(date +%T)] [${VIDEO_ID}] inference failed (rc=${rc})" >&2
    tail -n 40 "${WORK}/infer.log" >&2 || true
    exit 3
fi

NPZ="${WORK}/out/results_output/frames.npz"
if [[ ! -f "${NPZ}" ]]; then
    echo "[$(date +%T)] [${VIDEO_ID}] missing output ${NPZ}" >&2
    tail -n 40 "${WORK}/infer.log" >&2 || true
    exit 3
fi

mkdir -p "${OUT_DIR}"
cp "${NPZ}" "${OUT_DIR}/frames.npz" || { echo "stage npz failed" >&2; exit 4; }
for f in camera_poses.txt intrinsic.txt; do
    if [[ -f "${WORK}/out/${f}" ]]; then
        cp "${WORK}/out/${f}" "${OUT_DIR}/${f}"
    fi
done

sz=$(stat -c%s "${OUT_DIR}/frames.npz")
echo "[$(date +%T)] [${VIDEO_ID}] OK (npz=$(( sz / 1024 / 1024 )) MB, frames=${nfr})"

touch "${DONE_MARK}"
exit 0
