FROM vllm/vllm-openai:latest

ENV HF_HOME=/model-cache

ENV HF_HUB_OFFLINE=1

# Set CUDA architecture for NVIDIA T4 GPUs (used in Google Cloud Run)
# This reduces compilation time by avoiding compilation for all GPU architectures
# Compute capability 7.5 corresponds to NVIDIA T4
ENV TORCH_CUDA_ARCH_LIST="7.5"

# Fix for c10d warning: "The hostname of the client socket cannot be retrieved."
# This occurs in container environments where reverse DNS lookup for the container's IP fails.
# Adding the container's hostname to /etc/hosts pointing to localhost resolves this.
# The 'exec' command is used to ensure the python process replaces the shell,
# allowing it to receive signals correctly for graceful shutdown.
# Explicitly export TORCH_CUDA_ARCH_LIST to ensure it's available to vLLM worker processes
ENTRYPOINT echo "127.0.0.1 $(hostname)" >> /etc/hosts && \
    export TORCH_CUDA_ARCH_LIST="7.5" && \
    exec python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT:-8000} \
    --model ${MODEL_NAME:-google/gemma-3-1b-it} \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"}
