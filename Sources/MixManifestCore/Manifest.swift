import Foundation

public struct ManifestField: Codable, Equatable {
    public var label: String; public var value: String; public var source: String
    public init(label: String, value: String, source: String) { self.label = label; self.value = value; self.source = source }
}
public struct ManifestPlugin: Codable, Equatable, Identifiable {
    public var id: String; public var slot: Int?; public var name: String; public var details: String
    public init(id: String, slot: Int?, name: String, details: String) { self.id = id; self.slot = slot; self.name = name; self.details = details }
}
public struct ManifestTrack: Codable, Equatable, Identifiable {
    public var id: String; public var index: Int; public var name: String; public var kind: String
    public var fields: [ManifestField]; public var plugins: [ManifestPlugin]
    public init(id: String, index: Int, name: String, kind: String, fields: [ManifestField], plugins: [ManifestPlugin]) { self.id = id; self.index = index; self.name = name; self.kind = kind; self.fields = fields; self.plugins = plugins }
}
public struct ProjectAlternative: Codable, Equatable, Identifiable {
    public var id: String; public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct ProjectManifest: Codable, Equatable {
    public var schemaVersion: Int; public var capturedAt: Date; public var projectName: String; public var projectPath: String
    public var alternativeID: String; public var alternatives: [ProjectAlternative]; public var projectDataSHA256: String
    public var metadata: [ManifestField]; public var tracks: [ManifestTrack]; public var diagnostics: [String]
    public init(schemaVersion: Int = 2, capturedAt: Date, projectName: String, projectPath: String, alternativeID: String, alternatives: [ProjectAlternative], projectDataSHA256: String, metadata: [ManifestField], tracks: [ManifestTrack], diagnostics: [String]) {
        self.schemaVersion = schemaVersion; self.capturedAt = capturedAt; self.projectName = projectName; self.projectPath = projectPath; self.alternativeID = alternativeID; self.alternatives = alternatives; self.projectDataSHA256 = projectDataSHA256; self.metadata = metadata; self.tracks = tracks; self.diagnostics = diagnostics
    }
}
public enum ManifestIO {
    public static let maximumJSONBytes = 32 * 1024 * 1024
    public static func encodeJSON(_ manifest: ProjectManifest) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .deferredToDate; try validate(manifest)
        let data = try e.encode(manifest)
        guard data.count <= maximumJSONBytes else { throw LogicReadError.invalid("JSON 파일은 최대 32 MiB까지 저장할 수 있습니다.") }
        return data
    }
    public static func decodeJSON(_ data: Data) throws -> ProjectManifest { guard data.count <= maximumJSONBytes else { throw LogicReadError.invalid("JSON 파일이 너무 큽니다.") }; let d = JSONDecoder(); d.dateDecodingStrategy = .deferredToDate; let m = try d.decode(ProjectManifest.self, from: data); try validate(m); return m }
    private static func validate(_ m: ProjectManifest) throws {
        func require(_ condition: Bool) throws { guard condition else { throw LogicReadError.invalid("manifest 데이터의 schema·식별자·크기 제한을 확인하세요.") } }
        func string(_ s: String) -> Bool { s.utf8.count <= 65536 && !s.contains("\u{0000}") }
        func unique(_ ids: [String]) -> Bool { ids.allSatisfy { !$0.isEmpty && string($0) } && Set(ids).count == ids.count }
        func fields(_ values: [ManifestField]) -> Bool { values.count <= 1024 && values.allSatisfy { string($0.label) && string($0.value) && string($0.source) } }
        try require(m.schemaVersion == 2 && m.capturedAt.timeIntervalSince1970.isFinite && abs(m.capturedAt.timeIntervalSince1970) < 1e12)
        try require(string(m.projectName) && string(m.projectPath) && !m.projectName.isEmpty)
        try require(m.projectDataSHA256.count == 64 && m.projectDataSHA256.allSatisfy { $0.isHexDigit && $0.isASCII })
        try require(m.alternatives.count > 0 && m.alternatives.count <= 1024 && unique(m.alternatives.map(\.id)))
        try require(m.alternatives.contains { $0.id == m.alternativeID } && m.alternatives.allSatisfy { string($0.name) })
        try require(m.tracks.count <= 100000 && unique(m.tracks.map(\.id)) && fields(m.metadata))
        try require(m.diagnostics.count <= 100000 && m.diagnostics.allSatisfy(string))
        for t in m.tracks {
            try require(t.index >= 0 && string(t.name) && string(t.kind) && fields(t.fields) && t.plugins.count <= 1024 && unique(t.plugins.map(\.id)))
            try require(t.plugins.allSatisfy { string($0.name) && string($0.details) && ($0.slot == nil || (0...65535).contains($0.slot!)) })
        }
    }
    public static func validateExportDestination(_ url: URL, projectPath: String) throws {
        let lexical = url.standardizedFileURL
        // Foundation may leave a symlink unresolved when its final child does not exist.
        var ancestor = lexical
        var missingComponents: [String] = []
        let manager = FileManager.default
        while !manager.fileExists(atPath: ancestor.path) {
            let attributes = try? manager.attributesOfItem(atPath: ancestor.path)
            guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw LogicReadError.invalid("끊어진 symbolic link를 익스포트 대상으로 사용할 수 없습니다.")
            }
            guard ancestor.path != "/" else { throw LogicReadError.invalid("익스포트 경로를 확인할 수 없습니다.") }
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var destination = ancestor.resolvingSymlinksInPath()
        for component in missingComponents.reversed() { destination.appendPathComponent(component) }
        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.resolvingSymlinksInPath()
        let insideProject = project.pathExtension.lowercased() == "logicx" &&
            (destination.path == project.path || destination.path.hasPrefix(project.path + "/"))
        let insideAnyProject = [lexical, destination].contains { candidate in
            candidate.pathComponents.contains { $0.lowercased().hasSuffix(".logicx") }
        }
        guard !insideProject && !insideAnyProject else {
            throw LogicReadError.invalid("원본 프로젝트를 보호하기 위해 .logicx 내부에는 익스포트할 수 없습니다. 다른 폴더를 선택하세요.")
        }
    }
    public static func text(_ m: ProjectManifest) -> String {
        var lines = ["MixManifest — \(m.projectName)", "프로젝트: \(m.projectPath)", "Alternative: \(m.alternativeID)", "ProjectData SHA256: \(m.projectDataSHA256)", "읽은 시각: \(ISO8601DateFormatter().string(from: m.capturedAt))", ""]
        lines += m.metadata.map { "\($0.label): \($0.value) [\($0.source)]" }
        for t in m.tracks { lines += ["", "\(t.index). \(t.name) · \(t.kind)"]; lines += t.fields.map { "  \($0.label): \($0.value) [\($0.source)]" }; lines += t.plugins.map { "  플러그인 \($0.slot.map(String.init) ?? "?"): \($0.name) — \($0.details)" } }
        lines += ["", "해석 범위 및 진단"] + m.diagnostics.map { "- " + $0 }; return lines.joined(separator: "\n") + "\n"
    }
}
public enum LogicReadError: LocalizedError { case invalid(String); public var errorDescription: String? { switch self { case .invalid(let message): return message } } }
