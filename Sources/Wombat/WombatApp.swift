import SwiftUI
import AppKit

@main
struct WombatApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var scanner = DiskScanner()

    var body: some Scene {
        // A single window: ⌘N shouldn't open a second copy of the same scan.
        Window("Wombat", id: "main") {
            ContentView()
                .environmentObject(scanner)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Again") { Task { await scanner.scan(scanner.kind) } }
                    .keyboardShortcut("r")
                    .disabled(scanner.isScanning)
                Divider()
                ForEach(ScanKind.allCases) { kind in
                    Button("Scan: \(kind.title)") { Task { await scanner.scan(kind) } }
                        .disabled(scanner.isScanning)
                }
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
        Group {
            if scanner.hasResults || scanner.isScanning {
                dashboard
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .confirmationDialog(Text(confirm.map { "\($0.title): free \(fmt($0.bytes))?" } ?? ""),
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

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Hero()

                VStack(alignment: .leading, spacing: 48) {
                    banners
                    cleanupSection
                    breakdownSection
                }
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var banners: some View {
        if scanner.needsFullDiskAccess || scanner.lastError != nil {
            VStack(spacing: 10) {
                if scanner.needsFullDiskAccess {
                    Banner(icon: "lock.shield", text: "Wombat can't see inside protected folders like Mail and Messages, so some sizes are too small. Give it Full Disk Access, then quit and reopen Wombat.",
                           tint: Theme.orange, buttonTitle: "Open Settings", action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    })
                }
                if let error = scanner.lastError {
                    Banner(icon: "exclamationmark.triangle", text: error, tint: Theme.red, onClose: { scanner.lastError = nil })
                }
            }
            .padding(.bottom, -16)
        }
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(eyebrow: "Cleanup", title: "Clear out the clutter, keep what matters", text: takeaway)

            HStack(alignment: .top, spacing: 20) {
                CleanupCard(risk: .safe, title: "Clean with a click",
                            items: scanner.cleanup.filter { $0.risk == .safe },
                            confirm: $confirm, picker: $picker) {
                    if scanner.lastProjectScan == nil && !(scanner.isScanning && scanner.kind.includesProjects) {
                        ProjectsHint()
                    }
                }
                CleanupCard(risk: .check, title: "You decide",
                            items: scanner.cleanup.filter { $0.risk == .check },
                            confirm: $confirm, picker: $picker) { EmptyView() }
            }
        }
    }

    private var takeaway: String {
        guard !scanner.cleanup.isEmpty else {
            return "Safe things rebuild themselves, so you can clean them with a click. Everything else is yours to check first. Nothing is deleted without asking."
        }
        return "About \(fmt(scanner.safeBytes)) can be freed safely, and \(fmt(scanner.checkBytes)) more once you check what you still need. Nothing is deleted without asking."
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(eyebrow: "Breakdown", title: "Where your space went",
                           text: "\"System Data & other\" is what Wombat can't measure: /Library, /private/var, swap and local Time Machine snapshots. Double-click a row to show it in Finder.")

            if scanner.lastScan == nil && !(scanner.isScanning && scanner.kind.includesOverview) {
                OverviewHint()
            } else {
                HStack(alignment: .top, spacing: 20) {
                    Card(title: "By category") {
                        BarList(rows: scanner.slices.filter { $0.area != .free }.map {
                            BarRow(id: $0.name, label: $0.name, bytes: $0.bytes, color: $0.area.color, path: $0.path)
                        })
                    }
                    BiggestFolders()
                }
            }
        }
    }
}

// MARK: - Hero

/// The dark panel at the top, like the website's Cleanup section: free space, the usage bar and the scan button.
struct Hero: View {
    @EnvironmentObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                Text("Wombat").font(.display(19)).foregroundStyle(.white)
                Spacer()
                if let date = scanner.lastScan ?? scanner.lastProjectScan, !scanner.isScanning {
                    Text("Last dug \(date.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                        .help(date.formatted(date: .complete, time: .shortened))
                }
                ScanButton()
            }

            HStack(alignment: .bottom, spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Burrow.c300)
                    Text(fmt(scanner.free))
                        .font(.display(56))
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(lowSpace ? Theme.red : .white)
                    Text("of \(fmt(scanner.total)) · \(percentFull) full")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                HStack(spacing: 0) {
                    Stat(label: "Used", value: fmt(scanner.used))
                    Stat(label: "Safe to free", value: scanner.lastScan == nil ? "–" : fmt(scanner.safeBytes), tint: Theme.green)
                    Stat(label: "Free after the safe steps", value: fmt(scanner.free + scanner.safeBytes), last: true)
                }
                .fixedSize()
            }

            if scanner.isScanning {
                ScanProgress()
            } else if scanner.lastScan != nil {
                UsageBar(slices: scanner.slices, total: scanner.total)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 48)
        .padding(.bottom, 32)
        .background(
            LinearGradient(colors: [Burrow.c900, Burrow.c950], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        .environment(\.colorScheme, .dark)
    }

    private var lowSpace: Bool { scanner.total > 0 && Double(scanner.free) / Double(scanner.total) < 0.1 }

    private var percentFull: String {
        guard scanner.total > 0 else { return "–" }
        return String(format: "%.1f%%", 100 * Double(scanner.used) / Double(scanner.total))
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var tint: Color = .white
    var last = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text(value).font(.display(24)).monospacedDigit().foregroundStyle(tint)
            }
            .padding(.horizontal, 24)
            if !last {
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 44)
            }
        }
    }
}

/// While digging: which part is being measured, with a step list for the chosen kind of scan.
struct ScanProgress: View {
    @EnvironmentObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(scanner.phase.isEmpty ? "Starting…" : scanner.phase)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if let last = scanner.durations[scanner.kind] {
                    Text("\(scanner.kind.title) took \(duration(last)) last time")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }
            }
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Burrow.c300)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(.white.opacity(0.1)))
    }
}

func duration(_ seconds: Double) -> String {
    seconds < 90 ? "\(Int(seconds.rounded())) s" : "\(Int((seconds / 60).rounded())) min"
}

/// "Dig again" with a popover to choose the kind of scan.
struct ScanButton: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Label(scanner.isScanning ? "Digging…" : "Dig again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(PillButtonStyle(prominent: true, tint: .white, foreground: Burrow.c950, large: true))
        .disabled(scanner.isScanning)
        .help("Choose what to scan (⌘R scans the same as last time)")
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            ScanChooser(compact: true) { choosing = false }
                .padding(20)
                .frame(width: 380)
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 136, height: 136)
                Text("Dig up where your disk space went")
                    .font(.display(46))
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: 620)
                    .padding(.top, 24)
                Text("Wombat measures your disk, shows what fills it and helps you clear out caches, build leftovers and old node_modules, without touching anything you didn't pick.")
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560)
                    .padding(.top, 16)

                ScanChooser(compact: false)
                    .frame(maxWidth: 820)
                    .padding(.top, 40)

                Text("Nothing is deleted without asking · Wombat never connects to the internet")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 64)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The three kinds of scan as cards, plus the button that starts the chosen one.
struct ScanChooser: View {
    @EnvironmentObject var scanner: DiskScanner
    let compact: Bool
    var onStart: () -> Void = {}
    @State private var selected: ScanKind?

    var body: some View {
        let choice = selected ?? scanner.kind
        VStack(alignment: compact ? .leading : .center, spacing: compact ? 14 : 28) {
            if compact {
                Text("What should Wombat dig through?").font(.display(16)).foregroundStyle(Theme.ink)
            }
            let layout = compact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            layout {
                ForEach(ScanKind.allCases) { kind in
                    ScanKindCard(kind: kind, selected: kind == choice, compact: compact,
                                 lastDuration: scanner.durations[kind]) { selected = kind }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Button {
                onStart()
                Task { await scanner.scan(choice) }
            } label: {
                Label("Start digging", systemImage: "arrow.down.forward.circle")
            }
            .buttonStyle(PillButtonStyle(prominent: true, large: true))
            .keyboardShortcut(.defaultAction)
            .disabled(scanner.isScanning)
        }
    }
}

private struct ScanKindCard: View {
    let kind: ScanKind
    let selected: Bool
    let compact: Bool
    let lastDuration: Double?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Burrow.c600 : Theme.pageTop))
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(.display(15)).foregroundStyle(Theme.ink)
                    Text(kind.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastDuration {
                        Text("Took \(duration(lastDuration)) last time")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.link)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(selected ? Burrow.c500 : Theme.ring, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hints for parts that haven't been scanned

private struct ProjectsHint: View {
    @EnvironmentObject var scanner: DiskScanner

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(symbol: "shippingbox", tint: Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("node_modules and vendor folders").fontWeight(.medium).foregroundStyle(Theme.ink)
                Text("Not searched yet. The project search takes a while on big drives.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Button("Find projects") { Task { await scanner.scan(.projects) } }
                .buttonStyle(.pill)
                .disabled(scanner.isScanning)
        }
        .padding(.vertical, 12)
    }
}

private struct OverviewHint: View {
    @EnvironmentObject var scanner: DiskScanner

    var body: some View {
        HStack(spacing: 14) {
            ItemIcon(symbol: "chart.bar.xaxis", tint: Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("No disk overview yet").font(.display(15)).foregroundStyle(Theme.ink)
                Text("It measures your home folder, ~/Library and apps, and fills the usage bar and these lists.")
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Run the disk overview") { Task { await scanner.scan(.overview) } }
                .buttonStyle(.pillProminent)
                .disabled(scanner.isScanning)
        }
        .cardSurface(padding: 20)
    }
}
