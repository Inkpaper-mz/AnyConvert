import SwiftUI
import UniformTypeIdentifiers

/// 无宏 SwiftUI 界面：用 Binding(get:set:) 直连 AppModel，用 TimelineView 驱动刷新。
/// （本机仅 Command Line Tools，缺少 SwiftUIMacros，不能用 @State / @ObservededObject。）
struct SwiftUIRootView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    sidebar
                        .frame(width: 292)
                    Divider()
                    main
                }
                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            model.bootstrap()
            model.ensureValidFormat()
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.47, blue: 0.98),
                                              Color(red: 0.55, green: 0.36, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("app.title")).font(.system(size: 17, weight: .semibold))
                Text(L10n.t("app.tagline")).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Text(model.ffmpegVersion).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section(L10n.t("preset.title")) {
                    Menu {
                        ForEach(PresetStore.shared.all) { preset in
                            Button(preset.displayName) { model.apply(preset: preset) }
                        }
                    } label: {
                        SwiftUI.Label(L10n.t("preset.title"), systemImage: "wand.and.stars")
                    }
                }

                section(L10n.t("settings.format")) {
                    Picker("", selection: bind({ model.formatID }, { model.setFormat($0) })) {
                        Section(L10n.t("group.video")) {
                            ForEach(Catalog.videoFormats) { format in
                                Text(format.menuLabel).tag(format.id)
                            }
                        }
                        Section(L10n.t("group.audio")) {
                            ForEach(Catalog.audioFormats) { format in
                                Text(format.menuLabel).tag(format.id)
                            }
                        }
                        Section(L10n.t("group.image")) {
                            ForEach(Catalog.imageFormats) { format in
                                Text(format.menuLabel).tag(format.id)
                            }
                        }
                        Section(L10n.t("group.document")) {
                            ForEach(Catalog.documentFormats) { format in
                                Text(format.menuLabel).tag(format.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if !model.docEngineReady {
                    section("文档引擎") {
                        if model.docInstalling {
                            ProgressView(value: model.docInstallProgress)
                            Text(model.docInstallMessage)
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        } else {
                            Button("下载文档引擎（清华镜像）") { model.installDocumentEngine() }
                                .controlSize(.small)
                            Text("文档 / 表格 / 演示转换需要 LibreOffice，约 300 MB")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if model.currentFormat.kind == .document {
                    Text("LibreOffice 已就绪")
                        .font(.system(size: 10)).foregroundColor(.green)
                }

                if model.currentFormat.kind != .document {
                section(L10n.t("settings.quality")) {
                    Picker("", selection: bind({ model.quality }, { model.setQuality($0) })) {
                        ForEach(Quality.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                section(L10n.t("settings.resolution")) {
                    Picker("", selection: bind({ model.resolution }, { model.setResolution($0) })) {
                        ForEach(ResolutionPreset.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    if model.resolution == .custom {
                        HStack(spacing: 6) {
                            TextField("1920", text: bind(
                                { model.customWidth.map(String.init) ?? "" },
                                { model.setCustomResolution(width: Int($0), height: model.customHeight) }))
                                .textFieldStyle(.roundedBorder)
                            Text("×")
                            TextField("1080", text: bind(
                                { model.customHeight.map(String.init) ?? "" },
                                { model.setCustomResolution(width: model.customWidth, height: Int($0)) }))
                                .textFieldStyle(.roundedBorder)
                        }
                        Text(L10n.t("settings.customHint"))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }

                section(L10n.t("settings.bitrate")) {
                    Picker("", selection: bind({ model.audioBitrate }, { model.setAudioBitrate($0) })) {
                        ForEach(AudioBitrate.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if model.currentFormat.kind == .video {
                    Toggle(L10n.t("settings.hardware"),
                           isOn: bind({ model.hardware }, { model.setHardware($0 && model.hardwareAvailable) }))
                        .toggleStyle(.checkbox)
                        .disabled(!model.hardwareAvailable)
                    Text(model.hardwareAvailable ? L10n.t("settings.hwHint") : L10n.t("settings.hwUnsupported"))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }

                if model.currentFormat.kind == .image || model.currentFormat.kind == .video {
                section(L10n.t("settings.compression")) {
                    Toggle(L10n.t("settings.targetSize"),
                           isOn: bind({ model.targetSizeMB != nil },
                                      { model.setTargetSizeMB($0 ? 2.0 : nil) }))
                        .toggleStyle(.checkbox)
                    HStack(spacing: 6) {
                        TextField("2.0", text: bind(
                            { model.targetSizeMB.map { String(format: "%.1f", $0) } ?? "" },
                            { model.setTargetSizeMB(Double($0)) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 78)
                            .disabled(model.targetSizeMB == nil)
                        Text(L10n.t("settings.targetSizeUnit")).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Toggle(L10n.t("settings.allowDownscale"),
                           isOn: bind({ model.allowDownscale }, { model.setAllowDownscale($0) }))
                        .toggleStyle(.checkbox)
                        .disabled(model.targetSizeMB == nil)
                    Text(L10n.t("settings.targetSizeHint"))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                }
                }

                if model.currentFormat.kind == .video {
                    section(L10n.t("settings.fps")) {
                        Picker("", selection: bind({ model.fps }, { model.setFPS($0) })) {
                            Text(L10n.t("fps.original")).tag(0)
                            Text("60 fps").tag(60)
                            Text("30 fps").tag(30)
                            Text("24 fps").tag(24)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                section(L10n.t("settings.toolbox")) {
                    Menu {
                        Button(L10n.t("tool.mergePDF")) { Toolbox.mergePDFs() }
                        Button(L10n.t("tool.splitPDF")) { Toolbox.splitPDF() }
                        Button(L10n.t("tool.pdfImages")) { Toolbox.exportPDFImages() }
                        Button(L10n.t("tool.pdfTables")) { Toolbox.pdfTablesToExcel() }
                        Button(L10n.t("tool.imagesPDF")) { Toolbox.imagesToPDF() }
                        Divider()
                        Button(L10n.t("tool.zip")) { Toolbox.zipFiles() }
                    } label: {
                        SwiftUI.Label(L10n.t("tool.pdfzip"), systemImage: "wrench.and.screwdriver")
                    }
                }

                section(L10n.t("settings.output")) {
                    Picker("", selection: bind({ model.outputMode }, { model.setOutputMode($0) })) {
                        Text(L10n.t("settings.alongside")).tag(OutputMode.alongside)
                        Text(L10n.t("settings.custom")).tag(OutputMode.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    if model.outputMode == .custom {
                        HStack {
                            Text(model.customDirectory?.path ?? L10n.t("settings.noFolder"))
                                .font(.system(size: 10)).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Button(L10n.t("btn.choose")) { model.pickOutputDirectory() }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    // MARK: - 主区域

    private var main: some View {
        VStack(spacing: 12) {
            dropZone
            toolbar
            jobList
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(Color(red: 0.29, green: 0.47, blue: 0.98))
            Text(L10n.t("drop.title")).font(.system(size: 14, weight: .semibold))
            Text(L10n.t("drop.subtitle")).font(.system(size: 11)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(L10n.t("btn.chooseFiles")) { model.pickFiles() }
                Button(L10n.t("btn.chooseFolder")) { model.pickFolder() }
            }
            Text("\(L10n.t("status.image")) · \(model.currentFormat.title)")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.29, green: 0.47, blue: 0.98).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.29, green: 0.47, blue: 0.98).opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("\(model.pendingCount) → \(model.doneCount)")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Picker("", selection: bind({ model.maxConcurrent }, { model.setMaxConcurrent($0) })) {
                ForEach([1, 2, 3, 4, 5, 6, 8], id: \.self) { value in
                    Text("\(L10n.t("settings.parallel")) \(value)").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 96)
            Button(L10n.t("btn.clearDone")) { model.clearFinished() }
                .disabled(model.doneCount == 0 && model.jobs.isEmpty)
            Button(L10n.t("btn.clear")) { model.clearAll() }
                .disabled(model.jobs.isEmpty)
        }
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if model.jobs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray").font(.system(size: 26)).foregroundColor(.secondary)
                        Text(L10n.t("drop.subtitle")).font(.system(size: 12)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(model.jobs) { job in
                        jobRow(job)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private func jobRow(_ job: Job) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.info?.isImage == true ? "photo" : "film")
                .foregroundColor(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(job.message.isEmpty ? job.url.deletingLastPathComponent().path : job.message)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusChip(job.status)
            ProgressView(value: min(max(job.progress, 0), 1))
                .frame(width: 130)
            Text(job.status == .running ? String(format: "%.0f%%", job.progress * 100) : "")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
            if job.status == .done {
                Button(L10n.t("row.reveal")) { model.reveal(job.id) }.controlSize(.small)
            } else if job.status == .failed || job.status == .cancelled {
                Button(L10n.t("row.retry")) { model.retry(job.id) }.controlSize(.small)
            }
            Button(L10n.t("row.remove")) { model.remove(job.id) }.controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.6))
    }

    private func statusChip(_ status: Job.Status) -> some View {
        Text(status.label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color(for: status).opacity(0.14)))
            .foregroundColor(color(for: status))
    }

    private func color(for status: Job.Status) -> Color {
        switch status {
        case .done: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .running, .probing: return Color(red: 0.29, green: 0.47, blue: 0.98)
        default: return .secondary
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.summaryText).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Button(L10n.t("menu.openOutput")) { model.openOutputFolder() }
                .disabled(model.lastOutputDirectory == nil)
            if model.isRunning {
                Button(L10n.t("btn.cancel")) { model.cancel() }
                ProgressView().controlSize(.small)
            } else {
                Button(L10n.t("btn.start")) { model.start() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    }

    // MARK: - 辅助

    private func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock(); urls.append(url); lock.unlock()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { model.addFiles(urls) }
        }
    }
}
