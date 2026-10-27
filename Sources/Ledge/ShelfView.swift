import SwiftUI

struct ShelfView: View {
    @ObservedObject var controller: ShelfController
    @ObservedObject private var store = ShelfStore.shared

    private var items: [ShelfItem] { store.shelf(controller.shelfID)?.items ?? [] }

    var body: some View {
        // The header rides in the safe area so tiles scroll under it with the system's soft edge.
        content
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .overlay(DropHighlight(active: controller.isDropTarget, flash: controller.dropFlash).allowsHitTesting(false))
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
        HStack(spacing: 4) {
            DragAllRepresentable(controller: controller, itemPaths: items.map(\.path))
                .frame(width: 32, height: 24)
                .padding(.trailing, 2)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .allowsHitTesting(false)
            Spacer(minLength: 4)
            HeaderButton(symbol: "ellipsis", help: "More actions") { controller.showActionsMenu() }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controller.actionsButtonFrame = $0 }
                .disabled(items.isEmpty)
            HeaderButton(symbol: "xmark", help: "Close shelf (it stays in Recent Shelves)") { controller.close() }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(WindowDragArea())
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                Text("Drop Files Here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("or press ⌘V to paste")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ShelfController.cornerRadius - 8, style: .continuous)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .padding([.horizontal, .bottom], 8)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 4)], spacing: 4) {
                    ForEach(items) { item in
                        TileRepresentable(item: item, selected: controller.selection.contains(item.id),
                                          emphasized: controller.isKey, controller: controller)
                            .frame(height: items.count == 1 ? 140 : 108)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { controller.selection = [] }
            )
        }
    }
}

/// A borderless symbol button that shows a soft circle on hover, like controls on Tahoe's glass panels.
struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(HeaderButtonStyle(hovering: hovering && isEnabled))
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? .primary : .secondary)
            .background(Circle().fill(.primary.opacity(configuration.isPressed ? 0.15 : hovering ? 0.08 : 0)))
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Accent ring shown while something is held over the shelf (the glass also takes an accent tint),
/// plus a brief flash when it lands.
struct DropHighlight: View {
    let active: Bool
    let flash: Bool

    var body: some View {
        let inset: CGFloat = 3
        let edge = RoundedRectangle(cornerRadius: ShelfController.cornerRadius - inset, style: .continuous)
        ZStack {
            edge.strokeBorder(Color.accentColor, lineWidth: 2.5)
                .opacity(active ? 1 : 0)
            edge.fill(Color.accentColor.opacity(flash ? 0.18 : 0))
        }
        .padding(inset)
    }
}
