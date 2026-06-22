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
    var beginResize: (() -> Void)?
    var updateResize: ((CGSize) -> Void)?

    let speech = SpeechRecognizer()

    /// How many recognized tokens (within the current speech segment) we've
    /// already used to drive the cursor, and the size of the latest transcript.
    /// Tracked incrementally so each new spoken word advances at most once.
    private var processedTokens = 0
    private var lastTokenCount = 0
    /// How far ahead of the cursor we'll look for a spoken word. Lets the
    /// prompter catch up when recognition lags or jump forward if you skip.
    private let lookahead = 12
    private var autoTimer: Timer?

    init() {
        script = storedScript
        rebuild()

        speech.onTokens = { [weak self] tokens in
            self?.consume(tokens: tokens)
        }
        speech.onSegmentReset = { [weak self] in
            // New segment => transcript starts empty again.
            self?.processedTokens = 0
            self?.lastTokenCount = 0
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
    }

    // MARK: - Cursor control

    func jump(to index: Int) {
        currentIndex = max(0, min(index, words.count))
        // Ignore anything already said in this segment so old audio can't
        // re-advance us — but DON'T restart the recognizer (that would kill it).
        processedTokens = lastTokenCount
    }

    func restart() {
        jump(to: 0)
    }

    var isFinished: Bool { currentIndex >= words.count }

    // MARK: - Speech-driven advancement

    /// Process the running transcript incrementally: only newly recognized
    /// tokens drive the cursor, and each is matched against a *window* of
    /// upcoming words. This lets the prompter jump forward to whatever word you
    /// actually said (e.g. you say "three" in "one two three four" -> it lands
    /// on "three") and catch up when recognition lags behind your voice.
    private func consume(tokens: [String]) {
        guard voiceEnabled, !paused, !isEditing else {
            // Discard anything spoken while paused/editing so it can't advance
            // the cursor once we resume.
            processedTokens = tokens.count
            lastTokenCount = tokens.count
            return
        }
        // A partial result occasionally shrinks as the recognizer revises;
        // reprocess from the start of the (now shorter) transcript.
        if tokens.count < processedTokens { processedTokens = 0 }

        var newIndex = currentIndex
        for i in processedTokens..<tokens.count {
            if let landed = matchForward(spoken: tokens[i], from: newIndex) {
                newIndex = landed + 1
            }
        }
        processedTokens = tokens.count
        lastTokenCount = tokens.count

        if newIndex > currentIndex {
            withAnimation(.easeOut(duration: 0.22)) { currentIndex = newIndex }
        }
    }

    /// Find the nearest upcoming word (within `lookahead`) that the spoken
    /// token matches. Returns its index, or nil if nothing nearby matches
    /// (filler words / mis-hears are simply ignored). Only ever looks forward,
    /// so voice never drags the cursor backward — tapping handles that.
    private func matchForward(spoken: String, from start: Int) -> Int? {
        guard !spoken.isEmpty else { return nil }
        let end = min(words.count, start + lookahead)
        guard start < end else { return nil }
        for idx in start..<end where Self.matches(words[idx].clean, spoken) {
            return idx
        }
        return nil
    }

    private static func matches(_ scriptWord: String, _ spoken: String) -> Bool {
        guard !scriptWord.isEmpty, !spoken.isEmpty else { return false }
        if scriptWord == spoken { return true }
        // Tolerate plural / tense endings (prefix overlap on longer words).
        if scriptWord.count >= 4 && spoken.count >= 4 {
            if scriptWord.hasPrefix(spoken) || spoken.hasPrefix(scriptWord) { return true }
        }
        // Tolerate a single-character recognition slip on longer words.
        if scriptWord.count >= 5 && spoken.count >= 5
            && abs(scriptWord.count - spoken.count) <= 1
            && levenshtein(scriptWord, spoken) <= 1 {
            return true
        }
        return false
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    // MARK: - Transport

    func toggleVoice() {
        voiceEnabled.toggle()
        if voiceEnabled {
            autoEnabled = false
            stopAutoTimer()
            paused = false
            processedTokens = 0
            lastTokenCount = 0
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
