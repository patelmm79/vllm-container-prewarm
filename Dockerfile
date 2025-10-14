FROM vllm/vllm-openai:latest

ENV HF_HOME=/model-cache

ENV HF_HUB_OFFLINE=1

# Set CUDA architecture for NVIDIA T4 GPUs (used in Google Cloud Run)
# This reduces compilation time by avoiding compilation for all GPU architectures
# Compute capability 7.5 corresponds to NVIDIA T4
ENV TORCH_CUDA_ARCH_LIST="7.5"

# Enable torch.compile for optimized inference
# Level 1 provides a good balance of compilation time vs runtime performance
# The pre-warming script will trigger compilation for common input shapes on container startup,
# caching the compiled kernels for fast subsequent requests within the same container instance.
# Set to 0 to disable torch.compile if fast cold starts are more important than throughput.
ENV VLLM_TORCH_COMPILE_LEVEL=1

# Install requests library for pre-warming script
RUN pip install --no-cache-dir requests

# Copy pre-warming script and startup script
COPY prewarm_compile.py /app/prewarm_compile.py
COPY entrypoint.sh /app/entrypoint.sh

# Make scripts executable
RUN chmod +x /app/prewarm_compile.py /app/entrypoint.sh

# Use custom entrypoint that handles pre-warming
# The entrypoint script will:
# 1. Start vLLM server in background
# 2. Run pre-warming to trigger torch.compile for common input shapes
# 3. Keep vLLM server running in foreground for normal operation
ENTRYPOINT ["/app/entrypoint.sh"]
