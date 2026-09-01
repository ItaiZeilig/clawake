import Foundation
import ClawakeShared

// The privileged (root) daemon. Installed via SMAppService, reachable only over
// XPC. Bootstrap only: the connection gate lives in HelperService, the privileged
// work in SleepManager.
let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.main.run()
