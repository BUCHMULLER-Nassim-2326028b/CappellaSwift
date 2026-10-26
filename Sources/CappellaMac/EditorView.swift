import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import CappellaCore
import CappellaSession

private enum EditorPanel: String, Identifiable {
    case shotDetection, chooseRole, roles, importRoles, properties, find, timecode, shift, timestamp, positions, preferences, validation, scriptExport, movieExport
    var id: String { rawValue }
}

@MainActor
struct EditorView: View {
    @Binding var project: Project
    @StateObject private var transport = Transport()
    @StateObject private var commandActions = EditorActions()
    @StateObject private var projection = ProjectionController()
    @StateObject private var recorder = AudioRecorder()
    @State private var shotTask: Task<Void, Never>?
    @State private var shotProgress = 0.0
    @State private var shotThreshold = 0.25
    @State private var detectingShots = false
    @AppStorage("general.appearance") private var appearance = "light"
    @AppStorage("rythmo.closeReactions") private var closeReactions = false
    @AppStorage("video.offsetMilliseconds") private var videoOffsetMilliseconds = 0.0
    @State private var selection: UUID?
    @State private var selectedSign: UUID?
    @State private var editingPhrase = false
    @State private var originalPhrase: Cue?
    @State private var newPhrase = false
    @State private var chosenRole: UUID?
    @State private var pendingKind = "in_open"
    @State private var pendingText = ""
    @State private var assigningExisting = false
    @State private var pendingEdit = true
    @State private var currentTrack = 0
    @State private var caret = 0
    @State private var timelineWheelScroll = TimelineWheelScroll()
    @State private var detectionMode = false
    @State private var videoOnly = false
    @State private var readingMode = false
    @State private var readingLayout = ReadingLayout(project: Project())
    @State private var panel: EditorPanel?
    @State private var search = DialogueSearch()
    @State private var searchMessage = ""
    @FocusState private var searchFocused: Bool
    @State private var input = ""
    @State private var error: String?
    @State private var validationReport = ""
    @State private var scriptEntries: [ScriptEntry] = []
    @State private var orderedCues: [Cue] = []
    @State private var pendingScriptExport: ScriptExportOptions?
    @State private var lastScrolledCue: UUID?
    @State private var rolesToImport: [Role] = []
    @State private var pasteCandidate: Cue?
    @State private var pasteFrame = 0
    @State private var pasteTrack = 0
    @AppStorage("rythmo.pixelsPerSecond") private var pixelsPerSecond = 120.0
    @AppStorage("rythmo.font") private var fontName = ApplicationPreferences.defaultFontName
    @AppStorage("rythmo.fontSize") private var fontSize = 28.0
    @AppStorage("rythmo.height") private var rythmoHeight = 146.0
    @AppStorage("rythmo.grid") private var showGrid = true
    @AppStorage("rythmo.detection") private var showDetection = true
    private var frame: Int { project.mediaStartFrame + Timeline.frame(at: transport.seconds, fps: project.framesPerSecond, playing: transport.rate != 0) }
    private var selectedCue: Cue? { project.cues.first { $0.id == selection } }
    private var commandState: EditorCommandState {
        EditorCommandState(currentTrack: currentTrack, hasSelection: selection != nil, hasSign: selectedSign != nil,
                           showGrid: showGrid, showDetection: showDetection, videoOnly: videoOnly, readingMode: readingMode,
                           recording: recorder.recording, usingVI: transport.usingVI,
                           detectionMode: detectionMode, playbackRate: Double(transport.rate),
                           canUndo: ProjectSession.shared.canUndo, canRedo: ProjectSession.shared.canRedo)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    HSplitView {
                        VStack(spacing: 0) {
                            scriptPane
                            cartouche
                        }
                        .frame(minWidth: 310, idealWidth: geometry.size.width * 0.445, maxWidth: .infinity, maxHeight: .infinity)
                        Group {
                            if videoOnly || readingMode { Color.clear } else { videoPane }
                        }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    TimelineScroller(project: project, frame: frame, mediaDuration: transport.duration,
                                     viewportWidth: geometry.size.width, pixelsPerSecond: pixelsPerSecond,
                                     dark: appearance == "dark", onSeek: { target in
                        if editingPhrase { finishPhrase() }
                        transport.setRate(0)
                        seek(to: target)
                    })
                    .frame(height: NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy))
                    RythmoView(project: project, frame: frame, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize,
                               showGrid: showGrid, showDetection: showDetection, selectedSign: selectedSign, selectedTrack: currentTrack,
                               editingCue: editingPhrase ? selection : nil,
                               scrollBy: { steps in
                                   if editingPhrase { finishPhrase() }
                                   transport.setRate(0)
                                   let range = TimelineScrollRange(startFrame: project.mediaStartFrame,
                                       endFrame: TimelineScrollRange.contentEnd(in: project),
                                       framesPerSecond: project.framesPerSecond, mediaDuration: transport.duration,
                                       viewportWidth: geometry.size.width, pixelsPerSecond: pixelsPerSecond)
                                   if let target = timelineWheelScroll.target(currentFrame: frame, stepDelta: steps, range: range) {
                                       seek(to: target)
                                   }
                               },
                               selectTrack: { track in
                                   if editingPhrase { finishPhrase() }
                                   currentTrack = track; selectedSign = nil; selection = nil
                               }, moveSign: moveSign, editCue: editTimelineCue, contextMenu: phraseContextMenu)
                        .overlay(alignment: .topLeading) {
                            if editingPhrase, let cue = selectedCue {
                                timelineEditor(cue)
                            }
                        }
                        .frame(height: rythmoHeight)
                        .clipped()
                }
                .opacity(videoOnly || readingMode ? 0 : 1)
                .allowsHitTesting(!videoOnly && !readingMode)
                .accessibilityHidden(videoOnly || readingMode)
                if readingMode {
                    ReadingView(layout: readingLayout,
                        frame: Double(project.mediaStartFrame) + transport.seconds * Double(project.framesPerSecond),
                        player: transport.player, videoOffset: videoOffsetMilliseconds / 1000)
                }
                if videoOnly { videoPane.frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .background(appearance == "dark" ? Color(white: 0.13) : Color(white: 0.965))
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
        .background(EditorKeyboardMonitor(perform: perform).frame(width: 0, height: 0))
        .focusedSceneObject(commandActions)
        .onChange(of: commandState) { commandActions.state = $0 }
        .onAppear {
            rebuildScript()
            commandActions.perform = perform
            commandActions.state = commandState
            for index in project.cues.indices where project.cues[index].signs == nil { project.cues[index].signs = project.cues[index].anchors }
            if let position = project.lastPositionFrame { seek(to: position) }
            if let path = project.videoPath, FileManager.default.fileExists(atPath: path) { transport.open(URL(fileURLWithPath: path), sound: validSoundURL) }
            else if let sound = validSoundURL { transport.openSound(sound) }
            if ApplicationPreferences.load().showControlAtLaunch,
               ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_MARKER"] == nil {
                projection.showAtStartup(project: $project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
            }
            StartupSmokeCheck.recordEditorAppearance(cueCount: project.cues.count)
        }
        .onDisappear { commandActions.perform = { _ in }; transport.close(); projection.close(); shotTask?.cancel() }
        .onChange(of: project.cues) { _ in rebuildScript() }
        .onChange(of: project.loops) { _ in rebuildScript() }
        .onChange(of: project.shots) { _ in rebuildReadingLayout() }
        .onChange(of: project.roles) { _ in rebuildReadingLayout() }
        .onChange(of: project.title) { _ in rebuildReadingLayout() }
        .onChange(of: project.framesPerSecond) { _ in rebuildReadingLayout() }
        .onChange(of: pixelsPerSecond) { _ in rebuildReadingLayout() }
        .sheet(item: $panel, onDismiss: {
            guard let options = pendingScriptExport else { return }
            pendingScriptExport = nil
            exportData(type: .rtf, name: "Script.rtf") { ScriptDocument.rtf(project: project, options: options) }
        }) { activePanel in panelView(activePanel) }
        .alert("Cappella", isPresented: Binding(get: { error != nil || transport.error != nil || recorder.error != nil }, set: {
            if !$0 { error = nil; transport.error = nil; recorder.error = nil }
        })) { Button("OK") { error = nil; transport.error = nil; recorder.error = nil } } message: { Text(error ?? transport.error ?? recorder.error ?? "") }
    }

    private func rebuildReadingLayout() {
        readingLayout = ReadingLayout(project: project, pixelsPerSecond: pixelsPerSecond)
    }

    private func rebuildScript() {
        rebuildReadingLayout()
        scriptEntries = project.scriptEntries()
        orderedCues = scriptEntries.compactMap { entry in
            if case .cue(let cue) = entry { return cue }
            return nil
        }
    }

    private var scriptPane: some View {
        ScrollViewReader { proxy in
            let playback = DialogueScriptState(cues: orderedCues, frame: frame, loops: project.loops)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(scriptEntries) { entry in
                        switch entry {
                        case .loop(let marker):
                            Text("boucle " + marker.label)
                                .font(.custom("Courier New", size: 16))
                                .foregroundStyle(playback.activeLoopID == marker.id
                                    ? (appearance == "dark" ? Color(red: 1, green: 0.6, blue: 0.6) : Color(red: 0.73, green: 0.13, blue: 0.13))
                                    : (appearance == "dark" ? Color(white: 0.9) : Color(red: 0.02, green: 0.08, blue: 0.14)))
                                .padding(.horizontal, 8).padding(.top, 6)
                        case .cue(let cue):
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(Timecode.format(cue.start, fps: project.framesPerSecond)).font(.custom("Courier New", size: 9))
                                    Text("- \(roleName(cue.roleID)) :").font(.custom("Courier New", size: 12).weight(.bold))
                                }
                                Text(cue.text).font(.custom("Courier New", size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(playback.activeIDs.contains(cue.id)
                                ? (appearance == "dark" ? Color(red: 1, green: 0.6, blue: 0.6) : Color(red: 0.73, green: 0.13, blue: 0.13))
                                : (appearance == "dark" ? Color(white: 0.9) : Color(red: 0.02, green: 0.08, blue: 0.14)))
                            .padding(.vertical, 2).padding(.horizontal, 8)
                            .contentShape(Rectangle()).id(cue.id)
                            .onTapGesture(count: 2) { select(cue, edit: true) }
                            .onTapGesture { select(cue, edit: false) }
                            .overlay {
                                GeometryReader { geometry in
                                    TimelineContextMenu(menuAt: { _ in phraseContextMenu(cue.id, nil) }, textRects: [CGRect(origin: .zero, size: geometry.size)])
                                }
                            }
                        }
                    }
                }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(appearance == "dark" ? Color(white: 0.13) : Color(red: 0.965, green: 0.968, blue: 0.977))
            .onChange(of: selection) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: frame) { ProjectSession.shared.currentFrame = $0 }
            .onChange(of: playback.followID) { id in
                guard !editingPhrase, let id, id != lastScrolledCue else { return }
                lastScrolledCue = id; proxy.scrollTo(id, anchor: .center)
            }
            .onAppear {
                guard let id = playback.followID else { return }
                lastScrolledCue = id; proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var videoPane: some View {
        ZStack {
            Color.white
            if transport.mediaName != nil {
                NativeVideoView(player: transport.player, timeOffset: videoOffsetMilliseconds / 1000)
            } else if let image = Self.mire {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
        .overlay {
            if transport.preparingAudio { ProgressView("Préparation des pistes audio…").padding(14).background(.regularMaterial).cornerRadius(8) }
        }
        .contextMenu { Button("Ouvrir l'image…") { perform(.openMedia) } }
    }
    private static let mire = Bundle.main.url(forResource: "Mire", withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }

    private var cartouche: some View {
        GeometryReader { geometry in
            let dark = appearance == "dark"
            let mutedInk = dark ? Color(white: 0.70) : Color.gray
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("timecode").font(.system(size: 10))
                        Text(Timecode.format(frame, fps: project.framesPerSecond)).font(.system(size: 28, weight: .light)).monospacedDigit()
                    }.onTapGesture { perform(.goTimecode) }
                    if let loop = currentLoop {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("boucle").font(.system(size: 10)); Text(loop.marker.label).font(.system(size: 20, weight: .light))
                            Text("     durée").font(.system(size: 10))
                            Text("\(loop.duration / (project.framesPerSecond * 60))").font(.system(size: 20, weight: .light))
                            Text("min").font(.system(size: 10))
                            Text("\((loop.duration / project.framesPerSecond) % 60)").font(.system(size: 20, weight: .light))
                            Text("s").font(.system(size: 10))
                        }
                    } else { Spacer(minLength: 0) }
                    HStack {
                        if let loop = currentLoop {
                            Text("\(Timecode.format(loop.marker.frame, fps: project.framesPerSecond)) → \(Timecode.format(loop.end, fps: project.framesPerSecond))")
                        }
                        Spacer()
                        Button("VO") { if transport.usingVI { transport.toggleVI() } }.foregroundColor(!transport.usingVI ? .white : mutedInk)
                        Button("VI") { if !transport.usingVI { transport.toggleVI() } }.foregroundColor(transport.usingVI ? .white : mutedInk)
                        Spacer()
                    }.font(.system(size: 10)).foregroundStyle(dark ? Color(white: 0.78) : Color(red: 0.43, green: 0.53, blue: 0.59)).buttonStyle(.plain)
                }
                .padding(.horizontal, 7).padding(.vertical, 7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white).background(dark ? Color(white: 0.09) : Color(red: 0.14, green: 0.17, blue: 0.20))
                (dark ? Color(white: 0.13) : Color(white: 0.93)).frame(width: geometry.size.width * 0.19)
            }
        }.frame(height: 92).overlay(alignment: .top) { Rectangle().fill(appearance == "dark" ? Color.white.opacity(0.18) : Color.gray).frame(height: 0.5) }
    }

    private var currentLoop: (marker: Marker, end: Int, duration: Int)? {
        let loops = project.loops.sorted { $0.frame < $1.frame }
        guard let index = loops.lastIndex(where: { $0.frame <= frame }) else { return nil }
        let end = index + 1 < loops.count ? loops[index + 1].frame : max(project.cues.map(\.end).max() ?? loops[index].frame, project.mediaStartFrame + Int(transport.duration * Double(project.framesPerSecond)))
        return (loops[index], end, max(0, end - loops[index].frame))
    }

    private func timelineEditor(_ cue: Cue) -> some View {
        GeometryReader { geometry in
            let scale = CGFloat(pixelsPerSecond / Double(project.framesPerSecond))
            let left = max(0, geometry.size.width / 2 + CGFloat(cue.start - frame) * scale)
            let width = DialogueTextEditor.fittingWidth(cue.text, fontName: fontName, fontSize: fontSize)
            let textScale: CGFloat = cue.pendingEnd == true ? 1 : max(1, CGFloat(cue.end - cue.start) * scale) / max(1, width - 8)
            DialogueTextEditor(text: Binding(get: { selectedCue?.text ?? "" }, set: { value in
                mutateSelected { $0.editText(value) }
            }), caret: $caret, fontName: fontName, fontSize: fontSize, underlined: cue.voice == "off", menuProvider: { phraseContextMenu(cue.id, nil) })
                .frame(width: width, height: geometry.size.height / 4 - 2)
                .scaleEffect(x: textScale, y: 1, anchor: .leading)
                .offset(x: left, y: CGFloat(cue.track) * geometry.size.height / 4 + 1)
                .id(cue.id)
        }
    }

    @ViewBuilder private func panelView(_ active: EditorPanel) -> some View {
        switch active {
        case .shotDetection:
            VStack(alignment: .leading, spacing: 15) {
                Text("Détection des changements de plan").font(.headline)
                Picker("Type de programme", selection: $shotThreshold) {
                    Text("Prises de vues réelles").tag(0.25)
                    Text("Dessin animé").tag(0.40)
                }.disabled(detectingShots)
                HStack { Text("Seuil"); Slider(value: $shotThreshold, in: 0.05...0.75).disabled(detectingShots); Text(shotThreshold.formatted(.number.precision(.fractionLength(2)))) }
                if detectingShots { ProgressView(value: shotProgress) }
                Text("Les plans détectés remplaceront les repères de plan actuels après l'analyse.").font(.caption)
                HStack {
                    Button("Annuler") { shotTask?.cancel(); detectingShots = false; panel = nil }.keyboardShortcut(.cancelAction)
                    Spacer(); Button("Lancer", action: detectShots).disabled(detectingShots).keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 480).interactiveDismissDisabled(detectingShots)
        case .roles: RolesPanel(project: $project)
        case .importRoles: RoleImportPanel(project: $project, candidates: rolesToImport)
        case .properties: PropertiesPanel(project: $project, applyFiles: { old in
            if old.videoPath != project.videoPath || old.audioPath != project.audioPath {
                let position = transport.seconds
                transport.close()
                transport.seek(seconds: position)
                if let path = project.videoPath, FileManager.default.fileExists(atPath: path) {
                    transport.open(URL(fileURLWithPath: path), sound: validSoundURL)
                } else if let sound = validSoundURL { transport.openSound(sound) }
            }
        })
        case .chooseRole:
            VStack(alignment: .leading, spacing: 12) {
                Text("Attribuer la phrase à un rôle").font(.headline)
                HStack(alignment: .top, spacing: 16) {
                    List(project.roles, selection: $chosenRole) { role in
                        Text(role.name).foregroundStyle(roleReadingColor(role, dark: appearance == "dark")).tag(role.id)
                            .onTapGesture(count: 2) { chosenRole = role.id; confirmRole() }
                    }.frame(minWidth: 240)
                    VStack(spacing: 10) {
                        RolePortrait(role: project.roles.first { $0.id == chosenRole })
                        Text(project.roles.first { $0.id == chosenRole }?.name ?? "Sélectionner un rôle")
                            .font(.caption).multilineTextAlignment(.center)
                    }.frame(width: 140)
                }
                HStack {
                    Button("Nouveau…") {
                        if let name = prompt("Nom du rôle", initial: ""), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           !project.roles.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                            let role = Role(name: name, color: project.roles.count); project.roles.append(role); chosenRole = role.id
                        }
                    }
                    Button("Annuler") { pasteCandidate = nil; panel = nil }.keyboardShortcut(.cancelAction)
                    Spacer(); Button("OK", action: confirmRole).keyboardShortcut(.defaultAction).disabled(chosenRole == nil)
                }
            }.padding(18).frame(width: 460, height: 360)
        case .find:
            VStack(alignment: .leading, spacing: 18) {
                Text("Rechercher").font(.title3).fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rechercher").font(.subheadline)
                    TextField("Texte à rechercher", text: $search.text)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused).accessibilityLabel("Rechercher")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pour").font(.subheadline)
                    Picker("Pour", selection: $search.roleID) {
                        Text("Tous les rôles").tag(Optional<UUID>.none)
                        ForEach(project.roles) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options").font(.caption).foregroundColor(.secondary)
                    Toggle("Respecter la casse", isOn: $search.caseSensitive)
                    Toggle("Mot entier", isOn: $search.wholeWord)
                }.toggleStyle(.checkbox)
                Text(searchMessage.isEmpty ? " " : searchMessage)
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                Divider()
                HStack(spacing: 8) {
                    Spacer()
                    Button("Annuler") { panel = nil }.keyboardShortcut(.cancelAction)
                    Button("Suivant", action: findNext).keyboardShortcut(.defaultAction).disabled(search.text.isEmpty)
                }
            }
            .padding(24).frame(width: 400)
            .onAppear {
                searchMessage = ""; searchFocused = true
                if let id = search.roleID, !project.roles.contains(where: { $0.id == id }) { search.roleID = nil }
            }
            .onChange(of: search) { _ in searchMessage = "" }
        case .timecode, .timestamp, .shift:
            VStack(alignment: .leading, spacing: 16) {
                Text(active == .timecode ? "Aller au timecode" : active == .timestamp ? "Timestamp de l'image" : "Décaler la rythmo").font(.headline)
                TextField(active == .shift ? "Décalage en images (+ ou −)" : "HH:MM:SS:II", text: $input).onSubmit(applyInput)
                if active == .timestamp { Text("Les phrases, signes, boucles et plans sont décalés avec l'origine vidéo.").font(.caption) }
                HStack { Button("Annuler") { panel = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Appliquer", action: applyInput).keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width: 420)
        case .positions:
            VStack {
                Text("Positions mémorisées").font(.headline)
                List(project.positions ?? []) { marker in
                    HStack {
                        Button("\(Timecode.format(marker.frame, fps: project.framesPerSecond)) - \(marker.label)") { seek(to: marker.frame); panel = nil }.buttonStyle(.plain)
                        Spacer(); Button("Supprimer", role: .destructive) { project.positions?.removeAll { $0.id == marker.id } }
                    }
                }
                Button("Fermer") { panel = nil }.keyboardShortcut(.cancelAction)
            }.padding().frame(width: 500, height: 340)
        case .movieExport:
            RythmoMoviePanel(project: project, pixelsPerSecond: pixelsPerSecond,
                videoOffset: videoOffsetMilliseconds / 1000,
                options: RythmoMovieOptions(project: project, mediaDuration: transport.duration, international: transport.usingVI))
        case .scriptExport:
            ScriptExportPanel(roles: project.roles) { options in
                pendingScriptExport = options
                panel = nil
            }
        case .preferences: PreferencesPanel()
        case .validation:
            VStack {
                Text("Vérification de la rythmo").font(.headline)
                ScrollView { Text(validationReport).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Fermer") { panel = nil }.keyboardShortcut(.defaultAction)
            }.padding(20).frame(width: 580, height: 380)
        }
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .recordAudio: recorder.toggle()
        case .detectShots: panel = .shotDetection
        case .openMedia: chooseMedia(audio: false)
        case .openVI: chooseMedia(audio: true)
        case .importDetX: importDetX()
        case .importRoles:
            let picker = NSOpenPanel(); picker.allowedContentTypes = [.detx, .xml]
            guard picker.runModal() == .OK, let url = picker.url else { return }
            do { rolesToImport = try DetX.read(Data(contentsOf: url), fps: project.framesPerSecond).roles; if project.metadata == nil { project.metadata = [:] }; project.metadata?["roles-file"] = url.path; panel = .importRoles }
            catch { self.error = error.localizedDescription }
        case .exportDetX: exportData(type: .detx, name: "\(project.title).detx") { try DetX.write(project) }
        case .exportMovie:
            if !readingMode { perform(.readingMode) }
            transport.setRate(0); panel = .movieExport
        case .exportScript: panel = .scriptExport
        case .exportCrossTable: exportData(type: .commaSeparatedText, name: "Croisille.csv") { Data(project.crossTableCSV().utf8) }
        case .changeRole:
            pasteCandidate = nil
            guard let cue = selectedCue else { return }
            assigningExisting = true; chosenRole = cue.roleID; panel = .chooseRole
        case .roles:
            pasteCandidate = nil
            if editingPhrase { assigningExisting = true; chosenRole = selectedCue?.roleID; panel = .chooseRole }
            else { panel = .roles }
        case .properties: panel = .properties
        case .find: showSearch()
        case .goTimecode: input = Timecode.format(frame, fps: project.framesPerSecond); panel = .timecode
        case .shift: input = "0"; panel = .shift
        case .timestamp: transport.setRate(0); if editingPhrase { finishPhrase() }; input = Timecode.format(project.mediaStartFrame, fps: project.framesPerSecond); panel = .timestamp
        case .preferences: panel = .preferences
        case .check: verify()
        case .undo:
            transport.setRate(0); ProjectSession.shared.undo()
            editingPhrase = false; originalPhrase = nil; newPhrase = false
            if selectedCue == nil { selection = nil; selectedSign = nil }
        case .redo:
            transport.setRate(0); ProjectSession.shared.redo()
            editingPhrase = false; originalPhrase = nil; newPhrase = false
            if selectedCue == nil { selection = nil; selectedSign = nil }
        case .playPause: startShuttle(transport.rate == 0 ? 1 : 0)
        case .stop: transport.setRate(0); project.lastPositionFrame = frame
        case .step(let amount): transport.setRate(0); seek(to: frame + amount)
        case .rate(let value): startShuttle(Double(transport.rate == value ? 0 : value))
        case .shuttle(let value): startShuttle(value)
        case .jog(let direction): startShuttle(PlaybackControls.jogSpeed * Double(direction))
        case .navigate(let type, let direction): navigate(type, direction: direction)
        case .copyPhrase: copyPhrase(cut: false)
        case .cutPhrase: copyPhrase(cut: true)
        case .pastePhrase: pastePhrase()
        case .jumpAnchor(let direction):
            guard let cue = selectedCue else { return }
            let signs = cue.anchors
            let next = direction > 0 ? signs.first(where: { $0.textOffset > caret }) : signs.last(where: { $0.textOffset < caret })
            if let next { caret = next.textOffset; selectedSign = next.id; seek(to: next.frame) }
        case .addPhrase: pendingEdit = true; addPhrase(kind: "in_open")
        case .deleteSelection:
            if let cue = selectedCue, let id = selectedSign,
               let index = cue.anchors.firstIndex(where: { $0.id == id }),
               index > 0, index < cue.anchors.count - 1 { perform(.deleteSign) }
            else { perform(.deletePhrase) }
        case .deletePhrase:
            ProjectEditing.deletePhrase(in: &project, id: selection)
            selection = nil; selectedSign = nil; editingPhrase = false
        case .track(let value):
            if editingPhrase { finishPhrase() }
            currentTrack = min(3, max(0, value))
            selection = project.cues.last(where: { $0.track == currentTrack && $0.start <= frame && $0.end >= frame })?.id
            selectedSign = nil
        case .moveTrack(let value):
            guard let id = selection else { return }
            do { try ProjectEditing.movePhrase(in: &project, id: id, track: value); currentTrack = value }
            catch { self.error = error.localizedDescription }
        case .relativeTrack(let delta): perform(.track(currentTrack + delta))
        case .findNext: findNext()
        case .cancelPhrase:
            if readingMode { readingMode = false } else if videoOnly { videoOnly = false } else { cancelPhrase() }
        case .reaction(let text):
            if closeReactions {
                pendingText = text; pendingEdit = false; addPhrase(kind: "in_open")
            } else if newPhrase, selectedCue?.text == text { setBoundary(start: false, kind: "out_open"); finishPhrase() }
            else { pendingText = text; pendingEdit = false; addPhrase(kind: "in_open") }
        case .detachSigns:
            mutateSelected { ProjectEditing.detachAllSigns(in: &$0) }
        case .detachSign:
            guard let id = selectedSign else { return }
            mutateSelected { Timeline.detachSign(in: &$0, id: id) }
        case .changeSignType(let kind):
            guard let id = selectedSign else { return }
            mutateSelected { Timeline.changeSignType(in: &$0, id: id, kind: kind) }
        case .shiftAnchor(let delta):
            mutateSelected { Timeline.shiftTextAnchor(in: &$0, id: selectedSign, by: delta) }
        case .mode:
            if let cue = selectedCue, cue.pendingEnd == true {
                transport.setRate(0)
                do {
                    try ProjectEditing.finalizePhrase(in: &project, id: cue.id, frame: frame)
                    finishPhrase()
                } catch { self.error = error.localizedDescription }
            } else if editingPhrase {
                finishPhrase()
            } else if let cue = project.cues.last(where: { $0.track == currentTrack && $0.start <= frame && $0.end >= frame }) {
                selection = cue.id; if !newPhrase { originalPhrase = cue }
                beginEditing(cue, at: frame)
            } else { pendingEdit = true; addPhrase(kind: "in_open") }
        case .addSign(let kind): addSign(kind)
        case .deleteSign:
            guard let cue = selectedCue, let id = selectedSign, let index = cue.anchors.firstIndex(where: { $0.id == id }) else { return }
            guard index > 0, index < cue.anchors.count - 1 else { error = "Les signes de début et de fin délimitent la phrase. Supprimez la phrase pour les retirer."; return }
            mutateSelected { $0.signs?.removeAll { $0.id == id } }; selectedSign = nil
        case .shiftSign(let amount):
            if let cue = selectedCue, let sign = cue.anchors.first(where: { $0.id == selectedSign }) { moveSign(cue.id, sign.id, sign.frame + amount) }
        case .voiceOff: mutateSelected { $0.voice = $0.voice == "off" ? nil : "off" }
        case .addLoop: ProjectEditing.addMarker(in: &project, frame: frame, loop: true)
        case .addShot: ProjectEditing.addMarker(in: &project, frame: frame, loop: false)
        case .markPosition:
            if let label = prompt("Marquer cette position", initial: "Position \((project.positions?.count ?? 0) + 1)") {
                if project.positions == nil { project.positions = [] }
                project.positions?.append(Marker(frame: frame, label: label))
            }
        case .positions: panel = .positions
        case .zoom(let factor): pixelsPerSecond = min(800, max(15, pixelsPerSecond * factor))
        case .grid: showGrid.toggle()
        case .detection: showDetection.toggle()
        case .readingMode:
            if editingPhrase { finishPhrase() }
            videoOnly = false; readingMode.toggle(); rebuildReadingLayout()
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        case .fullScreen:
            readingMode = false
            if editingPhrase { finishPhrase() }
            videoOnly.toggle()
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        case .projection: projection.show(project: $project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
        case .toggleVI: transport.toggleVI()
        case .mute: transport.toggleMute()
        case .volume(let delta): transport.changeVolume(delta)
        }
    }

    private func phraseContextMenu(_ cueID: UUID, _ signID: UUID?) -> NSMenu? {
        guard let cue = project.cues.first(where: { $0.id == cueID }) else { return nil }
        if editingPhrase && selection != cueID { finishPhrase() }
        selection = cueID; currentTrack = cue.track; selectedSign = signID
        let sign = cue.anchors.first { $0.id == signID }
        return PhraseContextMenu.make(cue: cue, sign: sign, perform: perform)
    }

    private func mutateSelected(_ change: (inout Cue) -> Void) {
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        change(&project.cues[index])
    }
    private func roleName(_ id: UUID?) -> String { project.roles.first { $0.id == id }?.name ?? "Sans rôle" }
    private func seek(to target: Int) {
        let value = max(project.mediaStartFrame, target)
        transport.seek(frame: value - project.mediaStartFrame, fps: project.framesPerSecond)
    }
    private func select(_ cue: Cue, edit: Bool) {
        if editingPhrase && selection != cue.id { finishPhrase() }
        selection = cue.id; currentTrack = cue.track; selectedSign = nil
        seek(to: cue.start)
        if edit { beginEditing(cue, at: cue.start) }
    }
    private func beginEditing(_ cue: Cue, at target: Int) {
        transport.setRate(0)
        if !editingPhrase || selection != cue.id {
            ProjectSession.shared.endEditingGroup(); ProjectSession.shared.beginEditingGroup()
            originalPhrase = cue; newPhrase = false
        }
        selection = cue.id; currentTrack = cue.track; selectedSign = nil
        caret = Timeline.textOffset(in: cue, at: target)
        editingPhrase = true; detectionMode = false
    }
    private func editTimelineCue(_ id: UUID, _ target: Int) {
        guard let cue = project.cues.first(where: { $0.id == id }) else { return }
        beginEditing(cue, at: target)
    }
    private func addPhrase(kind: String) {
        transport.setRate(0)
        pasteCandidate = nil; assigningExisting = false; pendingKind = kind; chosenRole = selectedCue?.roleID ?? project.roles.first?.id
        panel = .chooseRole
    }
    private func confirmRole() {
        guard let role = chosenRole else { return }
        if assigningExisting { mutateSelected { $0.roleID = role }; assigningExisting = false; panel = nil; return }
        if let candidate = pasteCandidate {
            do {
                let cue = try ProjectEditing.paste(candidate, into: &project, frame: pasteFrame, track: pasteTrack, roleID: role)
                selection = cue.id; selectedSign = nil; pasteCandidate = nil; panel = nil
            } catch { self.error = error.localizedDescription }
            return
        }
        ProjectSession.shared.beginEditingGroup()
        let cue: Cue
        do { cue = try ProjectEditing.createPhrase(in: &project, role: role, frame: frame, track: currentTrack, text: pendingText, kind: pendingKind) }
        catch { ProjectSession.shared.endEditingGroup(); self.error = error.localizedDescription; return }
        selection = cue.id; selectedSign = nil
        originalPhrase = nil; newPhrase = true; editingPhrase = pendingEdit; detectionMode = !pendingEdit
        caret = cue.text.unicodeScalars.count
        let autoClose = closeReactions && !pendingText.isEmpty && !pendingEdit
        pendingText = ""; panel = nil
        if autoClose {
            try? ProjectEditing.finalizePhrase(in: &project, id: cue.id, frame: cue.end)
            finishPhrase()
        }
    }
    private func finishPhrase() {
        ProjectSession.shared.endEditingGroup()
        editingPhrase = false; detectionMode = true; originalPhrase = nil; newPhrase = false
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
    }
    private func cancelPhrase() {
        ProjectSession.shared.cancelEditingGroup()
        if selectedCue == nil { selection = nil; selectedSign = nil }
        finishPhrase()
    }
    private func setBoundary(start: Bool, kind: String?) {
        if !start, let id = selection {
            do { try ProjectEditing.finalizePhrase(in: &project, id: id, frame: frame, kind: kind ?? "out_open") }
            catch { self.error = error.localizedDescription }
            return
        }
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        do {
            guard (start ? frame < project.cues[index].end : frame > project.cues[index].start) else { throw ProjectError.invalid("La fin doit suivre le début.") }
            let signs = project.cues[index].anchors
            let boundary = signs[start ? 0 : signs.count - 1]
            Timeline.moveSign(in: &project.cues[index], id: boundary.id, to: frame)
            if let kind {
                var signs = project.cues[index].anchors
                signs[start ? 0 : signs.count - 1].kind = kind; project.cues[index].signs = signs
            }
        } catch { self.error = error.localizedDescription }
    }
    private func addSign(_ kind: String) {
        if kind.hasPrefix("in_") { pendingEdit = false; addPhrase(kind: kind); return }
        if kind.hasPrefix("out_") { setBoundary(start: false, kind: kind); finishPhrase(); return }
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        do {
            let offset = editingPhrase ? min(caret, project.cues[index].text.unicodeScalars.count) : Timeline.textOffset(in: project.cues[index], at: frame)
            try Timeline.addSign(to: &project.cues[index], kind: kind, frame: frame, textOffset: offset)
            selectedSign = project.cues[index].signs?.first { $0.frame == frame && $0.kind == kind }?.id
        } catch { self.error = error.localizedDescription }
    }
    private func moveSign(_ cueID: UUID, _ signID: UUID, _ target: Int) {
        guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else { return }
        currentTrack = project.cues[index].track
        selection = cueID; selectedSign = signID
        Timeline.moveSign(in: &project.cues[index], id: signID, to: target)
    }
    private func startShuttle(_ rate: Double) {
        if editingPhrase { finishPhrase() }
        transport.setRate(Float(rate))
    }
    private func navigate(_ type: String, direction: Int) {
        if editingPhrase { finishPhrase() }
        transport.setRate(0)
        guard let destination = ControlNavigation.destination(in: project, kind: type, direction: direction,
            from: frame, selection: selection, mediaDuration: transport.duration) else { return }
        seek(to: destination.frame)
        selectedSign = destination.signID
        if let id = destination.cueID, let track = destination.track {
            selection = id; currentTrack = track
        }
    }
    private func showSearch() {
        transport.setRate(0)
        if editingPhrase { finishPhrase() }
        searchMessage = ""
        panel = .find
    }
    private func findNext() {
        guard !search.text.isEmpty else { showSearch(); return }
        transport.setRate(0)
        if editingPhrase { finishPhrase() }
        guard let cue = search.next(in: project.cues, after: frame, selection: selection) else {
            if panel == .find { searchMessage = "Aucune phrase trouvée." }
            else { error = "Aucune phrase trouvée." }
            return
        }
        searchMessage = ""
        select(cue, edit: false)
    }
    private func applyInput() {
        do {
            if panel == .shift {
                guard let value = Int(input) else { throw ProjectError.invalid("Saisir un décalage entier en images.") }
                try project.shift(by: value)
            } else {
                guard let value = Timecode.parse(input, fps: project.framesPerSecond) else { throw ProjectError.invalid("Timecode invalide : HH:MM:SS:II.") }
                if panel == .timestamp { try project.shift(by: value - project.mediaStartFrame, includingMediaOrigin: true) }
                else { seek(to: value) }
            }
            panel = nil
        } catch { self.error = error.localizedDescription }
    }
    private func detectShots() {
        guard let path = project.videoPath, FileManager.default.fileExists(atPath: path) else { error = "Ouvrez d'abord le fichier image."; return }
        transport.setRate(0); detectingShots = true; shotProgress = 0
        let url = URL(fileURLWithPath: path), fps = project.framesPerSecond, threshold = shotThreshold
        let origin = project.mediaStartFrame
        shotTask = Task {
            do {
                let worker = Task.detached {
                    try await ShotDetector.detect(url: url, fps: fps, threshold: threshold) { value in
                        Task { @MainActor in shotProgress = value }
                    }
                }
                let frames = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                project.shots = frames.enumerated().map { Marker(frame: origin + $0.element, label: String($0.offset + 1)) }
                detectingShots = false; panel = nil
            } catch is CancellationError { detectingShots = false }
            catch { detectingShots = false; self.error = error.localizedDescription }
        }
    }
    private var validSoundURL: URL? {
        guard let path = project.audioPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
    private func copyPhrase(cut: Bool) {
        guard let cue = selectedCue, let data = try? JSONEncoder().encode(cue) else { return }
        let board = NSPasteboard.general; board.clearContents()
        guard board.setData(data, forType: NSPasteboard.PasteboardType(ProjectEditing.phraseClipboardType)) else { error = "Copie de la phrase impossible."; return }
        board.setString(cue.text, forType: .string)
        if cut { perform(.deletePhrase) }
    }
    private func pastePhrase() {
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(ProjectEditing.phraseClipboardType))
                ?? NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("org.cappella-rewrite.phrase")),
              let cue = try? JSONDecoder().decode(Cue.self, from: data) else { return }
        if editingPhrase { finishPhrase() }
        transport.setRate(0)
        do { try ProjectEditing.validatePaste(cue, in: project, frame: frame, track: currentTrack) }
        catch { self.error = error.localizedDescription; return }
        pasteFrame = frame; pasteTrack = currentTrack
        pasteCandidate = cue
        chosenRole = project.roles.contains(where: { $0.id == cue.roleID }) ? cue.roleID : project.roles.first?.id
        assigningExisting = false; panel = .chooseRole
    }
    private func chooseMedia(audio: Bool) {
        let picker = NSOpenPanel(); picker.allowedContentTypes = audio ? [.audio] : [.movie]; picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        if audio { transport.openSound(url); project.audioPath = url.path }
        else { transport.open(url, sound: validSoundURL); project.videoPath = url.path }
    }
    private func importDetX() { ProjectSession.shared.chooseOpen() }
    private func exportData(type: UTType, name: String, data: () throws -> Data) {
        do {
            let contents = try data()
            let picker = NSSavePanel(); picker.allowedContentTypes = [type]; picker.nameFieldStringValue = name
            guard picker.runModal() == .OK, let url = picker.url else { return }
            try contents.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    private func verify() {
        do {
            validationReport = try ProjectVerification.report(for: project)
        } catch { validationReport = error.localizedDescription }
        panel = .validation
    }
    private func prompt(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

@MainActor
private final class ProjectionController: ObservableObject {
    private var window: NSWindow?
    private static var didShowAtStartup = false
    func showAtStartup(project: Binding<Project>, transport: Transport, pixelsPerSecond: Double, fontName: String, fontSize: Double) {
        guard !Self.didShowAtStartup else { return }
        Self.didShowAtStartup = true
        show(project: project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
    }
    func show(project: Binding<Project>, transport: Transport, pixelsPerSecond: Double, fontName: String, fontSize: Double) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let view = ProjectionView(project: project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Cappella - Écran de contrôle"; window.styleMask.insert([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 1000, height: 650))
        if NSScreen.screens.count > 1, let screen = NSScreen.screens.last { window.setFrame(screen.visibleFrame, display: false) }
        else { window.center() }
        self.window = window; window.makeKeyAndOrderFront(nil)
    }
    func close() { window?.close(); window = nil }
}
private struct ProjectionView: View {
    @Binding var project: Project
    @ObservedObject var transport: Transport
    var pixelsPerSecond: Double
    var fontName: String
    var fontSize: Double
    @State private var video = AVPlayer()
    var body: some View {
        VStack(spacing: 0) {
            NativeVideoView(player: video)
            RythmoView(project: project, frame: project.mediaStartFrame + Int(transport.seconds * Double(project.framesPerSecond)),
                       pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize,
                       showGrid: true, showDetection: true, selectedSign: nil).frame(height: 160)
        }.frame(minWidth: 700, minHeight: 450)
        .onAppear(perform: attachVideo)
        .onChange(of: transport.mediaID) { _ in attachVideo() }
        .onChange(of: transport.rate) { rate in
            if rate > 0 { video.playImmediately(atRate: rate) } else { video.pause() }
        }
        .onChange(of: transport.seconds) { seconds in
            let time = video.currentTime().seconds
            if transport.rate <= 0 || !time.isFinite || abs(time - seconds) > 0.08 {
                video.seek(to: CMTime(seconds: seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        .onDisappear { video.pause() }
    }
    private func attachVideo() {
        video.pause(); video.isMuted = true
        video.replaceCurrentItem(with: transport.player.currentItem.map { AVPlayerItem(asset: $0.asset) })
        video.seek(to: CMTime(seconds: transport.seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
        if transport.rate > 0 { video.playImmediately(atRate: transport.rate) }
    }
}
