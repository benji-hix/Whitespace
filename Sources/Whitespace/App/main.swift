// Sources/Whitespace/App/main.swift
import AppKit

// The delegate is set before NSApplicationMain so it exists for
// applicationWillFinishLaunching, where fonts and the document controller are
// installed. NSApplicationMain then loads MainMenu.xib (NSMainNibFile), which
// holds the menu bar only. NSApplication.delegate is weak; this global keeps
// the delegate alive.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
