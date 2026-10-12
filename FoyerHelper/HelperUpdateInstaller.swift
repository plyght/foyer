import Foundation

/// Installs a downloaded update: unzips it with /usr/bin/ditto, swaps the
/// `.app` in place and relaunches it once the running app has quit (teardown
/// §1 / Part G §11: the XPC helper's `installUpdateWithZipPath:appBundlePath:reply:`).
enum HelperUpdateInstaller {
    private static let queue = DispatchQueue(label: "com.apple.controlcenter.FoyerHelper.update", qos: .userInitiated)

    static func install(zipPath: String, appBundlePath: String, appPID: pid_t,
                        reply: @escaping (Bool, String?) -> Void) {
        queue.async {
            do {
                try performInstall(zipPath: zipPath, appBundlePath: appBundlePath)
                reply(true, nil)
                scheduleRelaunch(appBundlePath: appBundlePath, appPID: appPID)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    private struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func performInstall(zipPath: String, appBundlePath: String) throws {
        let fileManager = FileManager.default
        let zipURL = URL(fileURLWithPath: zipPath)
        let appURL = URL(fileURLWithPath: appBundlePath).standardizedFileURL

        guard fileManager.fileExists(atPath: zipURL.path) else {
            throw InstallError(message: "The update archive does not exist at \(zipPath).")
        }
        guard appURL.pathExtension == "app" else {
            throw InstallError(message: "\(appBundlePath) is not an application bundle.")
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InstallError(message: "The application to update does not exist at \(appBundlePath).")
        }

        // Stage on the same volume so the final swap is an atomic rename.
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: appURL, create: true)
        defer { try? fileManager.removeItem(at: staging) }

        let unzip = run("/usr/bin/ditto", ["-x", "-k", zipURL.path, staging.path])
        guard unzip.status == 0 else {
            throw InstallError(message: "ditto failed to unpack the update (\(unzip.status)): \(unzip.output)")
        }

        guard let newAppURL = findApp(in: staging) else {
            throw InstallError(message: "The update archive does not contain an application.")
        }

        // Refuse an archive that carries a different app.
        let oldID = Bundle(url: appURL)?.bundleIdentifier
        let newID = Bundle(url: newAppURL)?.bundleIdentifier
        if let oldID, let newID, oldID != newID {
            throw InstallError(message: "The update is for \(newID), not \(oldID).")
        }

        // Downloaded archives carry quarantine; the unpacked app must not.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newAppURL.path])

        do {
            _ = try fileManager.replaceItemAt(appURL, withItemAt: newAppURL, backupItemName: nil, options: [])
        } catch {
            // Fall back to copying the new bundle over the old one with ditto.
            let backup = staging.appendingPathComponent("previous-\(UUID().uuidString).app")
            try fileManager.moveItem(at: appURL, to: backup)
            let copy = run("/usr/bin/ditto", [newAppURL.path, appURL.path])
            guard copy.status == 0 else {
                try? fileManager.removeItem(at: appURL)
                try? fileManager.moveItem(at: backup, to: appURL)
                throw InstallError(message: "ditto failed to install the update (\(copy.status)): \(copy.output)")
            }
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        // One level of nesting (e.g. a folder inside the zip).
        for item in items where item.lastPathComponent != "__MACOSX" {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let nested = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) else {
                continue
            }
            if let app = nested.first(where: { $0.pathExtension == "app" }) { return app }
        }
        return nil
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    /// The helper dies with the app, so the relaunch runs in a detached shell
    /// (its own session) that waits for the app to quit, asks it to quit after
    /// 10 s if it is still running, then opens the new bundle.
    private static func scheduleRelaunch(appBundlePath: String, appPID: pid_t) {
        let script = """
        pid="$1"; app="$2"; i=0
        if [ "$pid" -gt 0 ] 2>/dev/null; then
          while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
          if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null; i=0
            while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
          fi
        else
          sleep 1
        fi
        /usr/bin/open "$app"
        """
        let arguments = ["/bin/sh", "-c", script, "foyer-relaunch", String(appPID), appBundlePath]
        let environment = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        envp.append(nil)
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }

        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // POSIX_SPAWN_SETSID: start a new session so launchd's teardown of the
        // helper does not take the relauncher with it.
        posix_spawnattr_setflags(&attributes, Int16(0x0400))

        var pid: pid_t = 0
        let status = posix_spawn(&pid, "/bin/sh", nil, &attributes, argv, envp)
        if status != 0 {
            // Last resort: relaunch right away through Process.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [appBundlePath]
            try? process.run()
        }
    }
}
