import json
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.models.schemas import (
    GeneratePlanRequest,
    GeneratePlanResponse,
    HealthResponse,
    InstructionRequest,
    InstructionResponse,
)
from app.models.vision_schemas import (
    ExistingPantryItem,
    FridgeScanResponse,
    ValidatedReceiptResponse,
)
from app.services.fridge_reconciler import FridgeReconciler
from app.services.gemini_service import GeminiVisionService
from app.services.ingredient_catalog import IngredientCatalogService
from app.services.meal_planner import MealPlannerService
from app.services.recipe_repository import VerifiedRecipeRepository

repository = VerifiedRecipeRepository()
planner = MealPlannerService(repository)
catalog_service = IngredientCatalogService()
vision_service = GeminiVisionService(catalog_service=catalog_service)
fridge_reconciler = FridgeReconciler(catalog=catalog_service)

app = FastAPI(
    title="CulinaryAI API",
    version="0.3.0",
    description="Pantry-aware planning and vision AI API for the CulinaryAI platform.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", indexed_recipes=len(repository.recipes))


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
    
    return vision_service.parse_receipt(
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

    # Detect items using Gemini vision
    detected_scan = vision_service.scan_fridge(
        image_bytes=image_bytes,
        mime_type=mime,
        user_id=effective_user,
    )

    # Reconcile detected items vs household pantry items
    return fridge_reconciler.reconcile(
        detected_scan=detected_scan,
        pantry_items=pantry_items,
    )
