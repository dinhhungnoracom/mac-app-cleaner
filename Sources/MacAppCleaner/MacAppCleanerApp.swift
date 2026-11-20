import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacAppCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = AppStoreViewModel()

    var body: some Scene {
        WindowGroup("Mac App Cleaner") {
            ContentView(vm: vm)
                .frame(minWidth: 1120, minHeight: 680)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Quét ứng dụng") {
                Button("Quét lại") {
                    Task { await vm.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Điều hướng") {
                ForEach(Array(MainTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button(tab.title) {
                        vm.activeTab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}
