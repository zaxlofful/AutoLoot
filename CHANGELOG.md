# Changelog — EbonholdAutoLoot

## [1.2] - 2026-04-06

### Added
- Companion stuck detection: every bag-check tick, if the Greedy Scavenger is more than 5 yards from the player it is dismissed and re-summoned automatically.
- `IsPlayerMountedOrFlying()` — stuck detection is suppressed while the player is on a mount or airborne so the pet is not needlessly bounced during travel.
- `GetCompanionDistance()` — uses `UnitPosition("player")` and `UnitPosition("pet")` for a 2-D yard distance; returns `nil` gracefully if position data is unavailable.

### Changed
- Stuck check shares the existing `bagCheckTimer` interval (default 3 s) with no additional `OnUpdate` overhead.
- Stuck check is skipped on the same tick that triggers a sell cycle to prevent a dismiss colliding with the sell-cycle dismiss.

---

## [1.1] - 2026-04-06

### Added
- `SecureActionButtonTemplate` "Target Vendor" button in the GUI — targets the Goblin Merchant as a hardware event, works during combat lockdown.
- `EBVendor` macro generator (`/eal macro` or "Create Macro" button) — writes a `/targetexact Goblin Merchant` macro to the player's macro book, ready to drag to an action bar for in-combat use.
- Button pulse animation while state is SELLING to prompt the player to interact.
- Tooltips on both the Target Vendor and Create Macro buttons explaining the correct in-combat vendor flow.

### Changed
- Removed `/script InteractUnit('target')` from macro body — `InteractUnit` is Blizzard-UI-only and blocked in all macro/addon contexts regardless of hardware event status.
- In-combat vendor flow updated: addon targets the NPC; player opens vendor via right-click or Interact with Target keybind.
- Status bar and chat messages updated to reflect the correct two-step combat interaction.
- Window height increased to 552px to accommodate the new vendor button row.

### Removed
- `S_QUEUED` state and `sellQueued` flag.
- `PLAYER_REGEN_ENABLED` / `PLAYER_REGEN_DISABLED` event listeners and combat-queue logic.

---

## [1.0] - 2026-04-05

### Added
- Auto-loot cycle using the Greedy Scavenger companion pet.
- Bag-full detection (polls every 3 seconds via `OnUpdate`).
- Auto-switch to Goblin Merchant companion when bags are full.
- Auto-sell on `MERCHANT_SHOW` — sells all qualifying items the moment any vendor window opens.
- Per-quality sell toggles: Grey (default on), White, Uncommon, Rare, Epic.
- Item blacklist with scrollable list, add-by-name input, and per-entry Remove buttons.
- Case-insensitive companion name matching (`FindCompanion`).
- Live status display showing current state (IDLE / LOOTING / SELLING) and free bag slot count.
- Enable/Disable toggle and Force Sell Now button.
- Draggable, persistent window position saved via `SavedVariables`.
- Slash commands: `/eal`, `/autoloot`, `/eal enable`, `/eal disable`, `/eal reset`.
