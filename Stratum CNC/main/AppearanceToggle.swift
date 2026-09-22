//
//  AppearanceToggle.swift
//  Stratum CNC
//
//  Sun/moon day-night toolbar button. Shared by every top-level screen
//  (Projects list, CAM, Controller) so the switch lives in one place and
//  always flips the same app-wide `AppModel.isDarkMode` flag, rather than
//  each screen owning its own copy.
//

import SwiftUI

struct AppearanceToggle: View {

    @Binding var isDarkMode: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isDarkMode.toggle()
            }
        } label: {
            Label(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                  systemImage: isDarkMode ? "moon.fill" : "sun.max.fill")
        }
        .help(isDarkMode ? "Switch to light mode" : "Switch to dark mode")
    }
}
