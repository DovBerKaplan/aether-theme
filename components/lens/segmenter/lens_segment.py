#!/usr/bin/env python3
"""aether-lens segmenter: a resident helper that answers "what object is under this point?".

MobileSAM (via ultralytics) embeds the frozen screen once - a couple of seconds, in the background -
and then every tap is a prompt on that embedding, about 50 ms. Offline: it never touches the network.

Protocol, one JSON object per line.
  in : {"cmd": "image", "path": "<bmp/png>"}          embed this frame (physical pixels)
       {"cmd": "point", "id": N, "x": px, "y": px}     the object at the point
       {"cmd": "quit"}
  out: {"event": "ready"}                              the embedding is done
       {"id": N, "rect": [x, y, w, h] | null}          the answer, physical pixels
Exits by itself after IDLE seconds without a command.
"""
import json
import os
import select
import sys
import time

os.environ.setdefault("YOLO_OFFLINE", "1")
os.environ.setdefault("YOLO_VERBOSE", "False")

IDLE = 180
MODEL = os.path.join(os.path.expanduser("~"), ".local/share/aether-lens/models/mobile_sam.pt")


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    import cv2
    import numpy as np
    import torch
    from ultralytics.models.sam import Predictor

    torch.set_num_threads(max(2, (os.cpu_count() or 4) - 2))
    predictor = Predictor(overrides=dict(conf=0.25, task="segment", mode="predict", imgsz=1024,
                                         model=MODEL, save=False, verbose=False))
    have_image = False
    last = time.time()
    send({"event": "loaded"})
    while True:
        ready, _, _ = select.select([sys.stdin], [], [], 5.0)
        if not ready:
            if time.time() - last > IDLE:
                return
            continue
        line = sys.stdin.readline()
        if not line:
            return
        last = time.time()
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        cmd = msg.get("cmd")
        if cmd == "quit":
            return
        if cmd == "image":
            img = cv2.imread(msg["path"])
            if img is None:
                send({"event": "error", "what": "image"})
                continue
            predictor.set_image(img)
            have_image = True
            send({"event": "ready"})
        elif cmd == "point":
            rect = None
            if have_image:
                results = predictor(points=[[msg["x"], msg["y"]]], labels=[1])
                if results and results[0].masks is not None and len(results[0].masks.data):
                    ys, xs = np.where(results[0].masks.data[0].cpu().numpy() > 0)
                    if len(xs):
                        rect = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
            send({"id": msg.get("id", 0), "rect": rect})


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
