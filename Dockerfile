FROM vllm/vllm-openai:latest

# Use ARG to define the model name, making it easier to change and reuse
ARG MODEL_NAME=google/gemma-3-1b-it
# Expose the build-time argument as a runtime environment variable
ENV MODEL_NAME=${MODEL_NAME}

ENV HF_HOME=/model-cache

# Download the model using the secret.
RUN --mount=type=secret,id=HF_TOKEN \
    HF_TOKEN=$(cat /run/secrets/HF_TOKEN) huggingface-cli download ${MODEL_NAME}

# "Pre-warm" the model. By running the server once during the build, vLLM can
# create on-disk caches (if any) which can speed up subsequent startups.
# NOTE: This build step requires a machine with a compatible GPU for vLLM to load the model.
# The build will be slow as it includes the full model loading time.
RUN set -e; \
    python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} & \
    SERVER_PID=$!; \
    echo "Pre-warming model, waiting for server to become healthy (this may take several minutes)..."; \
    if ! timeout 420 bash -c 'while ! curl -s --fail http://localhost:8000/health > /dev/null; do echo -n "." && sleep 5; done'; then \
      echo "\nError: vLLM server did not become healthy within the timeout during pre-warming."; \
      kill $SERVER_PID; \
      exit 1; \
    fi; \
    echo "\nModel pre-warmed successfully. Stopping server."; \
    kill $SERVER_PID; \
    wait $SERVER_PID || echo "Server process exited as expected."

# Set to offline mode for runtime to prevent any calls to Hugging Face Hub
ENV HF_HUB_OFFLINE=1

# The entrypoint now starts the server. Due to the pre-warming step,
# it should initialize much faster. The MODEL_NAME is used consistently.
ENTRYPOINT python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT:-8000} \
    --model ${MODEL_NAME} \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}
