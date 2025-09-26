FROM vllm/vllm-openai:v0.10.1

# Set environment variables for vLLM and Hugging Face
ENV MODEL_NAME=google/gemma-3-1b-it
ENV HF_HOME=/model-cache

# Install curl for the pre-warming step and clean up apt cache to reduce image size.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Set comprehensive logging for debugging
ENV VLLM_LOGGING_LEVEL=DEBUG
ENV PYTHONUNBUFFERED=1
ENV VLLM_LOGGING_CONFIG_PATH=""
# Force CPU device detection for vLLM
ENV CUDA_VISIBLE_DEVICES=""
ENV VLLM_USE_MODELSCOPE=False

# Download the model weights from Hugging Face during build.
# This caches the model locally to avoid download at runtime.
RUN --mount=type=secret,id=HF_TOKEN /bin/sh -c ' \
    export HF_TOKEN=$(cat /run/secrets/HF_TOKEN) && \
    echo "Downloading model weights..." && \
    hf download ${MODEL_NAME} --local-dir ${HF_HOME} --local-dir-use-symlinks False && \
    echo "Model weights downloaded successfully to ${HF_HOME}" && \
    ls -la ${HF_HOME} && \
    echo "Contents of model directory:" && \
    find ${HF_HOME} -type f -name "*.json" -o -name "*.safetensors" -o -name "*.bin" | head -10'

# Prevent the final container from trying to contact Hugging Face Hub at runtime.
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set the entrypoint to start the vLLM OpenAI-compatible server
# Cloud Run sets PORT=8080, so we use that as default
ENV PORT=8080
ENTRYPOINT python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT} \
    --host 0.0.0.0 \
    --model ${HF_HOME} \
    --dtype float32 \
    --enforce-eager \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}