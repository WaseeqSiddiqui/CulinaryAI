"""
LangGraph-based Chef Chat Agent for CulinaryAI.

This is the main RAG pipeline. It uses a multi-node graph to:
  1. parse_intent     — Understand what the user wants
  2. retrieve_recipes — Semantic search in ChromaDB vector store
  3. filter_by_pantry — Match retrieved recipes against pantry items
  4. generate_response — Gemini LLM generates grounded, context-rich reply

The graph uses conditional edges so if retrieval finds nothing relevant,
it falls back to a pure Gemini generation without RAG context.

Architecture:
  START
    │
    ▼
  parse_intent
    │
    ▼
  retrieve_recipes ──(no results)──► generate_response (fallback)
    │                                        ▲
    ▼ (has results)                          │
  filter_by_pantry ──────────────────────────┘
    │
    ▼
  generate_response
    │
    ▼
  END
"""
from __future__ import annotations

import json
import logging
import os
from typing import Any, Literal

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_google_genai import ChatGoogleGenerativeAI
from langgraph.graph import END, START, StateGraph
from typing_extensions import TypedDict

from app.rag.vector_store import RecipeVectorStore

logger = logging.getLogger(__name__)

# ─────────────────────────────── State ──────────────────────────────────────

class ChefAgentState(TypedDict):
    """Shared state that flows through every node in the graph."""

    # Inputs
    user_message: str
    pantry_items: list[dict[str, Any]]           # [{name, quantity, unit}, ...]

    # Intermediate
    intent: str                                   # parsed intent label
    dietary_preferences: list[str]               # detected from message
    max_cook_time: int | None                    # detected from message
    retrieved_recipes: list[dict[str, Any]]      # from vector store
    pantry_filtered_recipes: list[dict[str, Any]]  # after pantry scoring

    # Output
    reply: str
    retrieval_used: bool
    recipes_found: int


# ──────────────────────────── Helper ────────────────────────────────────────

def _pantry_names(pantry_items: list[dict[str, Any]]) -> list[str]:
    return [item.get("name", "").lower() for item in pantry_items]


def _has_ingredient(required: str, pantry: list[str]) -> bool:
    req_tokens = set(required.lower().split())
    return any(
        req_tokens & set(p.split()) for p in pantry
    )


def _pantry_match_percent(recipe: dict[str, Any], pantry: list[str]) -> int:
    ingredients = recipe.get("ingredients_required", [])
    if not ingredients:
        return 0
    available = sum(
        1 for i in ingredients if _has_ingredient(i["name"], pantry)
    )
    return round(100 * available / len(ingredients))


def _build_recipe_context(recipes: list[dict[str, Any]], pantry: list[str]) -> str:
    """Format retrieved recipes into an LLM-readable context block."""
    lines = []
    for i, recipe in enumerate(recipes[:5], 1):
        match = _pantry_match_percent(recipe, pantry)
        ingredients = ", ".join(
            f"{ing['quantity']}{ing['unit']} {ing['name']}"
            for ing in recipe.get("ingredients_required", [])
        )
        lines.append(
            f"{i}. **{recipe['name']}** ({recipe.get('cuisine', 'International')})\n"
            f"   - Pantry match: {match}%\n"
            f"   - Cook time: {recipe.get('cook_time_minutes', '?')} min | "
            f"Calories: {recipe.get('calories_per_serving', '?')}/serving\n"
            f"   - Ingredients: {ingredients}\n"
            f"   - Similarity score: {recipe.get('_similarity_score', 0):.2f}"
        )
    return "\n\n".join(lines)


# ──────────────────────────── Nodes ─────────────────────────────────────────

def parse_intent(state: ChefAgentState) -> dict:
    """
    Node 1: Parse user message to extract:
    - Intent (recipe_suggestion, cooking_help, pantry_question, general)
    - Dietary preferences mentioned
    - Cook time constraint
    """
    msg = state["user_message"].lower()

    # Expand intent detection with Urdu and English culinary triggers
    recipe_triggers = [
        "cook", "banaun", "banana", "batao", "recipe", "what should",
        "kya banaun", "suggest", "meal", "khana", "khane", "dish", "dinner",
        "lunch", "breakfast", "raat", "nashta", "dopahar", "chahiye", "idea"
    ]
    cooking_help_triggers = [
        "how to", "kaise", "steps", "tarika", "method", "help", "guide", "samjha"
    ]
    pantry_triggers = [
        "pantry", "fridge", "available", "mere paas", "kya hai", "items", "ingredients"
    ]

    if any(w in msg for w in recipe_triggers):
        intent = "recipe_suggestion"
    elif any(w in msg for w in cooking_help_triggers):
        intent = "cooking_help"
    elif any(w in msg for w in pantry_triggers):
        intent = "pantry_question"
    else:
        intent = "general"

    # Extract dietary preferences
    dietary: list[str] = []
    if any(w in msg for w in ["vegetarian", "sabzi", "veg", "no meat"]):
        dietary.append("vegetarian")
    if any(w in msg for w in ["vegan", "dairy free"]):
        dietary.append("vegan")
    if any(w in msg for w in ["halal"]):
        dietary.append("halal")

    # Extract time constraint
    max_time: int | None = None
    if "quick" in msg or "jaldi" in msg or "fast" in msg:
        max_time = 25
    elif "30 min" in msg or "30 minute" in msg:
        max_time = 30

    logger.info("🧠 Intent: %s | Dietary: %s | MaxTime: %s", intent, dietary, max_time)

    return {
        "intent": intent,
        "dietary_preferences": dietary,
        "max_cook_time": max_time,
    }


def retrieve_recipes(state: ChefAgentState, vector_store: RecipeVectorStore) -> dict:
    """
    Node 2: Semantic retrieval from ChromaDB.

    Builds a rich query combining user message + pantry items for
    better embedding matching.
    """
    pantry = _pantry_names(state["pantry_items"])
    # Enrich query with pantry context for better semantic search
    pantry_str = ", ".join(pantry[:15]) if pantry else "general ingredients"
    query = f"{state['user_message']} with ingredients: {pantry_str}"

    recipes = vector_store.search(
        query=query,
        n_results=8,
        dietary_filter=state["dietary_preferences"] if state["dietary_preferences"] else None,
        max_cook_time=state["max_cook_time"],
    )

    logger.info("🔍 Retrieved %d recipes from vector store", len(recipes))
    return {"retrieved_recipes": recipes}


def filter_by_pantry(state: ChefAgentState) -> dict:
    """
    Node 3: Score and re-rank recipes by pantry match %.

    Combines:
    - Semantic similarity score (from vector store)
    - Pantry match percentage
    
    Final score = 0.4 * semantic + 0.6 * pantry_match
    """
    pantry = _pantry_names(state["pantry_items"])
    recipes = state["retrieved_recipes"]

    scored = []
    for recipe in recipes:
        match = _pantry_match_percent(recipe, pantry) / 100.0
        similarity = recipe.get("_similarity_score", 0.5)
        combined = 0.4 * similarity + 0.6 * match
        scored.append({**recipe, "_combined_score": round(combined, 4), "_pantry_match_pct": round(match * 100)})

    # Sort by combined score
    scored.sort(key=lambda r: r["_combined_score"], reverse=True)

    logger.info(
        "🥘 Top recipe: '%s' (pantry match: %d%%, combined: %.2f)",
        scored[0]["name"] if scored else "None",
        scored[0].get("_pantry_match_pct", 0) if scored else 0,
        scored[0].get("_combined_score", 0) if scored else 0,
    )

    return {"pantry_filtered_recipes": scored}


def generate_response(state: ChefAgentState) -> dict:
    """
    Node 4: Gemini LLM generates the final chef reply.

    Uses RAG context (retrieved recipes) if available.
    Falls back to general cooking knowledge if no relevant recipes found.
    """
    api_key = os.getenv("GEMINI_API_KEY", "")
    model_name = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")

    recipes = state.get("pantry_filtered_recipes") or state.get("retrieved_recipes") or []
    pantry = state.get("pantry_items", [])
    pantry_names = _pantry_names(pantry)
    has_rag_context = len(recipes) > 0

    if not api_key or api_key == "your_gemini_api_key_here":
        if has_rag_context:
            top = recipes[0]
            top_name = top.get("name", "dish")
            top_match = top.get("_pantry_match_pct", 0)
            cook_time = top.get("cook_time_minutes", 30)
            offline_reply = (
                f"🍳 Chef AI (Offline): I found {len(recipes)} matching recipe(s) for your pantry! "
                f"Top suggestion: **{top_name}** (pantry match: {top_match}%, cook time: {cook_time} min). "
                f"Add your GEMINI_API_KEY in backend/.env for full conversational responses."
            )
        else:
            offline_reply = (
                "🍳 Chef AI is currently in offline mode (no API key configured). "
                "Based on your pantry, I'd suggest checking what protein and vegetables you have "
                "and making a simple stir-fry or curry!"
            )
        return {
            "reply": offline_reply,
            "retrieval_used": has_rag_context,
            "recipes_found": len(recipes),
            "pantry_filtered_recipes": state.get("pantry_filtered_recipes", []),
        }

    # Build system prompt
    system_prompt = """You are Chef AI, a warm and knowledgeable Pakistani and international cooking assistant for the CulinaryAI app.

Your personality:
- Friendly and encouraging, like a knowledgeable family member in the kitchen
- You mix Urdu/English naturally when helpful (e.g. "Bilkul!", "Yeh try karo!")
- You give practical, specific advice

Your rules:
- ALWAYS recommend halal-friendly options
- Prioritize recipes the user can make with their available pantry items
- Be specific about quantities and techniques
- If the user has most ingredients for a recipe, tell them what small extras they might need
- Keep responses conversational and not too long (3-4 paragraphs max)"""

    # Build user context
    pantry_context = ""
    if pantry:
        pantry_context = f"\n\nUser's pantry items: {', '.join(pantry_names[:20])}"

    rag_context = ""
    if has_rag_context:
        rag_context = f"\n\nRelevant recipes from our verified database:\n{_build_recipe_context(recipes, pantry_names)}"
        instruction = (
            "Using ONLY the recipe information provided above as your primary source, "
            "answer the user's question. You can suggest the top 2-3 most suitable recipes "
            "based on pantry match and the user's request. Mention the pantry match % if high."
        )
    else:
        instruction = (
            "No specific recipes were retrieved. Use your general cooking knowledge "
            "to give helpful advice. Be honest that you don't have a specific verified recipe handy."
        )

    full_user_message = (
        f"User asks: {state['user_message']}"
        f"{pantry_context}"
        f"{rag_context}"
        f"\n\nInstruction: {instruction}"
    )

    try:
        llm = ChatGoogleGenerativeAI(
            model=model_name,
            google_api_key=api_key,
            temperature=0.7,
            max_output_tokens=600,
        )

        messages = [
            SystemMessage(content=system_prompt),
            HumanMessage(content=full_user_message),
        ]

        response = llm.invoke(messages)
        reply = response.content

        logger.info(
            "✅ Chef reply generated (RAG=%s, recipes=%d, chars=%d)",
            has_rag_context,
            len(recipes),
            len(reply),
        )

        return {
            "reply": reply,
            "retrieval_used": has_rag_context,
            "recipes_found": len(recipes),
            "pantry_filtered_recipes": state.get("pantry_filtered_recipes", []),
        }

    except Exception as exc:
        logger.error("LLM generation failed: %s", exc)
        return {
            "reply": f"I'm having trouble connecting right now. Please try again in a moment! (Error: {type(exc).__name__})",
            "retrieval_used": False,
            "recipes_found": 0,
            "pantry_filtered_recipes": state.get("pantry_filtered_recipes", []),
        }


# ──────────────────────────── Routing ───────────────────────────────────────

def should_use_rag(state: ChefAgentState) -> Literal["filter_by_pantry", "generate_response"]:
    """
    Conditional edge: if retrieval found recipes, go to pantry filter.
    Otherwise, skip straight to LLM generation (graceful fallback).
    """
    if state.get("retrieved_recipes"):
        return "filter_by_pantry"
    logger.warning("⚠️  No recipes retrieved — falling back to pure LLM generation")
    return "generate_response"


# ──────────────────────────── Graph Builder ──────────────────────────────────

def build_chef_agent(vector_store: RecipeVectorStore) -> Any:
    """
    Build and compile the LangGraph chef agent.

    Returns a compiled graph that can be invoked with:
        graph.invoke({"user_message": "...", "pantry_items": [...]})
    """

    # Partial-apply vector_store into the retrieve node
    def _retrieve(state: ChefAgentState) -> dict:
        return retrieve_recipes(state, vector_store)

    graph = StateGraph(ChefAgentState)

    # Add nodes
    graph.add_node("parse_intent", parse_intent)
    graph.add_node("retrieve_recipes", _retrieve)
    graph.add_node("filter_by_pantry", filter_by_pantry)
    graph.add_node("generate_response", generate_response)

    # Add edges
    graph.add_edge(START, "parse_intent")
    graph.add_edge("parse_intent", "retrieve_recipes")

    # Conditional edge: RAG or fallback
    graph.add_conditional_edges(
        "retrieve_recipes",
        should_use_rag,
        {
            "filter_by_pantry": "filter_by_pantry",
            "generate_response": "generate_response",
        },
    )

    graph.add_edge("filter_by_pantry", "generate_response")
    graph.add_edge("generate_response", END)

    compiled = graph.compile()
    logger.info("✅ LangGraph Chef Agent compiled successfully")
    return compiled
