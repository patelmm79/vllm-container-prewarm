
import os
import requests
import time
import subprocess
import pytest

SERVICE_NAME = "vllm-gemma-3-1b-it"
REGION = "us-central1"

@pytest.fixture(scope="module")
def service_url():
    """
    Retrieves the Cloud Run service URL.
    """
    try:
        command = [
            "gcloud", "run", "services", "describe",
            SERVICE_NAME,
            "--platform", "managed",
            "--region", REGION,
            "--format", "value(status.url)"
        ]
        process = subprocess.run(command, capture_output=True, text=True, check=True)
        url = process.stdout.strip()
        if not url:
            pytest.fail("Failed to retrieve Cloud Run service URL.")
        return url
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        pytest.fail(f"Error retrieving service URL: {e}")

def test_models_endpoint(service_url):
    """
    Tests the /v1/models endpoint.
    """
    endpoint_url = f"{service_url}/v1/models"
    print(f"Pinging model endpoint: {endpoint_url}")

    for i in range(5):
        try:
            response = requests.get(endpoint_url, timeout=30)
            print(f"Attempt {i+1}: Received HTTP status: {response.status_code}")
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException as e:
            print(f"Attempt {i+1}: Request failed: {e}")
        time.sleep(10)
    else:
        pytest.fail("Health check failed after multiple attempts.")

    assert response.status_code == 200, "Endpoint did not return status 200."

    response_body = response.json()
    print(f"Response body: {response_body}")
    assert "data" in response_body, "Response body does not contain 'data' key."
    model_ids = [model["id"] for model in response_body["data"]]
    assert "gemma-3-1b-it" in model_ids, "Model 'gemma-3-1b-it' not found in response."

def test_completions_endpoint(service_url):
    """
    Tests the /v1/completions endpoint.
    """
    completions_url = f"{service_url}/v1/completions"
    print(f"Testing completions endpoint: {completions_url}")

    payload = {
        "model": "gemma-3-1b-it",
        "prompt": "What is the capital of France?",
        "max_tokens": 50,
        "temperature": 0.7
    }

    response = requests.post(completions_url, json=payload, timeout=60)
    print(f"Completions response: {response.text}")

    assert response.status_code == 200, "Completions endpoint returned non-200 status."

    response_json = response.json()
    assert "choices" in response_json, "'choices' key not found in completions response."
    assert len(response_json["choices"]) > 0, "'choices' array is empty."
    assert "text" in response_json["choices"][0], "'text' key not found in the first choice."
    assert len(response_json["choices"][0]["text"]) > 0, "Generated text is empty."

