"""Existing endpoint fixtures do not exercise real Firebase authentication."""
import pytest


@pytest.fixture(autouse=True)
def isolate_subscription_enforcement(monkeypatch):
    monkeypatch.setenv("USAGE_LIMITS_ENABLED", "false")
