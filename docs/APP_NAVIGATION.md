# App navigation

Home starts with six named tasks. A recipe image no longer pushes core actions
below the first screen. The existing color palette is unchanged.

| Destination | Where to find it |
| --- | --- |
| Add an ingredient | Home → Add food → Enter an ingredient |
| Scan groceries | Home → Add food → Scan a receipt or Scan your fridge |
| Scan a receipt | Home → Scan receipt |
| Check or edit expiry | Home → Check expiry → select an ingredient |
| Scan an expiry label | Home → Check expiry → ingredient → Scan label |
| Pantry quantities and zones | My Pantry tab |
| Find or create recipes | Recipes tab → Find recipes or Create recipe |
| Guided cooking | Recipe details → Start guided cooking |
| Weekly planning | Recipes tab → Meal plan |
| Nutrition goals | Recipes tab → Nutrition |
| Meal nutrition scan | Recipes → Nutrition → Scan meal |
| Saved recipes | Recipes tab → Saved recipes |
| Cooking preferences | Recipes → Portions and dietary preferences |
| Chef Chat | Home → Ask Chef |
| Groceries to buy | Shopping tab |
| Recorded orders | Shopping → Order history |
| Profile and household | Profile tab |
| Every tool with a description | Home → All features |

All features includes a local search for feature names and descriptions. It
does not issue remote recipe or AI requests. Normal Android Back navigation
returns to the previous screen. The expiry overview reads the full pantry,
independently of active pantry search and zone filters, and opens the existing
ingredient editor at its expiry controls. No separate inventory save path is
introduced.

Switching recipe sections ignores responses from earlier sections so an
outstanding request cannot replace the newly selected section's results.

Layout and navigation checks cover a 320 px phone, a 390 px phone, tablet,
desktop, dark mode and enlarged text. They exercise feature search, scanner
routing, direct expiry editing and cancellation, recipe section changes and
the main destinations. These checks do not establish backend deployment,
merchant checkout readiness or app-store signing.
