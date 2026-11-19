//
//  FooterButton.swift
//  Stratum CNC
//
//  The buttons in the footer of the Probe, Change Bit and Review & Start sheets: one fixed
//  width so Back, Cancel and the primary action line up, and a title that never wraps.
//

import SwiftUI

struct FooterButton: View {

    /// Wide enough for the longest title ("Resume Job" with its icon).
    static let width: CGFloat = 112

    let title: String
    var systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .lineLimit(1)
            .frame(width: Self.width)
        }
        // The system's taller button (about 28 pt on macOS against 22 pt for the default).
        .controlSize(.large)
    }
}

/// The footer row of a multi-step sheet. The primary button sits at the trailing edge. With no
/// Back button, Cancel sits right beside it; once Back appears, Cancel animates over to the
/// leading edge and Back stays next to the primary button, so the pair that moves you through
/// the steps stays together. An optional `notice` (a blocker message, say) sits next to Cancel's
/// side of the row.
struct SheetFooter<Cancel: View, Notice: View, Back: View, Primary: View>: View {

    let showsBack: Bool
    let cancel: Cancel
    let notice: Notice
    let back: Back
    let primary: Primary

    @Namespace private var namespace

    init(showsBack: Bool,
         @ViewBuilder cancel: () -> Cancel,
         @ViewBuilder notice: () -> Notice,
         @ViewBuilder back: () -> Back,
         @ViewBuilder primary: () -> Primary) {
        self.showsBack = showsBack
        self.cancel = cancel()
        self.notice = notice()
        self.back = back()
        self.primary = primary()
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsBack {
                cancel.matchedGeometryEffect(id: "cancel", in: namespace)
                notice
                Spacer(minLength: 0)
                back.transition(.opacity)
            } else {
                notice
                Spacer(minLength: 0)
                cancel.matchedGeometryEffect(id: "cancel", in: namespace)
            }
            primary
        }
        .animation(.easeInOut(duration: 0.2), value: showsBack)
        .padding(16)
    }
}

extension SheetFooter where Notice == EmptyView {
    init(showsBack: Bool,
         @ViewBuilder cancel: () -> Cancel,
         @ViewBuilder back: () -> Back,
         @ViewBuilder primary: () -> Primary) {
        self.init(showsBack: showsBack, cancel: cancel, notice: { EmptyView() }, back: back, primary: primary)
    }
}

extension SheetFooter where Notice == EmptyView, Back == EmptyView {
    init(@ViewBuilder cancel: () -> Cancel, @ViewBuilder primary: () -> Primary) {
        self.init(showsBack: false, cancel: cancel, notice: { EmptyView() }, back: { EmptyView() }, primary: primary)
    }
}
