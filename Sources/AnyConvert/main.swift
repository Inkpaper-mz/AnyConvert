import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    let ok = SelfTest.run()
    exit(ok ? 0 : 1)
}

if arguments.contains("--print-env") {
    print(Toolchain.versionString())
    print("ffmpeg: \(Toolchain.ffmpeg?.path ?? "未找到")")
    print("ffprobe: \(Toolchain.ffprobe?.path ?? "未找到")")
    print("videotoolbox: \(Toolchain.supportsVideoToolbox())")
    exit(0)
}

acLog("main start, args=\(arguments)")
MainActor.assumeIsolated {
    acLog("inside assumeIsolated")
    let application = NSApplication.shared
    let delegate = AppDelegate()
    AppDelegate.retained = delegate
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
