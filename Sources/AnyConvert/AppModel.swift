import AppKit

@MainActor
protocol AppModelObserver: AnyObject {
    /// 列表结构或任务状态发生变化
    func modelJobsDidChange(_ model: AppModel)
    /// 单个任务的进度 / 状态更新（高频）
    func modelJobDidUpdate(_ model: AppModel, id: UUID)
    /// 转换设置变化
    func modelSettingsDidChange(_ model: AppModel)
    /// 队列全部结束
    func modelQueueDidFinish(_ model: AppModel)
    /// 需要提示给用户的信息
    func modelDidProduceMessage(_ model: AppModel, message: String)
}

@MainActor
final class AppModel {
    static let shared = AppModel()

    weak var observer: AppModelObserver?

    private(set) var jobs: [Job] = []
    private(set) var isRunning = false
    private(set) var ffmpegVersion = "检测中…"
    private(set) var lastOutputDirectory: URL?
    private(set) var hardwareAvailable = false

    private(set) var formatID = "mp4"
    private(set) var quality: Quality = .balanced
    private(set) var resolution: ResolutionPreset = .original
    private(set) var audioBitrate: AudioBitrate = .b192
    private(set) var hardware = false
    private(set) var outputMode: OutputMode = .alongside
    private(set) var customDirectory: URL?
    private(set) var customWidth: Int?
    private(set) var customHeight: Int?

    private let engine = Engine.shared
    private let defaults = UserDefaults.standard
    private var runTask: Task<Void, Never>?

    private enum Keys {
        static let format = "ac.format"
        static let quality = "ac.quality"
        static let resolution = "ac.resolution"
        static let audioBitrate = "ac.audioBitrate"
        static let hardware = "ac.hardware"
        static let outputMode = "ac.outputMode"
        static let customDirectory = "ac.customDirectory"
        static let customWidth = "ac.customWidth"
        static let customHeight = "ac.customHeight"
    }

    private init() {}

    // MARK: - 启动

    func bootstrap() {
        loadSettings()
        acLog("bootstrap: version…")
        ffmpegVersion = Toolchain.versionString()
        acLog("bootstrap: version=\(ffmpegVersion)")
        hardwareAvailable = Toolchain.supportsVideoToolbox()
        acLog("bootstrap: hw=\(hardwareAvailable)")
        if !hardwareAvailable { hardware = false }
        if let dir = customDirectory, !FileManager.default.fileExists(atPath: dir.path) {
            customDirectory = nil
        }
    }

    private func loadSettings() {
        if let v = defaults.string(forKey: Keys.format), Catalog.all.contains(where: { $0.id == v }) { formatID = v }
        if let v = defaults.string(forKey: Keys.quality), let q = Quality(rawValue: v) { quality = q }
        if let v = defaults.string(forKey: Keys.resolution), let r = ResolutionPreset(rawValue: v) { resolution = r }
        if let v = defaults.string(forKey: Keys.audioBitrate), let b = AudioBitrate(rawValue: v) { audioBitrate = b }
        if defaults.object(forKey: Keys.hardware) != nil { hardware = defaults.bool(forKey: Keys.hardware) }
        if let v = defaults.string(forKey: Keys.outputMode), let m = OutputMode(rawValue: v) { outputMode = m }
        if let path = defaults.string(forKey: Keys.customDirectory), !path.isEmpty {
            customDirectory = URL(fileURLWithPath: path)
        }
        let storedWidth = defaults.integer(forKey: Keys.customWidth)
        let storedHeight = defaults.integer(forKey: Keys.customHeight)
        customWidth = storedWidth > 0 ? storedWidth : nil
        customHeight = storedHeight > 0 ? storedHeight : nil
    }

    // MARK: - 计算属性

    var currentFormat: OutputFormat { Catalog.format(formatID) }

    var canStart: Bool {
        !isRunning && jobs.contains { $0.status == .waiting || $0.status == .failed || $0.status == .cancelled }
    }

    var pendingCount: Int {
        jobs.filter { $0.status == .waiting || $0.status == .failed || $0.status == .cancelled }.count
    }

    var doneCount: Int { jobs.filter { $0.status == .done }.count }

    var summaryText: String {
        if isRunning {
            return L10n.t("footer.running", jobs.filter { $0.status == .running }.count, doneCount, jobs.count)
        }
        if jobs.isEmpty { return L10n.t("status.noFiles") }
        return L10n.t("footer.summary", jobs.count, doneCount)
    }

    // MARK: - 设置

    func setFormat(_ id: String) {
        guard formatID != id else { return }
        formatID = id
        defaults.set(id, forKey: Keys.format)
        observer?.modelSettingsDidChange(self)
    }

    func setQuality(_ value: Quality) {
        guard quality != value else { return }
        quality = value
        defaults.set(value.rawValue, forKey: Keys.quality)
        observer?.modelSettingsDidChange(self)
    }

    func setResolution(_ value: ResolutionPreset) {
        guard resolution != value else { return }
        resolution = value
        defaults.set(value.rawValue, forKey: Keys.resolution)
        observer?.modelSettingsDidChange(self)
    }

    func setAudioBitrate(_ value: AudioBitrate) {
        guard audioBitrate != value else { return }
        audioBitrate = value
        defaults.set(value.rawValue, forKey: Keys.audioBitrate)
        observer?.modelSettingsDidChange(self)
    }

    func setHardware(_ value: Bool) {
        guard hardware != value else { return }
        hardware = value
        defaults.set(value, forKey: Keys.hardware)
        observer?.modelSettingsDidChange(self)
    }

    func setOutputMode(_ value: OutputMode) {
        guard outputMode != value else { return }
        outputMode = value
        defaults.set(value.rawValue, forKey: Keys.outputMode)
        observer?.modelSettingsDidChange(self)
    }

    func setCustomResolution(width: Int?, height: Int?) {
        guard customWidth != width || customHeight != height else { return }
        customWidth = width
        customHeight = height
        defaults.set(width ?? 0, forKey: Keys.customWidth)
        defaults.set(height ?? 0, forKey: Keys.customHeight)
        observer?.modelSettingsDidChange(self)
    }

    func setCustomDirectory(_ url: URL?) {
        customDirectory = url
        defaults.set(url?.path, forKey: Keys.customDirectory)
        observer?.modelSettingsDidChange(self)
    }

    // MARK: - 文件管理

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要转换的文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择包含音视频的文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = customDirectory
        if panel.runModal() == .OK, let url = panel.url {
            setCustomDirectory(url)
        }
    }

    func addFiles(_ urls: [URL]) {
        let expanded = FileUtilities.expand(urls: urls)
        guard !expanded.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.noMedia"))
            return
        }

        let existing = Set(jobs.map { $0.url.standardizedFileURL })
        var added: [UUID] = []
        for url in expanded {
            let standardized = url.standardizedFileURL
            if existing.contains(standardized) { continue }
            if jobs.contains(where: { $0.url.standardizedFileURL == standardized }) { continue }
            let job = Job(url: standardized, status: .probing)
            jobs.append(job)
            added.append(job.id)
        }

        guard !added.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.duplicate"))
            return
        }
        observer?.modelJobsDidChange(self)
        probe(added)
    }

    private func probe(_ ids: [UUID]) {
        let pairs: [(UUID, URL)] = ids.compactMap { id in
            jobs.first(where: { $0.id == id }).map { (id, $0.url) }
        }
        Task.detached(priority: .userInitiated) {
            for (id, url) in pairs {
                do {
                    let info = try await MediaProbe.probe(url)
                    await MainActor.run { self.apply(info: info, to: id) }
                } catch {
                    await MainActor.run { self.applyProbeFailure(error.localizedDescription, to: id) }
                }
            }
        }
    }

    private func apply(info: MediaInfo, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].info = info
        if jobs[index].status == .probing { jobs[index].status = .waiting }
        observer?.modelJobsDidChange(self)
    }

    private func applyProbeFailure(_ message: String, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .failed
        jobs[index].message = message
        observer?.modelJobsDidChange(self)
    }

    func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
        observer?.modelJobsDidChange(self)
    }

    func job(for id: UUID) -> Job? {
        jobs.first { $0.id == id }
    }

    func retry(_ id: UUID) {
        guard !isRunning, let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .waiting
        jobs[index].message = ""
        jobs[index].progress = 0
        observer?.modelJobDidUpdate(self, id: id)
        start()
    }

    func clearAll() {
        guard !isRunning else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.cancelFirst"))
            return
        }
        jobs.removeAll()
        lastOutputDirectory = nil
        observer?.modelJobsDidChange(self)
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.status == .done }
        observer?.modelJobsDidChange(self)
    }

    func reveal(_ id: UUID) {
        guard let job = job(for: id) else { return }
        if let out = job.outputURL, FileManager.default.fileExists(atPath: out.path) {
            FileUtilities.reveal(out)
        } else {
            FileUtilities.reveal(job.url)
        }
    }

    func openOutputFolder() {
        let dir = lastOutputDirectory ?? jobs.last?.url.deletingLastPathComponent()
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        }
    }

    // MARK: - 转换流程

    func start() {
        guard !isRunning else { return }

        let ids = jobs.filter {
            $0.status == .waiting || $0.status == .failed || $0.status == .cancelled
        }.map(\.id)

        guard !ids.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.noPending"))
            return
        }

        if outputMode == .custom {
            guard let dir = customDirectory else {
                observer?.modelDidProduceMessage(self, message: L10n.t("msg.chooseOutput"))
                return
            }
            if !FileManager.default.fileExists(atPath: dir.path) {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    observer?.modelDidProduceMessage(self, message: L10n.t("msg.createDirFail", error.localizedDescription))
                    return
                }
            }
        }

        isRunning = true
        let settings = makeSettings()
        observer?.modelJobsDidChange(self)

        runTask = Task { [weak self] in
            guard let self else { return }
            for id in ids {
                if Task.isCancelled { break }
                if self.jobs.first(where: { $0.id == id }) == nil { continue }
                await self.convert(id: id, settings: settings)
            }
            self.isRunning = false
            self.observer?.modelQueueDidFinish(self)
            self.observer?.modelJobsDidChange(self)
        }
    }

    func cancel() {
        runTask?.cancel()
        engine.cancel()
    }

    private func makeSettings() -> ConversionSettings {
        ConversionSettings(
            format: currentFormat,
            quality: quality,
            resolution: resolution,
            audioBitrate: audioBitrate,
            hardware: hardware && hardwareAvailable && currentFormat.kind == .video && !currentFormat.isAnimatedImage,
            customWidth: customWidth,
            customHeight: customHeight
        )
    }

    private func outputDirectory(for input: URL) -> URL {
        if outputMode == .custom, let dir = customDirectory { return dir }
        return input.deletingLastPathComponent()
    }

    private func convert(id: UUID, settings: ConversionSettings) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]

        var media = job.info
        if media == nil {
            do {
                media = try await MediaProbe.probe(job.url)
                if let media { apply(info: media, to: id) }
            } catch {
                fail(id, message: error.localizedDescription)
                return
            }
        }
        guard let info = media else { return }

        if settings.format.kind == .audio, !info.hasAudio {
            fail(id, message: ConvertError.noAudioTrack.localizedDescription)
            return
        }
        if settings.format.kind == .video, !info.hasVideo {
            fail(id, message: ConvertError.noVideoTrack.localizedDescription)
            return
        }
        if settings.format.kind == .image, !info.hasVideo {
            fail(id, message: ConvertError.noVideoTrack.localizedDescription)
            return
        }
        if settings.format.kind == .video, info.isImage, settings.format.id != "gif" {
            fail(id, message: ConvertError.imageNeedsImageFormat.localizedDescription)
            return
        }

        let directory = outputDirectory(for: job.url)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let output = FileUtilities.outputURL(for: job.url, ext: settings.format.ext, directory: directory)

        guard let runningIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[runningIndex].status = .running
        jobs[runningIndex].progress = 0
        jobs[runningIndex].speed = ""
        jobs[runningIndex].message = ""
        observer?.modelJobDidUpdate(self, id: id)

        do {
            try await runConversion(settings: settings, job: job, info: info, output: output)
            guard let doneIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[doneIndex].status = .done
            jobs[doneIndex].progress = 1
            jobs[doneIndex].speed = ""
            jobs[doneIndex].outputURL = output
            lastOutputDirectory = directory
            observer?.modelJobDidUpdate(self, id: id)
        } catch let error as ConvertError {
            if case .cancelled = error {
                markCancelled(id)
            } else {
                fail(id, message: error.localizedDescription)
            }
        } catch {
            fail(id, message: error.localizedDescription)
        }
    }

    private func runConversion(settings: ConversionSettings,
                               job: Job,
                               info: MediaInfo,
                               output: URL) async throws {
        var arguments = CommandBuilder.arguments(settings: settings, input: job.url, output: output, info: info)

        do {
            try await engine.run(arguments: arguments, duration: info.duration) { [weak self] percent, speed in
                Task { @MainActor in self?.updateProgress(jobID: job.id, percent: percent, speed: speed) }
            }
        } catch let error as ConvertError {
            guard case .encodeFailed = error, settings.hardware else { throw error }
            // 硬件编码不可用 → 自动回退到软件编码
            var software = settings
            software.hardware = false
            arguments = CommandBuilder.arguments(settings: software, input: job.url, output: output, info: info)
            try? FileManager.default.removeItem(at: output)
            try await engine.run(arguments: arguments, duration: info.duration) { [weak self] percent, speed in
                Task { @MainActor in self?.updateProgress(jobID: job.id, percent: percent, speed: speed) }
            }
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].message = L10n.t("msg.hwFallback")
                observer?.modelJobDidUpdate(self, id: job.id)
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)??.int64Value ?? 0
        guard size > 0 else {
            throw ConvertError.encodeFailed("输出文件为空，转换未成功。")
        }
    }

    private func updateProgress(jobID: UUID, percent: Double, speed: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = percent
        jobs[index].speed = speed
        observer?.modelJobDidUpdate(self, id: jobID)
    }

    private func markCancelled(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .cancelled
        jobs[index].progress = 0
        jobs[index].speed = ""
        observer?.modelJobDidUpdate(self, id: id)
    }

    private func fail(_ id: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .failed
        jobs[index].speed = ""
        jobs[index].message = message
        observer?.modelJobDidUpdate(self, id: id)
    }
}
