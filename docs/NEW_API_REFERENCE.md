# Added backend API reference

Existing paths and envelopes remain available. New HTTP success responses use `{"success": true, "data": ...}` plus the existing message field; errors use the existing code/message envelope. Authenticate with `Authorization: Bearer <access_token>`. All routes below require an authenticated player. See `OPENAPI.json` or `/docs` for exact validation bounds and request schemas.

| Method | Path | Request model |
| --- | --- | --- |
| POST | `/farm/refill` | `none` |
| GET | `/notifications` | `none` |
| POST | `/notifications/{notification_id}` | `NotificationUpdate` |
| GET | `/profile` | `none` |
| PUT | `/profile` | `ProfileUpdate` |
| POST | `/profile/save` | `none` |
| POST | `/profile/heartbeat` | `none` |
| POST | `/profile/tutorial` | `TutorialRequest` |
| POST | `/profile/hints/{feature}` | `none` |
| POST | `/profile/feedback` | `FeedbackRequest` |
| POST | `/profile/delete-account` | `DeleteAccountRequest` |
| GET | `/housing` | `none` |
| POST | `/housing/upgrade` | `UpgradeRequest` |
| POST | `/housing/decorations` | `DecorationRequest` |
| POST | `/housing/decorations/{decoration_id}/remove` | `none` |
| GET | `/pets` | `none` |
| POST | `/pets/actions` | `PetAction` |
| GET | `/shop` | `none` |
| POST | `/shop/buy` | `PurchaseRequest` |
| POST | `/shop/sell` | `ItemRequest` |
| GET | `/shop/collection` | `none` |
| GET | `/progression/goals` | `none` |
| GET | `/progression/statistics` | `none` |
| POST | `/fishing/cast` | `CastRequest` |
| POST | `/fishing/catch` | `CatchRequest` |
| POST | `/fishing/drops/{drop_id}/claim` | `none` |
| GET | `/fishing/spots` | `none` |
| GET | `/fishing/drops` | `none` |
| GET | `/social/search` | `none` |
| GET | `/social/friends` | `none` |
| GET | `/social/requests` | `none` |
| POST | `/social/requests` | `TargetRequest` |
| POST | `/social/friends/{target_id}` | `FriendAction` |
| GET | `/social/blocks` | `none` |
| POST | `/social/blocks` | `TargetRequest` |
| POST | `/social/blocks/{target_id}/remove` | `none` |
| POST | `/social/gifts` | `GiftRequest` |
| GET | `/social/gifts` | `none` |
| POST | `/social/gifts/{gift_id}/claim` | `none` |
| GET | `/social/trades` | `none` |
| POST | `/social/trades` | `TradeRequest` |
| POST | `/social/trades/{trade_id}` | `TradeAction` |
| POST | `/social/visit/{target_id}` | `none` |
| GET | `/social/invites` | `none` |
| POST | `/social/invites` | `TargetRequest` |
| POST | `/social/invites/{invite_id}/accept` | `none` |
| POST | `/social/messages` | `MessageRequest` |
| GET | `/social/messages/{target_id}` | `none` |
| POST | `/social/reports` | `ReportRequest` |
| GET | `/social/farms/{target_id}` | `none` |
| GET | `/events` | `none` |
| POST | `/events/{code}/claim` | `none` |
| POST | `/realtime/enter` | `EnterRequest` |
| POST | `/realtime/move` | `MoveRequest` |
| GET | `/realtime/snapshot` | `none` |
| POST | `/realtime/chat` | `NearbyChatRequest` |
| POST | `/realtime/emote` | `EmoteRequest` |

## Critical payloads

```json
{"request_id":"purchase-0001","item_code":"wheat_seed","quantity":1}
```

Use this with POST `/shop/buy`. Generate one stable request ID per intended purchase and reuse it only when retrying that same purchase.

```json
{"target_id":2,"request_id":"gift-0001","item_code":"wheat","quantity":1}
```

Use this with POST `/social/gifts`. The recipient claims the returned gift ID separately. A gift removes inventory immediately on sending; a pending trade does not.

```json
{"target_id":2,"request_id":"trade-0001","offered_code":"wheat","offered_quantity":1,"wanted_code":"corn","wanted_quantity":1}
```

Use this with POST `/social/trades`. The recipient then POSTs `{"action":"accept"}` to `/social/trades/{id}`. Recipient decline and sender cancel are also supported.

## WebSocket

Connect to `/realtime/ws`, send `{"type":"auth","token":"<access_token>"}` as the first message within ten seconds, and receive a `snapshot`. No token belongs in the URL. Supported messages are `enter`, `move`, `chat`, `emote`, and `snapshot`, with a `data` object matching the corresponding HTTP request. Examples:

```json
{"type":"move","data":{"x":7377,"y":-891,"sequence":1}}
```

```json
{"type":"chat","data":{"body":"Hello!"}}
```

The socket authenticates every processing step and closes for invalid/revoked/expired sessions. Idle snapshots are sent at about 5 Hz; a small per-message delay bounds incoming socket work. Each text message is limited to 8 KiB of UTF-8 bytes. Oversized messages close with 1009, malformed JSON/auth shapes with 1008, and binary frames with 1003. Send a sequenced stationary movement update to keep presence active. Re-enter after the 60-second grace period expires. This protocol is new and is not yet connected to the Godot client.

## Compatibility notes

- Original `/farm/plant` accepts `item_code` and the `crop_type` alias. New seed codes map to the existing crop code in the returned plot. Original crop codes still work for legacy callers.
- Original `/inventory/remove` now accepts optional `confirmed`; rare/high-value discards require `true`. Common-item requests keep their old payload shape.
- Login now grants 10 Aura once per UTC day. Currency response fields, including legacy `taka_balance`, are unchanged.
- Bucket watering is authoritative on the server. `/farm/refill` requires an active campus position inside a copied water-interaction polygon; no unverified client “near water” boolean is trusted.
- `/social/farms/{target_id}` returns friend-owned plots read-only. The original mutation routes always act on the authenticated player's own farm.
- HTTP query/body validation remains independent of client validation. Never use dev award routes as the production gameplay integration path.

Logout revokes the submitted refresh token; existing access tokens expire normally. Password changes/reset and account deletion invalidate active access tokens, including connected WebSockets. Clients should close sockets when logging out.
