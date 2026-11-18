//
//  OpenLibrary.swift
//  Stratum CNC
//
//  The tools and stock libraries are browse/edit workspaces, so on macOS they open in their own
//  windows: the canvas stays visible and usable next to them. On iOS they stay sheets.
//  Same idea as `OpenSettings.swift`: views call one function and don't care about the platform.
//  `ContentView` applies `libraryPresenter(_:)` once, at the root.
//
//  Picking (the popovers in the toolpath panels) is not affected: it returns a value to the field
//  that asked for it, so it stays attached to that field.
//

import SwiftUI

enum LibraryWindow {
    static let toolsID = "tools-library"
    static let stocksID = "stocks-library"
}

private struct OpenToolLibraryKey: EnvironmentKey {
    static var defaultValue: () -> Void { {} }
}

private struct OpenStockLibraryKey: EnvironmentKey {
    static var defaultValue: () -> Void { {} }
}

extension EnvironmentValues {
    /// Opens the tool library: a window on macOS (brought to front if already open), a sheet on iOS.
    var stOpenToolLibrary: () -> Void {
        get { self[OpenToolLibraryKey.self] }
        set { self[OpenToolLibraryKey.self] = newValue }
    }

    /// Opens the stock library: a window on macOS (brought to front if already open), a sheet on iOS.
    var stOpenStockLibrary: () -> Void {
        get { self[OpenStockLibraryKey.self] }
        set { self[OpenStockLibraryKey.self] = newValue }
    }
}

private struct LibraryPresenter: ViewModifier {

    @ObservedObject var appModel: AppModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .environment(\.stOpenToolLibrary, { openWindow(id: LibraryWindow.toolsID) })
            .environment(\.stOpenStockLibrary, { openWindow(id: LibraryWindow.stocksID) })
        #else
        content
            .environment(\.stOpenToolLibrary, { appModel.showingToolsSheet = true })
            .environment(\.stOpenStockLibrary, { appModel.showingStocksSheet = true })
        #endif
    }
}

extension View {
    func libraryPresenter(_ appModel: AppModel) -> some View {
        modifier(LibraryPresenter(appModel: appModel))
    }
}

#if os(macOS)
/// Content of the tool library window. Observes `AppModel` so the window follows the app-wide
/// day/night switch (the `App` scene body doesn't re-evaluate on `AppModel` changes).
struct ToolLibraryWindowContent: View {

    @ObservedObject var appModel: AppModel

    var body: some View {
        ToolsLib_Sheet(store: appModel.toolsStore, onPick: nil, isResizable: true)
            .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
    }
}

struct StockLibraryWindowContent: View {

    @ObservedObject var appModel: AppModel

    var body: some View {
        StocksLib_Sheet(store: appModel.stocksStore, onPick: nil, isResizable: true)
            .preferredColorScheme(appModel.isDarkMode ? .dark : .light)
    }
}
#endif

// MARK: - Window chrome

private struct IsLibraryWindowKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    /// True inside a library window, where the window bar owns the title.
    var stIsLibraryWindow: Bool {
        get { self[IsLibraryWindowKey.self] }
        set { self[IsLibraryWindowKey.self] = newValue }
    }
}

extension View {
    /// A navigation title that steps aside in a library window, so the window keeps showing the
    /// library's name instead of the selected item's.
    @ViewBuilder
    func libraryNavigationTitle(_ title: String) -> some View {
        modifier(LibraryNavigationTitle(title: title))
    }
}

private struct LibraryNavigationTitle: ViewModifier {

    let title: String
    @Environment(\.stIsLibraryWindow) private var isLibraryWindow

    @ViewBuilder
    func body(content: Content) -> some View {
        if isLibraryWindow {
            content
        } else {
            content.navigationTitle(title)
        }
    }
}

#if os(macOS)
/// In a library window the header lives in the window bar: the library's name (and an optional
/// subtitle) as the window title, the search field on the right. As a sheet or popover
/// (`isWindow == false`) nothing changes.
private struct LibraryWindowChrome<Search: View>: ViewModifier {

    let isWindow: Bool
    let title: String
    let subtitle: String?
    let search: Search

    @ViewBuilder
    func body(content: Content) -> some View {
        if isWindow {
            content
                .environment(\.stIsLibraryWindow, true)
                .navigationTitle(title)
                .navigationSubtitle(subtitle ?? "")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        search
                            .frame(width: 280)
                    }
                }
        } else {
            content
        }
    }
}
#endif

extension View {
    /// Moves the library's header (title, optional subtitle, search) into the window bar when
    /// shown in a window. No-op elsewhere.
    @ViewBuilder
    func libraryWindowChrome<Search: View>(isWindow: Bool,
                                           title: String,
                                           subtitle: String? = nil,
                                           @ViewBuilder search: () -> Search) -> some View {
        #if os(macOS)
        modifier(LibraryWindowChrome(isWindow: isWindow, title: title, subtitle: subtitle, search: search()))
        #else
        self
        #endif
    }
}
