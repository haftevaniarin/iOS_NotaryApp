//
import SwiftUI
import UIKit

@main
struct NotaryLedgerApp: App {
    init() {
        NLFonts.registerBundledFonts()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-fixtures") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
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
                    .preferredColorScheme(.light)
            }
            #else
            ContentView()
                .preferredColorScheme(.light)
            #endif
        }
    }
}
