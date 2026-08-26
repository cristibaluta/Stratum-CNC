//
//  GameControllerStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation
import GameController
import CoreHaptics

@MainActor
final class GameControllerStore: ObservableObject {

    struct ButtonPress: Identifiable, Equatable {
        let id = UUID()
        let controllerID: ObjectIdentifier
        let button: Button
        let timestamp = Date()

        enum Button: String {
            case a
            case b
            case x
            case y
            case dpadUp
            case dpadDown
            case dpadLeft
            case dpadRight
            case leftShoulder
            case rightShoulder
            case leftTrigger
            case rightTrigger
            case menu
            case options
            case home
        }
    }

    // MARK: - Public state

    private(set) var controllers: [GCController] = []
    private(set) var lastButtonPress: ButtonPress?

    /// All button presses, useful for consumers that want an event stream.
    let buttonPresses: AsyncStream<ButtonPress>

    // MARK: - Private

    private let continuation: AsyncStream<ButtonPress>.Continuation
    private var notificationTasks: [Task<Void, Never>] = []

    init() {
        var continuation: AsyncStream<ButtonPress>.Continuation!

        buttonPresses = AsyncStream { continuation = $0 }
        self.continuation = continuation

        refreshControllers()
        startListening()
    }

    deinit {
        continuation.finish()
//        notificationTasks.forEach { $0.cancel() }
    }

    // MARK: - Controller discovery

    func refreshControllers() {
        controllers = GCController.controllers()
    }

    private func startListening() {
        let connected = NotificationCenter.default.notifications(named: .GCControllerDidConnect)
        let disconnected = NotificationCenter.default.notifications(named: .GCControllerDidDisconnect)

        notificationTasks.append(
            Task { [weak self] in
                for await notification in connected {
                    guard let self, let controller = notification.object as? GCController else {
                        continue
                    }
                    self.addController(controller)
                }
            }
        )

        notificationTasks.append(
            Task { [weak self] in
                for await notification in disconnected {
                    guard let self, let controller = notification.object as? GCController else {
                        continue
                    }
                    self.removeController(controller)
                }
            }
        )

        // Configure controllers that were already connected.
        for controller in GCController.controllers() {
            configure(controller)
        }
    }

    private func addController(_ controller: GCController) {
        print("added controller \(String(describing: controller.vendorName))")
        guard !controllers.contains(where: { $0 === controller }) else {
            return
        }

        controllers.append(controller)
        configure(controller)
    }

    private func removeController(_ controller: GCController) {
        print("removed controller \(String(describing: controller))")
        controllers.removeAll {
            $0 === controller
        }
    }

    // MARK: - Input

    private func configure(_ controller: GCController) {
        print("🎮 CONFIGURING:", controller)

        guard let gamepad = controller.extendedGamepad else {
            print("❌ NO EXTENDED GAMEPAD")
            print("microGamepad:", controller.microGamepad as Any)
//            print("gamepad:", controller.gamepad as Any)
            return
        }

        print("✅ EXTENDED GAMEPAD FOUND")
        print("left:", gamepad.leftThumbstick)
        print("right:", gamepad.rightThumbstick)

        configureThumbsticks(gamepad)

        gamepad.buttonA.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.a, controller: controller)
        }

        gamepad.buttonB.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.b, controller: controller)
        }

        gamepad.buttonX.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.x, controller: controller)
        }

        gamepad.buttonY.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.y, controller: controller)
        }

        gamepad.dpad.up.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.dpadUp, controller: controller)
        }

        gamepad.dpad.down.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.dpadDown, controller: controller)
        }

        gamepad.dpad.left.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.dpadLeft, controller: controller)
        }

        gamepad.dpad.right.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.dpadRight, controller: controller)
        }

        gamepad.leftShoulder.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.leftShoulder, controller: controller)
        }

        gamepad.rightShoulder.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.rightShoulder, controller: controller)
        }

        gamepad.leftTrigger.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.leftTrigger, controller: controller)
        }

        gamepad.rightTrigger.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
            guard pressed, let controller else { return }
            self?.emit(.rightTrigger, controller: controller)
        }

        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, *) {
            gamepad.buttonMenu.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
                guard pressed, let controller else { return }
                self?.emit(.menu, controller: controller)
            }

            gamepad.buttonOptions?.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
                guard pressed, let controller else { return }
                self?.emit(.options, controller: controller)
            }
        }
    }

    private func configureThumbsticks(_ gamepad: GCExtendedGamepad) {
        gamepad.leftThumbstick.valueChangedHandler = { [weak self, weak gamepad] _, x, y in
            guard let self else {
                return
            }
//            print("🕹️ LEFT:", x, y)
            self.leftStick = Stick(x: self.applyDeadZone(x), y: self.applyDeadZone(y))
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else {
                return
            }
//            print("🕹️ RIGHT:", x, y)
            self.rightStick = Stick(x: self.applyDeadZone(x), y: self.applyDeadZone(y))
        }
    }

    struct Stick: Equatable {
        var x: Float
        var y: Float
    }

    private(set) var leftStick = Stick(x: 0, y: 0)
    private(set) var rightStick = Stick(x: 0, y: 0)

    private func applyDeadZone(_ value: Float) -> Float {
        let deadZone: Float = 0.15

        guard abs(value) > deadZone else {
            return 0
        }

        let sign: Float = value < 0 ? -1 : 1
        let magnitude = (abs(value) - deadZone) / (1 - deadZone)

        return sign * magnitude
    }


    private func emit(_ button: ButtonPress.Button, controller: GCController) {
        let press = ButtonPress(controllerID: ObjectIdentifier(controller), button: button)
//        print(">>>>> joystick button pressed: \(press)")

        lastButtonPress = press
        continuation.yield(press)
    }
}

extension GameControllerStore {

    func setActive(_ isActive: Bool) {
        guard let controller = controllers.first else {
            return
        }
        isActive
        ? setLight(controller, red: 0.15, green: 0.5, blue: 0)
        : setLight(controller, red: 0.5, green: 0.5, blue: 0.5)
    }

    func setAlarm() {
        guard let controller = controllers.first else {
            return
        }
        setLight(controller, red: 1, green: 0, blue: 0) // red
    }

    func vibrate() {
        guard let controller = controllers.first else {
            return
        }
        guard let haptics = controller.haptics else {
            print("❌ Controller has no haptics API")
            return
        }

        print("Supported localities:", haptics.supportedLocalities)

        guard let engine = haptics.createEngine(withLocality: .handles) else {
            print("❌ Couldn't create haptic engine")
            return
        }

        do {
            try engine.start()

            let event = CHHapticEvent(eventType: .hapticTransient,
                                      parameters: [
                                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                                      ],
                                      relativeTime: 0
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

        } catch {
            print("❌ Haptic error:", error)
        }
    }

    private func setLight(_ controller: GCController, red: Float, green: Float, blue: Float) {
        controller.light?.color = GCColor(red: red, green: green, blue: blue)
    }
}
