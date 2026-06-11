# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base

ARG HF_TOKEN=""

# Stop the build on any failure so we can see exactly what went wrong.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# install custom nodes — hard-fail if any of these don't install
RUN comfy node install comfyui-impact-subpack@1.3.5 --mode remote
RUN comfy node install comfyui-custom-scripts@1.2.5
RUN comfy node install comfyui-impact-pack@8.28 --mode remote
RUN git clone https://github.com/mav-rik/facerestore_cf /comfyui/custom_nodes/facerestore_cf && cd /comfyui/custom_nodes/facerestore_cf && (git checkout 67f90bc6be976fb58169866155346b0da13bebee 2>/dev/null || (git fetch origin 67f90bc6be976fb58169866155346b0da13bebee --depth=1 && git checkout 67f90bc6be976fb58169866155346b0da13bebee) || echo "WARN: commit 67f90bc6be976fb58169866155346b0da13bebee unreachable in https://github.com/mav-rik/facerestore_cf, falling back to default branch HEAD")
RUN comfy node install comfyui_ipadapter_plus@2.0.0 --mode remote
RUN git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && cd /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && (git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca 2>/dev/null || (git fetch origin d78b780ae43fcf8c6b7c6505e6ffb4584281ceca --depth=1 && git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca) || echo "WARN: commit d78b780ae43fcf8c6b7c6505e6ffb4584281ceca unreachable in https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes, falling back to default branch HEAD")
RUN comfy node install comfyui-kjnodes@1.0.8

# Explicit deps for facerestore_cf and Impact Pack's model loaders
RUN pip install --no-cache-dir lpips filterpy ultralytics>=8.0.0

# download models into comfyui
# face detection yolo for impact pack / face detailer
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt' --relative-path models/ultralytics --filename 'bbox/face_yolov8m.pt' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done

# helper: retry a single model download with backoff. usage: download_model <url> <relative-path> <filename>
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

# checkpoints (SDXL / SD 1.5) — all available at https://madville.org/ai/models/
RUN download_model.sh 'https://madville.org/ai/models/dreamshaper_8.safetensors'           'models/checkpoints' 'dreamshaper_8.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/SDXL/photonicFusionSDXL_final-005.safetensors' 'models/checkpoints/SDXL' 'PhotonicFusionSDXL_V.1.3.safetensors'
