# CulinaryAI manual testing guide

Roman Urdu guide | 10 November 2026 | Android test build

Yeh guide automatic purchasing aur checkout automation ke ilawa app ke features ko khud test karne ke liye hai. Har case mein screen ka rasta, test ka tareeqa aur pass hone ki condition di gayi hai. Case ko sirf tab PASS likhein jab aap us ka result phone par dekh lein.

## Abhi ki verified condition

- Flutter analysis mein koi issue nahi mila. Latest Flutter suite ke 216 tests pass hue.
- Local backend ke 96 tests pass hue. Yeh local code ki checking hai; hosted server par har feature ki availability ka proof nahi.
- Updated Android debug APK Vivo V2440 par install hua. Address selection ka extra blocking message hata diya gaya; Enter ab visible address suggestion select karta hai. Address fix ke baad user ka positive feedback mila; final scripted Sultan Town test complete nahi hua.
- Device par WebView JavaScript, backend HTTPS, TTS playback aur speech engine initialization check hue. Asal boli hui speech ki recognition abhi manually test karni hai.
- OCR model pehle APK mein missing tha. Asset ab bundle hota hai aur asset test pass hai; native expiry OCR ko corrected APK par dobara test karna zaroori hai.

## Khuli hui cheezen

Hosted backend par latest audit mein discover-recipes, step-explanation, cooking-step-chat aur validate-cooking-step endpoints 404 de rahe the. In online features ka full pass backend deploy aur retest ke baad hi milega. Household invites aur cross-device cloud writes ki live verification bhi baqi hai. Meal scanner ne non-food image par zero-confidence result diya tha; usay meal log mein save hone dena ek known gap hai.

## Test shuru karne se pehle

Ek test account aur alag test household use karein. Sample stock banayein: Milk 1 L, Rice 1 kg, Tomato 4 pcs aur Eggs 6 pcs. Fresh, kal expire hone wala aur guzri hui expiry wala alag test item rakhein. Ek saaf receipt, expiry label, fridge photo aur meal photo tayyar rakhein. Camera aur microphone permissions zaroorat par dein. Data delete ya household switch se pehle apna asli stock alag rakhein.

Har case ke liye PASS, FAIL, BLOCKED ya NOT RUN likhein. Network, permission ya server ki wajah se case na chal sake to BLOCKED likhein. Is document mein neeche diye gaye cases checklist hain; in sab ka live pass claim nahi kiya gaya.

<!-- page -->
## Account profile aur household

### A01 Account banana aur validation
Kahan: Login screen > Create an account.
Test: Khali fields, ghalat email aur mismatch passwords try karein. Phir naya test account banayein.
Pass: Ghalat input par samajh aane wala error aaye; valid account se Home khule aur duplicate account na bane.

### A02 Login logout aur session
Kahan: Login screen; Home > Kitchen Menu > Log out.
Test: Ghalat password try karein, sahi account se login karein, app band karke kholein. Logout cancel aur confirm dono check karein.
Pass: Error par app crash na ho; valid session restore ho; logout ke baad protected screens se purana account access na ho.

### A03 Google login aur demo
Kahan: Login > Continue with Google; Explore the Demo Kitchen.
Test: Google account picker cancel karein, phir test account se login karein. Demo alag session mein kholein.
Pass: Cancel se loading khatam ho; login sahi user ka ho. Demo ko real cloud account ki successful testing na samjhein.

### A04 Profile edit aur appearance
Kahan: Profile > Edit ya Edit Personal Details; Home ka Light Mode ya Dark Mode icon.
Test: Naam, phone, city, date of birth aur food preference badal kar save karein. Dobara kholein. Theme badlein.
Pass: Saved fields sahi rahen, email read-only ho to us ka behavior clear ho, dono themes mein text readable ho.

### A05 Household create aur rename
Kahan: Profile > Household > Your household.
Test: Alag test kitchen banayein; owner se Rename karein; screen dobara kholein.
Pass: Ek household bane, sahi naam aur owner nazar aayein; dobara kholne par naam retained ho.

### A06 Invite join aur member roles
Kahan: Your household > New invite; doosre test account se Join household.
Test: Valid, invalid aur expired invite try karein. Owner se member management kholein; member account se owner actions check karein.
Pass: Valid code hi join kare; ghalat code clear error de. Member ko owner privileges na milen. Invite access issue aaye to FAIL ya BLOCKED record karein.

### A07 Household data ki isolation
Kahan: Do test accounts aur do households ki My Pantry aur Restock screens.
Test: Household A mein ek unique item banayein; account ya household B par switch karein; phir A par wapas aayein.
Pass: B ko A ka private stock na dikhe; A par wapas aane se sahi stock aaye. Cloud sync ko do devices par alag verify karein.

<!-- page -->
## Pantry aur expiry

### P01 Ingredient add aur persistence
Kahan: My Pantry > Add ingredient ya Add your first ingredient.
Test: Milk 1 L add karein; quantity, unit, storage zone aur expiry set karein. Save karke screen aur app dobara kholein.
Pass: Ek hi item bane; har field sahi rahe. Empty name, invalid quantity aur double Save se ghalat record na bane.

### P02 Quantity edit aur stock controls
Kahan: My Pantry > item > Edit Details; item ke plus aur minus controls.
Test: Rice 1 kg ko 1.5 kg karein; plus aur minus dabayein; zero aur negative boundary check karein.
Pass: Sahi quantity aur unit dikhayen; negative stock na bane; refresh par value purani na ho. Duplicate items hon to pehle unhein alag pehchanein.

### P03 Zones filters aur item details
Kahan: My Pantry > All, Fridge, Freezer, Pantry Shelf, Spice Rack; Filter by Zone.
Test: Har zone mein ek item rakhein. Filter badlein, item details kholein aur item ko doosre zone mein move karein.
Pass: Sahi zone ke items hi dikhein; All par sab wapas aayen; moved item purane zone mein na rahe.

### P04 Expiry date manually set karna
Kahan: My Pantry > item > Edit Details > expiry date.
Test: Ek fresh date, kal ki date aur guzri hui date teen test items par set karein. Save karke reopen karein.
Pass: Date sahi save ho, din shift na ho, expiry badges aur Use Soon grouping date ke mutabiq hon. Boundary results ki screenshot lein.

### P05 Expiry label scan aur correction
Kahan: Item edit form > Scan label > Scan an expiry label.
Test: Saaf EXP ya Best Before label scan karein. Detected date ko asal label se milayein; zaroorat par correct karke confirm karein.
Pass: Confirmed date item form mein aaye aur Save ke baad retained ho. Manufacture date ko expiry samajhna FAIL hai; unclear scan ko manually correct kiya ja sake.

### P06 Estimate aur opened package
Kahan: Item edit form > Package details > Estimate aur Mark opened.
Test: Pehle printed expiry note karein. Estimated expiry aur opened state set karein; reopen karein.
Pass: Estimate ki nature clear rahe, opened state save ho, printed aur estimated dates confuse na hon. Estimate ko food safety ki guarantee na samjhein.

### P07 Remove undo aur low stock
Kahan: My Pantry > item > Remove; Home > Low Stock; Restock.
Test: Test item remove karke Undo karein. Phir quantity low-stock level tak kam karein aur tabs refresh karein.
Pass: Undo ek hi record restore kare; counts aur Restock sahi update hon; har refresh par duplicate shopping entries na banein.

<!-- page -->
## Fridge receipt aur meal scanners

### S01 Camera gallery aur cancel
Kahan: Home > Scan Fridge ya Scan Receipt; Kitchen Menu > Grocery management.
Test: Camera aur gallery dono kholein; photo lene se pehle cancel karein. Phir permission deny karke dobara try karein.
Pass: Cancel se stock na badle; deny par samajh aane wala message ho; permission dene ke baad retry kaam kare.

### S02 Fridge scan aur selective save
Kahan: Scan Fridge > photo > review.
Test: Saaf fridge photo dein. Detected names, quantities aur zones dekhein; ek item deselect ya correct karein; selected items save karein.
Pass: Sirf selected aur corrected items pantry mein aayen. AI ki har guessed quantity ko exact weight na maana jaye; repeated Save duplicate na banaye.

### S03 Empty photo aur failed scan
Kahan: Scan Fridge aur Scan Receipt.
Test: Non-food photo, blur aur blank image dein. Network band karke scan karein; phir Try another photo se retry karein.
Pass: Fake items auto-save na hon; loader hamesha na ghoomta rahe; error ya empty result clear ho aur retry mumkin ho.

### S04 Receipt line items aur totals
Kahan: Home > Scan Receipt > photo > review.
Test: Aisi receipt dein jiska total khud calculate kar sakein. Name, quantity, unit, line price aur total compare karein.
Pass: Items aur numbers receipt se match hon; discount, tax aur total ko grocery item na bana de. Unclear number ko save se pehle correct kiya ja sake.

### S05 Receipt edit add remove aur commit
Kahan: Receipt review > Review item options, Correct Receipt Item, Add Item, Choose storage zone.
Test: Ek line edit karein, ek remove karein, ek missing item add karein. Save karein aur My Pantry mein verify karein.
Pass: Final reviewed list hi add ho; removed line na aaye; double tap se stock do martaba add na ho. Retake se purana review commit na ho.

### S06 Meal nutrition aur daily log
Kahan: Kitchen Menu > Nutrition goals > Scan meal nutrition icon.
Test: Meal photo dein; dish, calories aur macros review karein; Add to today ek baar dabayein; goals screen par wapas aayein.
Pass: Ek log entry bane aur daily totals ek baar update hon. Nutrition estimates ko exact measurement na samjhein.

### S07 Non-food meal aur OCR retest
Kahan: Scan a meal; Scan an expiry label.
Test: Meal scanner ko non-food photo dein. Expiry scanner ko saaf test label dein aur detected date compare karein.
Pass: Non-food result meal log mein save na ho. Corrected APK mein OCR model load ho aur valid date review tak aaye. Dono cases abhi manual retest maangte hain.

<!-- page -->
## Recipes preferences aur meal planning

### R01 Pantry recipes aur availability
Kahan: Kitchen Menu > Pantry recipes; Home > Made for your pantry.
Test: Sample stock ke saath recipe list kholein. Ek required ingredient remove ya expire karke refresh karein.
Pass: Available aur missing ingredients sahi reflect hon; expired ya zero stock ko usable stock na gina jaye. Server unavailable ho to us ki clear state aaye.

### R02 Recipe details aur servings
Kahan: Recipe card > details.
Test: Ingredients, instructions, time aur nutrition dekhein. Servings 1 se 2 karein jahan control available ho.
Pass: Ingredient quantities servings ke mutabiq scale hon; units sahi rahen; per-serving aur total nutrition mix na ho. Instructions readable aur complete hon.

### R03 Recipe creator
Kahan: Home > Create Recipe ya Kitchen Menu > Recipe creator.
Test: Optional preference mein tomato pasta likhein; Find recipes dabayein. Empty query aur unavailable service bhi check karein.
Pass: Pantry-aware result ya clear empty/error state aaye; loading finish ho. Hosted discover-recipes 404 rahe to online case BLOCKED hai.

### R04 Preferences aur avoidance
Kahan: Recipe screen > Cooking preferences.
Test: People eating, Time to cook, Dietary needs, Allergens, Ingredients to avoid aur Favourite cuisines set karke Save preferences karein.
Pass: Reopen par settings retained hon aur generated suggestions mein apply hon. Allergy compliance ko manually ingredients se verify karein; sirf badge par PASS na dein.

### R05 Cookbook aur missing ingredients
Kahan: Pantry recipes > recipe > Save recipe; My cookbook icon; Add missing to Restock.
Test: Recipe save karein, cookbook dobara kholein. Missing list Restock mein add karein aur action repeat karein.
Pass: Saved recipe sahi mile; present items ko missing na gina jaye; repeated add se bekaar duplicates na banein.

### R06 Nutrition goals
Kahan: Kitchen Menu > Nutrition goals > Cooking preferences > Daily targets.
Test: Calories, Protein, Carbs, Fat aur Meals per day badlein. Ek meal log karke progress dekhein.
Pass: Saved targets sahi rahen; daily aur per-meal values clear hon; meal se totals sahi badlein. Invalid input crash ya nonsensical negative progress na de.

### R07 Weekly meal plan
Kahan: Home > Meal Planner ya Kitchen Menu > 7-day meal plan.
Test: People aur goals set karke plan banayein; din aur meals dekhein. Preferences badal kar naya plan request karein.
Pass: Sahi din, meal count aur servings hon; nayi preferences reflect hon. Failure par purane plan ko naya successful response keh kar na dikhaya jaye.

<!-- page -->
## Guided cooking aur Chef Chat

### C01 Cooking start aur step navigation
Kahan: Recipe details > Start guided cooking.
Test: Pehla step dekhein; Next aur Previous use karein. Ingredient checklist aur progress check karein.
Pass: Step number, instruction aur progress sync mein hon; pehle aur aakhri step par out-of-range navigation na ho.

### C02 Technique aur step explanation
Kahan: Guided cooking > Technique and doneness guide.
Test: Ek step ka guide kholein, phir agle step par jayein. Online aur offline dono try karein.
Pass: Guide current step ka ho; local fallback aur live response ka status clear ho. Hosted step-explanation 404 ho to live explanation ka PASS na dein.

### C03 Step chat aur photo question
Kahan: Guided cooking > Ask Chef; camera ya photo option.
Test: Current step par sawal poochein. Phir food photo ke saath Question for Chef aur Ask Chef use karein.
Pass: Response current step se relevant ho; request fail ho to clear error ho aur retry chale. Photo validation hosted deployment tak BLOCKED ho sakti hai.

### C04 Voice input aur spoken guidance
Kahan: Guided cooking > microphone ya voice control; speech playback controls.
Test: Chhota sawal bol kar transcript dekhein; listening stop karein; reply playback start aur stop karein. Microphone deny bhi check karein.
Pass: Asal bole hue lafz useful transcript dein; stop kaam kare; background ya back par microphone aur audio be-wajah chalu na rahen. Initialization ka pass recognition ka proof nahi.

### C05 Timer aur interruptions
Kahan: Guided cooking ke timer wale step.
Test: Timer start, pause aur resume karein. App ko background mein bhejein; 30 second baad wapas aayein.
Pass: Timer ka elapsed time aur state munasib rahe; duplicate timers ya multiple audio alerts na chalne lagen. Notification behavior ko actual phone settings ke saath record karein.

### C06 Finish cancel aur pantry deduction
Kahan: Guided cooking > finish confirmation > Keep cooking ya Confirm and finish.
Test: Pehle cancel karein aur stock compare karein. Phir test recipe finish karein; repeated confirmation try karein.
Pass: Cancel par stock na ghate; successful finish par ingredients sirf ek martaba ghatein; stock negative na ho aur unrelated items na badlein.

### C07 General Chef Chat
Kahan: Main tabs > Chef Chat.
Test: What do I have in my pantry, What is low stock, aur How do I cook tomato pasta poochein. Weekly plan ka sawal aur rapid Send bhi check karein.
Pass: Pantry facts sahi hon; general reply ya offline status clear ho; duplicate requests na chalain. Live recipe discovery ko normal text chat se alag result dein.

<!-- page -->
## Restock history aur screen behavior

### L01 Shopping list manually add karna
Kahan: Restock > Add an item.
Test: Rice 1 kg aur Eggs 6 pcs add karein; required input, unit aur repeat add check karein.
Pass: Naam, quantity aur unit sahi hon; empty entry na bane; repeat add ka behavior consistent ho. Yeh case merchant automation use nahi karta.

### L02 Low stock aur missing ingredients
Kahan: My Pantry > quantity controls; recipe > Add missing to Restock; phir Restock.
Test: Low stock trigger karein aur recipe ke missing ingredients add karein. Tabs aur app reopen karein.
Pass: Zaroori items list mein hon; zero ya expired stock availability ko ghalat na badhaye; unrelated items auto-add na hon.

### L03 Remove aur persistence
Kahan: Restock > item ka Remove icon.
Test: Ek manual test item remove karein; screen aur app dobara kholein.
Pass: Removed entry wapas na aaye jab tak low-stock rule use dobara legitimately add na kare. Baaqi list aur household association sahi rahe.

### L04 Pending order bina store ke
Kahan: Restock > Place order without store.
Test: Sirf test household mein pending order banayein. Order history aur pantry quantities compare karein.
Pass: Pending order record bane, usay merchant ki successful purchase na samjha jaye, pantry stock is action se na badle. Is existing option ko remove nahi kiya gaya.

### L05 Local order history
Kahan: Restock > Order history icon.
Test: Empty history dekhein; pending test order ke baad history reopen karein. App restart ke baad same device par verify karein.
Pass: Status, date aur lines sahi hon; ek action ka ek record ho. Local history ka pass cross-device cloud sync ka proof nahi.

### L06 Home counts aur navigation
Kahan: Home > Current Stock, Use Soon, Low Stock; bottom tabs; Kitchen Menu.
Test: Pantry badal kar counts compare karein. Har tab aur menu entry kholein, Android Back use karein.
Pass: Counts stock se match hon, har entry sahi screen khole aur Back expected jagah le jaye; screen stuck ya blank na ho.

### L07 Keyboard scrolling aur large text
Kahan: Pantry edit, Profile edit, Chef Chat, preferences aur scanners ki review screens.
Test: Keyboard khol kar last field aur Save tak scroll karein. Phone ka text size badha kar light aur dark mode check karein.
Pass: Buttons reachable hon; text ya values clip na hon; keyboard ke peeche critical action na chhupe. Form save se pehle bhara data scroll par reset na ho.

<!-- page -->
## Offline recovery aur memory stability

### M01 Offline editing aur reconnect
Kahan: My Pantry, Restock aur Profile.
Test: Test account ka data load karein; internet band karein; supported local edits try karein. Internet wapas karke reopen karein.
Pass: Unsupported action clear error de; successful local edit silently lost na ho; reconnect par duplicates ya doosre household ka data na aaye. Cloud persistence alag verify karein.

### M02 Repeated navigation
Kahan: Home > My Pantry > Chef Chat > Restock > Profile.
Test: Yeh cycle 20 martaba karein, phir recipe details aur edit forms khol kar band karein.
Pass: App crash, black screen, increasing lag ya repeated network requests ka visible flood na ho; entered data theek rahe.

### M03 Repeated scans
Kahan: Fridge, receipt, meal aur expiry scanners.
Test: Har scanner 5 martaba kholein; gallery photo dein; review se Back karein. Aakhir mein ek fresh scan karein.
Pass: Camera busy na rahe, previous photo new result ban kar na aaye, scan time lagatar barhta na jaye aur accidental saves na hon.

### M04 Background aur cold restart
Kahan: Item edit, recipe details, chat aur active cooking session.
Test: Unsaved aur saved changes alag note karein. App 2 minute background mein rakhein. Phir close karke cold launch karein.
Pass: Saved data retained ho; unsaved form aur active session ka restore ya reset behavior consistent ho. Jis screen ka restore supported nahi us ko data persistence ke pass mein include na karein.

### M05 Slow network aur retry
Kahan: Recipe creator, Chef Chat aur scanners.
Test: Request ke dauran network off karein; Back karein; reconnect ke baad retry karein.
Pass: Loader finish ya timeout ho; disposed screen error na aaye; old response nayi screen ka data overwrite na kare; retry se duplicate entries na banein.

### M06 Android memory reading
Kahan: Developer machine ka PowerShell aur connected Android phone.
Test: Fresh launch ke baad adb shell dumpsys meminfo com.enterprise.culinaryAI run karke TOTAL PSS note karein. M02 aur M03 ke baad, phir 60 second idle ke baad reading lein. Teen cycles repeat karein.
Pass: Crash ya out-of-memory na ho; idle readings har cycle mein be-hadd na barhein. Sirf ek PSS reading se memory leak prove ya disprove nahi hota; persistent growth ko investigate karein.

### M07 Permission recovery
Kahan: Android Settings > Apps > Culinary AI > Permissions.
Test: Camera aur microphone deny karke related feature kholein; phir permissions allow karke retry karein.
Pass: Denial par crash ya endless spinner na ho; allow ke baad feature recover ho. App sirf relevant feature par permission maange.

<!-- page -->
## Result sheet aur release decision

Har test ID ke saamne apna actual result likhein. Sab rows shuru mein NOT RUN hain; pehle se PASS assume na karein.

| Module | Case IDs | Result | Notes |
| --- | --- | --- | --- |
| Account aur household | A01 to A07 | NOT RUN | |
| Pantry aur expiry | P01 to P07 | NOT RUN | |
| Scanners | S01 to S07 | NOT RUN | |
| Recipes aur goals | R01 to R07 | NOT RUN | |
| Cooking aur Chef Chat | C01 to C07 | NOT RUN | |
| Restock aur screens | L01 to L07 | NOT RUN | |
| Offline aur memory | M01 to M07 | NOT RUN | |

## Bug record ka format

Test ID aur title:

App build aur test date:

Phone aur Android version:

Account ya household alias:

Exact steps jo aap ne kiye:

Expected result aur actual result:

Repeat hota hai ya kabhi kabhi:

Screenshot ya screen recording ka naam:

## Kab module ko pass kehna hai

Related cases phone par pass hon, saved data reopen ke baad sahi ho, aur us module ki koi unresolved critical failure na ho. BLOCKED aur NOT RUN ko PASS mein count na karein. Hosted backend deployment ke baghair online recipe discovery aur advanced cooking assistance ko fully working mark na karein.

Expiry OCR, non-food meal handling, speech recognition aur household cross-device behavior priority retests hain. Purchasing automation is guide ke scope se bahar hai; koi real order is checklist ke liye place karna zaroori nahi. Pehle testing mein merchant cart mein temporary products add hue the; agle real checkout se pehle unhein review aur remove karein.

Code evidence: lib/screens, lib/services, Flutter test suite, backend/tests aur docs/RELEASE_READINESS.md. Yeh report practical acceptance checklist hai; automated tests aur manually observed results ko alag rakhti hai.
