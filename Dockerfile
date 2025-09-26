FROM vllm/vllm-openai:v0.9.0

# Set environment variables for vLLM and Hugging Face
ENV MODEL_NAME=google/gemma-3-1b-it
ENV HF_HOME=/model-cache

# Install curl for the pre-warming step and clean up apt cache to reduce image size.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Download the model weights from Hugging Face and pre-warm the model.
# This executes the expensive model loading step during the build process.
RUN --mount=type=secret,id=HF_TOKEN /bin/sh -c ' \
    export HF_TOKEN=$(cat /run/secrets/HF_TOKEN) && \
    echo "Downloading model weights..." && \
    huggingface-cli download ${MODEL_NAME} --local-dir ${HF_HOME} && \
    echo "Starting vLLM server on CPU for pre-warming (with debug logging)..." && \
    export VLLM_LOGGING_LEVEL=DEBUG && \
    python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} --device cpu --dtype float32 & \
    VLLM_PID=$! && \
    echo "Waiting for vLLM server to be healthy (will try for 60 seconds)..." && \
    tries=0; \
    while ! curl -s --fail --max-time 5 -o /dev/null http://127.0.0.1:8000/health; do \
      sleep 1; \
      tries=$((tries+1)); \
      if [ "$tries" -gt 2000 ]; then echo "vLLM server failed to start after 2000 seconds"; exit 1; fi; \
    done && \
    echo "vLLM server started. Pre-warming model..." && \
    curl -X POST http://127.0.0.1:8000/v1/completions \
      -H "Content-Type: application/json" \
      -d "{ \"model\": \"${MODEL_NAME}\", \"prompt\": \"warmup\", \"max_tokens\": 1, \"stream\": false }" > /dev/null && \
    echo "Model pre-warmed. Stopping vLLM server..." && \
    kill $VLLM_PID'

# Prevent the final container from trying to contact Hugging Face Hub at runtime.
ENV HF_HUB_OFFLINE=1

# Set the entrypoint to start the vLLM OpenAI-compatible server
ENTRYPOINT python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT:-8000} \
    --model ${MODEL_NAME} \
    --dtype float32 \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}