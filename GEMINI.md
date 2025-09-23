# vLLM Gemma Container

This project provides the configuration to build a Docker container for serving the Gemma 3.1B Instruct model using the vLLM inference server.

## Overview

The primary goal is to package the vLLM server with the `gemma-3-1b-it` model into a container image that can be easily deployed. The build process is managed by Google Cloud Build.

## Building the Container

The container is built using Google Cloud Build and the configuration is defined in `cloudbuild.yaml`.

### Prerequisites

1.  A Google Cloud Project with the Cloud Build API and Secret Manager API enabled.
2.  The `gcloud` CLI installed and authenticated.
3.  A Hugging Face token with access to the Gemma model stored in Google Secret Manager. The secret must be named `HF_TOKEN`.

### Build Command

To start the build, run the following `gcloud` command from the root of the repository:

```bash
gcloud builds submit --config cloudbuild.yaml
```

### How It Works

The `cloudbuild.yaml` file defines the build steps:

-   **Builder**: It uses the standard Docker builder from `gcr.io/cloud-builders/docker`.
-   **Secrets**: It securely injects the `HF_TOKEN` from Secret Manager into the Docker build process. This is required to download the model from the Hugging Face Hub during the `docker build` command.
-   **Image**: The final container image is tagged and pushed to Google Artifact Registry. The image path is defined by the `_IMAGE` substitution variable:
    `us-central1-docker.pkg.dev/${PROJECT_ID}/vllm-gemma-3-1b-it-repo/vllm-gemma-3-1b-it`
-   **Machine Type**: The build is configured to run on a high-CPU machine (`E2_HIGHCPU_32`) to ensure the build process is fast and efficient.