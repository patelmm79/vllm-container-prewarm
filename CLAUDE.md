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
- `VLLM_TORCH_COMPILE_LEVEL`: Set to `0` to disable torch.compile and eliminate 60+ second startup delay
- `TORCH_CUDA_ARCH_LIST`: Set to `7.5` for NVIDIA T4 GPU optimization

## Runtime Configuration

The container serves the model via vLLM's OpenAI-compatible API with these defaults:
- Port: 8000 (configurable via `PORT` env var)
- Model: `google/gemma-3-1b-it`
- Data type: float32
- Optional max model length via `MAX_MODEL_LEN`

## Security Notes

- Hugging Face token is handled securely via Google Secret Manager
- Container runs offline at runtime to prevent unauthorized Hub access
- Model weights are cached during build to avoid runtime downloads