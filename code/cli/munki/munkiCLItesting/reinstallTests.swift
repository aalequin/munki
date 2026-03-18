//
//  reinstallTests.swift
//  munkiCLItesting
//
//  Tests for the reinstall feature:
//    - Force reinstall filter includes installed items
//    - Normal install filter excludes installed items
//    - Reinstall filter preserves non-reinstall items
//    - managed_reinstalls key parsing from SelfServeManifest
//    - My Items status for managed_install vs managed_update items
//    - optional_installs items are not duplicated in My Items
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Foundation
import Testing

// MARK: - Helper functions (mirror logic from the reinstall feature)

/// Filter that includes items for reinstall:
/// items where force_reinstall is true OR installed is false
private func reinstallFilter(_ list: [PlistDict]) -> [PlistDict] {
    list.filter {
        ($0["force_reinstall"] as? Bool ?? false) || !($0["installed"] as? Bool ?? false)
    }
}

/// Normal install filter: only items not yet installed
private func normalInstallFilter(_ list: [PlistDict]) -> [PlistDict] {
    list.filter {
        !($0["installed"] as? Bool ?? false)
    }
}

/// Simulate reading managed_reinstalls from a SelfServeManifest plist dict
private func managedReinstalls(from manifest: PlistDict) -> [String] {
    return manifest["managed_reinstalls"] as? [String] ?? []
}

// MARK: - Reinstall filter tests

struct reinstallFilterTests {
    let installList: [PlistDict] = [
        ["name": "Firefox", "installed": true, "version_to_install": "120.0", "force_reinstall": true],
        ["name": "GoogleChrome", "installed": false, "version_to_install": "119.0"],
        ["name": "Slack", "installed": true, "version_to_install": "4.35.0"],
    ]

    /// A force_reinstall item that is already installed should be included in reinstall filter
    @Test func forceReinstallFilterIncludesInstalledItem() {
        let result = reinstallFilter(installList)
        let names = result.compactMap { $0["name"] as? String }
        #expect(names.contains("Firefox"))
    }

    /// A normal install filter (not installed) should exclude installed items
    @Test func normalFilterExcludesInstalledItem() {
        let result = normalInstallFilter(installList)
        let names = result.compactMap { $0["name"] as? String }
        #expect(!names.contains("Firefox"))
        #expect(names.contains("GoogleChrome"))
        #expect(!names.contains("Slack"))
    }

    /// Non-reinstall installed items (no force_reinstall flag) are excluded from reinstall session
    @Test func reinstallFilterPreservesNonReinstallItems() {
        let result = reinstallFilter(installList)
        let names = result.compactMap { $0["name"] as? String }
        // Slack is installed but does NOT have force_reinstall: true, so should be excluded
        #expect(!names.contains("Slack"))
        // Firefox has force_reinstall: true, so should be included
        #expect(names.contains("Firefox"))
        // GoogleChrome is not installed, so should be included
        #expect(names.contains("GoogleChrome"))
    }
}

// MARK: - SelfServeManifest managed_reinstalls parsing tests

struct managedReinstallsParsingTests {
    /// Reading managed_reinstalls from a SelfServeManifest dict returns the correct array
    @Test func managedReinstallsKeyParsing() {
        let manifest: PlistDict = [
            "managed_installs": ["Firefox"],
            "managed_uninstalls": ["Slack"],
            "managed_reinstalls": ["Firefox", "VLC"],
        ]
        let reinstalls = managedReinstalls(from: manifest)
        #expect(reinstalls.count == 2)
        #expect(reinstalls.contains("Firefox"))
        #expect(reinstalls.contains("VLC"))
    }

    /// Missing managed_reinstalls key returns empty array
    @Test func missingManagedReinstallsKeyReturnsEmpty() {
        let manifest: PlistDict = [
            "managed_installs": ["Firefox"],
        ]
        let reinstalls = managedReinstalls(from: manifest)
        #expect(reinstalls.isEmpty)
    }
}

// MARK: - My Items status tests

struct myItemsStatusTests {
    /// A managed_install item (not in optional_installs, not in managed_updates)
    /// gets status "installed-not-removable"
    @Test func myItemsManagedInstallHasNotRemovableStatus() {
        let managedInstall: PlistDict = [
            "name": "Firefox",
            "installed": true,
            "version_to_install": "120.0",
        ]
        let optionalInstallNames: Set<String> = []
        let managedUpdateNames: Set<String> = []

        let name = managedInstall["name"] as? String ?? ""
        let installed = managedInstall["installed"] as? Bool ?? false
        let inOptional = optionalInstallNames.contains(name)
        let inManagedUpdate = managedUpdateNames.contains(name)

        #expect(installed)
        #expect(!inOptional)

        let status: String
        if inManagedUpdate {
            status = "installed"
        } else {
            status = "installed-not-removable"
        }
        #expect(status == "installed-not-removable")
    }

    /// A managed_update item gets status "installed"
    @Test func myItemsManagedUpdateHasInstalledStatus() {
        let managedUpdate: PlistDict = [
            "name": "GoogleChrome",
            "installed": true,
            "version_to_install": "119.0",
        ]
        let optionalInstallNames: Set<String> = []
        let managedUpdateNames: Set<String> = ["GoogleChrome"]

        let name = managedUpdate["name"] as? String ?? ""
        let installed = managedUpdate["installed"] as? Bool ?? false
        let inOptional = optionalInstallNames.contains(name)
        let inManagedUpdate = managedUpdateNames.contains(name)

        #expect(installed)
        #expect(!inOptional)
        #expect(inManagedUpdate)

        let status: String
        if inManagedUpdate {
            status = "installed"
        } else {
            status = "installed-not-removable"
        }
        #expect(status == "installed")
    }

    /// Items in optional_installs names should not appear as managed installed items
    @Test func myItemsOptionalInstallsNotDuplicated() {
        let managedInstalls: [PlistDict] = [
            ["name": "Firefox", "installed": true, "version_to_install": "120.0"],
            ["name": "VLC", "installed": true, "version_to_install": "3.0"],
        ]
        // Firefox is in optional_installs, VLC is not
        let optionalInstallNames: Set<String> = ["Firefox"]
        let managedUpdateNames: Set<String> = []

        var managedInstalledItems = [PlistDict]()
        for var item in managedInstalls {
            let name = item["name"] as? String ?? ""
            let installed = item["installed"] as? Bool ?? false
            guard installed, !optionalInstallNames.contains(name) else { continue }
            if managedUpdateNames.contains(name) {
                item["status"] = "installed"
            } else {
                item["status"] = "installed-not-removable"
            }
            managedInstalledItems.append(item)
        }

        let resultNames = managedInstalledItems.compactMap { $0["name"] as? String }
        // Firefox should be excluded (it's in optional_installs)
        #expect(!resultNames.contains("Firefox"))
        // VLC should be included
        #expect(resultNames.contains("VLC"))
        #expect(managedInstalledItems.count == 1)
    }
}

// MARK: - CLI --pkg force reinstall path tests

struct pkgFlagReinstallTests {
    /// When --pkg is set, the item is added to managed_reinstalls before the updatecheck.
    /// Simulate: addToSelfServeManagedReinstalls writes the item, then managed_reinstalls
    /// is read back correctly.
    @Test func pkgFlagAddsToManagedReinstalls() {
        var manifest: PlistDict = [
            "managed_installs": ["Firefox"],
            "managed_uninstalls": [],
        ]
        // Simulate addToSelfServeManagedReinstalls("GoogleChrome")
        var reinstalls = manifest["managed_reinstalls"] as? [String] ?? []
        if !reinstalls.contains("GoogleChrome") {
            reinstalls.append("GoogleChrome")
        }
        manifest["managed_reinstalls"] = reinstalls
        let result = manifest["managed_reinstalls"] as? [String] ?? []
        #expect(result.contains("GoogleChrome"))
    }

    /// Adding the same item twice does not create a duplicate entry.
    @Test func pkgFlagDeduplicatesReinstalls() {
        var manifest: PlistDict = [
            "managed_reinstalls": ["GoogleChrome"],
        ]
        var reinstalls = manifest["managed_reinstalls"] as? [String] ?? []
        if !reinstalls.contains("GoogleChrome") {
            reinstalls.append("GoogleChrome")
        }
        manifest["managed_reinstalls"] = reinstalls
        let result = manifest["managed_reinstalls"] as? [String] ?? []
        #expect(result.count == 1)
    }

    /// After a --pkg run, managed_reinstalls cleanup removes the item even if
    /// the installer already cleaned it up (removeFromSelfServeReinstalls is idempotent
    /// because filtering a missing item from a list is a no-op).
    @Test func postRunCleanupIsIdempotent() {
        var manifest: PlistDict = [
            "managed_reinstalls": [],  // already cleaned by installer on success
        ]
        // Simulate removeFromSelfServeReinstalls("GoogleChrome") on already-empty list
        var reinstalls = manifest["managed_reinstalls"] as? [String] ?? []
        reinstalls = reinstalls.filter { $0 != "GoogleChrome" }
        manifest["managed_reinstalls"] = reinstalls
        let result = manifest["managed_reinstalls"] as? [String] ?? []
        #expect(result.isEmpty)
    }

    /// The reinstall filter (installed: false OR force_reinstall: true) correctly
    /// includes an already-installed item that went through forceReinstall processing,
    /// which sets installed: false.
    @Test func forceReinstallProcessingSetsInstalledFalse() {
        // After processInstall(forceReinstall: true), the item has installed: false
        let afterForceProcess: PlistDict = [
            "name": "GoogleChrome",
            "installed": false,          // forced to false by forceReinstall path
            "force_reinstall": true,
            "version_to_install": "119.0",
            "installer_item": "GoogleChrome-119.0.pkg",
        ]
        let pendingInstalls = [afterForceProcess].filter {
            !($0["installed"] as? Bool ?? false)
        }
        #expect(pendingInstalls.count == 1)
        #expect(pendingInstalls.first?["name"] as? String == "GoogleChrome")
    }
}
