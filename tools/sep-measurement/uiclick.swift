// uiclick.swift — minimal CGEvent driver for GUI measurement automation.
// Usage:
//   swift uiclick.swift click <x> <y> [clicks]
//   swift uiclick.swift type <text>
//   swift uiclick.swift key <keycode> [cmd|shift|opt|ctrl ...]
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { exit(1) }

func post(_ e: CGEvent?) {
    e?.post(tap: .cghidEventTap)
    usleep(30_000)
}

switch args[1] {
case "click":
    let x = Double(args[2])!, y = Double(args[3])!
    let clicks = args.count > 4 ? Int64(args[4])! : 1
    let pt = CGPoint(x: x, y: y)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                 mouseCursorPosition: pt, mouseButton: .left))
    usleep(120_000)
    for n in 1...clicks {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: pt, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: n)
        post(down)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: pt, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: n)
        post(up)
        usleep(90_000)
    }
case "type":
    let text = args[2]
    for scalar in text.unicodeScalars {
        var chars: [UniChar] = Array(String(scalar).utf16)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        post(down)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        post(up)
    }
case "key":
    let code = CGKeyCode(UInt16(args[2])!)
    var flags: CGEventFlags = []
    for mod in args.dropFirst(3) {
        switch mod {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    down?.flags = flags
    post(down)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    up?.flags = flags
    post(up)
case "typenum":
    // Digits / minus / dot via REAL keycodes — Qt ignores pure unicode
    // events but honors hardware-style keycodes.
    let keymap: [Character: CGKeyCode] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "-": 27, ".": 47,
    ]
    for ch in args[2] {
        guard let code = keymap[ch] else { continue }
        post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
        post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false))
        usleep(60_000)
    }
default:
    exit(1)
}
