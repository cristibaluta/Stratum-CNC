//
//  RemoteFilesPopover.swift
//  Stratum CNC
//

import SwiftUI
import StratumLink

/// The G-code files on the machine's SD card, in a popover. Picking one
/// downloads it and loads it like any imported file (`onSelect`).
struct RemoteFilesPopover: View {

    @ObservedObject var info: MachineInfo
    @ObservedObject var downloader: MachineFileDownloader
    let isConnected: Bool
    let onSelect: (MachineFileEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let gcodeExtensions: Set<String> = ["nc", "ngc", "gcode", "cnc", "tap", "gc"]

    private var visibleFiles: [MachineFileEntry] {
        info.files.filter {
            // Hidden entries (".md5", ".lz" …) are the machine's own bookkeeping.
            !$0.name.hasPrefix(".") &&
            ($0.isDirectory || Self.gcodeExtensions.contains(($0.name as NSString).pathExtension.lowercased()))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    info.listFiles(in: (info.currentDirectory as NSString).deletingLastPathComponent)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(info.currentDirectory == "/sd" || info.currentDirectory == "/" || !isConnected)
                .help("Parent folder")

                Text(info.currentDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                if info.isLoadingFiles {
                    ProgressView().controlSize(.small)
                }
                Button {
                    info.listFiles(in: info.currentDirectory)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!isConnected || downloader.isActive)
                .help("Refresh")
            }

            Divider()

            if !isConnected {
                placeholder("Connect to a machine to see its files.")
            } else if visibleFiles.isEmpty {
                placeholder(info.isLoadingFiles ? "Loading…" : "No G-code files in this folder.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleFiles) { file in
                            row(file)
                        }
                    }
                }
                .frame(height: 260)
            }

            switch downloader.state {
            case .downloading(let path, let bytes):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading \((path as NSString).lastPathComponent)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(downloader.progress > 0
                             ? "\(Int(downloader.progress * 100))%"
                             : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    // Indeterminate until the machine reports the packet count.
                    if downloader.progress > 0 {
                        ProgressView(value: downloader.progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle:
                EmptyView()
            }
        }
        .padding(12)
        .frame(width: 340)
        // Stays open while the file comes down (so the progress is visible),
        // then closes itself once it has been handed over.
        .onChange(of: downloader.isActive) { wasActive, isActive in
            if wasActive, !isActive, downloader.state == .idle { dismiss() }
        }
        .onAppear {
            if isConnected, !downloader.isActive {
                info.listFiles(in: info.currentDirectory)
            }
        }
    }

    private func row(_ file: MachineFileEntry) -> some View {
        Button {
            if file.isDirectory {
                info.listFiles(in: file.path)
            } else {
                onSelect(file)
            }
        } label: {
            HStack {
                Image(systemName: file.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !file.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(downloader.isActive)
        .help(file.modified.map { $0.formatted() } ?? file.path)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
