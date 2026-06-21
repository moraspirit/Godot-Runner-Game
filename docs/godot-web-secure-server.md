# Godot Web Export — Secure Server Architecture

> **Companion:** [godot-web-secure-client.md](./godot-web-secure-client.md)  
> **Scope:** No user accounts v1 — anonymous **session + HMAC + re-simulation**.  
> **Rule:** Port Godot client spawn/replay logic exactly; compute all scores server-side.

---

## 1. Role of the server

The Godot HTML5 client is fully exposed (WASM + `.pck`). The server:

1. Issues short-lived **session signing secrets** and **map seeds**
2. **Re-generates** the segment map from the seed
3. **Replays** the move log with the same constants as `SimConstants`
4. **Accepts or rejects** checkpoints; returns the next seed and verified score

---

## 2. Tech stack (pick one)

| Option | Pros |
|--------|------|
| **Rust + axum** | Fast, shared sim crate, good crypto |
| **Go** | Simple deploy, good concurrency |
| **Node.js** | Fast to prototype |
| **Python FastAPI** | Quick MVP |

Use **PostgreSQL** (or SQLite for MVP) + **Redis** (nonces, rate limits).

---

## 3. Shared logic with Godot

Copy constants from client `sim_constants.gd` into server config. Implement:

```
generate_segment_map(seed) -> [SpawnEntry]
replay(seed, initial_lane, events) -> ReplayResult
score_from_replay(result) -> int
```

**CI gate:** For seeds `[1, 42, 12345, 99999]`, server output must match Godot golden JSON exported from client tests.

If Godot `RandomNumberGenerator` is hard to port, switch **both** sides to the same custom Xoshiro GDScript + server port — do not mix RNG implementations.

---

## 4. Session model (no auth)

### 4.1 Start session

`POST /v1/session/start`

Optional body: `{ "fingerprint": "optional-browser-hash" }` for abuse tracking only.

Response:

```json
{
  "session_id": "uuid",
  "signing_secret": "base64-32-bytes",
  "expires_at": "2026-06-21T12:00:00Z"
}
```

- Secret shown **once**; store hash server-side if you need revocation list.
- TTL: 2–24 hours.

### 4.2 Start run

`POST /v1/run/start` (signed)

Response:

```json
{
  "run_id": "uuid",
  "segment_index": 0,
  "seed": 482913,
  "segment_length": 2000,
  "sim_version": 1
}
```

### 4.3 Checkpoint / finish

`POST /v1/run/checkpoint` or `POST /v1/run/finish` (signed)

Body: move log from client doc (`sim_version`, `segment_index`, `seed`, `events`, …).

Success:

```json
{
  "accepted": true,
  "segment_score": 120,
  "run_total_score": 120,
  "next_segment_index": 1,
  "next_seed": 991827
}
```

Reject (`422`):

```json
{
  "accepted": false,
  "reason": "PICKUP_FRAUD",
  "message": "object_id 7 not at distance 450.2"
}
```

---

## 5. HMAC verification

Same as client canonical string:

```
POST\n/v1/run/checkpoint\n{timestamp}\n{nonce}\n{sha256_hex_body}
```

Checks:

1. Session exists and not expired
2. `|now - timestamp| <= 60_000` ms
3. Redis `SET nonce:{session_id}:{nonce} NX EX 120`
4. HMAC-SHA256 matches `signing_secret`
5. Then run replay pipeline

---

## 6. Re-simulation pipeline

```
1. Validate JSON schema + sim_version
2. Load run; assert segment_index is expected
3. Assert body.seed == server record for this segment
4. map = generate_segment_map(seed)
5. state = replay(initial_lane, events, map)
6. Assert end_reason matches state (collision vs complete)
7. Cross-check every coin/collision object_id against map
8. Assert distance/time within bounds (anti-speedhack)
9. score = server formula only
10. Persist submission; return next seed
```

### 6.1 Rejection codes

| Code | Meaning |
|------|---------|
| `SEED_MISMATCH` | Client seed ≠ server issued seed |
| `SEGMENT_ORDER` | Wrong segment_index |
| `INVALID_LANE` | Lane change from wrong lane |
| `LANE_SPAM` | Cooldown violation |
| `GHOST_OBJECT` | object_id not in map |
| `PICKUP_FRAUD` | Coin without overlap |
| `FAKE_CRASH` | Collision without overlap |
| `SPEED_HACK` | distance/time impossible |
| `DUPLICATE` | Replay attack on segment (policy) |

### 6.2 Score (server-only)

Example aligned with client constants:

```
score = floor(verified_distance * DISTANCE_SCORE_PER_UNIT)
      + coins_collected * COIN_SCORE
```

Ignore any client-sent score fields.

### 6.3 Timing slack

Expected duration ≈ `distance / SCROLL_SPEED` (adjust for jumps).

Allow ~15% slack + 200 ms for web latency.

---

## 7. Rate limiting

| Key | Limit |
|-----|-------|
| IP | 100 req / min |
| session_id | 30 checkpoints / min |
| run/start | 5 / min / session |

---

## 8. Persistence (minimal schema)

```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  signing_secret BYTEA NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE runs (
  id UUID PRIMARY KEY,
  session_id UUID REFERENCES sessions(id),
  status TEXT NOT NULL,
  total_score INT DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE segment_submissions (
  run_id UUID REFERENCES runs(id),
  segment_index INT NOT NULL,
  seed BIGINT NOT NULL,
  move_log JSONB NOT NULL,
  verdict TEXT NOT NULL,
  server_score INT NOT NULL,
  PRIMARY KEY (run_id, segment_index)
);
```

Leaderboards can be added later without changing the verification core.

---

## 9. Implementation phases

### Phase 1

- [ ] Session + HMAC middleware
- [ ] `/run/start` returns fixed test seed
- [ ] Port `generate_segment_map` — golden tests vs Godot
- [ ] `/run/checkpoint` replay happy path only

### Phase 2

- [ ] Full rejection rules
- [ ] Next seed rotation
- [ ] Rate limits + nonce store

### Phase 3

- [ ] Leaderboard (verified runs only)
- [ ] Anomaly flags (perfect coin rate, etc.)
- [ ] Admin review queue for top scores

---

## 10. CORS (Godot web)

Allow your game origin on API:

```
Access-Control-Allow-Origin: https://your-game.pages.dev
Access-Control-Allow-Headers: Content-Type, X-Session-Id, X-Timestamp, X-Nonce, X-Signature
```

Preflight `OPTIONS` for POST routes.

---

## 11. Threat model (realistic)

| Attack | Mitigation |
|--------|------------|
| Inflate score | Server replay |
| Fake coins | object_id + map |
| Replay POST | Nonce + timestamp |
| Patch WASM | Behavioral flags; bump `SIM_VERSION` often |
| Bots | Rate limits; CAPTCHA later on leaderboard submit |

100% cheat-proof is not achievable; goal is **expensive, detectable, low-reward** cheating.

---

## 12. References

- Client export, MoveLog, HMAC, Godot hooks: [godot-web-secure-client.md](./godot-web-secure-client.md)
