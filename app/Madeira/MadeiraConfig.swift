import Foundation

/// ml1095: ONE configuration file for every runtime switch: Documents/madeira.cfg
///
///     # comments start with #
///     key = value        (whitespace trimmed; the value runs to the end of the
///                         line, so it may contain '='; the last line wins)
///
/// Keys are the old per-file names without "madeira-" and ".txt"
/// (swap-mb, vram-mb, pool, totalphys, wx, ...). Environment exports are
/// "env.NAME = value". DXMT options are one line, "dxmt = a=b;c=d".
///
/// The native side reads the same file through build/madeira_cfg.h with the
/// same rules. When madeira.cfg is ABSENT the legacy one-value-per-file layout
/// still works; when it is PRESENT the legacy files are ignored, so the one
/// file is the single source of truth. `migrateLegacy()` writes madeira.cfg
/// from whatever legacy files exist, once, so they can then be deleted.
enum MadeiraConfig {
    static let fileName = "madeira.cfg"

    /// Every switch that used to live in its own Documents/madeira-<key>.txt.
    static let legacyKeys = [
        "swap-mb", "swap-canary", "vram-mb", "pool", "totalphys", "inproc-sync", "wx",
        "mono-bridge", "ctx-frame", "tf-trace", "usd-time", "real-suspend", "mono-suspend",
        "arena", "arena-mb", "arena-test", "fexfail", "remote", "remote-batch", "d3d12",
        "apicensus", "shadow", "census", "wxprobe", "args", "valley-args",
        "jumbo-mb", "jumbo-keep-mb", "iat-noexec", "vmwatch", "no-local-read", "vsps-fill",
    ]

    static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    static var url: URL? { documents?.appendingPathComponent(fileName) }
    static var present: Bool { url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    /// All key/value pairs of madeira.cfg (empty when the file is absent).
    static func all() -> [String: String] {
        guard let u = url, let text = try? String(contentsOf: u, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// The key/value pairs of text in madeira.cfg's syntax, the last line winning.
    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces)
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { out[k] = v }
        }
        return out
    }

    /// The value for `key`, trimmed, or nil when unset. Falls back to the legacy
    /// file ONLY when madeira.cfg does not exist.
    static func get(_ key: String) -> String? {
        if present { return all()[key] }
        guard let d = documents,
              let txt = try? String(contentsOf: d.appendingPathComponent("madeira-\(key).txt"), encoding: .utf8)
        else { return nil }
        return txt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A library game's own lines (Game details › This game's config): written to
    /// Application Support for each launch and named by MADEIRA_CFG_GAME, which
    /// build/madeira_cfg.h reads after madeira.cfg so a key there wins, and whose
    /// env.NAME lines WineProcessBridge.m exports after madeira.cfg's.
    static var gameURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("madeira-game.cfg")
    }

    /// `key` from the running game's own lines, or nil (also when empty). The
    /// native reader lets it win on its own; Swift readers that merge (dxmt) ask.
    static func gameValue(_ key: String) -> String? {
        guard let p = getenv("MADEIRA_CFG_GAME"), case let path = String(cString: p), !path.isEmpty,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parse(text)[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Makes `text` the running game's lines: written and exported as
    /// MADEIRA_CFG_GAME when it sets anything, otherwise the variable is unset
    /// and the file removed, so a previous game's lines never apply. Returns the
    /// pairs it applied; throws (with the variable unset) when the file cannot
    /// be written.
    @discardableResult
    static func applyGame(_ text: String?) throws -> [String: String] {
        unsetenv("MADEIRA_CFG_GAME")
        let pairs = parse(text ?? "")
        guard let u = gameURL else { return [:] }
        guard !pairs.isEmpty, let text else {
            try? FileManager.default.removeItem(at: u)
            return [:]
        }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.hasSuffix("\n") ? text : text + "\n").write(to: u, atomically: true, encoding: .utf8)
        setenv("MADEIRA_CFG_GAME", u.path, 1)
        return pairs
    }

    static func bool(_ key: String, default dflt: Bool = false) -> Bool {
        guard let v = get(key) else { return dflt }
        return ["1", "on", "true", "yes"].contains(v)
    }

    /// Set or remove one key in madeira.cfg (Settings). Comments and every
    /// other line are kept; earlier lines for the key are dropped and the new
    /// value is appended; a nil value removes the key. Without madeira.cfg the
    /// legacy files are migrated first, so writing one key never hides the
    /// switches that still live in madeira-*.txt files.
    @discardableResult
    static func set(_ key: String, _ value: String?) -> Bool {
        guard let u = url else { return false }
        if !present { migrateLegacy(log: { _ in }) }
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return false }
            return t[..<eq].trimmingCharacters(in: .whitespaces) == key
        }
        if let value { lines.append("\(key) = \(value)") }
        let out = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        do { try out.write(to: u, atomically: true, encoding: .utf8); return true } catch { return false }
    }

    /// An app-side switch spelled like the native ones: `env.NAME = value` in
    /// madeira.cfg, else the process environment, else `fallback`. Any value
    /// other than "0" means on.
    static func flag(_ name: String, fallback: Bool = true) -> Bool {
        if present, let v = all()["env." + name] { return v != "0" }
        return getenv(name).map { String(cString: $0) != "0" } ?? fallback
    }

    /// Winvoy: starting settings sized to this device, written once (marked by
    /// `device-profile`). Only keys the file does not already have are added, so
    /// anything the user set wins. 8 GB+ devices get the settings God of War ran
    /// with on an iPhone 15 Pro; smaller ones those X-Men Origins: Wolverine ran with
    /// on an iPad Air 4. The two address-space switches are only for maps that end
    /// below 0x7200000000 (454 GB on an iPad Air 4).
    static func applyDeviceProfile(log: (String) -> Void) {
        guard url != nil, get("device-profile") == nil else { return }
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / Double(1 << 30)
        var vmi = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmi) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let smallMap = kr == KERN_SUCCESS && vmi.max_address > 0x7100000000 && vmi.max_address < 0x7200000000
        let large = ramGB >= 7
        var keys: [(String, String)] = [
            ("pool", large ? "640" : "768"),
            ("vram-mb", "1024"),
            ("dxmt", "dxgi.forceSDR=True;d3d11.preferredMaxFrameRate=30"),
            ("env.DXMT_IOS_CACHE_DIR", "1"),
            ("swap-mb", large ? "6144" : "4096"),
            ("env.MADEIRA_SWAP_COVERAGE", "broad"),
            ("env.MADEIRA_SWAP_MIN_KB", "64"),
        ]
        if large {
            keys += [("swap-advise", "1"), ("totalphys", "4096"), ("vram-trim-mb", "1024")]
        }
        if smallMap {
            keys += [("env.MADEIRA_WOW_MIN_FREE_GB", "1"), ("env.FEX_DISABLEL2CACHE", "1")]
        }
        let have = all()
        let added = keys.filter { have[$0.0] == nil }
        for (k, v) in added { set(k, v) }
        let name = (large ? "8gb" : "small") + (smallMap ? "-smallmap" : "")
        set("device-profile", name)
        log(String(format: "madeira.cfg: device profile %@ (%.1f GB RAM, map ends at 0x%llx) added %@", name, ramGB,
                   UInt64(vmi.max_address), added.isEmpty ? "nothing" : added.map { $0.0 }.joined(separator: ", ")))
    }

    /// One-time migration: with no madeira.cfg and at least one legacy file,
    /// write madeira.cfg from them. Legacy files are left in place (ignored from
    /// now on) so nothing is destroyed; the log names them so they can be deleted.
    /// Returns the keys that were migrated.
    @discardableResult
    static func migrateLegacy(log: (String) -> Void) -> [String] {
        guard let d = documents, let u = url, !present else { return [] }
        var lines = ["# Madeira configuration (ml1095): one file for every switch.",
                     "# key = value; lines starting with # are comments; the last line wins.",
                     "# Keys are the old file names without 'madeira-' and '.txt'.",
                     "# Environment exports: env.NAME = value. DXMT options: dxmt = a=b;c=d.",
                     ""]
        var migrated: [String] = []
        for key in legacyKeys {
            guard let txt = try? String(contentsOf: d.appendingPathComponent("madeira-\(key).txt"), encoding: .utf8) else { continue }
            let v = txt.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(key) = \(v)")
            migrated.append(key)
        }
        if let txt = try? String(contentsOf: d.appendingPathComponent("madeira-dxmt.txt"), encoding: .utf8) {
            let parts = txt.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            if !parts.isEmpty { lines.append("dxmt = " + parts.joined(separator: ";")); migrated.append("dxmt") }
        }
        if let txt = try? String(contentsOf: d.appendingPathComponent("madeira-env.txt"), encoding: .utf8) {
            for raw in txt.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
                lines.append("env.\(line[..<eq]) = \(line[line.index(after: eq)...])")
            }
            migrated.append("env")
        }
        guard !migrated.isEmpty else { return [] }
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
            log("madeira.cfg written from legacy files (\(migrated.joined(separator: ", "))); the madeira-*.txt files are now ignored and can be deleted")
        } catch {
            log("madeira.cfg could not be written: \(error)")
            return []
        }
        return migrated
    }

    /// Once madeira.cfg exists the legacy files are dead weight: remove every
    /// known switch file (never logs, traces or the input map). Idempotent.
    /// Returns the names removed.
    @discardableResult
    static func deleteLegacyFiles(log: (String) -> Void) -> [String] {
        guard present, let d = documents else { return [] }
        var removed: [String] = []
        for name in legacyKeys.map({ "madeira-\($0).txt" }) + ["madeira-env.txt", "madeira-dxmt.txt"] {
            let u = d.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: u.path) else { continue }
            do { try FileManager.default.removeItem(at: u); removed.append(name) }
            catch { log("could not remove \(name): \(error)") }
        }
        if !removed.isEmpty { log("removed legacy config files (madeira.cfg is the one file now): " + removed.joined(separator: ", ")) }
        return removed
    }
}
