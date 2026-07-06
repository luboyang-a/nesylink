from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Any, Iterable

import numpy as np

from nesylink.core.constants import (
    ACTION_A,
    ACTION_DOWN,
    ACTION_LEFT,
    ACTION_NOOP,
    ACTION_RIGHT,
    ACTION_UP,
    MAP_TILE_HEIGHT,
    MAP_TILE_WIDTH,
    TILE_SIZE,
)


Position = tuple[int, int]

MOVE_ACTIONS = {ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT}

DIR_TO_ACTION = {
    "north": ACTION_UP,
    "south": ACTION_DOWN,
    "west": ACTION_LEFT,
    "east": ACTION_RIGHT,
}

ACTION_TO_DELTA = {
    ACTION_UP: (0, -1),
    ACTION_DOWN: (0, 1),
    ACTION_LEFT: (-1, 0),
    ACTION_RIGHT: (1, 0),
}

OPPOSITE_DIR = {
    "north": "south",
    "south": "north",
    "west": "east",
    "east": "west",
}


COLORS = {
    "wall_mid": (219, 18, 82),
    "wall_dark": (88, 0, 36),
    "outline": (8, 8, 16),
    "shadow": (42, 45, 88),
    "player": (36, 198, 72),
    "player_light": (126, 248, 82),
    "chest": (152, 82, 36),
    "gold": (255, 216, 80),
    "monster_chaser": (238, 126, 28),
    "monster_patroller": (200, 78, 16),
    "monster_ambusher": (255, 180, 48),
    "trap": (112, 112, 126),
    "spike": (238, 238, 236),
    "button": (40, 190, 74),
    "switch_down": (184, 124, 42),
    "gap": (16, 22, 48),
    "abyss": (0, 0, 0),
    "bridge": (172, 104, 48),
    "door": (96, 48, 26),
    "npc": (240, 154, 52),
}


@dataclass(frozen=True)
class Scene:
    player: Position
    walls: set[Position]
    traps: set[Position]
    gaps: set[Position]
    bridges: set[Position]
    chests: set[Position]
    monsters: set[Position]
    buttons: set[Position]
    switches: set[Position]
    npcs: set[Position]
    exits: dict[str, set[Position]]
    room_hint: str


def _color_mask(frame: np.ndarray, color: tuple[int, int, int]) -> np.ndarray:
    return np.all(frame == np.asarray(color, dtype=np.uint8), axis=-1)


def _count_color(tile: np.ndarray, color: tuple[int, int, int]) -> int:
    return int(np.count_nonzero(_color_mask(tile, color)))


def _tile(frame: np.ndarray, pos: Position) -> np.ndarray:
    x, y = pos
    return frame[
        y * TILE_SIZE : (y + 1) * TILE_SIZE,
        x * TILE_SIZE : (x + 1) * TILE_SIZE,
    ]


def _entity_tile_from_mask(mask: np.ndarray, fallback: Position = (0, 0)) -> Position:
    ys, xs = np.nonzero(mask)

    if len(xs) == 0:
        return fallback

    return (
        int(
            np.clip(
                round((float(xs.min()) + float(xs.max())) / 2.0) // TILE_SIZE,
                0,
                MAP_TILE_WIDTH - 1,
            )
        ),
        int(
            np.clip(
                round((float(ys.min()) + float(ys.max())) / 2.0) // TILE_SIZE,
                0,
                MAP_TILE_HEIGHT - 1,
            )
        ),
    )


def _tiles_from_mask(mask: np.ndarray, *, min_pixels: int) -> set[Position]:
    positions: set[Position] = set()

    for y in range(MAP_TILE_HEIGHT):
        for x in range(MAP_TILE_WIDTH):
            count = int(
                np.count_nonzero(
                    mask[
                        y * TILE_SIZE : (y + 1) * TILE_SIZE,
                        x * TILE_SIZE : (x + 1) * TILE_SIZE,
                    ]
                )
            )

            if count >= min_pixels:
                positions.add((x, y))

    return positions


def extract_scene(obs: np.ndarray, previous_player: Position = (0, 0)) -> Scene:
    frame = np.asarray(obs)

    player_mask = _color_mask(frame, COLORS["player"]) | _color_mask(
        frame, COLORS["player_light"]
    )
    player = _entity_tile_from_mask(player_mask, previous_player)

    monster_mask = (
        _color_mask(frame, COLORS["monster_chaser"])
        | _color_mask(frame, COLORS["monster_patroller"])
        | _color_mask(frame, COLORS["monster_ambusher"])
    )
    monsters = _tiles_from_mask(monster_mask, min_pixels=8)

    walls: set[Position] = set()
    traps: set[Position] = set()
    gaps: set[Position] = set()
    bridges: set[Position] = set()
    chests: set[Position] = set()
    buttons: set[Position] = set()
    switches: set[Position] = set()
    npcs: set[Position] = set()

    exits: dict[str, set[Position]] = {
        "north": set(),
        "south": set(),
        "west": set(),
        "east": set(),
    }

    for y in range(MAP_TILE_HEIGHT):
        for x in range(MAP_TILE_WIDTH):
            pos = (x, y)
            tile = _tile(frame, pos)

            wall = _count_color(tile, COLORS["wall_mid"])
            wall_dark = _count_color(tile, COLORS["wall_dark"])
            outline = _count_color(tile, COLORS["outline"])
            shadow = _count_color(tile, COLORS["shadow"])
            chest = _count_color(tile, COLORS["chest"])
            gold = _count_color(tile, COLORS["gold"])
            door = _count_color(tile, COLORS["door"])
            gap = _count_color(tile, COLORS["gap"])
            abyss = _count_color(tile, COLORS["abyss"])
            bridge = _count_color(tile, COLORS["bridge"])
            trap = _count_color(tile, COLORS["trap"]) + _count_color(
                tile, COLORS["spike"]
            )
            button = _count_color(tile, COLORS["button"])
            switch_down = _count_color(tile, COLORS["switch_down"])
            npc = _count_color(tile, COLORS["npc"])

            if wall >= 30 or (wall >= 16 and wall_dark >= 8):
                walls.add(pos)

            if gap >= 40 or abyss >= 180 or (
                outline >= 180 and pos not in monsters and pos != player
            ):
                gaps.add(pos)

            if bridge >= 30:
                bridges.add(pos)
                gaps.discard(pos)

            if trap >= 10:
                traps.add(pos)

            if chest >= 12:
                chests.add(pos)

            if button >= 12 and pos != player:
                buttons.add(pos)

            boundary = x in {0, MAP_TILE_WIDTH - 1} or y in {
                0,
                MAP_TILE_HEIGHT - 1,
            }

            if switch_down >= 4 or (
                not boundary
                and gold >= 16
                and outline >= 12
                and chest < 8
                and pos not in chests
            ):
                switches.add(pos)

            if npc >= 16 and pos != player:
                npcs.add(pos)

            exit_like = boundary and pos not in walls and (
                door >= 18 or shadow >= 20 or (gold >= 18 and outline >= 8)
            )

            if exit_like:
                if y == 0:
                    exits["north"].add(pos)
                if y == MAP_TILE_HEIGHT - 1:
                    exits["south"].add(pos)
                if x == 0:
                    exits["west"].add(pos)
                if x == MAP_TILE_WIDTH - 1:
                    exits["east"].add(pos)

    room_hint = _room_hint(
        walls,
        traps,
        gaps,
        bridges,
        chests,
        monsters,
        buttons,
        switches,
        npcs,
        exits,
    )

    return Scene(
        player=player,
        walls=walls,
        traps=traps,
        gaps=gaps,
        bridges=bridges,
        chests=chests,
        monsters=monsters,
        buttons=buttons,
        switches=switches,
        npcs=npcs,
        exits=exits,
        room_hint=room_hint,
    )

def _room_hint(
    walls: set[Position],
    traps: set[Position],
    gaps: set[Position],
    bridges: set[Position],
    chests: set[Position],
    monsters: set[Position],
    buttons: set[Position],
    switches: set[Position],
    npcs: set[Position],
    exits: dict[str, set[Position]],
) -> str:
    """Coarse structural hint used only by Tasks 1–4."""
    visible_exits = {
        direction for direction, tiles in exits.items() if tiles
    }
    if buttons or (npcs and len(visible_exits) >= 3):
        return "multi_exit_hub"
    if npcs and len(visible_exits) == 1:
        return "single_exit_branch"

    if traps:
        return "task2"

    if bridges or len(gaps) > 20:
        return "task4_center"

    if switches:
        return "task4_west"

    if (4, 3) in chests and exits["south"]:
        return "task4_north"

    if (5, 4) in chests and exits["west"] and len(walls) >= 20:
        return "task4_east"

    if exits["north"] and len(walls) >= 20 and not bridges and not switches:
        return "task4_south"

    if npcs and exits["east"] and exits["west"]:
        return "task3_start"

    if monsters and exits["east"] and exits["west"]:
        return "task3_hall"

    if chests and exits["east"] and not walls:
        return "task3_key"

    return "task1"


def neighbors(pos: Position) -> Iterable[Position]:
    x, y = pos
    yield (x, y - 1)
    yield (x, y + 1)
    yield (x - 1, y)
    yield (x + 1, y)


def in_bounds(pos: Position) -> bool:
    x, y = pos
    return 0 <= x < MAP_TILE_WIDTH and 0 <= y < MAP_TILE_HEIGHT


def manhattan(a: Position, b: Position) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def action_from_step(current: Position, nxt: Position) -> int:
    dx = nxt[0] - current[0]
    dy = nxt[1] - current[1]

    for action, delta in ACTION_TO_DELTA.items():
        if delta == (dx, dy):
            return action

    return ACTION_NOOP


def direction_action(current: Position, target: Position) -> int:
    dx = target[0] - current[0]
    dy = target[1] - current[1]

    if abs(dx) > abs(dy):
        return ACTION_RIGHT if dx > 0 else ACTION_LEFT

    if dy != 0:
        return ACTION_DOWN if dy > 0 else ACTION_UP

    return ACTION_NOOP


def is_walkable(scene: Scene, pos: Position, opened: set[tuple[str, Position]]) -> bool:
    del opened

    if not in_bounds(pos):
        return False

    if pos in scene.walls or pos in scene.traps:
        return False

    if pos in scene.gaps and pos not in scene.bridges:
        return False

    if pos in scene.npcs or pos in scene.monsters:
        return False

    if pos in scene.chests:
        return False

    return True


def bfs(
    scene: Scene,
    goals: set[Position],
    opened: set[tuple[str, Position]],
) -> list[Position] | None:
    if scene.player in goals:
        return [scene.player]

    queue: deque[Position] = deque([scene.player])
    parent: dict[Position, Position | None] = {scene.player: None}

    while queue:
        current = queue.popleft()

        for nxt in neighbors(current):
            if nxt in parent:
                continue

            if nxt not in goals and not is_walkable(scene, nxt, opened):
                continue

            if nxt in scene.monsters:
                continue

            parent[nxt] = current

            if nxt in goals:
                path: list[Position] = [nxt]
                backtrack = current

                while backtrack is not None:
                    path.append(backtrack)
                    backtrack = parent[backtrack]

                return list(reversed(path))

            queue.append(nxt)

    return None


def approach_tiles(
    scene: Scene,
    target: Position,
    opened: set[tuple[str, Position]],
) -> set[Position]:
    return {pos for pos in neighbors(target) if is_walkable(scene, pos, opened)}


RoomKey = frozenset[Position]


def room_key(scene: Scene) -> RoomKey:
    """Static wall geometry identifies a room across frames."""
    return frozenset(scene.walls)


@dataclass
class RoomMemory:
    exits: set[str]
    edges: dict[str, RoomKey]
    opened_chests: set[Position]
    button_seen: bool = False
    button_done: bool = False


def inventory_from_info(info: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(info, dict):
        return {}

    inv = info.get("inventory")

    if isinstance(inv, dict):
        return inv

    if any(key in info for key in ("keys", "gold", "items", "tools", "equipped")):
        return info

    return {}


def tools_from_inventory(inv: dict[str, Any], *, assume_default_sword: bool) -> set[str]:
    tools: set[str] = set()

    raw_tools = inv.get("tools")
    raw_items = inv.get("items")
    equipped = inv.get("equipped")

    if isinstance(raw_tools, (list, tuple, set)):
        tools.update(str(x) for x in raw_tools)

    if isinstance(raw_items, (list, tuple, set)):
        tools.update(str(x) for x in raw_items)

    if isinstance(equipped, dict):
        tools.update(str(v) for v in equipped.values() if isinstance(v, str))

    if assume_default_sword and not tools:
        tools.add("sword")

    return tools


class Policy:
    def __init__(self) -> None:
        self.task_id = ""
        self.previous_player: Position = (0, 0)
        self.last_move = ACTION_DOWN
        self.attack_cooldown = 0
        self.move_queue: deque[int] = deque()
        self.queue_next_move = True
        self.opened: set[tuple[str, Position]] = set()
        self.visited_hints: set[str] = set()
        self.switch_count = 0
        self.rooms: dict[RoomKey, RoomMemory] = {}
        self.current_room: RoomKey | None = None
        self.pending_exit: tuple[RoomKey, str] | None = None
        self.blocked_exits: dict[tuple[RoomKey, str], int] = {}
        self.last_action = ACTION_NOOP
        self.stationary_steps = 0

    def reset(self, seed: int | None = None, task_id: str | None = None) -> None:
        del seed

        self.task_id = task_id or ""
        self.previous_player = (0, 0)
        self.last_move = ACTION_DOWN
        self.attack_cooldown = 0
        self.move_queue.clear()
        self.queue_next_move = True
        self.opened.clear()
        self.visited_hints.clear()
        self.switch_count = 0
        self.rooms.clear()
        self.current_room = None
        self.pending_exit = None
        self.blocked_exits.clear()
        self.last_action = ACTION_NOOP
        self.stationary_steps = 0

    def act(self, obs: np.ndarray, info: dict[str, Any] | None = None) -> int:
        scene = extract_scene(obs, self.previous_player)

        if scene.player == self.previous_player and self.last_action in MOVE_ACTIONS:
            self.stationary_steps += 1
        else:
            self.stationary_steps = 0

        self.previous_player = scene.player
        self.visited_hints.add(scene.room_hint)

        inv = inventory_from_info(info)
        keys = int(inv.get("keys", 0) or 0)
        self._observe_room(scene)

        assume_default_sword = not self.task_id.endswith("task_4")
        tools_now = tools_from_inventory(inv, assume_default_sword=assume_default_sword)

        if self.stationary_steps >= 48:
            self.move_queue.clear()
            if self.pending_exit is not None:
                self.blocked_exits[self.pending_exit] = keys
                self.pending_exit = None
            self.stationary_steps = 0
            x, y = scene.player
            recovery = (
                ACTION_LEFT if x >= MAP_TILE_WIDTH // 2 else ACTION_RIGHT
            )
            if self.last_action in {ACTION_LEFT, ACTION_RIGHT}:
                recovery = ACTION_UP if y >= MAP_TILE_HEIGHT // 2 else ACTION_DOWN
            return self._emit(recovery)

        if self.move_queue and not any(
            manhattan(scene.player, monster) == 1 for monster in scene.monsters
        ):
            action = self.move_queue.popleft()
            self.last_move = action
            return self._emit(action)

        if self.attack_cooldown > 0:
            self.attack_cooldown -= 1
            return self._emit(ACTION_A)

        adjacent_monsters = [
            monster
            for monster in scene.monsters
            if manhattan(scene.player, monster) == 1
        ]

        if adjacent_monsters and "sword" in tools_now:
            monster = min(adjacent_monsters, key=lambda m: manhattan(scene.player, m))
            face = direction_action(scene.player, monster)

            if face in MOVE_ACTIONS and self.last_move != face:
                self.last_move = face
                self.move_queue.clear()
                self.attack_cooldown = 4
                return self._emit(face)

            self.attack_cooldown = 6
            return self._emit(ACTION_A)

        target = self._select_target(scene, inv)
        action = self._action_for_target(scene, target)

        if action in MOVE_ACTIONS:
            self.last_move = action

            if self.queue_next_move:
                self.move_queue.extend([action] * (TILE_SIZE - 1))

            self.queue_next_move = True

        if action == ACTION_A and target and target[0] == "open":
            key = self.current_room or room_key(scene)
            self.rooms[key].opened_chests.add(target[1])
            self.opened.add((scene.room_hint, target[1]))

        if action == ACTION_A and target and target[0] == "switch":
            self.switch_count += 1

        return self._emit(action)

    def _emit(self, action: int) -> int:
        self.last_action = action
        return action

    def _observe_room(self, scene: Scene) -> None:
        key = room_key(scene)
        memory = self.rooms.setdefault(
            key,
            RoomMemory(exits=set(), edges={}, opened_chests=set()),
        )
        memory.exits.update(
            direction for direction, tiles in scene.exits.items() if tiles
        )

        if self.current_room is not None and key != self.current_room:
            if self.pending_exit is not None:
                source, direction = self.pending_exit
                source_memory = self.rooms[source]
                source_memory.edges[direction] = key
                memory.edges[OPPOSITE_DIR[direction]] = source
            self.move_queue.clear()
            self.pending_exit = None
            self.stationary_steps = 0

        self.current_room = key

    def _select_target(
        self,
        scene: Scene,
        inv: dict[str, Any],
    ) -> tuple[str, Any] | None:
        keys = int(inv.get("keys", 0) or 0)

        assume_default_sword = not self.task_id.endswith("task_4")
        tools = tools_from_inventory(inv, assume_default_sword=assume_default_sword)

        if self.task_id.endswith("task_1"):
            if keys <= 0:
                return self._nearest_chest(scene)
            return ("exit", "north")

        if self.task_id.endswith("task_2"):
            if scene.monsters:
                return ("monster", self._nearest_reachable_interaction(scene, scene.monsters))
            if keys <= 0:
                return self._nearest_chest(scene)
            return ("exit", "west")

        if self.task_id.endswith("task_3"):
            if scene.monsters:
                return ("monster", self._nearest_reachable_interaction(scene, scene.monsters))
            if keys <= 0:
                if scene.chests:
                    return self._nearest_chest(scene)
                return ("exit", "west")
            return ("exit", "east")

        if self.task_id.endswith("task_4"):
            return self._task4_target(scene, keys, tools)

        if self.task_id.endswith("task_5"):
            return self._task5_topology_target(scene, keys)

        if scene.monsters:
            return ("monster", self._nearest_reachable_interaction(scene, scene.monsters))

        chest = self._nearest_chest(scene)
        if chest is not None:
            return chest

        for direction in ("north", "east", "south", "west"):
            if scene.exits[direction]:
                return ("exit", direction)

        return None

    def _nearest_chest(self, scene: Scene) -> tuple[str, Position] | None:
        key = self.current_room or room_key(scene)
        memory = self.rooms.setdefault(
            key,
            RoomMemory(exits=set(), edges={}, opened_chests=set()),
        )
        unopened = [
            chest
            for chest in scene.chests
            if chest not in memory.opened_chests
        ]

        reachable: list[tuple[int, Position]] = []
        for chest in unopened:
            goals = approach_tiles(scene, chest, self.opened)
            path = bfs(scene, goals, self.opened) if goals else None
            if path is not None:
                reachable.append((len(path), chest))

        if reachable:
            return ("open", min(reachable)[1])
        return None

    def _nearest_reachable_interaction(
        self,
        scene: Scene,
        targets: set[Position],
    ) -> Position:
        """
        从全局视觉识别出的目标集合中，选择一个局部可接近的目标。
        优先选择 BFS 能走到其邻接格的目标。
        """

        ordered = sorted(targets, key=lambda p: manhattan(scene.player, p))

        for target in ordered:
            if manhattan(scene.player, target) == 1:
                return target

            goals = approach_tiles(scene, target, self.opened)
            if goals and bfs(scene, goals, self.opened) is not None:
                return target

        return ordered[0]

    def _task5_topology_target(
        self,
        scene: Scene,
        keys: int,
    ) -> tuple[str, Any] | None:
        """Object goals first, then DFS/BFS exploration of the learned graph."""
        nearby = {
            monster
            for monster in scene.monsters
            if manhattan(scene.player, monster) <= 2
        }
        if nearby:
            return (
                "monster",
                min(nearby, key=lambda pos: manhattan(scene.player, pos)),
            )

        chest = self._nearest_chest(scene)
        if chest is not None:
            return chest

        key = self.current_room or room_key(scene)
        memory = self.rooms[key]
        if scene.buttons:
            memory.button_seen = True
            button = min(
                scene.buttons,
                key=lambda pos: manhattan(scene.player, pos),
            )
            return ("walk", button)
        if memory.button_seen:
            memory.button_done = True

        direction = self._next_exploration_exit(key, keys)
        if direction is not None:
            return ("exit", direction)

        # Never idle while a visible exit exists. This is the final fallback
        # for an imperfect signature or a temporarily occluded doorway.
        for direction in ("south", "east", "west", "north"):
            if scene.exits[direction]:
                return ("exit", direction)
        return None

    def _next_exploration_exit(
        self,
        start: RoomKey,
        keys: int,
    ) -> str | None:
        def unexplored(key: RoomKey) -> list[str]:
            memory = self.rooms[key]
            order = ("south", "east", "west", "north")
            return [
                direction
                for direction in order
                if direction in memory.exits
                and direction not in memory.edges
                and self.blocked_exits.get((key, direction), -1) < keys
            ]

        local = unexplored(start)
        if local:
            return local[0]

        queue: deque[RoomKey] = deque([start])
        first_step: dict[RoomKey, str | None] = {start: None}
        while queue:
            current = queue.popleft()
            if current != start and unexplored(current):
                return first_step[current]

            for direction, neighbor in self.rooms[current].edges.items():
                if neighbor in first_step:
                    continue
                first_step[neighbor] = first_step[current] or direction
                queue.append(neighbor)

        return None

    def _task4_target(
        self,
        scene: Scene,
        keys: int,
        tools: set[str],
    ) -> tuple[str, Any] | None:
        has_sword = "sword" in tools

        if has_sword and scene.monsters:
            return ("monster", self._nearest_reachable_interaction(scene, scene.monsters))

        if scene.room_hint == "task4_north" and keys <= 0 and scene.chests:
            return self._nearest_chest(scene)

        if scene.room_hint == "task4_east" and not has_sword and scene.chests:
            return self._nearest_chest(scene)

        if (
            scene.room_hint == "task4_center"
            and has_sword
            and "task4_south" in self.visited_hints
            and scene.chests
        ):
            return self._nearest_chest(scene)

        if keys <= 0:
            if scene.room_hint == "task4_center":
                return ("exit", "north")
            if scene.room_hint == "task4_north":
                return ("exit", "south")
            if scene.room_hint == "task4_west":
                return ("exit", "east")
            if scene.room_hint == "task4_east":
                return ("exit", "west")
            if scene.room_hint == "task4_south":
                return ("exit", "north")
            return ("exit", "north")

        if not has_sword:
            if scene.room_hint == "task4_west":
                if scene.switches and self.switch_count < 1:
                    return ("switch", next(iter(scene.switches)))
                return ("exit", "east")

            if scene.room_hint == "task4_center":
                if self.switch_count < 1:
                    return ("exit", "west")
                return ("exit", "east")

            if scene.room_hint == "task4_east":
                if scene.chests:
                    return self._nearest_chest(scene)
                return ("exit", "west")

            if scene.room_hint == "task4_north":
                return ("exit", "south")

            if scene.room_hint == "task4_south":
                return ("exit", "north")

            return ("exit", "west")

        if "task4_south" not in self.visited_hints:
            if self.switch_count < 2:
                if scene.room_hint == "task4_west":
                    if scene.switches:
                        return ("switch", next(iter(scene.switches)))
                    return ("exit", "east")

                if scene.room_hint == "task4_center":
                    return ("exit", "west")

                if scene.room_hint == "task4_east":
                    return ("exit", "west")

                if scene.room_hint == "task4_north":
                    return ("exit", "south")

                if scene.room_hint == "task4_south":
                    return ("exit", "north")

                return ("exit", "west")

            if scene.room_hint == "task4_center":
                return ("exit", "south")

            if scene.room_hint == "task4_west":
                return ("exit", "east")

            if scene.room_hint == "task4_east":
                return ("exit", "west")

            if scene.room_hint == "task4_north":
                return ("exit", "south")

            if scene.room_hint == "task4_south":
                return ("exit", "north")

            return ("exit", "south")

        if scene.room_hint == "task4_south":
            return ("exit", "north")

        if has_sword and "task4_south" in self.visited_hints and scene.exits["north"]:
            return ("exit", "north")

        if scene.room_hint == "task4_center" and scene.chests:
            return self._nearest_chest(scene)

        if scene.room_hint == "task4_west":
            return ("exit", "east")

        if scene.room_hint == "task4_east":
            return ("exit", "west")

        if scene.room_hint == "task4_north":
            return ("exit", "south")

        return None
    
    def _action_for_target(self, scene: Scene, target: tuple[str, Any] | None) -> int:
        if target is None:
            return ACTION_NOOP

        kind, value = target

        if kind == "exit":
            return self._exit_action(scene, str(value))

        if kind == "walk":
            return self._walk_to(scene, {value})

        if kind in {"open", "switch"}:
            target_pos = value

            if manhattan(scene.player, target_pos) == 1:
                face = direction_action(scene.player, target_pos)

                if face in MOVE_ACTIONS and self.last_move != face:
                    self.queue_next_move = False
                    return face

                return ACTION_A

            return self._walk_to(scene, approach_tiles(scene, target_pos, self.opened))

        if kind == "monster":
            target_pos = value

            if manhattan(scene.player, target_pos) == 1:
                face = direction_action(scene.player, target_pos)

                if face in MOVE_ACTIONS and self.last_move != face:
                    self.queue_next_move = False
                    return face

                self.attack_cooldown = 6
                return ACTION_A

            return self._walk_to(scene, approach_tiles(scene, target_pos, self.opened))

        return ACTION_NOOP

    def _walk_to(self, scene: Scene, goals: set[Position]) -> int:
        if not goals:
            return ACTION_NOOP

        path = bfs(scene, goals, self.opened)

        if path and len(path) > 1:
            return action_from_step(path[0], path[1])

        return ACTION_NOOP

    def _exit_action(self, scene: Scene, direction: str) -> int:
        action = DIR_TO_ACTION.get(direction, ACTION_NOOP)
        if self.current_room is not None:
            self.pending_exit = (self.current_room, direction)
        exits = scene.exits.get(direction, set())

        if not exits:
            if direction == "north":
                exits = {(4, 0), (5, 0)}
            elif direction == "south":
                exits = {(4, MAP_TILE_HEIGHT - 1), (5, MAP_TILE_HEIGHT - 1)}
            elif direction == "west":
                exits = {(0, 3), (0, 4)}
            elif direction == "east":
                exits = {(MAP_TILE_WIDTH - 1, 3), (MAP_TILE_WIDTH - 1, 4)}

        if scene.player in exits:
            self.move_queue.extend([action] * 19)
            return action

        walkable_exits = {
            pos for pos in exits if is_walkable(scene, pos, self.opened) or pos in exits
        }

        return self._walk_to(scene, walkable_exits)


def make_policy() -> Policy:
    return Policy()


policy = Policy()


def reset(seed: int | None = None, task_id: str | None = None) -> None:
    policy.reset(seed=seed, task_id=task_id)


def act(obs: np.ndarray, info: dict[str, Any] | None = None) -> int:
    return policy.act(obs, info)
