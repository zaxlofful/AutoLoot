# Changelog — EbonholdAutoLoot

## [2.0] - 2026-04-06

### Added
- **Vendor macro** (`EAL Merchant`): automatically created in your general Macro book every time you log in. The macro runs `/targetexact Goblin Merchant`, letting you target the vendor companion during combat. Once targeted, use your **Interact with Target** keybind or right-click the NPC to open the vendor window and trigger the auto-sell. A **"Create Macro"** button in the GUI lets you recreate or refresh it at any time while out of combat.

### Changed
- Window height expanded to 496px to accommodate the new vendor macro row between the Enable/Force Sell buttons and the quality toggles.

---

## [1.9] - 2026-04-06

### Changed
- Blacklist scroll UI simplified: removed Up/Down button controls. Scrolling is now mouse-wheel only. A slim 8px scrollbar track with a proportional amber thumb on the right edge of the list gives a clean visual position indicator — it moves as you scroll but is not clickable. The thumb hides when all items fit without scrolling.

---

## [1.8] - 2026-04-06

### Fixed
- Blacklist items now display correctly and Remove buttons now work. Root cause: `FauxScrollFrameTemplate` was still broken despite the v1.7 attempt — even with rows parented directly to the scroll frame, the template's internal scroll child movement conflicted with manual row positioning. Replaced entirely with a hand-rolled list: rows are parented directly to `listBg` at fixed offsets, a `g_blacklistOffset` integer tracks the scroll position, and Up/Down buttons plus mouse wheel (`OnMouseWheel`) update the offset and call `EAL_RefreshBlacklist`. No WoW scroll API is used at all.

---

## [1.7] - 2026-04-06

### Fixed
- Blacklist items now appear in the scroll panel after being added. Root cause: rows were parented to a `listContainer` frame that was set as the `ScrollFrame`'s scroll child. `FauxScrollFrameTemplate` manages row visibility manually via a logical offset and is not designed to work with a scroll child — the ScrollFrame widget was physically moving `listContainer` (and its children) on every scroll event, fighting the FauxScrollFrame offset logic and preventing rows from rendering in the correct positions. Fixed by removing `listContainer` and `SetScrollChild` entirely; rows are now parented directly to the scroll frame, which is the standard FauxScrollFrame pattern.
- Added `scrollFrame.offset = 0` initialisation and `or 0` fallback in `EAL_RefreshBlacklist` so `FauxScrollFrame_GetOffset` never returns nil on first paint.

---

## [1.6] - 2026-04-06

### Added
- Auto-repair on merchant open: calls `RepairAllItems()` before selling whenever `CanMerchantRepair()` returns true. Repair runs first so durability is restored regardless of whether the sell step finds anything. Prints "All items repaired." to chat when triggered.

---

## [1.5] - 2026-04-06

### Removed
- `CreateVendorMacro()`, `VENDOR_MACRO_NAME`, `VENDOR_MACRO_BODY` constants, the "Create Macro" GUI button, and the `/eal macro` slash command. `CreateMacro` and `InteractUnit` both require hardware events or non-combat context and could not be made to work reliably.
- "IN-COMBAT VENDOR" GUI section removed entirely.

### Changed
- Window height reduced to 460 px; quality toggles and blacklist shifted up to fill the space.
- Header comment updated to document the hard limitation: `InteractUnit` is Blizzard-UI-only with no client-side workaround. The fully automatic selling path requires the server to fire `MERCHANT_SHOW` automatically when the Goblin Merchant companion is summoned.

---

## [1.4] - 2026-04-06

### Fixed
- `/eal` and the window close button now work during combat. The `InCombatLockdown()` guards added in v1.3 were overly conservative — they are only required when a frame contains `SecureActionButtonTemplate` children, which was removed in v1.3. Plain frames with regular buttons and checkboxes can be shown and hidden freely at any time.

---

## [1.3] - 2026-04-06

### Fixed
- `/eal` no longer triggers "Interface action failed because of an AddOn". Root cause: `SecureActionButtonTemplate` cannot be parented to a regular addon-controlled frame — the engine blocks `Show`/`Hide` on any frame that has secure children.

### Changed
- Removed the `SecureActionButtonTemplate` "Target Vendor" button from the GUI entirely. The action-bar macro (`/eal macro`) is the correct and fully supported in-combat approach.
- Replaced the two-button vendor row with a single "Create Macro" button and an instruction hint label.
- Added `InCombatLockdown()` guard to the `/eal` slash command and the window close button so the GUI is never shown or hidden during combat lockdown.
- Removed `pulseTimer`, `g_interactBtn`, and `g_interactBtnGlow` runtime variables.
- Window height reduced back to 510 px.

---

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
