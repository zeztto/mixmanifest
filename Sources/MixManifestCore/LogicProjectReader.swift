// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mike Farr and Sungwoon Jeon.
import Foundation
import CryptoKit

// Read-only adaptation of phierceweb/logicxkit (Apache-2.0), commit
// 75b58fbf597a2ea1296b68323c09c7e3bed84ff6: insert.py, environment.py,
// tracklist.py, binding.py, levels.py and _binary.py. See THIRD_PARTY_NOTICES.md.
// This implementation adds strict framing, version checks, bounded reads and provenance.
public enum LogicProjectReader {
    public static func read(_ url: URL, alternativeID: String? = nil) throws -> ProjectManifest {
        let root = url.standardizedFileURL
        guard root.pathExtension.lowercased() == "logicx" else { throw LogicReadError.invalid(".logicx 프로젝트 패키지를 선택하세요.") }
        try check(root, root: root, directory: true)
        var diagnostics = ["저장된 프로젝트 파일만 읽었습니다. 저장하지 않은 Logic Pro 변경 사항은 포함되지 않습니다.", "비공개 포맷의 제한적 해석입니다. fader는 원시 8.24 값이며 dB로 환산하지 않습니다. 플러그인 전체 목록·파라미터·send·automation·mute/solo는 미지원입니다."]
        let info = try plist(root.appendingPathComponent("Resources/ProjectInformation.plist"), root: root)
        let altRoot = root.appendingPathComponent("Alternatives")
        try check(altRoot, root: root, directory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: altRoot, includingPropertiesForKeys: nil)
        guard entries.count <= 1024 else { throw LogicReadError.invalid("Alternative 항목 수가 한도를 초과합니다.") }
        let ids = try entries.filter { u in
            guard !u.lastPathComponent.isEmpty, u.lastPathComponent.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
            try check(u, root: root, directory: true); return true
        }.map(\.lastPathComponent).sorted()
        guard let first = ids.first else { throw LogicReadError.invalid("저장된 Alternative를 찾지 못했습니다.") }
        let selected = alternativeID ?? first
        guard ids.contains(selected) else { throw LogicReadError.invalid("선택한 Alternative가 없습니다.") }
        if alternativeID == nil && ids.count > 1 { diagnostics.append("활성 Alternative를 확정할 수 없어 ID 순서상 첫 항목 \(first)을 선택했습니다. 다른 Alternative를 직접 선택할 수 있습니다.") }
        let names = info["VariantNames"] as? [String: String] ?? [:]
        let alternatives = ids.map { ProjectAlternative(id: $0, name: names[String(Int($0) ?? -1)] ?? "Alternative \($0)") }
        let folder = altRoot.appendingPathComponent(selected)
        let meta = try plist(folder.appendingPathComponent("MetaData.plist"), root: root)
        var fields: [ManifestField] = []
        for (key, label) in [("LastSavedFrom", "저장한 Logic 버전"), ("BundleVersion", "패키지 버전")] { if let v = info[key] { fields.append(.init(label: label, value: String(describing: v), source: "Resources/ProjectInformation.plist#\(key)")) } }
        for (key, label) in [("NumberOfTracks", "메타데이터 트랙 수"), ("SampleRate", "샘플레이트 (Hz)"), ("BeatsPerMinute", "메타데이터 템포 (BPM)"), ("SongSignatureNumerator", "박자 분자"), ("SongSignatureDenominator", "박자 분모"), ("SongKey", "조성"), ("SongGenderKey", "조성 모드")] { if let v = meta[key] { fields.append(.init(label: label, value: String(describing: v), source: "Alternatives/\(selected)/MetaData.plist#\(key)")) } }
        diagnostics.append("BPM·박자·조성은 MetaData.plist의 저장값입니다. 프로젝트 전체 tempo/signature 변화를 나타내지 않습니다.")
        let data = try bounded(folder.appendingPathComponent("ProjectData"), root: root, limit: 256 * 1024 * 1024)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var tracks: [ManifestTrack] = []
        do { tracks = try parse(data, count: (meta["NumberOfTracks"] as? NSNumber)?.intValue, diagnostics: &diagnostics) }
        catch { diagnostics.append("ProjectData 해석 실패: \(error.localizedDescription) 트랙 목록은 미확인 상태입니다.") }
        return .init(capturedAt: Date(), projectName: root.deletingPathExtension().lastPathComponent, projectPath: root.path, alternativeID: selected, alternatives: alternatives, projectDataSHA256: hash, metadata: fields, tracks: tracks, diagnostics: diagnostics)
    }
    private static func check(_ url: URL, root: URL, directory: Bool) throws {
        let path = url.standardizedFileURL.path
        guard path == root.path || path.hasPrefix(root.path + "/") else { throw LogicReadError.invalid("프로젝트 밖 경로는 읽을 수 없습니다.") }
        var current = url.standardizedFileURL
        while current.path.count >= root.path.count {
            let a = try FileManager.default.attributesOfItem(atPath: current.path)
            guard a[.type] as? FileAttributeType != .typeSymbolicLink else { throw LogicReadError.invalid("프로젝트 내부 symbolic link는 지원하지 않습니다: \(current.lastPathComponent)") }
            if current.path == root.path { break }; current.deleteLastPathComponent()
        }
        let a = try FileManager.default.attributesOfItem(atPath: path)
        guard a[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular) else { throw LogicReadError.invalid("예상한 프로젝트 파일 형식이 아닙니다: \(url.lastPathComponent)") }
    }
    private static func bounded(_ url: URL, root: URL, limit: Int) throws -> Data {
        try check(url, root: root, directory: false)
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = a[.size] as? NSNumber, size.int64Value <= Int64(limit) else { throw LogicReadError.invalid("파일 크기가 읽기 한도를 초과합니다: \(url.lastPathComponent)") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit, bytes.count == size.intValue else { throw LogicReadError.invalid("읽는 동안 파일 크기가 바뀌었습니다. 저장이 끝난 뒤 다시 열어주세요.") }; return bytes
    }
    private static func plist(_ url: URL, root: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let d = try bounded(url, root: root, limit: 8 * 1024 * 1024)
        guard let p = try PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] else { throw LogicReadError.invalid("올바른 metadata dictionary가 아닙니다.") }; return p
    }
    private struct Record { let tag: String; let version: Int; let group: Int; let owner: Int; let key: Int; let offset: Int; let body: Data
        func source(_ offset: Int) -> String { "ProjectData/\(tag)@0x\(String(self.offset + 36 + offset, radix: 16))" }
    }
    private static func records(_ d: Data) throws -> [Record] {
        guard d.count >= 24, Array(d.prefix(4)) == [0x23, 0x47, 0xc0, 0xab], d.u32(16) == d.count - 24 else { throw LogicReadError.invalid("지원하지 않거나 손상된 ProjectData header입니다.") }
        var out: [Record] = []; var p = 24
        while p < d.count {
            guard d.count - p >= 36 else { throw LogicReadError.invalid("잘린 chunk header입니다.") }
            let size = d.u32(p + 28)
            guard size <= d.count - p - 36, out.count < 1_000_000 else { throw LogicReadError.invalid("잘린 chunk payload 또는 chunk 수 한도 초과입니다.") }
            out.append(.init(tag: String(decoding: d[p..<p+4], as: UTF8.self), version: d.u16(p+4), group: d.u32(p+8), owner: d.u16(p+14), key: d.u16(p+18), offset: p, body: d.subdata(in: p+36..<p+36+size)))
            p += 36 + size
        }; return out
    }
    private static func parse(_ data: Data, count: Int?, diagnostics: inout [String]) throws -> [ManifestTrack] {
        let all = try records(data)
        let versions = ["ivnE": 12, "karT": 6, "OCuA": 7, "UCuA": 5]
        for r in all { if let v = versions[r.tag], r.version != v { throw LogicReadError.invalid("미지원 \(r.tag) class version \(r.version) (지원 \(v)).") } }
        var runs: [[Record]] = []; var run: [Record] = []
        for r in all where r.tag == "karT" { if r.body.isEmpty { if !run.isEmpty { runs.append(run); run = [] } } else { run.append(r) } }
        if !run.isEmpty { runs.append(run) }
        guard let count = count, count >= 0, count < 100_000 else { throw LogicReadError.invalid("트랙 수 metadata가 없어 arrange 목록을 확정하지 못했습니다.") }
        let candidates = runs.filter { $0.count == count + 1 && $0.allSatisfy { $0.group == 0x40000 } }
        guard candidates.count == 1, let rows = candidates.first, rows.allSatisfy({ $0.body.count == 58 }) else { throw LogicReadError.invalid("arrange 목록과 metadata 트랙 수가 일치하지 않거나 모호합니다.") }
        var objects: [Int: Record] = [:]; var channels: [Int: Record] = [:]
        for r in all {
            if r.tag == "ivnE", r.body.count > 176, r.body.u16(0) == 1800 {
                let id = r.body.u32(16)
                guard objects[id] == nil else { throw LogicReadError.invalid("중복 Environment object ID입니다.") }; objects[id] = r
            }
            if r.tag == "OCuA", r.key == 65535, r.body.count > 200 {
                if let old = channels[r.owner], old.body.count == r.body.count, old.body != r.body { throw LogicReadError.invalid("동일 owner의 mixer record가 충돌합니다.") }
                if r.body.count > (channels[r.owner]?.body.count ?? 0) { channels[r.owner] = r }
            }
        }
        func uuid(_ r: Record) -> Data { r.body.suffix(48).prefix(16) }
        func label(_ r: Record) -> String { String(decoding: r.body[60..<92].prefix(while: { $0 != 0 }), as: UTF8.self).trimmingCharacters(in: .whitespaces) }
        var result: [ManifestTrack] = []
        var unbound = 0; var unknownNames = 0
        for (i, row) in rows.enumerated() {
            let id = row.body.u32(8)
            guard let obj = objects[id] else { throw LogicReadError.invalid("arrange row \(i)의 Environment object \(id)를 찾지 못했습니다.") }
            let n = obj.body.u16(158)
            guard n <= 63, 160 + n <= obj.body.count - 16 else { throw LogicReadError.invalid("잘못된 Environment 이름 길이입니다.") }
            let raw = obj.body[160..<160+n]
            let validName = n > 0 && raw.allSatisfy { $0 >= 32 && $0 < 127 }
            let name = validName ? String(decoding: raw, as: UTF8.self) : "이름 해석 미지원 (object \(id))"
            if !validName { unknownNames += 1 }
            var fields: [ManifestField] = [.init(label: "Object ID", value: String(id), source: row.source(8)), .init(label: "저장된 객체 이름", value: name, source: obj.source(160)), .init(label: "상위 Object ID", value: String(obj.body.u32(38)), source: obj.source(38))]
            if obj.body[45] & 1 == 0 { fields.append(.init(label: "이름 표시 방식", value: "channel strip setting이 화면 이름을 대체할 수 있음", source: obj.source(45))) }
            let matches = channels.values.filter { uuid($0) == obj.body.suffix(16) }
            var plugins: [ManifestPlugin] = []
            if matches.count == 1, let ch = matches.first {
                let p = ch.body
                fields += [.init(label: "채널", value: label(ch), source: ch.source(60)), .init(label: "Channel owner", value: String(ch.owner), source: "ProjectData/OCuA header@0x\(String(ch.offset + 14, radix: 16))")]
                if p[85] == p[119], p[85] <= 127 { fields.append(.init(label: "Fader 위치", value: String(format: "%.6f / 127 (8.24 raw: %u)", Double(p.u32(116)) / 16777216, UInt32(p.u32(116))), source: ch.source(116))) } else { diagnostics.append("\(name): fader 중복 필드가 불일치하여 미확인 처리했습니다.") }
                if p[89] <= 127 { fields.append(.init(label: "Pan", value: "\(Int(p[89]) - 64) (raw: \(p[89]))", source: ch.source(89))) }
                fields.append(.init(label: "채널 폭", value: "\(p[123])", source: ch.source(123)))
                for (labelName, start) in [("출력", p.count - 32), ("입력", p.count - 16)] {
                    let target = p.subdata(in: start..<start+16)
                    let destinations = channels.values.filter { uuid($0) == target }
                    let value: String
                    if target.allSatisfy({ $0 == 0 }) { value = "UUID 미설정" }
                    else if destinations.count == 1, let destination = destinations.first { value = label(destination) }
                    else { value = "미해석 UUID " + target.map { String(format: "%02x", $0) }.joined() }
                    fields.append(.init(label: labelName, value: value, source: ch.source(start)))
                }
                plugins = all.filter { $0.tag == "UCuA" && $0.owner == ch.owner }.compactMap { plugin($0) }
                plugins.sort { ($0.slot ?? Int.max, $0.id) < ($1.slot ?? Int.max, $1.id) }
            } else { unbound += 1; fields.append(.init(label: "믹서 연결", value: "UUID 연결 미확인", source: obj.source(obj.body.count - 16))) }
            let kind: String = row.body[51] == 0x85 ? "소프트웨어 악기" : row.body[51] == 0x07 ? "오디오" : "기타 (type \(row.body[51]))"
            result.append(.init(id: "object-\(id)-row-\(i)", index: i + 1, name: name, kind: kind, fields: fields, plugins: plugins))
        }
        diagnostics.append("arrange 목록 \(result.count)행을 해석했습니다. metadata 트랙 수 \(count)에 출력 행이 포함될 수 있어 행 수와 트랙 수는 다릅니다.")
        diagnostics.append("플러그인은 같은 owner의 UCuA v5 저장 레코드입니다. 현재 사용 여부·슬롯 연결의 완전성은 미확인입니다. 저장된 짧은 이름은 잘릴 수 있습니다.")
        if unbound > 0 { diagnostics.append("\(unbound)행은 mixer UUID 연결을 확정하지 못했습니다.") }
        if unknownNames > 0 { diagnostics.append("\(unknownNames)행 이름의 문자 인코딩이 미지원입니다. 임의 변환하지 않았습니다.") }
        return result
    }
    private static func plugin(_ r: Record) -> ManifestPlugin? {
        let p = r.body
        guard p.count >= 160, [1, 2].contains(p.u16(4)) else { return nil }
        func four(_ start: Int) -> String? { let bytes = p[start..<start+4].reversed(); guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }; return String(decoding: bytes, as: UTF8.self) }
        let component: String
        if Array(p[132..<136]) == Array("GAME".utf8), p.u32(136) == 0 {
            component = "Logic native type ID \(p.u32(140))"
        } else {
            guard let manufacturer = four(132), let type = four(136), let subtype = four(140), ["aufx", "aumu", "aumf", "augn", "aumi", "auol", "aumx"].contains(type) else { return nil }
            component = "\(manufacturer)/\(type)/\(subtype)"
        }
        let nameBytes = p[120..<132].prefix(while: { $0 != 0 })
        guard !nameBytes.isEmpty, nameBytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        let name = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let slot = p.u16(6)
        let chain = p.u16(4) == 2 ? "MIDI" : "Audio"
        let bypass = "저장 bypass 필드 \(p[112]) (현재 사용 여부 미확인)"
        return .init(id: "plugin-\(r.offset)", slot: slot, name: name, details: "저장 레코드·짧은 이름; \(chain) slot \(slot); \(component); \(bypass); \(r.source(120))")
    }
}
private extension Data {
    func u16(_ offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 | Int(self[offset + 2]) << 16 | Int(self[offset + 3]) << 24 }
}
