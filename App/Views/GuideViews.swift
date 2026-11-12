import SwiftUI

struct KeyboardGuideView: View {
    var body: some View {
        List {
            Section {
                StepRow(number: 1, text: "Settings › General › Keyboard › Keyboards › Add New Keyboard… › \"Voice Type\"")
                StepRow(number: 2, text: "Tap \"Voice Type\" in the list and turn on \"Allow Full Access\". (Needed so the keyboard can talk to the app. The keyboard never records or sends your keystrokes.)")
                StepRow(number: 3, text: "In any app, touch and hold 🌐 on the keyboard and choose \"Voice Type\".")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Setup (once)")
            }

            Section {
                StepRow(number: 1, text: "Switch to the Voice Type keyboard. It starts listening on its own; you can turn that off in Settings and tap the mic instead.")
                StepRow(number: 2, text: "If the microphone is off, Voice Type opens and starts recording right away. Swipe right along the bar at the bottom of the screen to go back to your app. You can talk the whole time.")
                StepRow(number: 3, text: "Tap the mic when you're done. The text is typed at the cursor. \"Undo\" on the keyboard removes it again.")
            } header: {
                Text("Usage")
            } footer: {
                Text("Apple does not let keyboards use the microphone, and does not let apps send you back to the previous app, so the Voice Type app records and you swipe back.\n\nTo skip that trip, choose a longer \"Keep Microphone On\" time in Settings: while the microphone is on, the keyboard listens instantly. iOS shows its microphone indicator during that time.")
            }

            Section {
                StepRow(number: 1, text: "In the Shortcuts app, create a shortcut with the \"Voice Type › Start Keyboard Session\" action.")
                StepRow(number: 2, text: "Bind it to the Action Button or Back Tap to turn the microphone on before you start typing.")
            } header: {
                Text("Tip: turn the microphone on ahead of time")
            }
        }
        .navigationTitle("Keyboard")
    }
}

struct BackTapGuideView: View {
    var body: some View {
        List {
            Section {
                StepRow(number: 1, text: "In the Shortcuts app, tap + to create a new shortcut. Name it \"Voice Type\".")
                StepRow(number: 2, text: "Add the \"Record Audio\" action. In its details: Audio Quality \"Normal\", Start Recording \"Immediately\", Finish Recording \"On Tap\".")
                StepRow(number: 3, text: "Add the \"Voice Type › Transcribe Audio\" action. Audio should be \"Recorded Audio\"; leave \"Copy to Clipboard\" on.")
                StepRow(number: 4, text: "(Optional) Add \"Show Notification\" with \"Transcribed Text\" as its text, so you can see what was written.")
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
            } header: {
                Text("1. Create the shortcut")
            }

            Section {
                StepRow(number: 1, text: "Settings › Accessibility › Touch › Back Tap")
                StepRow(number: 2, text: "\"Double Tap\" › choose the \"Voice Type\" shortcut from the list.")
            } header: {
                Text("2. Bind it to Back Tap")
            }

            Section {
                StepRow(number: 1, text: "In any app, double-tap the back of your phone.")
                StepRow(number: 2, text: "Speak, then tap the record button on screen when you're done.")
                StepRow(number: 3, text: "The text is copied to the clipboard. Touch and hold the text field and tap \"Paste\".")
            } header: {
                Text("Usage")
            } footer: {
                Text("iOS does not let apps type directly into another app's text field, so the Back Tap route copies the text to the clipboard. To have it typed directly, use the Voice Type keyboard.\n\nAlternative: instead of \"Record Audio\", you can use a single \"Voice Type › Dictate\" action. It opens the app and starts listening right away.")
            }
        }
        .navigationTitle("Back Tap")
    }
}
