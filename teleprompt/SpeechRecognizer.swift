//
//  SpeechRecognizer.swift
//  teleprompt
//
//  Offline (on-device) speech recognition wrapper built on Apple's
//  SFSpeechRecognizer + AVAudioEngine. Streams a running list of
//  recognized word tokens back to the caller.
//

import Foundation
import Combine
import AVFoundation
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {

    enum Status: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle

    /// Called on every partial/final result with the full list of normalized
    /// word tokens recognized so far *in the current segment*.
    var onTokens: (([String]) -> Void)?
    /// Called when a recognition segment ends so the consumer can reset its
    /// per-segment matching anchor.
    var onSegmentReset: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var wantsToListen = false

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Permissions

    func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                guard auth == .authorized else {
                    self.status = .unavailable("Speech recognition not authorized")
                    completion(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { micOK in
                    DispatchQueue.main.async {
                        if !micOK {
                            self.status = .unavailable("Microphone not authorized")
                        }
                        completion(micOK)
                    }
                }
            }
        }
    }

    // MARK: - Control

    func start() {
        wantsToListen = true
        requestPermissions { ok in
            guard ok else { return }
            self.beginSegment()
        }
    }

    func stop() {
        wantsToListen = false
        teardown()
        status = .idle
    }

    // MARK: - Internals

    private func beginSegment() {
        guard wantsToListen else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Recognizer unavailable")
            return
        }

        teardown()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The whole point: keep everything on-device so it works offline.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            status = .unavailable("Audio engine: \(error.localizedDescription)")
            return
        }

        onSegmentReset?()
        status = .listening

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let tokens = Self.tokenize(result.bestTranscription.formattedString)
                    self.onTokens?(tokens)
                }
                if error != nil || (result?.isFinal ?? false) {
                    // Segment finished (timeout/silence/error). Restart so the
                    // user can keep going as long as they're listening.
                    if self.wantsToListen {
                        self.beginSegment()
                    }
                }
            }
        }
    }

    private func teardown() {
        task?.cancel()
        task = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
    }

    /// Lowercased, punctuation-stripped word tokens.
    static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
