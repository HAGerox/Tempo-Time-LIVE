# Design

A small utility opens directly into its task. Each element must help the user act, choose, understand current state or recover.

- One obvious primary action per view; a few secondary actions. Put frequent choices first and reveal uncommon options when needed.
- Use literal labels: “Add files”, “Choose your stems”, “Backing up”, “Saved to Downloads”. No slogans, “we'll”, AI sparkle icons or reassurance about automatic handling.
- Say each fact once. Remove duplicate headings, selection summaries, idle status, zero-error counts, example placeholders and architecture explanations unless they resolve a real ambiguity.
- Explain meaningful differences briefly. Never remove essential compatibility, consequences, error recovery or accessibility to save words.
- Use genuine platform controls and behaviour where available. Match native sheets, inline rename, keyboard shortcuts, focus and list actions; verify against a real platform reference when unsure.
- Stable action placement and hitboxes. Lists scroll, short content collapses, expanded options never overlap the footer. Check the smallest supported window and a larger one.
- System typography, consistent spacing, restrained borders, one deliberate accent. Support system light/dark appearance in apps. Shared labels retain consistent colours.
- Initialize sheets and queues before displaying them; no flash of the wrong mode. Guard both window close and Cmd-Q when they would discard active work.
- Accept drag/drop only where meaningful. Exported files must behave like files and must not accidentally re-enter the input flow.
- Show progress only during work. Use meaningful stages, no fake steps or unreliable ETA. Keep short success feedback; show error counts only when errors exist.
- Empty states provide the next useful action. No branding header, welcome screen, settings page or nonfunctional control by default.
- Retain keyboard access, accessible names, visible focus and readable contrast. An icon-only control still needs an accessible label.

For website pages use the utility-website skill. Record only approved app-specific exceptions below; replace superseded decisions instead of appending a history.

Tempo Time LIVE uses the Tauri utility template, as explicitly requested. Keep the coral tap circle, cream/dark input area and ink note panel. Only input and channel lists, an always-running selected-channel level meter sit above the circle. Audio capture starts automatically and follows selection changes; there is no Listen/Stop control. Keep the layout fixed across connection and error states. A compact Music / Click track switch occupies the space beneath the circle, replacing the former Audio/Manual label. Default to Music and remember the selection. Tapping changes the existing TAP caption inside the circle to MANUAL and returns to the selected source after 30 seconds. Selecting either source ends manual override, including reselecting the current source. No BPM field or extra detector controls. The right panel contains only the six Android note rows (whole through thirty-second) and milliseconds. No pre-delay hero, selected rows, copy controls, rhythm settings, detector options or explanatory text. Detected musical beats and isolated clicks represent quarter notes. Channel selection is a list, never a typed number. The app icon places its original coral mark on a white macOS rounded-square background.
