from app.models.schemas import GeneratePlanRequest, PantryItemInput
from app.services.meal_planner import MealPlannerService
from app.services.recipe_repository import VerifiedRecipeRepository


def build_planner() -> MealPlannerService:
    return MealPlannerService(VerifiedRecipeRepository())


def test_plan_prioritizes_recipes_that_match_the_pantry() -> None:
    request = GeneratePlanRequest(
        pantry_items=[
            PantryItemInput(name="chicken breast", quantity=500, unit="g"),
            PantryItemInput(name="basmati rice", quantity=250, unit="g"),
            PantryItemInput(name="garlic cloves", quantity=3, unit="pcs"),
            PantryItemInput(name="olive oil", quantity=2, unit="tbsp"),
        ],
        meal_count=1,
        servings=4,
    )

    response = build_planner().generate_plan(request)

    assert response.meals[0].recipe_id == "rec_chicken_rice"
    assert response.meals[0].pantry_match_percent == 100
    assert response.meals[0].missing_ingredients == []


def test_dietary_and_cook_time_filters_are_applied() -> None:
    request = GeneratePlanRequest(
        pantry_items=[PantryItemInput(name="red lentils", quantity=500, unit="g")],
        dietary_preferences=["vegan"],
        max_cook_time_minutes=35,
        meal_count=7,
    )

    response = build_planner().generate_plan(request)

    assert response.meals
    assert all(meal.cook_time_minutes <= 35 for meal in response.meals)
    assert response.meals[0].recipe_id == "rec_spiced_dal"


def test_user_question_contributes_to_recipe_retrieval() -> None:
    request = GeneratePlanRequest(
        question="quick breakfast with eggs",
        pantry_items=[],
        meal_count=1,
    )

    response = build_planner().generate_plan(request)

    assert response.meals[0].recipe_id == "rec_frittata"


def test_instruction_generator_scales_ingredients() -> None:
    response = build_planner().instructions("rec_chicken_rice", servings=8)
    chicken = next(
        ingredient
        for ingredient in response.ingredients_required
        if ingredient.name == "Chicken Breast"
    )

    assert chicken.quantity == 1000
    assert response.steps[0].step_number == 1
    assert any(step.timer_seconds > 0 for step in response.steps)
