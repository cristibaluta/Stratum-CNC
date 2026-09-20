//
//  MachineConnectSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//


//
//  MachineConnectSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI

/// Presented from `GCodeViewer`'s Play/"Send to Machine" button in place of
/// `MachiningRunSheet` when nothing is connected yet — wraps `MachinesList`
/// (the same discovery/selection list the toolbar's machine picker uses) as
/// a sheet, so starting a job from a cold app isn't a dead end at a
/// disabled button.
///
/// No new connection logic here: `MachinesList`'s selection binding IS
/// `model.selectedMachine`, and `ControllerView` already has an
/// `onChange(of: model.selectedMachine)` that calls `connection.connect(to:)`
/// — that fires the same way whether the selection change came from the
/// toolbar picker or from here, since this sheet is presented on top of
/// `ControllerView`, not instead of it. This view only presents the list and
/// hands off once a connection lands.
struct MachineConnectSheet: View {

    @ObservedObject var model: ControllerModel
    /// Observed directly, not just through `model`, for the same reason
    /// `GCodeViewer` observes `connection` on its own (see its doc comment):
    /// `connection` is a `@Published` *reference* on `ControllerModel`, so
    /// `ControllerModel` only republishes when that reference itself is
    /// reassigned, not when the connection's own `isConnected` flips. This
    /// view's whole job is to notice that flip, so it needs its own
    /// subscription to it.
    @ObservedObject var connection: MachineConnection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MachinesList(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .frame(width: 420, height: 420)
        // The connection this sheet exists to establish just landed — hand
        // off straight to the review sheet instead of leaving the person to
        // notice and tap Play a second time.
        .onChange(of: connection.isConnected) { _, isConnected in
            guard isConnected else { return }
            dismiss()
            model.isShowingRunReview = true
        }
    }
}