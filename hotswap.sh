#!/bin/bash
# Author: FNGarvin
# License: MIT

INPUT="$1"
NAME=$(basename "$0")
BASE_NAME="${INPUT%.*}"
CSV="logs/${BASE_NAME}.stats.csv"

# Configuration Placeholders
COMFY_HOME="[COMFY_UI_PATH]"
COMFY_INPUT="${COMFY_HOME}/input"
COMFY_OUTPUT="${COMFY_HOME}/output"
COMFY_API="http://[INTERNAL_IP]:[PORT]/prompt"

DEST_DIR="stylizedframes"
RESULTS_DIR="results"

if [[ -z "$INPUT" ]]; then
    printf "Usage: %s [filename.mp4]\n" "$NAME"
    exit 1
fi

# 1. Environment Prep
printf "[%s] Resetting workspace...\n" "$(date +%T)"
rm -rf segments logs "$DEST_DIR" "$RESULTS_DIR"
mkdir -p segments logs "$DEST_DIR" "$RESULTS_DIR" "${COMFY_INPUT}/wananimate" "${COMFY_INPUT}/persona"

if [[ ! -f "wizard.png" ]]; then
    printf "CRITICAL: wizard.png missing.\n"
    exit 1
fi
cp "wizard.png" "${COMFY_INPUT}/persona/wizard.png"

# 2. Scene Detection
printf "[%s] Detecting scenes...\n" "$(date +%T)"
docker run --rm -v "$(pwd):/files:z" ghcr.io/fngarvin/pyscenedetect:fng-infra-docker-ci -i "/files/$INPUT" detect-adaptive list-scenes -f "/files/$CSV"

if [[ ! -f "$CSV" ]]; then
    printf "CRITICAL: Scene detection failed.\n"
    exit 1
fi

grep -E '^[0-9]+,' "$CSV" > logs/scenes_clean.csv

# 3. Pass 1: Flux 2 Klein Stylization
QUEUED_COUNT=0
while IFS=, read -u 3 -r scene_num start_frame start_timecode start_sec end_frame end_timecode end_sec rest; do
    IDX=$(echo "$scene_num" | tr -d '[:space:]' | sed 's/^0*//')
    [[ -z "$IDX" ]] && IDX=0
    
    ST_TC=$(echo "$start_timecode" | tr -d '[:space:]')
    DUR=$(echo "$end_sec - $start_sec" | bc)
    
    FRAME="segments/ref_${IDX}.png"
    VIDEO="segments/ref_${IDX}.mp4"
    
    ffmpeg -y -hide_banner -loglevel error -ss "$ST_TC" -i "$INPUT" -vframes 1 -vf "scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2" "$FRAME"
    ffmpeg -y -hide_banner -loglevel error -ss "$ST_TC" -t "$DUR" -i "$INPUT" -c:v libx264 -crf 18 -pix_fmt yuv420p "$VIDEO"

    if [[ -f "$FRAME" && -f "$VIDEO" ]]; then
        cp "$FRAME" "${COMFY_INPUT}/persona/ref_${IDX}.png"
        cp "$VIDEO" "${COMFY_INPUT}/wananimate/segment_${IDX}.mp4"

        PAYLOAD="logs/queue_p1_${IDX}.json"
        cat <<EOF > "$PAYLOAD"
{
  "prompt": {
    "76": { "class_type": "LoadImage", "inputs": { "image": "persona/ref_${IDX}.png" } },
    "81": { "class_type": "LoadImage", "inputs": { "image": "persona/wizard.png" } },
    "94": { "class_type": "SaveImage", "inputs": { "filename_prefix": "persona/persona_${IDX}", "images": ["92:105", 0] } },
    "75:61": { "class_type": "KSamplerSelect", "inputs": { "sampler_name": "euler" } },
    "75:62": { "class_type": "Flux2Scheduler", "inputs": { "height": ["75:99", 1], "steps": 4, "width": ["75:99", 0] } },
    "75:63": { "class_type": "CFGGuider", "inputs": { "cfg": 1, "model": ["75:70", 0], "negative": ["75:79:100", 0], "positive": ["75:79:77", 0] } },
    "75:64": { "class_type": "SamplerCustomAdvanced", "inputs": { "guider": ["75:63", 0], "latent_image": ["75:66", 0], "noise": ["75:73", 0], "sampler": ["75:61", 0], "sigmas": ["75:62", 0] } },
    "75:65": { "class_type": "VAEDecode", "inputs": { "samples": ["75:64", 0], "vae": ["75:72", 0] } },
    "75:66": { "class_type": "EmptyFlux2LatentImage", "inputs": { "batch_size": 1, "height": ["75:99", 1], "width": ["75:99", 0] } },
    "75:70": { "class_type": "UNETLoader", "inputs": { "unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default" } },
    "75:71": { "class_type": "CLIPLoader", "inputs": { "clip_name": "qwen_3_4b.safetensors", "device": "default", "type": "flux2" } },
    "75:72": { "class_type": "VAELoader", "inputs": { "vae_name": "flux2-vae.safetensors" } },
    "75:73": { "class_type": "RandomNoise", "inputs": { "noise_seed": 80085 } },
    "75:74": { "class_type": "CLIPTextEncode", "inputs": { "clip": ["75:71", 0], "text": "Change the woman into a handsome asian man" } },
    "75:80": { "class_type": "ImageScaleToTotalPixels", "inputs": { "image": ["76", 0], "megapixels": 1, "resolution_steps": 1, "upscale_method": "nearest-exact" } },
    "75:82": { "class_type": "ConditioningZeroOut", "inputs": { "conditioning": ["75:74", 0] } },
    "75:99": { "class_type": "GetImageSize", "inputs": { "image": ["75:80", 0] } },
    "75:79:77": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["75:74", 0], "latent": ["75:79:78", 0] } },
    "75:79:78": { "class_type": "VAEEncode", "inputs": { "pixels": ["75:80", 0], "vae": ["75:72", 0] } },
    "75:79:100": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["75:82", 0], "latent": ["75:79:78", 0] } },
    "92:101": { "class_type": "KSamplerSelect", "inputs": { "sampler_name": "euler" } },
    "92:102": { "class_type": "Flux2Scheduler", "inputs": { "height": ["92:114", 1], "steps": 4, "width": ["92:114", 0] } },
    "92:103": { "class_type": "CFGGuider", "inputs": { "cfg": 1, "model": ["92:107", 0], "negative": ["92:84:118", 0], "positive": ["92:84:120", 0] } },
    "92:104": { "class_type": "SamplerCustomAdvanced", "inputs": { "guider": ["92:103", 0], "latent_image": ["92:113", 0], "noise": ["92:106", 0], "sampler": ["92:101", 0], "sigmas": ["92:102", 0] } },
    "92:105": { "class_type": "VAEDecode", "inputs": { "samples": ["92:104", 0], "vae": ["92:110", 0] } },
    "92:106": { "class_type": "RandomNoise", "inputs": { "noise_seed": 80085 } },
    "92:107": { "class_type": "UNETLoader", "inputs": { "unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default" } },
    "92:108": { "class_type": "CLIPLoader", "inputs": { "clip_name": "qwen_3_4b.safetensors", "device": "default", "type": "flux2" } },
    "92:109": { "class_type": "CLIPTextEncode", "inputs": { "clip": ["92:108", 0], "text": "stylize the person in image1 with illustrated style of image 2" } },
    "92:110": { "class_type": "VAELoader", "inputs": { "vae_name": "flux2-vae.safetensors" } },
    "92:111": { "class_type": "ImageScaleToTotalPixels", "inputs": { "image": ["75:65", 0], "megapixels": 1, "resolution_steps": 1, "upscale_method": "nearest-exact" } },
    "92:113": { "class_type": "EmptyFlux2LatentImage", "inputs": { "batch_size": 1, "height": ["92:114", 1], "width": ["92:114", 0] } },
    "92:114": { "class_type": "GetImageSize", "inputs": { "image": ["92:111", 0] } },
    "92:85": { "class_type": "ImageScaleToTotalPixels", "inputs": { "image": ["81", 0], "megapixels": 1, "resolution_steps": 1, "upscale_method": "nearest-exact" } },
    "92:86": { "class_type": "ConditioningZeroOut", "inputs": { "conditioning": ["92:109", 0] } },
    "92:84:118": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["92:112:115", 0], "latent": ["92:84:119", 0] } },
    "92:84:119": { "class_type": "VAEEncode", "inputs": { "pixels": ["92:85", 0], "vae": ["92:110", 0] } },
    "92:84:120": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["92:112:117", 0], "latent": ["92:84:119", 0] } },
    "92:112:115": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["92:86", 0], "latent": ["92:112:116", 0] } },
    "92:112:116": { "class_type": "VAEEncode", "inputs": { "pixels": ["92:111", 0], "vae": ["92:110", 0] } },
    "92:112:117": { "class_type": "ReferenceLatent", "inputs": { "conditioning": ["92:109", 0], "latent": ["92:112:116", 0] } }
  }
}
EOF
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d @"$PAYLOAD" "$COMFY_API")
        
        if echo "$RESPONSE" | grep -q "prompt_id"; then
            ((QUEUED_COUNT++))
            printf "[%s] Scene %s: Pass 1 Queued.\n" "$(date +%T)" "$IDX"
        else
            printf "[%s] Scene %s: Pass 1 REJECTED.\n" "$(date +%T)" "$IDX"
            echo "$RESPONSE" > "logs/error_p1_${IDX}.json"
        fi
    fi
done 3< logs/scenes_clean.csv

# 4. Polling Pass 1
printf "[%s] Waiting for %d stylized frames...\n" "$(date +%T)" "$QUEUED_COUNT"
[[ "$QUEUED_COUNT" -eq 0 ]] && exit 1

while true; do
    CURRENT=$(find "${COMFY_OUTPUT}/persona" -maxdepth 1 -type f -name "persona_*.png" 2>/dev/null | wc -l)
    printf "\rStylization Progress: %d/%d" "$CURRENT" "$QUEUED_COUNT"
    [[ "$CURRENT" -ge "$QUEUED_COUNT" ]] && break
    sleep 5
done
mv "${COMFY_OUTPUT}/persona"/persona_*.png "$DEST_DIR/"

# 5. Pass 2: Animation
printf "\n[%s] Queueing animation passes...\n" "$(date +%T)"
while IFS=, read -u 3 -r scene_num rest; do
    IDX=$(echo "$scene_num" | tr -d '[:space:]' | sed 's/^0*//')
    [[ -z "$IDX" ]] && IDX=0
    
    FRAME=$(find "$DEST_DIR" -maxdepth 1 -name "persona_${IDX}_*.png" | head -n 1)

    if [[ -f "$FRAME" ]]; then
        cp "$FRAME" "${COMFY_INPUT}/wananimate/stylized_${IDX}.png"
        
        PAYLOAD="logs/queue_p2_${IDX}.json"
        cat <<EOF > "$PAYLOAD"
{
  "prompt": {
    "22": { "inputs": { "model": "Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors", "base_precision": "fp16_fast", "quantization": "disabled", "load_device": "offload_device", "attention_mode": "sageattn", "rms_norm_function": "default", "compile_args": ["35", 0] }, "class_type": "WanVideoModelLoader" },
    "27": { "inputs": { "steps": 4, "cfg": 1, "shift": 5, "seed": 42, "force_offload": true, "scheduler": "dpm++_sde", "riflex_freq_index": 0, "denoise_strength": 1, "batched_cfg": "", "rope_function": "comfy", "start_step": 0, "end_step": -1, "add_noise_to_samples": false, "model": ["50", 0], "image_embeds": ["62", 0], "text_embeds": ["65", 0] }, "class_type": "WanVideoSampler" },
    "28": { "inputs": { "enable_vae_tiling": false, "tile_x": 272, "tile_y": 272, "tile_stride_x": 144, "tile_stride_y": 128, "normalization": "default", "vae": ["38", 0], "samples": ["27", 0] }, "class_type": "WanVideoDecode" },
    "30": { "inputs": { "frame_rate": 16, "loop_count": 0, "filename_prefix": "wananimate/composite_${IDX}", "format": "video/h264-mp4", "pix_fmt": "yuv420p", "crf": 19, "save_metadata": true, "trim_to_audio": true, "pingpong": false, "save_output": true, "images": ["66", 0], "audio": ["63", 2] }, "class_type": "VHS_VideoCombine" },
    "35": { "inputs": { "backend": "inductor", "fullgraph": false, "mode": "default", "dynamic": false, "dynamo_cache_size_limit": 64, "compile_transformer_blocks_only": true, "dynamo_recompile_limit": 128, "force_parameter_static_shapes": false, "allow_unmerged_lora_compile": false }, "class_type": "WanVideoTorchCompileSettings" },
    "38": { "inputs": { "model_name": "Wan2_1_VAE_bf16.safetensors", "precision": "bf16", "use_cpu_cache": false, "verbose": false }, "class_type": "WanVideoVAELoader" },
    "42": { "inputs": { "image": ["28", 0] }, "class_type": "GetImageSizeAndCount" },
    "48": { "inputs": { "model": ["22", 0], "lora": ["171", 0] }, "class_type": "WanVideoSetLoRAs" },
    "50": { "inputs": { "model": ["48", 0], "block_swap_args": ["51", 0] }, "class_type": "WanVideoSetBlockSwap" },
    "51": { "inputs": { "blocks_to_swap": 25, "offload_img_emb": false, "offload_txt_emb": false, "use_non_blocking": true, "vace_blocks_to_swap": 0, "prefetch_blocks": 1, "block_swap_debug": false }, "class_type": "WanVideoBlockSwap" },
    "57": { "inputs": { "image": "wananimate/stylized_${IDX}.png" }, "class_type": "LoadImage" },
    "62": { "inputs": { "width": ["150", 0], "height": ["151", 0], "num_frames": ["63", 1], "force_offload": false, "frame_window_size": 77, "colormatch": "disabled", "pose_strength": 1, "face_strength": 1, "tiled_vae": false, "vae": ["38", 0], "clip_embeds": ["70", 0], "ref_images": ["64", 0], "pose_images": ["173", 0], "face_images": ["172", 1], "bg_images": ["99", 0], "mask": ["108", 0] }, "class_type": "WanVideoAnimateEmbeds" },
    "63": { "inputs": { "video": "wananimate/segment_${IDX}.mp4", "force_rate": 16, "custom_width": ["150", 0], "custom_height": ["151", 0], "frame_load_cap": 0, "skip_first_frames": 0, "select_every_nth": 1, "format": "AnimateDiff" }, "class_type": "VHS_LoadVideo" },
    "64": { "inputs": { "width": ["150", 0], "height": ["151", 0], "upscale_method": "lanczos", "keep_proportion": "pad_edge_pixel", "pad_color": "0, 0, 0", "crop_position": "top", "divisible_by": 16, "device": "cpu", "image": ["57", 0] }, "class_type": "ImageResizeKJv2" },
    "65": { "inputs": { "model_name": "umt5-xxl-enc-bf16.safetensors", "precision": "bf16", "positive_prompt": "the person is talking", "negative_prompt": "色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走", "quantization": "disabled", "use_disk_cache": false, "device": "gpu" }, "class_type": "WanVideoTextEncodeCached" },
    "66": { "inputs": { "inputcount": 2, "direction": "left", "match_image_size": true, "Update inputs": null, "image_1": ["42", 0], "image_2": ["77", 0] }, "class_type": "ImageConcatMulti" },
    "70": { "inputs": { "strength_1": 1, "strength_2": 1, "crop": "center", "combine_embeds": "average", "force_offload": true, "tiles": 0, "ratio": 0.5, "clip_vision": ["71", 0], "image_1": ["64", 0] }, "class_type": "WanVideoClipVisionEncode" },
    "71": { "inputs": { "clip_name": "clip_vision_h.safetensors" }, "class_type": "CLIPVisionLoader" },
    "75": { "inputs": { "frame_rate": 16, "loop_count": 0, "filename_prefix": "wananimate/WanVideo2_1_T2V_${IDX}", "format": "video/h264-mp4", "pix_fmt": "yuv420p", "crf": 19, "save_metadata": true, "trim_to_audio": false, "pingpong": false, "save_output": false, "images": ["99", 0] }, "class_type": "VHS_VideoCombine" },
    "77": { "inputs": { "inputcount": 4, "direction": "down", "match_image_size": true, "Update inputs": null, "image_1": ["64", 0], "image_2": ["172", 1], "image_3": ["173", 0], "image_4": ["63", 0] }, "class_type": "ImageConcatMulti" },
    "99": { "inputs": { "color": "0, 0, 0", "device": "cpu", "image": ["63", 0], "mask": ["108", 0] }, "class_type": "DrawMaskOnImage" },
    "102": { "inputs": { "model": "sam2.1_hiera_base_plus.safetensors", "segmentor": "video", "device": "cuda", "precision": "fp16" }, "class_type": "DownloadAndLoadSAM2Model" },
    "104": { "inputs": { "keep_model_loaded": false, "individual_objects": false, "sam2_model": ["102", 0], "image": ["180", 0], "bboxes": ["172", 3] }, "class_type": "Sam2Segmentation" },
    "108": { "inputs": { "block_size": 32, "device": "cpu", "masks": ["182", 0] }, "class_type": "BlockifyMask" },
    "110": { "inputs": { "context_schedule": "static_standard", "context_frames": 81, "context_stride": 4, "context_overlap": 32, "freenoise": true, "verbose": false, "fuse_method": "linear" }, "class_type": "WanVideoContextOptions" },
    "150": { "inputs": { "value": 512 }, "class_type": "INTConstant" },
    "151": { "inputs": { "value": 512 }, "class_type": "INTConstant" },
    "171": { "inputs": { "lora_0": "WanAnimate_relight_lora_fp16.safetensors", "strength_0": 1, "lora_1": "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors", "strength_1": 1.2, "lora_2": "none", "strength_2": 1, "lora_3": "none", "strength_3": 1, "lora_4": "none", "strength_4": 1, "low_mem_load": false, "merge_loras": false }, "class_type": "WanVideoLoraSelectMulti" },
    "172": { "inputs": { "width": ["180", 1], "height": ["180", 2], "face_padding": 0, "model": ["178", 0], "images": ["180", 0] }, "class_type": "PoseAndFaceDetection" },
    "173": { "inputs": { "width": ["180", 1], "height": ["180", 2], "retarget_padding": 16, "body_stick_width": -1, "hand_stick_width": -1, "draw_head": "True", "pose_data": ["172", 0] }, "class_type": "DrawViTPose" },
    "174": { "inputs": { "frame_rate": 16, "loop_count": 0, "filename_prefix": "wananimate/vitpose_${IDX}", "format": "video/h264-mp4", "pix_fmt": "yuv420p", "crf": 19, "save_metadata": true, "trim_to_audio": false, "pingpong": false, "save_output": false, "images": ["172", 1] }, "class_type": "VHS_VideoCombine" },
    "178": { "inputs": { "vitpose_model": "vitpose-l-wholebody.onnx", "yolo_model": "onnx/yolov10m.onnx", "onnx_device": "CUDAExecutionProvider" }, "class_type": "OnnxDetectionModelLoader" },
    "180": { "inputs": { "image": ["63", 0] }, "class_type": "GetImageSizeAndCount" },
    "181": { "inputs": { "frame_rate": 16, "loop_count": 0, "filename_prefix": "wananimate/WanVideo2_1_T2V_pose_${IDX}", "format": "video/h264-mp4", "pix_fmt": "yuv420p", "crf": 19, "save_metadata": true, "trim_to_audio": false, "pingpong": false, "save_output": false, "images": ["173", 0] }, "class_type": "VHS_VideoCombine" },
    "182": { "inputs": { "expand": 10, "incremental_expandrate": 0, "tapered_corners": true, "flip_input": false, "blur_radius": 0, "lerp_alpha": 1, "decay_factor": 1, "fill_holes": false, "mask": ["104", 0] }, "class_type": "GrowMaskWithBlur" },
    "187": { "inputs": { "frame_rate": 16, "loop_count": 0, "filename_prefix": "wananimate/swapped_${IDX}", "format": "video/h264-mp4", "pix_fmt": "yuv420p", "crf": 19, "save_metadata": true, "trim_to_audio": true, "pingpong": false, "save_output": true, "images": ["28", 0], "audio": ["63", 2] }, "class_type": "VHS_VideoCombine" },
    "188": { "inputs": { "inputcount": 2, "direction": "left", "match_image_size": true, "Update inputs": null, "image_1": ["42", 0] }, "class_type": "ImageConcatMulti" }
  }
}
EOF
        curl -s -X POST -H "Content-Type: application/json" -d @"$PAYLOAD" "$COMFY_API" > /dev/null
    fi
done 3< logs/scenes_clean.csv

# 6. Final Wait & Concat
while true; do
    CURRENT=$(find "${COMFY_OUTPUT}/wananimate" -maxdepth 1 -type f -name "swapped_*.mp4" 2>/dev/null | wc -l)
    printf "\rAnimation Progress: %d/%d" "$CURRENT" "$QUEUED_COUNT"
    [[ "$CURRENT" -ge "$QUEUED_COUNT" ]] && break
    sleep 5
done

mv "${COMFY_OUTPUT}/wananimate"/swapped_*.mp4 "$RESULTS_DIR/"
find "$(pwd)/$RESULTS_DIR" -name "swapped_*.mp4" | sort -V | sed "s/^/file '/;s/$/'/" > logs/concat.txt
ffmpeg -y -f concat -safe 0 -i logs/concat.txt -c copy "${BASE_NAME}.transformed.mp4"

printf "\n[%s] Transformed video: %s.transformed.mp4\n" "$(date +%T)" "$BASE_NAME"

#EOF hotswap.sh
