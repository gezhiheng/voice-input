import AppKit
import Foundation

struct PasteboardSnapshot: Equatable {
    struct Item: Equatable {
        var dataByType: [String: Data]
    }

    var items: [Item]
}

final class PasteboardClipboardManager: ClipboardManaging {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @MainActor
    func snapshot() -> PasteboardSnapshot {
        var items: [PasteboardSnapshot.Item] = []
        if let pasteboardItems = pasteboard.pasteboardItems {
            for item in pasteboardItems {
                var map: [String: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        map[type.rawValue] = data
                    }
                }
                items.append(PasteboardSnapshot.Item(dataByType: map))
            }
        }

        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func replaceContents(with text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw VoiceInputError.message("Failed to update the clipboard.")
        }
    }

    @MainActor
    func restore(from snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else {
            return
        }

        let items = snapshot.items.map { snapshotItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }

        pasteboard.writeObjects(items)
    }
}
