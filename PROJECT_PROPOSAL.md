# CULINARYAI: Master Project Proposal & System Specification (v2.1)
*AI-Powered Household Meal Planning & Kitchen Management System*

---

## 1. Project Information & Executive Overview

| Project Information | Details |
| :--- | :--- |
| **Project Name** | **CulinaryAI** |
| **Project Type** | AI-Powered Mobile Application / Research & Development |
| **Primary Platform** | Flutter Mobile Application (iOS & Android) |
| **Backend & Database** | Firebase (Auth, Firestore Realtime, Security Rules) + Python / FastAPI AI Microservice |
| **AI Layer** | LLM + RAG (Vector DB) + Multimodal Vision (Receipt Ingestion) |
| **Core Domains** | Pantry Management, Camera Receipt Ingestion, Interactive Guided Cooking, Nutrition, Smart Replenishment |
| **Team Structure** | **Person A**: Flutter App, Auth, Shared Pantry, Receipt Camera Scanner (UC6, UC11)<br>**Person B**: Nutrition & Portion Scaling Engine (UC2)<br>**Person C**: AI Meal Planning & Guided Cooking Assistant (UC1, UC4, UC5, UC7) |
| **Document Status** | Approved Master Proposal & Technical Architecture (Updated with Exact User Flows) |

---

## 2. Updated System Architecture

```mermaid
graph TD
    subgraph MobileApp ["Flutter Mobile Client (Person A)"]
        UI_Auth["Auth & Household Module"]
        UI_Pantry["Real-Time Pantry UI (UC6)"]
        UI_Receipt["Camera Receipt Scanner & Review (UC11)"]
        UI_Meal["Meal Plan & Recipes UI (UC1)"]
        UI_CookMode["Step-by-Step Guided Cooking Screen (UC5)"]
        UI_Replenish["Low Stock Cart & Deep Links (UC9, UC10)"]
    end

    subgraph FirebaseLayer ["Firebase Cloud Backend"]
        FB_Auth["Firebase Authentication"]
        FB_Store[("Cloud Firestore Real-Time DB")]
        FB_Rules["Security Rules (Household Isolation)"]
    end

    subgraph AIService ["AI & Data Microservice (FastAPI - Person C & B)"]
        API_Gateway["FastAPI Gateway"]
        Vision_OCR["Receipt OCR / Vision Extraction"]
        LLM_Planner["Pantry-Aware Meal Planner & Recipe Steps"]
        Nutr_Engine["Nutrition Calculation Engine (Person B)"]
    end

    UI_Receipt -->|1. Scan Receipt via Camera| Vision_OCR
    Vision_OCR -->|2. Structured Items JSON| UI_Receipt
    UI_Receipt -->|3. User Confirms Items| FB_Store

    UI_Pantry <-->|Live Snapshot Sync| FB_Store
    UI_Meal -->|What should I cook? (Pantry Items)| LLM_Planner
    LLM_Planner -->|Suggested Dishes| UI_Meal
    UI_Meal -->|User selects 'Cook This'| UI_CookMode
    UI_CookMode -->|Final Step: 'Yes, I cooked this'| FB_Store
    
    FB_Store -->|Low Stock Triggers| UI_Replenish
    UI_Replenish -->|Deep Link (Daraz Mart / Pandamart)| External_Stores["Daraz / Pandamart / Store Apps"]
```

---

## 3. Detailed Core User Flows

### Flow 1: Camera Receipt Scanning & Verified Inventory Onboarding (UC11 & UC6)
1. **Camera Capture**: User points the camera at a grocery store bill/receipt or selects a photo.
2. **Item Extraction**: The system extracts item names, quantities, and units (e.g. `Milk: 2 Litres`, `Eggs: 12 pcs`).
3. **User Verification Modal**: An editable review bottom-sheet displays detected items with checkboxes and locations (Fridge, Freezer, Pantry Shelf, Spice Rack).
4. **Instant Update**: User taps **"Confirm & Add to Pantry"** $\rightarrow$ items are batch-updated directly in the shared household inventory.

### Flow 2: Pantry-Aware Recommendation & Guided Cooking (UC1, UC5 & UC7)
1. **Pantry-Aware Prompt**: User asks: *"I want to cook something, tell me what should I cook."*
2. **AI Inspection**: AI checks currently available household pantry ingredients and generates matching recipes with match percentage and required ingredients.
3. **Interactive Guided Mode**: User taps **"Cook This"** on a chosen dish. The entire interface transforms into **Step-by-Step Guided Cooking Mode**.
4. **Step-by-Step Progression**: AI guides the user step-by-step (e.g., Step 1: Prepping chicken, Step 2: Adding spices/masalas, Step 3: Simmering).
5. **Final Confirmation & Safe Deduction (UC7)**:
   * At the final step, the AI prompts: *"Have you finished cooking this meal?"*
   * Only when the user taps **"Yes, I cooked this"**, the recipe's ingredients are permanently deducted from the pantry! No accidental or premature deductions occur.

### Flow 3: Smart Low-Stock Notifications & 1-Tap Purchase Redirect (UC8, UC9 & UC10)
1. **Proactive Alerts**: System monitors ingredient levels and estimated days remaining. If items run low (e.g., Milk, Cooking Oil, Eggs), proactive notifications/banners alert the user (e.g. in the evening).
2. **Restock Hub**: Opening the alert or navigating to the Restock screen presents a dedicated list of missing or low-stock items.
3. **1-Tap Direct Purchase**: Every item row features an immediate action button (e.g. **"Buy on Daraz Mart"** or **"Buy on Pandamart"**) that deep-links directly to the product search on the grocery delivery platform!

---

## 4. Complete Data Contracts

### 4.1 Pantry Item Schema (UC6 & UC11)
```json
{
  "item_id": "pantry_001",
  "household_id": "hh_9981",
  "name": "Whole Milk",
  "quantity": 2.0,
  "unit": "litres",
  "location": "fridge",
  "low_stock_threshold": 0.5,
  "is_low_stock": false,
  "updated_at": "2026-10-08T12:00:00Z"
}
```

### 4.2 Guided Cooking Recipe Schema (UC1 & UC5)
```json
{
  "recipe_id": "rec_001",
  "name": "Creamy Garlic Herb Chicken",
  "prep_time_minutes": 25,
  "servings": 4,
  "ingredients_required": [
    { "name": "Chicken Breast", "quantity": 500, "unit": "g" },
    { "name": "Garlic Cloves", "quantity": 4, "unit": "cloves" },
    { "name": "Heavy Cream", "quantity": 200, "unit": "ml" }
  ],
  "steps": [
    { "step_number": 1, "instruction": "Season chicken breast with salt, black pepper, and herbs.", "timer_seconds": 0 },
    { "step_number": 2, "instruction": "Heat olive oil in pan and sear chicken for 6-7 minutes each side.", "timer_seconds": 420 },
    { "step_number": 3, "instruction": "Add minced garlic and stir for 1 minute until fragrant.", "timer_seconds": 60 },
    { "step_number": 4, "instruction": "Pour in heavy cream and simmer until sauce thickens.", "timer_seconds": 180 }
  ]
}
```

---

## 5. Team Responsibilities & Week 1 Alignment

| Team Member | Domain | Scope & Deliverables |
| :--- | :--- | :--- |
| **Person A** | **App Shell, Auth, Pantry, Receipt Scanner & Shopping Links** | • Flutter project architecture & modern theme<br>• Firebase Auth & Household invite/join system<br>• Realtime Pantry CRUD with storage zones<br>• Camera Receipt Scanner + Review & Confirmation Dialog<br>• Guided Cooking completion deduction hook<br>• Low-stock Restock screen with Daraz/Pandamart deep linking |
| **Person B** | **Nutrition & Portion Scaling** | • Nutrition data layer and unit conversions<br>• Recipe calculation arithmetic (total & per-serving macros)<br>• Dynamic portion scaler module |
| **Person C** | **AI Meal Planning & Guided Cooking** | • FastAPI backend setup<br>• Pantry-aware meal generation endpoint (`/generate-plan`)<br>• Step-by-step cooking instruction generator<br>• RAG embedding pipeline for verified recipes |
