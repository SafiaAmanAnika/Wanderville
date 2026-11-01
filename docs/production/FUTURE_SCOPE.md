# Future scope

Concrete follow-up work suggested by the current gaps; no release dates are promised.

<details>
<summary><strong>Explore this page</strong></summary>

[Home](../../README.md) · [Priorities](#priorities) · [Gameplay ideas](#gameplay-ideas) · [Dependencies](#dependencies)

</details>


## Priorities

These are proposed priorities from the source review, not commitments from the creators.

| Priority | Work | Current status | Completion evidence |
| --- | --- | --- | --- |
| 1 | Check every manual step in the game | Planned acceptance pass | Dated screenshots and action results |
| 1 | Test contextual F/S input in fishing and housing | Shared bindings found in source | Successful catch and furniture flows without input conflict |
| 1 | Remove duplicated shop-router registration | Known source limitation | Unique route pairs and contract checks |
| 1 | Connect house/shop construction spending and house-sale credit to durable server transactions | Playable flows currently use temporary client wood/local sale credit | Inventory debit, rollback and receipt tests across reconnects |
| 2 | Reconcile visual day/night tint with backend world time | Client tint currently runs a separate 30-minute cycle | Same timeline observed by HUD, world tint and two clients |
| 2 | Verify house entry, room transitions and reconnects | Runtime review needed | Two-client transition evidence |
| 2 | Decide whether detailed furniture saves should sync | Currently local scoped saves | Ownership design, migration and cross-device test |
| 2 | Broaden ENet beyond campus | Experimental campus support only | Room authority, collision parity and regression suite |
| 3 | Share realtime state across backend workers | Current memory mode is per-process | Shared state design and multi-worker tests |
| 3 | Publish a versioned playable build and trailer | No verified public links here | Export smoke test and real release artifacts |
| 3 | Complete art credits and license inventory | Attribution gap | Confirmed author and license per asset family |

## Gameplay ideas

Housing, furniture placement, a fishing minigame, pets, six-preset customization, player shops and scene music are already implemented in the client; they are not future-only concepts. New locations, more furniture/fish/companions, additional storefront styles and seasonal activities can extend those existing systems. Backend goals/statistics, trades and event claims need a separate UI-integration review before promising a complete player-facing flow for each.

## Dependencies

Stabilize input, world transitions, ownership and reproducible tests before expanding transport scope. Cross-device housing needs a clear choice about what the backend owns. Public release work depends on a verified endpoint, export configuration and asset permissions. See [testing](TESTING.md), [networking](NETWORKING.md) and [art](WORLD_ART_BIBLE.md).

<details>
<summary><strong>Source and verification</strong></summary>

Source reviewed: `31ca97c39c05` · 2026-11-01. Source inspection is not a new gameplay test.

</details>

[← Previous](CREATORS_NOTE.md) · [Back to top](#future-scope) · [Home](../../README.md)
