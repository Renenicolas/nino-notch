import Foundation

/// Command-line checks for the module contract.
/// Compile: scripts/test-modules.sh
/// Run: scripts/test-modules.sh runs the linked binary, or
/// `NinoNotch.app --args --nino-module-self-test`
@main
@MainActor
struct NinoModuleTests {
    static func main() {
        let result = NinoModuleContract.run()
        for line in result.lines {
            print(line)
        }
        if result.failed == 0 {
            print("ALL TESTS PASSED")
            exit(0)
        } else {
            print("FAILED \(result.failed) check(s)")
            exit(1)
        }
    }
}
