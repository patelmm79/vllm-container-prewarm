#!/usr/bin/env python3
"""
Pre-warming script for torch.compile caching.

This script runs on container startup to trigger torch.compile for common input shapes.
The compiled kernels are cached in ~/.triton and ~/.inductor-cache directories,
which persist for the lifetime of the container instance.

This eliminates the 60+ second compilation delay on subsequent requests within
the same container instance, while still benefiting from torch.compile optimizations.
"""

import os
import sys
import time
import requests
from typing import List

# Configuration
MODEL_NAME = os.environ.get('MODEL_NAME', 'google/gemma-3-1b-it')
PORT = os.environ.get('PORT', '8000')
BASE_URL = f"http://localhost:{PORT}"
COMPLETIONS_ENDPOINT = f"{BASE_URL}/v1/completions"

# Common input lengths to pre-warm (in tokens, approximately)
# These cover typical use cases: short prompts, medium conversations, long context
PREWARM_LENGTHS = [128, 256, 512, 1024, 2048]

# Timeout for server startup (seconds)
SERVER_STARTUP_TIMEOUT = 180

# Timeout for each pre-warming request (seconds)
PREWARM_REQUEST_TIMEOUT = 120


def wait_for_server_ready(max_wait: int = SERVER_STARTUP_TIMEOUT) -> bool:
    """
    Wait for the vLLM server to be ready to accept requests.

    Args:
        max_wait: Maximum time to wait in seconds

    Returns:
        True if server is ready, False if timeout
    """
    print(f"[Pre-warm] Waiting for vLLM server to be ready at {BASE_URL}...", flush=True)
    start_time = time.time()
    models_endpoint = f"{BASE_URL}/v1/models"

    while time.time() - start_time < max_wait:
        try:
            response = requests.get(models_endpoint, timeout=5)
            if response.status_code == 200:
                elapsed = time.time() - start_time
                print(f"[Pre-warm] Server is ready! (took {elapsed:.1f}s)", flush=True)
                return True
        except requests.exceptions.RequestException:
            pass

        time.sleep(2)

    print(f"[Pre-warm] ERROR: Server did not become ready within {max_wait}s", flush=True)
    return False


def generate_prompt_of_length(target_tokens: int) -> str:
    """
    Generate a prompt that's approximately the target number of tokens.

    Uses repetition of a simple phrase. Rough approximation: 1 token ≈ 4 characters.

    Args:
        target_tokens: Approximate number of tokens desired

    Returns:
        Generated prompt string
    """
    # Rough heuristic: 1 token ≈ 4 characters for English text
    chars_per_token = 4
    target_chars = target_tokens * chars_per_token

    # Use a simple repeating pattern
    base_phrase = "The quick brown fox jumps over the lazy dog. "
    repetitions = (target_chars // len(base_phrase)) + 1
    prompt = base_phrase * repetitions

    # Trim to approximate length
    return prompt[:target_chars]


def prewarm_request(prompt_length: int) -> bool:
    """
    Make a single pre-warming request for a specific input length.

    Args:
        prompt_length: Target prompt length in tokens

    Returns:
        True if successful, False otherwise
    """
    prompt = generate_prompt_of_length(prompt_length)

    payload = {
        "model": MODEL_NAME,
        "prompt": prompt,
        "max_tokens": 10,  # Short generation, we just want to trigger compilation
        "temperature": 0.0
    }

    print(f"[Pre-warm] Sending request with ~{prompt_length} token prompt...", flush=True)
    start_time = time.time()

    try:
        response = requests.post(
            COMPLETIONS_ENDPOINT,
            json=payload,
            timeout=PREWARM_REQUEST_TIMEOUT
        )
        elapsed = time.time() - start_time

        if response.status_code == 200:
            print(f"[Pre-warm] ✓ Request completed successfully ({elapsed:.1f}s)", flush=True)
            return True
        else:
            print(f"[Pre-warm] ✗ Request failed with status {response.status_code} ({elapsed:.1f}s)", flush=True)
            print(f"[Pre-warm]   Response: {response.text[:200]}", flush=True)
            return False

    except requests.exceptions.Timeout:
        elapsed = time.time() - start_time
        print(f"[Pre-warm] ✗ Request timed out after {elapsed:.1f}s", flush=True)
        return False
    except requests.exceptions.RequestException as e:
        elapsed = time.time() - start_time
        print(f"[Pre-warm] ✗ Request failed with exception ({elapsed:.1f}s): {e}", flush=True)
        return False


def run_prewarming(prompt_lengths: List[int]) -> int:
    """
    Run pre-warming for all specified prompt lengths.

    Args:
        prompt_lengths: List of prompt lengths to pre-warm

    Returns:
        Number of successful pre-warming requests
    """
    print(f"[Pre-warm] Starting torch.compile pre-warming for {len(prompt_lengths)} input shapes", flush=True)
    print(f"[Pre-warm] Target prompt lengths (tokens): {prompt_lengths}", flush=True)

    overall_start = time.time()
    successful = 0

    for length in prompt_lengths:
        if prewarm_request(length):
            successful += 1
        # Small delay between requests
        time.sleep(1)

    overall_elapsed = time.time() - overall_start
    print(f"[Pre-warm] Pre-warming complete: {successful}/{len(prompt_lengths)} successful ({overall_elapsed:.1f}s total)", flush=True)

    return successful


def main() -> int:
    """
    Main entry point for pre-warming script.

    Returns:
        0 if pre-warming was successful (or skipped), 1 if critical failure
    """
    print("=" * 70, flush=True)
    print("[Pre-warm] torch.compile Pre-warming Script", flush=True)
    print("=" * 70, flush=True)

    # Check if pre-warming is disabled
    if os.environ.get('SKIP_PREWARM', '').lower() in ('1', 'true', 'yes'):
        print("[Pre-warm] SKIP_PREWARM is set, skipping pre-warming", flush=True)
        return 0

    # Check if torch.compile is disabled
    compile_level = os.environ.get('VLLM_TORCH_COMPILE_LEVEL', '1')
    if compile_level == '0':
        print("[Pre-warm] torch.compile is disabled (VLLM_TORCH_COMPILE_LEVEL=0), skipping pre-warming", flush=True)
        return 0

    print(f"[Pre-warm] Model: {MODEL_NAME}", flush=True)
    print(f"[Pre-warm] Server: {BASE_URL}", flush=True)
    print(f"[Pre-warm] torch.compile level: {compile_level}", flush=True)

    # Wait for server to be ready
    if not wait_for_server_ready():
        print("[Pre-warm] ERROR: Server failed to start, cannot run pre-warming", flush=True)
        # Don't fail the container startup, just skip pre-warming
        print("[Pre-warm] Continuing without pre-warming...", flush=True)
        return 0

    # Run pre-warming
    successful = run_prewarming(PREWARM_LENGTHS)

    if successful == 0:
        print("[Pre-warm] WARNING: No pre-warming requests succeeded", flush=True)
        # Don't fail the container, maybe the issue was transient
        return 0

    print("=" * 70, flush=True)
    print(f"[Pre-warm] Pre-warming complete! Cache is ready for serving.", flush=True)
    print("=" * 70, flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
