"""Provider selection and a Groq adapter for the kitchen's existing AI contracts.

The adapter accepts the content/config objects already used by the kitchen
services, so their prompts, Pydantic validation and inventory rules stay shared.
"""
from __future__ import annotations

import base64
import copy
import json
import os
from types import SimpleNamespace
from typing import Any

from fastapi import HTTPException
import httpx
from pydantic import BaseModel


DEFAULT_TEXT_MODEL = "openai/gpt-oss-120b"
DEFAULT_VISION_MODEL = "qwen/qwen3.8-27b"


def ai_provider() -> str:
    provider = os.getenv("AI_PROVIDER", "groq").strip().lower()
    if provider not in {"groq", "gemini"}:
        raise ValueError("AI_PROVIDER must be groq or gemini")
    return provider


def configured_key(provider: str) -> str:
    name = "GROQ_API_KEY" if provider == "groq" else "GEMINI_API_KEY"
    key = os.getenv(name, "").strip()
    return "" if key.startswith("your_") else key


def text_model() -> str:
    return os.getenv("GROQ_TEXT_MODEL", "").strip() or DEFAULT_TEXT_MODEL


def vision_model() -> str:
    model = os.getenv("GROQ_VISION_MODEL", "").strip() or DEFAULT_VISION_MODEL
    if model.startswith("openai/gpt-oss-"):
        raise ValueError("GROQ_VISION_MODEL must accept images; GPT-OSS is text-only")
    return model


def strict_schema(schema: dict) -> dict:
    """Groq strict output requires every property and closed object schemas."""
    result = copy.deepcopy(schema)

    def visit(value):
        if isinstance(value, dict):
            value.pop("default", None)
            if value.get("type") == "object" or "properties" in value:
                value["required"] = list(value.get("properties", {}))
                value["additionalProperties"] = False
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(result)
    return result


class GroqModelClient:
    def __init__(self, api_key: str, client: httpx.Client | None = None):
        self._api_key = api_key
        self._client = client or httpx.Client(
            timeout=httpx.Timeout(25, connect=4), follow_redirects=False,
        )
        self.models = self

    def close(self):
        self._client.close()

    def generate_content(self, *, model: str, contents: Any, config: Any = None):
        parts = contents if isinstance(contents, list) else [contents]
        content = []
        has_image = False
        for part in parts:
            if isinstance(part, str):
                content.append({"type": "text", "text": part})
            elif getattr(part, "inline_data", None) is not None:
                image = part.inline_data
                encoded = base64.b64encode(image.data).decode("ascii")
                content.append({"type": "image_url", "image_url": {
                    "url": f"data:{image.mime_type};base64,{encoded}",
                }})
                has_image = True
            elif getattr(part, "text", None) is not None:
                content.append({"type": "text", "text": part.text})
            else:
                raise ValueError("Unsupported kitchen AI content; no content was sent")
        if has_image and model.startswith("openai/gpt-oss-"):
            raise ValueError("GPT-OSS cannot process images; select a vision model")

        schema_type = getattr(config, "response_schema", None)
        schema = getattr(config, "response_json_schema", None)
        if isinstance(schema_type, type) and issubclass(schema_type, BaseModel):
            schema = schema_type.model_json_schema()
        structured = schema is not None
        body = {
            "model": model,
            "messages": [{"role": "user", "content": content}],
            "max_completion_tokens": 8192 if structured else 2048,
            "stream": False,
        }
        # Use quick instruction mode for Qwen and low reasoning for GPT-OSS.
        if model.startswith("qwen/"):
            body["reasoning_effort"] = "none"
        elif model.startswith("openai/gpt-oss-"):
            body["reasoning_effort"] = "low"
        temperature = getattr(config, "temperature", None)
        if temperature is not None:
            body["temperature"] = temperature
        if structured:
            body["response_format"] = {"type": "json_schema", "json_schema": {
                "name": schema.get("title", "kitchen_result"),
                "strict": True,
                "schema": strict_schema(schema),
            }}

        timeout_ms = getattr(getattr(config, "http_options", None), "timeout", None)
        seconds = (
            min(25.0, timeout_ms / 1000)
            if timeout_ms else (25.0 if has_image or structured else 7.0)
        )
        try:
            response = self._client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {self._api_key}"},
                json=body,
                timeout=httpx.Timeout(seconds, connect=min(4.0, seconds)),
            )
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Groq request timed out. Please retry.") from None
        except httpx.HTTPError:
            raise HTTPException(status_code=503, detail="Groq could not be reached. Please retry.") from None
        if not response.is_success:
            if response.status_code == 429:
                raise HTTPException(status_code=429, detail="Groq API rate limit reached. Please retry shortly.")
            if response.status_code in {401, 403}:
                raise HTTPException(status_code=503, detail="Groq API credentials or model access need configuration on the server.")
            if response.status_code == 400:
                raise HTTPException(status_code=400, detail="Groq could not process this request. Check the selected model and input.")
            raise HTTPException(status_code=503, detail="The selected Groq model is unavailable. Please retry or check server configuration.")
        try:
            choice = response.json()["choices"][0]
            if choice.get("finish_reason") in {"length", "content_filter"}:
                raise ValueError("Incomplete model response")
            text = choice["message"]["content"]
            if not isinstance(text, str) or not text.strip():
                raise ValueError("Empty model response")
            parsed = None
            if structured:
                if isinstance(schema_type, type) and issubclass(schema_type, BaseModel):
                    parsed = schema_type.model_validate_json(text)
                else:
                    parsed = json.loads(text)
                if not isinstance(parsed, (dict, BaseModel)):
                    raise ValueError("Expected a structured object")
            return SimpleNamespace(text=text.strip(), parsed=parsed)
        except (AttributeError, KeyError, IndexError, TypeError, ValueError):
            raise HTTPException(status_code=502, detail="Groq returned an incomplete or invalid response. Please retry.") from None


def create_client(provider: str, api_key: str):
    if not api_key:
        name = "GROQ_API_KEY" if provider == "groq" else "GEMINI_API_KEY"
        raise HTTPException(status_code=503, detail=f"{name} is not configured on the server.")
    if provider == "groq":
        return GroqModelClient(api_key)
    from google import genai
    return genai.Client(api_key=api_key)
