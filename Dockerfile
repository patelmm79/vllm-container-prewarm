FROM vllm/vllm-openai:latest

ENV MODEL_NAME=google/gemma-3-1b-it
ENV HF_HOME=/model-cache

# Download the model weights from Hugging Face during the build.
# This requires the HF_TOKEN secret to be available.
RUN --mount=type=secret,id=HF_TOKEN \
    HF_TOKEN=$(cat /run/secrets/HF_TOKEN) huggingface-cli download ${MODEL_NAME}
    
# Install curl for the pre-warming healthcheck.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Pull the model and pre-warm it by sending a dummy request.
# This will execute the expensive model loading step during the build.
RUN /bin/sh -c ' \
    python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} & \
    VLLM_PID=$! && \
    echo "Waiting for vLLM server to start..." && \
    tries=0; \
    while ! curl -s -f -o /dev/null http://127.0.0.1:8000/health; do \
      sleep 1; \
      tries=$((tries+1)); \
      if [ "$tries" -gt 60 ]; then echo "Server failed to start"; exit 1; fi; \
    done && \
    echo "vLLM server started. Pre-warming model..." && \
    curl -X POST http://127.0.0.1:8000/v1/completions \
      -H "Content-Type: application/json" \
      -d "{ \"model\": \"${MODEL_NAME}\", \"prompt\": \"warmup\", \"max_tokens\": 1, \"stream\": false }" > /dev/null && \
    echo "Model pre-warmed. Stopping server..." && \
    kill $VLLM_PID && \
    wait $VLLM_PID'

# Prevent the container from trying to contact Hugging Face Hub at runtime.
ENV HF_HUB_OFFLINE=1

ENTRYPOINT python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT:-8000} \
    --model ${MODEL_NAME} \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}