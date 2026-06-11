# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base

ARG HF_TOKEN=""

# Install Impact Pack via git clone — bypass the registry entirely.
# The registry doesn't have 8.28 and silent fallback to "latest" is the root
# cause of the FaceDetailer not found errors.
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack /comfyui/custom_nodes/comfyui-impact-pack && \
    cd /comfyui/custom_nodes/comfyui-impact-pack && \
    git fetch --tags && \
    git checkout 8.28 && \
    echo "Impact Pack: checked out $(git describe --tags --exact-match 2>/dev/null || git log --oneline -1)" && \
    pip install --no-cache-dir -r requirements.txt 2>&1 | tail -5 && \
    python install.py 2>&1 | tail -5

# Verify Impact Pack loaded after install
RUN cd /comfyui/custom_nodes/comfyui-impact-pack && \
    python -c "from impact.impact_pack import NODE_CLASS_MAPPINGS; assert 'FaceDetailer' in NODE_CLASS_MAPPINGS, 'FaceDetailer not in NODE_CLASS_MAPPINGS: ' + str(list(NODE_CLASS_MAPPINGS.keys())[:5]); print('FaceDetailer FOUND in', len(NODE_CLASS_MAPPINGS), 'nodes')"

# Install other custom nodes
RUN comfy node install comfyui-impact-subpack@1.3.5 --mode remote
RUN comfy node install comfyui-custom-scripts@1.2.5
RUN git clone https://github.com/mav-rik/facerestore_cf /comfyui/custom_nodes/facerestore_cf && cd /comfyui/custom_nodes/facerestore_cf && (git checkout 67f90bc6be976fb58169866155346b0da13bebee 2>/dev/null || (git fetch origin 67f90bc6be976fb58169866155346b0da13bebee --depth=1 && git checkout 67f90bc6be976fb58169866155346b0da13bebee) || echo "WARN: commit 67f90bc6be976fb58169866155346b0da13bebee unreachable")
RUN comfy node install comfyui_ipadapter_plus@2.0.0 --mode remote
RUN git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && cd /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && (git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca 2>/dev/null || (git fetch origin d78b780ae43fcf8c6b7c6505e6ffb4584281ceca --depth=1 && git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca) || echo "WARN: commit d78b780ae43fcf8c6b7c6505e6ffb4584281ceca unreachable")
RUN comfy node install comfyui-kjnodes@1.0.8

# Explicit deps for facerestore_cf and Impact Pack's model loaders
RUN pip install --no-cache-dir lpips filterpy ultralytics>=8.0.0

# download models into comfyui
# face detection yolo for impact pack / face detailer
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt' --relative-path models/ultralytics --filename 'bbox/face_yolov8m.pt' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done

# helper: retry a single model download with backoff.
RUN cat > /usr/local/bin/download_model.sh <<'EOF'
#!/bin/bash
set -e
URL="$1"
RPATH="$2"
FNAME="$3"
BACKOFFS="10 20 30 60 90"
for i in 1 2 3 4 5; do
  if comfy model download --url "$URL" --relative-path "$RPATH" --filename "$FNAME"; then
    echo "OK: $FNAME"
    exit 0
  fi
  if [ $i -eq 5 ]; then
    echo "FAIL: $FNAME after 5 attempts" >&2
    exit 1
  fi
  SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i)
  echo "RETRY $i: $FNAME (sleep $SLEEP s)" >&2
  sleep "$SLEEP"
done
EOF
RUN chmod +x /usr/local/bin/download_model.sh

# checkpoints
RUN download_model.sh 'https://madville.org/ai/models/dreamshaper_8.safetensors'           'models/checkpoints' 'dreamshaper_8.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/SDXL/photonicFusionSDXL_final-005.safetensors' 'models/checkpoints/SDXL' 'PhotonicFusionSDXL_V.1.3.safetensors'
