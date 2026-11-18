//
//  ResizableSidePanel.swift
//  Stratum CNC
//

#if os(macOS)
import SwiftUI
import AppKit

/// Gives a side panel a user-adjustable width. The drag handle sits in the gap between the
/// panel and its neighbour, on the panel's trailing (or leading) edge.
/// Double-click the handle to reset to the default width.
struct ResizableSidePanel: ViewModifier {

    enum HandleEdge {
        case leading
        case trailing
    }

    @Binding var width: Double
    let range: ClosedRange<Double>
    let handleEdge: HandleEdge
    let defaultWidth: Double
    /// Space between this panel and its neighbour; the handle fills it.
    let gap: CGFloat

    @State private var widthAtDragStart: Double?
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .overlay(alignment: handleEdge == .trailing ? .trailing : .leading) {
                handle
                    .offset(x: handleEdge == .trailing ? gap : -gap)
            }
    }

    private var isActive: Bool {
        isHovering || widthAtDragStart != nil
    }

    /// Three dots in the middle of the panel's height. Only they (plus a little margin) take
    /// the drag, so the rest of the edge stays inert.
    private var handle: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.55))
        .frame(width: gap, height: 36)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(drag)
        .onTapGesture(count: 2) {
            width = defaultWidth
        }
    }

    // Global coordinates: the handle moves with the panel while dragging, so local
    // coordinates would feed back into themselves and jitter.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                let delta = handleEdge == .trailing ? value.translation.width : -value.translation.width
                width = min(max(start + delta, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in
                widthAtDragStart = nil
            }
    }
}

extension View {
    func resizableSidePanel(width: Binding<Double>,
                            range: ClosedRange<Double>,
                            handleEdge: ResizableSidePanel.HandleEdge = .trailing,
                            defaultWidth: Double,
                            gap: CGFloat = 16) -> some View {
        modifier(ResizableSidePanel(width: width,
                                    range: range,
                                    handleEdge: handleEdge,
                                    defaultWidth: defaultWidth,
                                    gap: gap))
    }
}
#else
import SwiftUI

extension View {
    /// iOS keeps the fixed width.
    func resizableSidePanel(width: Binding<Double>,
                            range: ClosedRange<Double>,
                            defaultWidth: Double,
                            gap: CGFloat = 16) -> some View {
        frame(width: defaultWidth)
    }
}
#endif
