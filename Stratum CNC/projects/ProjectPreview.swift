//
//  ProjectPreview.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import AppKit

struct ProjectPreview: View {

    let image: NSImage?

    var body: some View {
        Group {
            if let image {
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
