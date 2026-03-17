import Carbon.HIToolbox
import Foundation

@MainActor
final class InputSourceService {
    private let onChange: () -> Void
    private var observer: NSObjectProtocol?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onChange()
            }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    /// Returns a display label for the current input source, matching macOS menu bar style.
    func currentSourceAbbreviation() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "??"
        }

        // 1. Check input mode ID (IMEs with multiple modes: Japanese, Chinese, Korean)
        if let modePtr = TISGetInputSourceProperty(source, kTISPropertyInputModeID) {
            let modeID = Unmanaged<CFString>.fromOpaque(modePtr).takeUnretainedValue() as String
            if let modeAbbr = abbreviationForMode(modeID) {
                return modeAbbr
            }
        }

        // 2. Check source ID against known table
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if let known = abbreviationForKnownSource(sourceID) {
                return known
            }
        }

        // 3. Language-based fallback for unknown IMEs (e.g. third-party)
        if let langPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let langs = Unmanaged<CFArray>.fromOpaque(langPtr).takeUnretainedValue() as? [String]
            if let primaryLang = langs?.first, let langAbbr = abbreviationForLanguage(primaryLang) {
                return langAbbr
            }
        }

        // 4. Localized name fallback
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            return String(name.prefix(3)).uppercased()
        }

        return "??"
    }

    func cycleToNextSource() {
        guard let sources = TISCreateInputSourceList(nil, false)?
            .takeRetainedValue() as? [TISInputSource] else { return }

        let selectable = sources.filter { source in
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
                return false
            }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
        }
        guard !selectable.isEmpty else { return }

        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let currentID = sourceID(current)

        let idx = selectable.firstIndex { source in
            sourceID(source) == currentID
        } ?? -1

        let next = selectable[(idx + 1) % selectable.count]
        TISSelectInputSource(next)
    }

    // MARK: - Private

    private func sourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // MARK: - Mode-based resolution (IMEs with multiple input modes)

    private func abbreviationForMode(_ modeID: String) -> String? {
        let id = modeID.lowercased()

        // Japanese (Apple Kotoeri, Google Japanese Input, ATOK, etc.)
        if id.contains("japanese") || id.contains("kotoeri") {
            return japaneseMode(id)
        }

        // Chinese Simplified (Pinyin, Wubi, etc.)
        if id.contains("scim") || id.contains("simplifiedchinese") || id.contains("pinyin") || id.contains("wubi") {
            if id.contains("base") || id.contains("ascii") || id.contains("english") { return "A" }
            return "拼"
        }

        // Chinese Traditional (Zhuyin, Cangjie, etc.)
        if id.contains("tcim") || id.contains("traditionalchinese") || id.contains("zhuyin") || id.contains("cangjie") {
            if id.contains("base") || id.contains("ascii") || id.contains("english") { return "A" }
            return "注"
        }

        // Korean
        if id.contains("korean") {
            if id.contains("base") || id.contains("ascii") || id.contains("english") { return "A" }
            return "한"
        }

        // Vietnamese
        if id.contains("vietnamese") {
            return "Vi"
        }

        // Generic: many IMEs use "Base"/"ASCII"/"English" for their latin sub-mode
        if id.contains("base") || id.contains("ascii") || id.contains("english") || id.contains("roman") {
            return "A"
        }

        return nil
    }

    private func japaneseMode(_ id: String) -> String {
        if id.contains("hiragana") || id.hasSuffix(".japanese") { return "あ" }
        if id.contains("halfwidthkatakana") || id.contains("halfwidthkana") { return "ｱ" }
        if id.contains("katakana") { return "ア" }
        if id.contains("fullwidthroman") { return "Ａ" }
        if id.contains("base") || id.contains("roman") || id.contains("ascii") || id.contains("english") {
            return "A"
        }
        return "あ"
    }

    // MARK: - Source ID-based resolution (keyboard layouts & known sources)

    private func abbreviationForKnownSource(_ sourceID: String) -> String? {
        let table: [String: String] = [
            "com.apple.keylayout.ABC": "ABC",
            "com.apple.keylayout.US": "U.S.",
            "com.apple.keylayout.British": "EN",
            "com.apple.keylayout.USInternational-PC": "EN",
            "com.apple.keylayout.Australian": "EN",
            "com.apple.keylayout.Canadian": "EN",
            "com.apple.keylayout.Colemak": "CO",
            "com.apple.keylayout.Dvorak": "DV",
        ]

        if let known = table[sourceID] { return known }

        // Keyboard layouts (com.apple.keylayout.*) — use last component
        if sourceID.contains("keylayout") {
            let last = sourceID.components(separatedBy: ".").last ?? sourceID
            return String(last.prefix(3)).uppercased()
        }

        return nil
    }

    // MARK: - Language-based fallback (for unknown / third-party IMEs)

    private func abbreviationForLanguage(_ lang: String) -> String? {
        let code = String(lang.prefix(2))
        let map: [String: String] = [
            "ja": "あ",
            "zh": "中",
            "ko": "한",
            "vi": "Vi",
            "th": "ไ",
            "ar": "ع",
            "he": "א",
            "hi": "हि",
            "ru": "RU",
            "uk": "UK",
            "en": "EN",
            "fr": "FR",
            "de": "DE",
            "es": "ES",
            "pt": "PT",
            "it": "IT",
        ]
        return map[code] ?? code.uppercased()
    }
}
