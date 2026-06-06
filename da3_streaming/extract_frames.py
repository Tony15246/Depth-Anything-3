import cv2
import os
import argparse


def extract_frames(video_path, output_dir, width=640):
    """Extract frames from video, scaled to target width (height auto-adjusted)."""
    os.makedirs(output_dir, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Error: Cannot open video {video_path}")
        return

    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    digits = max(6, len(str(total)))
    idx = 0
    interval = max(1, total // 100)  # progress print every ~1%

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        h, w = frame.shape[:2]
        if w != width:
            new_h = int(h * width / w)
            frame = cv2.resize(frame, (width, new_h), interpolation=cv2.INTER_AREA)

        out_path = os.path.join(output_dir, f"frame_{idx:06d}.png")
        cv2.imwrite(out_path, frame)

        if idx % interval == 0:
            print(f"\r{idx + 1}/{total} frames extracted", end="", flush=True)
        idx += 1

    cap.release()
    print(f"\nDone. {idx} frames saved to {output_dir}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract frames from video (FFmpeg replacement)")
    parser.add_argument("video", help="Path to input video file")
    parser.add_argument("-o", "--output", default="./extract_images", help="Output directory (default: ./extract_images)")
    parser.add_argument("-w", "--width", type=int, default=640, help="Target width, height auto-scaled (default: 640)")
    args = parser.parse_args()

    extract_frames(args.video, args.output, args.width)
