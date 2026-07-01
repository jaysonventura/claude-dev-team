import AppKit

// claude-dev-team menu bar usage monitor.
// `--once`/`--print`: one-shot terminal readout (reads the CLI status line's usage cache; no network).
// `--refresh-usage` (opt `--force`): ONE real gated realtime fetch → merge to cache (e2e of the network path).
// `--unregister`: remove the login item. Else: run the app.
if CommandLine.arguments.contains("--once") || CommandLine.arguments.contains("--print") {
    runOnce()
    exit(0)
}
if CommandLine.arguments.contains("--refresh-usage") {
    exit(runRefreshUsage(force: CommandLine.arguments.contains("--force")))
}
if CommandLine.arguments.contains("--unregister") {
    LoginItem.disable()
    exit(0)
}

// Accessory app: lives in the menu bar only, no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

LoginItem.enable()   // launch at login, attributed to the app ("CDT Usage"), not the signing team

let controller = MenuBarController()
let store = UsageStore(controller: controller)
store.start()

app.run()
