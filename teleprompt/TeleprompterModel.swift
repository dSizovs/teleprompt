//
//  TeleprompterModel.swift
//  teleprompt
//
//  Holds the script, the cursor (next word to be spoken) and the logic that
//  advances the cursor either from recognized speech or a constant-speed timer.
//

import Foundation
import SwiftUI
import Combine

struct ScriptWord: Identifiable, Equatable {
    let id: Int
    let text: String   // original, with punctuation, for display
    let clean: String  // normalized, for matching
}

@MainActor
final class TeleprompterModel: ObservableObject {

    // MARK: - Content
    @AppStorage("script") private var storedScript: String = TeleprompterModel.sample
    @Published var script: String = TeleprompterModel.sample { didSet { rebuild() } }
    @Published private(set) var words: [ScriptWord] = []

    /// Index of the next word the speaker should say. Everything before it is
    /// considered already spoken.
    @Published var currentIndex: Int = 0

    // MARK: - Appearance / persisted prefs
    @AppStorage("fontSize") var fontSize: Double = 38

    // MARK: - Transport state
    @Published var voiceEnabled = false   // advance from speech
    @Published var autoEnabled = false    // advance from timer
    @Published var paused = false         // master freeze
    @Published var isEditing = false { didSet { onEditingChange?(isEditing); updateStatus() } }
    @Published var speedWPM: Double = 130
    @Published var statusText: String = ""

    // Wired up by the AppDelegate to drive the host panel.
    var onEditingChange: ((Bool) -> Void)?
    var onQuit: (() -> Void)?
    var requestFront: (() -> Void)?

    let speech = SpeechRecognizer()

    /// Per-segment matching anchor: the cursor position when the current
    /// speech segment began. Alignment is recomputed from here each callback.
    private var segmentBase = 0
    private var autoTimer: Timer?

    init() {
        script = storedScript
        rebuild()

        speech.onTokens = { [weak self] tokens in
            self?.consume(tokens: tokens)
        }
        speech.onSegmentReset = { [weak self] in
            self?.segmentBase = self?.currentIndex ?? 0
        }
        $script
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] s in self?.storedScript = s }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Script parsing

    private func rebuild() {
        let tokens = script.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        var result: [ScriptWord] = []
        result.reserveCapacity(tokens.count)
        for (i, t) in tokens.enumerated() {
            let clean = SpeechRecognizer.tokenize(String(t)).joined()
            result.append(ScriptWord(id: i, text: String(t), clean: clean))
        }
        words = result
        if currentIndex > words.count { currentIndex = words.count }
        segmentBase = min(segmentBase, words.count)
    }

    // MARK: - Cursor control

    func jump(to index: Int) {
        currentIndex = max(0, min(index, words.count))
        segmentBase = currentIndex
        // Clear any in-flight transcription so old audio can't re-advance us.
        if voiceEnabled { speech.start() }
    }

    func restart() {
        jump(to: 0)
    }

    var isFinished: Bool { currentIndex >= words.count }

    // MARK: - Speech-driven advancement

    /// Greedy alignment of spoken tokens onto the upcoming script words,
    /// starting from the segment anchor. Idempotent: safe to recompute on every
    /// partial result. Tolerates a single skipped/misheard word.
    private func consume(tokens: [String]) {
        guard voiceEnabled, !paused, !isEditing else { return }
        var s = segmentBase
        var t = 0
        while t < tokens.count && s < words.count {
            let spoken = tokens[t]
            if Self.matches(words[s].clean, spoken) {
                s += 1; t += 1
            } else if s + 1 < words.count && Self.matches(words[s + 1].clean, spoken) {
                // Speaker skipped/omitted one word — move past it.
                s += 2; t += 1
            } else {
                // Unrecognized filler / mis-hear — skip the spoken token.
                t += 1
            }
        }
        if s > currentIndex {
            withAnimation(.easeOut(duration: 0.25)) { currentIndex = s }
        }
    }

    private static func matches(_ scriptWord: String, _ spoken: String) -> Bool {
        guard !scriptWord.isEmpty, !spoken.isEmpty else { return false }
        if scriptWord == spoken { return true }
        // Tolerate plural / tense endings and minor recognition slips.
        if scriptWord.count >= 4 && spoken.count >= 4 {
            if scriptWord.hasPrefix(spoken) || spoken.hasPrefix(scriptWord) { return true }
        }
        return false
    }

    // MARK: - Transport

    func toggleVoice() {
        voiceEnabled.toggle()
        if voiceEnabled {
            autoEnabled = false
            stopAutoTimer()
            paused = false
            segmentBase = currentIndex
            speech.start()
        } else {
            speech.stop()
        }
        updateStatus()
    }

    func toggleAuto() {
        autoEnabled.toggle()
        if autoEnabled {
            voiceEnabled = false
            speech.stop()
            paused = false
            startAutoTimer()
        } else {
            stopAutoTimer()
        }
        updateStatus()
    }

    func togglePause() {
        paused.toggle()
        if paused {
            stopAutoTimer()
        } else if autoEnabled {
            startAutoTimer()
        }
        updateStatus()
    }

    func beginEditing() {
        voiceEnabled = false
        autoEnabled = false
        stopAutoTimer()
        speech.stop()
        isEditing = true
        requestFront?()
    }

    func endEditing() {
        isEditing = false
    }

    func quit() { onQuit?() }

    func setSpeed(_ wpm: Double) {
        speedWPM = wpm
        if autoEnabled && !paused { startAutoTimer() }
    }

    private func startAutoTimer() {
        stopAutoTimer()
        let interval = max(0.12, 60.0 / max(40.0, speedWPM))
        autoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.autoTick(interval: interval) }
        }
    }

    private func stopAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func autoTick(interval: Double) {
        guard autoEnabled, !paused, !isEditing else { return }
        guard currentIndex < words.count else {
            autoEnabled = false
            stopAutoTimer()
            updateStatus()
            return
        }
        withAnimation(.linear(duration: interval)) { currentIndex += 1 }
    }

    private func updateStatus() {
        if isEditing { statusText = "Editing" }
        else if paused { statusText = "Paused" }
        else if voiceEnabled { statusText = "Listening" }
        else if autoEnabled { statusText = "Auto \(Int(speedWPM)) wpm" }
        else { statusText = "" }
    }

    // MARK: - Sample script

    static let sample = """
    Hello, and welcome. This is your teleprompter. Just start speaking and the \
    words will scroll along with you. If it ever gets stuck, tap any word to jump \
    straight there, or hit pause to catch your breath. You've got this.
    """
}
