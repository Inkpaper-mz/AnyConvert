import Foundation

/// 行缓冲：把管道里零散的字节流切成完整的一行行文本。
final class LineBuffer {
    private var bytes: [UInt8] = []
    private let lock = NSLock()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        bytes.append(contentsOf: data)
        var lines: [String] = []
        var start = 0
        for i in 0..<bytes.count where bytes[i] == 0x0A {
            if i > start {
                lines.append(String(decoding: bytes[start..<i], as: UTF8.self))
            }
            start = i + 1
        }
        if start > 0, start <= bytes.count {
            bytes.removeFirst(start)
        }
        lock.unlock()
        for line in lines { onLine(line) }
    }
}

/// FFmpeg 进程封装：异步执行、解析进度、支持取消。
final class Engine {
    static let shared = Engine()

    private let stateLock = NSLock()
    private var processes: [Process] = []
    private var cancelledByUser = false

    var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return processes.contains { $0.isRunning }
    }

    func cancel() {
        stateLock.lock()
        cancelledByUser = true
        let list = processes
        stateLock.unlock()
        for process in list { process.terminate() }
    }

    func resetCancellation() {
        stateLock.lock()
        cancelledByUser = false
        stateLock.unlock()
    }

    func run(arguments: [String],
             duration: Double,
             progress: @escaping (Double, String) -> Void) async throws {
        guard let ffmpeg = Toolchain.ffmpeg else { throw ConvertError.toolchainMissing }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.qualityOfService = .userInitiated

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let errLock = NSLock()
        var errorLines: [String] = []

        var lastPercent = -1.0
        var speedText = ""

        let progressBuffer = LineBuffer { line in
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { return }
            let key = String(pair[0])
            let value = String(pair[1])

            switch key {
            case "out_time_us", "out_time_ms":
                guard let microseconds = Int64(value), microseconds >= 0, duration > 0 else { return }
                let seconds = Double(microseconds) / 1_000_000
                let percent = min(max(seconds / duration, 0), 0.995)
                if percent - lastPercent >= 0.004 || (lastPercent < 0 && percent > 0) {
                    lastPercent = percent
                    progress(percent, speedText)
                }
            case "speed":
                speedText = value
            default:
                break
            }
        }

        let errorBuffer = LineBuffer { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            errLock.lock()
            errorLines.append(trimmed)
            if errorLines.count > 60 { errorLines.removeFirst(errorLines.count - 60) }
            errLock.unlock()
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            progressBuffer.append(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            errorBuffer.append(data)
        }

        stateLock.lock()
        processes.append(process)
        stateLock.unlock()

        let gate = ResumeGate()
        let status: Int32 = await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { finished in
                guard gate.claim() else { return }
                cont.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if gate.claim() { cont.resume(returning: -1) }
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        // 读完剩余输出
        _ = outPipe.fileHandleForReading.availableData
        _ = errPipe.fileHandleForReading.availableData

        stateLock.lock()
        processes.removeAll { $0 === process }
        let wasCancelled = cancelledByUser
        stateLock.unlock()

        if wasCancelled { throw ConvertError.cancelled }

        guard status == 0 else {
            errLock.lock()
            let captured = errorLines
            errLock.unlock()
            let detail = captured.suffix(3).joined(separator: " · ")
            throw ConvertError.encodeFailed(detail.isEmpty ? "编码失败（FFmpeg 返回 \(status)）" : detail)
        }
    }
}

/// 保证续体只被恢复一次。
final class ResumeGate {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
