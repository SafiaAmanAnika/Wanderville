# Local house ownership isolation

The existing house builder stored every account in `user://house.json` and retained its dictionary after logout. This made accounts on one installation inherit each other's house, floor and furniture.

House saves now use a filename scoped by API server, player ID and owned-world ID. Every load begins from an empty dictionary, including when the account has no file. Logout resets the dictionary and temporary building-wood counter. Saves from a mismatched owner context or a read-only farm visit are refused. The original unowned `house.json` is preserved: it remains available to guests and for manual recovery, and is never automatically assigned to a signed-in account whose ownership cannot be established.

The scene's HouseManager watches account and visit-context changes. It drops placement ghosts, closes its old dialogs, clears old exteriors/interiors, then loads the new scope. Ordinary session polls do not disturb an active placement. Build, floor, furniture, sell and destroy entry points refuse visitor/stale-context edits. Leaving the scene restores a carried rearrangement item before saving, so Leave World retains the house layout.

This fixes local account isolation. The existing detailed house builder remains local storage; this change does not turn its JSON layout into a synchronized server-side multiplayer housing system. Existing server housing tiers/decorations are a separate API representation. No cloud migration or mapping between those systems is claimed.

Validation: `continuation_check.gd` switches two accounts and multiple owned worlds, reloads house/furniture, checks the legacy unowned file, logout reset, read-only saves, visitor mutation guards and active placement during normal polls. `onboarding_integration.gd` checks authenticated Leave World → title → Continue → World, retained login and local house, and a new process restoring the same scoped house. Final disposable backend run: `code/server/.verification/client_4013b219`, Alice and restart both 0 failures.
