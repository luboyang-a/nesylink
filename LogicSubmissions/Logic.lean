namespace NesyLinkFormalization

/-!
  Symbolic formalization for the NesyLink mathematical-logic project.

  This file formalizes the symbolic planning layer used by the submitted
  search-based Python agent.

  The Python agent first extracts a symbolic Scene from pixels, then performs
  target selection and BFS-style path planning over tile positions.  This Lean
  file does not prove raw-pixel recognition correct and does not mechanically
  verify the Python implementation line by line.  Instead, it proves the
  planner-level contract used after visual extraction:

  * legal actions belong to the official action space;
  * safe tiles are inside the map and avoid walls/traps/monsters/chests/NPCs/
    unbridged gaps;
  * accepted paths are safe;
  * symbolic state transitions for movement, key chests, sword chests, combat,
    switches, buttons, and exits satisfy their intended postconditions;
  * task-level symbolic stages can be composed into successful plans.

  Some game-engine details are intentionally abstracted:
  * monster combat is modeled by the postcondition of a successful combat
    subroutine, not by individual animation ticks or monster HP;
  * chest rewards are represented by ChestLoot instead of assuming every chest
    gives a key;
  * buttons are modeled as being triggered after the player moves onto the
    button tile, matching the Python policy's "walk to button" behavior;
  * the final task objective is represented by a completed flag set by a final
    exit rule.
-/

/- -------------------------------------------------------------------------- -/
/- Basic objects                                                              -/
/- -------------------------------------------------------------------------- -/

abbrev Position := Nat × Nat

def mapWidth : Nat := 10
def mapHeight : Nat := 8

def inBounds (p : Position) : Prop :=
  p.1 < mapWidth ∧ p.2 < mapHeight

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

def actionForDir : Dir → Action
  | Dir.north => Action.up
  | Dir.south => Action.down
  | Dir.west => Action.left
  | Dir.east => Action.right

def manhattan (a b : Position) : Nat :=
  let dx := if a.1 ≤ b.1 then b.1 - a.1 else a.1 - b.1
  let dy := if a.2 ≤ b.2 then b.2 - a.2 else a.2 - b.2
  dx + dy

def adjacent (a b : Position) : Prop :=
  manhattan a b = 1

def nextPosition (p : Position) : Action → Position
  | Action.up => (p.1, p.2 - 1)
  | Action.down => (p.1, p.2 + 1)
  | Action.left => (p.1 - 1, p.2)
  | Action.right => (p.1 + 1, p.2)
  | _ => p

/- -------------------------------------------------------------------------- -/
/- Inventory, loot, and symbolic state                                        -/
/- -------------------------------------------------------------------------- -/

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

inductive ChestLoot where
  | none
  | key
  | gold
  | sword
  | shield
  deriving DecidableEq, Repr

def applyLoot (loot : ChestLoot) (inv : Inventory) : Inventory :=
  match loot with
  | ChestLoot.none => inv
  | ChestLoot.key => { inv with keys := inv.keys + 1 }
  | ChestLoot.gold => { inv with gold := inv.gold + 1 }
  | ChestLoot.sword => { inv with hasSword := true }
  | ChestLoot.shield => { inv with hasShield := true }

structure ChestRule where
  pos : Position
  loot : ChestLoot
  deriving DecidableEq, Repr

structure ExitRule where
  pos : Position
  direction : Dir
  target : Position
  requiredKeys : Nat := 0
  requiresSword : Bool := false
  requiresAllMonstersDefeated : Bool := false
  completeTask : Bool := false
  deriving DecidableEq, Repr

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
  completed : Bool
  inventory : Inventory
  deriving DecidableEq, Repr

/- -------------------------------------------------------------------------- -/
/- Safety                                                                     -/
/- -------------------------------------------------------------------------- -/

def isSafe (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  p ∉ s.traps ∧
  p ∉ s.monsters ∧
  p ∉ s.chests ∧
  p ∉ s.npcs ∧
  (p ∉ s.gaps ∨ p ∈ s.bridges)

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

/- -------------------------------------------------------------------------- -/
/- Automatic button trigger after movement                                    -/
/- -------------------------------------------------------------------------- -/

/-
  In the Python policy, buttons are handled by returning ("walk", button).
  Therefore the button is triggered by reaching the button tile, not by
  pressing ACTION_A.  This helper models the automatic symbolic update after
  a movement lands on a button.
-/
def afterMoveTo (s : SymbolicState) (p : Position) : SymbolicState :=
  if p ∈ s.buttons then
    { s with player := p, pressedButtons := p :: s.pressedButtons }
  else
    { s with player := p }

theorem afterMoveTo_player
    {s : SymbolicState} {p : Position} :
    (afterMoveTo s p).player = p := by
  by_cases hb : p ∈ s.buttons
  · simp [afterMoveTo, hb]
  · simp [afterMoveTo, hb]

def ButtonPressed (b : Position) (s : SymbolicState) : Prop :=
  b ∈ s.pressedButtons

theorem afterMoveTo_button_pressed
    {s : SymbolicState} {b : Position}
    (hb : b ∈ s.buttons) :
    ButtonPressed b (afterMoveTo s b) := by
  unfold ButtonPressed
  simp [afterMoveTo, hb]

/- -------------------------------------------------------------------------- -/
/- Preconditions for interactions                                             -/
/- -------------------------------------------------------------------------- -/

def canOpenChest (s : SymbolicState) (c : ChestRule) : Prop :=
  c.pos ∈ s.chests ∧ adjacent s.player c.pos

def canStartCombat (s : SymbolicState) (m : Position) : Prop :=
  m ∈ s.monsters ∧ adjacent s.player m ∧ s.inventory.hasSword = true

def canToggleSwitch (s : SymbolicState) (sw : Position) : Prop :=
  sw ∈ s.switches ∧ adjacent s.player sw

def canUseExit (s : SymbolicState) (e : ExitRule) : Prop :=
  e.pos ∈ s.exits ∧
  s.player = e.pos ∧
  e.requiredKeys ≤ s.inventory.keys ∧
  (e.requiresSword = true → s.inventory.hasSword = true) ∧
  (e.requiresAllMonstersDefeated = true → s.monsters = [])

theorem canOpenChest_chest_mem
    {s : SymbolicState} {c : ChestRule}
    (h : canOpenChest s c) :
    c.pos ∈ s.chests := by
  exact h.1

theorem canOpenChest_adjacent
    {s : SymbolicState} {c : ChestRule}
    (h : canOpenChest s c) :
    adjacent s.player c.pos := by
  exact h.2

theorem canStartCombat_monster_mem
    {s : SymbolicState} {m : Position}
    (h : canStartCombat s m) :
    m ∈ s.monsters := by
  exact h.1

theorem canStartCombat_hasSword
    {s : SymbolicState} {m : Position}
    (h : canStartCombat s m) :
    s.inventory.hasSword = true := by
  exact h.2.2

theorem canToggleSwitch_switch_mem
    {s : SymbolicState} {sw : Position}
    (h : canToggleSwitch s sw) :
    sw ∈ s.switches := by
  exact h.1

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

/- -------------------------------------------------------------------------- -/
/- State transformers                                                         -/
/- -------------------------------------------------------------------------- -/

def afterOpenChest (s : SymbolicState) (c : ChestRule) : SymbolicState :=
  { s with
    chests := s.chests.erase c.pos,
    inventory := applyLoot c.loot s.inventory }

def afterDefeatMonster (s : SymbolicState) (m : Position) : SymbolicState :=
  { s with monsters := s.monsters.erase m }

def afterToggleSwitch (s : SymbolicState) (_sw : Position) : SymbolicState :=
  { s with switchCount := s.switchCount + 1 }

def afterUseExit (s : SymbolicState) (e : ExitRule) : SymbolicState :=
  { s with
    player := e.target,
    completed := if e.completeTask then true else s.completed }

theorem afterOpenKeyChest_keys
    {s : SymbolicState} {c : ChestRule}
    (hLoot : c.loot = ChestLoot.key) :
    (afterOpenChest s c).inventory.keys = s.inventory.keys + 1 := by
  cases c with
  | mk pos loot =>
      cases loot <;> simp [afterOpenChest, applyLoot] at hLoot ⊢

theorem afterOpenSwordChest_hasSword
    {s : SymbolicState} {c : ChestRule}
    (hLoot : c.loot = ChestLoot.sword) :
    (afterOpenChest s c).inventory.hasSword = true := by
  cases c with
  | mk pos loot =>
      cases loot <;> simp [afterOpenChest, applyLoot] at hLoot ⊢

theorem afterOpenChest_player
    {s : SymbolicState} {c : ChestRule} :
    (afterOpenChest s c).player = s.player := by
  rfl

theorem afterDefeatMonster_player
    {s : SymbolicState} {m : Position} :
    (afterDefeatMonster s m).player = s.player := by
  rfl

theorem afterToggleSwitch_count
    {s : SymbolicState} {sw : Position} :
    (afterToggleSwitch s sw).switchCount = s.switchCount + 1 := by
  rfl

theorem afterUseExit_player
    {s : SymbolicState} {e : ExitRule} :
    (afterUseExit s e).player = e.target := by
  rfl

theorem afterUseExit_completed
    {s : SymbolicState} {e : ExitRule}
    (hComplete : e.completeTask = true) :
    (afterUseExit s e).completed = true := by
  simp [afterUseExit, hComplete]

/- -------------------------------------------------------------------------- -/
/- Step and Exec semantics                                                    -/
/- -------------------------------------------------------------------------- -/

/-
  Combat is abstracted as a completed combat subroutine.  In the real game, a
  monster may require multiple ACTION_A commands and animation ticks.  The rule
  below represents the postcondition after the combat routine succeeds: the
  monster is removed from the symbolic monster list.
-/
inductive Step : SymbolicState → Action → SymbolicState → Prop where
  | moveSafe
      {s : SymbolicState} {a : Action} :
      a ∈ moveActions →
      isSafe s (nextPosition s.player a) →
      Step s a (afterMoveTo s (nextPosition s.player a))
  | moveBlocked
      {s : SymbolicState} {a : Action} :
      a ∈ moveActions →
      ¬ isSafe s (nextPosition s.player a) →
      Step s a s
  | openChest
      {s : SymbolicState} {c : ChestRule} :
      canOpenChest s c →
      Step s Action.attack (afterOpenChest s c)
  | defeatMonster
      {s : SymbolicState} {m : Position} :
      canStartCombat s m →
      Step s Action.attack (afterDefeatMonster s m)
  | toggleSwitch
      {s : SymbolicState} {sw : Position} :
      canToggleSwitch s sw →
      Step s Action.attack (afterToggleSwitch s sw)
  | useExit
      {s : SymbolicState} {e : ExitRule} :
      canUseExit s e →
      Step s (actionForDir e.direction) (afterUseExit s e)
  | wait
      {s : SymbolicState} :
      Step s Action.wait s
  | shield
      {s : SymbolicState} :
      Step s Action.shield s

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
    SafeState (afterMoveTo s (nextPosition s.player a)) := by
  by_cases hb : nextPosition s.player a ∈ s.buttons
  · simp [SafeState, afterMoveTo, hb]
    exact ⟨isSafe_inBounds hsafe, isSafe_not_wall hsafe, isSafe_not_trap hsafe⟩
  · simp [SafeState, afterMoveTo, hb]
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

theorem exec_open_chest
    {s : SymbolicState} {c : ChestRule}
    (h : canOpenChest s c) :
    Exec s [Action.attack] (afterOpenChest s c) := by
  exact Exec.cons (Step.openChest h) Exec.nil

theorem exec_defeat_monster
    {s : SymbolicState} {m : Position}
    (h : canStartCombat s m) :
    Exec s [Action.attack] (afterDefeatMonster s m) := by
  exact Exec.cons (Step.defeatMonster h) Exec.nil

theorem exec_toggle_switch
    {s : SymbolicState} {sw : Position}
    (h : canToggleSwitch s sw) :
    Exec s [Action.attack] (afterToggleSwitch s sw) := by
  exact Exec.cons (Step.toggleSwitch h) Exec.nil

theorem exec_use_exit
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e) :
    Exec s [actionForDir e.direction] (afterUseExit s e) := by
  exact Exec.cons (Step.useExit h) Exec.nil

/- -------------------------------------------------------------------------- -/
/- Planner contract                                                           -/
/- -------------------------------------------------------------------------- -/

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

def ValidPath (s : SymbolicState) : List Position → Prop
  | [] => True
  | [_] => True
  | p :: q :: rest =>
      adjacent p q ∧ isSafe s q ∧ ValidPath s (q :: rest)

/-
  PathPlanSound is the contract expected from the Python BFS layer.
  Lean proves properties of any path satisfying this contract.  It does not
  mechanically prove that the Python function bfs always returns such a path.
-/
structure PathPlanSound
    (s : SymbolicState)
    (start : Position)
    (goals : List Position)
    (path : List Position) : Prop where
  starts : StartsAt start path
  valid : ValidPath s path
  reaches : EndsIn goals path

def SafePath (s : SymbolicState) (path : List Position) : Prop :=
  ValidPath s path

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

/- -------------------------------------------------------------------------- -/
/- Goal predicates                                                            -/
/- -------------------------------------------------------------------------- -/

def ReachesPosition (p : Position) (s : SymbolicState) : Prop :=
  s.player = p

def HasAtLeastKeys (n : Nat) (s : SymbolicState) : Prop :=
  n ≤ s.inventory.keys

def HasSword (s : SymbolicState) : Prop :=
  s.inventory.hasSword = true

def NoMonsters (s : SymbolicState) : Prop :=
  s.monsters = []

def ChestCleared (c : ChestRule) (s : SymbolicState) : Prop :=
  c.pos ∉ s.chests

def MonsterCleared (m : Position) (s : SymbolicState) : Prop :=
  m ∉ s.monsters

def SwitchCountAtLeast (n : Nat) (s : SymbolicState) : Prop :=
  n ≤ s.switchCount

def TaskCompletedByExit (e : ExitRule) (s : SymbolicState) : Prop :=
  s.player = e.target ∧ s.completed = true

def SuccessfulPlan
    (s0 : SymbolicState)
    (actions : List Action)
    (goal : SymbolicState → Prop) : Prop :=
  ∃ finalState : SymbolicState,
    Exec s0 actions finalState ∧ goal finalState

theorem open_key_chest_gives_key
    {s : SymbolicState} {c : ChestRule}
    (_hOpen : canOpenChest s c)
    (hLoot : c.loot = ChestLoot.key) :
    HasAtLeastKeys (s.inventory.keys + 1) (afterOpenChest s c) := by
  unfold HasAtLeastKeys
  rw [afterOpenKeyChest_keys hLoot]
  exact Nat.le_refl (s.inventory.keys + 1)

theorem open_sword_chest_gives_sword
    {s : SymbolicState} {c : ChestRule}
    (_hOpen : canOpenChest s c)
    (hLoot : c.loot = ChestLoot.sword) :
    HasSword (afterOpenChest s c) := by
  unfold HasSword
  exact afterOpenSwordChest_hasSword hLoot

/- -------------------------------------------------------------------------- -/
/- Task-level abstract composition theorems                                   -/
/- -------------------------------------------------------------------------- -/

namespace Task1

theorem task1_strategy_correct
    {s0 s1 s2 : SymbolicState}
    {keyChest : ChestRule}
    {exitRule : ExitRule}
    {goChest goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
    (hGoChest : Exec s0 goChest s1)
    (hOpen : canOpenChest s1 keyChest)
    (hGoExit : Exec (afterOpenChest s1 keyChest) goExit s2)
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
      (exec_append (exec_open_chest hOpen)
        (exec_append hGoExit
          (exec_use_exit hExit)))

  · unfold TaskCompletedByExit
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

theorem task1_open_key_chest_gives_key
    {s : SymbolicState} {keyChest : ChestRule}
    (hOpen : canOpenChest s keyChest)
    (hLoot : keyChest.loot = ChestLoot.key) :
    HasAtLeastKeys (s.inventory.keys + 1) (afterOpenChest s keyChest) := by
  exact open_key_chest_gives_key hOpen hLoot

end Task1

namespace Task2

theorem task2_strategy_correct
    {s0 s1 s2 s3 : SymbolicState}
    {monster : Position}
    {keyChest : ChestRule}
    {exitRule : ExitRule}
    {goMonster goChest goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
    (hGoMonster : Exec s0 goMonster s1)
    (hCombat : canStartCombat s1 monster)
    (hGoChest : Exec (afterDefeatMonster s1 monster) goChest s2)
    (hOpen : canOpenChest s2 keyChest)
    (hGoExit : Exec (afterOpenChest s2 keyChest) goExit s3)
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
      (exec_append (exec_defeat_monster hCombat)
        (exec_append hGoChest
          (exec_append (exec_open_chest hOpen)
            (exec_append hGoExit
              (exec_use_exit hExit)))))

  · unfold TaskCompletedByExit
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

theorem task2_combat_updates_monster_list
    {s : SymbolicState} {monster : Position}
    (_hCombat : canStartCombat s monster) :
    (afterDefeatMonster s monster).monsters = s.monsters.erase monster := by
  unfold afterDefeatMonster
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
    {monster : Position}
    {keyChest : ChestRule}
    {exitRule : ExitRule}
    {goMonster goChest goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
    (hGoMonster : Exec s0 goMonster s1)
    (hCombat : canStartCombat s1 monster)
    (hGoChest : Exec (afterDefeatMonster s1 monster) goChest s2)
    (hOpen : canOpenChest s2 keyChest)
    (hGoExit : Exec (afterOpenChest s2 keyChest) goExit s3)
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
      (exec_append (exec_defeat_monster hCombat)
        (exec_append hGoChest
          (exec_append (exec_open_chest hOpen)
            (exec_append hGoExit
              (exec_use_exit hExit)))))

  · unfold TaskCompletedByExit
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

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
  unfold SwitchCountAtLeast
  rw [afterToggleSwitch_count]
  exact Nat.le_refl (s.switchCount + 1)

theorem task4_open_sword_chest_gives_sword
    {s : SymbolicState} {swordChest : ChestRule}
    (hOpen : canOpenChest s swordChest)
    (hLoot : swordChest.loot = ChestLoot.sword) :
    HasSword (afterOpenChest s swordChest) := by
  exact open_sword_chest_gives_sword hOpen hLoot

theorem task4_bridge_stage_strategy_correct
    {s0 s1 s2 : SymbolicState}
    {exitRule : ExitRule}
    {prepareBridge goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
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
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

theorem task4_switch_then_exit_strategy_correct
    {s0 s1 s2 : SymbolicState}
    {sw : Position}
    {exitRule : ExitRule}
    {goSwitch goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
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
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

end Task4

namespace Task5

/-
  Task5 is intentionally modeled as a multi-stage symbolic plan rather than a
  concrete fixed map.  The theorem below says: if the topology exploration /
  button / chest / combat / exit stages are executable and the final exit is
  a completing exit, then the composed action list is a successful plan.

  This matches the report claim: Lean verifies the symbolic planner layer and
  final-goal composition, while empirical evaluation checks pixel extraction
  and robustness on original/spatial/color variants.
-/
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
    {s0 s1 s2 s3 : SymbolicState}
    {keyChest : ChestRule}
    {exitRule : ExitRule}
    {goButton goChest goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
    (hGoButton : Exec s0 goButton s1)
    (hGoChest : Exec s1 goChest s2)
    (hOpen : canOpenChest s2 keyChest)
    (hGoExit : Exec (afterOpenChest s2 keyChest) goExit s3)
    (hExit : canUseExit s3 exitRule) :
    ∃ plan,
      SuccessfulPlan s0 plan (TaskCompletedByExit exitRule) := by
  let plan :=
    goButton ++
      (goChest ++
        ([Action.attack] ++
          (goExit ++ [actionForDir exitRule.direction])))

  refine ⟨plan, ?_⟩
  unfold SuccessfulPlan
  refine ⟨afterUseExit s3 exitRule, ?_, ?_⟩

  · exact exec_append hGoButton
      (exec_append hGoChest
        (exec_append (exec_open_chest hOpen)
          (exec_append hGoExit
            (exec_use_exit hExit))))

  · unfold TaskCompletedByExit
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

theorem task5_exit_final_strategy_correct
    {s0 s1 s2 s3 s4 : SymbolicState}
    {exitRule : ExitRule}
    {stage1 stage2 stage3 goExit : List Action}
    (hExitComplete : exitRule.completeTask = true)
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
    constructor
    · exact afterUseExit_player
    · exact afterUseExit_completed hExitComplete

end Task5

end NesyLinkFormalization
