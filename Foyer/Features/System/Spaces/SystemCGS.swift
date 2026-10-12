import AppKit

/// Private CoreGraphics Services (SkyLight) entry points, resolved at runtime
/// with `PrivateAPI.symbol` (Part A §4: `SpaceManager` uses CGSSpaceCreate,
/// CGSSpaceSetAbsoluteLevel, CGSShowSpaces, CGSHideSpaces, CGSSpaceDestroy,
/// CGSAddWindowsToSpaces, CGSRemoveWindowsFromSpaces, CGSCopyManagedDisplaySpaces,
/// CGSGetActiveSpace and CGSSpaceGetType).
enum SystemCGS {
    typealias ConnectionID = Int32
    typealias SpaceID = UInt64

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias SpaceGetTypeFn = @convention(c) (Int32, UInt64) -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias WindowsAndSpacesFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias SpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceDestroyFn = @convention(c) (Int32, UInt64) -> Void

    /// Resolves `CGSName` in SkyLight, then its `SLSName` alias, then any
    /// loaded image (CoreGraphics re-exports the CGS names).
    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        if let fn = PrivateAPI.symbol(name, in: PrivateAPI.skyLight, as: type) { return fn }
        if name.hasPrefix("CGS") {
            let alias = "SLS" + String(name.dropFirst(3))
            if let fn = PrivateAPI.symbol(alias, in: PrivateAPI.skyLight, as: type) { return fn }
        }
        if let fn = PrivateAPI.symbol(name, in: PrivateAPI.coreGraphics, as: type) { return fn }
        return PrivateAPI.symbol(name, in: nil, as: type)
    }

    private static let mainConnectionIDFn = resolve("CGSMainConnectionID", as: MainConnectionIDFn.self)
    private static let copyManagedDisplaySpacesFn = resolve("CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self)
    private static let getActiveSpaceFn = resolve("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let spaceGetTypeFn = resolve("CGSSpaceGetType", as: SpaceGetTypeFn.self)
    private static let spaceCreateFn = resolve("CGSSpaceCreate", as: SpaceCreateFn.self)
    private static let spaceSetAbsoluteLevelFn = resolve("CGSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevelFn.self)
    private static let addWindowsToSpacesFn = resolve("CGSAddWindowsToSpaces", as: WindowsAndSpacesFn.self)
    private static let removeWindowsFromSpacesFn = resolve("CGSRemoveWindowsFromSpaces", as: WindowsAndSpacesFn.self)
    private static let showSpacesFn = resolve("CGSShowSpaces", as: SpacesFn.self)
    private static let hideSpacesFn = resolve("CGSHideSpaces", as: SpacesFn.self)
    private static let spaceDestroyFn = resolve("CGSSpaceDestroy", as: SpaceDestroyFn.self)

    // MARK: Queries

    static func mainConnectionID() -> ConnectionID? {
        guard let fn = mainConnectionIDFn else { return nil }
        let cid = fn()
        return cid == 0 ? nil : cid
    }

    /// One dictionary per display: "Display Identifier" (UUID, or "Main" when
    /// displays share Spaces), "Current Space", "Spaces".
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let cid = mainConnectionID(), let fn = copyManagedDisplaySpacesFn,
              let array = fn(cid)?.takeRetainedValue() else { return [] }
        return (array as NSArray) as? [[String: Any]] ?? []
    }

    static func activeSpace() -> SpaceID? {
        guard let cid = mainConnectionID(), let fn = getActiveSpaceFn else { return nil }
        let space = fn(cid)
        return space == 0 ? nil : space
    }

    static func spaceType(_ space: SpaceID) -> Int? {
        guard let cid = mainConnectionID(), let fn = spaceGetTypeFn else { return nil }
        return Int(fn(cid, space))
    }

    /// Alcove tests bit 2 of the space type (user 0, system 2, fullscreen 4).
    static func isFullscreenType(_ type: Int) -> Bool {
        (type >> SystemConstants.Spaces.fullscreenTypeBit) & 1 == 1
    }

    // MARK: Space lifecycle

    static var supportsSpaceCreation: Bool {
        mainConnectionIDFn != nil && spaceCreateFn != nil && spaceSetAbsoluteLevelFn != nil
            && addWindowsToSpacesFn != nil && removeWindowsFromSpacesFn != nil
            && showSpacesFn != nil && hideSpacesFn != nil && spaceDestroyFn != nil
    }

    /// `CGSSpaceCreate(cid, 1, nil)` → `CGSSpaceSetAbsoluteLevel` → `CGSShowSpaces`.
    static func createSpace(level: Int32) -> (ConnectionID, SpaceID)? {
        guard supportsSpaceCreation, let cid = mainConnectionID(),
              let create = spaceCreateFn, let setLevel = spaceSetAbsoluteLevelFn, let show = showSpacesFn
        else { return nil }
        let space = create(cid, 1, nil)
        guard space != 0 else { return nil }
        _ = setLevel(cid, space, level)
        show(cid, spaceArray(space))
        return (cid, space)
    }

    static func add(windowIDs: [UInt32], to space: SpaceID, connection: ConnectionID) {
        guard !windowIDs.isEmpty, let fn = addWindowsToSpacesFn else { return }
        fn(connection, windowArray(windowIDs), spaceArray(space))
    }

    static func remove(windowIDs: [UInt32], from space: SpaceID, connection: ConnectionID) {
        guard !windowIDs.isEmpty, let fn = removeWindowsFromSpacesFn else { return }
        fn(connection, windowArray(windowIDs), spaceArray(space))
    }

    /// `CGSHideSpaces` + `CGSSpaceDestroy`.
    static func destroy(space: SpaceID, connection: ConnectionID) {
        hideSpacesFn?(connection, spaceArray(space))
        spaceDestroyFn?(connection, space)
    }

    private static func spaceArray(_ space: SpaceID) -> CFArray {
        [NSNumber(value: space)] as NSArray as CFArray
    }

    private static func windowArray(_ ids: [UInt32]) -> CFArray {
        ids.map { NSNumber(value: $0) } as NSArray as CFArray
    }
}

/// A private CGS space at an absolute level. Windows added to it are drawn at
/// that level on every display (used to keep the lock-screen widgets above
/// the login window, Part A §4 / Part E §4).
///
///     let space = SystemCGSSpace(level: 400)
///     space?.add(lockPanel)
///     ...
///     space?.destroy()
@MainActor
final class SystemCGSSpace {
    let spaceID: UInt64
    let level: Int32
    private let connection: Int32
    private var windowIDs: Set<UInt32> = []
    private(set) var isDestroyed = false

    init?(level: Int32) {
        guard let created = SystemCGS.createSpace(level: level) else { return nil }
        self.connection = created.0
        self.spaceID = created.1
        self.level = level
    }

    /// Moves `window` into this space. The window must have a window number
    /// (created with `defer: false`, or ordered in once).
    func add(_ window: NSWindow) {
        guard !isDestroyed, window.windowNumber > 0 else { return }
        let id = UInt32(window.windowNumber)
        SystemCGS.add(windowIDs: [id], to: spaceID, connection: connection)
        windowIDs.insert(id)
    }

    func remove(_ window: NSWindow) {
        guard !isDestroyed, window.windowNumber > 0 else { return }
        let id = UInt32(window.windowNumber)
        SystemCGS.remove(windowIDs: [id], from: spaceID, connection: connection)
        windowIDs.remove(id)
    }

    /// Removes every window still in the space, hides and destroys it.
    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        if !windowIDs.isEmpty {
            SystemCGS.remove(windowIDs: Array(windowIDs), from: spaceID, connection: connection)
            windowIDs.removeAll()
        }
        SystemCGS.destroy(space: spaceID, connection: connection)
    }
}
