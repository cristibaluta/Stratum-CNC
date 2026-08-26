//
//  ProjectPreview.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import AppKit

struct ProjectPreview: View {

    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "photo",
                    description: Text("A preview will appear here")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
