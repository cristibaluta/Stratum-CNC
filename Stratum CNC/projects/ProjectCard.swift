//
//  ProjectCard.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import AppKit

struct ProjectCard: View {

    let project: Project
    let previewImage: NSImage?
    /// Material and size of the stock, if the project has one.
    var stockSummary: String? = nil
    @State private var isHovered: Bool = false

    /// The path with the user's real home folder shown as `~`. In a sandboxed
    /// app `NSHomeDirectory()` is the app's container, so ask the system.
    private static func displayPath(_ path: String) -> String {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ProjectPreview(image: previewImage)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.5))
                .clipped()

            Divider()

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                // What it is made of and how big, to tell apart projects with similar names
                if let stockSummary {
                    Text(stockSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(stockSummary)
                }

                HStack {
                    Text(project.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(stockSummary == nil ? .secondary : .tertiary)
                    Spacer()

                    // Projects saved outside the app show where they live.
                    if project.isExternal, let path = project.path {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help(path)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(
            RoundedRectangle(cornerRadius: 10)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? Color.primary.opacity(0.4) : Color(nsColor: .separatorColor))
        }
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: isHovered ? 8 : 0, x: 0, y: 3)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
