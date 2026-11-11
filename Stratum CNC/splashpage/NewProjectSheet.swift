//
//  NewProjectSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var usesCustomLocation = false
    @State private var customFolder: URL?
    #if !os(macOS)
    @State private var isChoosingFolder = false
    #endif
    @State private var errorMessage: String?

    /// Creates the project: in the app's own storage when `folder` is nil, or
    /// as `<folder>/<name>/` otherwise. Throws to keep the sheet open and show why.
    let onCreate: (String, URL?) throws -> Void

    private var trimmedName: String {
        name.trimmed
    }

    private var canCreate: Bool {
        ProjectPaths.isValidName(trimmedName) && (!usesCustomLocation || customFolder != nil)
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

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Save in a custom location", isOn: $usesCustomLocation)

                if usesCustomLocation {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(customFolder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "No folder chosen")
                            .font(.callout)
                            .foregroundStyle(customFolder == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button("Choose…") {
                            chooseFolder()
                        }
                    }
                    Text("A folder named after the project is created inside the location you choose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The project is managed by Stratum and stored in the app's own storage, so you don't need to look after any files. Turn this on to keep it in a folder you pick, such as Documents or a shared drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
        #if os(macOS)
        .frame(width: 420)
        #endif
        .onChange(of: usesCustomLocation) { _, isOn in
            errorMessage = nil
            // Ask for the folder right away; if the user backs out, there's no custom location.
            if isOn && customFolder == nil {
                chooseFolder()
                #if os(macOS)
                // The panel above is modal; on iOS the picker answers later (see `fileImporter`).
                if customFolder == nil {
                    usesCustomLocation = false
                }
                #endif
            }
        }
        .onChange(of: name) { _, _ in
            errorMessage = nil
        }
        #if !os(macOS)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                // Needed to make the bookmark of this folder when the project is created
                _ = url.startAccessingSecurityScopedResource()
                customFolder = url
            }
            if customFolder == nil {
                usesCustomLocation = false
            }
        }
        #endif
    }

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Project Location"
        panel.message = "Choose the folder where the new project folder will be created."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customFolder = url
        }
        #else
        isChoosingFolder = true
        #endif
    }

    private func create() {
        guard canCreate else {
            return
        }

        do {
            try onCreate(trimmedName, usesCustomLocation ? customFolder : nil)
            dismiss()
        } catch ProjectError.projectAlreadyExists {
            errorMessage = usesCustomLocation
                ? "A folder named “\(trimmedName)” already exists in that location."
                : "A project named “\(trimmedName)” already exists."
        } catch ProjectError.bookmarkFailed {
            errorMessage = "Couldn't keep access to that folder. Choose another location."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
