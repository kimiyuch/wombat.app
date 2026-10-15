import Foundation

@MainActor
final class DiskScanner: ObservableObject {
    @Published var isScanning = false
    @Published var phase = ""
    @Published var total: Int64 = 0
    @Published var free: Int64 = 0
    @Published var slices: [UsageSlice] = []
    @Published var homeFolders: [FolderSize] = []
    @Published var libraryFolders: [FolderSize] = []
    @Published var cleanup: [CleanupItem] = []
    @Published var nodeModules: [FolderSize] = []
    @Published var vendorDirs: [FolderSize] = []
    @Published var deepScanDone = false
    @Published var needsFullDiskAccess = false
    @Published var lastScan: Date?
    @Published var lastError: String?
    @Published var working: String?

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var lib: String { home + "/Library" }
    private var sizes: [String: Int64] = [:]
    private var simulatorBytes: Int64 = 0
    private var completed: Set<String> = []

    var used: Int64 { max(0, total - free) }
    var safeBytes: Int64 { cleanup.filter { $0.risk == .safe && !$0.upTo }.reduce(0) { $0 + $1.bytes } }
    var checkBytes: Int64 { cleanup.filter { $0.risk == .check && !$0.upTo }.reduce(0) { $0 + $1.bytes } }

    // MARK: - Scanning

    func refreshVolume() {
        let url = URL(fileURLWithPath: "/")
        // "Important usage" counts purgeable space as free, like Finder and System Settings do.
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            total = Int64(v.volumeTotalCapacity ?? 0)
            free = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        deepScanDone = false
        lastError = nil
        completed = []
        defer {
            isScanning = false
            phase = ""
        }

        let fm = FileManager.default
        refreshVolume()
        // ~/Library/Safari is protected by macOS; if we can't list it, Full Disk Access is missing.
        needsFullDiskAccess = (try? fm.contentsOfDirectory(atPath: lib + "/Safari")) == nil

        func children(_ dir: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0 != ".DS_Store" }
                .map { dir + "/" + $0 }
        }

        phase = "Measuring your home folder…"
        let homeKids = children(home).filter { $0 != lib }
        var s = await Shell.sizes(homeKids)
        let homeSizes = s

        phase = "Measuring ~/Library…"
        let deepDirs = ["Application Support", "Caches", "Containers", "Group Containers"].map { lib + "/" + $0 }
        let libTop = children(lib).filter { !deepDirs.contains($0) }
        let libDeep = deepDirs.flatMap { children($0) }
        let libSizes = await Shell.sizes(libTop + libDeep)
        s.merge(libSizes) { first, _ in first }
        let libTotal = libSizes.values.reduce(0, +)

        phase = "Measuring apps…"
        let appSizes = await Shell.sizes(children("/Applications"))
        let appsTotal = appSizes.values.reduce(0, +)

        phase = "Measuring developer tools…"
        let extra = [
            lib + "/Developer/Xcode/DerivedData",
            lib + "/Developer/Xcode/iOS DeviceSupport",
            lib + "/Developer/CoreSimulator",
            "/opt/homebrew",
            "/usr/local/Cellar",
        ].filter { fm.fileExists(atPath: $0) }
        let extraSizes = await Shell.sizes(extra)
        s.merge(extraSizes) { first, _ in first }
        simulatorBytes = await Self.simulatorRuntimeBytes()
        sizes = s

        // Non-overlapping categories for the usage bar.
        func sz(_ p: String) -> Int64 { s[p] ?? 0 }
        let mail = sz(lib + "/Mail") + sz(lib + "/Containers/com.apple.mail")
        let docker = sz(lib + "/Containers/com.docker.docker")
        let developer = sz(lib + "/Developer")
        let caches = childSum(lib + "/Caches")
        let otherLib = max(0, libTotal - mail - docker - developer - caches)

        var parts: [UsageSlice] = [
            UsageSlice(name: "Mail", bytes: mail, area: .library, path: lib + "/Mail"),
            UsageSlice(name: "Other app data (~/Library)", bytes: otherLib, area: .library, path: lib + "/Application Support"),
            UsageSlice(name: "Xcode & simulators (~/Library/Developer)", bytes: developer, area: .library, path: lib + "/Developer"),
            UsageSlice(name: "App caches", bytes: caches, area: .library, path: lib + "/Caches"),
            UsageSlice(name: "Docker Desktop data", bytes: docker, area: .library, path: lib + "/Containers/com.docker.docker"),
            UsageSlice(name: "Applications", bytes: appsTotal, area: .apps, path: "/Applications"),
            UsageSlice(name: "iOS simulator runtimes", bytes: simulatorBytes, area: .system),
            UsageSlice(name: "Homebrew", bytes: sz("/opt/homebrew") + sz("/usr/local/Cellar"), area: .system, path: "/opt/homebrew"),
        ]
        let sortedHome = homeSizes.sorted { $0.value > $1.value }
        for (path, bytes) in sortedHome.prefix(6) {
            parts.append(UsageSlice(name: short(path), bytes: bytes, area: .home, path: path))
        }
        let restHome = sortedHome.dropFirst(6).reduce(Int64(0)) { $0 + $1.value }
        parts.append(UsageSlice(name: "Other home folders", bytes: restHome, area: .home, path: home))

        parts = parts.filter { $0.bytes > 0 }
        let scanned = parts.reduce(Int64(0)) { $0 + $1.bytes }
        parts.append(UsageSlice(name: "System Data & other (not scanned)", bytes: max(0, used - scanned), area: .system))
        parts.sort { $0.bytes > $1.bytes }
        parts.append(UsageSlice(name: "Free", bytes: free, area: .free))
        slices = parts

        var homeList = sortedHome.map { FolderSize(path: $0.key, bytes: $0.value) }
        homeList.append(FolderSize(path: lib, bytes: libTotal))
        homeFolders = Array(homeList.sorted { $0.bytes > $1.bytes }.prefix(12))
        libraryFolders = Array(libSizes.map { FolderSize(path: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }.prefix(12))

        lastScan = Date()
        buildCleanup()

        phase = "Looking for node_modules and vendor folders…"
        await deepScan()
    }

    private func deepScan() async {
        let fm = FileManager.default
        // Skip ~/Library and hidden folders (caches, editor extensions) — only real projects.
        let result = await Shell.run("/usr/bin/find", [
            home, "(", "-path", lib, "-o", "-name", ".*", ")", "-prune", "-o",
            "-type", "d", "(", "-name", "node_modules", "-o", "-name", "vendor", ")", "-prune", "-print",
        ])
        let found = result.out.split(separator: "\n").map(String.init)
        let nm = found.filter { $0.hasSuffix("/node_modules") }
        let vendor = found.filter {
            $0.hasSuffix("/vendor") &&
                fm.fileExists(atPath: ($0 as NSString).deletingLastPathComponent + "/composer.json")
        }
        let found2 = await Shell.sizes(nm + vendor)
        nodeModules = nm.map { FolderSize(path: $0, bytes: found2[$0] ?? 0) }.sorted { $0.bytes > $1.bytes }
        vendorDirs = vendor.map { FolderSize(path: $0, bytes: found2[$0] ?? 0) }.sorted { $0.bytes > $1.bytes }
        deepScanDone = true
        buildCleanup()
    }

    private func childSum(_ dir: String) -> Int64 {
        let prefix = dir + "/"
        return sizes.reduce(Int64(0)) { acc, entry in
            let key = entry.key
            guard key.hasPrefix(prefix), !key.dropFirst(prefix.count).contains("/") else { return acc }
            return acc + entry.value
        }
    }

    // Uses `diskutil apfs list -plist` to find mounted simulator runtime images.
    static func simulatorRuntimeBytes() async -> Int64 {
        let result = await Shell.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"])
        guard let data = result.out.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return 0 }
        var total: Int64 = 0
        for container in containers {
            for volume in (container["Volumes"] as? [[String: Any]]) ?? [] {
                if let name = volume["Name"] as? String, name.contains("Simulator"),
                   let inUse = volume["CapacityInUse"] as? NSNumber {
                    total += inUse.int64Value
                }
            }
        }
        return total
    }

    // MARK: - Cleanup list

    func buildCleanup() {
        func sz(_ p: String) -> Int64 { sizes[p] ?? 0 }
        var items: [CleanupItem] = [
            CleanupItem(id: "trash", title: "Empty the Trash", detail: "Same as Finder → Empty Trash.",
                        bytes: sz(home + "/.Trash"), risk: .safe, action: .emptyTrash),
            CleanupItem(id: "caches", title: "App caches", detail: "Apps rebuild their caches. Quit big apps first.",
                        bytes: childSum(lib + "/Caches"), risk: .safe, action: .deleteContents(lib + "/Caches")),
            CleanupItem(id: "npm", title: "npm cache", detail: "npm downloads packages again when needed.",
                        bytes: sz(home + "/.npm"), risk: .safe, action: .shell("npm cache clean --force"),
                        command: "npm cache clean --force"),
            CleanupItem(id: "docker", title: "Docker images & stopped containers",
                        detail: "Unused images are pulled again when needed. Volumes (databases) are kept. Docker must be running.",
                        bytes: sz(lib + "/Containers/com.docker.docker"), risk: .check,
                        action: .shell("docker system prune -a -f"), command: "docker system prune -a -f", upTo: true),
            CleanupItem(id: "phpls", title: "PHP language-server index", detail: "Deletes ~/.phpls; it is rebuilt on the next index.",
                        bytes: sz(home + "/.phpls"), risk: .safe, action: .deletePaths([home + "/.phpls"])),
            CleanupItem(id: "simdevices", title: "Unavailable simulator devices",
                        detail: "Simulators for iOS versions no longer installed.",
                        bytes: sz(lib + "/Developer/CoreSimulator"), risk: .safe,
                        action: .shell("xcrun simctl delete unavailable"), command: "xcrun simctl delete unavailable", upTo: true),
            CleanupItem(id: "devicesupport", title: "iOS DeviceSupport", detail: "Debug symbols Xcode re-downloads when a device connects.",
                        bytes: sz(lib + "/Developer/Xcode/iOS DeviceSupport"), risk: .safe,
                        action: .deleteContents(lib + "/Developer/Xcode/iOS DeviceSupport")),
            CleanupItem(id: "derived", title: "Xcode DerivedData", detail: "Build products Xcode recreates.",
                        bytes: sz(lib + "/Developer/Xcode/DerivedData"), risk: .safe,
                        action: .deleteContents(lib + "/Developer/Xcode/DerivedData")),

            CleanupItem(id: "simruntimes", title: "iOS simulator runtimes",
                        detail: "Remove the ones you don't need in Xcode → Settings → Components.",
                        bytes: simulatorBytes, risk: .check, action: .reveal("/Library/Developer/CoreSimulator"),
                        command: "xcrun simctl runtime delete <id>"),
            CleanupItem(id: "mail", title: "Mail downloads & attachments",
                        detail: "Remove unused accounts, or stop downloading all attachments, in Mail → Settings → Accounts.",
                        bytes: sz(lib + "/Mail") + sz(lib + "/Containers/com.apple.mail"), risk: .check,
                        action: .reveal(lib + "/Containers/com.apple.mail")),
            CleanupItem(id: "downloads", title: "Downloads folder", detail: "Sort by size in Finder; delete installers and old exports.",
                        bytes: sz(home + "/Downloads"), risk: .check, action: .reveal(home + "/Downloads")),
            CleanupItem(id: "box", title: "Box Sync local copy", detail: "Box Sync is retired; Box Drive can keep files online-only.",
                        bytes: sz(home + "/Box Sync"), risk: .check, action: .reveal(home + "/Box Sync")),
            CleanupItem(id: "crossover", title: "CrossOver Windows bottles", detail: "Delete unused bottles in CrossOver.",
                        bytes: sz(lib + "/Application Support/CrossOver"), risk: .check,
                        action: .reveal(lib + "/Application Support/CrossOver")),
            CleanupItem(id: "omarchy", title: "Try Omarchy VM", detail: "Delete the VM if you're done trying it.",
                        bytes: sz(lib + "/Application Support/Try Omarchy"), risk: .check,
                        action: .reveal(lib + "/Application Support/Try Omarchy")),
            CleanupItem(id: "ollama", title: "Ollama models", detail: "Remove models you no longer use.",
                        bytes: sz(home + "/.ollama"), risk: .check, action: .reveal(home + "/.ollama"),
                        command: "ollama list → ollama rm <model>"),
        ]
        if deepScanDone {
            items.append(CleanupItem(id: "node_modules", title: "node_modules in \(nodeModules.count) projects",
                                     detail: "Pick the projects to clean; npm install brings them back.",
                                     bytes: nodeModules.total, risk: .safe, action: .pickFolders(.nodeModules)))
            items.append(CleanupItem(id: "vendor", title: "Composer vendor in \(vendorDirs.count) projects",
                                     detail: "Pick inactive projects; composer install brings them back.",
                                     bytes: vendorDirs.total, risk: .check, action: .pickFolders(.vendor)))
        }
        cleanup = items
            .filter { $0.bytes >= 50_000_000 && !completed.contains($0.id) }
            .sorted { ($0.risk == .safe ? 0 : 1, -$0.bytes) < ($1.risk == .safe ? 0 : 1, -$1.bytes) }
    }

    // MARK: - Actions

    struct CleanupError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func perform(_ item: CleanupItem) async {
        working = item.id
        defer { working = nil }
        do {
            switch item.action {
            case .emptyTrash:
                let r = await Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"], mergeStderr: true)
                if r.status != 0 { throw CleanupError(message: r.out.trimmingCharacters(in: .whitespacesAndNewlines)) }
            case .deleteContents(let dir):
                var failed = 0
                try await onBackground {
                    let fm = FileManager.default
                    for child in try fm.contentsOfDirectory(atPath: dir) {
                        do { try fm.removeItem(atPath: dir + "/" + child) } catch { failed += 1 }
                    }
                }
                if failed > 0 {
                    // Usually caches of running apps or protected folders; the rest is gone.
                    lastError = "\(item.title): \(failed) item\(failed == 1 ? "" : "s") couldn't be deleted (quit the apps using them and try again)."
                }
            case .deletePaths(let paths):
                try await onBackground {
                    for p in paths { try FileManager.default.removeItem(atPath: p) }
                }
            case .shell(let command):
                let r = await Shell.login(command)
                if r.status != 0 {
                    throw CleanupError(message: String(r.out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400)))
                }
            case .reveal, .pickFolders:
                return
            }
            completed.insert(item.id)
            refreshVolume()
            buildCleanup()
        } catch {
            lastError = "\(item.title): \(error.localizedDescription)"
        }
    }

    func deleteFolders(_ paths: [String], kind: FolderKind) async {
        working = kind == .nodeModules ? "node_modules" : "vendor"
        defer { working = nil }
        var failed: [String] = []
        try? await onBackground {
            for p in paths {
                do { try FileManager.default.removeItem(atPath: p) } catch { failed.append(p) }
            }
        }
        if !failed.isEmpty {
            lastError = "Couldn't delete \(failed.count) folder\(failed.count == 1 ? "" : "s"), e.g. \(short(failed[0]))."
        }
        let gone = Set(paths).subtracting(failed)
        if kind == .nodeModules {
            nodeModules.removeAll { gone.contains($0.path) }
        } else {
            vendorDirs.removeAll { gone.contains($0.path) }
        }
        refreshVolume()
        buildCleanup()
    }

    func short(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    func projectName(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return short(parent)
    }
}
