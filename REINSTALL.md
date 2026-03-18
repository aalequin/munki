# Reinstall Feature

Adds a **Reinstall** button to installed items in Managed Software Center's My Items view.
No new preferences are required — the button appears automatically for any installed item.

Button layout by item type:

| Item type | Buttons |
|-----------|---------|
| `managed_install` (installed) | **Reinstall** only (cannot be removed) |
| `managed_update` (installed) | **Reinstall** + Remove |
| `optional_installs` (installed, user-selected) | **Reinstall** + Remove |

All installed managed items now appear in My Items even if the user never explicitly
selected them via Self Service.

---

## How to Build

### Prerequisites

- Xcode 15+
- macOS 14+ (arm64 or x86_64)
- The repo at `/Users/aalequin/opensource/munki` (adjust paths as needed)
- Production Munki installed at `/usr/local/munki/` with a working munki server/repo

### Build `managedsoftwareupdate` CLI

```bash
cd /Users/aalequin/opensource/munki

xcodebuild \
  -project code/cli/munki/munki.xcodeproj \
  -scheme managedsoftwareupdate \
  -destination "platform=macOS,arch=arm64" \
  -configuration Debug \
  build
```

The built binary ends up at:
```
~/Library/Developer/Xcode/DerivedData/munki-*/Build/Products/Debug/managedsoftwareupdate
```

Quick one-liner to find it:
```bash
find ~/Library/Developer/Xcode/DerivedData/munki-* \
  -name managedsoftwareupdate -type f 2>/dev/null | head -1
```

### Build Managed Software Center.app

```bash
xcodebuild \
  -project "code/apps/Managed Software Center/Managed Software Center.xcodeproj" \
  -scheme "Managed Software Center" \
  -destination "platform=macOS,arch=arm64" \
  -configuration Debug \
  build
```

The built app ends up at:
```
~/Library/Developer/Xcode/DerivedData/Managed_Software_Center-*/Build/Products/Debug/Managed Software Center.app
```

**The build does NOT overwrite `/Applications/Managed Software Center.app`** — it goes to
Xcode's DerivedData directory.

### Run Unit Tests

```bash
xcodebuild \
  -project code/cli/munki/munki.xcodeproj \
  -scheme munkiCLItesting \
  test \
  -destination "platform=macOS,arch=arm64"
```

All reinstall tests are in `code/cli/munki/munkiCLItesting/reinstallTests.swift`.
You should see output like:

```
Test suite 'reinstallFilterTests' started
Test case 'reinstallFilterTests/forceReinstallFilterIncludesInstalledItem()' passed
Test case 'reinstallFilterTests/normalFilterExcludesInstalledItem()' passed
Test case 'reinstallFilterTests/reinstallFilterPreservesNonReinstallItems()' passed
Test suite 'managedReinstallsParsingTests' started
Test case 'managedReinstallsParsingTests/managedReinstallsKeyParsing()' passed
Test case 'managedReinstallsParsingTests/missingManagedReinstallsKeyReturnsEmpty()' passed
Test suite 'myItemsStatusTests' started
Test case 'myItemsStatusTests/myItemsManagedInstallHasNotRemovableStatus()' passed
Test case 'myItemsStatusTests/myItemsManagedUpdateHasInstalledStatus()' passed
Test case 'myItemsStatusTests/myItemsOptionalInstallsNotDuplicated()' passed
** TEST SUCCEEDED **
```

---

## End-to-End Testing

> **Your production munki at `/usr/local/munki/` is NOT touched by the build.** Xcode puts
> everything in DerivedData. You swap in the new binary and app only when ready to test.

### Step 1 — Verify you have installed items to test with

Run a check to make sure InstallInfo.plist has items with `installed: true`:

```bash
sudo /usr/local/munki/managedsoftwareupdate --checkonly -v
```

Then inspect the result:
```bash
/usr/bin/plutil -p /Library/Managed\ Installs/InstallInfo.plist | grep -A2 '"installed"'
```

You need at least one item in `managed_installs` where `"installed" => 1`. If nothing shows
as installed, install something first, re-run `--checkonly`, and confirm it now appears with
`installed: true`.

You can also check what managed items exist:
```bash
/usr/bin/plutil -p /Library/Managed\ Installs/InstallInfo.plist | grep '"name"'
```

### Step 2 — Swap in the new `managedsoftwareupdate` binary

> ⚠️  Back up your production binary first.

```bash
sudo cp /usr/local/munki/managedsoftwareupdate /usr/local/munki/managedsoftwareupdate.bak

MSU=$(find ~/Library/Developer/Xcode/DerivedData/munki-* \
  -name managedsoftwareupdate -type f 2>/dev/null | head -1)
echo "Built binary: $MSU"

sudo cp "$MSU" /usr/local/munki/managedsoftwareupdate
sudo chmod 755 /usr/local/munki/managedsoftwareupdate

# Verify
/usr/local/munki/managedsoftwareupdate --version
```

This is required for the full UI flow. The MSC app triggers installs by writing a launchd
trigger file, and launchd launches the binary at `/usr/local/munki/managedsoftwareupdate`.
If you skip this step, clicking Reinstall in the UI will use the old binary and the
`managed_reinstalls` key in SelfServeManifest will be ignored.

### Step 3 — Run the built MSC app

Run the built app directly from DerivedData (does NOT replace your production app):

```bash
MSC_APP=$(find ~/Library/Developer/Xcode/DerivedData/Managed_Software_Center-* \
  -name "Managed Software Center.app" -type d 2>/dev/null | head -1)
echo "Built app: $MSC_APP"
open "$MSC_APP"
```

### Step 4 — Navigate to My Items and verify Reinstall buttons appear

1. Open the built Managed Software Center app (from Step 3)
2. Click **My Items** in the sidebar
3. You should see:
   - Any `managed_install` or `managed_update` items that are currently installed listed here
     (previously these only appeared in the Updates tab)
   - A **Reinstall** button on each installed item
   - `managed_install` items show **Reinstall** only (no Remove)
   - `managed_update` and user-selected optional items show **Reinstall** + **Remove**

If My Items is empty, it means no items are currently installed and tracked. Run
`--checkonly` first (Step 1) to populate InstallInfo.plist.

### Step 5 — Click Reinstall on an item

1. Pick any installed item shown in My Items
2. Click its **Reinstall** button
3. Expected behavior:
   - The item's status changes to show activity (spinner)
   - A progress window appears (the standard Munki status window)
   - Munki runs an updatecheck first (to re-download the package if needed)
   - Then runs the install for only that item
   - Other pending items are **not** affected
4. After the session completes, My Items reloads and the item shows as **Installed**

### Step 6 — Verify only the reinstalled item was touched

Check the log to confirm only the target item was reinstalled:

```bash
tail -50 /Library/Managed\ Installs/Logs/ManagedSoftwareUpdate.log
```

You should see something like:

```
### Beginning managed software check ###
...
### Beginning solo installer session for: Firefox ###
Installing Firefox (1 of 1)
Install of Firefox-120.0: SUCCESSFUL
```

Confirm other pending items are still in InstallInfo.plist:

```bash
/usr/bin/plutil -p /Library/Managed\ Installs/InstallInfo.plist | grep '"name"'
```

### Step 7 — Verify SelfServeManifest is cleaned up

After a successful reinstall, the item should be removed from `managed_reinstalls` in the
SelfServeManifest. Confirm it is gone:

```bash
/usr/bin/plutil -p /Library/Managed\ Installs/manifests/SelfServeManifest 2>/dev/null \
  || echo "SelfServeManifest does not exist (OK if never used Self Service)"
```

The `managed_reinstalls` key should either be absent or empty.

### Step 8 — Test a failed reinstall (optional)

To verify that a failed reinstall leaves the item in a retryable state:

1. Disconnect from the network (or point munki at an invalid repo URL temporarily)
2. Click **Reinstall** on an item
3. The updatecheck phase should fail (can't download the package)
4. The item should remain in My Items with its original status
5. Reconnect and retry — it should work

---

## CLI Reinstall (without UI)

You can trigger a reinstall directly from the terminal using the `--pkg` flag.
This works for **any item the machine is scoped for** — it does not require the item
to be pending or not yet installed.

### Step 1 — Find the item name

Check what's available in your catalogs by looking at optional_installs or managed_installs:

```bash
/usr/bin/plutil -p /Library/Managed\ Installs/InstallInfo.plist | grep '"name"'
```

### Step 2 — Reinstall with --pkg

```bash
sudo /usr/local/munki/managedsoftwareupdate --pkg "GoogleChrome" -v
```

What happens internally:
1. `GoogleChrome` is written to `managed_reinstalls` in SelfServeManifest
2. The updatecheck runs and sees `managed_reinstalls: ["GoogleChrome"]`
3. `processInstall` is called with `forceReinstall: true` — bypasses the "already installed"
   check, downloads the package
4. The installer runs a solo install of GoogleChrome only
5. `managed_reinstalls` is cleaned up (regardless of success/failure)

### Step 3 — Verify the reinstall

Check the install log:

```bash
grep "GoogleChrome" /Library/Managed\ Installs/Logs/Install.log | tail -5
```

You should see `Install of GoogleChrome-...: SUCCESSFUL`.

### Step 4 — Confirm managed_reinstalls was cleaned up

```bash
/usr/bin/defaults read /Library/Managed\ Installs/manifests/SelfServeManifest \
  managed_reinstalls 2>/dev/null || echo "key absent (expected)"
```

---

## Restore Production Binary

If you need to revert to your original `managedsoftwareupdate`:

```bash
sudo cp /usr/local/munki/managedsoftwareupdate.bak /usr/local/munki/managedsoftwareupdate
```

---

## Architecture / How It Works

### Reinstall Flow

```
User clicks Reinstall
        │
        ▼
SelfService.requestReinstall(itemName)
  → writes managed_reinstalls: ["Firefox"] to /Users/Shared/.SelfServeManifest
        │
        ▼
kickOffReinstallSession(itemName:)
  → sets _pendingSoloInstallItem = itemName
  → calls startUpdateCheck(true)  [tasktype = "checktheninstall"]
        │
        ▼
managedsoftwareupdate --checkonly (suppress Apple updates)
  → processSelfServeManifest reads managed_reinstalls
  → calls processInstall("Firefox", forceReinstall: true)
  → bypasses "already installed" check
  → downloads the package
  → sets force_reinstall: true on item in managed_installs (installed: false)
        │
        ▼
munkiStatusSessionEnded (tasktype = "checktheninstall")
  → clearMunkiItemsCache()
  → updateNow()
  → _pendingSoloInstallItem is set → kickOffSoloInstallSession("Firefox")
        │
        ▼
managedsoftwareupdate --installwithnologout
  [SoloInstallItemName: "Firefox" in trigger file]
  → doInstallsAndRemovals(soloItemName: "Firefox")
  → installs only Firefox (force_reinstall: true bypasses installed filter)
  → on success: removeFromSelfServeReinstalls("Firefox")
        │
        ▼
My Items reloads — Firefox shows as Installed
```

### Key Files

#### Backend (Swift CLI)

| File | Change |
|------|--------|
| `code/cli/munki/shared/updatecheck/analyze.swift` | `processInstall` gets `forceReinstall: Bool = false` — bypasses installed-check, forces download, sets `force_reinstall: true` on item |
| `code/cli/munki/shared/updatecheck/updatecheck.swift` | `processSelfServeManifest` processes `managed_reinstalls` key |
| `code/cli/munki/shared/updatecheck/manifests.swift` | Added `removeFromSelfServeReinstalls()` |
| `code/cli/munki/shared/installer/installer.swift` | Calls `removeFromSelfServeReinstalls` after successful force-reinstall |

#### Frontend (Swift MSC App)

| File | Change |
|------|--------|
| `code/apps/Managed Software Center/.../SelfService.swift` | Added `_reinstalls` set, `requestReinstall`/`cancelReinstall` methods, `managed_reinstalls` saved to manifest |
| `code/apps/Managed Software Center/.../MunkiItems.swift` | `reinstall_button()`, expanded `getMyItemsList()` to include installed managed items, new status strings |
| `code/apps/Managed Software Center/.../Resources/templates/myitems_item_template.html` | Added `${reinstall_button}` slot |
| `code/apps/Managed Software Center/.../Controllers/MainWindowController+WKScriptMessageHandler.swift` | `reinstallButtonClicked` handler + `kickOffReinstallSession` |
| `code/apps/Managed Software Center/.../Controllers/MainWindowController.swift` | Registered `reinstallButtonClicked` message handler |

#### Tests

| File | Description |
|------|-------------|
| `code/cli/munki/munkiCLItesting/reinstallTests.swift` | 7 unit tests: force-reinstall filter logic, `managed_reinstalls` key parsing, My Items status assignment |

---

## Known Limitations / Future Work

- **Progress feedback**: The item shows the standard animated spinner during reinstall.
  A per-item determinate progress bar would require changes to the HTML/JS UI templates.
- **Logout-required items**: Reinstall only works for items installable without logout
  (`--installwithnologout` path). Items requiring restart/logout are not yet supported.
- **`--installonly --pkg`**: If `--installonly` is combined with `--pkg`, the updatecheck
  is skipped and the package may not be re-downloaded. Use `--pkg` alone (without
  `--installonly`) to ensure the package is fetched before reinstalling.
- **Removals**: There is no `Reinstall` equivalent for removals.
- **Integration test**: The above steps use the real launchd pipeline. A more automated
  integration test would mock the trigger file and SelfServeManifest paths.
