# RoHoops — Game Design Plan

## 1. Game Concept

**RoHoops** is a skill-focused basketball game built around fluid, responsive controls, simple environments, and player customization.

The main design goal is to make basketball feel **fast, readable, and mechanically expressive** without requiring a visually complex map or an overwhelming control scheme.

The player creates a custom basketball build, improves it through gameplay, and uses movement, dribbling, shooting, passing, defense, and finishing mechanics to outplay opponents.

### Core pillars

1. **Skill-based gameplay** — player input and timing should matter more than complicated menus or systems.
2. **Fluid movement** — movement, dribbling, shooting, and defensive actions should connect naturally.
3. **Simple presentation** — maps should remain lightweight so performance and gameplay responsiveness are prioritized.
4. **Build progression** — players gradually develop their own playstyle through attributes and skill points.
5. **Basketball variety** — the same basic input can produce different basketball actions depending on movement, position, timing, and context.

---

# 2. Core Gameplay Loop

The intended gameplay loop is:

```text
Create Build
    ↓
Enter Game
    ↓
Move / Dribble / Pass / Defend
    ↓
Use Basketball Skills
    ↓
Score or Stop Opponent
    ↓
Earn Progress / XP
    ↓
Level Up
    ↓
Spend Skill Points
    ↓
Improve Build
    ↓
Return to Game
```

The important idea is that progression should **support gameplay rather than replace it**. A better build gives the player more options, but player skill should remain important.

---

# 3. Camera

## Fixed Rim-Focused Camera

The camera should remain relatively fixed and oriented toward the basketball rim.

### Goals

- Keep the court easy to read.
- Make movement predictable.
- Reduce camera management.
- Keep attention on basketball actions.
- Support precise dribbling and defensive movement.

The camera should not require the player to constantly rotate it while playing.

A slight camera adjustment may be allowed when necessary to keep the active play area visible, but the camera should remain fundamentally **rim-focused**.

---

# 4. Player Movement

## Basic Movement

| Input | Action |
|---|---|
| `W` / `↑` | Move forward |
| `A` / `←` | Move left |
| `S` / `↓` | Move backward |
| `D` / `→` | Move right |
| `Shift` | Run |

Movement should be responsive and allow the player to quickly transition between:

- Walking
- Running
- Dribbling
- Shooting
- Finishing
- Passing
- Defending

The game should avoid excessive movement animations that make the player feel disconnected from their input.

---

# 5. Skill / Dribbling System

## Mouse / Trackpad Skills

Dribbling and skill moves are controlled primarily through the **mouse or trackpad**.

The system is inspired by the movement philosophy of **NBA 2K Arcade Edition**, where directional input can be used to perform basketball moves rather than relying entirely on a large collection of individual buttons.

The objective is to make the player feel like they are **controlling the movement of the ball**, rather than selecting an animation from a menu.

### Design goals

- Directional skill input.
- Fast transitions between moves.
- Context-sensitive animations.
- Minimal button combinations.
- High skill ceiling.

Examples of possible skill actions:

- Crossovers
- Behind-the-back
- Between-the-legs
- Hesitation
- Spin
- Step-through
- Direction changes

The exact move set can be defined later.

---

# 6. Shooting

## Primary Shoot Input

`E` = Shoot / Finish

The result of pressing `E` depends on the player's position, movement, and context.

This keeps the control scheme simple while allowing multiple types of basketball actions.

### Shooting states

The game should be able to distinguish between:

- Standing shots
- Pull-ups
- Fadeaways
- Step-backs
- Side shots

The player's movement immediately before or during the shot can influence which animation is selected.

### Example

```text
Running → E
        ↓
Pull-up / moving shot

Moving backward → E
        ↓
Fadeaway / step-back

Moving sideways → E
        ↓
Side shot

Stationary → E
        ↓
Regular jump shot
```

The exact rules should be tuned during prototyping rather than permanently hard-coded from the beginning.

---

# 7. Finishing

Finishing uses the same `E` input as shooting, but the result depends on proximity to the rim and player movement.

## Layups

`E` while running toward the rim or while positioned appropriately near the rim.

Possible finishing moves:

- Regular layup
- Jelly layup
- Floater
- Hook shot

### Context-based finishing

```text
Far from rim
    ↓
Jump shot

Mid-range
    ↓
Jump shot / pull-up / fadeaway

Close to rim
    ↓
Layup / floater / hook

Driving toward rim
    ↓
Layup / finishing animation
```

This creates a unified shooting/finishing control instead of requiring separate buttons for every shot type.

---

# 8. Dunking

## Input

`Double-click`

A dunk can be triggered when:

1. The player is sufficiently close to the rim.
2. The player has enough momentum/position to attempt a dunk.
3. The player's build and/or attributes allow the dunk.

The initial design specifically uses a **double-click** to distinguish dunking from normal shooting.

### Potential future variables

Dunk success could eventually depend on:

- Dunk attribute
- Vertical
- Height
- Distance from rim
- Running momentum
- Defensive pressure
- Timing

These should be considered only after the basic dunk system feels good.

---

# 9. Defense

Defense should use equally simple controls while providing enough options for skilled players.

| Input | Action |
|---|---|
| `G` | Guard |
| `R` | Steal |
| `Double-click` | Block |

## Guard

`G` activates the player's primary guarding stance.

The purpose is to make defensive positioning easier and more controlled.

Possible behavior:

- Reduce unnecessary movement.
- Keep the player facing the opponent.
- Improve lateral defensive movement.
- Help maintain defensive positioning.

The exact implementation should be tested because an automatic-facing system could become too powerful.

## Steal

`R` attempts a steal.

A steal should not be guaranteed simply because the player pressed `R`.

Success should depend on factors such as:

- Timing
- Distance
- Ball position
- Defender positioning
- Ball-handler movement
- Defensive attributes

This prevents repeated button pressing from becoming the optimal strategy.

## Block

`Double-click` while defending attempts a block.

A block should be context-sensitive:

```text
Defending
   +
Double-click
   +
Opponent shooting/finishing
   ↓
Block attempt
```

Timing and positioning should determine the result.

---

# 10. Passing

## Pass Input

Passing uses a **press + swipe** gesture.

The player presses the pass input and swipes toward the intended teammate.

```text
Press pass
    +
Swipe toward teammate
    ↓
Pass toward selected direction
```

This should make passing feel more direct than selecting a teammate from a menu.

### Design goals

- Fast passing.
- Directional control.
- Minimal UI.
- Easy teammate targeting.
- Ability to make quick passes during movement.

Potential future additions:

- Bounce pass
- Lob pass
- Alley-oop
- Pass fakes

These should not be part of the initial prototype unless the basic passing system already works reliably.

---

# 11. Player Builds

Players can create their own basketball build.

The build system determines the player's physical profile and attributes.

## Height

Player height can range from:

**5'9" → 7'2"**

Height should have meaningful gameplay consequences.

Potential effects:

- Reach
- Finishing
- Blocking
- Rebounding
- Speed
- Acceleration
- Defensive coverage
- Shot creation

Height should involve trade-offs rather than simply making taller builds objectively better.

---

# 12. Attributes

Attributes range from:

**30 → 99**

A player's attributes determine their strengths and weaknesses.

Potential attribute categories:

### Offense

- Close Shot
- Layup
- Dunk
- Mid-Range
- Three-Point
- Free Throw
- Ball Handle
- Passing

### Defense

- Perimeter Defense
- Interior Defense
- Steal
- Block
- Defensive Rebound

### Physical

- Speed
- Acceleration
- Strength
- Vertical
- Stamina

The final attribute list should be kept relatively small at first.

Too many attributes would make the build system unnecessarily complicated.

---

# 13. Overall Rating

Players start at:

**60 OVR**

The overall rating represents the general strength of the build.

It should be calculated from the player's attributes rather than being freely assigned.

Example:

```text
New Player
    ↓
60 OVR
    ↓
Play games
    ↓
Earn XP
    ↓
Level up
    ↓
Receive Skill Points
    ↓
Increase attributes
    ↓
Higher OVR
```

The exact OVR formula should be designed later.

---

# 14. Progression

Playing the game increases the player's **level**.

Leveling up gives the player **Skill Points**.

Skill Points can be spent to improve attributes.

### Progression loop

```text
Play
 ↓
Earn XP
 ↓
Level Up
 ↓
Skill Points
 ↓
Upgrade Attributes
 ↓
Improve Build
```

The progression system should reward continued play without making new players completely helpless against experienced players.

---

# 15. Build Philosophy

RoHoops should encourage different playstyles.

For example:

### Small Guard

- Lower height
- High speed
- High ball handling
- Strong shooting
- Lower interior defense

### Wing

- Medium height
- Balanced attributes
- Strong perimeter defense
- Good shooting and finishing

### Big

- High height
- Strong interior defense
- Strong rebounding
- Strong finishing
- Lower speed and ball handling

These are examples rather than fixed classes.

The player should be able to distribute their attributes freely enough to create their own build.

---

# 16. Map / Court Design

The map should intentionally remain simple.

## Design Principle

**Gameplay > Visual Complexity**

The environment does not need to be large or visually elaborate.

### Goals

- High FPS.
- Low hardware requirements.
- Minimal distractions.
- Fast loading.
- Clear player visibility.
- Focus on basketball mechanics.

The initial map can be essentially a clean basketball court with only the necessary surrounding geometry.

Avoid adding large environments, unnecessary NPCs, decorative systems, or complex visual effects until the core gameplay is proven.

---

# 17. Performance Philosophy

Performance should be considered a core design constraint rather than something optimized at the end.

The game should prioritize:

- Stable FPS
- Low input latency
- Fast response to controls
- Simple collision
- Lightweight environments
- Efficient animations
- Minimal unnecessary effects

This is particularly important because RoHoops relies heavily on **timing and mechanical precision**.

A visually impressive game with input delay would undermine the main gameplay concept.

---

# 18. Core Prototype

Before building the complete progression system, the first playable prototype should focus only on whether the basketball feels good.

## Prototype 1

Implement:

- Simple basketball court
- Fixed camera
- One player
- WASD / arrow movement
- Shift running
- Basic dribbling
- Mouse/trackpad skill movement
- `E` shooting
- Basic layup
- Basic dunk
- Basic defense
- Basic steal
- Basic block

The objective is not to make a complete game.

The objective is to answer:

> **Is RoHoops fun when all the menus, progression, cosmetics, and extra systems are removed?**

If the answer is yes, additional systems can be built around the core.

---

# 19. Suggested Development Order

## Phase 1 — Movement

Build:

1. Player controller
2. WASD / arrow movement
3. Running
4. Acceleration/deceleration
5. Basic animations
6. Fixed camera

**Goal:** movement should already feel responsive.

---

## Phase 2 — Ball Handling

Build:

1. Ball possession
2. Basic dribbling
3. Mouse/trackpad directional skills
4. Crossover
5. Direction changes
6. Ball/player synchronization

**Goal:** dribbling should feel responsive and controllable.

---

## Phase 3 — Shooting & Finishing

Build:

1. `E` shooting
2. Shot detection
3. Shot timing
4. Standing shots
5. Pull-ups
6. Fadeaways
7. Step-backs
8. Side shots
9. Layups
10. Floaters
11. Hook shots
12. Dunking

**Goal:** the player should be able to create different shots naturally from movement.

---

## Phase 4 — Defense

Build:

1. Guard
2. Defensive movement
3. Steal
4. Block
5. Defensive collision
6. Shot contest
7. Defensive reactions

**Goal:** defense should be as mechanically meaningful as offense.

---

## Phase 5 — Passing

Build:

1. Teammate detection
2. Directional pass
3. Press + swipe input
4. Pass animations
5. Pass interception
6. Pass accuracy

---

## Phase 6 — Game Rules

Once the individual mechanics work:

- Teams
- Scoring
- Possession
- Out of bounds
- Shot clock
- Fouls
- Game timer
- Win/loss conditions
- Basic matchmaking/game flow

---

## Phase 7 — Builds & Progression

Only after the core gameplay works:

- Player creation
- Height
- Attributes
- 60 OVR starting point
- XP
- Levels
- Skill Points
- Attribute upgrades
- OVR calculation

---

# 20. Important Design Principle: Context Over Buttons

One of the strongest ideas in the current concept is that **the same input can produce different actions depending on context**.

For example:

```text
E
│
├── Outside shooting range
│      └── Jump shot
│
├── Moving toward rim
│      └── Layup
│
├── Moving backward
│      └── Fadeaway / step-back
│
├── Moving sideways
│      └── Side shot
│
└── Near rim + appropriate conditions
       └── Finishing move
```

Likewise:

```text
Double-click
│
├── Offense + near rim
│      └── Dunk
│
└── Defense + opponent shooting
       └── Block
```

This keeps the control scheme compact while allowing a large number of basketball actions.

---

# 21. What Should NOT Be Built First

Avoid starting with:

- Large maps
- Detailed cosmetics
- Complex menus
- Large inventories
- Complicated matchmaking
- Huge attribute systems
- Hundreds of animations
- Advanced monetization
- Extensive progression
- NPC crowds
- Excessive visual effects

These systems can be added later.

The first question is whether **movement + dribbling + shooting + defense** are satisfying.

---

# 22. Initial Minimum Viable Game

The first genuinely playable version of RoHoops should contain:

### Player

- Customizable basic player
- Height
- Basic attributes

### Movement

- WASD / arrows
- Running
- Fixed camera

### Offense

- Dribbling
- Skill moves
- Shooting
- Layups
- Dunking
- Passing

### Defense

- Guarding
- Stealing
- Blocking

### Environment

- One simple basketball court

### Game

- Basic opponent
- Scoring
- Possession
- Win/loss condition

Everything else can come afterward.

---

# 23. Design Goal

The final experience should feel like:

> **Simple controls, difficult execution.**

A new player should be able to understand the controls quickly, while an experienced player can use movement, timing, positioning, and skill moves to become significantly better.

RoHoops should not try to win through the number of mechanics it contains.

It should win through **how well those mechanics connect together**.
