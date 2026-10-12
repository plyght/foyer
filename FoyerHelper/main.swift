import Foundation

// Entry point of FoyerHelper.xpc. The Now Playing feature provides
// `FoyerHelperService` (the exported object) and `HelperListenerDelegate`.
let delegate = HelperListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
