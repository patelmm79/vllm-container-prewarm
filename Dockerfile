FROM ollama/ollama:latest
FROM vllm/vllm-openai:latest

# Listen on all interfaces, port 8080
ENV OLLAMA_HOST 0.0.0.0:8080
ENV MODEL_NAME=google/gemma-3-1b-it
ENV HF_HOME=/model-cache

# Store model weight files in /models
ENV OLLAMA_MODELS /models

# Reduce logging verbosity
ENV OLLAMA_DEBUG false

# Never unload model weights from the GPU
ENV OLLAMA_KEEP_ALIVE -1

# Store the model weights in the container image
ENV MODEL gemma3:1b
RUN ollama serve & sleep 5 && ollama pull $MODEL

# Install curl for the pre-warming step and clean up apt cache to reduce image size.
# This is in a separate layer to leverage Docker's build cache.
# Download the model weights from Hugging Face during the build.
# This requires the HF_TOKEN secret to be available.
RUN --mount=type=secret,id=HF_TOKEN \
    HF_TOKEN=$(cat /run/secrets/HF_TOKEN) huggingface-cli download ${MODEL_NAME}
    
# Install curl for the pre-warming healthcheck.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*


RUN --mount=type=secret,id=HF_TOKEN \
    export HF_TOKEN=$(cat /run/secrets/HF_TOKEN) && \
    pip install -r requirements.txt
# Pull the model and pre-warm it by sending a dummy request.
# This will execute the expensive model loading step during the build.
RUN /bin/sh -c ' \
    ollama serve & \
    OLLAMA_PID=$! && \
    echo "Waiting for Ollama server to start..." && \
    echo "Waiting for Ollama server to start (will try for 60 seconds)..." && \
    python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} & \
    VLLM_PID=$! && \
    echo "Waiting for vLLM server to start..." && \
    tries=0; \
    while ! curl -s -f -o /dev/null http://127.0.0.1:8080; do \
      sleep 1; \
      tries=$((tries+1)); \
      if [ "$tries" -gt 60 ]; then echo "Ollama server failed to start"; exit 1; fi; \
    done && \
    echo "Ollama server started. Pulling model..." && \
    ollama pull $MODEL && \
    echo "Model pulled. Pre-warming model..." && \
    curl -X POST http://127.0.0.1:8080/api/generate -d "{ \"model\": \"$MODEL\", \"prompt\": \"warmup\", \"stream\": false }" > /dev/null && \
    tries=0; \
    while ! curl -s -f -o /dev/null http://127.0.0.1:8000/health; do \
      sleep 1; \
      tries=$((tries+1)); \
      if [ "$tries" -gt 60 ]; then echo "vLLM server failed to start"; exit 1; fi; \
    done && \
    echo "vLLM server started. Pre-warming model..." && \
    curl -X POST http://127.0.0.1:8000/v1/completions \
      -H "Content-Type: application/json" \
      -d "{ \"model\": \"${MODEL_NAME}\", \"prompt\": \"warmup\", \"max_tokens\": 1, \"stream\": false }" > /dev/null && \
    echo "Model pre-warmed. Stopping server..." && \
    kill $OLLAMA_PID && \
    kill $VLLM_PID'

# Start Ollama
ENTRYPOINT ["ollama", "serve"]
# Prevent the container from trying to contact Hugging Face Hub at runtime.
ENV HF_HUB_OFFLINE=1

ENTRYPOINT python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT:-8000} \
    --model ${MODEL_NAME} \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}