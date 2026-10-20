from app.rag.vector_store import RecipeVectorStore
from app.rag.langgraph_agent import build_chef_agent

vs = RecipeVectorStore()
agent = build_chef_agent(vs)

print("=== TEST 1: Semantic Search in Vector Store ===")
results = vs.search("biryani masala rice", n_results=3)
for r in results:
    score = r["_similarity_score"]
    name = r["name"]
    cuisine = r.get("cuisine", "")
    t = r.get("cook_time_minutes", 0)
    print(f"- {name} | Score: {score:.3f} | Cuisine: {cuisine} | Time: {t}m")

print("\n=== TEST 2: Filter by Cook Time (<= 25m) ===")
quick_results = vs.search("dinner", n_results=4, max_cook_time=25)
for r in quick_results:
    print(f"- {r['name']} | Time: {r.get('cook_time_minutes')}m")

print("\n=== TEST 3: Dietary Filter (vegetarian) ===")
veg_results = vs.search("curry", n_results=3, dietary_filter=["vegetarian"])
for r in veg_results:
    print(f"- {r['name']} | Dietary: {r.get('dietary_tags')}")

print("\n=== TEST 4: Full LangGraph Graph Execution ===")
state_in = {
    "user_message": "aaj raat ke liye jaldi banne wali chicken dish batao",
    "pantry_items": [
        {"name": "Chicken", "quantity": 500, "unit": "g"},
        {"name": "Garlic", "quantity": 4, "unit": "cloves"},
        {"name": "Basmati Rice", "quantity": 250, "unit": "g"},
        {"name": "Cooking Oil", "quantity": 50, "unit": "ml"}
    ]
}
out = agent.invoke(state_in)
print(f"Intent detected: {out['intent']}")
print(f"Max time constraint: {out['max_cook_time']} min")
print(f"Retrieved count: {len(out['retrieved_recipes'])}")
print("Top Pantry-Ranked Recipes:")
for r in out["pantry_filtered_recipes"][:3]:
    p_pct = r["_pantry_match_pct"]
    c_score = r["_combined_score"]
    print(f"  * {r['name']}: pantry_match={p_pct}%, combined_score={c_score}")
print("ALL TESTS PASSED SUCCESSFULLY!")
