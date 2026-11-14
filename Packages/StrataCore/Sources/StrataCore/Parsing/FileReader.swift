import Foundation

/// Reads configuration files defensively: size-capped, UTF-8 only, never throwing past the scanner.
struct FileReader {
    static let maximumFileSize = 2 * 1024 * 1024

    enum ReadError: Error, Equatable {
        case missing
        case notAFile
        case tooLarge(Int)
        case unreadable(String)
        case notText
    }

    enum JSONError: Error, Equatable {
        case read(ReadError)
        case malformed(String)
        case notAnObject
    }

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func isExecutable(_ url: URL) -> Bool {
        isFile(url) && fileManager.isExecutableFile(atPath: url.path)
    }

    func text(at url: URL) -> Result<String, ReadError> {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .failure(.missing) }
        guard !isDirectory.boolValue else { return .failure(.notAFile) }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int, size > Self.maximumFileSize {
                return .failure(.tooLarge(size))
            }
            let data = try Data(contentsOf: url)
            guard let string = String(data: data, encoding: .utf8) else { return .failure(.notText) }
            return .success(string)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    func jsonObject(at url: URL) -> Result<[String: Any], JSONError> {
        switch text(at: url) {
        case .failure(let error):
            return .failure(.read(error))
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .success([:]) }
            do {
                let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [])
                guard let dictionary = object as? [String: Any] else { return .failure(.notAnObject) }
                return .success(dictionary)
            } catch {
                return .failure(.malformed(Self.describe(error)))
            }
        }
    }

    /// Resolves a URL's symlinks so the same folder reached two ways is recognised as one.
    func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if let detail = nsError.userInfo[NSDebugDescriptionErrorKey] as? String { return detail }
        return nsError.localizedDescription
    }
}

extension FileReader.ReadError {
    var message: String {
        switch self {
        case .missing: "The file doesn't exist."
        case .notAFile: "Expected a file but found a folder."
        case .tooLarge(let size): "The file is \(size / 1024) KB, larger than Strata reads (\(FileReader.maximumFileSize / 1024 / 1024) MB)."
        case .unreadable(let reason): "Couldn't read the file: \(reason)"
        case .notText: "The file isn't UTF-8 text."
        }
    }
}

extension FileReader.JSONError {
    var message: String {
        switch self {
        case .read(let error): error.message
        case .malformed(let reason): "Invalid JSON: \(reason)"
        case .notAnObject: "Expected a JSON object at the top level."
        }
    }
}
