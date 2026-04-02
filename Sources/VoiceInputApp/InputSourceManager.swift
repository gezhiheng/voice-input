import Carbon
import Foundation

final class InputSourceManager: InputSourceManaging {
    func currentInputSource() -> InputSourceDescriptor? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }

        let source = unmanaged.takeRetainedValue()
        return descriptor(for: source)
    }

    func asciiCapableInputSource() -> InputSourceDescriptor? {
        guard let unmanaged = TISCopyCurrentASCIICapableKeyboardInputSource() else {
            return nil
        }

        let source = unmanaged.takeRetainedValue()
        return descriptor(for: source)
    }

    func selectInputSource(withID id: String) -> Bool {
        let properties = [kTISPropertyInputSourceID as String: id] as CFDictionary

        if let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
           let source = list.first {
            return TISSelectInputSource(source) == noErr
        }

        if let list = TISCreateInputSourceList(properties, true)?.takeRetainedValue() as? [TISInputSource],
           let source = list.first {
            return TISSelectInputSource(source) == noErr
        }

        return false
    }

    static func isCJKSensitive(_ source: InputSourceDescriptor) -> Bool {
        if source.languages.contains(where: { language in
            language.hasPrefix("zh") || language.hasPrefix("ja") || language.hasPrefix("ko")
        }) {
            return true
        }

        let type = source.sourceType.lowercased()
        return type.contains("inputmethod") && !source.isASCII
    }

    private func descriptor(for source: TISInputSource) -> InputSourceDescriptor {
        let id = stringProperty(source: source, key: kTISPropertyInputSourceID)
        let languages = arrayProperty(source: source, key: kTISPropertyInputSourceLanguages)
        let type = stringProperty(source: source, key: kTISPropertyInputSourceType)
        let isASCII = boolProperty(source: source, key: kTISPropertyInputSourceIsASCIICapable)

        return InputSourceDescriptor(
            id: id,
            languages: languages,
            sourceType: type,
            isASCII: isASCII
        )
    }

    private func stringProperty(source: TISInputSource, key: CFString?) -> String {
        guard let key, let raw = TISGetInputSourceProperty(source, key) else {
            return ""
        }

        return unsafeBitCast(raw, to: CFString.self) as String
    }

    private func arrayProperty(source: TISInputSource, key: CFString?) -> [String] {
        guard let key, let raw = TISGetInputSourceProperty(source, key) else {
            return []
        }

        return (unsafeBitCast(raw, to: CFArray.self) as NSArray) as? [String] ?? []
    }

    private func boolProperty(source: TISInputSource, key: CFString?) -> Bool {
        guard let key, let raw = TISGetInputSourceProperty(source, key) else {
            return false
        }

        return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
    }
}
