import os
import traceback

import openpi.shared.download as download


def main() -> None:
    url = os.environ.get("CHECKPOINT_PATH", "gs://openpi-assets/checkpoints/pi05_libero")
    print(f"[openpi] Pre-downloading checkpoint: {url}")
    try:
        path = download.maybe_download(url, gs={"token": "anon"})
    except Exception as e:
        print(f"[openpi] download failed: {e}.")
        raise
    print(f"[openpi] Checkpoint cached at: {path}")


if __name__ == "__main__":
    main()

