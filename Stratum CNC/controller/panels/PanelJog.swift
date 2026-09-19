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
    /// Directions the mouse is currently holding down on screen — so the
    /// drag gesture, which reports continuously, only starts each hold once.
    @State private var mouseHeld: Set<JogDirection> = []

    var onJog: ((ControllerModel.JogRequest) -> Void)?
    /// Hold mode: a direction went down (`true`) or came back up (`false`).
    var onHold: ((JogDirection, Bool) -> Void)?
    /// Ends every hold at once — mode changed, view left, controller disabled.
    var onStopHold: (() -> Void)?

    var body: some View {
        GroupBox("JOG") {
            VStack {
                if let j = joystick.controllers.first {
                    HStack(spacing: 8) {
                        Toggle("Enable \(j.vendorName ?? "Unknown")", isOn: $joystickActive)
                            .toggleStyle(.checkbox)
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

                HStack(spacing: 8) {
                    VStack(spacing: 8) {
                        modePicker
                        joystickView
                    }
                    Divider()
                    VStack(spacing: 16) {
                        aAxisView
                        Divider()
                        zAxisView
                    }
                }
            }
            .padding(8)
        }
        .onChange(of: jogMode) { _, _ in
            // Whatever was held belongs to the mode that's just been left.
            mouseHeld.removeAll()
            onStopHold?()
        }
        .onDisappear {
            mouseHeld.removeAll()
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

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .labelsHidden()
            Spacer()
        }
    }

    private var joystickView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Spacer()

                jogButton("arrow.up", help: "Y+", direction: .yPlus, isHighlighted: $topHighlighted)

                Spacer()
            }

            HStack(spacing: 5) {
                jogButton("arrow.left", help: "X-", direction: .xMinus, isHighlighted: $leftHighlighted)

                Button {
                    // Absolute, unlike the arrow buttons: go to work zero,
                    // don't step by 0.
                    onJog?(.absolute(x: 0, y: 0, z: nil, a: nil))
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 36, height: 30)
                }
                .help("Move X/Y to zero")

                jogButton("arrow.right", help: "X+", direction: .xPlus, isHighlighted: $rightHighlighted)
            }

            HStack(spacing: 5) {
                Spacer()

                jogButton("arrow.down", help: "Y-", direction: .yMinus, isHighlighted: $bottomHighlighted)

                Spacer()
            }
        }
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

    /// One direction button. Step mode acts on the click; hold mode acts on
    /// the mouse going down and coming back up, which a `Button`'s own
    /// action can't report — hence the drag gesture (no minimum distance, so
    /// it starts on mouse-down, and it keeps tracking until mouse-up even if
    /// the pointer slides off the button).
    private func jogButton(_ systemName: String,
                           help: String,
                           w: CGFloat? = 36,
                           h: CGFloat? = 30,
                           direction: JogDirection,
                           isHighlighted: Binding<Bool>) -> some View {
        Button {
            if jogMode == .step {
                step(direction)
            }
        } label: {
            Image(systemName: systemName)
                .frame(minWidth: w, minHeight: h)
        }
        .modifier(HighlightModifier(isHighlighted: isHighlighted.wrappedValue))
        .help(help)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard jogMode == .hold, !mouseHeld.contains(direction) else {
                        return
                    }
                    mouseHeld.insert(direction)
                    onHold?(direction, true)
                }
                .onEnded { _ in
                    guard mouseHeld.remove(direction) != nil else {
                        return
                    }
                    onHold?(direction, false)
                }
        )
    }

    /// One relative step of `selectedJogStep` in `direction` — see
    /// `ControllerModel.JogRequest`.
    private func step(_ direction: JogDirection) {
        let unit = direction.unit
        onJog?(.relative(x: unit.x == 0 ? nil : unit.x * selectedJogStep,
                         y: unit.y == 0 ? nil : unit.y * selectedJogStep,
                         z: unit.z == 0 ? nil : unit.z * selectedJogStep,
                         a: unit.a == 0 ? nil : unit.a * selectedJogStep))
    }
}

private struct HighlightModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        if isHighlighted {
            content
                .buttonStyle(.borderedProminent)
                .tint(.blue)
        } else {
            content
        }
    }
}
