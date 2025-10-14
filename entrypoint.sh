#!/bin/bash
# entrypoint.sh - Startup script for vLLM container with torch.compile pre-warming
#
# This script:
# 1. Starts the vLLM server in the background
# 2. Runs the pre-warming script to trigger torch.compile for common input shapes
# 3. Brings the vLLM server to the foreground for normal operation

set -e  # Exit on error

echo "========================================="
echo "vLLM Container Startup with Pre-warming"
echo "========================================="

# Apply system configurations
echo "[Startup] Setting file descriptor limit..."
ulimit -n 1048576

echo "[Startup] Adding hostname to /etc/hosts..."
echo "127.0.0.1 $(hostname)" >> /etc/hosts

# Export environment variables that should be inherited by child processes
export TORCH_CUDA_ARCH_LIST="7.5"
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
export MODEL_NAME="${MODEL_NAME:-google/gemma-3-1b-it}"
export PORT="${PORT:-8000}"

echo "[Startup] Configuration:"
echo "  MODEL_NAME: $MODEL_NAME"
echo "  PORT: $PORT"
echo "  TORCH_CUDA_ARCH_LIST: $TORCH_CUDA_ARCH_LIST"
echo "  HF_HUB_OFFLINE: $HF_HUB_OFFLINE"
echo "  VLLM_TORCH_COMPILE_LEVEL: ${VLLM_TORCH_COMPILE_LEVEL:-1}"

# Start vLLM server in the background
echo ""
echo "[Startup] Starting vLLM server in background..."
python3 -m vllm.entrypoints.openai.api_server \
    --port ${PORT} \
    --model ${MODEL_NAME} \
    ${MAX_MODEL_LEN:+--max-model-len "$MAX_MODEL_LEN"} \
    &

# Store the PID of the vLLM server
VLLM_PID=$!
echo "[Startup] vLLM server started with PID: $VLLM_PID"

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "[Startup] Received shutdown signal, stopping vLLM server..."
    kill -TERM "$VLLM_PID" 2>/dev/null || true
    wait "$VLLM_PID" 2>/dev/null || true
    exit 0
}

# Register cleanup function for common termination signals
trap cleanup SIGTERM SIGINT SIGQUIT

# Run pre-warming script
# This script will wait for the server to be ready, then make test requests
# to trigger torch.compile for common input shapes
echo ""
echo "[Startup] Running pre-warming script..."
if ! python3 /app/prewarm_compile.py; then
    echo "[Startup] WARNING: Pre-warming script failed or was skipped"
    echo "[Startup] Continuing with server startup anyway..."
fi

# Check if vLLM server is still running
if ! kill -0 "$VLLM_PID" 2>/dev/null; then
    echo "[Startup] ERROR: vLLM server has stopped unexpectedly!"
    exit 1
fi

# Pre-warming complete, now keep the vLLM server running in foreground
echo ""
echo "[Startup] Pre-warming complete! Server is ready to accept requests."
echo "[Startup] vLLM server is now running on port $PORT"
echo "========================================="

# Wait for the vLLM server process to complete
# This keeps the container running and passes signals to the server
wait "$VLLM_PID"
