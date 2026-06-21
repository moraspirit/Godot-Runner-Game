extends Node

const SIM_VERSION: int = 3

const NUM_LANES: int = 3
const LANE_X: Array = [-2.0, 0.0, 2.0]

const SEGMENT_LENGTH: float = 2000.0
const CHUNK_LENGTH: float = 200.0

const SCROLL_SPEED: float = 15.0
const LANE_SWITCH_SPEED: float = 14.0
const LANE_SWITCH_COOLDOWN_MS: int = 100

const JUMP_FORCE: float = 9.0
const GRAVITY: float = 22.0
const JUMP_CLEAR_Y: float = 0.72

const HIT_Z: float = 0.9
const HIT_X: float = 0.9

const COIN_SCORE: int = 1
const DISTANCE_SCORE_PER_UNIT: float = 0.0
const LOCAL_SCORE_PER_SEC: float = 0.0

const API_BASE: String = "http://localhost:8080"
const OFFLINE_FALLBACK: bool = true
const DEBUG_API: bool = true
const SECURE_SPAWNS: bool = true

const SPAWN_Z: float = -50.0
const SPAWN_LEAD: float = 55.0
const MIN_ROCK_GAP: float = 55.0
const MIN_COIN_GAP: float = 8.0
const COIN_CHUNK_THRESHOLD: float = 0.05
const COIN_COUNT_MIN: int = 8
const COIN_COUNT_MAX: int = 14
const COIN_SECOND_WAVE_CHANCE: float = 0.45
