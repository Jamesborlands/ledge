import SwiftUI

struct ShelfView: View {
    @ObservedObject var controller: ShelfController
    @ObservedObject private var store = ShelfStore.shared

    private var items: [ShelfItem] { store.shelf(controller.shelfID)?.items ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .background(VisualEffectBackground().ignoresSafeArea())
        .overlay(DropGlow(active: controller.isDropTarget, flash: controller.dropFlash).allowsHitTesting(false))
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: controller.isDropTarget)
        .animation(.easeOut(duration: 0.3), value: controller.dropFlash)
    }

    private var title: String {
        switch items.count {
        case 0: return "Shelf"
        case 1: return items[0].name
        default: return "\(items.count) Items"
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            DragAllRepresentable(controller: controller, itemPaths: items.map(\.path))
                .frame(width: 34, height: 24)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .allowsHitTesting(false)
            Spacer(minLength: 4)
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(items.isEmpty)
            Button {
                controller.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close shelf (it stays in Recent Shelves)")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(WindowDragArea())
    }

    @ViewBuilder
    private var actions: some View {
        let scope = controller.selection.isEmpty ? "All" : "Selected"
        Button("Open \(scope)") { controller.open(controller.targetItems) }
        Button("Quick Look") { controller.quickLook() }
        Button("Show in Finder") { controller.reveal(controller.targetItems) }
        Divider()
        Button("Copy \(scope)") { controller.copy(controller.targetItems) }
        Button("Share…") { controller.share(controller.targetItems) }
        Button("Save Copies To…") { controller.saveToFolder(controller.targetItems) }
        Button("Compress \(scope) to Zip") { controller.compress(controller.targetItems) }
        Divider()
        Button("Select All") { controller.selection = Set(items.map(\.id)) }
        if !controller.selection.isEmpty {
            Button("Remove Selected") { controller.removeFromShelf(controller.selectedItems) }
        }
        Button("Clear Shelf") { controller.clear() }
        Button("Close Shelf") { controller.close() }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .light))
                Text("Drop files here")
                    .font(.system(size: 13, weight: .medium))
                Text("or press ⌘V to paste")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.tertiary)
            )
            .padding(10)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 6)], spacing: 6) {
                    ForEach(items) { item in
                        TileRepresentable(item: item, selected: controller.selection.contains(item.id), controller: controller)
                            .frame(height: items.count == 1 ? 130 : 96)
                    }
                }
                .padding(8)
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { controller.selection = [] }
            )
        }
    }
}

/// Glowing edge shown while something is held over the shelf, plus a brief flash when it lands.
struct DropGlow: View {
    let active: Bool
    let flash: Bool

    private let cyan = Color(red: 0.38, green: 0.86, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.45, blue: 1.0)

    var body: some View {
        let edge = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            edge.fill(LinearGradient(colors: [cyan.opacity(0.16), violet.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                .opacity(active || flash ? 1 : 0)
            edge.strokeBorder(LinearGradient(colors: [cyan, violet], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                .shadow(color: cyan.opacity(0.9), radius: 5)
                .shadow(color: violet.opacity(0.7), radius: 12)
                .padding(3)
                .opacity(active ? 1 : 0)
                .phaseAnimator([0.65, 1.0]) { view, phase in
                    view.opacity(active ? phase : 0)
                } animation: { _ in .easeInOut(duration: 0.7) }
            edge.fill(cyan.opacity(flash ? 0.28 : 0))
        }
    }
}
