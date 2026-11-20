import SwiftUI
import MacCleanKit

/// What a module's intro screen says (UI_SPEC §4.1, copy rules §9).
/// Copy is ours: calm, factual, no hype. English for now; the Phase 11 copy
/// pass adds the other languages.
struct ModuleIntro {
    struct Bullet: Hashable {
        let symbol: String
        let title: String
        let body: String
    }

    /// Placeholder for the hero illustration until our art exists (§2.5).
    let heroSymbol: String
    let subtitle: String
    let bullets: [Bullet]
    /// Primary button label on the intro.
    var action: String = L10n.tr("扫描", "Scan", "Сканировать")
}

extension SidebarItem {
    var intro: ModuleIntro {
        typealias B = ModuleIntro.Bullet
        switch self {
        case .smartScan:
            return ModuleIntro(
                heroSymbol: "sparkle.magnifyingglass",
                subtitle: "A quick look over cleanup, protection and speed in one pass.",
                bullets: [
                    B(symbol: "internaldrive", title: "Clears what's safe to clear",
                      body: "Caches, logs and leftovers that apps rebuild on their own."),
                    B(symbol: "ladybug", title: "Checks for threats",
                      body: "Looks for known adware and unwanted software."),
                    B(symbol: "gauge.with.dots.needle.67percent", title: "Finds easy speed-ups",
                      body: "Login items and maintenance tasks worth a look."),
                ],
                action: "Scan")
        case .systemJunk:
            return ModuleIntro(
                heroSymbol: "internaldrive",
                subtitle: "Caches, logs and leftovers that build up as you use your Mac.",
                bullets: [
                    B(symbol: "arrow.triangle.2.circlepath", title: "Rebuilt when needed",
                      body: "Most of what's found is recreated by apps the next time they need it."),
                    B(symbol: "checklist", title: "You choose",
                      body: "Review every category before anything is removed."),
                ])
        case .mailAttachments:
            return ModuleIntro(
                heroSymbol: "paperclip",
                subtitle: "Local copies of attachments that Mail has already downloaded.",
                bullets: [
                    B(symbol: "envelope", title: "Your mail stays put",
                      body: "Only the local copies go. Messages keep their attachments on the server."),
                    B(symbol: "arrow.down.circle", title: "Fetched again on demand",
                      body: "Open the message and Mail downloads the file again."),
                ])
        case .trashBins:
            return ModuleIntro(
                heroSymbol: "trash",
                subtitle: "Empty the Trash on your Mac and on connected drives in one go.",
                bullets: [
                    B(symbol: "externaldrive", title: "Every drive",
                      body: "Includes the hidden Trash folders on external disks."),
                    B(symbol: "exclamationmark.triangle", title: "Permanent",
                      body: "Emptied items can't be put back, so you'll be asked first."),
                ],
                action: "Scan")
        case .malwareRemoval:
            return ModuleIntro(
                heroSymbol: "ladybug",
                subtitle: "Scans for adware, unwanted apps and known threats.",
                bullets: [
                    B(symbol: "shield.lefthalf.filled", title: "Known signatures",
                      body: "Checks apps, launch agents and extensions against threat lists."),
                    B(symbol: "eye.slash", title: "Stays on your Mac",
                      body: "Nothing about your files is uploaded."),
                ])
        case .privacy:
            return ModuleIntro(
                heroSymbol: "lock",
                subtitle: "Browsing history, recent items and other traces you may not want kept.",
                bullets: [
                    B(symbol: "safari", title: "Per browser",
                      body: "Pick what to clear for each browser you use."),
                    B(symbol: "clock.arrow.circlepath", title: "Recent items",
                      body: "Clear the lists of recently opened files and apps."),
                ])
        case .wifiNetworks:
            return ModuleIntro(
                heroSymbol: "wifi",
                subtitle: "Wi-Fi networks your Mac remembers and joins on its own.",
                bullets: [
                    B(symbol: "list.bullet", title: "See them all",
                      body: "Including networks you joined once, years ago."),
                    B(symbol: "minus.circle", title: "Forget the old ones",
                      body: "Stops your Mac from joining networks you no longer trust."),
                ])
        case .appPermissions:
            return ModuleIntro(
                heroSymbol: "key",
                subtitle: "Which apps can use your camera, microphone, files and more.",
                bullets: [
                    B(symbol: "camera", title: "One overview",
                      body: "Every permission and the apps that have it, side by side."),
                    B(symbol: "gearshape", title: "Change in System Settings",
                      body: "Jump straight to the right pane to switch access off."),
                ],
                action: "View Apps")
        case .optimization:
            return ModuleIntro(
                heroSymbol: "slider.horizontal.3",
                subtitle: "Login items, background agents and apps using lots of memory.",
                bullets: [
                    B(symbol: "power", title: "Login items",
                      body: "Decide what starts when you log in."),
                    B(symbol: "memorychip", title: "Heavy apps",
                      body: "See what's using the most memory right now."),
                ],
                action: "Scan")
        case .maintenance:
            return ModuleIntro(
                heroSymbol: "gearshape.2",
                subtitle: "Routine housekeeping tasks for when things feel slow.",
                bullets: [
                    B(symbol: "externaldrive.badge.checkmark", title: "Disk and index",
                      body: "Free up purgeable space and rebuild Spotlight's index."),
                    B(symbol: "network", title: "Network and caches",
                      body: "Flush DNS and refresh system caches."),
                ],
                action: "Run")
        case .uninstaller:
            return ModuleIntro(
                heroSymbol: "shippingbox",
                subtitle: "Remove apps together with the files they leave behind.",
                bullets: [
                    B(symbol: "folder", title: "The whole app",
                      body: "Preferences, caches and support files go with it."),
                    B(symbol: "arrow.counterclockwise", title: "Reset instead",
                      body: "Keep the app but clear its data to start fresh."),
                ],
                action: "View Apps")
        case .unusedApps:
            return ModuleIntro(
                heroSymbol: "moon.zzz",
                subtitle: "Apps you haven't opened in a long time.",
                bullets: [
                    B(symbol: "calendar", title: "Last opened",
                      body: "Sorted by how long they've sat unused."),
                    B(symbol: "shippingbox", title: "Remove cleanly",
                      body: "Uninstall with their leftovers in one step."),
                ])
        case .extensions:
            return ModuleIntro(
                heroSymbol: "puzzlepiece.extension",
                subtitle: "Plug-ins, widgets and extensions added by your apps.",
                bullets: [
                    B(symbol: "list.bullet.rectangle", title: "All in one place",
                      body: "Spotlight, QuickLook, Preference panes and more."),
                    B(symbol: "minus.circle", title: "Remove what you don't use",
                      body: "Fewer extensions, fewer surprises."),
                ],
                action: "View All")
        case .updater:
            return ModuleIntro(
                heroSymbol: "arrow.up.circle",
                subtitle: "Check your apps for newer versions.",
                bullets: [
                    B(symbol: "checkmark.seal", title: "From the source",
                      body: "Updates come from each app's own update feed."),
                    B(symbol: "list.number", title: "One list",
                      body: "See what's new and update in one place."),
                ],
                action: "Check")
        case .spaceLens:
            return ModuleIntro(
                heroSymbol: "chart.pie",
                subtitle: "A map of what's taking up space, folder by folder.",
                bullets: [
                    B(symbol: "circle.circle", title: "See it at a glance",
                      body: "Bigger rings mean bigger folders."),
                    B(symbol: "cursorarrow.click", title: "Drill down",
                      body: "Click into any folder to find what's inside."),
                ])
        case .largeOldFiles:
            return ModuleIntro(
                heroSymbol: "archivebox",
                subtitle: "Big files and things you haven't touched in a while.",
                bullets: [
                    B(symbol: "arrow.up.arrow.down", title: "Sorted by size",
                      body: "The largest files come first."),
                    B(symbol: "calendar.badge.clock", title: "And by age",
                      body: "Spot files untouched for a year or more."),
                ])
        case .duplicates:
            return ModuleIntro(
                heroSymbol: "doc.on.doc",
                subtitle: "Identical copies of the same file in different places.",
                bullets: [
                    B(symbol: "number", title: "Byte for byte",
                      body: "Files are compared by content, not just by name."),
                    B(symbol: "star", title: "Keep the original",
                      body: "One copy in each group is always kept."),
                ])
        case .shredder:
            return ModuleIntro(
                heroSymbol: "scissors",
                subtitle: "Remove files so they can't be recovered.",
                bullets: [
                    B(symbol: "lock.doc", title: "Gone for good",
                      body: "Skips the Trash and overwrites where possible."),
                    B(symbol: "hand.raised", title: "Double-checked",
                      body: "You'll confirm before anything is removed."),
                ],
                action: "Select Files")
        case .browserExtensions:
            return ModuleIntro(
                heroSymbol: "globe",
                subtitle: "Extensions installed in your browsers.",
                bullets: [
                    B(symbol: "safari", title: "Every browser",
                      body: "Safari, Chrome, Firefox and others in one list."),
                    B(symbol: "minus.circle", title: "Remove the strays",
                      body: "Clear out extensions you don't remember adding."),
                ])
        case .diskHogs:
            return ModuleIntro(
                heroSymbol: "externaldrive.badge.xmark",
                subtitle: "Developer tools that quietly use a lot of disk.",
                bullets: [
                    B(symbol: "shippingbox", title: "Containers and VMs",
                      body: "Docker images, simulators and SDK downloads."),
                    B(symbol: "arrow.triangle.2.circlepath", title: "Rebuildable",
                      body: "Most of it comes back the next time you build."),
                ])
        case .projectJunk:
            return ModuleIntro(
                heroSymbol: "hammer",
                subtitle: "Build folders and dependencies inside your projects.",
                bullets: [
                    B(symbol: "folder.badge.gearshape", title: "Per project",
                      body: "node_modules, build and target folders you can regenerate."),
                    B(symbol: "clock", title: "Old projects first",
                      body: "Focus on projects you haven't worked on lately."),
                ])
        case .cleanHistory:
            return ModuleIntro(
                heroSymbol: "clock.arrow.circlepath",
                subtitle: "Everything Clean1 has removed, and what can still be put back.",
                bullets: [
                    B(symbol: "arrow.uturn.backward", title: "Undo",
                      body: "Items still in the Trash can be restored."),
                ],
                action: "Open")
        case .settings:
            return ModuleIntro(heroSymbol: "gearshape", subtitle: "", bullets: [], action: "Open")
        }
    }
}

extension ScanCategory {
    /// Symbol for the 26 pt category tile (UI_SPEC §2.4).
    var tileSymbol: String {
        switch self {
        case .userCaches, .systemCaches: "folder"
        case .userLogs, .systemLogs: "doc.text"
        case .languageFiles: "character.bubble"
        case .brokenPreferences: "gearshape"
        case .brokenLoginItems: "power"
        case .documentVersions: "doc.on.doc"
        case .brokenDownloads, .incompleteDownloads: "arrow.down.circle"
        case .iosDeviceBackups: "iphone"
        case .oldUpdates: "arrow.up.circle"
        case .universalBinaries: "cpu"
        case .xcodeJunk: "hammer"
        case .deletedUsers: "person.crop.circle.badge.xmark"
        case .unusedDiskImages: "opticaldiscdrive"
        case .appLeftovers: "shippingbox"
        case .packageManagerCaches: "cube.box"
        case .ideCaches: "chevron.left.forwardslash.chevron.right"
        case .aiToolCaches: "brain"
        case .clipboardArchives: "doc.on.clipboard"
        case .mailAttachments: "paperclip"
        case .trashBins: "trash"
        case .malware: "ladybug.fill"
        case .possibleThreats: "exclamationmark"
        case .browserPrivacy: "safari"
        case .systemPrivacy: "lock"
        case .largeFiles: "archivebox"
        case .oldFiles: "calendar.badge.clock"
        case .duplicates: "doc.on.doc"
        case .projectJunk: "hammer"
        }
    }

    var isThreat: Bool { self == .malware || self == .possibleThreats }
}
