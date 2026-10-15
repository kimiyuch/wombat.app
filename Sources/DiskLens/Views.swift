import SwiftUI

// MARK: - Building blocks

struct Card<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
    }
}

struct Tile: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
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
                Text("Scanning…").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Capsule()
                        .fill(row.color)
                        .frame(width: max(2, barWidth * CGFloat(row.bytes) / CGFloat(maxBytes)), height: 8)
                        .frame(width: barWidth, alignment: .leading)
                    Text(fmt(row.bytes))
                        .monospacedDigit()
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                if let s = slices.first(where: { $0.id == hovered }) {
                    Circle().fill(s.area.color).frame(width: 8, height: 8)
                    Text(s.name).fontWeight(.medium)
                    Text("\(fmt(s.bytes)) · \(percent(s.bytes))").foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("Hover the bar to see each part.").foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
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
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(risk.color)
            .overlay(Capsule().stroke(risk.color))
            .fixedSize()
    }
}

struct CleanupList: View {
    @EnvironmentObject var scanner: DiskScanner
    @Binding var confirm: CleanupItem?
    @Binding var picker: FolderKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if scanner.cleanup.isEmpty && scanner.isScanning {
                Text("Scanning…").foregroundStyle(.secondary)
            }
            ForEach(scanner.cleanup) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let command = item.command {
                            Text(command)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(item.upTo ? "up to \(fmt(item.bytes))" : fmt(item.bytes))
                        .monospacedDigit()
                        .help(item.upTo ? "The size of the whole folder; the actual saving is usually smaller, so it isn't counted in the totals." : "")
                    RiskPill(risk: item.risk)
                    actionButton(item).frame(width: 118, alignment: .trailing)
                }
                .padding(.vertical, 8)
                Divider()
            }
            if scanner.isScanning && !scanner.deepScanDone && !scanner.cleanup.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for node_modules and vendor folders…").foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ item: CleanupItem) -> some View {
        if scanner.working == item.id {
            ProgressView().controlSize(.small)
        } else {
            switch item.action {
            case .reveal(let path):
                Button("Show in Finder") { reveal(path) }
            case .pickFolders(let kind):
                Button("Choose…") { picker = kind }
                    .disabled(scanner.working != nil)
            default:
                Button("Clean…") { confirm = item }
                    .disabled(scanner.working != nil)
            }
        }
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
            Text(kind.title).font(.title2)
            Text(kind.note).foregroundStyle(.secondary)
            HStack {
                Button("Select all") { selected = Set(folders.map(\.path)) }
                Button("Select none") { selected = [] }
                Spacer()
                Text("\(selected.count) selected · \(fmt(selectedBytes))").monospacedDigit()
            }
            List(folders) { folder in
                Toggle(isOn: Binding(
                    get: { selected.contains(folder.path) },
                    set: { on in if on { selected.insert(folder.path) } else { selected.remove(folder.path) } }
                )) {
                    HStack {
                        Text(scanner.projectName(folder.path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(fmt(folder.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .contextMenu { Button("Show in Finder") { reveal(folder.path) } }
            }
            .frame(minHeight: 340)
            HStack {
                Text("Right-click a project to show it in Finder.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete \(fmt(selectedBytes))…", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
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
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let buttonTitle, let action { Button(buttonTitle, action: action) }
            if let onClose {
                Button { onClose() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
    }
}
