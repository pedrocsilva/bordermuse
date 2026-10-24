// QA executable only. Never linked into BorderMuse. Uses its exact entitlements.
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Expected the QA fixture directory") }
let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = fixture.appendingPathComponent("unselected.txt")
let output = fixture.appendingPathComponent("unselected-output.txt")
let containerFile = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-\(UUID().uuidString).txt")
var deniedRead = false
var deniedWrite = false
var containerWrite = false
do { _ = try Data(contentsOf: source) } catch { deniedRead = true }
do { try Data("QA only".utf8).write(to: output) } catch { deniedWrite = true }
do {
    try Data("Container access".utf8).write(to: containerFile)
    containerWrite = try Data(contentsOf: containerFile) == Data("Container access".utf8)
    try FileManager.default.removeItem(at: containerFile)
} catch { containerWrite = false }
let report: [String: Bool] = ["unselectedReadDenied": deniedRead,
                            "unselectedWriteDenied": deniedWrite,
                            "containerReadWriteAllowed": containerWrite]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(deniedRead && deniedWrite && containerWrite ? 0 : 1)
