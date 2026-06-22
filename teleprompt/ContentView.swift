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
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip(model: model)
                .opacity(hovering && !model.isEditing ? 0.9 : 0)
                .animation(.easeInOut(duration: 0.15), value: hovering)
        }
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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 12, lineSpacing: max(6, model.fontSize * 0.28)) {
                    ForEach(model.words) { word in
                        Text(word.text)
                            .font(.system(size: model.fontSize,
                                           weight: .semibold, design: .rounded))
                            .foregroundStyle(color(for: word))
                            .fixedSize()
                            .id(word.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.jump(to: word.id) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Top & bottom breathing room so the first/last lines can scroll
                // to the active anchor position and older text stays visible.
                .padding(.vertical, 8)
            }
            .onChange(of: model.currentIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.28)) {
                    // Keep the active word ~40% down: leaves a line or two of
                    // already-spoken text above it for context.
                    proxy.scrollTo(idx, anchor: UnitPoint(x: 0.5, y: 0.42))
                }
            }
            .onChange(of: model.fontSize) { _, _ in
                proxy.scrollTo(model.currentIndex, anchor: UnitPoint(x: 0.5, y: 0.42))
            }
            .onAppear { proxy.scrollTo(model.currentIndex, anchor: UnitPoint(x: 0.5, y: 0.42)) }
        }
    }

    private func color(for word: ScriptWord) -> Color {
        if word.id < model.currentIndex { return .white.opacity(0.3) }    // spoken
        if word.id == model.currentIndex {                                 // up next
            return model.paused ? .orange : .green
        }
        return .white.opacity(0.92)                                        // upcoming
    }
}

// MARK: - Flow layout (wraps words onto multiple lines)

struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxLineWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : maxLineWidth
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
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

// MARK: - Resize grip

private struct ResizeGrip: View {
    @ObservedObject var model: TeleprompterModel
    @State private var dragging = false

    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !dragging { dragging = true; model.beginResize?() }
                        model.updateResize?(value.translation)
                    }
                    .onEnded { _ in dragging = false }
            )
            .help("Drag to resize")
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
