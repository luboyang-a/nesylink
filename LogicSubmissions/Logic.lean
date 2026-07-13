namespace NesyLinkFormalization

/-!
  Symbolic formalization for the NesyLink mathematical-logic project.

  This file formalizes the symbolic layer used by the submitted search-based
  agent.  The Python agent first extracts a symbolic Scene from pixels, then
  performs target selection and BFS-style path planning over tile positions.

  This Lean file does not prove raw-pixel recognition correct.  Instead, it
  proves properties of the symbolic planner after visual extraction:
  positions, actions, safety, executable action sequences, valid paths, legal
  actions, and abstract task-level compositions.

  Concrete task maps are intentionally not encoded.  Task-level theorems are
  stated over generic executable stages, matching the way the Python policy
  composes search stages such as "go to chest", "open chest", "go to exit",
  "use exit", "press button", or "toggle switch".
-/

/- Basic grid position. NesyLink maps use a 10 x 8 tile grid. -/
abbrev Position := Nat × Nat

def mapWidth : Nat := 10
def mapHeight : Nat := 8

def inBounds (p : Position) : Prop :=
  p.1 < mapWidth ∧ p.2 < mapHeight

/- Actions used by the symbolic planner.

   These correspond to the official seven-action interface:
   wait, four movement directions, interact/attack, and shield.
-/
inductive Action where
  | wait
  | up
  | down
  | left
  | right
  | attack
  | shield
  deriving DecidableEq, Repr

def moveActions : List Action :=
  [Action.up, Action.down, Action.left, Action.right]

def isMoveAction (a : Action) : Prop :=
  a ∈ moveActions

/- Legal action predicate.

   Since Action is an inductive type with exactly seven constructors, every
   value of type Action is legal.  This corresponds to the fact that the Python
   policy only outputs action IDs in the official action space 0..6.
-/
def LegalAction (a : Action) : Prop :=
  a = Action.wait ∨
  a = Action.up ∨
  a = Action.down ∨
  a = Action.left ∨
  a = Action.right ∨
  a = Action.attack ∨
  a = Action.shield

def LegalPlan (plan : List Action) : Prop :=
  ∀ a, a ∈ plan → LegalAction a

theorem every_action_legal (a : Action) : LegalAction a := by
  cases a <;> simp [LegalAction]

theorem every_plan_legal (plan : List Action) : LegalPlan plan := by
  intro a _ha
  exact every_action_legal a

/- Cardinal directions for exits and room graph edges. -/
inductive Dir where
  | north
  | south
  | west
  | east
  deriving DecidableEq, Repr

def opposite : Dir → Dir
  | Dir.north => Dir.south
  | Dir.south => Dir.north
  | Dir.west => Dir.east
  | Dir.east => Dir.west

theorem opposite_involutive (d : Dir) :
    opposite (opposite d) = d := by
  cases d <;> rfl

/- Manhattan distance and adjacency. -/
def manhattan (a b : Position) : Nat :=
  let dx := if a.1 ≤ b.1 then b.1 - a.1 else a.1 - b.1
  let dy := if a.2 ≤ b.2 then b.2 - a.2 else a.2 - b.2
  dx + dy

def adjacent (a b : Position) : Prop :=
  manhattan a b = 1

/- One-tile symbolic movement.

   Nat subtraction is saturating in Lean, so moving left from x = 0 gives x = 0.
   Legal movement is guarded by isSafe.
-/
def nextPosition (p : Position) : Action → Position
  | Action.up => (p.1, p.2 - 1)
  | Action.down => (p.1, p.2 + 1)
  | Action.left => (p.1 - 1, p.2)
  | Action.right => (p.1 + 1, p.2)
  | _ => p

/- Inventory abstraction.

   This matches the safe information used by the Python agent: keys, gold, and
   equipped tools such as sword/shield.  Hidden health is intentionally not
   modeled here, because the submitted safe policy does not read agent hp.
-/
structure Inventory where
  keys : Nat
  gold : Nat
  hasSword : Bool
  hasShield : Bool
  deriving DecidableEq, Repr

def hasKey (inv : Inventory) : Prop :=
  inv.keys > 0

def noKey (inv : Inventory) : Prop :=
  inv.keys = 0

/- Symbolic state extracted from pixels.

   This is not the full engine state.  It is the planner-level state after
   visual extraction.

   buttons and switches are included because Task4/Task5 require them.
   npcs are included because the Python walkability layer may treat non-player
   occupants as blocked tiles.
-/
structure SymbolicState where
  player : Position
  exits : List Position
  walls : List Position
  traps : List Position
  monsters : List Position
  chests : List Position
  buttons : List Position
  switches : List Position
  npcs : List Position
  gaps : List Position
  bridges : List Position
  pressedButtons : List Position
  switchCount : Nat
  inventory : Inventory
  deriving DecidableEq, Repr

/- A tile is safe/passable for movement if it is:
   - inside the grid;
   - not a wall;
   - not a trap;
   - not occupied by a monster;
   - not occupied by a chest;
   - not occupied by an NPC;
   - not an unbridged gap.

   Exits, buttons, and switches are intentionally not blocked.
-/
def isSafe (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  p ∉ s.traps ∧
  p ∉ s.monsters ∧
  p ∉ s.chests ∧
  p ∉ s.npcs ∧
  (p ∉ s.gaps ∨ p ∈ s.bridges)

/- A basic safe state for the current player position. -/
def SafeState (s : SymbolicState) : Prop :=
  inBounds s.player ∧
  s.player ∉ s.walls ∧
  s.player ∉ s.traps

theorem isSafe_inBounds
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    inBounds p := by
  exact h.1

theorem isSafe_not_wall
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.walls := by
  exact h.2.1

theorem isSafe_not_trap
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.traps := by
  exact h.2.2.1

theorem isSafe_not_monster
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.monsters := by
  exact h.2.2.2.1

theorem isSafe_not_chest
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.chests := by
  exact h.2.2.2.2.1

theorem isSafe_not_npc
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.npcs := by
  exact h.2.2.2.2.2.1

theorem isSafe_gap_or_bridge
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.gaps ∨ p ∈ s.bridges := by
  exact h.2.2.2.2.2.2

theorem safe_player_implies_safe_state
    {s : SymbolicState}
    (h : isSafe s s.player) :
    SafeState s := by
  exact ⟨isSafe_inBounds h, isSafe_not_wall h, isSafe_not_trap h⟩

/- Direction to movement action. -/
def actionForDir : Dir → Action
  | Dir.north => Action.up
  | Dir.south => Action.down
  | Dir.west => Action.left
  | Dir.east => Action.right

/- Abstract exit rule. -/
structure ExitRule where
  pos : Position
  direction : Dir
  target : Position
  requiredKeys : Nat := 0
  requiresSword : Bool := false
  requiresAllMonstersDefeated : Bool := false
  completeTask : Bool := false
  deriving DecidableEq, Repr

def canUseExit (s : SymbolicState) (e : ExitRule) : Prop :=
  e.pos ∈ s.exits ∧
  s.player = e.pos ∧
  e.requiredKeys ≤ s.inventory.keys ∧
  (e.requiresSword = true → s.inventory.hasSword = true) ∧
  (e.requiresAllMonstersDefeated = true → s.monsters = [])

def canOpenChest (s : SymbolicState) (c : Position) : Prop :=
  c ∈ s.chests ∧ adjacent s.player c

def canAttack (s : SymbolicState) (m : Position) : Prop :=
  m ∈ s.monsters ∧ adjacent s.player m ∧ s.inventory.hasSword = true

def canPressButton (s : SymbolicState) (b : Position) : Prop :=
  b ∈ s.buttons ∧ adjacent s.player b

def canToggleSwitch (s : SymbolicState) (sw : Position) : Prop :=
  sw ∈ s.switches ∧ adjacent s.player sw

theorem canUseExit_has_required_keys
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e) :
    e.requiredKeys ≤ s.inventory.keys := by
  exact h.2.2.1

theorem canUseExit_requires_sword
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e)
    (hs : e.requiresSword = true) :
    s.inventory.hasSword = true := by
  exact h.2.2.2.1 hs

theorem canUseExit_requires_monsters_defeated
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e)
    (hm : e.requiresAllMonstersDefeated = true) :
    s.monsters = [] := by
  exact h.2.2.2.2 hm

theorem canOpenChest_chest_mem
    {s : SymbolicState} {c : Position}
    (h : canOpenChest s c) :
    c ∈ s.chests := by
  exact h.1

theorem canOpenChest_adjacent
    {s : SymbolicState} {c : Position}
    (h : canOpenChest s c) :
    adjacent s.player c := by
  exact h.2

theorem canAttack_monster_mem
    {s : SymbolicState} {m : Position}
    (h : canAttack s m) :
    m ∈ s.monsters := by
  exact h.1

theorem canAttack_hasSword
    {s : SymbolicState} {m : Position}
    (h : canAttack s m) :
    s.inventory.hasSword = true := by
  exact h.2.2

theorem canPressButton_button_mem
    {s : SymbolicState} {b : Position}
    (h : canPressButton s b) :
    b ∈ s.buttons := by
  exact h.1

theorem canToggleSwitch_switch_mem
    {s : SymbolicState} {sw : Position}
    (h : canToggleSwitch s sw) :
    sw ∈ s.switches := by
  exact h.1

/- Abstract one-step semantics.

   Action.attack is used as the symbolic interaction action.  Depending on the
   nearby target, it may open a chest, attack a monster, press a button, or
   toggle a switch.
-/
inductive Step : SymbolicState → Action → SymbolicState → Prop where
  | moveSafe
      {s : SymbolicState} {a : Action} :
      a ∈ moveActions →
      isSafe s (nextPosition s.player a) →
      Step s a { s with player := nextPosition s.player a }
  | moveBlocked
      {s : SymbolicState} {a : Action} :
      a ∈ moveActions →
      ¬ isSafe s (nextPosition s.player a) →
      Step s a s
  | openKeyChest
      {s : SymbolicState} {c : Position} :
      canOpenChest s c →
      Step s Action.attack
        { s with
          chests := s.chests.erase c,
          inventory := { s.inventory with keys := s.inventory.keys + 1 } }
  | attackMonster
      {s : SymbolicState} {m : Position} :
      canAttack s m →
      Step s Action.attack
        { s with monsters := s.monsters.erase m }
  | pressButton
      {s : SymbolicState} {b : Position} :
      canPressButton s b →
      Step s Action.attack
        { s with pressedButtons := b :: s.pressedButtons }
  | toggleSwitch
      {s : SymbolicState} {sw : Position} :
      canToggleSwitch s sw →
      Step s Action.attack
        { s with switchCount := s.switchCount + 1 }
  | useExit
      {s : SymbolicState} {e : ExitRule} :
      canUseExit s e →
      Step s (actionForDir e.direction)
        { s with player := e.target }
  | wait
      {s : SymbolicState} :
      Step s Action.wait s
  | shield
      {s : SymbolicState} :
      Step s Action.shield s

/- Multi-step execution. -/
inductive Exec : SymbolicState → List Action → SymbolicState → Prop where
  | nil {s : SymbolicState} :
      Exec s [] s
  | cons {s t u : SymbolicState} {a : Action} {rest : List Action} :
      Step s a t →
      Exec t rest u →
      Exec s (a :: rest) u

theorem safe_move_result_safe_state
    {s : SymbolicState} {a : Action}
    (_ha : a ∈ moveActions)
    (hsafe : isSafe s (nextPosition s.player a)) :
    SafeState { s with player := nextPosition s.player a } := by
  exact ⟨isSafe_inBounds hsafe, isSafe_not_wall hsafe, isSafe_not_trap hsafe⟩

theorem exec_cons_inv
    {s u : SymbolicState} {a : Action} {rest : List Action}
    (h : Exec s (a :: rest) u) :
    ∃ t, Step s a t ∧ Exec t rest u := by
  cases h with
  | cons hstep hexec =>
      exact ⟨_, hstep, hexec⟩

theorem exec_append
    {s t u : SymbolicState} {p q : List Action}
    (hp : Exec s p t)
    (hq : Exec t q u) :
    Exec s (p ++ q) u := by
  induction hp with
  | nil =>
      exact hq
  | cons hstep hexec ih =>
      exact Exec.cons hstep (ih hq)

/- Named state transformers. -/
def afterOpenChest (s : SymbolicState) (c : Position) : SymbolicState :=
  { s with
    chests := s.chests.erase c,
    inventory := { s.inventory with keys := s.inventory.keys + 1 } }

def afterAttackMonster (s : SymbolicState) (m : Position) : SymbolicState :=
  { s with monsters := s.monsters.erase m }

def afterPressButton (s : SymbolicState) (b : Position) : SymbolicState :=
  { s with pressedButtons := b :: s.pressedButtons }

def afterToggleSwitch (s : SymbolicState) (_sw : Position) : SymbolicState :=
  { s with switchCount := s.switchCount + 1 }

def afterUseExit (s : SymbolicState) (e : ExitRule) : SymbolicState :=
  { s with player := e.target }

/- One-step executable actions. -/
theorem exec_open_key_chest
    {s : SymbolicState} {c : Position}
    (h : canOpenChest s c) :
    Exec s [Action.attack] (afterOpenChest s c) := by
  unfold afterOpenChest
  exact Exec.cons (Step.openKeyChest h) Exec.nil

theorem exec_attack_monster
    {s : SymbolicState} {m : Position}
    (h : canAttack s m) :
    Exec s [Action.attack] (afterAttackMonster s m) := by
  unfold afterAttackMonster
  exact Exec.cons (Step.attackMonster h) Exec.nil

theorem exec_press_button
    {s : SymbolicState} {b : Position}
    (h : canPressButton s b) :
    Exec s [Action.attack] (afterPressButton s b) := by
  unfold afterPressButton
  exact Exec.cons (Step.pressButton h) Exec.nil

theorem exec_toggle_switch
    {s : SymbolicState} {sw : Position}
    (h : canToggleSwitch s sw) :
    Exec s [Action.attack] (afterToggleSwitch s sw) := by
  unfold afterToggleSwitch
  exact Exec.cons (Step.toggleSwitch h) Exec.nil

theorem exec_use_exit
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e) :
    Exec s [actionForDir e.direction] (afterUseExit s e) := by
  unfold afterUseExit
  exact Exec.cons (Step.useExit h) Exec.nil

/- State update facts. -/
theorem afterOpenChest_keys
    {s : SymbolicState} {c : Position} :
    (afterOpenChest s c).inventory.keys = s.inventory.keys + 1 := by
  rfl

theorem afterOpenChest_player
    {s : SymbolicState} {c : Position} :
    (afterOpenChest s c).player = s.player := by
  rfl

theorem afterAttackMonster_player
    {s : SymbolicState} {m : Position} :
    (afterAttackMonster s m).player = s.player := by
  rfl

theorem afterPressButton_contains
    {s : SymbolicState} {b : Position} :
    b ∈ (afterPressButton s b).pressedButtons := by
  unfold afterPressButton
  simp

theorem afterToggleSwitch_count
    {s : SymbolicState} {sw : Position} :
    (afterToggleSwitch s sw).switchCount = s.switchCount + 1 := by
  rfl

theorem afterUseExit_player
    {s : SymbolicState} {e : ExitRule} :
    (afterUseExit s e).player = e.target := by
  rfl

/- Planner-level formalization. -/

def StartsAt (start : Position) : List Position → Prop
  | [] => False
  | p :: _ => p = start

def EndsAt (goal : Position) : List Position → Prop
  | [] => False
  | [p] => p = goal
  | _ :: rest => EndsAt goal rest

def EndsIn (goals : List Position) : List Position → Prop
  | [] => False
  | [p] => p ∈ goals
  | _ :: rest => EndsIn goals rest

/- A valid path is a tile-level path where every consecutive pair is adjacent
   and every next tile is safe. -/
def ValidPath (s : SymbolicState) : List Position → Prop
  | [] => True
  | [_] => True
  | p :: q :: rest =>
      adjacent p q ∧ isSafe s q ∧ ValidPath s (q :: rest)

structure PathPlanSound
    (s : SymbolicState)
    (start : Position)
    (goals : List Position)
    (path : List Position) : Prop where
  starts : StartsAt start path
  valid : ValidPath s path
  reaches : EndsIn goals path

theorem sound_plan_starts
    {s : SymbolicState} {start : Position} {goals path : List Position}
    (h : PathPlanSound s start goals path) :
    StartsAt start path := by
  exact h.starts

theorem sound_plan_valid
    {s : SymbolicState} {start : Position} {goals path : List Position}
    (h : PathPlanSound s start goals path) :
    ValidPath s path := by
  exact h.valid

theorem sound_plan_reaches
    {s : SymbolicState} {start : Position} {goals path : List Position}
    (h : PathPlanSound s start goals path) :
    EndsIn goals path := by
  exact h.reaches

theorem validPath_next_adjacent
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    adjacent p q := by
  simp [ValidPath] at h
  exact h.1

theorem validPath_next_safe
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    isSafe s q := by
  simp [ValidPath] at h
  exact h.2.1

theorem validPath_tail
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    ValidPath s (q :: rest) := by
  simp [ValidPath] at h
  exact h.2.2

theorem validPath_next_inBounds
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    inBounds q := by
  exact isSafe_inBounds (validPath_next_safe h)

theorem validPath_next_not_wall
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.walls := by
  exact isSafe_not_wall (validPath_next_safe h)

theorem validPath_next_not_trap
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.traps := by
  exact isSafe_not_trap (validPath_next_safe h)

theorem validPath_next_not_monster
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.monsters := by
  exact isSafe_not_monster (validPath_next_safe h)

theorem validPath_next_not_chest
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.chests := by
  exact isSafe_not_chest (validPath_next_safe h)

theorem validPath_next_not_npc
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.npcs := by
  exact isSafe_not_npc (validPath_next_safe h)

theorem validPath_next_gap_or_bridge
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.gaps ∨ q ∈ s.bridges := by
  exact isSafe_gap_or_bridge (validPath_next_safe h)

def SafePath (s : SymbolicState) (path : List Position) : Prop :=
  ValidPath s path

theorem validPath_is_safePath
    {s : SymbolicState} {path : List Position}
    (h : ValidPath s path) :
    SafePath s path := by
  exact h

theorem sound_plan_is_safe
    {s : SymbolicState} {start : Position} {goals path : List Position}
    (h : PathPlanSound s start goals path) :
    SafePath s path := by
  exact validPath_is_safePath h.valid

theorem sound_plan_next_safe
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    isSafe s q := by
  exact validPath_next_safe h.valid

theorem sound_plan_next_adjacent
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    adjacent p q := by
  exact validPath_next_adjacent h.valid

theorem sound_plan_next_inBounds
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    inBounds q := by
  exact validPath_next_inBounds h.valid

theorem sound_plan_next_not_wall
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.walls := by
  exact validPath_next_not_wall h.valid

theorem sound_plan_next_not_trap
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.traps := by
  exact validPath_next_not_trap h.valid

theorem sound_plan_next_not_monster
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.monsters := by
  exact validPath_next_not_monster h.valid

theorem sound_plan_next_not_chest
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.chests := by
  exact validPath_next_not_chest h.valid

theorem sound_plan_next_gap_or_bridge
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.gaps ∨ q ∈ s.bridges := by
  exact validPath_next_gap_or_bridge h.valid

/- Generic goal predicates. -/

def ReachesPosition (p : Position) (s : SymbolicState) : Prop :=
  s.player = p

def HasAtLeastKeys (n : Nat) (s : SymbolicState) : Prop :=
  n ≤ s.inventory.keys

def NoMonsters (s : SymbolicState) : Prop :=
  s.monsters = []

def ChestCleared (c : Position) (s : SymbolicState) : Prop :=
  c ∉ s.chests

def MonsterCleared (m : Position) (s : SymbolicState) : Prop :=
  m ∉ s.monsters

def ButtonPressed (b : Position) (s : SymbolicState) : Prop :=
  b ∈ s.pressedButtons

def SwitchCountAtLeast (n : Nat) (s : SymbolicState) : Prop :=
  n ≤ s.switchCount

def TaskCompletedByExit (e : ExitRule) (s : SymbolicState) : Prop :=
  s.player = e.target

def SuccessfulPlan
    (s0 : SymbolicState)
    (actions : List Action)
    (goal : SymbolicState → Prop) : Prop :=
  ∃ finalState : SymbolicState,
    Exec s0 actions finalState ∧ goal finalState

/- -------------------------------------------------------------------------- -/
/- Task-level abstract composition theorems.                                  -/
/- -------------------------------------------------------------------------- -/

namespace Task1

theorem task1_strategy_correct
    {s0 s1 s2 : SymbolicState}
    {chest : Position}
    {exitRule : ExitRule}
    {goChest goExit : List Action}
    (hGoChest : Exec s0 goChest s1)
    (hOpen : canOpenChest s1 chest)
    (hGoExit : Exec (afterOpenChest s1 chest) goExit s2)
    (hExit : canUseExit s2 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goChest ++
      ([Action.attack] ++
        (goExit ++ [actionForDir exitRule.direction]))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s2 exitRule, ?_, ?_⟩

  · exact exec_append hGoChest
      (exec_append (exec_open_key_chest hOpen)
        (exec_append hGoExit
          (exec_use_exit hExit)))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

theorem task1_open_chest_gives_key
    {s : SymbolicState} {chest : Position}
    (_hOpen : canOpenChest s chest) :
    HasAtLeastKeys (s.inventory.keys + 1) (afterOpenChest s chest) := by
  simp [HasAtLeastKeys, afterOpenChest]

end Task1

namespace Task2

theorem task2_strategy_correct
    {s0 s1 s2 s3 : SymbolicState}
    {monster chest : Position}
    {exitRule : ExitRule}
    {goMonster goChest goExit : List Action}
    (hGoMonster : Exec s0 goMonster s1)
    (hAttack : canAttack s1 monster)
    (hGoChest : Exec (afterAttackMonster s1 monster) goChest s2)
    (hOpen : canOpenChest s2 chest)
    (hGoExit : Exec (afterOpenChest s2 chest) goExit s3)
    (hExit : canUseExit s3 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goMonster ++
      ([Action.attack] ++
        (goChest ++
          ([Action.attack] ++
            (goExit ++ [actionForDir exitRule.direction]))))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s3 exitRule, ?_, ?_⟩

  · exact exec_append hGoMonster
      (exec_append (exec_attack_monster hAttack)
        (exec_append hGoChest
          (exec_append (exec_open_key_chest hOpen)
            (exec_append hGoExit
              (exec_use_exit hExit)))))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

theorem task2_attack_updates_monsters
    {s : SymbolicState} {monster : Position}
    (_hAttack : canAttack s monster) :
    (afterAttackMonster s monster).monsters = s.monsters.erase monster := by
  unfold afterAttackMonster
  rfl

end Task2

namespace Task3

theorem task3_three_stage_strategy_correct
    {s0 s1 s2 s3 : SymbolicState}
    {exitRule : ExitRule}
    {stage1 stage2 stage3 : List Action}
    (h1 : Exec s0 stage1 s1)
    (h2 : Exec s1 stage2 s2)
    (h3 : Exec s2 stage3 s3)
    (hGoal : TaskCompletedByExit exitRule s3) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan := stage1 ++ (stage2 ++ stage3)

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨s3, ?_, ?_⟩

  · exact exec_append h1
      (exec_append h2 h3)

  · exact hGoal

theorem task3_monster_chest_exit_strategy_correct
    {s0 s1 s2 s3 : SymbolicState}
    {monster chest : Position}
    {exitRule : ExitRule}
    {goMonster goChest goExit : List Action}
    (hGoMonster : Exec s0 goMonster s1)
    (hAttack : canAttack s1 monster)
    (hGoChest : Exec (afterAttackMonster s1 monster) goChest s2)
    (hOpen : canOpenChest s2 chest)
    (hGoExit : Exec (afterOpenChest s2 chest) goExit s3)
    (hExit : canUseExit s3 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goMonster ++
      ([Action.attack] ++
        (goChest ++
          ([Action.attack] ++
            (goExit ++ [actionForDir exitRule.direction]))))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s3 exitRule, ?_, ?_⟩

  · exact exec_append hGoMonster
      (exec_append (exec_attack_monster hAttack)
        (exec_append hGoChest
          (exec_append (exec_open_key_chest hOpen)
            (exec_append hGoExit
              (exec_use_exit hExit)))))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

end Task3

namespace Task4

theorem task4_gap_step_requires_bridge
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (hPath : ValidPath s (p :: q :: rest))
    (hGap : q ∈ s.gaps) :
    q ∈ s.bridges := by
  have hGapOrBridge : q ∉ s.gaps ∨ q ∈ s.bridges :=
    validPath_next_gap_or_bridge hPath
  cases hGapOrBridge with
  | inl hNotGap =>
      exact False.elim (hNotGap hGap)
  | inr hBridge =>
      exact hBridge

theorem task4_toggle_switch_increases_counter
    {s : SymbolicState} {sw : Position}
    (_hSwitch : canToggleSwitch s sw) :
    SwitchCountAtLeast (s.switchCount + 1) (afterToggleSwitch s sw) := by
  simp [SwitchCountAtLeast, afterToggleSwitch]

theorem task4_bridge_stage_strategy_correct
    {s0 s1 s2 : SymbolicState}
    {exitRule : ExitRule}
    {prepareBridge goExit : List Action}
    (hPrepare : Exec s0 prepareBridge s1)
    (hGoExit : Exec s1 goExit s2)
    (hExit : canUseExit s2 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    prepareBridge ++
      (goExit ++ [actionForDir exitRule.direction])

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s2 exitRule, ?_, ?_⟩

  · exact exec_append hPrepare
      (exec_append hGoExit
        (exec_use_exit hExit))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

theorem task4_switch_then_exit_strategy_correct
    {s0 s1 s2  : SymbolicState}
    {sw : Position}
    {exitRule : ExitRule}
    {goSwitch goExit : List Action}
    (hGoSwitch : Exec s0 goSwitch s1)
    (hSwitch : canToggleSwitch s1 sw)
    (hGoExit : Exec (afterToggleSwitch s1 sw) goExit s2)
    (hExit : canUseExit s2 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goSwitch ++
      ([Action.attack] ++
        (goExit ++ [actionForDir exitRule.direction]))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s2 exitRule, ?_, ?_⟩

  · exact exec_append hGoSwitch
      (exec_append (exec_toggle_switch hSwitch)
        (exec_append hGoExit
          (exec_use_exit hExit)))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

end Task4

namespace Task5

theorem task5_press_button_records_button
    {s : SymbolicState} {b : Position}
    (_hButton : canPressButton s b) :
    ButtonPressed b (afterPressButton s b) := by
  unfold ButtonPressed
  exact afterPressButton_contains

theorem task5_four_stage_strategy_correct
    {s0 s1 s2 s3 s4 : SymbolicState}
    {exitRule : ExitRule}
    {stage1 stage2 stage3 stage4 : List Action}
    (h1 : Exec s0 stage1 s1)
    (h2 : Exec s1 stage2 s2)
    (h3 : Exec s2 stage3 s3)
    (h4 : Exec s3 stage4 s4)
    (hGoal : TaskCompletedByExit exitRule s4) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    stage1 ++
      (stage2 ++
        (stage3 ++ stage4))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨s4, ?_, ?_⟩

  · exact exec_append h1
      (exec_append h2
        (exec_append h3 h4))

  · exact hGoal

theorem task5_button_key_exit_strategy_correct
    {s0 s1 s2 s3  : SymbolicState}
    {button chest : Position}
    {exitRule : ExitRule}
    {goButton goChest goExit : List Action}
    (hGoButton : Exec s0 goButton s1)
    (hButton : canPressButton s1 button)
    (hGoChest : Exec (afterPressButton s1 button) goChest s2)
    (hOpen : canOpenChest s2 chest)
    (hGoExit : Exec (afterOpenChest s2 chest) goExit s3)
    (hExit : canUseExit s3 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goButton ++
      ([Action.attack] ++
        (goChest ++
          ([Action.attack] ++
            (goExit ++ [actionForDir exitRule.direction]))))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s3 exitRule, ?_, ?_⟩

  · exact exec_append hGoButton
      (exec_append (exec_press_button hButton)
        (exec_append hGoChest
          (exec_append (exec_open_key_chest hOpen)
            (exec_append hGoExit
              (exec_use_exit hExit)))))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

theorem task5_exit_final_strategy_correct
    {s0 s1 s2 s3 s4 : SymbolicState}
    {exitRule : ExitRule}
    {stage1 stage2 stage3 goExit : List Action}
    (h1 : Exec s0 stage1 s1)
    (h2 : Exec s1 stage2 s2)
    (h3 : Exec s2 stage3 s3)
    (hGoExit : Exec s3 goExit s4)
    (hExit : canUseExit s4 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    stage1 ++
      (stage2 ++
        (stage3 ++
          (goExit ++ [actionForDir exitRule.direction])))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s4 exitRule, ?_, ?_⟩

  · exact exec_append h1
      (exec_append h2
        (exec_append h3
          (exec_append hGoExit
            (exec_use_exit hExit))))

  · unfold TaskCompletedByExit
    unfold afterUseExit
    rfl

end Task5

end NesyLinkFormalization
