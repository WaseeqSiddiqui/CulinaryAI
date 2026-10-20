import asyncio
import json
import logging
import os

from dotenv import load_dotenv

# Load .env from the backend directory (one level up from app/)
load_dotenv()

# ── RAG imports ──────────────────────────────────────────────────────────────
from app.rag.vector_store import RecipeVectorStore
from app.rag.langgraph_agent import build_chef_agent

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.models.schemas import (
    GeneratePlanRequest,
    GeneratePlanResponse,
    HealthResponse,
    InstructionRequest,
    InstructionResponse,
    MatchProductRequest,
    MatchProductResponse,
    NormalizeShoppingQueryRequest,
    NormalizeShoppingQueryResponse,
    ChefChatRequest,
    ChefChatResponse,
)
from app.models.vision_schemas import (
    ExistingPantryItem,
    FridgeScanResponse,
    ValidatedReceiptResponse,
    MealNutritionEstimate,
)
from app.services.fridge_reconciler import FridgeReconciler
from app.services.gemini_service import GeminiVisionService
from app.services.ingredient_catalog import IngredientCatalogService
from app.services.meal_planner import MealPlannerService
from app.services.product_matcher import ProductMatcher
from app.services.recipe_repository import VerifiedRecipeRepository

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

repository = VerifiedRecipeRepository()
planner = MealPlannerService(repository)
catalog_service = IngredientCatalogService()
vision_service = GeminiVisionService(catalog_service=catalog_service)
fridge_reconciler = FridgeReconciler(catalog=catalog_service)
product_matcher = ProductMatcher()

# ── RAG: Vector Store + LangGraph Agent ───────────────────────────────────
vector_store = RecipeVectorStore()
chef_agent = build_chef_agent(vector_store)

app = FastAPI(
    title="CulinaryAI API",
    version="0.3.0",
    description="Pantry-aware planning and vision AI API for the CulinaryAI platform.",
)


@app.on_event("startup")
async def _startup_check() -> None:
    key = os.getenv("GEMINI_API_KEY", "")
    if key and key != "your_gemini_api_key_here":
        logger.info("✅ GEMINI_API_KEY is configured (model: %s)", os.getenv("GEMINI_MODEL", "gemini-2.5-flash"))
    else:
        logger.warning(
            "⚠️  GEMINI_API_KEY is NOT set. "
            "Receipt and fridge scanning will return 500 errors. "
            "Create backend/.env with GEMINI_API_KEY=<your_key>"
        )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.get("/")
def root() -> dict:
    return {
        "status": "online",
        "service": "CulinaryAI API",
        "version": app.version,
        "health": "/health",
        "docs": "/docs",
    }


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", indexed_recipes=len(repository.recipes))



@app.post("/match-product", response_model=MatchProductResponse)
async def match_product(request: MatchProductRequest) -> MatchProductResponse:
    return await asyncio.to_thread(product_matcher.match, request)


@app.post("/normalize-shopping-query", response_model=NormalizeShoppingQueryResponse)
async def normalize_shopping_query(
    request: NormalizeShoppingQueryRequest,
) -> NormalizeShoppingQueryResponse:
    return await asyncio.to_thread(product_matcher.normalize_query, request)


@app.post("/chef-chat", response_model=ChefChatResponse)
async def chef_chat(request: ChefChatRequest) -> ChefChatResponse:
    """
    AI Chef Chat powered by a 4-node LangGraph RAG pipeline:
      1. parse_intent   — Detect what the user wants
      2. retrieve_recipes — ChromaDB semantic search (Gemini embeddings)
      3. filter_by_pantry — Re-rank by pantry availability
      4. generate_response — Gemini LLM with retrieved recipe context
    """
    pantry_dicts = [item.model_dump() for item in request.pantry_items]

    result = await asyncio.to_thread(
        chef_agent.invoke,
        {
            "user_message": request.message,
            "pantry_items": pantry_dicts,
            # Initialize optional state fields with defaults
            "intent": "",
            "dietary_preferences": [],
            "max_cook_time": None,
            "retrieved_recipes": [],
            "pantry_filtered_recipes": [],
            "reply": "",
            "retrieval_used": False,
            "recipes_found": 0,
        },
    )

    return ChefChatResponse(reply=result["reply"])


@app.get("/rag-status")
def rag_status() -> dict:
    """Debug endpoint: shows RAG vector store health."""
    return {
        "status": "ok",
        "vector_store": "chromadb",
        "embedding_model": "gemini-text-embedding-004",
        "indexed_recipes": vector_store.recipe_count,
        "langgraph_nodes": ["parse_intent", "retrieve_recipes", "filter_by_pantry", "generate_response"],
    }


@app.post("/generate-plan", response_model=GeneratePlanResponse)
def generate_plan(request: GeneratePlanRequest) -> GeneratePlanResponse:
    return planner.generate_plan(request)


@app.post("/generate-instructions", response_model=InstructionResponse)
def generate_instructions(request: InstructionRequest) -> InstructionResponse:
    try:
        return planner.instructions(request.recipe_id, request.servings)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Recipe not found") from error


@app.post("/parse-receipt", response_model=ValidatedReceiptResponse)
async def parse_receipt(
    file: UploadFile = File(..., description="Multipart image of receipt"),
    user_id: str | None = Header(default=None, alias="X-User-Id"),
    user_id_form: str | None = Form(default=None, alias="user_id"),
    aliases_json: str | None = Form(default=None, alias="household_aliases"),
) -> ValidatedReceiptResponse:
    effective_user = user_id or user_id_form or "default_user"
    
    aliases: dict[str, str] | None = None
    if aliases_json:
        try:
            aliases = json.loads(aliases_json)
        except Exception:
            aliases = None

    image_bytes = await file.read()
    mime = file.content_type or "image/jpeg"
    
    return await asyncio.to_thread(
        vision_service.parse_receipt,
        image_bytes=image_bytes,
        mime_type=mime,
        user_id=effective_user,
        household_aliases=aliases,
    )


@app.post("/scan-fridge", response_model=FridgeScanResponse)
async def scan_fridge(
    file: UploadFile = File(..., description="Multipart image of fridge shelf or compartment"),
    user_id: str | None = Header(default=None, alias="X-User-Id"),
    user_id_form: str | None = Form(default=None, alias="user_id"),
    pantry_items_json: str | None = Form(default=None, alias="pantry_items"),
) -> FridgeScanResponse:
    effective_user = user_id or user_id_form or "default_user"

    pantry_items: list[ExistingPantryItem] = []
    if pantry_items_json:
        try:
            raw_list = json.loads(pantry_items_json)
            if isinstance(raw_list, list):
                for item in raw_list:
                    pantry_items.append(ExistingPantryItem.model_validate(item))
        except Exception:
            pass

    image_bytes = await file.read()
    mime = file.content_type or "image/jpeg"

    # Detect items using Gemini vision (run sync SDK call off the event loop)
    detected_scan = await asyncio.to_thread(
        vision_service.scan_fridge,
        image_bytes=image_bytes,
        mime_type=mime,
        user_id=effective_user,
    )

    # Reconcile detected items vs household pantry items
    return fridge_reconciler.reconcile(
        detected_scan=detected_scan,
        pantry_items=pantry_items,
    )


@app.post("/analyze-meal", response_model=MealNutritionEstimate)
async def analyze_meal(
    file: UploadFile = File(..., description="Photo of one meal or plate"),
    user_id: str | None = Header(default=None, alias="X-User-Id"),
    user_id_form: str | None = Form(default=None, alias="user_id"),
) -> MealNutritionEstimate:
    effective_user = user_id or user_id_form or "default_user"
    image_bytes = await file.read()
    return await asyncio.to_thread(
        vision_service.analyze_meal,
        image_bytes=image_bytes,
        mime_type=file.content_type or "image/jpeg",
        user_id=effective_user,
    )
