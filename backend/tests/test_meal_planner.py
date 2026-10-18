from app.models.schemas import GeneratePlanRequest, PantryItemInput
from app.services.meal_planner import MealPlannerService
from app.services.recipe_repository import RetrievedRecipe, VerifiedRecipeRepository


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


def test_allergens_and_disliked_ingredients_are_excluded() -> None:
    request = GeneratePlanRequest(
        pantry_items=[PantryItemInput(name="rice", quantity=500, unit="g")],
        avoid_ingredients=["egg"],
        meal_count=7,
    )

    response = build_planner().generate_plan(request)

    assert response.meals
    assert all(
        "egg" not in " ".join(
            ingredient.name.lower() for ingredient in meal.ingredients_required
        )
        for meal in response.meals
    )


def test_pantry_first_never_returns_a_recipe_with_zero_pantry_overlap() -> None:
    request = GeneratePlanRequest(
        pantry_items=[PantryItemInput(name="eggs", quantity=6, unit="pcs")],
        meal_count=7,
        pantry_first=True,
    )

    response = build_planner().generate_plan(request)

    assert response.pantry_checked is True
    assert response.meals
    assert all(meal.available_ingredients for meal in response.meals)
    assert all(meal.pantry_match_percent > 0 for meal in response.meals)


def test_per_person_calorie_target_contributes_to_ranking() -> None:
    repository = VerifiedRecipeRepository()
    lower = RetrievedRecipe(repository.get("rec_spiced_dal"), score=0.5)
    higher = RetrievedRecipe(repository.get("rec_chicken_rice"), score=0.5)
    request = GeneratePlanRequest(
        meals_per_day=3,
        target_calories_per_person_per_day=1200,
    )
    planner = MealPlannerService(repository)

    lower_score = planner._combined_score(lower, [], request)
    higher_score = planner._combined_score(higher, [], request)

    assert planner._calorie_target(request) == 400
    assert lower_score > higher_score


def test_people_count_scales_quantities_without_changing_per_person_calories() -> None:
    request = GeneratePlanRequest(
        pantry_items=[
            PantryItemInput(name="chicken breast", quantity=500, unit="g"),
            PantryItemInput(name="basmati rice", quantity=250, unit="g"),
        ],
        servings=2,
        meal_count=1,
    )

    response = build_planner().generate_plan(request)
    meal = response.meals[0]
    chicken = next(
        ingredient
        for ingredient in meal.ingredients_required
        if ingredient.name == "Chicken Breast"
    )

    assert response.requested_servings == 2
    assert meal.servings == 2
    assert chicken.quantity == 250
    assert meal.calories_per_serving == 480
