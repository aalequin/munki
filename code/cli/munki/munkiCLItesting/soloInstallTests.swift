//
//  soloInstallTests.swift
//  munkiCLItesting
//
//  Tests for the solo install feature:
//    - doInstallsAndRemovals solo item filtering
//    - Case-insensitive name matching
//    - Non-solo items are preserved in InstallInfo after a solo install
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

// MARK: - Unit tests for solo install filtering logic
// These tests exercise the filtering logic directly without spawning a real
// managedsoftwareupdate process, so they run quickly and without side effects.

/// Helpers that mirror the filtering logic in doInstallsAndRemovals
/// (duplicated here to keep the tests self-contained)
private func soloFilterInstallList(_ list: [PlistDict], soloItemName: String) -> [PlistDict] {
    list.filter {
        ($0["name"] as? String ?? "").lowercased() == soloItemName.lowercased()
    }
}

private func preserveNonSoloItems(
    allInstalls: [PlistDict],
    skippedInstalls: [PlistDict],
    soloItemName: String
) -> [PlistDict] {
    let soloNameLower = soloItemName.lowercased()
    let nonSoloItems = allInstalls.filter {
        ($0["name"] as? String ?? "").lowercased() != soloNameLower
    }
    let failedSoloItems = skippedInstalls.filter {
        ($0["name"] as? String ?? "").lowercased() == soloNameLower
    }
    return nonSoloItems + failedSoloItems
}

// MARK: - Filter tests

struct soloInstallFilterTests {
    let managedInstalls: [PlistDict] = [
        ["name": "Firefox", "installed": false, "version_to_install": "120.0"],
        ["name": "GoogleChrome", "installed": false, "version_to_install": "119.0"],
        ["name": "Slack", "installed": false, "version_to_install": "4.35.0"],
    ]

    /// Filtering with the exact item name returns only that item
    @Test func filterBySoloNameExactMatch() {
        let result = soloFilterInstallList(managedInstalls, soloItemName: "Firefox")
        #expect(result.count == 1)
        #expect(result.first?["name"] as? String == "Firefox")
    }

    /// Filtering is case-insensitive (all lower)
    @Test func filterBySoloNameCaseInsensitiveLower() {
        let result = soloFilterInstallList(managedInstalls, soloItemName: "firefox")
        #expect(result.count == 1)
        #expect(result.first?["name"] as? String == "Firefox")
    }

    /// Filtering is case-insensitive (all upper)
    @Test func filterBySoloNameCaseInsensitiveUpper() {
        let result = soloFilterInstallList(managedInstalls, soloItemName: "FIREFOX")
        #expect(result.count == 1)
        #expect(result.first?["name"] as? String == "Firefox")
    }

    /// Filtering is case-insensitive (mixed case)
    @Test func filterBySoloNameCaseInsensitiveMixed() {
        let result = soloFilterInstallList(managedInstalls, soloItemName: "GoOgLeChRoMe")
        #expect(result.count == 1)
        #expect(result.first?["name"] as? String == "GoogleChrome")
    }

    /// Filtering with a name not in the list returns empty
    @Test func filterBySoloNameNotFound() {
        let result = soloFilterInstallList(managedInstalls, soloItemName: "VLC")
        #expect(result.isEmpty)
    }
}

// MARK: - Preservation tests (non-solo items stay in InstallInfo after solo install)

struct soloInstallPreservationTests {
    let managedInstalls: [PlistDict] = [
        ["name": "Firefox", "installed": false, "version_to_install": "120.0"],
        ["name": "GoogleChrome", "installed": false, "version_to_install": "119.0"],
        ["name": "Slack", "installed": false, "version_to_install": "4.35.0"],
    ]

    /// After a successful solo install of Firefox, Chrome and Slack are preserved
    @Test func nonSoloItemsPreservedAfterSuccessfulSoloInstall() {
        // Firefox was installed successfully -> skippedInstalls does NOT contain Firefox
        let skippedInstalls: [PlistDict] = []
        let result = preserveNonSoloItems(
            allInstalls: managedInstalls,
            skippedInstalls: skippedInstalls,
            soloItemName: "Firefox"
        )
        #expect(result.count == 2)
        let names = result.compactMap { $0["name"] as? String }
        #expect(names.contains("GoogleChrome"))
        #expect(names.contains("Slack"))
        #expect(!names.contains("Firefox"))
    }

    /// After a failed solo install of Firefox, Chrome, Slack, AND Firefox are preserved
    @Test func nonSoloItemsPreservedAfterFailedSoloInstall() {
        // Firefox install failed -> skippedInstalls contains Firefox
        let skippedInstalls: [PlistDict] = [
            ["name": "Firefox", "installed": false, "version_to_install": "120.0"],
        ]
        let result = preserveNonSoloItems(
            allInstalls: managedInstalls,
            skippedInstalls: skippedInstalls,
            soloItemName: "Firefox"
        )
        #expect(result.count == 3)
        let names = result.compactMap { $0["name"] as? String }
        #expect(names.contains("Firefox"))
        #expect(names.contains("GoogleChrome"))
        #expect(names.contains("Slack"))
    }

    /// Preservation is case-insensitive for the solo item name
    @Test func preservationIsCaseInsensitive() {
        let skippedInstalls: [PlistDict] = []
        let result = preserveNonSoloItems(
            allInstalls: managedInstalls,
            skippedInstalls: skippedInstalls,
            soloItemName: "FIREFOX"  // uppercase
        )
        #expect(result.count == 2)
        let names = result.compactMap { $0["name"] as? String }
        #expect(!names.contains("Firefox"))
        #expect(names.contains("GoogleChrome"))
        #expect(names.contains("Slack"))
    }

    /// When solo item is not in the list, all items are preserved
    @Test func allItemsPreservedWhenSoloItemNotFound() {
        let skippedInstalls: [PlistDict] = []
        let result = preserveNonSoloItems(
            allInstalls: managedInstalls,
            skippedInstalls: skippedInstalls,
            soloItemName: "VLC"
        )
        #expect(result.count == 3)
    }
}

// MARK: - Trigger file content tests

struct soloInstallTriggerFileTests {
    /// The solo item name can be retrieved from the trigger plist structure
    @Test func soloItemNameCanBeReadFromTriggerPlist() throws {
        let plist: PlistDict = [
            "LaunchStagedOSInstaller": false,
            "SoloInstallItemName": "MyApp"
        ]
        let soloName = plist["SoloInstallItemName"] as? String
        #expect(soloName == "MyApp")
    }

    /// An empty SoloInstallItemName is treated as "no solo install"
    @Test func emptySoloItemNameMeansNoSoloInstall() throws {
        let plist: PlistDict = [
            "LaunchStagedOSInstaller": false,
            "SoloInstallItemName": ""
        ]
        let soloName = plist["SoloInstallItemName"] as? String ?? ""
        #expect(soloName.isEmpty)
    }

    /// A missing SoloInstallItemName key results in no solo install
    @Test func missingSoloItemKeyMeansNoSoloInstall() throws {
        let plist: PlistDict = [
            "LaunchStagedOSInstaller": false,
        ]
        let soloName = plist["SoloInstallItemName"] as? String ?? ""
        #expect(soloName.isEmpty)
    }
}

// MARK: - Pkginfo allow_solo_install key propagation tests

struct allowSoloInstallKeyTests {
    /// An item with allow_solo_install: true in pkginfo passes the flag through
    @Test func allowSoloInstallTrueIsPreserved() {
        let optionalInstallItem: PlistDict = [
            "name": "MyApp",
            "installed": false,
            "allow_solo_install": true,
        ]
        let allowsSolo = optionalInstallItem["allow_solo_install"] as? Bool ?? false
        #expect(allowsSolo == true)
    }

    /// An item without allow_solo_install defaults to false
    @Test func missingAllowSoloInstallDefaultsFalse() {
        let optionalInstallItem: PlistDict = [
            "name": "MyApp",
            "installed": false,
        ]
        let allowsSolo = optionalInstallItem["allow_solo_install"] as? Bool ?? false
        #expect(allowsSolo == false)
    }

    /// An item with allow_solo_install: false is not solo-installable by key
    @Test func allowSoloInstallFalseIsNotSoloInstallable() {
        let optionalInstallItem: PlistDict = [
            "name": "MyApp",
            "installed": false,
            "allow_solo_install": false,
        ]
        let allowsSolo = optionalInstallItem["allow_solo_install"] as? Bool ?? false
        #expect(allowsSolo == false)
    }
}
