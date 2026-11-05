//
import SwiftUI

@main
struct NotaryLedgerApp: App {
    init() {
        NLFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Unit tests provide their own views and fixture services. Avoid starting
            // the live session bootstrap behind the snapshot host.
            if NSClassFromString("XCTestCase") != nil {
                Color.clear
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
