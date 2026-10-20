"""
RAG (Retrieval-Augmented Generation) package for CulinaryAI.

Pipeline:
  User Query + Pantry Items
       ↓
  LangGraph Agent (multi-node)
       ↓
  ChromaDB Vector Store (Gemini Embeddings)
       ↓
  Retrieved Recipes (context)
       ↓
  Gemini LLM (grounded generation)
       ↓
  Structured Chef Response
"""
