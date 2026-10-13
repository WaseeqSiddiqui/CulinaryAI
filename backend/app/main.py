from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.models.schemas import (
    GeneratePlanRequest,
    GeneratePlanResponse,
    HealthResponse,
    InstructionRequest,
    InstructionResponse,
)
from app.services.meal_planner import MealPlannerService
from app.services.recipe_repository import VerifiedRecipeRepository

repository = VerifiedRecipeRepository()
planner = MealPlannerService(repository)

app = FastAPI(
    title="CulinaryAI Meal Planning API",
    version="0.2.0",
    description="Pantry-aware planning API integrated with the CulinaryAI mobile client.",
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
