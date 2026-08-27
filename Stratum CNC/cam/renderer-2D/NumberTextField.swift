//
//  NumberTextField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

final class NumberTextField: NSTextField {

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        sendAction(action, to: target)
    }
}
