# Solo Install Feature

Allows users to install a single optional item from Managed Software Center without triggering
all other pending updates. Also adds a `--pkg` flag to `managedsoftwareupdate` for terminal/agent use.

---

## How to Build

### Prerequisites
- Xcode 15+
- macOS 14+ (arm64 or x86_64)
- The repo at `/Users/aalequin/opensource/munki` (adjust paths as needed)

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
Xcode's DerivedData directory. You run it directly from there for testing.

### Run Unit Tests

```bash
xcodebuild \
  -project code/cli/munki/munki.xcodeproj \
  -scheme munkiCLItesting \
  test \
  -destination "platform=macOS,arch=arm64"
```

All solo install tests are in `code/cli/munki/munkiCLItesting/soloInstallTests.swift`.
You should see output like:

```
Test suite 'soloInstallFilterTests' started
Test case 'soloInstallFilterTests/filterBySoloNameExactMatch()' passed
Test case 'soloInstallFilterTests/filterBySoloNameCaseInsensitiveLower()' passed
Test case 'soloInstallFilterTests/filterBySoloNameCaseInsensitiveUpper()' passed
...
Test suite 'soloInstallTriggerFileTests' passed
Test suite 'allowSoloInstallKeyTests' passed
```

---

## How to Test Locally (with Production Munki Installed)

> **Your production munki at `/usr/local/munki/` is NOT touched by the build.** Xcode puts
> everything in DerivedData. You swap in the new binary only when you're ready to test it.

### Step 1 — Enable the Solo Install Preference

```bash
sudo defaults write /Library/Preferences/ManagedInstalls AllowSoloInstall -bool true

# Option A: allow ALL optional items to be solo-installed
sudo defaults write /Library/Preferences/ManagedInstalls AllowSoloInstallForAllManifestItems -bool true

# Option B: only items with allow_solo_install:true in pkginfo (see pkginfo section below)
# (leave AllowSoloInstallForAllManifestItems at false or absent)
```

Verify:
```bash
defaults read /Library/Preferences/ManagedInstalls AllowSoloInstall
defaults read /Library/Preferences/ManagedInstalls AllowSoloInstallForAllManifestItems
```

### Step 2 — Test the CLI (`--pkg` flag)

Build the binary first (see above), then locate it:

```bash
MSU=$(find ~/Library/Developer/Xcode/DerivedData/munki-* \
  -name managedsoftwareupdate -type f 2>/dev/null | head -1)
echo "Built binary: $MSU"
```

Do a dry check to make sure it picks up pending installs:
```bash
sudo "$MSU" --checkonly -v
```

Then do a solo install of one item (case-insensitive):
```bash
sudo "$MSU" --installonly --pkg "Firefox"
# or
sudo "$MSU" --installonly --pkg "firefox"
```

Expected behavior:
- Only `Firefox` is installed
- All other items remain in `/Library/Managed Installs/InstallInfo.plist`
- Log at `/Library/Managed Installs/Logs/ManagedSoftwareUpdate.log` shows:
  ```
  ### Beginning solo installer session for: Firefox ###
  ```

Confirm other items are still pending after the solo install:
```bash
/usr/bin/plutil -p /Library/Managed\ Installs/InstallInfo.plist | grep '"name"'
```

### Step 3 — Swap in the New Binary for a Full Run

> ⚠️  Back up your production binary first.

```bash
sudo cp /usr/local/munki/managedsoftwareupdate /usr/local/munki/managedsoftwareupdate.bak

MSU=$(find ~/Library/Developer/Xcode/DerivedData/munki-* \
  -name managedsoftwareupdate -type f 2>/dev/null | head -1)

sudo cp "$MSU" /usr/local/munki/managedsoftwareupdate
sudo chmod 755 /usr/local/munki/managedsoftwareupdate

# Verify
/usr/local/munki/managedsoftwareupdate --version
```

Restore production binary if needed:
```bash
sudo cp /usr/local/munki/managedsoftwareupdate.bak /usr/local/munki/managedsoftwareupdate
```

### Step 4 — Test the MSC App UI

Run the built MSC app directly from DerivedData (does NOT replace your production app):

```bash
MSC_APP=$(find ~/Library/Developer/Xcode/DerivedData/Managed_Software_Center-* \
  -name "Managed Software Center.app" -type d 2>/dev/null | head -1)
echo "Built app: $MSC_APP"
open "$MSC_APP"
```

With `AllowSoloInstall = true` and either `AllowSoloInstallForAllManifestItems = true` or a
matching pkginfo key, clicking **Install** on a catalog item will install only that item.
The item's status shows the standard `installing` animation while the backend runs.

> **Note:** The MSC app communicates with `managedsoftwareupdate` via launchd trigger files
> (see IPC section below). For a full end-to-end UI test you need Step 3 done first
> (the production `/usr/local/munki/managedsoftwareupdate` replaced with the new binary),
> because launchd launches the binary at that path.

---

## pkginfo Key: `allow_solo_install`

Add this boolean to any pkginfo to allow that specific item to be solo-installed when
`AllowSoloInstall = true` in preferences (and `AllowSoloInstallForAllManifestItems` is false
or absent):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <key>name</key>
    <string>Firefox</string>
    <key>version</key>
    <string>120.0</string>
    <!-- ... other keys ... -->

    <!-- ADD THIS to allow solo install for this specific item -->
    <key>allow_solo_install</key>
    <true/>
</dict>
</plist>
```

After adding the key to pkginfo, run `makecatalogs` to rebuild catalogs, then
`managedsoftwareupdate --checkonly` so the flag propagates into `InstallInfo.plist`.

---

## Preferences Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `AllowSoloInstall` | Bool | `false` | Master toggle. Must be `true` for any solo install to work. |
| `AllowSoloInstallForAllManifestItems` | Bool | `false` | When `true`, every optional install item gets solo-install behavior. When `false`, only items with `allow_solo_install: true` in their pkginfo qualify. |

Set via:
```bash
sudo defaults write /Library/Preferences/ManagedInstalls AllowSoloInstall -bool true
sudo defaults write /Library/Preferences/ManagedInstalls AllowSoloInstallForAllManifestItems -bool true
```

Or via a Configuration Profile (MDM) targeting the `ManagedInstalls` domain.

---

## CLI Flag Reference

```
managedsoftwareupdate --installonly --pkg "PackageName"
```

| Flag | Description |
|------|-------------|
| `--pkg <name>` | Install only the named item (case-insensitive). All other pending updates are preserved in `InstallInfo.plist` for the next run. |

Can be combined with `--installonly` (skips updatecheck) or used alone (runs check first).

Examples:
```bash
# Install only Firefox, skip other pending updates
sudo managedsoftwareupdate --installonly --pkg "Firefox"

# Case-insensitive — same result
sudo managedsoftwareupdate --installonly --pkg "FIREFOX"

# Check for updates first, then install only Slack
sudo managedsoftwareupdate --pkg "Slack"
```

---

## Architecture / How It Works

### IPC: MSC → managedsoftwareupdate

MSC triggers installs by writing a plist to a launchd-watched file:

**Normal install** (`/private/tmp/.com.googlecode.munki.managedinstall.launchd`):
```xml
<dict>
    <key>LaunchStagedOSInstaller</key><false/>
</dict>
```

**Solo install** (same file, new key):
```xml
<dict>
    <key>LaunchStagedOSInstaller</key><false/>
    <key>SoloInstallItemName</key><string>Firefox</string>
</dict>
```

launchd sees the file appear and launches:
```
/usr/local/munki/managedsoftwareupdate --installwithnologout
```

The backend reads `SoloInstallItemName` and filters `InstallInfo.plist` accordingly.

### Install Filtering

When a solo item name is set, `doInstallsAndRemovals` in `installer.swift`:
1. Filters `managed_installs` to only the named item (case-insensitive)
2. Installs only that item
3. On success: removes only that item from `InstallInfo.plist`
4. On failure: leaves everything as-is
5. All **other** pending items remain in `InstallInfo.plist` unchanged

### MSC UI Decision Point

In `actionButtonPerformAction` → `updateNow()`:
- If `canSoloInstall(item_name)` returns `true`, sets `_pendingSoloInstallItem`
- Bypasses the "other pending updates require your approval" alert for solo installs
- After updatecheck completes, calls `kickOffSoloInstallSession(itemName:)` instead of `kickOffInstallSession()`
- Only that item's status is set to `"installing"` in the DOM

---

## Files Changed

### Backend (Swift CLI)
| File | Change |
|------|--------|
| `code/cli/munki/shared/prefs.swift` | Added `AllowSoloInstall`, `AllowSoloInstallForAllManifestItems` to defaults and config key list |
| `code/cli/munki/managedsoftwareupdate/msuoptions.swift` | Added `--pkg` option to `MSUOtherOptions` |
| `code/cli/munki/managedsoftwareupdate/managedsoftwareupdate.swift` | Reads `--pkg` flag and `SoloInstallItemName` from trigger file; passes `soloInstallItemName` through install pipeline |
| `code/cli/munki/managedsoftwareupdate/msuutils.swift` | Added `soloItemName` param to `doInstallTasks()` |
| `code/cli/munki/shared/installer/installer.swift` | Added `soloItemName` param to `doInstallsAndRemovals()`; filters install list; preserves non-solo items in `InstallInfo.plist` |
| `code/cli/munki/shared/updatecheck/analyze.swift` | Added `allow_solo_install` to `optionalKeys` so the pkginfo flag propagates into `InstallInfo.plist` |

### Frontend (Swift MSC App)
| File | Change |
|------|--------|
| `code/apps/Managed Software Center/.../munki.swift` | Added `soloJustUpdate(itemName:)` — writes `SoloInstallItemName` to trigger file |
| `code/apps/Managed Software Center/.../MainWindowController.swift` | Added `_pendingSoloInstallItem`, `canSoloInstall()`, `kickOffSoloInstallSession()`, `markSoloItemAsInstalling()`; modified `updateNow()` and `actionButtonPerformAction()` |

### Python Backend (legacy path)
| File | Change |
|------|--------|
| `code/client/munkilib/prefs.py` | Added `AllowSoloInstall`, `AllowSoloInstallForAllManifestItems` to `DEFAULT_PREFS` |
| `code/client/munkilib/updatecheck/analyze.py` | Added `allow_solo_install` to `optional_keys` |

### Tests
| File | Description |
|------|-------------|
| `code/cli/munki/munkiCLItesting/soloInstallTests.swift` | Unit tests for filtering logic, case-insensitivity, item preservation, trigger file parsing, and pkginfo key handling |

---

## Known Limitations / Future Work

- **Progress bar**: The item shows the standard `"installing"` animated status (spinner) in the
  MSC catalog view. A true per-item determinate progress bar would require changes to the HTML/JS
  UI templates in `code/apps/Managed Software Center/.../html/` — that's a follow-on task.
- **Removals**: Solo install currently only applies to installs, not removals. A
  `--remove-pkg` flag and `allow_solo_remove` pkginfo key would be symmetric extensions.
- **`--logoutinstall` path**: Solo install only works for `--installwithnologout` (the MSC
  in-session path). Items requiring logout/restart are not yet filtered for solo installs.
- **Integration test**: The above steps use the real `launchd` pipeline. A more automated
  integration test would use a mock `InstallInfo.plist` and fake trigger file — see the
  `munkitester` target for examples of that pattern.
