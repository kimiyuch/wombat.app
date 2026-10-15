import SwiftUI
import AppKit

@main
struct DiskLensApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var scanner = DiskScanner()

    var body: some Scene {
        // A single window: ⌘N shouldn't open a second copy of the same scan.
        Window("DiskLens", id: "main") {
            ContentView()
                .environmentObject(scanner)
        }
        .defaultSize(width: 1180, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { Task { await scanner.scan() } }
                    .keyboardShortcut("r")
                    .disabled(scanner.isScanning)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var confirm: CleanupItem?
    @State private var picker: FolderKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if scanner.needsFullDiskAccess {
                    Banner(icon: "lock.shield", text: "DiskLens can't see inside protected folders like Mail and Messages, so some sizes are too small. Give it Full Disk Access, then quit and reopen DiskLens.",
                           tint: .orange, buttonTitle: "Open Settings", action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    })
                }
                if let error = scanner.lastError {
                    Banner(icon: "exclamationmark.triangle", text: error, tint: .red, onClose: { scanner.lastError = nil })
                }

                tiles

                Card(title: "Where the space goes",
                     note: "The whole disk, largest first. \"System Data & other\" is what DiskLens can't measure: /Library, /private/var, swap and local Time Machine snapshots.") {
                    UsageBar(slices: scanner.slices, total: scanner.total)
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "By category", note: "Double-click a row to show it in Finder.") {
                        BarList(rows: scanner.slices.filter { $0.area != .free }.map {
                            BarRow(id: $0.name, label: $0.name, bytes: $0.bytes, color: $0.area.color, path: $0.path)
                        })
                    }
                    .frame(maxWidth: 440)
                    Card(title: "What you can free",
                         note: "\"Safe\" items are caches or things that rebuild themselves. \"Check first\" holds your own files or tools you may still use. Nothing is deleted without asking.") {
                        CleanupList(confirm: $confirm, picker: $picker)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Biggest folders in your home") {
                        BarList(rows: scanner.homeFolders.map {
                            BarRow(id: $0.path, label: scanner.short($0.path), bytes: $0.bytes, color: Area.home.color, path: $0.path)
                        })
                    }
                    Card(title: "Biggest app data in ~/Library") {
                        BarList(rows: scanner.libraryFolders.map {
                            BarRow(id: $0.path, label: scanner.short($0.path).replacingOccurrences(of: "~/Library/", with: ""),
                                   bytes: $0.bytes, color: Area.library.color, path: $0.path)
                        })
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .toolbar {
            ToolbarItem {
                Button { Task { await scanner.scan() } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(scanner.isScanning)
                .help("Scan the disk again (⌘R)")
            }
        }
        .task {
            if scanner.lastScan == nil { await scanner.scan() }
        }
        .confirmationDialog(Text(confirm.map { "\($0.title) — free \(fmt($0.bytes))?" } ?? ""),
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { item in
            Button("Clean", role: .destructive) {
                Task { await scanner.perform(item) }
            }
        } message: { item in
            Text(item.confirmText)
        }
        .sheet(item: $picker) { kind in
            FolderPicker(kind: kind).environmentObject(scanner)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mac disk usage")
                .font(.system(size: 30, weight: .regular, design: .serif))
            Text(takeaway).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if scanner.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(scanner.phase)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let date = scanner.lastScan {
                Text("Scanned \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var takeaway: String {
        guard scanner.total > 0 else { return "Scanning your disk…" }
        let pct = String(format: "%.1f", 100 * Double(scanner.used) / Double(scanner.total))
        var text = "Your disk is \(pct)% full with \(fmt(scanner.free)) free."
        if !scanner.cleanup.isEmpty {
            text += " About \(fmt(scanner.safeBytes)) can be freed safely, and \(fmt(scanner.checkBytes)) more once you check what you still need."
        }
        return text
    }

    private var tiles: some View {
        let lowSpace = scanner.total > 0 && Double(scanner.free) / Double(scanner.total) < 0.1
        return HStack(spacing: 12) {
            Tile(label: "Disk size", value: fmt(scanner.total))
            Tile(label: "Used", value: fmt(scanner.used))
            Tile(label: "Free now", value: fmt(scanner.free), tint: lowSpace ? .red : .primary)
            Tile(label: "Safe to free", value: fmt(scanner.safeBytes), tint: .green)
            Tile(label: "Free after the safe steps", value: fmt(scanner.free + scanner.safeBytes))
        }
    }
}
