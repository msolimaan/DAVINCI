import CleanerCore
import SwiftUI

struct SpaceLensView: View {
    @EnvironmentObject private var model: SpaceLensViewModel
    private let module = Module.spaceLens

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "square.grid.2x2", title: "Visual map", detail: "Every box is a folder or file, sized by how much space it takes."),
                    Feature(symbol: "cursorarrow.click.2", title: "Drill down", detail: "Click a folder to zoom in; use the path bar to go back."),
                    Feature(symbol: "trash", title: "Clean as you go", detail: "Select boxes and remove them without leaving the map."),
                ],
                buttonTitle: "Map Home",
                action: { model.start(at: FileManager.default.homeDirectoryForCurrentUser) }
            ) {
                Button("Choose Another Folder…") {
                    if let url = Finder.chooseFolder() { model.start(at: url) }
                }
                .buttonStyle(PillButtonStyle())
            }
        case .browsing:
            SpaceLensBrowser(model: model, module: module)
        }
    }
}

private struct SpaceLensBrowser: View {
    @ObservedObject var model: SpaceLensViewModel
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: ByteFormatter.string(model.totalSize),
                subtitle: "in \(Finder.abbreviated(model.current))",
                onBack: model.close
            ) {
                Button("Choose Folder…") {
                    if let url = Finder.chooseFolder(startingAt: model.current) { model.start(at: url) }
                }
                .buttonStyle(PillButtonStyle())
            }
            breadcrumbs
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    TreemapView(model: model, palette: module.palette)
                    if model.isLoading {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .fill(.black.opacity(0.35))
                        ProgressRing(progress: nil, palette: module.palette, diameter: 90, lineWidth: 8) {
                            EmptyView()
                        }
                    }
                }
                sidePanel.frame(width: 300)
            }
            .padding(.horizontal, 20)
            ActionBar(
                module: module,
                buttonTitle: "Remove",
                isEnabled: !model.selectedIDs.isEmpty,
                action: model.removeSelected
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: model.selectedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
        .alert(
            "Some items couldn't be removed",
            isPresented: Binding(
                get: { !(model.report?.failures.isEmpty ?? true) },
                set: { if !$0 { model.dismissReport() } }
            )
        ) {
            Button("OK") { model.dismissReport() }
        } message: {
            Text(model.report?.failures.first?.reason ?? "")
        }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: model.goUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(model.path.count < 2)
                .help("Enclosing Folder")
                ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Button(index == 0 ? Finder.abbreviated(url) : url.lastPathComponent) {
                        model.goTo(depth: index)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: index == model.path.count - 1 ? .bold : .medium, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(index == model.path.count - 1 ? 0.18 : 0.08)))
                }
            }
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let node = model.hoveredNode {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            FileIcon(url: node.url, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name).font(.cardTitle).lineLimit(1)
                                Text(node.isFolder ? "\(node.itemCount) items" : "File")
                                    .font(.caption)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        SizeText(bytes: node.size, font: .system(size: 20, weight: .bold, design: .rounded))
                    }
                } else {
                    Text("Hover over a box for details. Click a folder to open it; right-click for more.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(16)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.nodes.enumerated()), id: \.element.id) { index, node in
                        HoverRow(isSelected: model.hoveredID == node.id) {
                            HStack(spacing: 8) {
                                CheckButton(mark: model.selectedIDs.contains(node.id) ? .on : .off) {
                                    model.toggle(node)
                                }
                                Circle()
                                    .fill(Theme.tilePalette[index % Theme.tilePalette.count])
                                    .frame(width: 8, height: 8)
                                Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                SizeText(bytes: node.size, font: .system(size: 12, weight: .semibold, design: .rounded))
                            }
                        }
                        .onTapGesture(count: 2) { model.open(node) }
                        .onHover { inside in
                            if inside { model.hoveredID = node.id }
                        }
                    }
                }
                .padding(6)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
    }
}

/// Squarified treemap: each child of the current folder is a box sized by its disk usage.
private struct TreemapView: View {
    @ObservedObject var model: SpaceLensViewModel
    let palette: ModulePalette

    /// Tiny items are merged visually; drawing thousands of 1-pixel boxes helps no one.
    private static let maximumTiles = 120

    var body: some View {
        GeometryReader { proxy in
            let nodes = Array(model.nodes.prefix(Self.maximumTiles))
            let rects = TreemapLayout.squarify(
                nodes.map { Double($0.size) },
                in: CGRect(origin: .zero, size: proxy.size)
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let rect = rects[index].insetBy(dx: 2, dy: 2)
                    if rect.width > 1, rect.height > 1 {
                        TreemapTile(
                            node: node,
                            color: Theme.tilePalette[index % Theme.tilePalette.count],
                            isSelected: model.selectedIDs.contains(node.id),
                            isHovered: model.hoveredID == node.id,
                            size: rect.size
                        )
                        .offset(x: rect.minX, y: rect.minY)
                        .onHover { inside in
                            if inside { model.hoveredID = node.id }
                        }
                        .onTapGesture {
                            if node.isFolder { model.open(node) } else { model.toggle(node) }
                        }
                        .contextMenu {
                            if node.isFolder {
                                Button("Open") { model.open(node) }
                            }
                            Button(model.selectedIDs.contains(node.id) ? "Deselect" : "Select for Removal") {
                                model.toggle(node)
                            }
                            Divider()
                            Button("Reveal in Finder") { Finder.reveal(node.url) }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .overlay {
            if model.nodes.isEmpty && !model.isLoading {
                EmptyStateView(symbol: "folder", title: "Empty folder", message: "There's nothing in here, or macOS won't let us look.")
            }
        }
    }
}

private struct TreemapTile: View {
    let node: SpaceNode
    let color: Color
    let isSelected: Bool
    let isHovered: Bool
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(10, min(size.width, size.height) / 4), style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(
                LinearGradient(
                    colors: [color.opacity(isHovered ? 0.95 : 0.75), color.opacity(isHovered ? 0.7 : 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.strokeBorder(.white.opacity(isSelected ? 0.95 : 0.18), lineWidth: isSelected ? 2.5 : 1)
            if size.width > 70 && size.height > 38 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: node.isFolder ? "folder.fill" : "doc.fill")
                            .font(.system(size: 10))
                        Text(node.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(ByteFormatter.string(node.size))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2)
                .padding(8)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
