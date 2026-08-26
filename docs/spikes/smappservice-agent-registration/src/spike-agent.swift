import Foundation

let logPath = NSHomeDirectory() + "/spike-smappservice/agent.log"
let line = "[\(Date())] agent started pid=\(getpid()) argv=\(CommandLine.arguments)\n"
if let fh = FileHandle(forWritingAtPath: logPath) {
    fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close()
} else {
    try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
}
// Stay alive so `launchctl print` shows a running process.
while true { sleep(60) }
