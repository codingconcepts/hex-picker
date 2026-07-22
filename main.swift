import SwiftUI

struct SavedColour: Codable, Equatable {
    let r: Int, g: Int, b: Int
    var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    var rgb: String { "rgb(\(r), \(g), \(b))" }
    var color: Color { Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255) }
}

class ColourStore: ObservableObject {
    static let maxColours = 6
    @Published var slots: [SavedColour?] = Array(repeating: nil, count: 6)
    @Published var selected: SavedColour?

    init() { load() }

    func pickColour(at index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let sampler = NSColorSampler()
            sampler.show { color in
                guard let self = self, let color = color?.usingColorSpace(.sRGB) else { return }
                let r = Int(color.redComponent * 255)
                let g = Int(color.greenComponent * 255)
                let b = Int(color.blueComponent * 255)
                let c = SavedColour(r: r, g: g, b: b)
                self.slots[index] = c
                self.selected = c
                self.save()
            }
        }
    }

    func remove(at index: Int) {
        if let c = slots[index], selected == c { selected = nil }
        slots[index] = nil
        save()
    }

    func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: "savedColours")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "savedColours"),
           let decoded = try? JSONDecoder().decode([SavedColour?].self, from: data) {
            slots = decoded
            while slots.count < Self.maxColours { slots.append(nil) }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SwatchDeleteButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if hovering {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct CopyButton: View {
    let label: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(hovering ? 0.12 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(hovering ? 0.25 : 0.1), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = !disabled && $0 }
        .disabled(disabled)
    }
}

struct ContentView: View {
    @ObservedObject var store: ColourStore
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<ColourStore.maxColours, id: \.self) { i in
                    if let c = store.slots[i] {
                        colourSwatch(c, at: i)
                    } else {
                        emptySwatch(at: i)
                    }
                }
            }

            HStack(spacing: 12) {
                copyButton(
                    label: store.selected?.hex ?? "#hex",
                    action: { if let c = store.selected { store.copyToClipboard(c.hex) } }
                )
                copyButton(
                    label: store.selected?.rgb ?? "rgb",
                    action: { if let c = store.selected { store.copyToClipboard(c.rgb) } }
                )
            }
            .opacity(store.selected == nil ? 0.4 : 1.0)
        }
        .padding(16)
        .frame(width: 400)
        .background(VisualEffectBackground())
    }

    func colourSwatch(_ c: SavedColour, at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(c.color)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(store.selected == c ? 0.6 : 0.3),
                            lineWidth: store.selected == c ? 2.5 : 1.5)
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                SwatchDeleteButton { store.remove(at: index) }
            }
            .onTapGesture { store.selected = c }
    }

    func emptySwatch(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
            )
            .aspectRatio(1, contentMode: .fit)
            .onTapGesture { store.pickColour(at: index) }
    }

    func copyButton(label: String, action: @escaping () -> Void) -> some View {
        CopyButton(label: label, disabled: store.selected == nil, action: action)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let store = ColourStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

        let hosting = NSHostingView(rootView: ContentView(store: store))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Hex Picker"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = hosting
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func setupMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func pickColour() {
        let index = store.slots.firstIndex(where: { $0 == nil }) ?? 0
        store.pickColour(at: index)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
