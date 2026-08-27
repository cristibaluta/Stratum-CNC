//
//  JogView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.08.2026.
//

import SwiftUI

struct PanelJog: View {

    @ObservedObject var joystick: GameControllerStore

    @State private var leftHighlighted = false
    @State private var rightHighlighted = false
    @State private var topHighlighted = false
    @State private var bottomHighlighted = false
    @State private var zUpHighlighted = false
    @State private var zDownHighlighted = false
    @State private var aLeftHighlighted = false
    @State private var aRightHighlighted = false

    @State private var joystickActive = false

    @State private var selectedJogStep: Double = 0.1
    var onJog: ((Double?, Double?, Double?, Double?) -> Void)?

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
                            }
                        Spacer()
                    }
                    Divider()
                }

                HStack(spacing: 8) {
                    VStack(spacing: 8) {
                        stepPicker
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
        .task {
            var resetTask: Task<Void, Never>?
            for await press in joystick.buttonPresses {
                print(">>>>>>>> \(press)")
                leftHighlighted = press.button == .dpadLeft
                rightHighlighted = press.button == .dpadRight
                topHighlighted = press.button == .dpadUp
                bottomHighlighted = press.button == .dpadDown
                zUpHighlighted = press.button == .rightShoulder
                zDownHighlighted = press.button == .rightTrigger

                if press.button == .leftShoulder {
                    selectedJogStep = min(10, selectedJogStep + 0.01)
                } else if press.button == .leftTrigger {
                    selectedJogStep = max(0.01, selectedJogStep - 0.01)
                }

                resetTask?.cancel()
                resetTask = Task {
                    try? await Task.sleep(for: .milliseconds(100))

                    leftHighlighted = false
                    rightHighlighted = false
                    topHighlighted = false
                    bottomHighlighted = false
                    zUpHighlighted = false
                    zDownHighlighted = false
                    aLeftHighlighted = false
                    aRightHighlighted = false
                }
            }
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

                jogButton("arrow.up", help: "Y+", isHighlighted: $topHighlighted) {
                    jog(y: selectedJogStep)
                }

                Spacer()
            }

            HStack(spacing: 5) {
                jogButton("arrow.left", help: "X-", isHighlighted: $leftHighlighted) {
                    jog(x: -selectedJogStep)
                }

                Button {
                    jog(x: 0, y: 0)
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 36, height: 30)
                }
                .help("Move X/Y to zero")

                jogButton("arrow.right", help: "X+", isHighlighted: $rightHighlighted) {
                    jog(x: selectedJogStep)
                }
            }

            HStack(spacing: 5) {
                Spacer()

                jogButton("arrow.down", help: "Y-", isHighlighted: $bottomHighlighted) {
                    jog(y: -selectedJogStep)
                }

                Spacer()
            }
        }
    }

    private var zAxisView: some View {
        VStack {
            jogButton("arrow.up.to.line", help: "Z+", w: 40, isHighlighted: $zUpHighlighted) {
                jog(z: selectedJogStep)
            }
            Text("Z")
                .font(.caption)
                .frame(maxWidth: .infinity)
            jogButton("arrow.down.to.line", help: "Z-", w: 40, isHighlighted: $zDownHighlighted) {
                jog(z: -selectedJogStep)
            }
        }
    }

    private var aAxisView: some View {
        HStack(spacing: 0) {
            jogButton("arrow.trianglehead.clockwise.rotate.90", help: "A+", w: 16, h: 24, isHighlighted: $aRightHighlighted) {
                jog(z: selectedJogStep)
            }
            Text("A")
                .font(.caption)
                .frame(maxWidth: .infinity)
            jogButton("arrow.trianglehead.counterclockwise.rotate.90", help: "A-", w: 16, h: 24, isHighlighted: $aLeftHighlighted) {
                jog(z: -selectedJogStep)
            }
        }
    }

    private func jogButton(_ systemName: String,
                           help: String,
                           w: CGFloat? = 36,
                           h: CGFloat? = 30,
                           isHighlighted: Binding<Bool>,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(minWidth: w, minHeight: h)
        }
        .modifier(HighlightModifier(isHighlighted: isHighlighted.wrappedValue))
        .help(help)
    }

    private func jog(x: Double? = nil, y: Double? = nil, z: Double? = nil, a: Double? = nil) {
        onJog?(x, y, z, nil)
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
