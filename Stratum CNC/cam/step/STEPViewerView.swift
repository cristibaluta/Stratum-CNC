//
//  STEPViewerView.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

import OCCTSwift
import OCCTSwiftIO
import OCCTSwiftViewport
import OCCTSwiftTools

struct STEPViewerView: View {

    // MARK: - Model

    @State private var document: OCCTSwift.Document?
    @State private var modelURL: URL?

    @State private var viewportBodies: [ViewportBody] = []

    @State private var errorMessage: String?
    @State private var isOpening = false
    @State private var isLoading = false

    // The viewport controller must live for the lifetime of the view.
    @State private var viewportController = ViewportController()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            toolbar

            Divider()

            ZStack {
                if viewportBodies.isEmpty {
                    emptyState
                } else {
                    viewport
                }

                if isLoading {
                    loadingOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 650)
        .fileImporter(
            isPresented: $isOpening,
            allowedContentTypes: [
                .init(filenameExtension: "step")!,
                .init(filenameExtension: "stp")!
            ],
            allowsMultipleSelection: false
        ) { result in
            openResult(result)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {

            Button {
                isOpening = true
            } label: {
                Label("Open STEP", systemImage: "folder")
            }
            .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let modelURL {
                Text(modelURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !viewportBodies.isEmpty {
                Text("\(viewportBodies.count) part(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    // MARK: - Viewport

    private var viewport: some View {
        viewportController.displayMode = .shadedWithEdges
        return MetalViewportView(
            controller: viewportController,
            bodies: $viewportBodies
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {

            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text("Unable to load STEP")
                    .font(.headline)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                Button("Open Another STEP") {
                    isOpening = true
                }
                .buttonStyle(.borderedProminent)

            } else {
                Text("No STEP file loaded")
                    .font(.headline)

                Button("Open STEP File") {
                    isOpening = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.15))

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text("Loading STEP…")
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(
                RoundedRectangle(cornerRadius: 12)
            )
        }
    }

    // MARK: - File Import

    private func openResult(
        _ result: Result<[URL], Error>
    ) {
        switch result {

        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            loadSTEP(url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - STEP Loading

    private func loadSTEP(_ url: URL) {

        errorMessage = nil
        document = nil
        viewportBodies.removeAll()

        modelURL = url
        isLoading = true

        let didStartAccessing =
            url.startAccessingSecurityScopedResource()

        Task {
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {

                let result = try await CADFileLoader.load(
                    from: url,
                    format: .step
                )

                await MainActor.run {
                    viewportBodies = result.bodies
                    isLoading = false
                }

            } catch {

                await MainActor.run {
                    viewportBodies.removeAll()
                    document = nil
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
