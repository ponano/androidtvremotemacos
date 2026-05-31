import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

#if TESTING
let tester = KVMTests()
let success = tester.runAllTests()
exit(success ? 0 : 1)
#else
setbuf(stdout, nil)
setbuf(stderr, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
