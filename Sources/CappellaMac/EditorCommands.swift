import SwiftUI
import AppKit
import CappellaSession

func cappellaFunctionKey(_ number: Int) -> KeyEquivalent {
    KeyEquivalent(Character(UnicodeScalar(0xF704 + number - 1)!))
}

enum EditorAction {
    case openMedia, openVI, importDetX, importRoles, exportDetX, exportScript, exportCrossTable, exportMovie
    case roles, changeRole, properties, find, goTimecode, shift, timestamp, check, preferences
    case undo, redo
    case playPause, stop, step(Int), rate(Float), shuttle(Double), jog(Int), navigate(String, Int)
    case addPhrase, deletePhrase, deleteSelection, track(Int), mode, addSign(String), deleteSign, shiftSign(Int), voiceOff
    case addLoop, addShot, markPosition, positions, zoom(Double), grid, detection, fullScreen, projection, readingMode
    case toggleVI, mute, volume(Float), recordAudio, detectShots
    case detachSign, changeSignType(String)
    case moveTrack(Int), relativeTrack(Int), cancelPhrase, findNext, reaction(String), shiftAnchor(Int), detachSigns, jumpAnchor(Int), copyPhrase, cutPhrase, pastePhrase
}

/// Only state that affects the menus belongs here; the playback clock does not.
struct EditorCommandState: Equatable {
    var currentTrack = 0
    var hasSelection = false
    var hasSign = false
    var showGrid = true
    var showDetection = true
    var videoOnly = false
    var readingMode = false
    var recording = false
    var usingVI = false
    var detectionMode = false
    var playbackRate = 0.0
    var canUndo = false
    var canRedo = false
}

/// One stable object per document prevents each video frame from publishing a
/// new focused command value and rebuilding SwiftUI's menu hierarchy.
final class EditorActions: ObservableObject {
    var perform: (EditorAction) -> Void = { _ in }
    @Published var state = EditorCommandState()
    var hasSelection: Bool { state.hasSelection }
    var hasSign: Bool { state.hasSign }
    var showGrid: Bool { state.showGrid }
    var videoOnly: Bool { state.videoOnly }
    var showDetection: Bool { state.showDetection }
    var recording: Bool { state.recording }
    var usingVI: Bool { state.usingVI }
    var detectionMode: Bool { state.detectionMode }
}

@MainActor
struct CappellaCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var editor: EditorActions?
    private func run(_ action: EditorAction) { editor?.perform(action) }
    var body: some Commands {
        let _ = ExternalFileOpenRouter.shared.installWindowOpener { openWindow(id: "editor") }
        CappellaFileCommands()
        CommandGroup(replacing: .undoRedo) {
            Button("Annuler") { run(.undo) }.keyboardShortcut("z", modifiers: .command).disabled(editor?.state.canUndo != true)
            Button("Rétablir") { run(.redo) }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(editor?.state.canRedo != true)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Rechercher…") { run(.find) }.keyboardShortcut("f", modifiers: .control)
            Menu("Piste") {
                Button("Piste précédente") { run(.relativeTrack(-1)) }.keyboardShortcut(.upArrow, modifiers: .control).disabled(editor?.state.currentTrack == 0)
                Button("Piste suivante") { run(.relativeTrack(1)) }.keyboardShortcut(.downArrow, modifiers: .control).disabled(editor?.state.currentTrack == 3)
                Divider()
                ForEach(0..<4) { track in Button("Piste \(track + 1)") { run(.track(track)) }.keyboardShortcut(cappellaFunctionKey(5 + track), modifiers: []) }
            }
            Menu("Ajouter un signe") {
                Button("Début de phrase ouverte") { run(.addSign("in_open")) }.keyboardShortcut("2", modifiers: [])
                Button("Fin de phrase ouverte") { run(.addSign("out_open")) }.keyboardShortcut("3", modifiers: [])
                Button("Début de phrase fermée") { run(.addSign("in_close")) }.keyboardShortcut("2", modifiers: .control)
                Button("Fin de phrase fermée") { run(.addSign("out_close")) }.keyboardShortcut("3", modifiers: .control)
                Divider()
                Button("Labiale m,b,p") { run(.addSign("mpb")) }.keyboardShortcut("4", modifiers: [])
                Button("Demi-labiale f,v,r") { run(.addSign("fvr")) }.keyboardShortcut("5", modifiers: [])
                Button("Neutre") { run(.addSign("neutral")) }.keyboardShortcut("6", modifiers: [])
                Button("Cul de poule w, eu, que") { run(.addSign("weuque")) }.keyboardShortcut("9", modifiers: [])
                Button("Grande ouverture A") { run(.addSign("a")) }.keyboardShortcut("7", modifiers: [])
                Button("Ouverture en rond O") { run(.addSign("o")) }.keyboardShortcut("8", modifiers: [])
                Divider()
                Button("Boucle") { run(.addLoop) }.keyboardShortcut("0", modifiers: [])
                Button("Changement de plan") { run(.addShot) }.keyboardShortcut("1", modifiers: [])
            }
            Button("Déplacer le signe à gauche") { run(.shiftSign(-1)) }.keyboardShortcut(.leftArrow, modifiers: .control).disabled(editor?.hasSign != true)
            Button("Déplacer le signe à droite") { run(.shiftSign(1)) }.keyboardShortcut(.rightArrow, modifiers: .control).disabled(editor?.hasSign != true)
            Button("Supprimer le signe") { run(.deleteSign) }.keyboardShortcut(.deleteForward, modifiers: []).disabled(editor?.hasSign != true)
            Divider()
            Button("Décrocher tous les signes") { run(.detachSigns) }.keyboardShortcut("d", modifiers: [.control, .shift])
            Divider()
            Button("Mode Édition / Mode Détection") { run(.mode) }.keyboardShortcut(.return, modifiers: [])
            Button("Annuler la phrase") { run(.cancelPhrase) }.keyboardShortcut(.escape, modifiers: [])
            Button("Nouvelle phrase") { run(.addPhrase) }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Supprimer la phrase") { run(.deletePhrase) }.keyboardShortcut(.deleteForward, modifiers: [.control])
                .disabled(editor?.hasSelection != true)
            Button("Voix off") { run(.voiceOff) }.keyboardShortcut("u", modifiers: .control).disabled(editor?.hasSelection != true)
            Button("Rôles…") { run(.roles) }.keyboardShortcut("r", modifiers: .control)
            Menu("Déplacer la phrase") {
                ForEach(0..<4) { track in
                    Button("Piste \(track + 1)") { run(.moveTrack(track)) }
                        .keyboardShortcut(cappellaFunctionKey(5 + track), modifiers: .control)
                }
            }
            Button("Détection des changements de plan…") { run(.detectShots) }
            Button("Vérifier") { run(.check) }.keyboardShortcut(cappellaFunctionKey(4), modifiers: [])
            Button("Décaler la rythmo…") { run(.shift) }
            Divider()
            Button("Préférences…") { run(.preferences) }.keyboardShortcut(",")
        }
        CommandMenu("Contrôle") {
            Button("Lecture/Pause") { run(.playPause) }.keyboardShortcut(.space, modifiers: [])
            Button("Lecture avant") { run(.rate(1)) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Lecture inverse") { run(.rate(-1)) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Stop") { run(.stop) }
            Divider()
            Button("Image suivante") { run(.step(1)) }.keyboardShortcut(.rightArrow, modifiers: .option)
            Button("Image précédente") { run(.step(-1)) }.keyboardShortcut(.leftArrow, modifiers: .option)
            Button("Jog avant") { run(.jog(1)) }
            Button("Jog arrière") { run(.jog(-1)) }
            Menu("Shuttle") {
                ForEach(PlaybackControls.shuttleSpeeds) { speed in
                    Toggle(speed.title, isOn: Binding(
                        get: { editor?.state.playbackRate == speed.rate },
                        set: { _ in run(.shuttle(speed.rate)) }
                    ))
                }
            }
            Divider()
            Button("Signe précédent") { run(.navigate("sign", -1)) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Signe suivant") { run(.navigate("sign", 1)) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Phrase précédente") { run(.navigate("phrase", -1)) }.keyboardShortcut(cappellaFunctionKey(9), modifiers: [])
            Button("Phrase suivante") { run(.navigate("phrase", 1)) }.keyboardShortcut(cappellaFunctionKey(10), modifiers: [])
            Button("Phrase précédente de ce rôle") { run(.navigate("role", -1)) }.keyboardShortcut(cappellaFunctionKey(9), modifiers: .control)
            Button("Phrase suivante de ce rôle") { run(.navigate("role", 1)) }.keyboardShortcut(cappellaFunctionKey(10), modifiers: .control)
            Button("Boucle précédente") { run(.navigate("loop", -1)) }.keyboardShortcut(cappellaFunctionKey(11), modifiers: [])
            Button("Boucle suivante") { run(.navigate("loop", 1)) }.keyboardShortcut(cappellaFunctionKey(12), modifiers: [])
            Button("Plan précédent") { run(.navigate("shot", -1)) }
            Button("Plan suivant") { run(.navigate("shot", 1)) }
            Divider()
            Button("Changer le timestamp…") { run(.timestamp) }
            Button("Machine Orphée…") {}.disabled(true).help("Le protocole de la machine Orphée n'est pas encore porté sur Mac.")
        }
        CommandMenu("Position") {
            Button("Aller au timecode…") { run(.goTimecode) }.keyboardShortcut("g", modifiers: .control)
            Button("Marquer cette position…") { run(.markPosition) }.keyboardShortcut("d", modifiers: .control)
            Button("Supprimer une position…") { run(.positions) }
        }
        CommandMenu("Affichage") {
            Toggle("Détection", isOn: Binding(get: { editor?.showDetection ?? true }, set: { _ in run(.detection) })).keyboardShortcut(cappellaFunctionKey(9), modifiers: [.control, .option])
            Toggle("Grille et signes", isOn: Binding(get: { editor?.showGrid ?? true }, set: { _ in run(.grid) })).keyboardShortcut(cappellaFunctionKey(10), modifiers: [.control, .option])
            Toggle("Mode lecture", isOn: Binding(get: { editor?.state.readingMode ?? false }, set: { _ in run(.readingMode) }))
            Toggle("Plein écran", isOn: Binding(get: { editor?.videoOnly ?? false }, set: { _ in run(.fullScreen) })).keyboardShortcut(.return, modifiers: [.option])
            Divider()
            Button("Zoom avant") { run(.zoom(1.25)) }.keyboardShortcut("+", modifiers: [])
            Button("Zoom arrière") { run(.zoom(0.8)) }.keyboardShortcut("-", modifiers: [])
            Divider()
            Button("Désentrelacer") {}.disabled(true).help("Le réglage manuel du désentrelacement reste à porter.")
            Button("Haute qualité") {}.disabled(true).help("Le réglage manuel de la qualité reste à porter.")
            Button("Écran de contrôle") { run(.projection) }
        }
        CommandMenu("Audio") {
            Button(editor?.usingVI == true ? "Passer en VO" : "Passer en VI") { run(.toggleVI) }.keyboardShortcut(cappellaFunctionKey(2), modifiers: [])
            Divider()
            Button("Monter le volume") { run(.volume(0.1)) }.keyboardShortcut("+", modifiers: .control)
            Button("Baisser le volume") { run(.volume(-0.1)) }.keyboardShortcut("-", modifiers: .control)
            Button("Couper le son") { run(.mute) }.keyboardShortcut("*", modifiers: .control)
            Divider()
            Button(editor?.recording == true ? "Arrêter l'enregistrement" : "Enregistrer…") { run(.recordAudio) }
        }
        CommandGroup(replacing: .appSettings) {}
    }
}

/// Local key handling leaves normal typing, spaces and arrows to text editors.
struct EditorKeyboardMonitor: NSViewRepresentable {
    var perform: (EditorAction) -> Void
    func makeNSView(context: Context) -> KeyboardView { let view = KeyboardView(); view.perform = perform; return view }
    func updateNSView(_ view: KeyboardView, context: Context) { view.perform = perform }
    final class KeyboardView: NSView {
        var perform: ((EditorAction) -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true,
                      self.window?.attachedSheet == nil else { return event }
                let flags = event.modifierFlags.intersection([.control, .command, .option, .shift])
                let ctrl = flags.contains(.control) || flags.contains(.command)
                let alt = flags.contains(.option)
                let shift = flags.contains(.shift)
                let typing = self.window?.firstResponder is NSTextView
                let timelineInput = self.window?.firstResponder as? DialogueTextEditor.FocusedTextView
                let wholePhrase = !typing || timelineInput?.selectedRange().length == 0
                let phraseOnClipboard = ctrl && !shift && event.keyCode == 9 &&
                    NSPasteboard.general.availableType(from: [.init(ProjectEditing.phraseClipboardType), .init("org.cappella-rewrite.phrase")]) != nil
                let key = event.charactersIgnoringModifiers ?? ""
                var action: EditorAction?
                if ctrl {
                    switch event.keyCode {
                    case 123: action = alt ? .shiftAnchor(-1) : .shiftSign(-1)
                    case 124: action = alt ? .shiftAnchor(1) : .shiftSign(1)
                    case 126: action = .relativeTrack(-1)
                    case 125: action = .relativeTrack(1)
                    case 96: action = .moveTrack(0)
                    case 97: action = .moveTrack(1)
                    case 98: action = .moveTrack(2)
                    case 100: action = .moveTrack(3)
                    case 101: action = alt ? .detection : .navigate("role", -1)
                    case 109: action = alt ? .grid : .navigate("role", 1)
                    case 111: action = .fullScreen
                    case 117, 51: action = .deletePhrase
                    case 36, 76: break
                    default:
                        switch key.lowercased() {
                        case "z": action = shift ? .redo : .undo
                        case "y": action = .redo
                        case "c" where wholePhrase: action = .copyPhrase
                        case "x" where wholePhrase: action = .cutPhrase
                        case "v" where !shift && (!typing || (timelineInput != nil && phraseOnClipboard)): action = .pastePhrase
                        case "e": action = shift ? nil : .exportScript
                        case "r": action = .roles
                        case "f": action = .find
                        case "g": action = .goTimecode
                        case "p": action = .properties
                        case "u": if !event.isARepeat { action = .voiceOff } else { return nil }
                        case "d": action = shift ? .detachSigns : .markPosition
                        case "v" where shift: action = .openMedia
                        case "+", "=": action = .volume(0.1)
                        case "-": action = .volume(-0.1)
                        case "*": action = .mute
                        case "2": action = .addSign("in_close")
                        case "3": action = .addSign("out_close")
                        case "n": ProjectSession.shared.newProject(); return nil
                        case "o": ProjectSession.shared.chooseOpen(); return nil
                        case "s": ProjectSession.shared.save(as: shift, copy: alt); return nil
                        case "z", "x", "c", "v", "a":
                            // Windows muscle memory, forwarded to the native responder chain.
                            let selectors = ["n":"newDocument:", "o":"openDocument:", "s": shift ? "saveDocumentAs:" : alt ? "saveDocumentTo:" : "saveDocument:",
                                             "z": shift ? "redo:" : "undo:", "x":"cut:", "c":"copy:", "v":"paste:", "a":"selectAll:"]
                            if flags.contains(.control), let selector = selectors[key.lowercased()] { NSApp.sendAction(Selector(selector), to: nil, from: nil); return nil }
                        default: break
                        }
                    }
                } else {
                    switch event.keyCode {
                    case 36, 76: action = alt ? .fullScreen : .mode
                    case 53: action = .cancelPhrase
                    case 122:
                        NSWorkspace.shared.open(URL(string: "https://cappella.app/")!); return nil
                    case 120: action = .toggleVI
                    case 99: action = .findNext
                    case 118: action = .check
                    case 96: action = .track(0)
                    case 97: action = .track(1)
                    case 98: action = .track(2)
                    case 100: action = .track(3)
                    case 101: action = .navigate("phrase", -1)
                    case 109: action = .navigate("phrase", 1)
                    case 103: action = .navigate("loop", -1)
                    case 111: action = .navigate("loop", 1)
                    case 48 where !typing: action = .navigate("phrase", shift ? 1 : -1)
                    case 49 where !typing: action = .playPause
                    case 123 where !typing || alt: action = alt ? .step(-1) : .navigate("sign", -1)
                    case 124 where !typing || alt: action = alt ? .step(1) : .navigate("sign", 1)
                    case 126: action = .rate(1)
                    case 125: action = .rate(-1)
                    case 117 where !typing: action = .deleteSelection
                    default:
                        if !typing {
                            switch key {
                            case "2": action = .addSign("in_open")
                            case "3": action = .addSign("out_open")
                            case "4": action = .addSign("mpb")
                            case "5": action = .addSign("fvr")
                            case "6": action = .addSign("neutral")
                            case "7": action = .addSign("a")
                            case "8": action = .addSign("o")
                            case "9": action = .addSign("weuque")
                            case "0": action = .addLoop
                            case "1": action = .addShot
                            case "+", "=": action = .zoom(1.25)
                            case "-": action = .zoom(0.8)
                            case "v", "V": action = .rate(-0.75)
                            case "b", "B": action = .rate(-0.25)
                            case "n", "N": action = .rate(0.25)
                            case ",": action = .rate(0.75)
                            default:
                                let character = event.characters ?? key
                                if let text = ReactionShortcuts.text(for: shift ? character.uppercased() : character.lowercased()) {
                                    action = .reaction(text)
                                }
                            }
                        }
                    }
                }
                if !ctrl, let character = event.characters, character == "&" || character == "²" {
                    action = .jumpAnchor(character == "&" ? 1 : -1)
                }
                if ctrl, (event.keyCode == 36 || event.keyCode == 76), let view = self.window?.firstResponder as? NSTextView {
                    view.insertNewlineIgnoringFieldEditor(nil); return nil
                }
                guard let action else {
                    // Plain-character menu equivalents must never steal a letter
                    // or a number from the on-band text editor.
                    if typing, !ctrl, let view = self.window?.firstResponder as? NSTextView {
                        view.keyDown(with: event); return nil
                    }
                    return event
                }
                if event.isARepeat {
                    switch action {
                    case .playPause, .rate(_), .reaction(_), .voiceOff: return nil
                    default: break
                    }
                }
                self.perform?(action); return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

private struct CappellaFileCommands: Commands {
    @FocusedObject private var editor: EditorActions?
    private func run(_ action: EditorAction) { editor?.perform(action) }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouveau") { ProjectSession.shared.newProject() }.keyboardShortcut("n")
            Button("Ouvrir…") { ProjectSession.shared.chooseOpen() }.keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Button("Ouvrir une sauvegarde…") { ProjectSession.shared.chooseOpen(backup: true) }
        }
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .saveItem) {
            Button("Enregistrer") { ProjectSession.shared.save() }.keyboardShortcut("s")
            Button("Enregistrer sous…") { ProjectSession.shared.save(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Enregistrer une copie sous…") { ProjectSession.shared.save(copy: true) }.keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandGroup(after: .importExport) {
            Divider()
            Button("Ouvrir l'image…") { run(.openMedia) }.keyboardShortcut("v", modifiers: [.control, .shift])
            Menu("Importer") {
                Button("Détection DetX…") { run(.importDetX) }
                Button("Liste de rôles d'un DetX…") { run(.importRoles) }
            }
            Menu("Exporter") {
                Button("Document DetX…") { run(.exportDetX) }
                Button("Script…") { run(.exportScript) }.keyboardShortcut("e")
                Button("Rythmo MP4…") { run(.exportMovie) }
                Button("Croisillé CSV…") { run(.exportCrossTable) }
            }
            Button("Propriétés…") { run(.properties) }.keyboardShortcut("p", modifiers: .control)
            Divider()
            Button("Quitter") { NSApp.terminate(nil) }
        }
    }
}
