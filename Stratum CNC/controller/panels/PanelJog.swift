//
//  JogView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

struct PanelJog: View {

    /// Step: a click (or game controller press) moves once by the chosen
    /// step. Hold: the machine moves for as long as the button is held.
    private enum JogMode: Hashable {
        case step
        case hold
    }

    @ObservedObject var model: ControllerModel
    @ObservedObject var joystick: GameControllerStore
    /// Speed used in hold mode, in mm/min. Owned by `ControllerModel`.
    @Binding var holdFeed: Double

    @State private var leftHighlighted = false
    @State private var rightHighlighted = false
    @State private var topHighlighted = false
    @State private var bottomHighlighted = false
    @State private var zUpHighlighted = false
    @State private var zDownHighlighted = false
    @State private var aLeftHighlighted = false
    @State private var aRightHighlighted = false

    @State private var joystickActive = false

    @State private var jogMode: JogMode = .step
    @State private var selectedJogStep: Double = 0.1
    var onJog: ((ControllerModel.JogRequest) -> Void)?
    /// Hold mode: a direction went down (`true`) or came back up (`false`).
    var onHold: ((JogDirection, Bool) -> Void)?
    /// Ends every hold at once — mode changed, view left, controller disabled.
    var onStopHold: (() -> Void)?

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        homingAction
                        joystickView
                    }
                    Divider()
                        .frame(height: 142)
                    VStack(spacing: 16) {
                        aAxisView
                        Divider()
                        zAxisView
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    modePicker
                }

                if let j = joystick.controllers.first {
                    HStack(spacing: 8) {
                        Toggle("Enable \(j.vendorName ?? "Unknown")", isOn: $joystickActive)
                            .stCheckboxToggleStyle()
                            .font(.caption)
                            .onChange(of: joystickActive) { _, newValue in
                                joystick.setActive(newValue)
                                if !newValue {
                                    onStopHold?()
                                }
                            }
                        Spacer()
                    }
                    Divider()
                }
            }
            .padding(8)
        }
        .onChange(of: jogMode) { _, _ in
            // Whatever was held belongs to the mode that's just been left.
            onStopHold?()
        }
        .onDisappear {
            onStopHold?()
        }
        .task {
            for await event in joystick.buttonPresses {
                setHighlight(for: event.button, pressed: event.isPressed)

                // Step-size shortcuts act on the press only.
                if event.isPressed {
                    if event.button == .leftShoulder {
                        selectedJogStep = min(10, selectedJogStep + 0.01)
                    } else if event.button == .leftTrigger {
                        selectedJogStep = max(0.01, selectedJogStep - 0.01)
                    }
                }

                // Moving the machine needs the "Enable" checkbox; without
                // it the controller only lights up the on-screen buttons.
                guard joystickActive, let direction = jogDirection(for: event.button) else {
                    continue
                }
                switch jogMode {
                case .hold:
                    onHold?(direction, event.isPressed)
                case .step:
                    if event.isPressed {
                        step(direction)
                    }
                }
            }
        }
    }

    private func jogDirection(for button: GameControllerStore.ButtonPress.Button) -> JogDirection? {
        switch button {
            case .dpadUp: .yPlus
            case .dpadDown: .yMinus
            case .dpadLeft: .xMinus
            case .dpadRight: .xPlus
            case .rightShoulder: .zPlus
            case .rightTrigger: .zMinus
            default: nil
        }
    }

    private func setHighlight(for button: GameControllerStore.ButtonPress.Button, pressed: Bool) {
        switch button {
            case .dpadLeft: leftHighlighted = pressed
            case .dpadRight: rightHighlighted = pressed
            case .dpadUp: topHighlighted = pressed
            case .dpadDown: bottomHighlighted = pressed
            case .rightShoulder: zUpHighlighted = pressed
            case .rightTrigger: zDownHighlighted = pressed
            default: break
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        Picker("Mode", selection: $jogMode) {
            Text("Step").tag(JogMode.step)
            Text("Hold").tag(JogMode.hold)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Step: one move per click. Hold: keeps moving while the button is held.")

        switch jogMode {
            case .step:
                stepPicker
            case .hold:
                speedPicker
        }
    }

    private var speedPicker: some View {
        HStack {
            Text("Speed")
                .font(.caption)
            Picker("Speed", selection: $holdFeed) {
                Text("Slow").tag(250.0)
                Text("Medium").tag(750.0)
                Text("Fast").tag(1500.0)
            }
            .labelsHidden()
            .help("250 / 750 / 1500 mm/min. The machine coasts a little after release — faster means further.")
            Spacer()
        }
    }

    private var stepPicker: some View {
        HStack {
            Text("Step")
                .font(.caption)
            Picker("Step", selection: $selectedJogStep) {
                Text("0.01 mm").tag(0.01)
                Text("0.1 mm").tag(0.1)
                Text("1 mm").tag(1.0)
                Text("10 mm").tag(10.0)
                if ![0.01, 0.1, 1.0, 10.0, 100.0].contains(selectedJogStep) {
                    Text("\(selectedJogStep, specifier: "%g") mm")
                        .tag(selectedJogStep)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
        }
    }

    private var joystickView: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 8) {
            GridRow {
                diagonalButton("arrow.up.left", help: "X- Y+", directions: [.xMinus, .yPlus])
                jogButton("arrow.up", help: "Y+", direction: .yPlus, isHighlighted: $topHighlighted)
                diagonalButton("arrow.up.right", help: "X+ Y+", directions: [.xPlus, .yPlus])
            }
            GridRow {
                jogButton("arrow.left", help: "X-", direction: .xMinus, isHighlighted: $leftHighlighted)
                Button {
                    onJog?(.absolute(x: 0, y: 0, z: nil, a: nil))
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 36, height: 30)
                }
                .help("Go to the work's XY zero")
                jogButton("arrow.right", help: "X+", direction: .xPlus, isHighlighted: $rightHighlighted)
            }
            GridRow {
                diagonalButton("arrow.down.left", help: "X- Y-", directions: [.xMinus, .yMinus])
                jogButton("arrow.down", help: "Y-", direction: .yMinus, isHighlighted: $bottomHighlighted)
                diagonalButton("arrow.down.right", help: "X+ Y-", directions: [.xPlus, .yMinus])
            }
        }
    }

    /// A corner of the pad: moves X and Y at the same time. Just the arrow, no button chrome.
    private func diagonalButton(_ systemName: String,
                                help: String,
                                directions: [JogDirection]) -> some View {
        JogPadButton(systemName: systemName, minWidth: 36, minHeight: 30, showsChrome: false,
                     isHighlighted: false, begin: { beginJog(directions) })
            .help(help)
    }

    private var zAxisView: some View {
        VStack {
            jogButton("arrow.up.to.line", help: "Z+", w: 40, direction: .zPlus, isHighlighted: $zUpHighlighted)
            Text("Z")
                .font(.caption)
                .frame(maxWidth: .infinity)
            jogButton("arrow.down.to.line", help: "Z-", w: 40, direction: .zMinus, isHighlighted: $zDownHighlighted)
        }
    }

    private var aAxisView: some View {
        HStack(spacing: 0) {
            jogButton("arrow.trianglehead.clockwise.rotate.90", help: "A+", w: 16, h: 24, direction: .aPlus, isHighlighted: $aRightHighlighted)
            Text("A")
                .font(.caption)
                .frame(maxWidth: .infinity)
            jogButton("arrow.trianglehead.counterclockwise.rotate.90", help: "A-", w: 16, h: 24, direction: .aMinus, isHighlighted: $aLeftHighlighted)
        }
    }

    /// One direction button; see `JogPadButton` and `beginJog`.
    private func jogButton(_ systemName: String,
                           help: String,
                           w: CGFloat? = 36,
                           h: CGFloat? = 30,
                           direction: JogDirection,
                           isHighlighted: Binding<Bool>) -> some View {
        JogPadButton(systemName: systemName, minWidth: w, minHeight: h, showsChrome: true,
                     isHighlighted: isHighlighted.wrappedValue, begin: { beginJog([direction]) })
            .help(help)
    }

    /// A pad button went down. What it does is decided now, by the mode at
    /// this moment, and the returned closure finishes exactly that: a hold
    /// ends on release, a step moves on release (unless the press was dragged
    /// away), even if the mode was switched in between.
    private func beginJog(_ directions: [JogDirection]) -> (_ cancelled: Bool) -> Void {
        switch jogMode {
        case .hold:
            directions.forEach { onHold?($0, true) }
            return { _ in
                directions.forEach { onHold?($0, false) }
            }
        case .step:
            return { cancelled in
                if !cancelled {
                    step(directions)
                }
            }
        }
    }

    /// One relative step of `selectedJogStep` in `direction` — see
    /// `ControllerModel.JogRequest`.
    private func step(_ direction: JogDirection) {
        step([direction])
    }

    /// One relative move combining several directions (the diagonals: X and Y at once).
    private func step(_ directions: [JogDirection]) {
        let x = directions.reduce(0) { $0 + $1.unit.x }
        let y = directions.reduce(0) { $0 + $1.unit.y }
        let z = directions.reduce(0) { $0 + $1.unit.z }
        let a = directions.reduce(0) { $0 + $1.unit.a }
        onJog?(.relative(x: x == 0 ? nil : x * selectedJogStep,
                         y: y == 0 ? nil : y * selectedJogStep,
                         z: z == 0 ? nil : z * selectedJogStep,
                         a: a == 0 ? nil : a * selectedJogStep))
    }

    private var homingAction: some View {
        HStack(spacing: 8) {
            Button {
                model.sendRawCommand(model.homeCommand)
            } label: {
                Label("Home", systemImage: "house")
            }
            .help("Return to the machine's home position")

            //            if isAlarm {
            //                Button {
            //                    model.sendRawCommand(model.unlockCommand)
            //                } label: {
            //                    Label("Unlock", systemImage: "lock.open")
            //                }
            //                .buttonStyle(QuietButtonStyle(tint: .orange))
            //                .help("Clear the alarm lock so the machine can move")
            //            }
            .buttonStyle(.quiet)

            Spacer()
        }
    }
}

/// A jog button driven by one `DragGesture(minimumDistance: 0)` instead of a
/// `Button`. On macOS a `Button` tracks the mouse itself until mouse-up, so a
/// gesture attached next to it never sees the mouse-down and hold-to-jog
/// silently does nothing. This view owns the whole press, for both modes.
private struct JogPadButton: View {

    let systemName: String
    var minWidth: CGFloat?
    var minHeight: CGFloat?
    /// False for the diagonal corners: just the glyph.
    var showsChrome: Bool
    /// Lit from outside (the game controller's D-pad).
    var isHighlighted: Bool
    /// Called on mouse-down; returns what to do on mouse-up (`true` = the
    /// pointer was dragged well away, i.e. the click was abandoned).
    var begin: () -> (_ cancelled: Bool) -> Void

    @State private var finish: ((Bool) -> Void)?

    /// How far a press may slide and still count as a click, in points.
    private let clickSlop: CGFloat = 40

    private var isActive: Bool {
        finish != nil || isHighlighted
    }

    var body: some View {
        Image(systemName: systemName)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .foregroundStyle(foreground)
            .background {
                if showsChrome {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.primary.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard finish == nil else {
                            return
                        }
                        finish = begin()
                    }
                    .onEnded { value in
                        let done = finish
                        finish = nil
                        let slid = hypot(value.translation.width, value.translation.height)
                        done?(slid > clickSlop)
                    }
            )
            .onDisappear {
                // The view going away mid-press never delivers a mouse-up.
                let done = finish
                finish = nil
                done?(true)
            }
    }

    private var foreground: Color {
        if showsChrome {
            return isActive ? .white : .primary
        }
        return isActive ? .accentColor : .secondary
    }
}
