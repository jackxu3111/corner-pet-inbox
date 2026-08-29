import AppKit
import Carbon
import CoreGraphics
import Foundation

enum InputSourceError: Error, CustomStringConvertible {
    case invalidArguments
    case missingIdentifier
    case sourceNotFound(String)
    case sourceNotSelectable(String)
    case selectionFailed(String, OSStatus)
    case selectionDidNotStick(expected: String, actual: String)
    case quiesceFailed(identifier: String, bundleIdentifier: String)
    case eventPostingUnavailable

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: cornerpet-input-source current | select <input-source-id> | quiesce <input-source-id>"
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
            "input source candidate cleanup failed (source \(identifier), bundle \(bundleIdentifier))"
        case .eventPostingUnavailable:
            "event-posting access is unavailable for candidate-window cleanup"
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

func sourceBundleIdentifier(identifier sourceIdentifier: String) throws -> String? {
    guard let source = enabledSource(identifier: sourceIdentifier) else {
        throw InputSourceError.sourceNotFound(sourceIdentifier)
    }

    return property(
        of: source,
        key: kTISPropertyBundleID,
        as: String.self
    )
}

func quiesce(identifier sourceIdentifier: String) throws -> String {
    guard let bundleIdentifier = try sourceBundleIdentifier(identifier: sourceIdentifier),
          !bundleIdentifier.isEmpty else {
        return "unchanged"
    }

    let applications = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
    )
    guard !applications.isEmpty else {
        return "unchanged"
    }

    guard CGPreflightPostEventAccess() else {
        throw InputSourceError.eventPostingUnavailable
    }

    guard let eventSource = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(
              keyboardEventSource: eventSource,
              virtualKey: 53,
              keyDown: true
          ),
          let keyUp = CGEvent(
              keyboardEventSource: eventSource,
              virtualKey: 53,
              keyDown: false
          ) else {
        throw InputSourceError.quiesceFailed(
            identifier: sourceIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }

    for application in applications {
        keyDown.postToPid(application.processIdentifier)
        keyUp.postToPid(application.processIdentifier)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    return "escape-posted"
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["current"] {
        print(try currentIdentifier())
    } else if arguments.count == 2, arguments[0] == "select" {
        try select(identifier: arguments[1])
    } else if arguments.count == 2, arguments[0] == "quiesce" {
        print(try quiesce(identifier: arguments[1]))
    } else {
        throw InputSourceError.invalidArguments
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(64)
}
