namespace NesyLinkFormalization

/-!
  Basic shared definitions for the NesyLink mathematical-logic project.

  This file is intentionally task-independent.

  It contains only the common symbolic vocabulary used by all task proofs:
  positions, actions, directions, map bounds, symbolic state, safety predicate,
  and a few small lemmas.

  Task-specific concepts such as Task1Goal, BridgeState, RoomMemory, or
  concrete task maps should be defined in separate files.
-/

/- Basic grid position.

   NesyLink maps use a 10 x 8 tile grid.
   A position is represented as (x, y), where x is the column and y is the row.
-/
abbrev Position := Nat × Nat

def mapWidth : Nat := 10
def mapHeight : Nat := 8

def inBounds (p : Position) : Prop :=
  p.1 < mapWidth ∧ p.2 < mapHeight

/- Actions used by the symbolic planner.

   These correspond to the seven NesyLink actions at the symbolic level:
   wait, four movement directions, attack/interact, and shield.
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

/- Manhattan distance and adjacency.

   Two tiles are adjacent if their Manhattan distance is exactly 1.
-/
def manhattan (a b : Position) : Nat :=
  let dx := if a.1 ≤ b.1 then b.1 - a.1 else a.1 - b.1
  let dy := if a.2 ≤ b.2 then b.2 - a.2 else a.2 - b.2
  dx + dy

def adjacent (a b : Position) : Prop :=
  manhattan a b = 1

/- One-tile symbolic movement.

   Nat subtraction is saturating in Lean, so moving left from x = 0 gives x = 0.
   This is fine because actual legal movement is later guarded by `inBounds`
   and `isSafe`.
-/
def nextPosition (p : Position) : Action → Position
  | Action.up => (p.1, p.2 - 1)
  | Action.down => (p.1, p.2 + 1)
  | Action.left => (p.1 - 1, p.2)
  | Action.right => (p.1 + 1, p.2)
  | _ => p

/- Inventory abstraction.

   We keep this small because the Python policy is allowed to use inventory
   information such as keys and equipped tools.
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

   This is not the full NesyLink engine state. It is the abstract state used by
   the symbolic planner after visual extraction.

   `gaps` and `bridges` are included for Task4-style bridge/gap reasoning.
   If a task does not use them, the task file can simply set them to [].
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
  gaps : List Position
  bridges : List Position
  health : Nat
  inventory : Inventory
  deriving DecidableEq, Repr

/- A tile is passable/safe for movement if it is:
   - inside the 10 x 8 grid;
   - not a wall;
   - not a trap;
   - not occupied by a monster;
   - not occupied by a chest;
   - not an unbridged gap.

   This corresponds to the Python planner's `is_walkable` / `isSafe` layer.
-/
def isSafe (s : SymbolicState) (p : Position) : Prop :=
  inBounds p ∧
  p ∉ s.walls ∧
  p ∉ s.traps ∧
  p ∉ s.monsters ∧
  p ∉ s.chests ∧
  (p ∉ s.gaps ∨ p ∈ s.bridges)

/- A basic safe state: the player is currently not out of bounds,
   not in a wall, and not on a trap.

   We keep this weaker than `isSafe s s.player`, because in the real game the
   player may stand next to chests/monsters or on exits/buttons.
-/
def SafeState (s : SymbolicState) : Prop :=
  inBounds s.player ∧
  s.player ∉ s.walls ∧
  s.player ∉ s.traps

/- Small reusable lemmas about `isSafe`.

   These are useful in Planner.lean and task-specific proofs.
-/
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

theorem isSafe_gap_or_bridge
    {s : SymbolicState} {p : Position}
    (h : isSafe s p) :
    p ∉ s.gaps ∨ p ∈ s.bridges := by
  exact h.2.2.2.2.2

/- If the player is at a safe tile, then the symbolic state is a SafeState. -/
theorem safe_player_implies_safe_state
    {s : SymbolicState}
    (h : isSafe s s.player) :
    SafeState s := by
  exact ⟨isSafe_inBounds h, isSafe_not_wall h, isSafe_not_trap h⟩

/-!
  Shared symbolic environment semantics.

  The Python engine is pixel-based, but the submitted planner reasons over
  extracted tile positions.  The following definitions model the verifiable
  tile-level layer:

  * safe movement goes to the next tile;
  * blocked movement leaves the player in place;
  * opening a key chest removes the chest and increases the key count;
  * attacking a reachable monster removes it in this abstract combat model;
  * using an exit moves the player to the target spawn when requirements hold.

  Monster hit points, knockback, animation ticks, and raw-pixel extraction are
  intentionally outside this layer.  They should be discussed as abstraction
  boundaries in the report.
-/

def actionForDir : Dir → Action
  | Dir.north => Action.up
  | Dir.south => Action.down
  | Dir.west => Action.left
  | Dir.east => Action.right

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

theorem canUseExit_has_required_keys
    {s : SymbolicState} {e : ExitRule}
    (h : canUseExit s e) :
    e.requiredKeys ≤ s.inventory.keys := by
  exact h.2.2.1

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
      Step s Action.attack { s with monsters := s.monsters.erase m }
  | useExit
      {s : SymbolicState} {e : ExitRule} :
      canUseExit s e →
      Step s (actionForDir e.direction) { s with player := e.target }
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
    SafeState { s with player := nextPosition s.player a } := by
  exact ⟨isSafe_inBounds hsafe, isSafe_not_wall hsafe, isSafe_not_trap hsafe⟩

theorem open_key_chest_increases_keys
    {s : SymbolicState} {c : Position}
    (_h : canOpenChest s c) :
    ({ s with
      chests := s.chests.erase c,
      inventory := { s.inventory with keys := s.inventory.keys + 1 } }).inventory.keys
      = s.inventory.keys + 1 := by
  rfl

theorem attack_monster_removes_monster
    {s : SymbolicState} {m : Position}
    (_h : canAttack s m) :
    ({ s with monsters := s.monsters.erase m }).monsters = s.monsters.erase m := by
  rfl

theorem use_exit_moves_to_target
    {s : SymbolicState} {e : ExitRule}
    (_h : canUseExit s e) :
    ({ s with player := e.target }).player = e.target := by
  rfl

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

/-!
  Shared task-independent state transformers.

  These definitions name the state updates already used by the Step semantics.
  They make task-level proofs shorter and clearer.
-/

def afterOpenChest (s : SymbolicState) (c : Position) : SymbolicState :=
  { s with
    chests := s.chests.erase c,
    inventory := { s.inventory with keys := s.inventory.keys + 1 } }

def afterAttackMonster (s : SymbolicState) (m : Position) : SymbolicState :=
  { s with monsters := s.monsters.erase m }

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

theorem afterUseExit_player
    {s : SymbolicState} {e : ExitRule} :
    (afterUseExit s e).player = e.target := by
  rfl

/-!
  Shared planner-level formalization.

  This file proves task-independent properties of the symbolic path planner.

  It corresponds to the Python layer where the agent:
  1. builds a symbolic Scene from pixels;
  2. computes a BFS/path over tile positions;
  3. moves along the path only if every next tile is safe.

  This file does not formalize raw-pixel extraction and does not formalize
  task-specific goals such as "open all chests" or "rotate bridge twice".
  Those belong in Task1.lean ... Task5.lean.
-/

/- A path starts at a given position. -/
def StartsAt (start : Position) : List Position → Prop
  | [] => False
  | p :: _ => p = start

/- A path ends at a given position. -/
def EndsAt (goal : Position) : List Position → Prop
  | [] => False
  | [p] => p = goal
  | _ :: rest => EndsAt goal rest

/- A path ends in one of a list of goal positions. -/
def EndsIn (goals : List Position) : List Position → Prop
  | [] => False
  | [p] => p ∈ goals
  | _ :: rest => EndsIn goals rest

/- A valid path is a tile-level path where every consecutive pair is adjacent
   and every next tile is safe.

   The first tile is not required to satisfy `isSafe`, because it is the current
   player position. In the actual environment, the player may stand on an exit,
   button, or other special tile. What matters for planning is that every move
   goes to a safe next tile.
-/
def ValidPath (s : SymbolicState) : List Position → Prop
  | [] => True
  | [_] => True
  | p :: q :: rest =>
      adjacent p q ∧ isSafe s q ∧ ValidPath s (q :: rest)

/- A sound path plan from a start position to a list of goal positions. -/
structure PathPlanSound
    (s : SymbolicState)
    (start : Position)
    (goals : List Position)
    (path : List Position) : Prop where
  starts : StartsAt start path
  valid : ValidPath s path
  reaches : EndsIn goals path

/- Basic projections from a sound path plan. -/
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

/- If a path has at least two positions and is valid, then the first movement
   step goes to an adjacent tile. -/
theorem validPath_next_adjacent
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    adjacent p q := by
  simp [ValidPath] at h
  exact h.1

/- If a path has at least two positions and is valid, then the first next tile
   is safe. -/
theorem validPath_next_safe
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    isSafe s q := by
  simp [ValidPath] at h
  exact h.2.1

/- The tail of a valid path is also a valid path. -/
theorem validPath_tail
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    ValidPath s (q :: rest) := by
  simp [ValidPath] at h
  exact h.2.2

/- Safety consequences for the next step of a valid path. -/
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

theorem validPath_next_gap_or_bridge
    {s : SymbolicState} {p q : Position} {rest : List Position}
    (h : ValidPath s (p :: q :: rest)) :
    q ∉ s.gaps ∨ q ∈ s.bridges := by
  exact isSafe_gap_or_bridge (validPath_next_safe h)

/- A path is safe if it satisfies ValidPath.

   This theorem is intentionally simple: it gives a named safety theorem that
   can be cited in the report.
-/
def SafePath (s : SymbolicState) (path : List Position) : Prop :=
  ValidPath s path

theorem validPath_is_safePath
    {s : SymbolicState} {path : List Position}
    (h : ValidPath s path) :
    SafePath s path := by
  exact h

/- Soundness theorem for a planner result.

   If a path plan is sound, then the movement path used by the planner is safe.
   This is the theorem that corresponds most directly to the Python BFS layer:
   BFS may be implemented in Python, but Lean proves what must be true of any
   accepted BFS result.
-/
theorem sound_plan_is_safe
    {s : SymbolicState} {start : Position} {goals path : List Position}
    (h : PathPlanSound s start goals path) :
    SafePath s path := by
  exact validPath_is_safePath h.valid

/- If a sound plan has at least one movement step, that next step is safe. -/
theorem sound_plan_next_safe
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    isSafe s q := by
  exact validPath_next_safe h.valid

/- If a sound plan has at least one movement step, that next step is adjacent. -/
theorem sound_plan_next_adjacent
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    adjacent p q := by
  exact validPath_next_adjacent h.valid

/- If a sound plan has at least one movement step, that next step is not a trap. -/
theorem sound_plan_next_not_trap
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.traps := by
  exact validPath_next_not_trap h.valid

/- If a sound plan has at least one movement step, that next step is not a wall. -/
theorem sound_plan_next_not_wall
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    q ∉ s.walls := by
  exact validPath_next_not_wall h.valid

/- If a sound plan has at least one movement step, that next step is inside the map. -/
theorem sound_plan_next_inBounds
    {s : SymbolicState} {start p q : Position}
    {goals : List Position} {rest : List Position}
    (h : PathPlanSound s start goals (p :: q :: rest)) :
    inBounds q := by
  exact validPath_next_inBounds h.valid

/-!
  Generic goal predicates used by task-level proofs.
-/

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

def TaskCompletedByExit (e : ExitRule) (s : SymbolicState) : Prop :=
  s.player = e.target

/-!
  A successful action plan is an executable action list whose final state
  satisfies a symbolic goal predicate.
-/

def SuccessfulPlan
    (s0 : SymbolicState)
    (actions : List Action)
    (goal : SymbolicState → Prop) : Prop :=
  ∃ finalState : SymbolicState,
    Exec s0 actions finalState ∧ goal finalState

namespace Task1

/--
Task 1 strategy correctness.

The abstract Task 1 strategy is:

1. execute a planner-produced path to a chest-adjacent state;
2. open the key chest;
3. execute a planner-produced path to the exit;
4. use the exit.

The theorem proves that, if every stage is executable and the exit rule is
satisfied, then there exists a successful action plan whose final state reaches
the exit target.
-/
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

/--
Opening the Task 1 chest increases the number of keys by one.
This theorem captures the symbolic effect used by the Python planner when it
updates its inventory after interacting with a chest.
-/
theorem task1_open_chest_gives_key
    {s : SymbolicState} {chest : Position}
    (_hOpen : canOpenChest s chest) :
    HasAtLeastKeys (s.inventory.keys + 1) (afterOpenChest s chest) := by
   simp [HasAtLeastKeys, afterOpenChest]

end Task1


namespace Task2

/--
Task 2 strategy correctness.

The abstract Task 2 strategy is:

1. execute a planner-produced path to a monster-adjacent state;
2. attack and remove the monster;
3. execute a planner-produced path to a chest-adjacent state;
4. open the key chest;
5. execute a planner-produced path to the exit;
6. use the exit.

This corresponds to the Python search policy for tasks where combat must happen
before the key/chest/exit sequence can be completed.
-/
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

/--
After attacking a monster in the abstract combat model, the resulting state is
exactly the state where that monster has been erased from the monster list.
-/
theorem task2_attack_updates_monsters
    {s : SymbolicState} {monster : Position}
    (_hAttack : canAttack s monster) :
    (afterAttackMonster s monster).monsters = s.monsters.erase monster := by
  unfold afterAttackMonster
  rfl

end Task2


namespace Task3

/--
Generic three-stage Task 3 composition theorem.

Task 3 may require several symbolic phases, such as combat, collecting a key,
opening a chest or door, and reaching an exit.  Instead of hard-coding a concrete
map, this theorem proves the reusable planner property:

if three executable stages compose into a final state satisfying the task goal,
then the concatenated action list is a successful plan.
-/
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

/--
A more concrete Task 3 theorem for the common monster → chest/key → exit
pattern.

This is similar to Task 2, but it is placed in Task3 because the third task can
be described as a longer composition of symbolic subgoals.
-/
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

/--
Task 4 bridge/gap safety property.

If the symbolic planner accepts a path and the next tile is a gap, then that gap
must already be in the bridge list.  Therefore, the planner never accepts a move
onto an unbridged gap.
-/
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

/--
Task 4 bridge-stage strategy correctness.

The detailed bridge/button mechanism is abstracted as a preparatory executable
stage.  If that stage reaches a state from which the planner can safely move to
the exit and the exit rule is satisfied, then the combined plan completes the
task.
-/
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

end Task4


namespace Task5

/--
Generic four-stage Task 5 composition theorem.

Task 5 is treated as a longer symbolic plan.  The theorem states that if four
planner stages execute successfully and the final state satisfies the symbolic
goal, then their concatenation is a successful plan.
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

/--
Task 5 exit-finalization theorem.

This version is useful when the last symbolic phase is explicitly:
move to an exit state, then use the exit.
-/
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
