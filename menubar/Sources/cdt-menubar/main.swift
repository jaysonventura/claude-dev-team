import AppKit

// claude-dev-team menu bar usage monitor.
// `--once` / `--print`: one-shot terminal readout (no GUI). Otherwise: run the menu bar app.
if CommandLine.arguments.contains("--once") || CommandLine.arguments.contains("--print") {
    runOnce()
    exit(0)
}

// Accessory app: lives in the menu bar only, no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = MenuBarController()
let store = UsageStore(controller: controller)
store.start()

app.run()
