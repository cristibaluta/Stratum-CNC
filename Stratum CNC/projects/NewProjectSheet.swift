//
//  NewProjectSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct NewProjectSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    let onCreate: (String) -> Void

    private var canCreate: Bool {
        ProjectPaths.isValidName(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("New Project")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    create()
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard ProjectPaths.isValidName(trimmed) else {
            return
        }

        onCreate(trimmed)
        dismiss()
    }
}
