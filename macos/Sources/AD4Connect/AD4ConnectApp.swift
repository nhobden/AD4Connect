import SwiftUI

@main
struct AD4ConnectApp: App {
    @StateObject private var viewModel = PrinterViewModel()

    var body: some Scene {
        WindowGroup("AD4Connect") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
