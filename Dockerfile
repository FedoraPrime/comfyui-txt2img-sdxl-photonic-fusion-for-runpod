# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base

# build-time tokens for gated downloads — never baked into final image.
# pass via: docker build --build-arg HF_TOKEN=$HF_TOKEN ...
ARG HF_TOKEN=""

# install custom nodes into comfyui
RUN comfy node install --exit-on-fail comfyui-impact-subpack@1.2.9 --mode remote || (echo "WARN: comfyui-impact-subpack@1.2.9 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-impact-subpack --mode remote)
RUN comfy node install --exit-on-fail comfyui-custom-scripts@1.2.5 || (echo "WARN: comfyui-custom-scripts@1.2.5 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-custom-scripts)
RUN comfy node install --exit-on-fail comfyui-impact-pack@8.8.1 || (echo "WARN: comfyui-impact-pack@8.8.1 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-impact-pack)

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
RUN download_model.sh 'https://madville.org/ai/models/photonicFusionSDXL_final-005.safetensors' 'models/checkpoints/SDXL' 'PhotonicFusionSDXL_V.1.3.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/cyberrealisticXL_v70.safetensors'     'models/checkpoints/SDXL' 'cyberrealisticXL_v70.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/epicrealismXL_xxxlLastfameRealism.safetensors' 'models/checkpoints/SDXL' 'epicrealismXL_xxxlLastfameRealism.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors' 'models/checkpoints/SDXL' 'juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/photorealisticAllPurpose_v40-002.safetensors' 'models/checkpoints/SDXL' 'photorealisticAllPurpose_v40-002.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/pornworksBadBoysPhoto_v06-004.safetensors' 'models/checkpoints/SDXL' 'pornworksBadBoysPhoto_v06-004.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/realvisxlV50_v40Bakedvae.safetensors' 'models/checkpoints/SDXL' 'realvisxlV50_v40Bakedvae.safetensors'
RUN download_model.sh 'https://madville.org/ai/models/Sony_Lens_XL-003.safetensors'         'models/checkpoints/SDXL' 'Sony_Lens_XL-003.safetensors'
