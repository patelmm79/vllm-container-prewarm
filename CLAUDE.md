# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a containerized vLLM inference server project that serves the Google Gemma 3.1B Instruct model. The project focuses on creating "pre-warmed" containers where the expensive model loading step is performed during the Docker build process rather than at runtime.

## Architecture

The project consists of three main components:

1. **Dockerfile**: Builds a container based on `vllm/vllm-openai:v0.9.0` that:
   - Downloads the `google/gemma-3-1b-it` model during build time using a Hugging Face token
   - Pre-warms the model by starting vLLM server, making a test request, then stopping it
   - Includes comprehensive debug logging and timeout handling (300 second timeout with progress updates)
   - Captures and displays vLLM server logs for troubleshooting
   - Sets up the container to run offline (no Hugging Face Hub access at runtime)
   - Serves the model via OpenAI-compatible API on port 8000

2. **Cloud Build Configuration** (`cloudbuild.yaml`): Orchestrates the build process using:
   - Google Cloud Build with `E2_HIGHCPU_8` machine type
   - Docker buildx for advanced build features
   - Secure injection of `HF_TOKEN` from Google Secret Manager
   - Pushes to Google Artifact Registry at `us-central1-docker.pkg.dev/${PROJECT_ID}/vllm-gemma-3-1b-it-repo/vllm-gemma-3-1b-it`

3. **Documentation**: `GEMINI.md` provides detailed build instructions and prerequisites

## Build Commands

### Local Development
```bash
# Build locally (requires HF_TOKEN environment variable)
docker build --secret id=HF_TOKEN --tag vllm-gemma .
```

### Production Build
```bash
# Build using Google Cloud Build
gcloud builds submit --config cloudbuild.yaml
```

## Key Environment Variables

- `MODEL_NAME`: Set to `google/gemma-3-1b-it`
- `HF_HOME`: Model cache directory (`/model-cache`)
- `HF_TOKEN`: Required for downloading the model from Hugging Face
- `HF_HUB_OFFLINE`: Set to `1` in final container to prevent runtime Hub access
- `PORT`: Server port (defaults to 8000)
- `MAX_MODEL_LEN`: Optional model length limit
- `VLLM_TORCH_COMPILE_LEVEL`: torch.compile optimization level (default: `1`)
  - `0`: Disabled (fastest cold start, no compilation overhead)
  - `1`: Basic compilation (balanced - recommended for most cases)
  - `2-3`: More aggressive optimization (longer compilation, higher throughput)
- `SKIP_PREWARM`: Set to `1` to skip the runtime pre-warming phase (not recommended)

## Runtime Configuration

The container serves the model via vLLM's OpenAI-compatible API with these defaults:
- Port: 8000 (configurable via `PORT` env var)
- Model: `google/gemma-3-1b-it`
- Data type: float32
- Optional max model length via `MAX_MODEL_LEN`

## torch.compile Pre-warming

The container implements a hybrid pre-warming strategy for torch.compile to optimize both cold start time and runtime performance:

### How It Works

1. **On container startup**, the custom entrypoint script (`entrypoint.sh`):
   - Starts the vLLM server in the background
   - Waits for the server to become ready
   - Runs the pre-warming script (`prewarm_compile.py`)
   - Keeps the server running for normal operation

2. **The pre-warming script** makes test inference requests with common input lengths (128, 256, 512, 1024, 2048 tokens) to trigger torch.compile for those shapes

3. **Compiled kernels are cached** in the container filesystem (`~/.triton`, `~/.inductor-cache`)

4. **Subsequent requests** within the same container instance use the cached compiled kernels for fast execution

### Performance Characteristics

- **First container startup**: ~60s one-time compilation cost
- **Cache lifetime**: Persists for the lifetime of the container instance
- **Subsequent requests**: Fast execution with compiled optimizations
- **Hardware-specific**: Compilation happens on the actual Cloud Run T4 GPU

### Configuration

- Set `VLLM_TORCH_COMPILE_LEVEL=0` to disable torch.compile entirely (no pre-warming, faster cold starts)
- Set `SKIP_PREWARM=1` to skip pre-warming phase (not recommended unless debugging)
- Default configuration (`VLLM_TORCH_COMPILE_LEVEL=1`) provides the best balance for most use cases

### Design Rationale

This approach addresses the limitations of build-time pre-compilation:
- ✅ Compiles on actual target hardware (T4 GPUs in Cloud Run)
- ✅ No GPU required in Cloud Build environment
- ✅ Cache is hardware and version-matched
- ✅ One-time cost per container instance, not per request
- ✅ Works with Cloud Run's auto-scaling model

## Security Notes

- Hugging Face token is handled securely via Google Secret Manager
- Container runs offline at runtime to prevent unauthorized Hub access
- Model weights are cached during build to avoid runtime downloads