import SwiftUI

// MARK: - Building blocks

struct Card<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(15)).foregroundStyle(Theme.ink)
                if let note {
                    Text(note).font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .cardSurface(padding: 20)
    }
}

/// The website's section opener: a small coloured eyebrow, a Figtree heading and a line of text.
struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var text: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.display(28)).tracking(-0.5).foregroundStyle(Theme.ink)
            if let text {
                Text(text)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 680, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

/// An SF Symbol on a soft tinted square, in front of list rows.
struct ItemIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.12)))
    }
}

struct BarRow: Identifiable {
    let id: String
    let label: String
    let bytes: Int64
    let color: Color
    var path: String? = nil
}

struct BarList: View {
    let rows: [BarRow]
    var barWidth: CGFloat = 140

    var body: some View {
        let maxBytes = max(rows.map(\.bytes).max() ?? 1, 1)
        VStack(spacing: 7) {
            if rows.isEmpty {
                Text("Digging…").foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Capsule()
                        .fill(row.color)
                        .frame(width: max(2, barWidth * CGFloat(row.bytes) / CGFloat(maxBytes)), height: 8)
                        .frame(width: barWidth, alignment: .leading)
                    Text(fmt(row.bytes))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .frame(width: 76, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .help(row.path.map { "\($0) — double-click to show in Finder" } ?? row.label)
                .onTapGesture(count: 2) { if let p = row.path { reveal(p) } }
                .contextMenu {
                    if let p = row.path { Button("Show in Finder") { reveal(p) } }
                }
            }
        }
    }
}

// MARK: - Usage bar

struct UsageBar: View {
    let slices: [UsageSlice]
    let total: Int64
    @State private var hovered: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(slices) { slice in
                        let width = geo.size.width * CGFloat(slice.bytes) / CGFloat(max(total, 1))
                        Rectangle()
                            .fill(slice.area.color.opacity(hovered == nil || hovered == slice.id ? 1 : 0.4))
                            .frame(width: max(1, width - 1))
                            .onHover { inside in
                                if inside { hovered = slice.id } else if hovered == slice.id { hovered = nil }
                            }
                            .help("\(slice.name): \(fmt(slice.bytes))")
                    }
                }
            }
            .frame(height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 6) {
                if let s = slices.first(where: { $0.id == hovered }) {
                    Circle().fill(s.area.color).frame(width: 8, height: 8)
                    Text(s.name).fontWeight(.medium).foregroundStyle(Theme.ink)
                    Text("\(fmt(s.bytes)) · \(percent(s.bytes))").foregroundStyle(Theme.muted).monospacedDigit()
                } else {
                    Text("Hover the bar to see each part.").foregroundStyle(Theme.muted)
                }
            }
            .font(.callout)
            .frame(height: 18)

            HStack(spacing: 16) {
                ForEach(Area.allCases, id: \.self) { area in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(area.color).frame(width: 10, height: 10)
                        Text(area.rawValue)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }

    private func percent(_ bytes: Int64) -> String {
        guard total > 0 else { return "" }
        return String(format: "%.1f%%", 100 * Double(bytes) / Double(total))
    }
}

// MARK: - Cleanup

struct RiskPill: View {
    let risk: Risk
    var body: some View {
        Text(risk.rawValue)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .foregroundStyle(risk.color)
            .overlay(Capsule().strokeBorder(risk.color.opacity(0.6)))
            .fixedSize()
    }
}

/// One of the two piles: "Safe" (clean with a click) or "Check first" (you decide).
struct CleanupCard<Footer: View>: View {
    @EnvironmentObject var scanner: DiskScanner
    let risk: Risk
    let title: String
    let items: [CleanupItem]
    @Binding var confirm: CleanupItem?
    @Binding var picker: FolderKind?
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RiskPill(risk: risk)
                Text(title).font(.display(16)).foregroundStyle(Theme.ink)
                Spacer()
                let total = items.filter { !$0.upTo }.reduce(Int64(0)) { $0 + $1.bytes }
                if total > 0 {
                    Text(fmt(total)).font(.display(16)).monospacedDigit().foregroundStyle(risk.color)
                }
            }
            .padding(.bottom, 8)

            if items.isEmpty {
                Text(scanner.isScanning ? "Digging…" : "Nothing here above 50 MB.")
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 12)
            }
            ForEach(items) { item in
                Rectangle().fill(Theme.divider).frame(height: 1)
                row(item)
            }
            if scanner.isScanning && scanner.kind.includesProjects && !scanner.deepScanDone && risk == .safe {
                Rectangle().fill(Theme.divider).frame(height: 1)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for node_modules and vendor folders…").foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 12)
            } else if !(footer is EmptyView) {
                Rectangle().fill(Theme.divider).frame(height: 1)
                footer
            }
        }
        .cardSurface(padding: 20)
    }

    private func row(_ item: CleanupItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ItemIcon(symbol: item.symbol, tint: risk == .safe ? Theme.accent : Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).fontWeight(.medium).foregroundStyle(Theme.ink)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let command = item.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.link)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.pageTop))
                        .textSelection(.enabled)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.upTo ? "up to \(fmt(item.bytes))" : fmt(item.bytes))
                    .font(.display(14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .help(item.upTo ? "The size of the whole folder; the actual saving is usually smaller, so it isn't counted in the totals." : "")
                actionButton(item)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func actionButton(_ item: CleanupItem) -> some View {
        if scanner.working == item.id {
            ProgressView().controlSize(.small)
        } else {
            switch item.action {
            case .reveal(let path):
                Button("Show in Finder") { reveal(path) }
                    .buttonStyle(.pill)
            case .pickFolders(let kind):
                Button("Choose…") { picker = kind }
                    .buttonStyle(.pillProminent)
                    .disabled(scanner.working != nil)
            default:
                Button("Clean…") { confirm = item }
                    .buttonStyle(.pillProminent)
                    .disabled(scanner.working != nil)
            }
        }
    }
}

/// The biggest folders in the home folder or in ~/Library, switched with a pill toggle.
struct BiggestFolders: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var library = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Biggest folders").font(.display(15)).foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 2) {
                    segment("Home", selected: !library) { library = false }
                    segment("~/Library", selected: library) { library = true }
                }
                .padding(2)
                .background(Capsule().fill(Theme.pageTop))
                .overlay(Capsule().strokeBorder(Theme.ring))
            }
            if library {
                BarList(rows: scanner.libraryFolders.map {
                    BarRow(id: $0.path, label: scanner.short($0.path).replacingOccurrences(of: "~/Library/", with: ""),
                           bytes: $0.bytes, color: Area.library.color, path: $0.path)
                })
            } else {
                BarList(rows: scanner.homeFolders.map {
                    BarRow(id: $0.path, label: scanner.short($0.path), bytes: $0.bytes, color: Area.home.color, path: $0.path)
                })
            }
        }
        .cardSurface(padding: 20)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? .white : Theme.link)
                .background(Capsule().fill(selected ? Burrow.c600 : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FolderPicker: View {
    @EnvironmentObject var scanner: DiskScanner
    @Environment(\.dismiss) private var dismiss
    let kind: FolderKind
    @State private var selected: Set<String> = []
    @State private var confirming = false

    private var folders: [FolderSize] { kind == .nodeModules ? scanner.nodeModules : scanner.vendorDirs }
    private var selectedBytes: Int64 { folders.filter { selected.contains($0.path) }.total }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title).font(.display(22)).foregroundStyle(Theme.ink)
            Text(kind.note).foregroundStyle(Theme.muted)
            HStack {
                Button("Select all") { selected = Set(folders.map(\.path)) }.buttonStyle(.pill)
                Button("Select none") { selected = [] }.buttonStyle(.pill)
                Spacer()
                Text("\(selected.count) selected · \(fmt(selectedBytes))").monospacedDigit().foregroundStyle(Theme.text)
            }
            List(folders) { folder in
                Toggle(isOn: Binding(
                    get: { selected.contains(folder.path) },
                    set: { on in if on { selected.insert(folder.path) } else { selected.remove(folder.path) } }
                )) {
                    HStack {
                        Text(scanner.projectName(folder.path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(fmt(folder.bytes)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                .contextMenu { Button("Show in Finder") { reveal(folder.path) } }
            }
            .scrollContentBackground(.hidden)
            .frame(minHeight: 340)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.ring))
            HStack {
                Text("Right-click a project to show it in Finder.").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pill).keyboardShortcut(.cancelAction)
                Button("Delete \(fmt(selectedBytes))…", role: .destructive) { confirming = true }
                    .buttonStyle(.pillDestructive)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(24)
        .background(Theme.background)
        .tint(Theme.accent)
        .frame(width: 660, height: 580)
        .confirmationDialog("Delete \(selected.count) folders (\(fmt(selectedBytes)))?", isPresented: $confirming) {
            Button("Delete", role: .destructive) {
                let paths = Array(selected)
                dismiss()
                Task { await scanner.deleteFolders(paths, kind: kind) }
            }
        } message: {
            Text(kind.restore)
        }
    }
}

// MARK: - Banners

struct Banner: View {
    let icon: String
    let text: String
    let tint: Color
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15, weight: .semibold))
            Text(text).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let buttonTitle, let action { Button(buttonTitle, action: action).buttonStyle(.pillProminent) }
            if let onClose {
                Button { onClose() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(tint.opacity(0.3)))
    }
}
