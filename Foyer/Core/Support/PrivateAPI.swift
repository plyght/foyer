import Foundation

/// Runtime loader for private frameworks. Foyer resolves every private symbol
/// with dlopen/dlsym so the app links only public SDK frameworks and degrades
/// gracefully when a symbol disappears in a future macOS.
enum PrivateAPI {
    static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    static let mediaRemote = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    static let coreBrightness = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
    static let login = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    static let tcc = "/System/Library/PrivateFrameworks/TCC.framework/TCC"
    static let mediaPlaybackCore = "/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore"
    static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    private static var handles: [String: UnsafeMutableRawPointer] = [:]
    private static let lock = NSLock()

    static func handle(_ path: String) -> UnsafeMutableRawPointer? {
        lock.lock(); defer { lock.unlock() }
        if let h = handles[path] { return h }
        guard let h = dlopen(path, RTLD_NOW) else { return nil }
        handles[path] = h
        return h
    }

    /// Resolves `name` in `path` (or in any already-loaded image when `path`
    /// is nil) and casts it to the C function type `T`.
    static func symbol<T>(_ name: String, in path: String? = nil, as type: T.Type = T.self) -> T? {
        let h: UnsafeMutableRawPointer?
        if let path {
            h = handle(path)
        } else {
            h = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        }
        guard let h, let sym = dlsym(h, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
