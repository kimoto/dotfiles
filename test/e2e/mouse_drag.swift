// Drag with the left mouse button from (x1, y1) to (x2, y2), in global points,
// for test/e2e/hammerspoon_translate_test.sh: screencapture -i takes a region
// from the mouse only, so no key press can stand in for it.
import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard a.count == 4 else {
    FileHandle.standardError.write("usage: mouse_drag.swift x1 y1 x2 y2\n".data(using: .utf8)!)
    exit(2)
}
let from = CGPoint(x: a[0], y: a[1]), to = CGPoint(x: a[2], y: a[3])

func post(_ type: CGEventType, _ at: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    usleep(30_000)
}

post(.mouseMoved, from)
post(.leftMouseDown, from)
for i in 1...20 {
    let t = Double(i) / 20
    post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
}
post(.leftMouseUp, to)
