# HTTP API

Generated endpoints and concrete request conventions from the current FastAPI application.

<details>
<summary><strong>Explore this page</strong></summary>

[Home](../README.md) · [Contract and authentication](#contract-and-authentication) · [Envelopes and errors](#envelopes-and-errors) · [Planting example](#planting-example) · [Endpoint reference](#endpoint-reference) · [Request and response models](#request-and-response-models)

</details>


## Contract and authentication

The app identifies itself as **WanderVille API 2.0.0**. No universal `/api/v2` path prefix is assumed. Local examples use `http://127.0.0.1:8000`. Authenticated gameplay requests use `Authorization: Bearer <access-token>`; internal multiplayer routes have their own host authentication. Check each endpoint's schema and dependency.

[OPENAPI.json](OPENAPI.json) was generated from the current app. It contains **124 paths / 136 operations**. Interactive `/docs` and `/openapi.json` are available on a running FastAPI instance. The shop router is currently registered twice in [app/main.py](../code/server/app/main.py), duplicating six method/path pairs.

The game using this API also has house construction and furniture editing, a moving-target fishing minigame, an inventory aquarium, player-run shops, companions, customization, social rooms and music. Endpoint groups and client activities do not map one-to-one: detailed house layouts are local even though `/housing` tier/decorations endpoints exist; the fishing minigame records a catch separately from backend cast/reel sessions; pet selection is saved while companion movement runs locally. Music/SFX and device preferences are client systems. Use the [manual](MANUAL.md) for player flows and [client implementation](CLIENT_SIDE.md) for the owning scripts.

## Envelopes and errors

Typical service success:

```json
{"success": true, "data": {}, "message": "OK"}
```

Translated error:

```json
{"success": false, "error": "VALIDATION_ERROR", "message": "x: Input should be a valid integer"}
```

Validation maps to 422, missing bearer authentication may yield 401, integrity conflicts map to 409, and database failures map to 503. Domain errors choose their own status. Health, OAuth/browser and other special endpoints can use their own response shape; do not force every route into a common envelope. Generated responses below describe declared OpenAPI contracts; runtime exception handlers may add statuses not listed there.

Sources: [responses](../code/server/app/core/responses.py) · [error mapping](../code/server/app/core/errors.py).

## Planting example

```http
POST /farm/plant
Authorization: Bearer <access-token>
Content-Type: application/json

{"x": 12, "y": 8, "item_code": "paddy_seed"}
```

This is an illustrative request, not a replay against a live account. Coordinates must be in the caller's valid farm area and the player must own the supplied seed code. Planting may till an empty tile implicitly for legacy clients. The schema accepts `crop_type` as a legacy alias for `item_code`; conflicting values are invalid. Inspect `PlantRequest` in the schema before changing clients.

## Endpoint reference

<details>
<summary><strong>auth / 13 operations</strong></summary>

### GET `/auth/config`

Auth Config

Declared responses: `200` Successful Response.

### POST `/auth/google/code`

Google Code

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/GoogleCodeRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/signup`

Signup

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/SignupRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/login`

Login

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/LoginRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/google`

Google

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/GoogleRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/refresh`

Refresh

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/RefreshRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/logout`

Logout

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/RefreshRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### GET `/auth/verify-email`

Verify Email

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `token` | query | True | `{"type": "string", "minLength": 1, "maxLength": 512, "title": "Token"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/resend-verification`

Resend

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/EmailRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/forgot-password`

Forgot

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/EmailRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/auth/reset-password`

Reset

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ResetRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### PUT `/auth/change-password`

Change

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ChangePasswordRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/auth/me`

Me

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>economy / 6 operations</strong></summary>

### GET `/economy/`

Economy

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/economy/earn`

Earn

Development compatibility rewards only.

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TransactionRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/economy/spend`

Spend

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TransactionRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/economy/xp`

Xp

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/economy/xp/gain`

Gain

Development compatibility rewards only.

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/XPGainRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/economy/transactions`

History

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `limit` | query | False | `{"type": "integer", "maximum": 100, "minimum": 1, "default": 20, "title": "Limit"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>events / 2 operations</strong></summary>

### GET `/events`

Get Events

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/events/{code}/claim`

Post Code Claim

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `code` | path | True | `{"type": "string", "title": "Code"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>farm-visiting / 10 operations</strong></summary>

### POST `/farm/visiting/invitations`

Create Invitation

Host invites one guest to their farm.

Idempotent: re-inviting inside the existing offer's window returns the same
pending invitation rather than creating a second one.

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/FarmInviteRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/farm/visiting/invitations`

List Invitations

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `resolved` | query | False | `{"type": "boolean", "description": "Include declined/expired/cancelled", "default": false, "title": "Resolved"}` |
| `as_host` | query | False | `{"type": "boolean", "description": "Outgoing instead of incoming", "default": false, "title": "As Host"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/visiting/invitations/{invitation_id}/accept`

Accept Invitation

Guest accepts: capacity checked and slot reserved in one transaction.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `invitation_id` | path | True | `{"type": "integer", "title": "Invitation Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/visiting/invitations/{invitation_id}/decline`

Decline Invitation

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `invitation_id` | path | True | `{"type": "integer", "title": "Invitation Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### DELETE `/farm/visiting/invitations/{invitation_id}`

Cancel Invitation

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `invitation_id` | path | True | `{"type": "integer", "title": "Invitation Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/farm/visiting/session`

Current Session

The caller's resolved session: owned vs current world and the mode.

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/farm/visiting/visitors`

List Visitors

Current occupancy of the caller's own farm. The owner is not counted.

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### DELETE `/farm/visiting/visitors/{visit_session_id}`

Remove Visitor

Owner kicks a visitor; the visitor is returned to their own world.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `visit_session_id` | path | True | `{"type": "integer", "title": "Visit Session Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/visiting/leave`

Leave Farm

Visitor leaves: slot released and the caller returns to their own farm.

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/farm/visiting/state`

Visiting State

Authoritative snapshot of the world the caller is currently in.

While visiting this is the host's farm, including its tiles, crops and
growth state. It is a read; the caller cannot change what comes back.

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>farming / 7 operations</strong></summary>

### POST `/farm/relocate`

Relocate

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/RelocateRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/farm/plots`

Plots

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/till`

Till

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TileRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/plant`

Plant

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PlantRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/water`

Water

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PlotRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/harvest`

Harvest

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PlotRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/farm/refill`

Refill

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>fishing / 6 operations</strong></summary>

### POST `/fishing/cast`

Post Cast

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/CastRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/fishing/catch`

Post Catch

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/CatchRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/fishing/drops/{drop_id}/claim`

Post Drops Drop Id Claim

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `drop_id` | path | True | `{"type": "integer", "title": "Drop Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/fishing/minigame`

Post Minigame Catch

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/MinigameCatchRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/fishing/spots`

Get Spots

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/fishing/drops`

Get Drops

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>health / 2 operations</strong></summary>

### GET `/health`

Health

Declared responses: `200` Successful Response.

### GET `/ready`

Ready

Declared responses: `200` Successful Response.

</details>

<details>
<summary><strong>housing / 4 operations</strong></summary>

### GET `/housing`

Get Housing

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/housing/upgrade`

Post Upgrade

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/UpgradeRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/housing/decorations`

Post Decorations

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/DecorationRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/housing/decorations/{decoration_id}/remove`

Post Decorations Decoration Id Remove

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `decoration_id` | path | True | `{"type": "integer", "title": "Decoration Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>internal-multiplayer / 4 operations</strong></summary>

### POST `/internal/multiplayer/tickets/consume`

Consume Ticket

Spend a ticket and return the authoritative identity behind it.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `x-multiplayer-secret` | header | False | `{"anyOf": [{"type": "string"}, {"type": "null"}], "title": "X-Multiplayer-Secret"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ConsumeRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/internal/multiplayer/tickets/introspect`

Introspect Ticket

Inspect a ticket without spending it, for server-side diagnostics.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `x-multiplayer-secret` | header | False | `{"anyOf": [{"type": "string"}, {"type": "null"}], "title": "X-Multiplayer-Secret"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ConsumeRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### POST `/internal/multiplayer/presence`

Push Presence

Record the movement host's live campus positions into the projection.

The host is trusted -- it computed these positions with its own physics --
but the *room* is not taken from the host. Each update is matched to the
player's own ``player_presence`` row, and only a campus row is accepted, so a
host cannot place a player into a farm they are not standing in. Coordinates
go to the in-memory projection, never to a per-step PostgreSQL write; the
durable row keeps the last committed position and the socket heartbeat keeps
it live.

Unknown players and non-campus rooms are skipped rather than rejected, so one
stale row cannot make the whole batch fail.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `x-multiplayer-secret` | header | False | `{"anyOf": [{"type": "string"}, {"type": "null"}], "title": "X-Multiplayer-Secret"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PresencePush"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

### GET `/internal/multiplayer/health`

Host Health

Let the Godot server confirm it can reach the backend before listening.

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `x-multiplayer-secret` | header | False | `{"anyOf": [{"type": "string"}, {"type": "null"}], "title": "X-Multiplayer-Secret"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

</details>

<details>
<summary><strong>inventory / 7 operations</strong></summary>

### GET `/inventory/`

Inventory

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/inventory/catalog`

Catalog

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/inventory/catalog/{season}`

Seasonal Catalog

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `season` | path | True | `{"type": "string", "title": "Season"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/inventory/add`

Add

Development compatibility endpoint. Disabled outside dev/test.

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ItemRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/inventory/remove`

Remove

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ItemRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/inventory/use`

Use

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ItemRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/inventory/transfer`

Transfer

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TransferRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>market / 8 operations</strong></summary>

### GET `/market`

Get My Shop

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/market`

Post Open Shop

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/OpenShopRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/market/friends`

Get Friends Shops

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/market/{shop_id}/listings`

Get Listings

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `shop_id` | path | True | `{"type": "integer", "title": "Shop Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/market/{shop_id}/sales`

Get Sales

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `shop_id` | path | True | `{"type": "integer", "title": "Shop Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/market/listings`

Post Listing

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ListingRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/market/listings/remove`

Post Listing Remove

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/UnstockRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/market/buy`

Post Buy

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/BuyRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>multiplayer / 2 operations</strong></summary>

### POST `/multiplayer/tickets`

Create Ticket

Mint a short-lived, single-use admission ticket for this player.

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TicketRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/multiplayer/config`

Multiplayer Config

What a client needs to know before it tries to connect.

Declared responses: `200` Successful Response.

</details>

<details>
<summary><strong>notifications / 2 operations</strong></summary>

### GET `/notifications`

Get Notifications

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `before` | query | False | `{"anyOf": [{"type": "integer", "exclusiveMinimum": 0}, {"type": "null"}], "title": "Before"}` |
| `limit` | query | False | `{"type": "integer", "maximum": 100, "minimum": 1, "default": 50, "title": "Limit"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/notifications/{notification_id}`

Post Notification Id

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `notification_id` | path | True | `{"type": "integer", "title": "Notification Id"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/NotificationUpdate"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>pets / 3 operations</strong></summary>

### GET `/pets`

Get Pets

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### PUT `/pets`

Choose Pet

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PetSelection"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/pets/actions`

Post Actions

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PetAction"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>profile / 8 operations</strong></summary>

### GET `/profile`

Get Profile

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### PUT `/profile`

Put Profile

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ProfileUpdate"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/save`

Post Save

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/heartbeat`

Post Heartbeat

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/tutorial`

Post Tutorial

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TutorialRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/hints/{feature}`

Post Hints Feature

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `feature` | path | True | `{"enum": ["movement", "farming", "fishing", "shop", "pets", "social"], "type": "string", "title": "Feature"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/feedback`

Post Feedback

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/FeedbackRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/profile/delete-account`

Post Delete Account

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/DeleteAccountRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>progression / 2 operations</strong></summary>

### GET `/progression/goals`

Get Goals

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/progression/statistics`

Get Statistics

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>realtime / 6 operations</strong></summary>

### POST `/realtime/enter`

Enter

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/EnterRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/realtime/move`

Move

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/MoveRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/realtime/snapshot`

Snapshot

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/realtime/chat`

Chat

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/NearbyChatRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/realtime/emote`

Emote

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/EmoteRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/realtime/proximity`

Proximity

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>shop / 6 operations</strong></summary>

### GET `/shop`

Get Shop

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/shop/buy`

Post Buy

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PurchaseRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/shop/sell`

Post Sell

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/SaleRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/shop/transactions/{request_id}`

Transaction Status

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `request_id` | path | True | `{"type": "string", "minLength": 8, "maxLength": 64, "pattern": "^[a-zA-Z0-9_-]+$", "title": "Request Id"}` |
| `action` | query | False | `{"enum": ["buy", "sell"], "type": "string", "default": "buy", "title": "Action"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/shop/starter/claim`

Claim Starter

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/shop/collection`

Get Collection

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `fish_only` | query | False | `{"type": "boolean", "default": false, "title": "Fish Only"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>social / 30 operations</strong></summary>

### GET `/social/search`

Get Search

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `q` | query | True | `{"type": "string", "minLength": 2, "maxLength": 32, "title": "Q"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/friends`

Get Friends

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/requests`

Get Requests

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/requests`

Post Requests

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TargetRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/friends/{target_id}`

Post Friends Target Id

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `target_id` | path | True | `{"type": "integer", "title": "Target Id"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/FriendAction"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/blocks`

Blocks

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/blocks`

Post Blocks

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TargetRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/blocks/{target_id}/remove`

Post Blocks Target Id Remove

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `target_id` | path | True | `{"type": "integer", "title": "Target Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/gifts`

Post Gifts

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/GiftRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/gifts`

Gifts

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `before` | query | False | `{"anyOf": [{"type": "integer", "exclusiveMinimum": 0}, {"type": "null"}], "title": "Before"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/gifts/{gift_id}/claim`

Post Gifts Gift Id Claim

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `gift_id` | path | True | `{"type": "integer", "title": "Gift Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/trades`

Trades

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/trades`

Post Trades

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TradeRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/trades/{trade_id}`

Post Trades Trade Id

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `trade_id` | path | True | `{"type": "integer", "title": "Trade Id"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TradeAction"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/visit/{target_id}`

Post Visit Target Id

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `target_id` | path | True | `{"type": "integer", "title": "Target Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/invites`

Invites

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/invites`

Post Invites

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/TargetRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/invites/{invite_id}/accept`

Post Invites Invite Id Accept

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `invite_id` | path | True | `{"type": "integer", "title": "Invite Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/messages`

Post Messages

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/MessageRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/messages/{target_id}`

Get Messages Target Id

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `target_id` | path | True | `{"type": "integer", "title": "Target Id"}` |
| `after` | query | False | `{"type": "integer", "minimum": 0, "default": 0, "title": "After"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### POST `/social/reports`

Post Reports

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ReportRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/farms/{target_id}`

Farm

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `target_id` | path | True | `{"type": "integer", "title": "Target Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/preferences`

Preferences

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### PATCH `/social/preferences`

Update Preferences

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/PreferencesRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/wishlist`

Wishlist

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/players/{player_id}/wishlist`

Friend Wishlist

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `player_id` | path | True | `{"type": "integer", "exclusiveMinimum": 0, "title": "Player Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### PUT `/social/wishlist/{item_code}`

Put Wishlist

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `item_code` | path | True | `{"type": "string", "minLength": 1, "maxLength": 32, "title": "Item Code"}` |

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/WishlistRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### DELETE `/social/wishlist/{item_code}`

Remove Wishlist

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `item_code` | path | True | `{"type": "string", "minLength": 1, "maxLength": 32, "title": "Item Code"}` |
| `expected_version` | query | True | `{"type": "integer", "exclusiveMinimum": 0, "title": "Expected Version"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/wishlist/{item_code}`

Own Wishlist Item

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `item_code` | path | True | `{"type": "string", "minLength": 1, "maxLength": 32, "title": "Item Code"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

### GET `/social/gifts/requests/{request_id}`

Gift Receipt

| Parameter | In | Required | Schema |
| --- | --- | --- | --- |
| `request_id` | path | True | `{"type": "string", "minLength": 8, "maxLength": 64, "pattern": "^[a-zA-Z0-9_-]+$", "title": "Request Id"}` |

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>state / 1 operations</strong></summary>

### GET `/state/bundle`

All gameplay sections in one round trip

Replaces the client's six sequential gameplay reads after each action.

Every section matches its standalone endpoint exactly, so this is additive:
the individual routes remain available and unchanged.

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>trees / 2 operations</strong></summary>

### GET `/trees`

Get Forest

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/trees/chop`

Post Chop

Request body (required):

```json
{
  "application/json": {
    "schema": {
      "$ref": "#/components/schemas/ChopRequest"
    }
  }
}
```

Declared responses: `200` Successful Response, `422` Validation Error.

Security: `[{"HTTPBearer": []}]`.

</details>

<details>
<summary><strong>world / 5 operations</strong></summary>

### GET `/world/me`

Mine

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### GET `/world/state`

State

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### POST `/world/advance-season`

Advance

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### PUT `/world/tiles`

Retired

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

### PUT `/world/tile`

Retired

Declared responses: `200` Successful Response.

Security: `[{"HTTPBearer": []}]`.

</details>

## Request and response models

All `$ref` values above resolve under `components.schemas` in [OPENAPI.json](OPENAPI.json). For retries, use a route's actual request ID contract; not all mutation routes are idempotent. Buying with the same receipt ID and a changed payload is rejected. WebSocket messages are described separately in [networking](NETWORKING.md).

<details>
<summary><strong>Source and verification</strong></summary>

Source reviewed: `31ca97c39c05` · 2026-11-01. Source inspection is not a new gameplay test.

</details>

[← Previous](DATABASE.md) · [Back to top](#http-api) · [Next →](NETWORKING.md)
