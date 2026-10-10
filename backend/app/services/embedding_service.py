from __future__ import annotations

import hashlib
import math
import re
from collections import Counter


class HashEmbeddingService:
    """Deterministic local embeddings suitable for the Week 1 RAG prototype."""

    def __init__(self, dimensions: int = 256) -> None:
        if dimensions <= 0:
            raise ValueError("dimensions must be positive")
        self.dimensions = dimensions

    def embed(self, text: str) -> list[float]:
        tokens = re.findall(r"[a-z0-9]+", text.lower())
        if not tokens:
            return [0.0] * self.dimensions

        vector = [0.0] * self.dimensions
        for token, count in Counter(tokens).items():
            digest = hashlib.sha256(token.encode("utf-8")).digest()
            index = int.from_bytes(digest[:4], "big") % self.dimensions
            sign = 1.0 if digest[4] % 2 == 0 else -1.0
            vector[index] += sign * (1 + math.log(count))

        magnitude = math.sqrt(sum(value * value for value in vector))
        return [value / magnitude for value in vector]

    @staticmethod
    def similarity(left: list[float], right: list[float]) -> float:
        if len(left) != len(right):
            raise ValueError("embedding dimensions must match")
        return sum(a * b for a, b in zip(left, right, strict=True))
