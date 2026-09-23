import Foundation

/// In-process checks. Launch the built app with --nino-module-self-test and
/// it writes a receipt to /tmp then exits.
enum NinoModuleSelfTest {
    static let receiptPath = "/tmp/nino-module-selftest.txt"

    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--nino-module-self-test") else { return }

        let result = NinoModuleContract.run()
        let status = result.failed == 0 ? "ALL TESTS PASSED" : "FAILED \(result.failed) check(s)"
        var lines = result.lines
        lines.append(status)
        let body = lines.joined(separator: "\n") + "\n"

        fputs(body, stdout)
        fflush(stdout)

        do {
            try body.write(toFile: receiptPath, atomically: true, encoding: .utf8)
        } catch {
            fputs("FAIL  could not write receipt \(receiptPath): \(error)\n", stderr)
            exit(1)
        }

        exit(result.failed == 0 ? 0 : 1)
    }
}
