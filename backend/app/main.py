import asyncio
import json
import logging
import os

from dotenv import load_dotenv

# Load .env from the backend directory (one level up from app/)
load_dotenv()

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
    CookingStepValidationResponse,
    StepExplanationRequest,
    StepExplanationResponse,
    CookingStepChatRequest,
    CookingStepChatResponse,
)
from app.services.fridge_reconciler import FridgeReconciler
from app.services.gemini_service import GeminiVisionService
from app.services.ingredient_catalog import IngredientCatalogService
from app.services.meal_planner import MealPlannerService
from app.services.product_matcher import ProductMatcher
from app.services.recipe_repository import VerifiedRecipeRepository
from app.models.recipe_discovery import RecipeDiscoveryRequest, RecipeDiscoveryResponse
from app.services.live_recipe_discovery import LiveRecipeDiscoveryService, RecipeProviderUnavailable

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

repository = VerifiedRecipeRepository()
planner = MealPlannerService(repository)
catalog_service = IngredientCatalogService()
vision_service = GeminiVisionService(catalog_service=catalog_service)
fridge_reconciler = FridgeReconciler(catalog=catalog_service)
product_matcher = ProductMatcher()
recipe_discovery = LiveRecipeDiscoveryService()

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
    pantry_dicts = [item.model_dump() for item in request.pantry_items]
    reply = await asyncio.to_thread(
        vision_service.ask_chef,
        prompt=request.message,
        pantry_items=pantry_dicts,
    )
    return ChefChatResponse(reply=reply)


@app.post("/generate-plan", response_model=GeneratePlanResponse)
def generate_plan(request: GeneratePlanRequest) -> GeneratePlanResponse:
    return planner.generate_plan(request)


@app.post("/discover-recipes", response_model=RecipeDiscoveryResponse)
def discover_recipes(request: RecipeDiscoveryRequest) -> RecipeDiscoveryResponse:
    try:
        return recipe_discovery.discover(request)
    except RecipeProviderUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from None
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None


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


@app.post("/validate-cooking-step", response_model=CookingStepValidationResponse)
async def validate_cooking_step(
    file: UploadFile = File(..., description="Photo of cooking progress in pan/pot"),
    recipe_title: str = Form(..., description="Title of the recipe being cooked"),
    step_number: int = Form(..., description="Current step index or number"),
    step_instruction: str = Form(..., description="Instruction text of the current step"),
    user_question: str | None = Form(default=None, description="Optional question/check from the cook"),
    user_id: str | None = Header(default=None, alias="X-User-Id"),
    user_id_form: str | None = Form(default=None, alias="user_id"),
) -> CookingStepValidationResponse:
    effective_user = user_id or user_id_form or "default_user"
    image_bytes = await file.read()
    mime = file.content_type or "image/jpeg"
    return await asyncio.to_thread(
        vision_service.validate_cooking_step,
        image_bytes=image_bytes,
        mime_type=mime,
        recipe_title=recipe_title,
        step_number=step_number,
        step_instruction=step_instruction,
        user_question=user_question,
        user_id=effective_user,
    )


@app.post("/step-explanation", response_model=StepExplanationResponse)
async def get_step_explanation(
    request: StepExplanationRequest,
) -> StepExplanationResponse:
    return await asyncio.to_thread(
        vision_service.get_step_explanation,
        recipe_title=request.recipe_title,
        step_number=request.step_number,
        step_instruction=request.step_instruction,
    )


@app.post("/cooking-step-chat", response_model=CookingStepChatResponse)
async def cooking_step_chat(
    request: CookingStepChatRequest,
) -> CookingStepChatResponse:
    reply = await asyncio.to_thread(
        vision_service.chat_cooking_step,
        recipe_title=request.recipe_title,
        step_number=request.step_number,
        step_instruction=request.step_instruction,
        message=request.message,
        conversation_history=[turn.model_dump() for turn in request.conversation_history],
        adjustments=request.adjustments,
        dietary_restrictions=request.dietary_restrictions,
    )
    return CookingStepChatResponse(reply=reply)
