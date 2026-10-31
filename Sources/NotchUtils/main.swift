// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationWillTerminate(_ notification: Notification) {
        controller?.fans.restoreAutomaticNow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--open <tab>` starts pinned open on a tab.
        let args = CommandLine.arguments
        var initialTab: NotchTab?
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            initialTab = NotchTab(rawValue: args[i + 1])
        }
        controller = NotchController(pinnedTab: initialTab)

        #if DEMO
        if let i = args.firstIndex(of: "--demo-capture"), i + 1 < args.count, let controller {
            DispatchQueue.main.async {
                let capture = DemoCapture(controller: controller, directory: args[i + 1])
                if args.contains("--thermals-states") {
                    capture.runThermalsStates()
                } else {
                    capture.run()
                }
            }
            return
        }
        #endif

        // `--snapshot <path>` writes the panel to a PNG once it has settled, then quits.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [controller] in
                controller?.writeSnapshot(to: args[i + 1])
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
