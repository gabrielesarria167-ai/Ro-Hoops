# RoHoops — Movement References

Real-world references behind every movement in the game, collected in October 2026 to make the procedural animation look natural: the ball path, the feet and the posture. The plan that uses them is the movement-naturalness pass (see the PR or commit that adds this file).

## How to read this

**Tags on every number**
- **[M]** measured in a study
- **[C]** coaching consensus
- **[D]** derived with physics or geometry from the sources
- **[E]** an animation estimate where no source measured the value

**Units.** H = standing body height. Joint flexion is in degrees from straight (0° = straight).

**Converting to the R15 rig.** Body ≈ 5 studs, standing HipRootPart centre ≈ 3.0 studs, hip joints ≈ 2.0, knees ≈ 1.0–1.1, shoulders ≈ 3.9, top of the head ≈ 5.2. The hip-to-ankle leg is ≈ 1.6 studs. Roblox legs are short (32% of height against ~46% in a person), so a fraction of H can't be multiplied by 5 directly. Use these rules:

| Real measure | Rig rule | Example |
|---|---|---|
| Height **below the hips** (fraction f of H, f < 0.53) | f ÷ 0.53 × 2.0 studs | knee 0.285 H → 1.08 studs |
| Height **above the hips** | 2.0 + (f − 0.53) × 6.8 studs | shoulder 0.82 H → 3.97 studs |
| Foot spacing, step length, hip drop | × 3.4 studs per H (scaled by the leg) | 0.1 H step → 0.34 stud |
| Hand / upper-body reach | × 5 studs per H | 0.1 H → 0.5 stud |

**Gaps.** The research hit a session web-search cap of 200 calls, so some pages were read from search snippets (marked "snippet" or "desc" in the source reports). Some numbers have no measured source:
- crossover phase timing, spin duration and step-back flight time ([D]/[E] only);
- fadeaway trunk angle in degrees, step-back and side-step distances ([E]);
- pull-up gather kinematics (one thesis abstract) and floater numbers (qualitative only).

Check these against slow-motion video before treating them as fact.

---

## Shared studies (cited across many movements)

- Hirata, Sawamura, Ae & Kobayashi 2011, "Comparison of the hand-dribbling motion between skilled and unskilled subjects", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/4779
- Li, Rupčić & Knjaz 2021, "The effect of fatigue on kinematics and kinetics of basketball dribbling with changes of direction", *Kinesiology* 53(2) — https://ojs.srce.hr/kinesiology/article/view/17087
- Liu & Hodgins 2018, "Learning Basketball Dribbling Skills Using Trajectory Optimization and Deep RL", ACM TOG — http://libliu.info/Basketball/Basketball.pdf
- Okazaki & Rodacki 2012, J Sports Sci Med 11:231 — https://www.jssm.org/jssm-11-231.xml-Fulltext
- Podmenik, Supej, Debevec & Erčulj 2021, "Common Movement Patterns of the Jump Shot while Increasing the Distance", J Hum Kinet 78 — https://johk.pl/wp-content/uploads/2023/04/10078-78-2021-v78-2021-03.pdf
- Miller & Bartlett 1993, "The effects of increased distance on basketball shooting kinematics", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/2817
- Chang, Cesario-Ketchum & Hsieh 2012, "The effects of fatigue during the take-off phase of a basketball lay-up", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/5325/4896
- Vaverka et al. 2016, "Effect of an arm swing on countermovement vertical jump performance", J Hum Kinet — https://pmc.ncbi.nlm.nih.gov/articles/PMC5260575/

---

## 1. Dribbling stance (the base posture)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Stance width (foot centres) | 0.22–0.28 H | 1.4–1.6 studs | [C] |
| Toe-out | 5–15° | same | [C] |
| Stagger (neutral / protecting) | 0–0.05 H / 0.15–0.25 H ball-side foot back | 0–0.15 / 0.5–0.85 stud | [C] |
| Knee flexion (idle / low pound) | 30–40° / 50–65° | crouch ≈ 0.12–0.2 / 0.3–0.45 stud | [M]+[D] |
| Pelvis drop from standing | 4–6% H idle, 8–12% H low | 0.14–0.2 / 0.27–0.4 stud | [M] Li |
| Trunk forward lean (from the hips, back straight) | 20–30° idle, 30–40° low | same | [C]+[D] |
| Neck extension (keeps the gaze level) | 15–30° | same | [D] |
| Off arm (arm bar) | upper arm ~45° forward/out, elbow ~90°, forearm across at waist–chest, 20–35 cm in front | palm ≈ 2.6–3.4 studs up, ~1.0–1.6 forward | [C] |
| Ball catch / release height | 0.40–0.45 H / 0.32–0.36 H | ≈ 1.5–1.7 / 1.2–1.35 studs | [M] Hirata |
| Hand contact per bounce | 0.39 s skilled (0.28 s unskilled) | — | [M] |
| Bounce rate | 1.5–2 Hz relaxed, ~3 Hz low pound | — | [D]+[M] Liu 0.75 s cycle |
| Ball landing spot | 0.10–0.15 H outside the ball-side foot, level with the toes to slightly behind | ≈ 0.35–0.5 stud outside the foot | [C] |
| Ball restitution | e ≈ 0.85 | — | [M] FIBA |

**The dribble cycle.** The hand meets the ball while it is still rising, rides it up 3–6 cm, then pushes it down (the elbow extends and the wrist snaps 10–20°). The hand waits low; it doesn't fly back up to the hip. The knees dip 1–2 cm in time with the push.

**Mistakes to avoid**
- slapping the ball at the top of its bounce;
- a rounded back, or eyes looking down at the ball;
- the ball bouncing in front of the toes;
- a dead off arm;
- a perfectly regular rhythm (add about ±10% jitter).

**References**
1. Hirata et al. 2011 (ISBS) — https://ojs.ub.uni-konstanz.de/cpa/article/view/4779
2. Katsuhara et al. 2010, "Spatiotemporal characteristics of rhythmic, stationary basketball bouncing", Perceptual and Motor Skills 110:469–478 (cited in Hirata)
3. Fujii, Yamada & Oda 2010, "Skilled basketball players rotate their shoulders more during running while dribbling" — https://journals.sagepub.com/doi/abs/10.2466/pms.110.3.983-994
4. Li, Rupčić & Knjaz 2021, *Kinesiology* 53(2) — https://ojs.srce.hr/kinesiology/article/view/17087
5. Basketball For Coaches, "How to Dribble a Basketball (7-Step Guide)" — https://www.basketballforcoaches.com/how-to-dribble-a-basketball/
6. Breakthrough Basketball, "7 Common Traits in Elite Level Dribbling" (snippet) — https://www.breakthroughbasketball.com/fundamentals/dribbling-traits
7. KFUPM PE, "Basketball skills" — https://faculty.kfupm.edu.sa/PE/abuhilal/basketball_skills.html
8. HoopStudent, "Basketball dribbling basics" — https://hoopstudent.com/basketball-dribbling-basics
9. HoopStudent, "Athletic stance" — https://hoopstudent.com/basketball-athletic-stance
10. Jr. NBA, "How to Dribble a Basketball" — https://jr.nba.com/how-to-dribble-a-basketball
11. UBC KIN366 wiki, "Dribbling" — https://wiki.ubc.ca/Course:KIN366/ConceptLibrary/Dribbling
12. Coaches Clipboard, "Dribbling" — https://www.coachesclipboard.net/Dribbling.html
13. UVic, "Demonstration of Control and Speed Dribble" — https://web.uvic.ca/~thopper/Unitplan452/invasion2000/Steph%20&%20Chris/Gametasks/DemoDribble.html
14. Special Olympics, Dribbling Faults and Fixes chart — https://specialolympicswisconsin.org/wp-content/uploads/2024/10/Dribbling-Faults-and-Fixes-Chart.pdf
15. US Sports Camps (Pisapia), "Ball handling: staying low" — https://www.ussportscamps.com/tips/basketball/ball-handling-staying-low
16. Active.com, "The Basic Shuffle Dribble" — https://www.active.com/basketball/articles/the-basic-shuffle-dribble-2
17. Altavilla, Di Tore, D'Isanto & Raiola 2017, "Some teaching method elements of the basketball dribble" — https://iris.unicas.it/retrieve/de2a6153-e48d-86a2-e053-1705fe0a3017/Altavilla%20et%20al%20Some%20teaching%20method%20elements%20of%20the%20basketball%20dribble.pdf
18. Aussie Hoops Rookie Drills (snippet) — https://beachcombersbasketball.club/wp-content/uploads/2024/07/Aussie-Hoops-Rookie-Drills.pdf
19. Sports Camps Canada, "Three important ways to dribble" — https://www.sportscampscanada.com/training-tips/three-important-ways-to-dribble-for-pro-level-ball-handling
20. Wikipedia, "Dribble" — https://en.wikipedia.org/wiki/Dribble
21. ILoveBasketballTV, beginner dribbling tutorial — https://youtube.com/watch?v=k4yuKrQKNUY
22. ILoveBasketballTV, ball-handling workout — https://youtube.com/watch?v=2Wuo3RfnO2M
23. Hoelzemann et al. 2023, "Hang-Time HAR" — https://arxiv.org/pdf/2305.13124
24. Paul Fabritz via Exercise.com (snippet) — https://www.exercise.com/blog/step-up-your-ball-handling-game-with-these-3-easy-tips-from-paul-fabritz/
25. CoachTube, "Ball Handling the Right Way – pound dribble stops" (snippet) — https://coachtube.com/course_lesson/ball-handling-the-right-way/pound-dribble-stops/2280367
26. Mojo, "What is the triple-threat position?" — https://mojo.sport/coachs-corner/what-is-the-triple-threat-position/
27. FIBA ball-bounce spec (Illustrative Mathematics) — https://tasks.illustrativemathematics.org/content-standards/tasks/347
28. Basketball For Coaches, "Defensive stance" — https://www.basketballforcoaches.com/defensive-stance/
29. Adolescent directional dribbling study (ResearchGate 388922834) — https://www.researchgate.net/publication/388922834_The_biomechanical_characteristics_and_training_suggestions_of_adolescent_basketball_players'_directional_dribbling_movements
30. Coaches Clipboard, Footwork — https://www.coachesclipboard.net/Footwork.html
31. Schepers et al. 2025, "What makes a dribble successful?" (method only) — https://arxiv.org/abs/2506.22503

## 2. Side shuffle while dribbling

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Foot order | lead foot lifts and lands first, trail foot slides in 80–150 ms later; feet never cross | — | [C]+[D] |
| Base width → reach | 0.28–0.35 H → 0.40–0.45 H | 1.4 → ~2.0 studs | [C]+[D] |
| Lead step per cycle | ≤ 0.25 H | ≤ 0.85 stud | [C] |
| Base opens and closes | lead foot steps out, trail foot "brought up close" as soon as it lands; never crossing or clicking | lead +0.3 stud wider, trail −0.3 stud narrower (`SHUFFLE_LEAD_OUT` / `SHUFFLE_TRAIL_IN`) | [C] (refs 25, 26) |
| Hips | low and square; thighs ~45° to the court | +0.1 stud extra crouch while shuffling (`SHUFFLE_CROUCH`) | [C] (refs 25, 26) |
| Ball height | no higher than the knees; hand midway between front and rear foot | catch ≈ 1.25 studs (`DRIBBLE_SHUFFLE_CATCH_HEIGHT`) | [C] (ref 25) |
| Foot clearance | 2–5 cm | 0.05–0.1 stud | [C] |
| Shuffle cycle (lead + trail) | 0.30–0.40 s at game speed, 0.45–0.6 s casual | — | [D] |
| Hip height bob | ≤ 2–4% H | ≤ 0.07–0.14 stud | [M] Koyama |
| Trunk | 20–35° forward, held constant; shoulders level | — | [M]+[C] |
| Dribble | one bounce per shuffle cycle; the floor contact lands with the lead foot | — | [C]+[D] |
| Ball lead in the direction of travel | ≈ 0.1 H | ≈ 0.5 stud | [D] |

**Mistakes to avoid**
- hops where the hips bob more than 5% H;
- a skating motion with both feet moving together;
- the trail foot moving first;
- the trunk rolling side to side;
- the dribble not locked to the steps.

**References**
1. Koyama et al. 2015, "Kinematics of side-step motion in basketball players", Tokai J Sports Med Sci 27 — https://www.u-tokai.ac.jp/uploads/2024/02/2015p021-1.pdf
2. Takayama 2015, side-step hip/knee 30°/30° — https://cir.nii.ac.jp/crid/1050288789739773952?lang=en
3. Han, Lee, Park & Park 2026, "Sex differences in biomechanical deceleration strategies during a side shuffle step" — https://kjss.sports.re.kr/assets/pdf/1084/journal-37-2-367.pdf
4. Petway et al. 2026, "Influence of maximal linear deceleration on lateral deceleration and shuffle performance" — https://knowledge.lancashire.ac.uk/id/eprint/58750/
5. Chang, Chang & Li 2008, "Ground reaction force analysis for different feet position in basketball defensive-shuffle", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/1981
6. Active.com, "The Basic Shuffle Dribble" — https://www.active.com/basketball/articles/the-basic-shuffle-dribble-2
7. Active.com, "Step Slides" — https://www.active.com/basketball/articles/step-slides
8. Coaches Clipboard Newsletter #318 — https://www.coachesclipboard.net/newsletters/CCNewsLetter05212025.html
9. Coaches Clipboard, Z-Drill — https://www.coachesclipboard.net/DefenseZDrill.html
10. Breakthrough Basketball, "Why you should NOT step slide on defense" (snippet) — https://www.breakthroughbasketball.com/defense/step-slide
11. "10 Week Defensive Program" (Scribd, snippet) — https://www.scribd.com/document/53049956/10-Week-Defensive-Program
12. UVic, "Defensive Sliding" — https://web.uvic.ca/~thopper/tactic/Units/KateCourtney/Gametasks/sliding.html
13. Basketball Manitoba, "Key Slides" — https://www.basketballmanitoba.ca/2017/12/drill-key-slides.html
14. Basketball Manitoba, "Zig Zags" — https://www.basketballmanitoba.ca/2018/03/drill-zig-zags.html
15. Altavilla et al. 2017 — https://iris.unicas.it/retrieve/de2a6153-e48d-86a2-e053-1705fe0a3017/Altavilla%20et%20al%20Some%20teaching%20method%20elements%20of%20the%20basketball%20dribble.pdf
16. Hashizume, Ae & Takenaka, "Biomechanical study on a basketball dribble with a cutting motion", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/6030
17. Special Olympics Faults & Fixes ("Dribble and Slide") — https://specialolympicswisconsin.org/wp-content/uploads/2024/10/Dribbling-Faults-and-Fixes-Chart.pdf
18. FastModel Sports, "C2E Lateral Slide/Sprint/Slide … Dribble" — https://playbank.fastmodelsports.com/library/basketball/fastdraw/56278/play-C2E-Lateral-Slide-Sprint-Slide-Grab-Dribble-Shoot-Drill
19. Zhu et al. 2024, *Sensors* (snippet) — https://doaj.org/article/94ea47a29dee42fc9857f3f17629a909
20. Inaba et al., JSSF abstract (snippet) — https://www.shobix.co.jp/jssf/contents/supplement/files/P-067.pdf
21. ILoveBasketballTV tutorial — https://youtube.com/watch?v=k4yuKrQKNUY
22. Sasaki et al. 2011, "Relationship between performance and trunk movement during change of direction", JSSM 10 — https://www.jssm.org/jssm-10-112.xml
23. SimpliFaster, "Deconstructing performance training: basketball defense" — https://simplifaster.com/articles/deconstructing-preformance-training-basketball-defense/
24. Calgary SHRed, side shuffles — https://ucalgary.ca/shred-injuries/all-sports/volleyball/side-shuffles

Added 2026-10-22 (base that opens and closes, low hips, low ball):

25. Active.com, "The Basic Shuffle Dribble" (re-read in full): front foot slides out "with almost no space between the floor and the foot", then the rear foot is brought "up close to the front foot"; thighs "at a forty-five degree angle to the court"; shoulders level ("a full glass of water"); dribble hand "roughly midway between your front foot and your rear foot", ball "no higher than your knees"; free arm out ~45° and bent 90° as a shield — https://www.active.com/basketball/articles/the-basic-shuffle-dribble-2
26. Coaches Insider, "5 drills to improve your lateral quickness": "keeping your hips low and square", move the feet "smoothly", "Your feet should never cross!" — https://coachesinsider.com/mens-basketball/5-drills-to-improve-your-lateral-quickness-for-basketball-article/
27. OPEN Phys Ed, Basketball skill cue cards (snippet): defensive slide = "lead foot step", "push and shuffle with the trail leg", "fast, explosive feet" — https://openphysed.org/wp-content/uploads/2019/01/M-12-07-Basketball-SkillCueCards.pdf
28. VertiMax, basketball dribbling drills: lateral dribble out and back to cones, left to right — https://vertimax.com/blog/basketball-dribbling-drills

## 3. Backpedal (retreat dribble)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Body facing | side-on, 45–90° from the defender (in RoHoops the body faces the rim, so use a partial turn) | — | [C] |
| Foot pattern | push-step: the rear foot reaches back on a diagonal, then the front foot pushes and slides back; the feet never cross | — | [C] |
| Step length | 0.2–0.3 H | 0.7–1.0 stud | [D] |
| Foot contact | toes/forefoot first, then the heel | foot pitched toes-down on landing | [M] Threlkeld via Arata |
| Leg motion | smaller hip/knee swing than a forward run (hip 42° vs 63°, knee 83° vs 119°), higher cadence | — | [M] |
| Trunk | keeps the 20–35° forward hinge, never leans back | — | [C] |
| Ball | beside or just behind the rear hip/knee, 0.28–0.40 H high, pushed 10–20° backward | ≈ 1.05–1.5 studs | [C]+[D] |
| Rhythm | one bounce per push-step (~2–2.5 Hz) | — | [C] |

**References**
1. HoopStudent, "Escape (retreat) dribble" — https://hoopstudent.com/basketball-escape-dribble/
2. FastModel Sports, "3 Up 2 Back" — https://playbank.fastmodelsports.com/library/basketball/fastdraw/386705/play-3-Up--2-Back
3. FastModel Sports, "Box Ball Handling" (snippet) — https://fastmodelsports.com/library/basketball/fastdraw/251857/play-Box-Ball-Handling
4. Altavilla et al. 2017 — https://iris.unicas.it/retrieve/de2a6153-e48d-86a2-e053-1705fe0a3017/Altavilla%20et%20al%20Some%20teaching%20method%20elements%20of%20the%20basketball%20dribble.pdf
5. Coaches Clipboard, "Dribbling" (back-up dribble) — https://www.coachesclipboard.net/Dribbling.html
6. Coaches Clipboard, Z-Drill — https://www.coachesclipboard.net/DefenseZDrill.html
7. Coaches Clipboard Newsletter #318 — https://www.coachesclipboard.net/newsletters/CCNewsLetter05212025.html
8. Breakthrough Basketball, "Duke jerk back" (snippet) — https://www.breakthroughbasketball.com/fundamentals/duke-jerk-back
9. Scribd ball-handling handout (snippet) — https://www.scribd.com/document/671978949/Ballhandling
10. Special Olympics, Sports Essentials Basketball Drills 2024 — https://media.specialolympics.org/resources/sports-essentials/coaching-guides/Sports-Essentials-Basketball-Drills-2024-English.pdf
11. Jr. Jazz Basketball Clinics outline (snippet) — https://www.lehi-ut.gov/wp-content/uploads/2013/09/Jr.-Jazz-Basketball-Clinics.pdf
12. Arata, University of Oregon backward-running pages — https://pages.uoregon.edu/btbates/backward/alan2.htm (also https://darkwing.uoregon.edu/~btbates/backward/alan.htm)
13. Sodeyama et al. 2005, "Characteristics of backward walking and backward running in primary school children", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/1114
14. Devita & Stribling 1991; Vilensky 1987 (cited in Arata) — https://pages.uoregon.edu/btbates/backward/alan2.htm
15. Dr. Dish, "Duke Drive and Retreat" — https://blog.drdishbasketball.com/duke-team-shooting-drill-drive-and-retreat
16. ThePEDept, "Retreat Dribble Pressure Practice" — https://thepedept.com/activities/retreat-dribble-pressure-practice
17. Tanjungpura J Coaching Research 2023, retreat dribble + zig-zag training — https://doaj.org/article/a80c0f7da3e843b5b7314cf82942fb2c
18. Basketball For Coaches, "How to dribble" — https://www.basketballforcoaches.com/how-to-dribble-a-basketball/
19. UGA open textbook, "Fundamentals – dribbling" (snippet) — https://open.online.uga.edu/basketball/chapter/fundamentals-dribbling/
20. Special Olympics Faults & Fixes — https://specialolympicswisconsin.org/wp-content/uploads/2024/10/Dribbling-Faults-and-Fixes-Chart.pdf
21. Li et al. 2021, *Kinesiology* — https://ojs.srce.hr/kinesiology/article/view/17087
22. Hashizume et al., ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/6030
23. SimpliFaster, backpedal training — https://simplifaster.com/articles/backpedal-training-athletic-performance/
24. Basketball HQ, resistance-band retreat dribble — https://basketballhq.com/resistance-band-retreat-dribble-basketball-drill/amp

## 4. Running (speed) dribble

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Catch / release height | 0.40–0.55 H (rising with speed) / ~0.33 H | ≈ 1.5–2.1 / ≈ 1.25 studs | [M] Hirata + [C] |
| Hand contact | 0.39 s, ~60% of the cycle | — | [M] |
| Cycle | 0.6 s per bounce | — | [M] Liu |
| Bounces per stride | 1 per stride (2 steps) at a run | — | [M] |
| Footfall sync (right hand) | catch during left-foot stance at the body's low point; push and release during right stance | — | [M]+[D] |
| Ball lead | 0.3–0.5 H ahead of the lead foot, 0.1–0.15 H outside the dribble-side foot | ≈ 1.0–1.7 ahead, 0.35–0.5 out | [C]+[E] |
| Apex drift | up to 0.11 H between cycles (add noise) | ≈ 0.4 stud | [M] Liu |
| Trunk / shoulders | 12–20° forward; upper body twists ±15–25° in time with the arm | — | [M]+[E] |
| Off arm | swings opposite the legs as in a normal run (no arm bar) | — | [M] Liu |

**References**
1. Hirata et al. 2011 (ISBS) — https://ojs.ub.uni-konstanz.de/cpa/article/view/4779
2. Fujii, Yamada & Oda 2010 — https://lida.sport-iat.de/ta/Record/4020283?lng=en (also https://journals.sagepub.com/doi/abs/10.2466/pms.110.3.983-994)
3. Imai 2017, "Biomechanical study on the dribbling sprint motion" — https://sanotan.repo.nii.ac.jp/records/107
4. Liu & Hodgins 2018 — http://libliu.info/Basketball/Basketball.pdf
5. Conte, Scanlan & Dalbo 2020, "Dribble Deficit", Biology of Sport — https://termedia.pl/doi_ft/10.5114/biolsport.2020.95637
6. Hang-Time HAR — https://arxiv.org/pdf/2305.13124
7. Coaches Clipboard, "Dribbling" — https://www.coachesclipboard.net/Dribbling.html
8. Sportplan, "Dribbling at Speed" — https://www.sportplan.net/drills/Basketball/sessionPlans/Dribbling-at-Speed-9299679.jsp
9. Sikana, "Learn different kinds of dribble" — https://www.sikana.tv/en/sport/learn-to-play-basketball/learn-different-kinds-of-dribble
10. UVic, "Demonstration of Control and Speed Dribble" — https://web.uvic.ca/~thopper/Unitplan452/invasion2000/Steph%20&%20Chris/Gametasks/DemoDribble.html
11. Breakthrough Basketball speed-dribble tips (snippet) — https://www.breakthroughbasketball.com/qa/q1015 and https://www.breakthroughbasketball.com/drills/speed-dribble-relay-race.html
12. Breakthrough Basketball, "The Coach K Speed Dribble" (snippet) — https://www.breakthroughbasketball.com/issue022823
13. Breakthrough Basketball, 1-on-1 speed dribble drill (snippet) — https://www.breakthroughbasketball.com/drills/1on1speeddribble
14. HoopStudent, "Basketball speed dribble" — https://hoopstudent.com/basketball-speed-dribble/
15. Special Olympics, Sports Essentials Basketball Drills 2024 — https://media.specialolympics.org/resources/sports-essentials/coaching-guides/Sports-Essentials-Basketball-Drills-2024-English.pdf
16. Sport Wales, "Dribbling Hands" — https://citbag.sport.wales/wp-content/uploads/2022/03/Dribbling-Hands.pdf
17. KFUPM basketball skills — https://faculty.kfupm.edu.sa/PE/abuhilal/basketball_skills.html
18. Top End Sports, coefficient of restitution — https://topendsports.com/biomechanics/coefficient-of-restitution.htm
19. US Sports Camps, "Changing pace while dribbling" — https://www.ussportscamps.com/tips/basketball/changing-pace-while-dribbling
20. Believe Basketball, "Fast Paced Dribbling Basics" — https://www.youtube.com/watch?v=1zHF5uLAYZ4
21. Streetball Strategies, "Power & Speed Dribble Tutorial" — https://www.youtube.com/watch?v=faRTyk8CAIc
22. Get Handles, "5 Ways How To Dribble FASTER" — https://www.youtube.com/watch?v=39x3Q18FHks
23. THINCPRO, "Dribble with SPEED and CONTROL" — https://www.youtube.com/watch?v=GUNEv7qahVo
24. Special Olympics Michigan, "Basketball Speed Dribble tutorial" — https://www.youtube.com/watch?v=SKFKY-HB58o
25. Clip Studio Tips, dribble animation — https://tips.clip-studio.com/en-us/articles/4970
26. Game Developer, "DeepDribble: Simulating Basketball with AI" — https://www.gamedeveloper.com/disciplines/deepdribble-simulating-basketball-with-ai

## 5. Hand switch (H) / low crossover in place

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Ball height | below the knee, ≤ 0.25 H (tight: shin, 0.15–0.2 H) | ≤ 0.95 stud (0.55–0.75) | [C] |
| Bounce point | on the body's centre line, 0.05–0.15 H in front of the toes; a "V" path | 0.25–0.75 stud ahead | [C]+[E] |
| Hand-to-hand travel | 0.35–0.45 H | ≈ 1.2–1.5 studs | [E] |
| Ball flight, release → catch | 0.15–0.2 s (0.12–0.24) | — | [D] |
| Each hand's contact | 0.15–0.25 s | — | [E] |
| Sending hand | on the upper-outside quarter of the ball, whipping it inward | — | [C] |
| Receiving hand | waits low beside the opposite hip, meets the ball on the rise, gives 0.03–0.05 H toward the "hip pocket" | — | [C]+[D] |
| Body | hips square; shoulders roll ~5–10° and twist ±10° with the ball; head still; 60/40 weight shift; feet stay planted | — | [E] |

**References**
1. Hirata et al. 2011 — https://ojs.ub.uni-konstanz.de/cpa/article/view/4779
2. Katsuhara et al. 2010, Perceptual and Motor Skills 110:469–478 (via Hirata)
3. Liu & Hodgins 2018 — http://libliu.info/Basketball/Basketball.pdf
4. HoopStudent, "Basketball crossover dribble" — https://hoopstudent.com/basketball-crossover-dribble/
5. Inspirational Basketball, "How to do a crossover" — https://inspirationalbasketball.com/how-to-do-a-crossover-dribble-in-basketball/
6. Inspirational Basketball, "V Dribbling Drill" — https://inspirationalbasketball.com/v-dribbling-drill/
7. T.J. Allan / STACK via Coaches Insider, "Develop an unstoppable crossover" — https://coachesinsider.com/mens-basketball/develop-an-unstoppable-crossover-dribble-with-just-3-drills-article/
8. Wootten & Wootten, *Coaching Basketball Successfully* (excerpt) — https://us.humankinetics.com/blogs/excerpt/stationary-moves-are-a-key-offensive-skill
9. Krause & Nelson, *Basketball Skills & Drills* (excerpt) — https://us.humankinetics.com/blogs/excerpt/moves-with-either-pivot-foot-advanced
10. Coaches Clipboard, "Dribbling" — https://www.coachesclipboard.net/Dribbling.html
11. KFUPM — https://faculty.kfupm.edu.sa/PE/abuhilal/basketball_skills.html
12. Basketball For Coaches, "How to do a crossover" — https://www.basketballforcoaches.com/crossover-basketball/
13. Hoops Basket, "The Crossover Dribble" — https://www.hoopsbasket.com/blogs/hoops-basketball/the-crossover-dribble
14. Gymaesthetics, "Mastering the Basketball Crossover" — https://www.gymaesthetics.com/blogs/sport-basketball/mastering-the-basketball-crossover-techniques-tips-and-benefits
15. DribbleUp, "In and Out crossover" — https://dribbleup.com/blog/learn-how-to-do-a-crossover-in-and-out-dribble
16. Jr. NBA MVP Practice Plans — https://jr.nba.com/basketball-practice-plans/mvp/page/4
17. MasterClass (Stephen Curry) (snippet) — https://www.masterclass.com/articles/stephen-curry-teaches-the-art-of-the-basketball-crossover-move
18. ILoveBasketballTV, "The Ultimate Guide to a SHIFTY Crossover" — https://www.youtube.com/watch?v=Sag6mu2aEkA
19. Get Handles, "How To Crossover For Beginners" — https://www.youtube.com/watch?v=I-_yRvGPkWU
20. SLAM/IMG Academy, "How To Perform a Low-Drop Crossover" — https://www.youtube.com/watch?v=OOt_96_GQmA
21. Get Handles, "3 EASY Crossover Moves" — https://www.youtube.com/watch?v=YDUt0jWrDSc
22. Ganon Baker, "23 Ways to Destroy Your Defender" (snippet) — https://www.udemy.com/course/23-ways-to-destroy-your-defender-basketball-coaching-program/
23. Hang-Time HAR — https://arxiv.org/pdf/2305.13124
24. Top End Sports / FIBA restitution — https://topendsports.com/biomechanics/coefficient-of-restitution.htm
25. Tuts+, "How to animate a bouncing ball" — https://photography.tutsplus.com/tutorials/animation-for-beginners-how-to-animate-a-bouncing-ball--cms-24787

## 6. Wide (Iverson-style) crossover

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Jab step | 0.15–0.3 H, diagonally forward and out (30–45°), never a flat sideways lunge (textbook jab ≈ 15 cm) | 0.5–1.0 stud | [C]+[M] Hashizume |
| Ball during the sell | 0.25–0.35 H out from the centre line, below the knee | ≈ 1.25–1.75 studs out, ≤ 1.05 high | [E] |
| Shoulder dip on the sell | trunk side-bend 15–25° toward the jab, plus 10–15° more forward | — | [E] |
| Head fake | 15–30° yaw toward the fake; snaps back 0.05–0.1 s before the ball crosses | — | [E] |
| Hesitation | 0.15–0.3 s | — | [E] |
| Cross | below the knee, 0.5–0.7 H wide, 0.15–0.22 s flight | — | [D] |
| Push-off | the jab foot pushes off as the ball crosses | — | [C] |
| Order of motion | head → shoulders → ball → push-off → step | — | [E] |

**References**
1. Basketball For Coaches, "Allen Iverson Crossover (Break Ankles in 3 Easy Steps)" — https://www.basketballforcoaches.com/?p=8732
2. Basketball For Coaches, "How to do a crossover" (Iverson variation) — https://www.basketballforcoaches.com/crossover-basketball/
3. Wikipedia, "Crossover dribble" — https://en.wikipedia.org/wiki/Crossover_dribble
4. ILoveBasketballTV, "The 4 Crossovers That Create INSTANT Separation" — https://www.youtube.com/watch?v=4BI0-6gP5mE
5. Tyler Relph's Hoop Dynamic, "IVERSON CROSSOVER – Skip Cross Tutorial" — https://www.youtube.com/watch?v=x26tSzy4kEk
6. Get Handles, "How to Allen Iverson Crossover Tutorial" — https://www.youtube.com/watch?v=zW3VgbqTo8M
7. Revenge Basketball, "How To Do The Allen Iverson Crossover (STEP-BY-STEP)" — https://www.youtube.com/watch?v=IBm4cjgY5X8
8. Believe Basketball, "The Allen Iverson Crossover | Complete breakdown" — https://www.youtube.com/watch?v=UX_IVk1cpkA
9. SuperHandles, "How to do the IVERSON CROSSOVER" — https://www.youtube.com/watch?v=e-y0D7MXntg
10. Basketball Coach Allen, "Allen Iverson Killer Crossover Tutorial" — https://www.youtube.com/watch?v=k05HSqV91EA
11. Hashizume, Ae & Takenaka, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/6030
12. Wootten & Wootten (Human Kinetics excerpt) — https://us.humankinetics.com/blogs/excerpt/stationary-moves-are-a-key-offensive-skill
13. Krause & Nelson (Human Kinetics excerpt) — https://us.humankinetics.com/blogs/excerpt/moves-with-either-pivot-foot-advanced
14. T.J. Allan / STACK (Coaches Insider) — https://coachesinsider.com/mens-basketball/develop-an-unstoppable-crossover-dribble-with-just-3-drills-article/
15. Huffman Basketball, "Cross jab" — https://huffmanbasketballtraining.substack.com/p/how-to-master-the-cross-jab-basketball
16. Sports Stars of Tomorrow, "Jab cross" — https://www.sportsstarsoftomorrow.tv/video/how-to-do-a-jab-cross-with-deron-rippey-jr-basketball-tip
17. Hoops Basket — https://www.hoopsbasket.com/blogs/hoops-basketball/the-crossover-dribble
18. Barry Popik, "UTEP Two-Step" — https://barrypopik.com/blog/utep_two_step_basketball_dribble
19. SportsEdTV, "Tim Hardaway Breaks Down… Killer Crossover" — https://www.youtube.com/watch?v=o5noGn9raWg
20. FIBA Basketball, "Tim Hardaway's Killer Crossover Masterclass" — https://www.youtube.com/watch?v=CfuqG37Fd2Y
21. Get Handles, "How To Tim Hardaway Crossover (UTEP 2 Step)" — https://www.youtube.com/watch?v=sw4iBZQabA4
22. HoopStudent crossover — https://hoopstudent.com/basketball-crossover-dribble/
23. US Sports Camps — https://www.ussportscamps.com/tips/basketball/changing-pace-while-dribbling
24. Jr. NBA MVP — https://jr.nba.com/basketball-practice-plans/mvp/page/4
25. Liu & Hodgins 2018 — http://libliu.info/Basketball/Basketball.pdf
26. ILoveBasketballTV, "3 Elite Combo Moves" — https://www.youtube.com/watch?v=6jdyzKk8AVE
27. Pro Training Basketball, "Cross jab / Tim Hardaway Killer Crossover" — https://www.youtube.com/watch?v=SfcMGcl_MCk
28. Sportskeeda, "Allen Iverson crosses over and fades" (snippet) — https://www.sportskeeda.com/basketball/basketball-moves-breakdown-allen-iverson-crosses-over-and-fades

## 7. Stab dribble (ball-side push-pull, mirror of the in-and-out)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Step | ball-side foot, 0.10–0.20 H, 30–45° out from straight ahead | 0.35–0.7 stud | [E] |
| Sync | the bounce and the jab foot landing within 1–2 frames | — | [C] |
| Bounce point | 0.20–0.25 H out from the centre line, 0.10–0.15 H in front of the toes, just outside the jab foot | ≈ 1.0–1.25 studs out (within reach) | [E] |
| Ball height | knee or below at the bounce; hand receives at 0.35–0.45 H | ≤ 1.05; 1.3–1.7 | [C] |
| Hand | inside-top → over the top → outside-top; never under the ball; wrist ~390°/s | — | [C]+[M] Li |
| Rhythm | slower "sold" push, fast pull-back; ~0.6–0.8 s total | — | [C]+[E] |
| Body | pelvis 0.41–0.44 H (≈ 0.3–0.4 stud drop); knee ~60°; shoulder dips toward the stab; head tilts | — | [M]+[C] |

**References**
1. Breakthrough Basketball, "The In & Out Dribble Explained" (snippet) — https://www.breakthroughbasketball.com/training/in-and-out-move
2. Coach's Clipboard, Dribbling — https://www.coachesclipboard.net/Dribbling.html
3. Dick's Pro Tips, In-and-Out (snippet) — https://www.dickssportinggoods.com/protips/sports-and-activities/basketball/basketball-dribbling-the-in-and-out-dribble
4. DribbleUp, Crossover In-and-Out — https://dribbleup.com/blog/learn-how-to-do-a-crossover-in-and-out-dribble
5. Basketball for Coaches, Crossover — https://www.basketballforcoaches.com/crossover-basketball/
6. XbotGo, Crossover technique — https://xbotgo.com/blogs/knowledge/crossover-dribble
7. Online-Basketball-Drills, In/Out with Crossover — https://www.online-basketball-drills.com/in-out-with-crossover-drill
8. Wikipedia, Basketball moves — https://en.wikipedia.org/wiki/Basketball_moves
9. Wikipedia, Crossover dribble — https://en.wikipedia.org/wiki/Crossover_dribble
10. Dr. Dish, "In and Out Shift with Ryan Razooky" (snippet) — https://blog.drdishbasketball.com/ball-handling-drills-in-and-out-shift-with-ryan-razooky
11. Hooptactics, player fundamentals (snippet) — https://hooptactics.net/premium/player/offskilldevelopment/playerofffunds.php
12. Hudl/InStat glossary, Dribble moves — https://instatglossary.hudl.com/basketball/events/dribble-moves/
13. Inspirational Basketball, Jab step — https://inspirationalbasketball.com/jab-step-basketball-shooting-drill/
14. MasterClass, Jab step guide (snippet) — https://www.masterclass.com/articles/jab-step-guide
15. Li et al. 2021, *Kinesiology* — https://ojs.srce.hr/kinesiology/article/view/17087
16. ISBS, "Biomechanical study on a basketball dribble with a cutting motion" — https://ojs.ub.uni-konstanz.de/cpa/article/view/6030/5511
17. "Dribble Accuracy & Arm Coordination", IJERPH 2023 — https://pmc.ncbi.nlm.nih.gov/articles/PMC10218343/
18. Sports Reflector, ball handling (snippet) — https://sportsreflector.com/blog/basketball-dribbling-ball-handling-mastery
19. IMG Academy / Vince Walden, "How To Perform An In-And-Out Dribble" — https://www.youtube.com/watch?v=0Yzz0u9p5yM (also https://slamonline.com/?p=429119)
20. Jr. NBA / Megan Griffith, "Stationary In & Out Drill" — https://www.youtube.com/watch?v=Fy3gNOuxHmw
21. "How to PERFECT the In & Out Dribble" — https://www.youtube.com/watch?v=8uq04FX4Q6Y
22. "In & Out + V Dribble – Ball Handling 101" — https://www.youtube.com/watch?v=WsTRB8CUcnE
23. "In & Out Dribble Breakdown (Unguardable Move)" — https://www.youtube.com/watch?v=ritQndurZVM
24. Revenge Basketball, "Master The In & Out Dribble Move" — https://www.youtube.com/watch?v=VsQZPvP6g-c ; https://www.youtube.com/watch?v=T40whUDs9Uk ; https://www.youtube.com/watch?v=rsus01blZNY

## 8. Step-back (dribble move)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Distance | ~6 ft of space (Harden, Second Spectrum tracking) | ≈ 4.6 studs (~4.5 ft for the 5'0" avatar; `STEPBACK_SPEED` × `STEPBACK_STEP_TIME` + slow-down), about Harden's 6 ft scaled to body height | [M] (ref 28) |
| Direction | ~45° back and away from the defender | 30° toward the ball side (`STEPBACK_ANGLE`) | [C] (ref 29) |
| Push foot | the lead (front) foot on the dribble-hand side | — | [C] |
| Landing | balanced, ball in the shooting pocket as the feet touch; then straight up for the shot. The game uses a one-foot bound (back foot first, front foot 0.12 s later), the user's choice over the drills' two-foot landing | back foot reaches 0.5 stud behind the stance | [C] (refs 29, 30) + play-test |
| Hop | off the front foot, the back foot taking the big hop; hips kept low ("drop your hips"), flight 0.15–0.22 s | hips rise ~0.25 stud | [C]+[D] (ref 29) |
| Trunk | 20–30° forward at the plant, 10–20° on landing; never leans back; shoulders turn 15–20° | — | [C] |
| Ball | a pound at the plant, snatched back on its front-top, bounces between the feet on the side away from the defender, slightly toward the lead foot | — | [C] |

**References**
1. ClutchPoints, "Harden's deadly stepback" — https://clutchpoints.com/nba/houston-rockets/james-harden-deadly-stepback-makes-him-the-best-offensive-player-in-nba
2. The Ringer, "The NBA's Electric Slide" — https://www.theringer.com/2019/03/05/nba/james-harden-side-step-houston-rockets
3. adidas, "How to do the James Harden step back" (snippet) — https://www.adidas.com/us/blog/create-space-instantly-how-to-do-the-james-harden-step-back
4. FIBA WABC manual, "Step back move off the dribble" (snippet) — https://wabc.fiba.com/manual/level-2/l2-player/2-offensive-basketball-skills/2-4-dribbling/2-4-4-advanced-dribbling-step-back-move-off-the-dribble/
5. Breakthrough Basketball, "5 Step Back Moves" (snippet) — https://www.breakthroughbasketball.com/training/5-step-back-moves
6. Hoops Basketball, "The Step-Back Jumpshot" — https://www.hoopsbasket.com/blogs/hoops-basketball/the-step-back-jumpshot
7. Baller Boot Camp, step-back jumper — https://ballerbootcamp.com/how-to-step-back-jumper/
8. LevelUp Basket, Step Backs — https://www.levelupbasket.com/basketball-drills/shooting-drills/step-backs
9. HoopsKing, "What is a step back" — https://hoopsking.com/blogs/default-blog/what-is-a-step-back-in-basketball-a-guide-to-the-move
10. Basketball Fundamentals, step-back like Dončić — https://basketballfundamentals.com/how-to-master-the-step-back-jumper-create-space-and-score-like-luka-doncic-2/
11. 143 Basketball Haven, Dončić breakdown (numbers unverified) — https://143basketballhaven.com/en/blog/luka-doncic-step-back-three-technical-breakdown
12. Sky Sports, Dončić step-back (snippet) — https://www.skysports.com/nba/news/36244/12007736/luka-doncics-step-back-jumper-howd-he-do-that
13. ESPN, Dončić isolation repertoire (snippet) — https://www.espn.com/nba/story/_/id/34822076/how-luka-doncic-built-nba-most-dangerous-isolation-repertoire
14. NBA Video Rulebook, "no push off by dribbler on step back" — https://videorulebook.nba.com/archive/legal-play-no-push-off-by-dribbler-on-step-back-2
15. Hudl glossary — https://instatglossary.hudl.com/basketball/events/dribble-moves/
16. Wikipedia, Basketball moves — https://en.wikipedia.org/wiki/Basketball_moves
17. Coach's Clipboard, Dribbling — https://www.coachesclipboard.net/Dribbling.html
18. HoopStudent, Escape dribble (snippet) — https://hoopstudent.com/basketball-escape-dribble/
19. Altavilla et al. (snippet) — https://iris.unicas.it/retrieve/de2a6153-e48d-86a2-e053-1705fe0a3017/Altavilla%20et%20al%20Some%20teaching%20method%20elements%20of%20the%20basketball%20dribble.pdf
20. Business Insider on Harden travel calls (snippet) — https://www.businessinsider.nl/nba-referee-james-harden-step-back-jumper-travel-basketball-zach-zarba-2018-4/
21. DeltiasGaming, NBA 2K26 stepback (snippet) — https://deltiasgaming.com/?p=344385
22. Practical Basketball (Roblox) guide — https://practicalbasketball.net/guides/dribble-moves
23. "The Perfect James Harden Step-back Tutorial" — https://www.youtube.com/watch?v=-CTGDhPV4S0
24. "How To: Stephen Curry Deadly Slide Step Back" — https://www.youtube.com/watch?v=8zxd3zJl68s
25. "Learn 3 Different Types of Step Back Moves with Jordan Lawley" — https://www.youtube.com/watch?v=GxDiMyN9LBE
26. "HOW TO – Punch Dribble Side Step FOOTWORK" — https://www.youtube.com/watch?v=Af9vRV-Qf0o
27. "3 Moves to Improve Your Stepback Jumper" — https://www.youtube.com/watch?v=Q41TgJNulYY ; also https://www.youtube.com/watch?v=vmgJHzwKsKo , https://www.youtube.com/watch?v=NDc8W_P5LtI , https://www.youtube.com/watch?v=c-7WeMeQcE8

Added 2026-10-22 (the step-back is a real hop covering ground; the earlier "≤ 2 studs, flat hop" targets were replaced after play-testing felt like walking backwards):

28. ESPN, "These step-back 3s sent another planet" (search snippet): "On average, the Harden step-back creates about 6 feet of shooting space, per Second Spectrum data" — https://www.espn.co.uk/nba/story/_/id/26118445/these-step-back-3s-sent-another-planet
29. US Sports Camps / Nike, "The Kobe Step-Back Drill": "push off your front foot", "push back and hop at a 45 angle, land on 2 feet", "Drop your hips, the higher you stand the harder it is!", "get the ball into your shooting pocket as your feet touch the ground", "explode straight up to shoot" — https://www.ussportscamps.com/tips/basketball/nike-basketball-camps-present-the-kobe-step-back-drill
30. CoachUp, "Basketball Tips: The Step Back" (Brandon Ball): plant the inside foot and step back to "create as much space as possible"; "land on both feet and make sure you're on balance"; "jump straight up, straight down" — https://www.coachup.com/nation/?p=1736
31. Dr. Dish, "Shooting footwork: 1-2 vs. the hop": the two-foot hop lands "with an equal amount of power" on both legs and can give a quicker release; coaches favour it on the move — https://blog.drdishbasketball.com/basketball-shooting-footwork-1-2-vs.-the-hop

## 9. Spin (reverse pivot)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Pivot foot | the front/inside foot (opposite the dribble hand), on the ball of the foot with the heel lifted; it doesn't slide | — | [C] |
| Hip height | lowest 0.42 H, average 0.46 H, range only ~0.07 H | ≈ 0.25–0.4 stud drop, ±0.12 | [M] Li |
| Pivot knee | ~63–68° flexion; ~2× body weight on the pivot leg | — | [M] |
| Hips travel | 3.15 m/s ≈ 1.7 H/s; a travelling move, not a spin on the spot | — | [M] |
| Swing leg | swings back round in a tight arc, knee bent, foot low; lands 0.25–0.35 H from the pivot in the new direction | 0.85–1.2 studs | [C]+[E] |
| Head | turns first, ~0.05 s ahead of the hips; eyes find the target before the body finishes | — | [C] |
| Shoulders | lead the pelvis by 15–30° of turn at mid-spin | — | [E] |
| Trunk | 10–25° forward, never back; side-bend within ±15° | — | [C]+[M] |
| Ball | a hard pound, then pulled round close to the far hip (radius 0.2–0.3 H, not touching the hip), pushed down in front in the new direction, other hand catches | — | [C] |
| Duration | plant → swing foot down 0.30–0.40 s; whole spin 0.55–0.75 s | — | [E] |

**References**
1. Coach's Clipboard, Dribbling — https://www.coachesclipboard.net/Dribbling.html
2. Coach's Clipboard, Footwork — https://www.coachesclipboard.net/Footwork.html
3. Active.com, "5 Crossover Dribbling Techniques" — https://www.active.com/basketball/articles/5-crossover-dribbling-techniques-a
4. FIBA WABC, Advanced lay-up techniques (snippet) — https://wabc-chn.fiba.com/?p=1124
5. Baller Boot Camp, Spin move — https://ballerbootcamp.com/how-to-spin-move-in-basketball/
6. Basketball Army, spin move breakdown — https://basketballarmy.com/how-to-do-a-basketball-spin-move/
7. Basketball Army, step-by-step (snippet) — https://basketballarmy.com/how-to-do-a-spin-move-in-basketball/
8. BasketballTrainer, spin mastery — https://basketballtrainer.com/how-to-do-a-spin-move-in-basketball/
9. LevelUp Basket, Spin into the shot — https://www.levelupbasket.com/basketball-drills/shooting-drills/spin-move-into-the-shot
10. The Ball Zone, spin move — https://theballzone.com/how-to-do-a-basketball-spin-move/
11. Li et al. 2021, *Kinesiology* — https://ojs.srce.hr/kinesiology/article/view/17087
12. 180-degree pivot turn biomechanics (PMC8355634) — https://pmc.ncbi.nlm.nih.gov/articles/PMC8355634/
13. NBA Video Rulebook, "lifts pivot foot on spin move" — https://videorulebook.nba.com/archive/travel-in-the-post-lifts-pivot-foot-on-spin-move/
14. Basketball for Coaches, Pivot foot — https://www.basketballforcoaches.com/pivot-foot/
15. Wikipedia, Carrying (basketball) — https://en.wikipedia.org/wiki/Carrying_(basketball)
16. Officiating.com forum, "Spin move" (snippet) — https://forum.officiating.com/basketball/100656-spin-move.html
17. Sportplan, "Dribble with Spin" — https://www.sportplan.net/s/Basketball/spin-move.jsp
18. One Up Basketball, Kyrie cross-spin — https://oneupbasketball.com/master-the-kyrie-irving-cross-spin-move/ (video https://www.youtube.com/watch?v=sQZzdsnuq_0)
19. Sportskeeda, Kobe drive/spin/fade (snippet) — https://sportskeeda.com/basketball/basketball-moves-breakdown-kobe-drives-spins-and-fades
20. Quora, step-by-step spin (snippet) — https://www.quora.com/How-do-you-do-the-spin-move-in-basketball-Is-there-any-step-by-step-guide
21. "The RIGHT Way To Do A Spin Move!" — https://www.youtube.com/watch?v=5xL1cJv1fMM
22. "How to Spin Move Tutorial! Basketball Basics for Beginners" — https://www.youtube.com/watch?v=K6CdZGGhQGk
23. iSport and others — https://www.youtube.com/watch?v=K0MzjnMzbj4 ; https://www.youtube.com/watch?v=TKW1jc7aKQk ; https://www.youtube.com/watch?v=ymf9X-42XFI ; https://www.youtube.com/watch?v=LpgT6W8plPY ; https://www.youtube.com/watch?v=ZRA6DI0X61U
24. Coach Meech (@ilb), jump-stop / 1-2 / seal spins — https://gondola.cc/posts/35794655-ilb-youtube

## 10. Standing jump shot

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Stance | width 19–25% H; shooting foot forward 6–8% H; rear toe turned out 15–24° | width ≈ 1.3–1.5 studs; stagger ≈ 0.2–0.27 | [M] Miller & Bartlett |
| Body turn | pelvis 8–26°, shoulders 15–29° toward the non-shooting side | — | [M] |
| Dip | knee 105–120° included (60–75° flexion), hip ~33° flexion, trunk 10–20° forward | — | [M] Okazaki |
| Pocket (wrist at the start) | 55–61% H (belt line) | ≈ 2.15–2.55 studs | [M] Podmenik |
| Ball at takeoff | wrist already 103–109% H (forehead) — **arms and legs rise together** | ≈ 5.0–5.4 studs | [M] |
| Release | wrist 113–126% H; elbow 135–160° (not locked); shoulder 115–130° | ball ≈ 6.0–6.5 | [M] |
| Release vs. the top of the jump | close: 0–60 ms after; mid-range: at it; three: 40–100 ms before | — | [M]+[D] |
| Jump | hips rise 0.23–0.31 m (0.13–0.16 H); flight 0.42–0.45 s | ≈ 0.45–0.55 stud by leg scale | [M] |
| Follow-through | wrist flexes 35–45° (not 90°); arm held ~0.6–1.0 s | — | [M]+[C] |
| Landing | 15–50 cm forward (0.08–0.26 H), 3–36 cm toward the non-shooting side; knees absorb | ≈ 0.3–0.9 stud forward | [M] |
| Order of motion | upper arm peaks 0.12 s before release, forearm 0.02–0.03 s before, hand at release | — | [M] Diehl |

**References**
1. Podmenik et al. 2021, J Hum Kinet 78 — https://johk.pl/wp-content/uploads/2023/04/10078-78-2021-v78-2021-03.pdf
2. Miller & Bartlett 1993, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/2817
3. Miller, "Relationship between kinematic variables and shooting distance: a re-evaluation", ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/3026
4. Satern 1993, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/1736
5. Diehl, Tant, Emmons & Osborn, set shot vs jump shot, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/1735
6. Vencúrik et al. 2021, IJERPH 18:934 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7908352
7. Amaro et al. 2025, JFMK 10:459 — https://pmc.ncbi.nlm.nih.gov/articles/PMC12641682/
8. Stojanović et al. 2019, Facta Universitatis — https://casopisi.junis.ni.ac.rs/index.php/FUPhysEdSport/article/download/3908/3222
9. Mikić et al. 2024, MJSSM 13(1) — https://www.mjssm.me/clanci/MJSSM_March_2024_Mikic.pdf
10. Miller & Bartlett 1996, J Sports Sci 14:243 — https://sponet.de/sponet/Record/4001903
11. Rojas, Cepero, Oña & Gutiérrez 2000, Ergonomics 43 — https://sponet.de/sponet/Record/4004741
12. Wissel (Human Kinetics excerpt), "Develop your shot with shooting mechanics" — https://us.humankinetics.com/blogs/excerpt/develop-your-shot-with-shooting-mechanics
13. Coach's Clipboard, Wissel shooting mechanics — https://coachesclipboard.net/WisselShootingMechanics.html
14. Breakthrough Basketball, "Shooting Footwork 101: Fight for Feet" — https://www.breakthroughbasketball.com/training/fight-for-feet
15. Breakthrough Basketball, "Three Components of a Quick Release" — https://www.breakthroughbasketball.com/fundamentals/shooting/three-components-of-a-quick-release
16. Breakthrough Basketball, "One Motion Shooting" — https://www.breakthroughbasketball.com/fundamentals/one-motion-shooting
17. Breakthrough Basketball, "Melissa Dixon" — https://www.breakthroughbasketball.com/fundamentals/melissa-dixon
18. SF Chronicle (Fontanella on Curry) — https://www.sfchronicle.com/sports/warriors/article/Stephen-Curry-s-shot-a-thing-of-scientific-6858446.php
19. Eugene Wei, "Stephen Curry" — https://www.eugenewei.com/blog/2015/12/10/curry
20. Physical Education Update, "Release the Ball Early for Better Jump Shots" — https://www.physicaleducationupdate.com/public/329.cfm
21. Acta Bioeng Biomech 2023, jump-shot kinematics (snippet; the reported URL was truncated to yadda.icm.edu.pl)
22. JFMK 2023 8(3):129 (snippet) — https://www.mdpi.com/2411-5142/8/3/129
23. Sponet 4078381, set- vs jump-shot kinematics — https://www.sponet.de/sponet/Record/4078381
24. Dot Esports, NBA 2K24 jumpshot guide — https://dotesports.com/nba-2k/news/ultimate-nba-2k24-jumpshot-guide-best-jumpshots-for-each-player-height
25. efdeportes, jump-shot biomechanics — https://efdeportes.com/efd105/biomecanica-do-arremesso-de-jump-no-basquetebol.htm
26. Cabarkapa et al. (PMC9590067) — https://pmc.ncbi.nlm.nih.gov/articles/PMC9590067/
27. Dip study (PMC8273237) — https://pmc.ncbi.nlm.nih.gov/articles/PMC8273237/
28. Knudson's teaching points (Frontiers) — https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.658102/full
29. Okazaki & Rodacki 2012 — https://www.jssm.org/jssm-11-231.xml-Fulltext

## 11. Pull-up jumper

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Braking | 3–5 m/s cut to ~0.8–1.0 m/s by takeoff; takeoff direction 78–88° (nearly vertical) | — | [M]+[D] |
| Brake step | heel first, 0.27–0.37 H ahead of the hips; longer than a walking stride | ≈ 0.9–1.25 studs | [C]+[D] |
| Gather (1-2) | inside foot, then the second foot lands level into the stagger 0.12–0.20 s later | — | [C]+[D] |
| Gather (hop) | both feet land together; hop 0.10–0.15 s, 5–10 cm high | — | [C]+[D] |
| Ball | the last dribble pounded; caught at the pocket (55–60% H) on the final foot contact; then rises without stopping | — | [C]+[M] |
| Trunk | 10–20° forward on the brake step, upright by takeoff | — | [D] |
| Jump | standing jump + 0–20% | — | [M] NTNU |
| Landing | 0.3–0.6 m forward | ≈ 0.55–1.1 studs | [M]+[D] |

**References**
1. Breakthrough Basketball, "Use THIS Tip To Make Pull-Ups Like Devin Booker" — https://www.breakthroughbasketball.com/training/pullup-pound-dribble
2. Dr. Dish blog, "Shooting Footwork: 1-2 vs The Hop" — https://blog.drdishbasketball.com/basketball-shooting-footwork-1-2-vs.-the-hop
3. Breakthrough Basketball, "1-2 or Hop" — https://www.breakthroughbasketball.com/fundamentals/camps-12-hop
4. Active.com, "Shooting after ending a dribble" — https://www.active.com/basketball/articles/shooting-after-ending-a-dribble-2
5. NBA Video Rulebook, hop-travel — https://videorulebook.nba.com/archive/travel-on-drive-hop-travel-jumps-off-of-and-lands-on-same-foot-3
6. NBA Video Rulebook, "too many steps after gather" — https://videorulebook.nba.com/archive/travel-in-the-post-too-many-steps-after-gather-5
7. Coachhoops Substack, "Shooting Footwork" — https://coachhoops.substack.com/p/shooting-footwork
8. Breakthrough Basketball, "Fight for Feet" — https://www.breakthroughbasketball.com/training/fight-for-feet
9. Breakthrough Basketball, "Melissa Dixon" — https://www.breakthroughbasketball.com/fundamentals/melissa-dixon
10. Mikić et al. 2024, MJSSM — https://www.mjssm.me/clanci/MJSSM_March_2024_Mikic.pdf
11. Vencúrik et al. 2021 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7908352
12. Miller & Bartlett 1993 — https://ojs.ub.uni-konstanz.de/cpa/article/view/2817
13. Podmenik et al. 2021 — https://johk.pl/wp-content/uploads/2023/04/10078-78-2021-v78-2021-03.pdf
14. Satern 1993 — https://ojs.ub.uni-konstanz.de/cpa/article/view/1736
15. Diehl et al. — https://ojs.ub.uni-konstanz.de/cpa/article/view/1735
16. Universitat de València, "Effect of the delay of the second support…" — https://producciocientifica.uv.es/documentos/60a311e1f08f127ee113c8df
17. Hirata et al. 2011 — https://ojs.ub.uni-konstanz.de/cpa/article/view/4779
18. Jin et al., ISBS, long-jumper kinematics — https://ojs.ub.uni-konstanz.de/cpa/article/view/2379
19. SF Chronicle (Fontanella) — https://www.sfchronicle.com/sports/warriors/article/Stephen-Curry-s-shot-a-thing-of-scientific-6858446.php
20. Eugene Wei on Curry — https://www.eugenewei.com/blog/2015/12/10/curry
21. MILO Homecourt, "Shooting coming from dribble" — https://www.milo.com.ph/milo-homecourt/online-sports-programs/basketball/shooting-coming-from-dribble
22. HoopDirt, "Drill of the Week" — https://hoopdirt.com/drill-of-the-week-28/
23. NTNU thesis, dribble-and-shoot vs catch-and-shoot — https://etds.lib.ntnu.edu.tw/thesis/detail/38d77cfccf7425cc235eaf478ca0a463
24. FIBA WABC, jump stop vs two-count stop — https://wabc.fiba.com/?p=409

## 12. Fadeaway

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Trunk lean back at release | 12–15° typical (8–25°; Dirk/Jordan 20–25°), built at the hips and spine during the rise; head tilts back about half as much | — | [E] (normal shot 1–4° back, [M]) |
| Ball release angle | unchanged (59–60°); keep the arm's angle to the floor fixed, so the ball ends up in front of and above the face | — | [M] Cheng 2025 |
| Arm extension | 0.183 s (~8% faster than normal) | — | [M] |
| Prep before takeoff | trunk 5–7° forward | — | [M] |
| Backward travel | 0.13–0.3 H, ~0.2 H typical | ≈ 0.45–1.0 stud | [E] |
| Jump | lower than a normal jump | — | [E] |
| Legs in the air | feet slightly ahead of the hips as a counterweight, knees 150–170°; one-leg variant: free knee forward at 60–90° hip flexion | — | [E] |
| Landing | behind the takeoff point; balls of the feet, then heels; knees bend 30–40° | — | [E] |

**References**
1. Dallas News, "Signature shot: breaking down Dirk Nowitzki's one-legged fadeaway" — https://sportsday.dallasnews.com/dallas-mavericks/mavericks/2019/04/02/signature-shot-breaking-dirk-nowitzkis-one-legged-fadeaway-beaten-defenders-decades
2. theScore, "Unrivaled: Dirk Nowitzki's fadeaway jumpshot" — https://www.thescore.com/nba/news/558457
3. NBA.com, "Archive 75: Dirk Nowitzki" — https://www.nba.com/news/archive-75-dirk-nowitzki
4. mavs.com breakdown — https://mavs.com/?p=184370
5. Mavs Moneyball 2017 — https://www.mavsmoneyball.com/2017/11/16/16664602/dirk-nowitzki-fadeaway-still-get-buckets
6. ESPN, "Why Dirk Nowitzki's legacy will never fade away" — https://www.espn.com/nba/story/_/id/22188892
7. Sky Sports, Jordan's turnaround fadeaway — https://www.skysports.com/nba/news/12040/11990222/michael-jordans-iconic-turnaround-fadeaway-jump-shot-howd-he-do-that
8. the42.ie on Durant — https://www.the42.ie/article.php?id=1832964
9. Sports Feel Good Stories, "Fadeaway in basketball" — https://www.sportsfeelgoodstories.com/fadeaway-definition-in-basketball/
10. NBC LA, "Kobe Bryant fading away with the fadeaway" — https://www.nbclosangeles.com/news/sports/lakers_kobe-bryant-fadeaway-2014-15/62363
11. "How to: Shoot a PERFECT Fadeaway Jump Shot" — https://www.youtube.com/watch?v=YI-wEjHurJ4
12. "How To Shoot A Fadeaway" (Short) — https://www.youtube.com/shorts/9tCqtOBaVxM
13. Mariah Chandler, "Easy Fadeaway Tutorial" — https://www.youtube.com/watch?v=TQbbSbr2Y6g
14. "How to Create a LETHAL Fadeaway Like Kobe Bryant" — https://www.youtube.com/watch?v=tlN3MT1D2SQ
15. Breakthrough Basketball forum, "fading back" — https://www.breakthroughbasketball.com/forum/viewtopic.php?p=6402
16. Cheng et al. 2025, "Biomechanics Analysis of Normal Jump Shot and Fade-Away Jump Shot" — https://pdfs.semanticscholar.org/b380/a52e89b135d0c0eda12265d473dfb07ecc35.pdf
17. St. Michel, Zebas & Potteiger, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/2931/2773
18. Hudson, free-throw skill level, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/1736/1635
19. "Kinematic analysis of the basketball jump shot with a backward take-off" — https://www.bib.irb.hr/1031270
20. Wikipedia, "Fadeaway" — https://en.wikipedia.org/wiki/Fadeaway

## 13. Step-back jumper

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Rhythm | gather/zero step, 1, 2, launch | — | [C] |
| Gap between the two landings | 0.08–0.20 s (0.12 typical) | — | [E] |
| Hop back | small for this game: 0.15–0.25 H, flight 0.15–0.25 s, hips rise only 0.05–0.10 m | ≈ 0.5–0.85 stud | [E] |
| Brake on landing | knee to 104–112° included (~70° flexion) for 0.1–0.15 s; landing foot 0.1–0.2 H behind the hips | — | [M]+[E] |
| Trunk | 5–10° forward while braking; upright (0–5° back) at release | — | [M]+[E] |
| Backward drift in the shooting jump | 0–0.08 H (ideally ~0) | ≤ 0.27 stud | [E] |
| Ball | held at the hip/chest during the hop; rises only after the second foot lands | — | [C] |

**References**
1. ESPN, "Why James Harden is always a step ahead (or step back)" — https://www.espn.co.uk/nba/story/_/id/21742270/nba-stepback-3-cheat-code-made-james-harden-virtually-unguardable
2. Houston Chronicle, "Why James Harden isn't traveling on his step-back" — https://preview-prod.w.houstonchronicle.com/texas-sports-nation/rockets/article/Why-James-Harden-isn-t-traveling-on-his-step-back-12841154.php
3. Business Insider, referee Zarba on Harden's step-back — https://www.businessinsider.nl/nba-referee-james-harden-step-back-jumper-travel-basketball-zach-zarba-2018-4/
4. NBA.com, "NBA works to tighten traveling calls, 2019-20" — https://www.nba.com/news/nba-works-tighten-traveling-calls-2019-20
5. Basketball For Coaches, "What is the gather step rule?" — https://basketballforcoaches.com/?p=9511
6. adidas, "How to do the James Harden step back" — https://www.adidas.com/us/blog/create-space-instantly-how-to-do-the-james-harden-step-back
7. CoachUp, "The Step Back" — https://www.coachup.com/nation/?p=1736
8. InsideHook, Dončić step-back eccentric force — https://www.insidehook.com/fitness/luka-doncic-step-back-eccentric-force/amp
9. theScore, "Court Vision: Dončić's signature step-back" — https://www.thescore.com/news/1675581
10. The Ringer, Luka game-winner vs Gobert 2024 — https://www.theringer.com/2024/5/25/24164655/luka-doncic-game-winner-rudy-gobert-dallas-mavericks
11. ESPN, "Slowing quickly", 2024 playoffs — https://africa.espn.com/nba/story/_/id/40053245/nba-playoffs-2024-slowing-quickly-become-favorite-move-elite-scorers-such-anthony-edwards-luka-doncic-nikola-jokic-sga
12. Taylor Jannsen, "Stride Stops" — https://taylorjannsen.substack.com/p/stride-stops
13. TeamArete shooting footwork — https://id3430.securedata.net/teamarete/footwork.html
14. Breakthrough Basketball, 4 shooting drill progressions — https://www.breakthroughbasketball.com/training/4shootingdribblemoves
15. Breakthrough, "3 Moves to Improve Your Stepback Jumper" — https://www.youtube.com/watch?v=Q41TgJNulYY
16. Coach Nick, "Proper Footwork On The Step Back" — https://www.youtube.com/watch?v=mnN-DPBPMrQ
17. Baller Boot Camp, "EXACTLY How To Shoot A Step Back Jumper" — https://www.youtube.com/watch?v=Z4l66qb3RkA
18. Creighton, "Ground reaction forces … run, rapid stop and vertical jump" — https://researchworks.creighton.edu/esploro/outputs/conferencePaper/Ground-reaction-forces-and-dominant-leg/991005929808702656
19. Struzik et al. 2014, J Hum Kinet 42 — https://pmc.ncbi.nlm.nih.gov/articles/PMC4234772
20. Vencúrik et al. 2021 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7908352/

## 14. Side shot (side-step / drifting jumper)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Footwork | push off the outside foot; the lead (travel-side) foot lands first and brakes; the trail foot lands shoulder-width away; then jump straight up | — | [C] |
| Gap between landings | 0.08–0.2 s | — | [E] |
| Sideways drift in the shooting jump | 0–0.08 H (aim for ~0) | ≤ 0.27 stud | [E] |
| Trunk side tilt | 5–12° toward the outside while braking; 0–5° at release (up to 8–10° away from the drift if drifting on purpose) | — | [E] |
| Shoulders | square to the rim by release; feet may stay turned 10–20° open | — | [C] |
| Ball | straight line to the rim; rises up the centre line after the second foot lands | — | [C] |

**References**
1. The Ringer, "The NBA's Electric Slide" — https://www.theringer.com/2019/03/05/nba/james-harden-side-step-houston-rockets
2. Houston Chronicle (Harden side-stepping Aldridge) — https://preview-prod.w.houstonchronicle.com/texas-sports-nation/rockets/article/Why-James-Harden-isn-t-traveling-on-his-step-back-12841154.php
3. ESPN, Harden step-back feature — https://www.espn.co.uk/nba/story/_/id/21742270/nba-stepback-3-cheat-code-made-james-harden-virtually-unguardable
4. Spin.ph, Harden one-legged side-step three — https://www.spin.ph/life/guide/james-harden-unstoppable-moves-one-leg-three-points-a547-20190820
5. Breakthrough Basketball, "Add Steph's gold-medal-winning move" — https://www.breakthroughbasketball.com/training/steph-side-step
6. Breakthrough Basketball, Harden Euro / side-step — https://www.breakthroughbasketball.com/training/Harden-Euro-Step
7. adidas, Harden step-back blog — https://www.adidas.com/us/blog/create-space-instantly-how-to-do-the-james-harden-step-back
8. Sportplan, "Around the World (jump shots)" — https://www.sportplan.net/sketches/Basketball/openSketch/4374079
9. TeamArete, "Taking the lid" — https://id3430.securedata.net/teamarete/takingthelid.html
10. Basketball For Coaches, Steph Curry shooting form — https://www.basketballforcoaches.com/steph-curry-shooting-form/
11. FIBA WABC coaching notes — https://wabc.fiba.com/?p=430
12. Messina, Chieffi, Monda et al. 2014, "Laterality of a second player position…" — https://fair.unifg.it/handle/11369/345195
13. ISBS, "Joint torque of support leg and GRF in side-step cutting" — https://ojs.ub.uni-konstanz.de/cpa/article/view/5662
14. "The art of side step and step back MASTER this footwork" — https://www.youtube.com/watch?v=c-7WeMeQcE8
15. HoopStudy, "Three SIDE STEP drills" — https://www.youtube.com/watch?v=7Rxxbm4V0pk (also https://www.youtube.com/shorts/rOisI6mzowY)
16. Coachhoops Substack, "Shooting footwork" — https://coachhoops.substack.com/p/shooting-footwork
17. Dr. Dish, "Shooting on the move" — https://blog.drdishbasketball.com/basketball-shooting-workout-on-the-move-shooting
18. Miller & Bartlett 1993 — https://ojs.ub.uni-konstanz.de/cpa/article/view/2817
19. Knudson 1993, "Six key teaching points" — https://researchgate.net/profile/Duane-Knudson/publication/240177823
20. BetterBasketball / CoachTube, "The Shooting Course" week 6 — https://coachtube.com/course_lesson/the-shooting-course/week-6/664773

## 15. Close shot (inside ~8 ft)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Start | ball high (chest–chin, 70–85% H), no big dip | ≈ 3.2–4.2 studs | [C]+[M] |
| Stance | near-square, stagger ≤ 0.1 m, shoulders turned ≤ 15° | — | [M]+[C] |
| Release | 30–80 ms **after** the top of the jump (a little "hang"); steep 60–75° arc; elbow 140–150° with a firm wrist flick | — | [M]+[D] |
| Trunk at release | ~5° back | — | [M] Okazaki 95.8° |
| Forward drift | 0.05–0.25 m | ≈ 0.1–0.45 stud | [M]+[D] |
| Floater variant (not in the game yet) | one foot, low jump 0.10–0.20 m, arm nearly vertical, trunk 10–15° back, no pause | — | [M] Machida + [D] |

**References**
1. Miller & Bartlett 1993 — https://ojs.ub.uni-konstanz.de/cpa/article/view/2817
2. Miller, re-evaluation, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/3026
3. Satern 1993 — https://ojs.ub.uni-konstanz.de/cpa/article/view/1736
4. Diehl et al. — https://ojs.ub.uni-konstanz.de/cpa/article/view/1735
5. Podmenik et al. 2021 — https://johk.pl/wp-content/uploads/2023/04/10078-78-2021-v78-2021-03.pdf
6. Machida et al. 2016, "A study on the mechanism and usefulness of the floater shot" — https://lida.sport-iat.de/dbb/Record/4038510
7. AIP Inside Science, "Dissecting the bank shot" — https://www.aip.org/inside-science/dissecting-the-bank-shot
8. 80 Percent Mental, bank-shot study — https://www.80percentmental.com/blog/tag/Bank+Shot
9. Coach's Clipboard (Wissel) — https://coachesclipboard.net/WisselShootingMechanics.html
10. Human Kinetics (Wissel) — https://us.humankinetics.com/blogs/excerpt/develop-your-shot-with-shooting-mechanics
11. Physical Education Update — https://www.physicaleducationupdate.com/public/329.cfm
12. Rojas et al. 2000 — https://sponet.de/sponet/Record/4004741
13. Amaro et al. 2025 — https://pmc.ncbi.nlm.nih.gov/articles/PMC12641682/
14. Miller & Bartlett 1996 — https://sponet.de/sponet/Record/4001903
15. Breakthrough "Melissa Dixon" — https://www.breakthroughbasketball.com/fundamentals/melissa-dixon
16. Stojanović et al. 2019 — https://casopisi.junis.ni.ac.rs/index.php/FUPhysEdSport/article/download/3908/3222
17. Semarak Ilmu, normal vs fade-away jump shot — https://semarakilmu.com.my/journals/index.php/applied_sciences_eng_tech/article/view/5650
18. Sponet set- vs jump-shot model — https://www.sponet.de/sponet/Record/4078381
19. Okazaki & Rodacki 2012 — https://www.jssm.org/jssm-11-231.xml-Fulltext
20. FIBA WABC, jump stop vs two-count stop — https://wabc.fiba.com/?p=409

## 16. Layup (right hand)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Footwork | gather on the RIGHT foot (long step 0.62–0.72 H), then a shorter LEFT plant (0.85–0.9× the first), jump off the left | ≈ 2.1–2.4 then ≈ 1.8–2.1 studs (by leg scale) | [M] Hanna |
| Dip before the plant | the hips drop 3–5 cm on the right step | ≈ 0.1–0.17 stud | [M] |
| Plant leg | knee ~21° bent at touchdown, rising ~25° more; hip 29°; heel first | — | [M] Chang |
| Takeoff | ~2.4 m/s upward; hips rise ≈ 0.16 H; flight ~0.5 s | — | [M]+[D] |
| Right knee drive | thigh about horizontal (hip 80–100°, knee ~90°), peaking near the release | — | [E] |
| Ball | gathered at the right hip, carried up the right side to the shoulder or ear ("high and tight"), never across the belly; released 0.3–0.5 m above the head, in front of the right shoulder, at or just before the top of the jump | — | [C]+[E] |
| Guide hand | leaves the ball at head height and becomes a bent arm bar | — | [C] |
| Trunk | 5–15° forward, tall; right shoulder toward the basket | — | [E] |
| Landing | left foot or both feet; knees and hips bend 30–60° | — | [E] |

**References**
1. Chang, Cesario-Ketchum & Hsieh 2012, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/5325/4896
2. Hanna et al. 2015, JHSE — https://www.jhse.ua.es/article/view/2015-v10-n2-proc-comparison-in-some-kinematic-variables-of-layup (also https://www.kheljournal.com/archives/2019/vol6issue3/PartB/6-3-12-621.pdf)
3. Miura (NIFS Kanoya), running one-legged jump — https://www.nifs-k.ac.jp/files/faculties/ronbun/miura.pdf
4. "Ankle biomechanics of the three-step layup", Scientific Reports 2023 — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10618240/
5. Underhand lay-up from the right and left sides, Sportive (UNM) — https://journal.unm.ac.id/index.php/sportive/article/view/12775
6. Chakravarty 2018, IJPEAES — https://journal.lnipeassam.edu.in/assets/resources/2024/12/Vol-4-No.-2-November-2018.pdf
7. Vint & Hinrichs 1996, J Appl Biomech — https://researchgate.net/profile/Richard-Hinrichs-2/publication/288544133
8. Jadidi & Kilani, one-foot vs two-foot take-off, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/4563/4250
9. Basketball For Coaches, "How to Do a Layup (6-Step Guide)" — https://basketballforcoaches.com/?p=7401
10. Owayo Magazine, "The Lay Up" — https://www.owayo.com/magazine/basketball-layup-us.htm
11. Coach's Clipboard, "Layup" — https://www.coachesclipboard.net/Layup.html
12. Coaches Insider, "Outside Foot Layup Drill" — https://coachesinsider.com/mens-basketball/outside-foot-layup-drill/
13. Breakthrough Basketball, "Lay Up Progressions" — https://www.breakthroughbasketball.com/drills/lay-up-progressions
14. Active.com, "The most missed shot in basketball" — https://active.com/basketball/articles/the-most-missed-shot-in-basketball-b
15. Issaquah Parks, Shooting Drills — https://www.issaquahwa.gov/DocumentCenter/View/7748/Shooting-Drills
16. Basketball For Coaches, "What is the Gather Step Rule" — https://www.basketballforcoaches.com/?p=9511
17. ESPN TrueHoop, "The two-step" — https://www.espn.com/blog/truehoop/post/_/id/7097/the-two-step
18. Wikipedia, "Basketball moves" — https://en.wikipedia.org/wiki/Basketball_moves
19. Cal Poly Grand Ave, "Master the basketball layup" — https://grandavehousing.calpoly.edu/news/master-the-basketball-layup-a
20. Jared Berggren, "Creating Proper Footwork for a Standard Layup" — https://www.youtube.com/watch?v=aJm-dKpJYXo
21. HoopsKing, "How to Teach Basketball Layups with Proper Footwork" — https://www.youtube.com/watch?v=y3EBpd5RdgY
22. "The Basic Steps of the Lay Up (Right Side)" — https://www.youtube.com/watch?v=uv7COBs24D8
23. "Footwork For PERFECT LAYUPS" — https://www.youtube.com/watch?v=jIGz6flxoQ8
24. "Footwork For A Left/Right Handed Layup" — https://www.youtube.com/watch?v=ZIXkhpvpU1o
25. Coach Kam, "Proper Layup Footwork Explained" — https://www.youtube.com/shorts/Q9rqFgaMgBM
26. World Athletics 2017, long-jump biomechanics — https://lida.sport-iat.de/dlv/Record/4049026

## 17. Running dunk

**Recommendation.** Use a one-foot takeoff off the LEFT foot, the same footwork as the layup. If a two-foot takeoff is kept, use a staggered 1-2 plant (the second foot 0.05–0.15 s later), never a simultaneous stop at running speed, which reads as a freeze.

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Penultimate step | 6–15% longer, lands flat; hips drop 3–5 cm | hip drop ≈ 0.1–0.17 stud | [M] |
| Plant | shorter last step, heel first, knee ~20° → 45–55°, contact 0.2–0.3 s | — | [M]+[E] |
| Takeoff distance | 0.8–1.0 H from the rim | — | [M] Sharpe 1.63 m |
| Ball | gathered at the right hip; arms swing forward and up with the plant; overhead on the way up; cocked behind the head near the top of the jump; slammed at or just after the top | — | [C]+[E] |
| Legs in the air | knees tuck back behind the hips after the top (knees ~90°) | — | [M] PopSci |
| Rim hang | 0.1–0.3 s | — | [E] |
| Trunk | tall at the plant (no forward dive); slight arch on the cock; 20–30° forward on the slam | — | [E] |

**References**
1. Vint & Hinrichs 1996 — https://researchgate.net/profile/Richard-Hinrichs-2/publication/288544133
2. Tai et al. 2018, J Hum Kinet 64 — https://johk.pl/wp-content/uploads/2023/03/10078-64-2018-v64-2018-07.pdf
3. Tai et al. 2026, single-leg-approach jumps — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12843030/
4. Miura (NIFS) — https://www.nifs-k.ac.jp/files/faculties/ronbun/miura.pdf
5. Jadidi & Kilani, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/4563/4250
6. NBA.com, "How NBA Dunk Score is calculated" — https://www.nba.com/news/a-deep-dive-into-how-nba-dunk-score-is-calculated
7. Edoardo Hoop Bag, "Analyzing NBA dunks with R" — https://edoardohoopbag.substack.com/p/analyzing-nba-dunks-with-r-a-tutorial
8. PopSci, "The physics behind iconic NBA slam dunks" — https://www.popsci.com/story/science/nba-dunk-physics/
9. The Hoops Geek, "How to Dunk" — https://www.thehoopsgeek.com/how-to-dunk
10. The Hoops Geek, "Jump higher off two feet" — https://www.thehoopsgeek.com/jump-higher-off-two-feet/
11. A1 Athlete, "Vertical Jump Technique" — https://a1athlete.com/vertical-jump-technique/
12. Sport Manitoba, "Your answer to increasing your vertical" — https://sportmanitoba.ca/resources/your-answer-to-increasing-your-vertical
13. Breakthrough Basketball, "Improving your vertical jump" — https://www.breakthroughbasketball.com/issue092223
14. Breakthrough Basketball, "1 foot or 2? Finishing at the rim" — https://www.breakthroughbasketball.com/training/one-foot-v-two-feet-finishing
15. Basketball Catalyst, "The power of playing off two feet" (snippet) — https://www.basketballcatalyst.com/post/the-power-of-playing-off-two-feet-it-s-more-than-just-a-just-a-jump-stop
16. FIBA WABC, "Advanced lay-up techniques" — https://wabc-chn.fiba.com/?p=1134
17. AnandTech forum (anecdotal) — https://forums.anandtech.com/threads/jumping.1666956/post-16930196
18. ISBS, support phase in long and high jumping — https://ojs.ub.uni-konstanz.de/cpa/article/view/2950
19. World Athletics 2017 — https://lida.sport-iat.de/dlv/Record/4049026
20. NBA Video Rulebook, hanging on the rim — https://videorulebook.nba.com/archive/technical-foul-player-hangs-on-rim-following-dunk-2
21. Boston.com, Tatum rim-hang technical — https://www.boston.com/sports/boston-celtics/2024/01/19/nba-celtics-nuggets-jayson-tatum-technical-foul-hanging-on-rim-dunk-watch
22. WikiHow / Kiwix, "Dunk" — https://kiwix.lema.org/wikihow_en_maxi_2023-03/Dunk
23. Slovak J Sport Sci 2021, dunk kinetics — https://doaj.org/article/6677c35dec564731a24eb4df16bc0887
24. Journal of Sports Analytics 2019, dunk-contest scoring — https://journals.sagepub.com/doi/10.3233/JSA-190242
25. "How To Dunk: Approach" — https://www.youtube.com/watch?v=xW5zA7Y3JNk
26. "How To Jump off 2 Feet [Technique/Mistakes]" — https://www.youtube.com/watch?v=dN1gatltwNg
27. "How To Dunk Off 2 Feet" — https://m.youtube.com/watch?v=B4ibsH463N4
28. Vadym Miller, "Jump Technique off two feet" — https://www.youtube.com/watch?v=pQ34IU-2xhc
29. C.J. Champion, "21 Levels of Dunking" — https://www.youtube.com/watch?v=H854e_GFV_U
30. Pro Hoops Daily, "Classic Slow Motion Dunks" — https://www.youtube.com/watch?v=wtCST_Df0Uo

## 18. Standing dunk (two feet, under the rim)

**Target values**

| What | Real | Rig | Tag |
|---|---|---|---|
| Phases (real) | dip 0.42 s + brake 0.16 s + push 0.29 s = 0.86 s (games compress to 0.45–0.6 s) | — | [M] Vaverka |
| Bottom of the dip | knee flexion 90–110°, hips 0.2–0.25 H lower, trunk 35–45° forward | hip drop ≈ 0.7–0.85 stud (limited by the rig's leg reach) | [M] |
| Ball / arm swing | the ball swings DOWN toward the knees/shins during the dip, then UP fast; the upswing starts at ~76% of the takeoff (just after the bottom); overhead at toe-off | — | [M] |
| Extension order | hips first, then knees; ankles ~0.1 s later | — | [M] |
| Slam | ball cocked behind the head (elbows 90–110°), then driven down 0.08–0.15 s; trunk folds 15–30° | — | [E] |
| Landing | near the takeoff spot (< 0.3 m drift); knees bend 40–70° | — | [E] |

**References**
1. Vaverka et al. 2016, J Hum Kinet — https://pmc.ncbi.nlm.nih.gov/articles/PMC5260575/
2. Effect of countermovement depth, 2024 — https://pmc.ncbi.nlm.nih.gov/articles/PMC11208864/
3. "Optimal knee angle for maximum vertical jump height", IJESAB — https://digitalcommons.wku.edu/ijesab/vol8/iss8/45
4. BYU study (ISBS) — https://ojs.ub.uni-konstanz.de/cpa/article/view/2330/2173
5. Mandic et al. 2016 — https://pmc.ncbi.nlm.nih.gov/articles/PMC5260520
6. Harrison, Floría & Sánchez-Sixto 2018 — https://pure.ul.ie/en/publications/larger-countermovement-increases-the-jump-height-of-countermoveme/
7. Pérez-Castilla et al. 2020 — https://lida.sport-iat.de/ta/Record/4065143?lng=en
8. Lees, Vanrenterghem & De Clercq 2004, J Biomech 37:1929 (arm swing in the vertical jump)
9. Chen et al. 2008, arm-motion simulation — https://lida.sport-iat.de/twm/Record/4014544?lng=en
10. Induced-energy analysis of arm swing (Sports Biomech 2010) — https://pure.psu.edu/en/publications/an-induced-energy-analysis-to-determine-the-mechanism-for-perform/
11. Essex, arm swing and proximal-to-distal delay — https://repository.essex.ac.uk/39117/1/
12. WKU IJESAB, arm swing on CMJ — https://digitalcommons.wku.edu/ijesab/vol16/iss2/335
13. IJSC 2024, CMJ with and without arm swing — https://doaj.org/article/8a372a4b8cdd4a68b262c225b7293c7e
14. Eric Cressey, "Breaking down the countermovement jump – Part 1" — https://ericcressey.com/?p=50195
15. The Hoops Geek, "How to Dunk" — https://www.thehoopsgeek.com/how-to-dunk
16. Jadidi & Kilani, ISBS — https://ojs.ub.uni-konstanz.de/cpa/article/view/4563/4250
17. Tom Reiter, big-man pre-practice drills — https://id3430.securedata.net/teamarete/prepractice.html
18. Breakthrough Basketball, "Mikan Drill" — https://www.breakthroughbasketball.com/drills/mikan-drill
19. Wikipedia, "Mikan drill" — https://en.wikipedia.org/wiki/Mikan_drill
20. Coaches Insider / Belmont, "Guard Mikans" — https://coachesinsider.com/mens-basketball/guard-mikans-with-bart-brooks-belmont-univ-2
21. Cortland thesis, one- vs two-foot landing forces — https://digitalcommons.cortland.edu/theses/142
22. Netball WA, landing basics — https://wa.netball.com.au/sites/wa/files/2020-06/Netball%20WA%20Basic%20Netball%20Skills%20%26%20Activities.pdf
23. UW CSE 459, "Two-footed (symmetrical) jump tutorial" — https://courses.cs.washington.edu/courses/cse459/03wi/Projects/Adam/symJump/symJump.html
24. Toronto CSC418 animation-principles slides — https://www.dgp.toronto.edu/~karan/courses/418f17/slides/lecture9.pdf
25. "2 foot dunk technique Tutorial" — https://www.youtube.com/watch?v=mXNCQvWShGA
26. Vadym Miller, "Jump Technique off two feet" — https://www.youtube.com/watch?v=pQ34IU-2xhc
27. NBA.com Dunk Score definitions — https://www.nba.com/news/a-deep-dive-into-how-nba-dunk-score-is-calculated
28. Dunk-height calculator — https://calculover.com/sports-athletics/basketball/dunk/
