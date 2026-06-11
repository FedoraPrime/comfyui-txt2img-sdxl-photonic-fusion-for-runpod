# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base
ARG HF_TOKEN=""

# Strict bash: exit on error (-e), print commands (-x), fail on pipe (-o pipefail)
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]

# ═══════════════════════════════════════════════════════════════
#  IMPACT PACK — manual git clone to guarantee version 8.28
# ═══════════════════════════════════════════════════════════════

# Step 1: Clone the repo
RUN echo ">>> Cloning Impact Pack..." && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack \
      /comfyui/custom_nodes/comfyui-impact-pack

WORKDIR /comfyui/custom_nodes/comfyui-impact-pack

# Step 2: Checkout the right version (with fallbacks)
RUN echo ">>> Fetching tags..." && \
    git fetch --tags && \
    echo ">>> Checking out version 8.28..." && \
    (git checkout 8.28 2>&1 || git checkout v8.28 2>&1 || \
     { echo "WARN: tags 8.28/v8.28 not found, listing available tags:"; \
       git tag -l | grep -E "^[0-9v]" | sort -V | tail -10; \
       LATEST=$(git tag -l | grep -E "^[0-9]" | sort -V | tail -1); \
       echo ">>> Falling back to $LATEST"; \
       git checkout "$LATEST"; }) && \
    echo ">>> Impact Pack version: $(git describe --tags --always 2>/dev/null || git log --oneline -1)"

# Step 3: Install Python requirements (separate layer — verbose output)
RUN echo ">>> Installing Impact Pack Python requirements..." && \
    pip install --no-cache-dir -r requirements.txt 2>&1 | tail -20 && \
    echo ">>> Requirements installed OK"

# Step 4: Run install.py with a timeout — it hangs trying to download models
RUN echo ">>> Running Impact Pack install.py (timeout 180s)..." && \
    timeout 180 python install.py 2>&1 | tail -30; \
    EXIT_CODE=${PIPESTATUS[0]}; \
    if [ "$EXIT_CODE" -eq 0 ]; then \
      echo ">>> install.py completed successfully"; \
    elif [ "$EXIT_CODE" -eq 124 ]; then \
      echo ">>> WARN: install.py timed out after 180s (expected — it tries to download models)"; \
    else \
      echo ">>> WARN: install.py exited with code $EXIT_CODE"; \
    fi

# Step 5: Verify FaceDetailer is present — this is the whole reason we're here
RUN echo ">>> Verifying FaceDetailer node..." && \
    python -c "\
from impact.impact_pack import NODE_CLASS_MAPPINGS; \
keys = sorted(NODE_CLASS_MAPPINGS.keys()); \
assert 'FaceDetailer' in NODE_CLASS_MAPPINGS, \
  'FAILED: FaceDetailer not found. Available nodes (' + str(len(keys)) + '): ' + str(keys[:20]); \
print('SUCCESS: FaceDetailer found in', len(NODE_CLASS_MAPPINGS), 'Impact Pack nodes')"

# ═══════════════════════════════════════════════════════════════
#  OTHER CUSTOM NODES
# ═══════════════════════════════════════════════════════════════

# Impact Subpack (companion to Impact Pack)
RUN comfy node install comfyui-impact-subpack@1.3.5 --mode remote

# Custom Scripts
RUN comfy node install comfyui-custom-scripts@1.2.5

# FaceRestore CF (pinned to specific commit)
RUN git clone https://github.com/mav-rik/facerestore_cf \
      /comfyui/custom_nodes/facerestore_cf && \
    cd /comfyui/custom_nodes/facerestore_cf && \
    (git checkout 67f90bc6be976fb58169866155346b0da13bebee 2>/dev/null || \
     (git fetch origin 67f90bc6be976fb58169866155346b0da13bebee --depth=1 && \
      git checkout 67f90bc6be976fb58169866155346b0da13bebee) || \
     echo "WARN: commit 67f90bc6be976fb58169866155346b0da13bebee unreachable")

# IPAdapter Plus
RUN comfy node install comfyui_ipadapter_plus@2.0.0 --mode remote

# Comfyroll (pinned to specific commit)
RUN git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes \
      /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && \
    cd /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && \
    (git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca 2>/dev/null || \
     (git fetch origin d78b780ae43fcf8c6b7c6505e6ffb4584281ceca --depth=1 && \
      git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca) || \
     echo "WARN: commit d78b780ae43fcf8c6b7c6505e6ffb4584281ceca unreachable")

# KJNodes
RUN comfy node install comfyui-kjnodes@1.0.8

# ═══════════════════════════════════════════════════════════════
#  EXPLICIT PIP DEPS (facerestore_cf + Impact Pack model loaders)
# ═══════════════════════════════════════════════════════════════

RUN pip install --no-cache-dir lpips filterpy "ultralytics>=8.0.0"

# ═══════════════════════════════════════════════════════════════
#  MODEL DOWNLOADS
# ═══════════════════════════════════════════════════════════════

# Helper: retry a single model download with exponential backoff
RUN cat > /usr/local/bin/download_model.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
URL="$1"
RPATH="$2"
FNAME="$3"
BACKOFFS=(10 20 30 60 90)
for i in 0 1 2 3 4; do
  if comfy model download --url "$URL" --relative-path "$RPATH" --filename "$FNAME"; then
    echo "OK: $FNAME"
    exit 0
  fi
  if [ $i -eq 4 ]; then
    echo "FAIL: $FNAME after 5 attempts" >&2
    exit 1
  fi
  echo "RETRY $((i+1)): $FNAME (sleep ${BACKOFFS[$i]}s)" >&2
  sleep "${BACKOFFS[$i]}"
done
SCRIPT
RUN chmod +x /usr/local/bin/download_model.sh

# Face detection YOLO for Impact Pack / FaceDetailer
RUN download_model.sh \
    'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt' \
    'models/ultralytics' \
    'bbox/face_yolov8m.pt'

# Checkpoints
RUN download_model.sh \
    'https://madville.org/ai/models/dreamshaper_8.safetensors' \
    'models/checkpoints' \
    'dreamshaper_8.safetensors'

RUN download_model.sh \
    'https://madville.org/ai/models/SDXL/photonicFusionSDXL_final-005.safetensors' \
    'models/checkpoints/SDXL' \
    'PhotonicFusionSDXL_V.1.3.safetensors'
