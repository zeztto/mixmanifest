import Foundation
import MixManifestCore

private enum CheckError: Error { case failed(String) }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckError.failed(message) }
}
private func rejects(_ message: String = "Expected malformed or unsafe input to be rejected", _ action: () throws -> Void) throws {
    do { try action() } catch { return }
    throw CheckError.failed(message)
}
private let fm = FileManager.default
private func temporary(_ body: (URL) throws -> Void) throws {
    let root = fm.temporaryDirectory.appendingPathComponent("MixManifestChecks-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try body(root)
}
private func plist(_ value: [String: Any], to url: URL) throws {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
}

@main struct CoreChecks {
    static func main() {
        var passed = 0
        var failures = 0
        func run(_ name: String, _ body: () throws -> Void) {
            do { try body(); passed += 1; print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        run("missing and wrong project paths") {
            try temporary { root in
                try rejects { _ = try LogicProjectReader.read(root.appendingPathComponent("missing.logicx")) }
                try rejects { _ = try LogicProjectReader.read(root) }
                let file = root.appendingPathComponent("file.logicx")
                try Data("not a package".utf8).write(to: file)
                try rejects { _ = try LogicProjectReader.read(file) }
                let empty = root.appendingPathComponent("empty.logicx")
                try fm.createDirectory(at: empty, withIntermediateDirectories: true)
                try rejects { _ = try LogicProjectReader.read(empty) }
            }
        }
        run("corrupt and truncated ProjectData") {
            try temporary { root in
                let project = root.appendingPathComponent("broken.logicx")
                let alternative = project.appendingPathComponent("Alternatives/000")
                try fm.createDirectory(at: alternative, withIntermediateDirectories: true)
                try plist(["SampleRate": 48000, "NumberOfTracks": 1, "Tempo": 120], to: alternative.appendingPathComponent("MetaData.plist"))
                var truncatedHeader = Data(repeating: 0, count: 32)
                truncatedHeader.replaceSubrange(0..<4, with: [0x23, 0x47, 0xc0, 0xab])
                truncatedHeader[16] = 8
                var truncatedPayload = Data(repeating: 0, count: 60)
                truncatedPayload.replaceSubrange(0..<4, with: [0x23, 0x47, 0xc0, 0xab])
                truncatedPayload[16] = 36
                truncatedPayload[52] = 200
                for bytes in [Data(), Data("garbage".utf8), Data(repeating: 0, count: 128), truncatedHeader, truncatedPayload] {
                    try bytes.write(to: alternative.appendingPathComponent("ProjectData"))
                    let result = try LogicProjectReader.read(project)
                    try require(result.tracks.isEmpty, "Corrupt data must not yield invented tracks")
                    try require(result.diagnostics.contains { $0.contains("해석 실패") }, "Corrupt data needs explicit diagnostic")
                    try require(result.metadata.contains { $0.value == "48000" }, "Available metadata should survive parse failure")
                }
                try rejects { _ = try LogicProjectReader.read(project, alternativeID: "../000") }
                try rejects { _ = try LogicProjectReader.read(project, alternativeID: "missing") }
            }
        }
        run("ProjectData symlink cannot escape package") {
            try temporary { root in
                let project = root.appendingPathComponent("linked.logicx")
                let alternative = project.appendingPathComponent("Alternatives/000")
                try fm.createDirectory(at: alternative, withIntermediateDirectories: true)
                let outside = root.appendingPathComponent("outside")
                try Data("outside-project".utf8).write(to: outside)
                try fm.createSymbolicLink(at: alternative.appendingPathComponent("ProjectData"), withDestinationURL: outside)
                try rejects { _ = try LogicProjectReader.read(project) }
                let after = try Data(contentsOf: outside)
                try require(after == Data("outside-project".utf8), "Outside file changed")
            }
        }
        run("bounded track records and unsupported format versions") {
            try temporary { root in
                let project = root.appendingPathComponent("records.logicx")
                let alt = project.appendingPathComponent("Alternatives/000")
                try fm.createDirectory(at: alt, withIntermediateDirectories: true)
                try plist(["NumberOfTracks": 1], to: alt.appendingPathComponent("MetaData.plist"))
                func chunk(_ tag: String, version: UInt8, owner: UInt8 = 0, body: Data) -> Data {
                    var header = Data(repeating: 0, count: 36)
                    header.replaceSubrange(0..<4, with: tag.utf8)
                    header[4] = version
                    header[14] = owner
                    if tag == "karT" { header[10] = 4 }
                    if tag == "OCuA" { header[18] = 255; header[19] = 255 }
                    for i in 0..<4 { header[28 + i] = UInt8((body.count >> (i * 8)) & 255) }
                    return header + body
                }
                func bytes(version: UInt8) -> Data {
                    var chunks = Data()
                    for (id, name) in [(1, "Test Track"), (2, "Output")] {
                        var object = Data(repeating: 0, count: 200)
                        object[0] = 8; object[1] = 7; object[16] = UInt8(id)
                        object[184] = UInt8(id)
                        object[158] = UInt8(name.utf8.count)
                        object.replaceSubrange(160..<160 + name.utf8.count, with: name.utf8)
                        chunks += chunk("ivnE", version: version, body: object)
                    }
                    for id in [1, 2] {
                        var row = Data(repeating: 0, count: 58)
                        row[8] = UInt8(id); row[51] = 7
                        chunks += chunk("karT", version: 6, body: row)
                    }
                    var channel = Data(repeating: 0, count: 240)
                    channel[192] = 1
                    channel[89] = 24
                    chunks += chunk("OCuA", version: 7, owner: 9, body: channel)
                    // Synthetic descriptors exercise the distinct native and AU layouts.
                    let descriptors: [(UInt8, UInt8, String, Bool)] = [
                        (1, 0, "Test AU", false),
                        (1, 1, "Second AU", false),
                        (1, 2, "Test Native", true),
                        (2, 0, "Test MIDI", true)
                    ]
                    for (chain, slot, name, native) in descriptors {
                        var plugin = Data(repeating: 0, count: 160)
                        plugin[4] = chain; plugin[6] = slot
                        plugin.replaceSubrange(120..<120 + name.utf8.count, with: name.utf8)
                        if native {
                            plugin.replaceSubrange(132..<136, with: "GAME".utf8)
                            plugin[140] = chain
                        } else {
                            for (offset, value) in [(132, "TEST"), (136, "aufx"), (140, "fx01")] {
                                plugin.replaceSubrange(offset..<offset + 4, with: value.utf8.reversed())
                            }
                        }
                        chunks += chunk("UCuA", version: 5, owner: 9, body: plugin)
                    }
                    var header = Data(repeating: 0, count: 24)
                    header.replaceSubrange(0..<4, with: [0x23, 0x47, 0xc0, 0xab])
                    for i in 0..<4 { header[16 + i] = UInt8((chunks.count >> (i * 8)) & 255) }
                    return header + chunks
                }
                try bytes(version: 12).write(to: alt.appendingPathComponent("ProjectData"))
                let manifest = try LogicProjectReader.read(project)
                let afterRead = try Data(contentsOf: alt.appendingPathComponent("ProjectData"))
                try require(afterRead == bytes(version: 12), "Read-only extraction changed package bytes")
                try require(manifest.tracks.map(\.name) == ["Test Track", "Output"], "Framed records lost names/order")
                let linked = manifest.tracks[0]
                try require(Set(linked.plugins.map(\.name)) == Set(["Test AU", "Second AU", "Test Native", "Test MIDI"]), "Native or Audio Unit plugins silently lost")
                try require(linked.plugins.first { $0.name == "Test MIDI" }?.details.contains("MIDI slot 0") == true, "MIDI FX chain lost")
                try require(linked.plugins.first { $0.name == "Test Native" }?.slot == 2, "Native effect slot lost")
                try require(linked.fields.contains { $0.label == "Pan" && $0.value == "-40 (raw: 24)" }, "Signed Pan decoding changed")
                try require(manifest.tracks[1].fields.contains { $0.value == "UUID 연결 미확인" }, "Unbound mixer must remain unconfirmed")
                try bytes(version: 99).write(to: alt.appendingPathComponent("ProjectData"))
                let unsupported = try LogicProjectReader.read(project)
                try require(unsupported.tracks.isEmpty && unsupported.diagnostics.contains { $0.contains("해석 실패") }, "Unsupported version must not be decoded as supported")
            }
        }
        run("alternative selection and metadata provenance") {
            try temporary { root in
                let project = root.appendingPathComponent("alternatives.logicx")
                let resources = project.appendingPathComponent("Resources")
                try fm.createDirectory(at: resources, withIntermediateDirectories: true)
                try plist(["VariantNames": ["0": "첫 번째", "1": "두 번째"]], to: resources.appendingPathComponent("ProjectInformation.plist"))
                for (id, bpm) in [("000", 120), ("001", 87)] {
                    let alt = project.appendingPathComponent("Alternatives/" + id)
                    try fm.createDirectory(at: alt, withIntermediateDirectories: true)
                    try plist(["BeatsPerMinute": bpm, "SampleRate": 48000], to: alt.appendingPathComponent("MetaData.plist"))
                    try Data("unsupported fixture format".utf8).write(to: alt.appendingPathComponent("ProjectData"))
                }
                let initial = try LogicProjectReader.read(project)
                let selected = try LogicProjectReader.read(project, alternativeID: "001")
                try require(initial.alternativeID == "000", "Default selection is nondeterministic")
                try require(initial.alternatives.map(\.name) == ["첫 번째", "두 번째"], "Alternative names lost")
                try require(selected.alternativeID == "001", "Explicit alternative ignored")
                try require(selected.metadata.contains { $0.value == "87" && $0.source == "Alternatives/001/MetaData.plist#BeatsPerMinute" }, "Selected alternative metadata or provenance wrong")
                let encoded = try ManifestIO.encodeJSON(selected)
                let decoded = try ManifestIO.decodeJSON(encoded)
                try require(decoded.tracks == selected.tracks && decoded.metadata == selected.metadata && decoded.alternatives == selected.alternatives && decoded.diagnostics == selected.diagnostics, "Manifest roundtrip lost data")
                var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                object["schemaVersion"] = 1
                try rejects { _ = try ManifestIO.decodeJSON(JSONSerialization.data(withJSONObject: object)) }
            }
        }
        run("malformed imported JSON") {
            try rejects { _ = try ManifestIO.decodeJSON(Data("{}".utf8)) }
            try rejects { _ = try ManifestIO.decodeJSON(Data("not json".utf8)) }
            try rejects { _ = try ManifestIO.decodeJSON(Data(repeating: 32, count: 32 * 1024 * 1024 + 1)) }
        }
        run("JSON export stays inside its import size contract") {
            let manifest = fixtureManifest(diagnostics: Array(repeating: String(repeating: "x", count: 32768), count: 1024))
            try rejects { _ = try ManifestIO.encodeJSON(manifest) }
        }
        run("manifest schema and identifier boundaries") {
            var manifest = fixtureManifest()
            _ = try ManifestIO.decodeJSON(ManifestIO.encodeJSON(manifest))
            manifest.schemaVersion = 3
            try rejects { _ = try ManifestIO.encodeJSON(manifest) }
            manifest = fixtureManifest()
            manifest.projectName = "bad\u{0000}name"
            try rejects { _ = try ManifestIO.encodeJSON(manifest) }
            manifest = fixtureManifest()
            manifest.alternatives.append(manifest.alternatives[0])
            try rejects { _ = try ManifestIO.encodeJSON(manifest) }
            manifest = fixtureManifest()
            manifest.projectDataSHA256 = "not-a-hash"
            try rejects { _ = try ManifestIO.encodeJSON(manifest) }
        }
        run("oversized project files are rejected before reading") {
            try temporary { root in
                let project = root.appendingPathComponent("oversized.logicx")
                let alt = project.appendingPathComponent("Alternatives/000")
                try fm.createDirectory(at: alt, withIntermediateDirectories: true)
                let dataURL = alt.appendingPathComponent("ProjectData")
                try Data().write(to: dataURL)
                let handle = try FileHandle(forWritingTo: dataURL)
                try handle.truncate(atOffset: 256 * 1024 * 1024 + 1)
                try handle.close()
                try rejects { _ = try LogicProjectReader.read(project) }
            }
        }
        run("export destinations protect original and other project packages") {
            try temporary { root in
                let project = root.appendingPathComponent("source.logicx")
                let other = root.appendingPathComponent("other.LOGICX")
                try fm.createDirectory(at: project, withIntermediateDirectories: true)
                try fm.createDirectory(at: other, withIntermediateDirectories: true)
                let sentinel = project.appendingPathComponent("original.json")
                try Data("original".utf8).write(to: sentinel)
                try rejects("Direct source package export accepted") { try ManifestIO.validateExportDestination(sentinel, projectPath: project.path) }
                try rejects("Other project package export accepted") { try ManifestIO.validateExportDestination(other.appendingPathComponent("export.json"), projectPath: project.path) }
                let alias = root.appendingPathComponent("alias")
                try fm.createSymbolicLink(at: alias, withDestinationURL: project)
                try rejects("Symlink into project export accepted") { try ManifestIO.validateExportDestination(alias.appendingPathComponent("export.json"), projectPath: project.path) }
                let dangling = root.appendingPathComponent("dangling.json")
                try fm.createSymbolicLink(at: dangling, withDestinationURL: project.appendingPathComponent("missing.json"))
                try rejects("Dangling symlink export accepted") { try ManifestIO.validateExportDestination(dangling, projectPath: project.path) }
                let lexicalAlias = root.appendingPathComponent("alias.logicx")
                let safeFolder = root.appendingPathComponent("exports")
                try fm.createDirectory(at: safeFolder, withIntermediateDirectories: true)
                try fm.createSymbolicLink(at: lexicalAlias, withDestinationURL: safeFolder)
                try rejects("Lexical project path export accepted") { try ManifestIO.validateExportDestination(lexicalAlias.appendingPathComponent("export.json"), projectPath: project.path) }
                try ManifestIO.validateExportDestination(safeFolder.appendingPathComponent("manifest.json"), projectPath: project.path)
                try ManifestIO.validateExportDestination(root.appendingPathComponent("source.logicx-backup/manifest.json"), projectPath: project.path)
                let after = try Data(contentsOf: sentinel)
                try require(after == Data("original".utf8), "Export validation changed original bytes")
            }
        }
        run("metadata and package symlinks cannot escape input root") {
            try temporary { root in
                let project = root.appendingPathComponent("source.logicx")
                let alt = project.appendingPathComponent("Alternatives/000")
                try fm.createDirectory(at: alt, withIntermediateDirectories: true)
                try Data("unsupported".utf8).write(to: alt.appendingPathComponent("ProjectData"))
                let outside = root.appendingPathComponent("outside.plist")
                try plist(["SampleRate": 48000], to: outside)
                try fm.createSymbolicLink(at: alt.appendingPathComponent("MetaData.plist"), withDestinationURL: outside)
                try rejects { _ = try LogicProjectReader.read(project) }
                let linkedRoot = root.appendingPathComponent("linked.logicx")
                try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: project)
                try rejects { _ = try LogicProjectReader.read(linkedRoot) }
            }
        }
        run("oversized metadata plist is rejected") {
            try temporary { root in
                let project = root.appendingPathComponent("metadata.logicx")
                let resources = project.appendingPathComponent("Resources")
                try fm.createDirectory(at: resources, withIntermediateDirectories: true)
                let url = resources.appendingPathComponent("ProjectInformation.plist")
                try Data().write(to: url)
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 8 * 1024 * 1024 + 1)
                try handle.close()
                try rejects { _ = try LogicProjectReader.read(project) }
            }
        }
        print("CoreChecks: \(passed) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    private static func fixtureManifest(diagnostics: [String] = []) -> ProjectManifest {
        .init(capturedAt: Date(timeIntervalSince1970: 1), projectName: "Synthetic Project",
              projectPath: "Synthetic.logicx", alternativeID: "000",
              alternatives: [.init(id: "000", name: "Synthetic")],
              projectDataSHA256: String(repeating: "0", count: 64),
              metadata: [], tracks: [], diagnostics: diagnostics)
    }
}
