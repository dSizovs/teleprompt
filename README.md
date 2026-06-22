# Teleprompt

Teleprompt is a lightweight, macOS-native, always-on-top teleprompter application built with SwiftUI. It is designed to hover just below the screen notch.

## Features

* **Always-On-Top:** A floating, borderless window designed to stay visible while you present.
* **Speech-Driven Scrolling:** Uses on-device speech recognition (`SFSpeechRecognizer`) to follow your voice in real-time, allowing you to speak naturally without manual adjustments.
* **Auto-Scroll:** Includes a timer-based auto-scroll feature with adjustable speed (WPM).
* **Interactive Controls:**
    * **Jump:** Tap any word in the script to jump the cursor immediately.
    * **Pause/Resume:** Easily pause the session to collect your thoughts.
    * **Text Editor:** Built-in editor to update your script on the fly.
    * **Adjustable:** Resize the window and change text size to fit your setup.
* **Privacy-Focused:** Offline, on-device speech recognition.

## Architecture

* **SwiftUI:** Used for the modern, reactive user interface.
* **NSPanel:** The core window is a custom `NSPanel` subclass configured to be borderless and floating, ensuring it stays out of the way but always accessible.
* **Speech Recognition:** Built on Apple's `SFSpeechRecognizer` and `AVAudioEngine`, specifically configured for on-device recognition to ensure privacy and offline functionality.
* **Custom Layout:** Includes a custom `FlowLayout` to handle the dynamic wrapping of script words across multiple lines.
* **Model-View-Controller/ObservableObject:** Uses the `TeleprompterModel` (`@ObservedObject`) as the central source of truth for the application state, managing the script, current cursor index, transport state (voice/auto), and settings.

## Getting Started

1.  **Clone the repository.**
2.  **Open in Xcode.**
3.  **Check Entitlements:** Ensure `teleprompt.entitlements` is correctly configured for your environment (required for Microphone access and Speech Recognition).
4.  **Run:** Build and run the app. It will appear as a borderless panel pinned under your menu bar.

## Requirements

* macOS (SwiftUI/AppKit)
* Xcode 15+ (recommended)
* Microphone and Speech Recognition permissions are required at runtime.

## License

I developed this project for my personal use during my Master's degree studies at the University of Freiburg. Feel free to use it :)
