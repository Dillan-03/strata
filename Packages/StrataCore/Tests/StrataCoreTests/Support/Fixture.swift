import Foundation
import StrataCore
import XCTest

/// A throwaway home folder, repository and managed-settings folder for one test.
final class Fixture {
    let root: URL
    let home: URL
    let repository: URL
    let managed: URL
    let bin: URL

    init(file: StaticString = #filePath, line: UInt = #line) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("strata-tests-\(UUID().uuidString)", isDirectory: true)
        root = base.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home", isDirectory: true)
        repository = home.appendingPathComponent("code/repo", isDirectory: true)
        managed = root.appendingPathComponent("managed", isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        for directory in [home, repository, managed, bin] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var claude: URL { home.appendingPathComponent(".claude", isDirectory: true) }

    var environment: ScanEnvironment {
        ScanEnvironment(homeDirectory: home, managedDirectory: managed, executableSearchPaths: [bin], nestedSearchDepth: 6)
    }

    func inspect() -> InspectionReport {
        Inspector(environment: environment).inspect(repository)
    }

    @discardableResult
    func write(_ relativePath: String, in base: URL, _ contents: String) throws -> URL {
        let url = base.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func json(_ relativePath: String, in base: URL, _ object: Any) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return try write(relativePath, in: base, String(decoding: data, as: UTF8.self))
    }

    func makeDirectory(_ relativePath: String, in base: URL) throws {
        try FileManager.default.createDirectory(at: base.appendingPathComponent(relativePath), withIntermediateDirectories: true)
    }

    func makeExecutable(_ name: String) throws -> URL {
        let url = try write(name, in: bin, "#!/bin/sh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func skill(name: String? = nil, description: String = "Does a thing", extra: String = "") -> String {
        var lines = ["---"]
        if let name { lines.append("name: \(name)") }
        lines.append("description: \(description)")
        if !extra.isEmpty { lines.append(extra) }
        lines.append("---")
        lines.append("Instructions.")
        return lines.joined(separator: "\n")
    }
}

extension InspectionReport {
    func items(_ kind: ItemKind, named name: String) -> [ConfigItem] {
        items.filter { $0.kind == kind && $0.name == name }
    }

    func onlyItem(_ kind: ItemKind, named name: String, file: StaticString = #filePath, line: UInt = #line) throws -> ConfigItem {
        let matches = items(kind, named: name)
        XCTAssertEqual(matches.count, 1, "Expected one \(kind) named \(name), found \(matches.count)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func hasDiagnostic(_ code: Diagnostic.Code) -> Bool {
        diagnostics.contains { $0.code == code }
    }
}
