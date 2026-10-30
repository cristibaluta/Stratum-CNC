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
                // The preview is a transparent drawing in black: shown as a template in the
                // text color, it reads on both the light and the dark card background.
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
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
