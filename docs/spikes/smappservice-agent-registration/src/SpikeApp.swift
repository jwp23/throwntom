import Foundation
import ServiceManagement
import AppKit

let logPath = ProcessInfo.processInfo.environment["SPIKE_LOG"]
    ?? NSHomeDirectory() + "/spike-smappservice/app.log"

func emit(_ line: String) {
    let stamped = "[\(Date())] \(line)\n"
    FileHandle.standardOutput.write(stamped.data(using: .utf8)!)
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(stamped.data(using: .utf8)!)
        try? fh.close()
    } else {
        try? stamped.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

func describe(_ s: SMAppService.Status) -> String {
    switch s {
    case .notRegistered: return "notRegistered"
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "unknown(\(s.rawValue))"
    }
}

let env = ProcessInfo.processInfo.environment
let action = env["SPIKE_ACTION"] ?? "status"
let plistName = env["SPIKE_PLIST"] ?? "com.throwntom.spike.agent.plist"

let agent = SMAppService.agent(plistName: plistName)
let mainApp = SMAppService.mainApp

emit("--- action=\(action) bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath)")
emit("pre  agent=\(describe(agent.status)) mainApp=\(describe(mainApp.status))")

switch action {
case "register":
    do { try agent.register(); emit("agent.register() -> OK") }
    catch { emit("agent.register() -> ERROR \(error) (\(error as NSError))") }
case "unregister":
    do { try agent.unregister(); emit("agent.unregister() -> OK") }
    catch { emit("agent.unregister() -> ERROR \(error) (\(error as NSError))") }
case "login-on":
    do { try mainApp.register(); emit("mainApp.register() -> OK") }
    catch { emit("mainApp.register() -> ERROR \(error) (\(error as NSError))") }
case "login-off":
    do { try mainApp.unregister(); emit("mainApp.unregister() -> OK") }
    catch { emit("mainApp.unregister() -> ERROR \(error) (\(error as NSError))") }
case "status":
    break
default:
    emit("unknown action")
}

emit("post agent=\(describe(agent.status)) mainApp=\(describe(mainApp.status))")
exit(0)
