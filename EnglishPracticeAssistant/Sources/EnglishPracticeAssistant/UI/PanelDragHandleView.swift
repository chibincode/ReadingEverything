import SwiftUI

struct PanelDragHandleView: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: 18)
            .frame(minWidth: 18, minHeight: 18)
            .contentShape(Rectangle())
            .help("Drag")
    }
}
