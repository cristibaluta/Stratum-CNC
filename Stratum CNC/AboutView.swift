//
//  AboutView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//

import SwiftUI

/// Small About window, in the spirit of Xcode's: logo, version, what the app
/// is, the work-in-progress disclaimer and a link to the GitHub repository.
struct AboutView: View {

    static let windowID = "about"

    private let repositoryURL = URL(string: "https://github.com/cristibaluta/Stratum-CNC")!

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != version {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 64)

            Text(versionText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("CAM and Controller for your Makera CNC machine. Set up stock and tools, generate toolpaths, simulate the cut and send the job to your machine, all in one app.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 2)

            VStack(spacing: 6) {
                Text("This opensource software is work in progress and does not guarantee that all the features work as expected.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Link("For contributions and feedback please visit GitHub",
                     destination: repositoryURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 400)
    }
}

#Preview {
    AboutView()
}
