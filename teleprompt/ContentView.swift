//
//  ContentView.swift
//  teleprompt
//
//  The teleprompter strip: a single horizontal line of words with the current
//  word centered & highlighted, plus a hover-revealed control bar.
//

import SwiftUI

struct TeleprompterView: View {
    @ObservedObject var model: TeleprompterModel
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            if model.isEditing {
                EditorView(model: model)
                    .padding(14)
            } else {
                PrompterStrip(model: model)
                    .padding(.horizontal, 10)
            }

            if !model.isEditing {
                ControlBar(model: model)
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: hovering)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering = $0 }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.black.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Prompter strip

private struct PrompterStrip: View {
    @ObservedObject var model: TeleprompterModel

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // Leading inset so the first word can sit at center.
                        Color.clear.frame(width: geo.size.width / 2)
                        ForEach(model.words) { word in
                            Text(word.text)
                                .font(.system(size: model.fontSize,
                                               weight: .semibold, design: .rounded))
                                .foregroundStyle(color(for: word))
                                .fixedSize()
                                .id(word.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.jump(to: word.id) }
                                .scaleEffect(word.id == model.currentIndex ? 1.0 : 0.96)
                                .animation(.easeOut(duration: 0.2), value: model.currentIndex)
                        }
                        Color.clear.frame(width: geo.size.width / 2)
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: model.currentIndex) { _, idx in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
                .onAppear { proxy.scrollTo(model.currentIndex, anchor: .center) }
            }
            // Center guide line under the active word.
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func color(for word: ScriptWord) -> Color {
        if word.id < model.currentIndex { return .white.opacity(0.28) }   // spoken
        if word.id == model.currentIndex {                                 // up next
            return model.paused ? .orange : .green
        }
        return .white.opacity(0.92)                                        // upcoming
    }
}

// MARK: - Control bar

private struct ControlBar: View {
    @ObservedObject var model: TeleprompterModel

    var body: some View {
        HStack(spacing: 14) {
            iconButton(model.voiceEnabled ? "mic.fill" : "mic.slash",
                       active: model.voiceEnabled, help: "Voice follow") {
                model.toggleVoice()
            }
            iconButton(model.autoEnabled ? "play.fill" : "play",
                       active: model.autoEnabled, help: "Auto-scroll") {
                model.toggleAuto()
            }
            iconButton(model.paused ? "play.circle.fill" : "pause.circle",
                       active: model.paused, help: "Pause / resume") {
                model.togglePause()
            }

            Divider().frame(height: 16)

            iconButton("textformat.size.smaller", active: false, help: "Smaller") {
                model.fontSize = max(18, model.fontSize - 3)
            }
            iconButton("textformat.size.larger", active: false, help: "Larger") {
                model.fontSize = min(96, model.fontSize + 3)
            }

            if model.autoEnabled {
                Slider(value: Binding(get: { model.speedWPM },
                                      set: { model.setSpeed($0) }),
                       in: 60...260)
                    .frame(width: 90)
                    .tint(.white.opacity(0.7))
            }

            Divider().frame(height: 16)

            iconButton("pencil", active: false, help: "Edit text") { model.beginEditing() }
            iconButton("backward.end", active: false, help: "Restart") { model.restart() }

            if !model.statusText.isEmpty {
                Text(model.statusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
            iconButton("xmark", active: false, help: "Quit") { model.quit() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .padding(.bottom, 6)
        .padding(.horizontal, 12)
    }

    private func iconButton(_ name: String, active: Bool, help: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .green : .white.opacity(0.85))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Editor

private struct EditorView: View {
    @ObservedObject var model: TeleprompterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Edit script")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Done") { model.endEditing() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            TextEditor(text: $model.script)
                .font(.system(size: 16, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }
}
