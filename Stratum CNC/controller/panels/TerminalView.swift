//
//  TerminalView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI

struct TerminalView: View {

    @ObservedObject var model: ControllerModel
    @FocusState private var commandFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
//            HStack {
//                Spacer()
//                Toggle("Auto-scroll", isOn: $model.terminalAutoScroll)
//                    .toggleStyle(.checkbox)
//                    .font(.caption)
//                Button {
//                    model.clearTerminal()
//                } label: {
//                    Image(systemName: "trash")
//                }
//                .buttonStyle(.borderless)
//                .help("Clear terminal")
//            }

            terminalView

            Divider()

            commandBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.connection.rawLog.enumerated()), id: \.offset) { index, line in
                        terminalLine(line)
                            .id(index)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("terminal-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: model.connection.rawLog.count) {
                guard model.terminalAutoScroll else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("terminal-bottom", anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func terminalLine(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if line.hasPrefix("> ") {
                Text(">")
                    .foregroundStyle(.blue)

                Text(
                    String(line.dropFirst(2))
                )
                .foregroundStyle(.primary)
            } else {
                Text("<")
                    .foregroundStyle(.green)

                Text(line)
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    // MARK: - Command Bar

    private var commandBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)

            TextField("Send a command…", text: $model.mdiInput)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .focused(
                $commandFieldFocused
            )
            .onSubmit {
                model.sendMDI()
            }
            .onKeyPress(.upArrow) {
                model.historyPrevious()
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.historyNext()
                return .handled
            }
            .onKeyPress(.escape) {
                model.mdiInput = ""
                model.historyIndex = nil
                return .handled
            }

            if !model.mdiInput.isEmpty {
                Button {
                    model.mdiInput = ""
                    model.historyIndex = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Button {
                model.sendMDI()
            } label: {
                Text("Send")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!model.connection.isConnected || model.mdiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                model.isShowingCommandPalette = true
            } label: {
                Image(systemName: "command")
            }
            .buttonStyle(.borderless)
            .help("Command palette")
        }
        .padding(.vertical, 8)
    }
}
