import AppKit
import Carbon
import Foundation

enum InputSourceError: Error, CustomStringConvertible {
    case invalidArguments
    case missingIdentifier
    case sourceNotFound(String)
    case sourceNotSelectable(String)
    case selectionFailed(String, OSStatus)
    case selectionDidNotStick(expected: String, actual: String)
    case quiesceFailed(identifier: String, bundleIdentifier: String)

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: cornerpet-input-source current | select <input-source-id>"
        case .missingIdentifier:
            "the current keyboard input source has no identifier"
        case let .sourceNotFound(identifier):
            "enabled input source not found: \(identifier)"
        case let .sourceNotSelectable(identifier):
            "input source is not selectable: \(identifier)"
        case let .selectionFailed(identifier, status):
            "failed to select input source \(identifier) (OSStatus \(status))"
        case let .selectionDidNotStick(expected, actual):
            "input source selection did not stick (expected \(expected), got \(actual))"
        case let .quiesceFailed(identifier, bundleIdentifier):
            "input source process did not stop (source \(identifier), bundle \(bundleIdentifier))"
        }
    }
}

func property<T>(of source: TISInputSource, key: CFString, as type: T.Type) -> T? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue() as? T
}

func identifier(of source: TISInputSource) -> String? {
    property(of: source, key: kTISPropertyInputSourceID, as: String.self)
}

func currentIdentifier() throws -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let identifier = identifier(of: source) else {
        throw InputSourceError.missingIdentifier
    }
    return identifier
}

func enabledSource(identifier: String) -> TISInputSource? {
    let properties = [kTISPropertyInputSourceID: identifier] as CFDictionary
    let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
    guard let rawSource = sources.firstObject,
          CFGetTypeID(rawSource as CFTypeRef) == TISInputSourceGetTypeID() else {
        return nil
    }
    return (rawSource as! TISInputSource)
}

func select(identifier expectedIdentifier: String) throws {
    guard let source = enabledSource(identifier: expectedIdentifier) else {
        throw InputSourceError.sourceNotFound(expectedIdentifier)
    }

    let isSelectable = property(
        of: source,
        key: kTISPropertyInputSourceIsSelectCapable,
        as: NSNumber.self
    )?.boolValue ?? false
    guard isSelectable else {
        throw InputSourceError.sourceNotSelectable(expectedIdentifier)
    }

    let status = TISSelectInputSource(source)
    guard status == noErr else {
        throw InputSourceError.selectionFailed(expectedIdentifier, status)
    }

    let actualIdentifier = try currentIdentifier()
    guard actualIdentifier == expectedIdentifier else {
        throw InputSourceError.selectionDidNotStick(
            expected: expectedIdentifier,
            actual: actualIdentifier
        )
    }
}

func quiesce(identifier sourceIdentifier: String) throws {
    guard let source = enabledSource(identifier: sourceIdentifier) else {
        throw InputSourceError.sourceNotFound(sourceIdentifier)
    }

    guard let bundleIdentifier = property(
        of: source,
        key: kTISPropertyBundleID,
        as: String.self
    ), !bundleIdentifier.isEmpty else {
        return
    }

    let applications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
    )
    guard !applications.isEmpty else {
        return
    }

    guard applications.allSatisfy({ $0.terminate() }) else {
        throw InputSourceError.quiesceFailed(
            identifier: sourceIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }

    let deadline = Date().addingTimeInterval(3)
    while applications.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    guard applications.allSatisfy(\.isTerminated) else {
        throw InputSourceError.quiesceFailed(
            identifier: sourceIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["current"] {
        print(try currentIdentifier())
    } else if arguments.count == 2, arguments[0] == "select" {
        try select(identifier: arguments[1])
    } else if arguments.count == 2, arguments[0] == "quiesce" {
        try quiesce(identifier: arguments[1])
    } else {
        throw InputSourceError.invalidArguments
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(64)
}
