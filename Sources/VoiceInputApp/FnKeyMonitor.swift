import ApplicationServices
import Foundation

final class FnKeyMonitor {
    var onToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsPressed = false

    func start() {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        fnIsPressed = false
    }

    static func canCreateProbeTap() -> Bool {
        let mask = 1 << CGEventType.flagsChanged.rawValue
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        if let tap {
            CFMachPortInvalidate(tap)
            return true
        }

        return false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        let transitionChanged = isPressed != fnIsPressed

        guard transitionChanged else {
            return Unmanaged.passUnretained(event)
        }

        fnIsPressed = isPressed

        if isPressed {
            onToggle?()
        }

        return nil
    }
}
