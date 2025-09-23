FROM ollama/ollama:latest

# Listen on all interfaces, port 8080
ENV OLLAMA_HOST 0.0.0.0:8080

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
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Pull the model and pre-warm it by sending a dummy request.
# This will execute the expensive model loading step during the build.
RUN /bin/sh -c ' \
    ollama serve & \
    OLLAMA_PID=$! && \
    echo "Waiting for Ollama server to start..." && \
    echo "Waiting for Ollama server to start (will try for 60 seconds)..." && \
    tries=0; \
    while ! curl -s -o /dev/null http://127.0.0.1:8080; do \
      sleep 1; \
      tries=$((tries+1)); \
      if [ "$tries" -gt 30 ]; then echo "Server failed to start"; exit 1; fi; \
      if [ "$tries" -gt 60 ]; then echo "Server failed to start"; exit 1; fi; \
    done && \
    echo "Ollama server started. Pulling model..." && \
    ollama pull $MODEL && \
    echo "Model pulled. Pre-warming model..." && \
   curl -X POST http://127.0.0.1:8080/api/generate -d "{ \"model\": \"$MODEL\", \"prompt\": \"warmup\", \"stream\": false }" > /dev/null && \
    curl -X POST http://127.0.0.1:8080/api/generate -d "{ \"model\": \"$MODEL\", \"prompt\": \"warmup\", \"stream\": false }" > /dev/null && \
    echo "Model pre-warmed. Stopping server..." && \
    kill $OLLAMA_PID && \
    wait $OLLAMA_PID'

# Start Ollama
ENTRYPOINT ["ollama", "serve"]