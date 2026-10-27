import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MixManifestCore

// Logic projects may be registered as packages or appear as ordinary folders.
// Do not use a dynamically resolved UTType to decide whether they are selectable.
private final class LogicProjectPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if url.pathExtension.lowercased() == "logicx" { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard url.pathExtension.lowercased() == "logicx" else {
            throw NSError(domain: "MixManifest", code: 3, userInfo: [
                NSLocalizedDescriptionKey: ".logicx 프로젝트 파일 또는 폴더를 선택하세요."
            ])
        }
    }
}

@main
struct MixManifestApp: App {
    var body: some Scene {
        WindowGroup("MixManifest") {
            ManifestView().frame(minWidth: 1000, minHeight: 650)
        }
        .defaultSize(width: 1200, height: 790)
    }
}

private struct ManifestView: View {
    @State private var manifest: ProjectManifest?
    @State private var selectedID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importedJSON = false
    @State private var status = "저장된 Logic Pro 프로젝트를 선택하세요."

    private var selected: ManifestTrack? { manifest?.tracks.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let manifest {
                overview(manifest)
                Divider()
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("트랙 및 채널").font(.headline)
                            Spacer()
                            Text("해석된 항목 \(manifest.tracks.count)개").font(.caption).foregroundStyle(.secondary)
                        }.padding(16)
                        Table(manifest.tracks, selection: $selectedID) {
                            TableColumn("순서") { track in Text(String(track.index)).monospacedDigit().lineLimit(1) }.width(32)
                            TableColumn("이름") { track in Text(track.name).lineLimit(1).help(track.name) }.width(min: 140, ideal: 170, max: 240)
                            TableColumn("Pan") { track in Text(compactValue(track, label: "Pan")).monospacedDigit().lineLimit(1).help(fieldValue(track, label: "Pan")) }.width(54)
                            TableColumn("Fader 위치") { track in Text(compactValue(track, label: "Fader 위치")).monospacedDigit().lineLimit(1).help(fieldValue(track, label: "Fader 위치")) }.width(75)
                            TableColumn("플러그인 레코드") { track in
                                Text(track.plugins.isEmpty ? "—" : track.plugins.map(\.name).joined(separator: ", ")).lineLimit(1)
                            }.width(min: 120, ideal: 150, max: 180)
                        }
                        if manifest.tracks.isEmpty {
                            Text("이 프로젝트에서 트랙 정보를 해석하지 못했습니다. 프로젝트 개요와 진단을 확인하세요.")
                                .font(.callout).foregroundStyle(.secondary).padding(16)
                        }
                    }.frame(minWidth: 540)
                    detail.frame(minWidth: 300, idealWidth: 330, maxWidth: 360)
                }
                if !manifest.diagnostics.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(manifest.diagnostics.enumerated()), id: \.offset) { _, message in
                                Text(message).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
                    }.frame(maxHeight: 90)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Logic Pro 프로젝트 열기").font(.title2).fontWeight(.semibold)
                    Text(".logicx 파일을 직접 읽어 프로젝트와 트랙 정보를 한 화면에 표시합니다.")
                    Text("Logic Pro를 실행하지 않아도 됩니다. 저장된 파일의 상태를 읽으므로, 최근 변경을 보려면 먼저 Logic Pro에서 저장하세요.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("프로젝트 선택…", action: openProject).controlSize(.large).disabled(isLoading)
                }.frame(maxWidth: 530, alignment: .leading).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if isLoading { ProgressView().controlSize(.small) }
                Text(status).lineLimit(2)
                Spacer()
                if let manifest { Text("읽은 시각 \(manifest.capturedAt.formatted(date: .omitted, time: .standard))") }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("JSON 열기…", action: openJSON).disabled(isLoading)
            }
        }
        .alert("파일을 읽거나 저장하지 못했습니다", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MixManifest").font(.system(size: 25, weight: .semibold))
                Text("저장된 Logic Pro 프로젝트를 읽고 기록합니다.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("프로젝트 열기…", action: openProject).controlSize(.large).disabled(isLoading)
            if let manifest {
                Button("다시 읽기") {
                    load(URL(fileURLWithPath: manifest.projectPath), alternativeID: manifest.alternativeID)
                }.disabled(isLoading)
                Menu("익스포트") {
                    Button("텍스트 (.txt)") { export(asJSON: false) }
                    Button("JSON (.json)") { export(asJSON: true) }
                }.disabled(isLoading)
            }
        }.padding(20)
    }

    private func overview(_ manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(manifest.projectName).font(.title3).fontWeight(.semibold).textSelection(.enabled)
                Text(importedJSON ? "저장된 JSON" : "프로젝트 파일").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !manifest.alternatives.isEmpty {
                    Picker("프로젝트 대안", selection: Binding(get: { manifest.alternativeID }, set: { alternative in
                        load(URL(fileURLWithPath: manifest.projectPath), alternativeID: alternative)
                    })) {
                        ForEach(manifest.alternatives) { alternative in Text(alternative.name).tag(alternative.id) }
                    }.frame(maxWidth: 290).disabled(isLoading || importedJSON)
                }
            }
            Text(manifest.projectPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(manifest.projectPath).textSelection(.enabled)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(Array(manifest.metadata.enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.label).font(.caption).foregroundStyle(.secondary)
                            Text(field.value).font(.callout).textSelection(.enabled)
                        }.help(field.source)
                    }
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("선택 항목 상세").font(.headline)
                if let selected {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.name).font(.title3).fontWeight(.semibold).textSelection(.enabled)
                    }
                    ForEach(Array(practicalFields(selected).enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.caption).foregroundStyle(.secondary)
                            Text(field.value).font(.callout).textSelection(.enabled)
                        }
                    }
                    Divider()
                    Text("저장된 플러그인 레코드").font(.headline)
                    if selected.plugins.isEmpty {
                        Text("해석된 플러그인 레코드가 없습니다.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(selected.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                if let slot = plugin.slot { Text("\(slot)").foregroundStyle(.secondary).monospacedDigit() }
                                Text(plugin.name).fontWeight(.medium)
                            }
                            if !plugin.details.isEmpty { Text(plugin.details).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                    DisclosureGroup("해석 근거") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selected.kind).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(selected.fields.enumerated()), id: \.offset) { _, field in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.label).fontWeight(.medium)
                                    Text(field.value).textSelection(.enabled)
                                    Text(field.source).foregroundStyle(.secondary).textSelection(.enabled)
                                }.font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                } else {
                    Text("목록에서 트랙 또는 채널을 선택하세요.").foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
    }

    private func fieldValue(_ track: ManifestTrack, label: String) -> String {
        track.fields.first { $0.label == label }?.value ?? "—"
    }

    private func compactValue(_ track: ManifestTrack, label: String) -> String {
        let value = fieldValue(track, label: label)
        if label == "Pan" {
            return value.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? value
        }
        let prefix = value.components(separatedBy: " /").first ?? value
        guard let number = Double(prefix) else { return value }
        return number.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func practicalFields(_ track: ManifestTrack) -> [ManifestField] {
        let order = ["채널", "Pan", "Fader 위치", "출력", "입력"]
        return track.fields.filter { field in order.contains { field.label.hasPrefix($0) } }
            .sorted { lhs, rhs in
                (order.firstIndex { lhs.label.hasPrefix($0) } ?? order.count) <
                (order.firstIndex { rhs.label.hasPrefix($0) } ?? order.count)
            }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        let delegate = LogicProjectPanelDelegate()
        panel.delegate = delegate
        panel.allowedContentTypes = []
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Logic Pro 프로젝트 열기"
        let response = withExtendedLifetime(delegate) { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL, alternativeID: String? = nil) {
        isLoading = true
        status = "\(url.lastPathComponent) 읽는 중…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LogicProjectReader.read(url, alternativeID: alternativeID)
                }.value
                manifest = result
                importedJSON = false
                selectedID = nil
                status = "저장된 프로젝트 파일을 읽었습니다. 원본 파일은 변경하지 않았습니다."
            } catch {
                errorMessage = error.localizedDescription
                status = "프로젝트를 읽지 못했습니다."
            }
            isLoading = false
        }
    }

    private func openJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "MixManifest JSON 열기"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isLoading = true
        status = "JSON 읽는 중…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    let limit = 32 * 1024 * 1024
                    guard resource.isRegularFile == true else {
                        throw NSError(domain: "MixManifest", code: 1, userInfo: [NSLocalizedDescriptionKey: "일반 JSON 파일을 선택하세요."])
                    }
                    guard (resource.fileSize ?? 0) <= limit else {
                        throw NSError(domain: "MixManifest", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON 파일은 최대 32 MB까지 열 수 있습니다."])
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: limit + 1) ?? Data()
                    guard data.count <= limit else {
                        throw NSError(domain: "MixManifest", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON 파일은 최대 32 MB까지 열 수 있습니다."])
                    }
                    return try ManifestIO.decodeJSON(data)
                }.value
                manifest = result
                importedJSON = true
                selectedID = nil
                status = "저장된 JSON을 열었습니다. ‘다시 읽기’를 누르면 기록된 원본 경로에서 프로젝트를 읽습니다."
            } catch {
                errorMessage = error.localizedDescription
                status = "JSON을 읽지 못했습니다."
            }
            isLoading = false
        }
    }

    private func export(asJSON: Bool) {
        guard let manifest else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [asJSON ? .json : .plainText]
        let safeName = manifest.projectName.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
        panel.nameFieldStringValue = "\(String(safeName.prefix(120)))-MixManifest.\(asJSON ? "json" : "txt")"
        panel.title = "프로젝트 정보 저장"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ManifestIO.validateExportDestination(url, projectPath: manifest.projectPath)
            let data = try asJSON ? ManifestIO.encodeJSON(manifest) : Data(ManifestIO.text(manifest).utf8)
            try data.write(to: url, options: .atomic)
            status = "저장 완료: \(url.lastPathComponent)"
        } catch { errorMessage = error.localizedDescription }
    }
}
