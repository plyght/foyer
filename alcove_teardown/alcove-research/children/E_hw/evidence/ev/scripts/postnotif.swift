// usage: postnotif <name> ; posts a DistributedNotificationCenter notification
import Foundation
let name = CommandLine.arguments[1]
DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
print("posted \(name)")
