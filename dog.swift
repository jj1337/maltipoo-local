import Cocoa

let home = NSHomeDirectory() + "/.maltipoo-local"

// When launched from Maltipoo.app, seed ~/.maltipoo-dog with the bundled assets (never overwrites user files).
if let res = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: res + "/gifs") {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
    for n in ["gifs", "gifs_orig", "dur.json"] where !fm.fileExists(atPath: home + "/" + n) {
        try? fm.copyItem(atPath: res + "/" + n, toPath: home + "/" + n)
    }
}
let durs: [String: Double] = {
    if let d = try? Data(contentsOf: URL(fileURLWithPath: home + "/dur.json")),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Double] { return j }
    return [:]
}()
let reactions = ["Waving","JumpingHappy","DancingHappy","Excited","Turning","Hula","Dizzy","Spark","Lightbulb","Walking","Bark","Yawn"]
let parentPid: Int32 = CommandLine.arguments.count > 1 ? Int32(CommandLine.arguments[1]) ?? 0 : 0

struct Settings: Codable {
    var size: Double = 110
    var model: String = ""          // local model used for screenshots and checks ("" = first installed)
    var endpoint: String = "http://localhost:11434"   // Ollama; LM Studio is http://localhost:1234
    var waves: Bool = true
    var sleeping: Bool = false
    var walk: Bool = true
    var walkFreq: Int = 1      // 0 often, 1 sometimes, 2 rarely
    var bite: Int = 2          // 0 off, 1 very rarely, 2 rarely
    var alpha: Double = 1.0
    var autosleep: Int = 0     // minutes, 0 = never
    var game: Bool = false     // game mode: eats the cursor every 2 minutes
    var acts: Bool = true      // sits, lies, yawns sometimes
    var toy = true
    var chatSession = ""   // id of the current local dialog
    var chatModel = ""   // local model for the chat ("" = first installed)
    var helpEvery = 30      // minutes between 'need help?' screen checks, 0 = off
    var showTag = true, showCollar = true, showReactions = true, followEyes = true, petReact = true
    var theme: String = "boy"
    var name: String = ""
    init() {}
    enum CodingKeys: String, CodingKey { case size, model, endpoint, waves, sleeping, walk, walkFreq, bite, alpha, autosleep, game, acts, theme, name, chatModel, chatSession, toy, helpEvery, showTag, showCollar, showReactions, followEyes, petReact }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 110
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? "http://localhost:11434"
        waves = try c.decodeIfPresent(Bool.self, forKey: .waves) ?? true
        sleeping = try c.decodeIfPresent(Bool.self, forKey: .sleeping) ?? false
        walk = try c.decodeIfPresent(Bool.self, forKey: .walk) ?? true
        walkFreq = try c.decodeIfPresent(Int.self, forKey: .walkFreq) ?? 1
        bite = try c.decodeIfPresent(Int.self, forKey: .bite) ?? 2
        alpha = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0
        autosleep = try c.decodeIfPresent(Int.self, forKey: .autosleep) ?? 0
        game = try c.decodeIfPresent(Bool.self, forKey: .game) ?? false
        acts = try c.decodeIfPresent(Bool.self, forKey: .acts) ?? true
        chatModel = try c.decodeIfPresent(String.self, forKey: .chatModel) ?? ""
        chatSession = try c.decodeIfPresent(String.self, forKey: .chatSession) ?? ""
        toy = try c.decodeIfPresent(Bool.self, forKey: .toy) ?? true
        helpEvery = try c.decodeIfPresent(Int.self, forKey: .helpEvery) ?? 30
        showTag = try c.decodeIfPresent(Bool.self, forKey: .showTag) ?? true
        showCollar = try c.decodeIfPresent(Bool.self, forKey: .showCollar) ?? true
        showReactions = try c.decodeIfPresent(Bool.self, forKey: .showReactions) ?? true
        followEyes = try c.decodeIfPresent(Bool.self, forKey: .followEyes) ?? true
        petReact = try c.decodeIfPresent(Bool.self, forKey: .petReact) ?? true
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "boy"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
    static func load() -> Settings {
        if let d = try? Data(contentsOf: URL(fileURLWithPath: home + "/settings.json")),
           let s = try? JSONDecoder().decode(Settings.self, from: d) { return s }
        return Settings()
    }
    func save() { try? JSONEncoder().encode(self).write(to: URL(fileURLWithPath: home + "/settings.json")) }
}
var settings = Settings.load()
func dlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    let p = home + "/log.txt"
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
}


// MARK: pixel UI kit (tofi style: notched corners, hard outlines, bitmap icons, no emoji)
enum Px {
    static func font(_ size: CGFloat) -> NSFont { NSFont(name: "Menlo-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size) }
    static func mix(_ a: NSColor, _ b: NSColor, _ f: CGFloat) -> NSColor { a.blended(withFraction: f, of: b) ?? a }
    static func notched(_ r: NSRect, _ u: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.appendRect(NSRect(x: r.minX + u, y: r.minY, width: r.width - 2 * u, height: r.height))
        p.appendRect(NSRect(x: r.minX, y: r.minY + u, width: r.width, height: r.height - 2 * u))
        return p
    }
    static func box(_ r: NSRect, fill: NSColor, ink: NSColor, u: CGFloat = 3, shadow: NSColor? = nil, bevel: Bool = false) {
        if let s = shadow { s.setFill(); notched(r.offsetBy(dx: u, dy: -u), u).fill() }
        ink.setFill(); notched(r, u).fill()
        let inner = r.insetBy(dx: u, dy: u)
        fill.setFill(); notched(inner, u).fill()
        if bevel && inner.width > 4 * u && inner.height > 3 * u {
            mix(fill, .white, 0.45).setFill(); NSRect(x: inner.minX + u, y: inner.maxY - u, width: inner.width - 2 * u, height: u).fill()
            mix(fill, .black, 0.2).setFill(); NSRect(x: inner.minX + u, y: inner.minY, width: inner.width - 2 * u, height: u).fill()
        }
    }
    static func textWidth(_ s: String, _ size: CGFloat) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font(size)]).width) }
    /// Text drawn without anti-aliasing so it reads as bitmap type.
    static func text(_ s: String, at p: NSPoint, size: CGFloat = 11, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); ctx.setShouldAntialias(false); ctx.setShouldSmoothFonts(false)
        NSAttributedString(string: s, attributes: [.font: font(size), .foregroundColor: color]).draw(at: p)
        ctx.restoreGState()
    }
    static func textHeight(_ size: CGFloat) -> CGFloat { ceil(("Ag" as NSString).size(withAttributes: [.font: font(size)]).height) }

    static func ear(x: CGFloat, y: CGFloat, ink: NSColor) {
        let brown = NSColor(calibratedRed: 201 / 255, green: 153 / 255, blue: 106 / 255, alpha: 1)
        ink.setFill()
        NSRect(x: x, y: y, width: 24, height: 4).fill(); NSRect(x: x + 3, y: y + 4, width: 18, height: 4).fill(); NSRect(x: x + 6, y: y + 8, width: 12, height: 4).fill()
        brown.setFill()
        NSRect(x: x + 3, y: y, width: 18, height: 4).fill(); NSRect(x: x + 6, y: y + 4, width: 12, height: 4).fill()
    }
}

enum PxIcon {
    static let art: [String: [String]] = [
        "paw": ["..##.##..", "..##.##..", "##.....##", "##.....##", "..#####..", ".#######.", ".#######.", "..##.##.."],
        "heart": [".##...##.", "####.####", "#########", "#########", ".#######.", "..#####..", "...###...", "....#...."],
        "star": ["....#....", "....#....", "...###...", "#########", ".#######.", "..#####..", "..##.##..", ".##...##.", ".#.....#."],
        "moon": ["..###.", ".###..", "###...", "###...", "###...", ".###..", "..###."],
        "sun": [".#..#..#.", "..#####..", "#.#####.#", "..#####..", ".#..#..#."],
        "clover": [".##.##.", "#######", "#######", ".#####.", "#######", "#######", ".##.##."],
        "sparkle": ["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."],
        "bone": ["##.......##", "###########", "###########", "##.......##"],
        "ball": ["..####..", ".######.", "########", "########", "########", "########", ".######.", "..####.."],
        "file": ["#####...", "#...##..", "#...#.#.", "#...####", "#......#", "#......#", "#......#", "#......#", "#......#", "########"],
        "camera": ["..###.....", "##########", "#........#", "#..####..#", "#..#..#..#", "#..####..#", "##########"],
        "plus": ["...#...", "...#...", "...#...", "#######", "...#...", "...#...", "...#..."],
        "list": ["#.######", "........", "#.######", "........", "#.######"],
        "x": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
        "pin": [".#####.", ".#...#.", ".#...#.", "..###..", "...#...", "...#...", "...#..."],
        "eye": ["..#####..", ".#.....#.", "#..###..#", ".#.###.#.", "..#####.."],
        "check": ["......##", ".....##.", "#...##..", "##.##...", ".###....", "..#....."],
    ]
    static var cache: [String: NSImage] = [:]
    static func size(_ name: String, scale: CGFloat) -> NSSize {
        guard let a = art[name] else { return .zero }
        return NSSize(width: CGFloat(a[0].count) * scale, height: CGFloat(a.count) * scale)
    }
    static func image(_ name: String, color: NSColor, scale: CGFloat = 2) -> NSImage? {
        guard let rows = art[name] else { return nil }
        let key = "\(name)|\(color.description)|\(scale)"
        if let c = cache[key] { return c }
        let img = NSImage(size: size(name, scale: scale))
        img.lockFocus()
        color.setFill()
        for (r, line) in rows.enumerated() { for (c, ch) in line.enumerated() where ch == "#" {
            NSRect(x: CGFloat(c) * scale, y: CGFloat(rows.count - 1 - r) * scale, width: scale, height: scale).fill()
        } }
        img.unlockFocus()
        cache[key] = img
        return img
    }
    @discardableResult static func draw(_ name: String, at p: NSPoint, color: NSColor, scale: CGFloat = 2) -> CGFloat {
        guard let img = image(name, color: color, scale: scale) else { return 0 }
        img.draw(at: p, from: .zero, operation: .sourceOver, fraction: 1)
        return img.size.width
    }
    static func attachment(_ name: String, color: NSColor, scale: CGFloat = 2) -> NSAttributedString {
        guard let img = image(name, color: color, scale: scale) else { return NSAttributedString(string: "") }
        let a = NSTextAttachment(); a.image = img
        a.bounds = NSRect(x: 0, y: -2, width: img.size.width, height: img.size.height)
        return NSAttributedString(attachment: a)
    }
}

/// Strips emoji from model output / canned phrases so the UI stays in the pixel style.
func noEmoji(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    for u in s.unicodeScalars {
        let v = u.value
        if v >= 0x1F000 || (0x2600...0x27BF).contains(v) || (0x2B00...0x2BFF).contains(v) || v == 0xFE0F || v == 0x200D || u.properties.isEmojiPresentation { continue }
        out.append(u)
    }
    return String(out).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
}

class PixelBoxView: NSView {
    var u: CGFloat = 3
    var dropShadow = false
    var fillOverride: NSColor?
    override func draw(_ r: NSRect) {
        let t = curTheme()
        var rect = bounds
        if dropShadow { rect = NSRect(x: bounds.minX, y: bounds.minY + u, width: bounds.width - u, height: bounds.height - u) }
        Px.box(rect, fill: fillOverride ?? t.bg, ink: t.text, u: u, shadow: dropShadow ? Px.mix(t.border, t.text, 0.35).withAlphaComponent(0.55) : nil)
    }
}

/// Window content: the box with tofi's ears sticking out of the top corners.
final class PixelWindowView: NSView {
    static let earH: CGFloat = 12
    init(inner: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: inner.frame.width, height: inner.frame.height + PixelWindowView.earH))
        inner.frame.origin = .zero
        addSubview(inner)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let ink = curTheme().text
        let top = bounds.height - PixelWindowView.earH
        Px.ear(x: 22, y: top - 1, ink: ink)
        Px.ear(x: bounds.width - 22 - 24 - 3, y: top - 1, ink: ink)
    }
}

func pxTitle(_ icon: String?, _ text: String, color: NSColor, size: CGFloat = 13) -> NSTextField {
    let a = NSMutableAttributedString()
    if let i = icon { a.append(PxIcon.attachment(i, color: color)); a.append(NSAttributedString(string: " ")) }
    a.append(NSAttributedString(string: text, attributes: [.font: Px.font(size), .foregroundColor: color]))
    let l = NSTextField(labelWithAttributedString: a)
    l.lineBreakMode = .byTruncatingTail
    return l
}

struct Theme {
    let title: String, text: NSColor, accent: NSColor, fill: NSColor, border: NSColor, bg: NSColor, i1: String, i2: String
    static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
    static let order = ["boy", "mint", "sunny", "night", "pink"]
    static let all: [String: Theme] = [
        "boy": Theme(title: "Голубая", text: c(0.14, 0.24, 0.42), accent: c(0.18, 0.44, 0.86), fill: c(0.92, 0.96, 1), border: c(0.45, 0.70, 0.98), bg: c(0.93, 0.96, 1), i1: "paw", i2: "star"),
        "mint": Theme(title: "Мятная", text: c(0.12, 0.33, 0.27), accent: c(0.10, 0.60, 0.46), fill: c(0.92, 1, 0.96), border: c(0.50, 0.84, 0.70), bg: c(0.93, 1, 0.96), i1: "paw", i2: "clover"),
        "sunny": Theme(title: "Солнечная", text: c(0.45, 0.25, 0.05), accent: c(0.93, 0.48, 0.08), fill: c(1, 0.96, 0.88), border: c(1, 0.75, 0.40), bg: c(1, 0.97, 0.90), i1: "bone", i2: "sun"),
        "night": Theme(title: "Ночная", text: c(0.88, 0.90, 1), accent: c(0.62, 0.68, 1), fill: c(0.14, 0.16, 0.28), border: c(0.45, 0.50, 0.95), bg: c(0.12, 0.13, 0.24), i1: "moon", i2: "sparkle"),
        "pink": Theme(title: "Розовая", text: c(0.42, 0.24, 0.30), accent: c(0.86, 0.36, 0.55), fill: c(1, 0.94, 0.96), border: c(0.98, 0.66, 0.78), bg: c(1, 0.95, 0.97), i1: "paw", i2: "heart"),
    ]
}
/// Models installed in the local server (Ollama /api/tags, falling back to OpenAI-style /v1/models).
var localModels: [String] = []
func fetchLocalModels() -> [String] {
    let base = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    func get(_ path: String) -> Any? {
        guard let u = URL(string: base + path) else { return nil }
        var req = URLRequest(url: u); req.timeoutInterval = 4
        let sem = DispatchSemaphore(value: 0); var out: Any?
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d = d { out = try? JSONSerialization.jsonObject(with: d) }; sem.signal()
        }.resume(); sem.wait(); return out
    }
    var names: [String] = []
    if let j = get("/api/tags") as? [String: Any], let a = j["models"] as? [[String: Any]] { names = a.compactMap { $0["name"] as? String } }
    else if let j = get("/v1/models") as? [String: Any], let a = j["data"] as? [[String: Any]] { names = a.compactMap { $0["id"] as? String } }
    return names.filter { !$0.lowercased().contains("embed") }
}
func refreshLocalModels(_ done: (() -> Void)? = nil) {
    DispatchQueue.global().async {
        let m = fetchLocalModels()
        DispatchQueue.main.async { localModels = m; done?() }
    }
}
func resolveModel(_ pref: String) -> String { !pref.isEmpty ? pref : (localModels.first ?? "") }
func curTheme() -> Theme { Theme.all[settings.theme] ?? Theme.all["boy"]! }
func petName() -> String { settings.name.isEmpty ? "Мальтипу" : settings.name }
func persona() -> String {
    "Ты — милый говорящий мальтипу-талисман, мальчик (говори о себе в мужском роде), живёшь на рабочем столе пользователя." +
    (settings.name.isEmpty ? "" : " Тебя зовут \(settings.name) — это твоё имя навсегда, откликайся на него.")
}

// MARK: markdown + Claude session helpers
func mdInline(_ s: String, font: NSFont, color: NSColor) -> NSAttributedString {
    var opts = AttributedString.MarkdownParsingOptions()
    opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
    opts.failurePolicy = .returnPartiallyParsedIfPossible
    guard let a = try? AttributedString(markdown: s, options: opts) else {
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }
    let out = NSMutableAttributedString()
    for run in a.runs {
        let txt = String(a[run.range].characters)
        let intent = run.inlinePresentationIntent ?? []
        var f = font
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        if intent.contains(.code) {
            f = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attrs[.backgroundColor] = curTheme().fill
        } else {
            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            if !traits.isEmpty { f = NSFontManager.shared.convert(font, toHaveTrait: traits) }
        }
        if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let l = run.link { attrs[.link] = l; attrs[.foregroundColor] = curTheme().accent; attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        attrs[.font] = f
        out.append(NSAttributedString(string: txt, attributes: attrs))
    }
    return out
}

func mdAttributed(_ src: String, color: NSColor, size: CGFloat = 14) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let base = NSFont.systemFont(ofSize: size)
    var inCode = false
    var lines = src.components(separatedBy: "\n")
    while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { lines.removeLast() }
    func match(_ pat: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pat), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }
    for raw in lines {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { inCode.toggle(); continue }
        let ps = NSMutableParagraphStyle(); ps.paragraphSpacing = 2
        if inCode {
            out.append(NSAttributedString(string: raw + "\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular), .foregroundColor: color, .backgroundColor: curTheme().fill, .paragraphStyle: ps]))
            continue
        }
        var body = raw, prefix = "", font = base
        if let m = match(#"^\s{0,3}(#{1,6})\s+(.*)$"#, raw) {
            font = NSFont.boldSystemFont(ofSize: size + (m[1].count <= 1 ? 3 : (m[1].count == 2 ? 2 : 1))); body = m[2]
            ps.paragraphSpacingBefore = 4
        } else if let m = match(#"^(\s*)[-*+]\s+(.*)$"#, raw) {
            let lvl = CGFloat(m[1].count / 2)
            prefix = "•  "; body = m[2]; ps.firstLineHeadIndent = 4 + lvl * 14; ps.headIndent = 20 + lvl * 14
        } else if let m = match(#"^(\s*)(\d+)[.)]\s+(.*)$"#, raw) {
            let lvl = CGFloat(m[1].count / 2)
            prefix = m[2] + ".  "; body = m[3]; ps.firstLineHeadIndent = 4 + lvl * 14; ps.headIndent = 22 + lvl * 14
        } else if trimmed.hasPrefix(">") {
            prefix = "▎ "; body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            font = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask); ps.headIndent = 12
        } else if match(#"^\s*([-*_])\1{2,}\s*$"#, raw) != nil {
            out.append(NSAttributedString(string: "────────────\n", attributes: [.font: base, .foregroundColor: color.withAlphaComponent(0.4)])); continue
        }
        let line = NSMutableAttributedString()
        if !prefix.isEmpty { line.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color])) }
        line.append(mdInline(body, font: font, color: color))
        line.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        line.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: line.length))
        out.append(line)
    }
    if out.length > 0, out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
    return out
}
func mdPlain(_ s: String) -> String { mdAttributed(s, color: .black).string }

struct Dialog: Codable { var id: String; var title: String; var updated: Double }
func loadDialogs() -> [Dialog] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: home + "/dialogs.json")),
          let a = try? JSONDecoder().decode([Dialog].self, from: d) else { return [] }
    return a
}
func saveDialogs(_ a: [Dialog]) { try? JSONEncoder().encode(a).write(to: URL(fileURLWithPath: home + "/dialogs.json")) }
func dialogTitle(from q: String) -> String {
    let one = q.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    return one.count > 38 ? String(one.prefix(36)) + "…" : (one.isEmpty ? "Диалог" : one)
}

final class DialogRow: NSView {
    let title: String, sub: String, current: Bool
    var onOpen: (() -> Void)?, onDelete: (() -> Void)?
    init(width: CGFloat, title: String, sub: String, current: Bool) {
        self.title = title; self.sub = sub; self.current = current
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 48))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x > bounds.width - 38 { onDelete?() } else { onOpen?() }
    }
    override func draw(_ r: NSRect) {
        let t = curTheme()
        Px.box(bounds, fill: current ? Px.mix(t.fill, t.accent, 0.3) : t.fill, ink: current ? t.accent : t.text, u: 3, bevel: true)
        var tt = title
        while tt.count > 3 && Px.textWidth(tt, 12) > bounds.width - 60 { tt = String(tt.dropLast(2)) + "…" }
        Px.text(tt, at: NSPoint(x: 14, y: 26), size: 12, color: t.text)
        Px.text(sub, at: NSPoint(x: 14, y: 9), size: 10, color: Px.mix(t.text, t.bg, 0.4))
        PxIcon.draw("x", at: NSPoint(x: bounds.width - 28, y: 17), color: t.accent, scale: 2)
    }
}


/// Dialogs are kept locally as ~/.maltipoo-local/chats/<id>.json.
func sessionPath(_ id: String) -> String { home + "/chats/" + id + ".json" }
func readSession(_ id: String) -> [(uuid: String, role: String, text: String)] {
    guard !id.isEmpty, let d = try? Data(contentsOf: URL(fileURLWithPath: sessionPath(id))),
          let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return [] }
    return arr.compactMap { e in
        guard let u = e["uuid"], let r = e["role"], let t = e["text"] else { return nil }
        return (u, r, t)
    }
}
func appendSession(_ id: String, role: String, text: String) {
    try? FileManager.default.createDirectory(atPath: home + "/chats", withIntermediateDirectories: true)
    var arr = readSession(id).map { ["uuid": $0.uuid, "role": $0.role, "text": $0.text] }
    arr.append(["uuid": UUID().uuidString, "role": role, "text": text])
    if let d = try? JSONSerialization.data(withJSONObject: arr) { try? d.write(to: URL(fileURLWithPath: sessionPath(id)), options: .atomic) }
}

func gifPath(_ n: String) -> String {
    let orig = "\(home)/gifs_orig/\(n).gif"
    if !settings.showCollar && FileManager.default.fileExists(atPath: orig) { return orig }
    return "\(home)/gifs/\(n).gif"
}
func gif(_ n: String) -> NSImage? { NSImage(contentsOfFile: gifPath(n)) }


let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
/// Local models have no file tools, so attachments are inlined: text files as text, folders as a listing, images as vision input.
func attachmentContext(_ paths: [String]) -> (text: String, images: [String]) {
    let fm = FileManager.default
    var text = "", images: [String] = []
    for p in paths {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
        let u = URL(fileURLWithPath: p)
        if isDir.boolValue {
            let items = ((try? fm.contentsOfDirectory(atPath: p)) ?? []).sorted().prefix(150)
            text += "\n\n=== Папка \(p) ===\n" + items.joined(separator: "\n")
        } else if imageExts.contains(u.pathExtension.lowercased()) {
            images.append(p)
        } else if let d = try? Data(contentsOf: u), d.count < 4_000_000, let t = String(data: d.prefix(16000), encoding: .utf8) {
            text += "\n\n=== Файл \(p)\(d.count > 16000 ? " (первые 16000 байт)" : "") ===\n" + t
        } else {
            text += "\n\n=== Файл \(p) — бинарный, прочитать нельзя ==="
        }
    }
    return (text, images)
}
func downscaledJPEGBase64(_ path: String, maxSide: CGFloat = 1280) -> String? {
    guard let img = NSImage(contentsOfFile: path), let rep = img.representations.first else { return nil }
    let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
    guard w > 0, h > 0 else { return nil }
    let k = min(1, maxSide / max(w, h))
    let nw = Int(w * k), nh = Int(h * k)
    guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: nw, pixelsHigh: nh, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    img.draw(in: NSRect(x: 0, y: 0, width: nw, height: nh), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.base64EncodedString()
}

/// One chat completion against the local OpenAI-compatible server (Ollama, LM Studio, llama.cpp, ...). Blocking.
func runLocal(prompt: String, system: String?, files: [String] = [], history: [(role: String, text: String)] = [], model: String) -> String? {
    let m = resolveModel(model)
    guard !m.isEmpty else { dlog("runLocal: no local model"); return nil }
    let base = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    guard let url = URL(string: base + "/v1/chat/completions") else { return nil }
    let ctx = attachmentContext(files)
    var msgs: [[String: Any]] = []
    if let sys = system { msgs.append(["role": "system", "content": sys]) }
    for h in history { msgs.append(["role": h.role, "content": h.text]) }
    let userText = prompt + ctx.text
    if ctx.images.isEmpty { msgs.append(["role": "user", "content": userText]) }
    else {
        var parts: [[String: Any]] = [["type": "text", "text": userText]]
        for p in ctx.images { if let b = downscaledJPEGBase64(p) { parts.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + b]]) } }
        msgs.append(["role": "user", "content": parts])
    }
    var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 300
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": m, "messages": msgs, "stream": false])
    let sem = DispatchSemaphore(value: 0); var result: String?
    URLSession.shared.dataTask(with: req) { d, resp, err in
        defer { sem.signal() }
        guard let d = d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { dlog("runLocal: \(err?.localizedDescription ?? "bad response")"); return }
        if let e = j["error"] { dlog("runLocal error: \(e)"); return }
        guard let ch = (j["choices"] as? [[String: Any]])?.first, let msg = ch["message"] as? [String: Any], var t = msg["content"] as? String else { return }
        t = t.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { result = t }
    }.resume()
    sem.wait()
    return result
}

func dirOf(_ u: URL) -> String {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
    return isDir.boolValue ? u.path : u.deletingLastPathComponent().path
}

final class DropView: PixelBoxView {
    var onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty { return false }
        onDrop?(urls); return true
    }
}


final class BubbleView: NSView {
    let label = NSTextField(labelWithString: "")
    let full: String
    let tail: CGFloat = 14
    var tailX: CGFloat = 40
    var onClick: (() -> Void)?
    var shown = 0
    var typer: Timer?
    static let font: NSFont = Px.font(12)
    init(text: String) {
        let text = mdPlain(noEmoji(text))
        full = text
        let probe = NSTextField(wrappingLabelWithString: text)
        probe.font = BubbleView.font; probe.preferredMaxLayoutWidth = 250
        let sz = probe.sizeThatFits(NSSize(width: 250, height: 3000))
        let w = max(96, min(sz.width, 250)) + 40, h = sz.height + 36
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h + tail + 6))
        label.isBezeled = false; label.drawsBackground = false
        label.font = BubbleView.font
        label.textColor = curTheme().text
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 250
        label.frame = NSRect(x: 20, y: tail + 18, width: w - 40, height: sz.height)
        addSubview(label)
        typer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let s = self else { t.invalidate(); return }
            s.shown = min(s.full.count, s.shown + 1)
            s.label.stringValue = String(s.full.prefix(s.shown))
            if s.shown >= s.full.count { t.invalidate() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { typer?.invalidate(); onClick?() }
    override func draw(_ r: NSRect) {
        let t = curTheme()
        let body = NSRect(x: 2, y: tail + 2, width: bounds.width - 6, height: bounds.height - tail - 4)
        // stepped tail
        t.text.setFill()
        NSRect(x: tailX - 6, y: body.minY - 3, width: 12, height: 3).fill()
        NSRect(x: tailX - 3, y: body.minY - 6, width: 6, height: 3).fill()
        Px.box(body, fill: t.fill, ink: t.text, u: 3, shadow: Px.mix(t.border, t.text, 0.35).withAlphaComponent(0.5))
        t.fill.setFill(); NSRect(x: tailX - 3, y: body.minY - 3, width: 6, height: 6).fill()
        PxIcon.draw(t.i1, at: NSPoint(x: bounds.width - 34, y: bounds.height - 22), color: t.accent, scale: 2)
        PxIcon.draw(t.i2, at: NSPoint(x: 10, y: bounds.height - 21), color: t.accent, scale: 2)
    }
}



func fileURLs(_ pb: NSPasteboard) -> [URL] {
    pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
}

final class FieldEditor: NSTextView {
    var onFiles: (([URL]) -> Void)?
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        fileURLs(s.draggingPasteboard).isEmpty ? super.draggingEntered(s) : .copy
    }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let u = fileURLs(s.draggingPasteboard)
        if u.isEmpty { return super.performDragOperation(s) }
        onFiles?(u); return true
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let u = fileURLs(pb)
        if !u.isEmpty { onFiles?(u); return }
        if pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil,
           let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let dir = home + "/pasted"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let f = URL(fileURLWithPath: dir + "/image-\(Int(Date().timeIntervalSince1970)).png")
            if (try? png.write(to: f)) != nil { onFiles?([f]); return }
        }
        super.paste(sender)
    }
}

final class ChatPanel: NSPanel, NSDraggingDestination {
    var onFiles: (([URL]) -> Void)?
    func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty { return false }
        onFiles?(urls); return true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ChatController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let editor = FieldEditor()
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if let c = client as? NSTextField, c === input {
            editor.isFieldEditor = true; editor.onFiles = { [weak self] urls in self?.attach(urls) }
            return editor
        }
        return nil
    }
    var panel: ChatPanel?
    let text = NSTextView()
    let input = NSTextField()
    var history: [(String, String)] = []
    var waiting = false
    var attached: [URL] = []
    var seen = Set<String>(), loaded = false
    var poller: Timer?
    weak var dog: DogView?
    func show(_ e: (uuid: String, role: String, text: String)) {
        append(e.role == "user" ? "Ты:" : "🐾", e.text, pinkName: e.role != "user")
        history.append((e.role == "user" ? "user" : "dog", e.text))
    }
    func loadSession() {
        loaded = true
        for e in readSession(settings.chatSession).suffix(40) { seen.insert(e.uuid); show(e) }
    }
    func markSeen() { for e in readSession(settings.chatSession) { seen.insert(e.uuid) } }
    /// Messages added to the shared session from the Claude app show up here.
    func syncFromApp() {
        guard isOpen, !waiting, !settings.chatSession.isEmpty else { return }
        for e in readSession(settings.chatSession) where !seen.contains(e.uuid) { seen.insert(e.uuid); show(e) }
    }
    var dialogs: [Dialog] = loadDialogs()
    var listView: NSView?
    func ensureCurrentListed() {
        let sid = settings.chatSession
        guard !sid.isEmpty, !dialogs.contains(where: { $0.id == sid }) else { return }
        let first = readSession(sid).first(where: { $0.role == "user" })?.text ?? ""
        dialogs.append(Dialog(id: sid, title: dialogTitle(from: first), updated: Date().timeIntervalSince1970)); saveDialogs(dialogs)
    }
    func hideList() { listView?.removeFromSuperview(); listView = nil }
    func toggleList() { listView != nil ? hideList() : showList() }
    func showList() {
        guard let bg = panel?.contentView else { return }
        hideList(); ensureCurrentListed()
        let t = curTheme()
        let box = PixelBoxView(frame: NSRect(x: 12, y: 56, width: bg.frame.width - 24, height: bg.frame.height - 56 - 82))
        box.u = 3
        let head = pxTitle(nil, "Диалоги", color: t.accent, size: 12)
        head.frame = NSRect(x: 14, y: box.frame.height - 28, width: 200, height: 18); box.addSubview(head)
        let sv = NSScrollView(frame: NSRect(x: 8, y: 8, width: box.frame.width - 16, height: box.frame.height - 40))
        sv.hasVerticalScroller = true; sv.drawsBackground = false; sv.borderType = .noBorder; sv.autohidesScrollers = true
        let rw = sv.frame.width - 4
        let sorted = dialogs.sorted { $0.updated > $1.updated }
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: rw, height: max(sv.frame.height, CGFloat(sorted.count) * 54 + 4)))
        let rel = RelativeDateTimeFormatter(); rel.locale = Locale(identifier: "ru_RU"); rel.unitsStyle = .short
        if sorted.isEmpty {
            let l = NSTextField(wrappingLabelWithString: "Пока пусто. Напиши что-нибудь, и диалог появится здесь.")
            l.font = NSFont.systemFont(ofSize: 12.5); l.textColor = t.text.withAlphaComponent(0.7)
            l.frame = NSRect(x: 8, y: 8, width: rw - 16, height: 40); doc.addSubview(l)
        }
        for (i, d) in sorted.enumerated() {
            let cur = d.id == settings.chatSession
            let row = DialogRow(width: rw, title: d.title, sub: rel.localizedString(for: Date(timeIntervalSince1970: d.updated), relativeTo: Date()) + (cur ? " · открыт" : ""), current: cur)
            row.frame.origin = NSPoint(x: 0, y: CGFloat(i) * 54 + 2)
            row.onOpen = { [weak self] in self?.switchTo(d.id) }
            row.onDelete = { [weak self] in self?.removeDialog(d.id) }
            doc.addSubview(row)
        }
        sv.documentView = doc
        box.addSubview(sv)
        bg.addSubview(box)
        listView = box
    }
    func switchTo(_ id: String) {
        guard !waiting else { return }
        settings.chatSession = id; settings.save(); seen = []; history = []
        text.textStorage?.setAttributedString(NSAttributedString(string: ""))
        loadSession()
        if history.isEmpty { append("🐾", "Привет! Продолжим?", pinkName: true) }
        hideList()
    }
    func removeDialog(_ id: String) {
        dialogs.removeAll { $0.id == id }; saveDialogs(dialogs)
        if id == settings.chatSession { newDialog() }   // the session file itself stays untouched
        if listView != nil { showList() }
    }
    func newDialog() {
        guard !waiting else { return }
        hideList()
        settings.chatSession = ""; settings.save(); seen = []; history = []; loaded = true
        text.textStorage?.setAttributedString(NSAttributedString(string: ""))
        append("🐾", "Начали новый диалог! О чём поболтаем?", pinkName: true)
    }
    var isOpen: Bool { panel?.isVisible ?? false }
    var brown: NSColor { curTheme().text }
    var pink: NSColor { curTheme().accent }
    func rebuild() {
        let was = isOpen
        panel?.orderOut(nil); panel = nil
        if was, let w = dog?.window { open(near: w) }
    }

    func toggle(near w: NSWindow) { isOpen ? close() : open(near: w) }
    func close() { panel?.orderOut(nil); poller?.invalidate() }
    func open(near w: NSWindow) {
        if panel == nil { build() }
        if !loaded { loadSession() }
        poller?.invalidate()
        poller = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.syncFromApp() }
        guard let p = panel else { return }
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = w.frame.midX - p.frame.width + 40
        x = min(max(scr.minX + 8, x), scr.maxX - p.frame.width - 8)
        var y = w.frame.maxY + 6
        if y + p.frame.height > scr.maxY { y = max(scr.minY + 8, scr.maxY - p.frame.height - 8) }
        p.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(input)
        if history.isEmpty { append("🐾", settings.name.isEmpty ? "Гав! Я тут. О чём поболтаем?" : "Гав! Я \(settings.name). О чём поболтаем?", pinkName: true) }
    }
    var modelBar: NSView?, attachBar: NSView?
    func build() {
        let W: CGFloat = 410, H: CGFloat = 500
        listView = nil
        let p = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H + PixelWindowView.earH),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        let bg = DropView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        bg.onDrop = { [weak self] urls in self?.attach(urls) }
        bg.dropShadow = true
        let title = pxTitle(curTheme().i1, petName(), color: pink, size: 14)
        title.frame = NSRect(x: 20, y: H - 40, width: 140, height: 22)
        bg.addSubview(title)
        let nb = Chip("plus|Новый") { [weak self] in self?.newDialog() }
        nb.frame.origin = NSPoint(x: W - nb.frame.width - 18, y: H - 44); bg.addSubview(nb)
        let lb = Chip("list|Диалоги") { [weak self] in self?.toggleList() }
        lb.frame.origin = NSPoint(x: nb.frame.minX - lb.frame.width - 6, y: H - 44); bg.addSubview(lb)
        let mb = NSView(frame: NSRect(x: 12, y: H - 74, width: W - 24, height: 32))
        bg.addSubview(mb); modelBar = mb
        let sv = NSScrollView(frame: NSRect(x: 12, y: 94, width: W - 24, height: H - 94 - 82))
        sv.hasVerticalScroller = true; sv.drawsBackground = false; sv.borderType = .noBorder
        text.isEditable = false; text.drawsBackground = false
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        sv.documentView = text
        bg.addSubview(sv)
        let ab = NSView(frame: NSRect(x: 12, y: 56, width: W - 24, height: 32))
        bg.addSubview(ab); attachBar = ab
        let clip = Chip("file|") { [weak self] in self?.pickFiles() }
        clip.frame.origin = NSPoint(x: 16, y: 16); bg.addSubview(clip)
        let shot = Chip("camera|") { [weak self] in self?.shootAndAsk(full: false, question: nil) }
        shot.frame.origin = NSPoint(x: clip.frame.maxX + 4, y: 16); bg.addSubview(shot)
        input.frame = NSRect(x: shot.frame.maxX + 16, y: 20, width: W - shot.frame.maxX - 16 - 24, height: 22)
        let inBox = PixelBoxView(frame: NSRect(x: shot.frame.maxX + 6, y: 14, width: W - shot.frame.maxX - 6 - 18, height: 34))
        inBox.u = 2; inBox.fillOverride = curTheme().fill; bg.addSubview(inBox)
        input.placeholderString = "Напиши… (/скрин — скриншот)"
        input.font = Px.font(12); input.textColor = curTheme().text
        input.isBordered = false; input.isBezeled = false; input.drawsBackground = false; input.focusRingType = .none
        input.delegate = self
        bg.addSubview(input)
        text.unregisterDraggedTypes(); sv.unregisterDraggedTypes(); input.unregisterDraggedTypes()
        p.contentView = PixelWindowView(inner: bg)
        panel = p
        p.registerForDraggedTypes([.fileURL])
        p.onFiles = { [weak self] urls in self?.attach(urls) }
        p.delegate = self
        refreshModelBar(); refreshAttachBar()
    }
    func refreshModelBar() {
        guard let bar = modelBar else { return }
        bar.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        let cur = resolveModel(settings.chatModel)
        let opts: [(String, String)] = localModels.isEmpty ? [("", "модели не найдены: запусти Ollama")] : localModels.map { ($0, String($0.prefix(18))) }
        for o in opts {
            let c = Chip(o.1, on: cur == o.0) { [weak self] in
                if !o.0.isEmpty { settings.chatModel = o.0; settings.save() }; self?.refreshModelBar()
            }
            c.frame.origin = NSPoint(x: x, y: 2); bar.addSubview(c); x += c.frame.width + 5
        }
    }
    func refreshAttachBar() {
        guard let bar = attachBar else { return }
        bar.subviews.forEach { $0.removeFromSuperview() }
        if attached.isEmpty {
            let l = NSTextField(labelWithString: "Перетащи файлы или картинки сюда, вставь из буфера или жми кнопки слева")
            l.font = NSFont.systemFont(ofSize: 11.5); l.textColor = brown.withAlphaComponent(0.6)
            l.frame = NSRect(x: 4, y: 7, width: bar.frame.width - 8, height: 16); bar.addSubview(l)
            return
        }
        var x: CGFloat = 0
        for (i, u) in attached.enumerated() {
            var name = u.lastPathComponent
            if name.count > 16 { name = String(name.prefix(14)) + "…" }
            let c = Chip("x|" + name, on: false) { [weak self] in
                guard let s = self, i < s.attached.count else { return }
                s.attached.remove(at: i); s.refreshAttachBar()
            }
            if x + c.frame.width > bar.frame.width - 70 { 
                let more = Chip("+\(attached.count - i)") { [weak self] in self?.attached.removeAll(); self?.refreshAttachBar() }
                more.frame.origin = NSPoint(x: x, y: 2); bar.addSubview(more); x += more.frame.width + 5
                break
            }
            c.frame.origin = NSPoint(x: x, y: 2); bar.addSubview(c); x += c.frame.width + 5
        }
        let clear = Chip("Убрать все") { [weak self] in self?.attached.removeAll(); self?.refreshAttachBar() }
        clear.frame.origin = NSPoint(x: bar.frame.width - clear.frame.width, y: 2); bar.addSubview(clear)
    }
    /// Hides the chat, lets the user grab a region (or the whole main display), and attaches the PNG to the dialog.
    func captureScreenshot(full: Bool, done: @escaping (Bool) -> Void = { _ in }) {
        let dir = home + "/pasted"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/screen-\(Int(Date().timeIntervalSince1970)).png"
        panel?.orderOut(nil)
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.3)
            let cap = Process()
            cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            cap.arguments = full ? ["-x", "-m", path] : ["-i", "-x", path]
            try? cap.run(); cap.waitUntilExit()
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.panel?.makeKeyAndOrderFront(nil); self.panel?.makeFirstResponder(self.input)
                if (size ?? 0) > 0 { self.attach([URL(fileURLWithPath: path)]); done(true) }
                else {
                    self.append("🐾", "Скриншот не получился или отменён. Если не выходит совсем, проверь доступ к записи экрана в системных настройках.", pinkName: true)
                    done(false)
                }
            }
        }
    }
    /// Grab a screenshot, attach it and send it right away (typed text, if any, becomes the question).
    func shootAndAsk(full: Bool, question: String?) {
        guard !waiting else { return }
        let typed = (question ?? input.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        input.stringValue = ""
        captureScreenshot(full: full) { [weak self] ok in
            guard let s = self else { return }
            if ok { s.input.stringValue = typed.isEmpty ? "Что на этом скриншоте? Если видишь проблему, подскажи, как её решить." : typed; s.send() }
            else { s.input.stringValue = typed }
        }
    }
    func pickFiles() {
        let op = NSOpenPanel()
        op.canChooseFiles = true; op.canChooseDirectories = true; op.allowsMultipleSelection = true
        op.prompt = "Прикрепить"
        op.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        if op.runModal() == .OK { attach(op.urls) }
        panel?.makeKeyAndOrderFront(nil)
    }
    func attach(_ urls: [URL]) {
        dlog("chat attach: \(urls.map { $0.path })")
        let new = urls.filter { u in !attached.contains(u) }
        attached.append(contentsOf: new)
        refreshAttachBar()
        append("📎", "Прикреплено: " + urls.map { $0.lastPathComponent }.joined(separator: ", ") + ". Спрашивай про это или проси что-то изменить.", pinkName: true)
    }
    func append(_ who: String, _ msg: String, pinkName: Bool) {
        let a = NSMutableAttributedString()
        let whoFont = Px.font(12)
        if who == "🐾" {
            a.append(PxIcon.attachment(curTheme().i1, color: pink))
            a.append(NSAttributedString(string: " " + petName() + ": ", attributes: [.font: whoFont, .foregroundColor: pink]))
        } else if who == "📎" {
            a.append(PxIcon.attachment("file", color: pink)); a.append(NSAttributedString(string: " ", attributes: [.font: whoFont]))
        } else {
            a.append(NSAttributedString(string: who + " ", attributes: [.font: whoFont, .foregroundColor: pinkName ? pink : brown]))
        }
        if pinkName { a.append(mdAttributed(noEmoji(msg), color: brown)) }
        else { a.append(NSAttributedString(string: msg, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: brown])) }
        a.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        text.textStorage?.append(a)
        text.scrollToEndOfDocument(nil)
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { send(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
    func send() {
        let q = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        dlog("chat send: \(q)")
        if q.isEmpty || waiting { return }
        let low = q.lowercased()
        for (cmd, full) in [("/скрин", false), ("/screen", false), ("/экран", true)] where low.hasPrefix(cmd) {
            // "/скрин что тут не так?" grabs a region, attaches it and asks the question right away; "/экран ..." takes the whole screen
            let rest = String(q.dropFirst(cmd.count)).trimmingCharacters(in: .whitespaces)
            shootAndAsk(full: full, question: rest)
            return
        }
        if q.lowercased().hasPrefix("/имя") {
            dog?.setName(String(q.dropFirst(4)))
            input.stringValue = ""
            append("🐾", settings.name.isEmpty ? "Имя убрано." : "Теперь меня зовут \(settings.name)! Гав!", pinkName: true)
            return
        }
        input.stringValue = ""
        append("Ты:", q, pinkName: false)
        history.append(("user", q))
        waiting = true; dog?.show("Thinking")
        let files = attached
        let paths = files.map { $0.path }.joined(separator: ", ")
        let rules: String
        if files.isEmpty { rules = "" }
        else {
            rules = "\n\nПрикреплённые пользователем файлы и папки: " + paths + ".\nИх содержимое приведено ниже в сообщении (картинки приложены). Ты ничего не можешь изменять, создавать или удалять — только читать и объяснять.\nВАЖНО: пока речь о файлах, отвечай обычным человеческим языком, без «гав», без милых междометий и без эмодзи, коротко и по делу."
        }
        let system = persona() + " Отвечай по-русски, тепло и коротко (1-4 предложения), без эмодзи; допустим markdown." + rules
        let note = files.isEmpty ? "" : "\n\n(Прикреплено: " + paths + ")"
        if settings.chatSession.isEmpty { settings.chatSession = UUID().uuidString.lowercased(); settings.save() }
        let sid = settings.chatSession
        hideList()
        let nowT = Date().timeIntervalSince1970
        if let i = dialogs.firstIndex(where: { $0.id == sid }) { dialogs[i].updated = nowT }
        else { dialogs.append(Dialog(id: sid, title: dialogTitle(from: q), updated: nowT)) }
        saveDialogs(dialogs)
        let prior = history.dropLast().suffix(14).map { (role: $0.0 == "user" ? "user" : "assistant", text: $0.1) }
        let model = settings.chatModel
        DispatchQueue.global().async {
            let ans = runLocal(prompt: q, system: system, files: files.map { $0.path }, history: Array(prior), model: model)
                ?? (localModels.isEmpty ? "Гав! Не вижу локальную модель. Запусти Ollama (ollama serve) 🥺" : (files.isEmpty ? "Гав! Что-то пошло не так 🥺" : "Не получилось выполнить запрос к файлам."))
            let ok = !ans.hasPrefix("Гав! Не вижу") && !ans.hasPrefix("Гав! Что-то") && !ans.hasPrefix("Не получилось")
            if ok { appendSession(sid, role: "user", text: q); appendSession(sid, role: "assistant", text: ans) }
            DispatchQueue.main.async {
                self.history.append(("dog", ans))
                self.append("🐾", ans, pinkName: true)
                self.markSeen(); self.waiting = false; self.dog?.play("Excited")
            }
        }
    }
}

// Static front-facing idle frame with the eyes erased; pupils are repainted one sprite pixel (5px) off-centre.
final class GazeFace {
    static var cache: [String: GazeFace?] = [:]
    static func get(_ n: String) -> GazeFace? {
        if let c = cache[n] { return c }
        let f = GazeFace(n); cache[n] = .some(f); return f
    }
    var base: [UInt8] = [], w = 0, h = 0
    var eyes: [(x: Int, y: Int, fur: [UInt8], left: Bool)] = []
    let step = 5
    init?(_ n: String) {
        guard n == "LookingAround" || n == "Sit",
              let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: gifPath(n)) as CFURL, nil),
              let im = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        w = im.width; h = im.height
        base = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
        func dark(_ x: Int, _ y: Int) -> Bool { let o = (y * w + x) * 4; return base[o + 3] > 200 && base[o] == 20 && base[o + 1] == 20 }
        var seen = Set<Int>(); var found: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where dark(x, y) && !seen.contains(y * w + x) {
            var st = [(x, y)]; seen.insert(y * w + x)
            var x0 = x, x1 = x, y0 = y, y1 = y, a = 0
            while let (cx, cy) = st.popLast() {
                a += 1; x0 = min(x0, cx); x1 = max(x1, cx); y0 = min(y0, cy); y1 = max(y1, cy)
                for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h && dark(nx, ny) && !seen.contains(ny * w + nx) { seen.insert(ny * w + nx); st.append((nx, ny)) }
            }
            if a >= 90 && x1 - x0 + 1 == 10 && y1 - y0 + 1 == 10 { found.append((x0, y0)) }
        } }
        guard found.count == 2 else { return nil }
        found.sort { $0.0 < $1.0 }
        for (i, e) in found.enumerated() {
            let sx = i == 0 ? e.0 - 1 : e.0 + 10, sy = e.1 + 4
            let o = (sy * w + sx) * 4
            eyes.append((e.0, e.1, [base[o], base[o + 1], base[o + 2], base[o + 3]], i == 0))
        }
        for e in eyes { fill(&base, e.x, e.y, 10, 10, e.fur) }
    }
    func fill(_ b: inout [UInt8], _ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: [UInt8]) {
        for yy in max(0, y)..<min(h, y + rh) { for xx in max(0, x)..<min(w, x + rw) {
            let o = (yy * w + xx) * 4; b[o] = c[0]; b[o + 1] = c[1]; b[o + 2] = c[2]; b[o + 3] = c[3]
        } }
    }
    func render(dx: Int, dy: Int, blink: Bool, happy: Bool = false) -> NSImage? {
        var b = base
        for e in eyes {
            // pupils converge slightly: the eye on the far side moves a bit less
            let ox = dx * step, oy = -dy * step
            if happy {   // closed, content eyes: ^ ^
                fill(&b, e.x, e.y + 2, 10, 5, [20, 20, 19, 255])
                fill(&b, e.x - 5, e.y + 7, 5, 5, [20, 20, 19, 255]); fill(&b, e.x + 10, e.y + 7, 5, 5, [20, 20, 19, 255])
            }
            else if blink { fill(&b, e.x + ox, e.y + oy + 5, 10, 5, [20, 20, 19, 255]) }
            else { fill(&b, e.x + ox, e.y + oy, 10, 10, [20, 20, 19, 255]) }
        }
        return b.withUnsafeMutableBytes { p -> NSImage? in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class Chip: NSView {
    let title: String, icon: String?, on: Bool, tint: Theme?, action: () -> Void
    static let fs: CGFloat = 11
    /// "icon|text" puts a pixel icon in front of the text.
    init(_ raw: String, icon: String? = nil, on: Bool = false, tint: Theme? = nil, action: @escaping () -> Void) {
        var t = raw, ic = icon
        if let bar = raw.firstIndex(of: "|") { ic = String(raw[..<bar]); t = String(raw[raw.index(after: bar)...]) }
        self.title = t; self.icon = ic; self.on = on; self.tint = tint; self.action = action
        let iw = ic.map { PxIcon.size($0, scale: 2).width } ?? 0
        let w = (t.isEmpty ? 0 : Px.textWidth(t, Chip.fs)) + iw + (ic != nil && !t.isEmpty ? 7 : 0) + 26
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 30))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
    override func draw(_ r: NSRect) {
        let t = tint ?? curTheme()
        Px.box(bounds, fill: on ? t.accent : t.fill, ink: t.text, u: 2, bevel: true)
        let fg = on ? t.bg : t.text
        let iw = icon.map { PxIcon.size($0, scale: 2).width } ?? 0
        let tw = title.isEmpty ? 0 : Px.textWidth(title, Chip.fs)
        let total = iw + (iw > 0 && tw > 0 ? 7 : 0) + tw
        var x = (bounds.width - total) / 2
        if let ic = icon {
            let ih = PxIcon.size(ic, scale: 2).height
            PxIcon.draw(ic, at: NSPoint(x: x, y: (bounds.height - ih) / 2), color: fg, scale: 2)
            x += iw + 7
        }
        if tw > 0 { Px.text(title, at: NSPoint(x: x, y: (bounds.height - Px.textHeight(Chip.fs)) / 2), size: Chip.fs, color: fg) }
    }
}


final class SwitchView: NSView {
    let on: Bool, action: () -> Void
    init(on: Bool, action: @escaping () -> Void) {
        self.on = on; self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 46, height: 26))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
    override func draw(_ r: NSRect) {
        let t = curTheme()
        Px.box(bounds, fill: on ? t.accent : Px.mix(t.fill, t.text, 0.15), ink: t.text, u: 2)
        let k = NSRect(x: on ? 24 : 4, y: 4, width: 18, height: 18)
        Px.box(k, fill: t.fill, ink: t.text, u: 2, bevel: true)
    }
}


final class SettingsController: NSObject, NSTextFieldDelegate {
    weak var dog: DogView?
    var panel: ChatPanel?
    var scroll: NSScrollView?
    var nameField: NSTextField?
    var isOpen: Bool { panel?.isVisible ?? false }
    let W: CGFloat = 344, H: CGFloat = 540

    func toggle(near w: NSWindow) { isOpen ? close() : open(near: w) }
    func close() { panel?.orderOut(nil) }
    func open(near w: NSWindow) {
        build()
        guard let p = panel else { return }
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let h = H + PixelWindowView.earH
        p.setContentSize(NSSize(width: W, height: h))
        var x = w.frame.midX - W + 40
        x = min(max(scr.minX + 8, x), scr.maxX - W - 8)
        var y = w.frame.maxY + 6
        if y + h > scr.maxY { y = max(scr.minY + 8, scr.maxY - h - 8) }
        p.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }
    func rebuildSoon() { DispatchQueue.main.async { self.rebuild() } }
    func rebuild() {
        guard isOpen, let old = panel else { return }
        let y = scroll?.contentView.bounds.origin.y ?? 0
        let frame = old.frame
        build()
        guard let p = panel else { return }
        p.setFrame(frame, display: true)
        if let sv = scroll { sv.contentView.scroll(to: NSPoint(x: 0, y: y)); sv.reflectScrolledClipView(sv.contentView) }
        old.orderOut(nil)
        p.makeKeyAndOrderFront(nil)
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { saveName(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
    func saveName() { dog?.setName(nameField?.stringValue ?? "") }
    func mi(_ v: Any) -> NSMenuItem { let i = NSMenuItem(); i.representedObject = v; return i }

    func build() {
        guard let dog = dog else { return }
        let t = curTheme()
        let p = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H + PixelWindowView.earH), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        let bg = PixelBoxView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        bg.dropShadow = true
        let title = pxTitle(t.i1, "Настройки: " + petName(), color: t.accent, size: 13)
        title.frame = NSRect(x: 20, y: H - 40, width: W - 130, height: 22)
        bg.addSubview(title)
        let closeChip = Chip("check|Готово", on: true) { [weak self] in self?.close() }
        closeChip.frame.origin = NSPoint(x: W - closeChip.frame.width - 18, y: H - 44)
        bg.addSubview(closeChip)

        let docW = W - 24
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: docW, height: 100))
        var y: CGFloat = 6
        func act(_ f: @escaping () -> Void) -> () -> Void { { [weak self] in f(); self?.rebuildSoon() } }
        func header(_ s: String) {
            y += 6
            let l = NSTextField(labelWithString: s)
            l.font = Px.font(12); l.textColor = t.accent
            l.frame = NSRect(x: 6, y: y, width: docW - 12, height: 18); doc.addSubview(l); y += 24
        }
        func chips(_ items: [(String, Bool, Theme?, () -> Void)]) {
            var x: CGFloat = 6, rowY = y
            for it in items {
                let c = Chip(it.0, on: it.1, tint: it.2, action: act(it.3))
                if x + c.frame.width > docW - 6 && x > 6 { x = 6; rowY += 34 }
                c.frame.origin = NSPoint(x: x, y: rowY); doc.addSubview(c); x += c.frame.width + 6
            }
            y = rowY + 34
        }
        func toggleRow(_ s: String, _ on: Bool, _ f: @escaping () -> Void) {
            let l = NSTextField(wrappingLabelWithString: s)
            l.font = Px.font(11); l.textColor = t.text
            l.frame = NSRect(x: 6, y: y + 2, width: docW - 76, height: 34)
            doc.addSubview(l)
            let sw = SwitchView(on: on, action: act(f))
            sw.frame.origin = NSPoint(x: docW - 56, y: y + 4); doc.addSubview(sw)
            y += 40
        }
        func opts<T: Equatable>(_ list: [(String, T)], cur: T, _ f: @escaping (T) -> Void) {
            chips(list.map { item -> (String, Bool, Theme?, () -> Void) in
                let v = item.1
                return (item.0, v == cur, nil, { f(v) })
            })
        }

        header("Как зовут")
        let nf = NSTextField(frame: NSRect(x: 6, y: y, width: 196, height: 28))
        nf.stringValue = settings.name; nf.placeholderString = "Имя собачки"
        nf.font = Px.font(12); nf.textColor = t.text; nf.isBordered = false; nf.isBezeled = false; nf.drawsBackground = false; nf.focusRingType = .none
        nf.frame = NSRect(x: 16, y: y + 5, width: 176, height: 20)
        let nfBox = PixelBoxView(frame: NSRect(x: 6, y: y, width: 196, height: 30)); nfBox.u = 2; nfBox.fillOverride = t.fill
        doc.addSubview(nfBox)
        nf.delegate = self; doc.addSubview(nf); nameField = nf
        let save = Chip("Сохранить") { [weak self] in self?.saveName() }
        save.frame.origin = NSPoint(x: 210, y: y); doc.addSubview(save)
        y += 36

        header("Тема")
        chips(Theme.order.map { k in (Theme.all[k]!.title, settings.theme == k, Theme.all[k]!, { dog.doTheme(self.mi(k)) }) })

        header("Собачка")
        chips([(dog.sleeping ? "Разбудить" : "Уложить спать", false, nil, { dog.sleeping ? dog.doWake() : dog.doSleep() }),
               ("В угол экрана", false, nil, { dog.doReset() }),
               ("ball|Дать игрушку", false, nil, { dog.startPlay() })])

        header("Размер")
        opts([("Маленькая", 80.0), ("Средняя", 110.0), ("Большая", 150.0), ("Огромная", 200.0)], cur: settings.size) { dog.doSize(self.mi($0)) }
        header("Прозрачность")
        opts([("100%", 1.0), ("75%", 0.75), ("50%", 0.5)], cur: settings.alpha) { dog.doAlpha(self.mi($0)) }

        header("Прогулки")
        toggleRow("Гулять по экрану", settings.walk) { dog.doWalk() }
        opts([("Часто", 0), ("Иногда", 1), ("Редко", 2)], cur: settings.walkFreq) { dog.doWalkFreq(self.mi($0)) }
        header("Кусать курсор")
        opts([("Не кусать", 0), ("Очень редко", 1), ("Редко", 2)], cur: settings.bite) { dog.doBite(self.mi($0)) }
        header("Засыпать, если не трогаю")
        opts([("Никогда", 0), ("15 мин", 15), ("30 мин", 30), ("Час", 60)], cur: settings.autosleep) { dog.doAuto(self.mi($0)) }
        header("Модель в чате")
        opts(localModels.map { ($0, $0) }, cur: resolveModel(settings.chatModel)) { k in settings.chatModel = k; settings.save(); dog.chat.refreshModelBar() }
        header("Ответы на скриншоты (нужна модель с vision)")
        opts(localModels.map { ($0, $0) }, cur: resolveModel(settings.model)) { k in settings.model = k; settings.save() }
        header("Сервер: \(settings.endpoint)")
        chips([("Ollama", settings.endpoint.contains("11434"), nil, { settings.endpoint = "http://localhost:11434"; settings.save(); refreshLocalModels { dog.chat.refreshModelBar() } }),
               ("LM Studio", settings.endpoint.contains("1234"), nil, { settings.endpoint = "http://localhost:1234"; settings.save(); refreshLocalModels { dog.chat.refreshModelBar() } }),
               ("Обновить модели", false, nil, { refreshLocalModels { dog.chat.refreshModelBar() } })])

        header("Поведение")
        toggleRow("Режим игры: жрёт курсор раз в 2 минуты", settings.game) { dog.doGame() }
        toggleRow("Иногда сидеть, лежать и зевать", settings.acts) { dog.doActs() }
        toggleRow("Иногда махать лапкой", settings.waves) { dog.doWaves() }
        toggleRow("Иногда играть с игрушкой", settings.toy) { dog.doToy() }

        header("Иногда заглядывать на экран и спрашивать, нужна ли помощь")
        opts([("Выкл", 0), ("10 мин", 10), ("20 мин", 20), ("30 мин", 30), ("Час", 60)], cur: settings.helpEvery) { dog.doHelpEvery(self.mi($0)) }
        chips([("eye|Посмотреть сейчас", false, nil, { dog.checkHelp(force: true) })])

        header("Что показывать")
        toggleRow("Бирка с именем", settings.showTag) { dog.doShow(self.mi("tag")) }
        toggleRow("Ошейник", settings.showCollar) { dog.doShow(self.mi("collar")) }
        toggleRow("Реплики-реакции (Ням!, Ммм)", settings.showReactions) { dog.doShow(self.mi("react")) }
        toggleRow("Следит глазами за курсором и экраном", settings.followEyes) { dog.doShow(self.mi("eyes")) }
        toggleRow("Жмурится, когда гладишь", settings.petReact) { dog.doShow(self.mi("pet")) }

        y += 8
        let quit = Chip("Закрыть собачку") { dog.doQuit() }
        quit.frame.origin = NSPoint(x: 6, y: y); doc.addSubview(quit)
        y += 40
        doc.frame.size.height = y

        let sv = NSScrollView(frame: NSRect(x: 12, y: 12, width: docW, height: H - 62))
        sv.hasVerticalScroller = true; sv.drawsBackground = false; sv.borderType = .noBorder; sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        sv.documentView = doc
        bg.addSubview(sv)
        p.contentView = PixelWindowView(inner: bg)
        panel = p; scroll = sv
    }
}

final class NameTagView: NSView {
    let name: String
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    init(text: String) {
        name = text
        let t = curTheme()
        let iw = PxIcon.size(t.i1, scale: 2).width
        super.init(frame: NSRect(x: 0, y: 0, width: Px.textWidth(text, 11) + iw + 7 + 28, height: 28))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let t = curTheme()
        Px.box(bounds, fill: t.fill, ink: t.text, u: 2, bevel: true)
        let ih = PxIcon.size(t.i1, scale: 2).height
        let iw = PxIcon.draw(t.i1, at: NSPoint(x: 13, y: (bounds.height - ih) / 2), color: t.accent, scale: 2)
        Px.text(name, at: NSPoint(x: 13 + iw + 7, y: (bounds.height - Px.textHeight(11)) / 2), size: 11, color: t.text)
    }
}


final class DogView: NSView {
    let iv = NSImageView()
    var busy = false, asking = false, sleeping = false
    var downPt = NSPoint.zero, winOrigin = NSPoint.zero, moved = false, longFired = false
    var t: Timer?, pressTimer: Timer?, clickTimer: Timer?, bubbleTimer: Timer?
    var bubble: NSPanel?
    let chat = ChatController()
    var tripActive = false, dragging = false
    var moveTimer: Timer?, tripTimer: Timer?
    var homeOrigin = NSPoint.zero
    var nextWalkAt = Date().addingTimeInterval(60)
    var nextBiteAt = Date().addingTimeInterval(DogView.biteDelay())
    var lastInteraction = Date()
    var nextGameAt = Date().addingTimeInterval(120)
    var carryTimer: Timer?
    var curAnim = ""
    var nextActAt = Date().addingTimeInterval(60)
    // gaze: the dog's pupils (one sprite pixel steps) follow whatever it is paying attention to
    var face: GazeFace? = nil
    var qx = 0, qy = 0, wantX = 0, wantY = 0
    var wantSince = Date()
    var blinkUntil = Date.distantPast
    var nextBlinkAt = Date().addingTimeInterval(3)
    var glanceTarget: NSPoint? = nil
    var glanceUntil = Date.distantPast
    var nextGlanceAt = Date().addingTimeInterval(5)
    var lastMouse = NSEvent.mouseLocation
    var lastMouseAt = Date()
    var lastMotion = Date.distantPast
    var lastRendered = ""
    var nameTag: NSPanel?
    let prefs = SettingsController()
    var tagTick = 0
    var petting = false, petDist: CGFloat = 0, lastPetMove = Date.distantPast

    func renderFace(force: Bool = false) {
        guard let f = face else { return }
        let blinking = Date() < blinkUntil
        let key = "\(qx),\(qy),\(blinking),\(petting)"
        if !force && key == lastRendered { return }
        lastRendered = key
        iv.image = f.render(dx: qx, dy: qy, blink: blinking, happy: petting)
    }
    func glance(at p: NSPoint, for dur: TimeInterval) {
        glanceTarget = p; glanceUntil = Date().addingTimeInterval(dur)
        nextGlanceAt = max(nextGlanceAt, Date().addingTimeInterval(dur + 3))
    }
    func glanceAtApp(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        for wi in list {
            guard (wi[kCGWindowOwnerPID as String] as? Int32) == pid, (wi[kCGWindowLayer as String] as? Int) == 0,
                  let b = wi[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"], w > 100, h > 100 else { continue }
            glance(at: NSPoint(x: x + w / 2, y: mainH - (y + h / 2)), for: 2.2)
            return
        }
    }
    var quickPanel: NSPanel?
    var quickMon: Any?
    func toggleQuick() { quickPanel != nil ? closeQuick() : openQuick() }
    func closeQuick() {
        quickPanel?.orderOut(nil); quickPanel = nil
        if let m = quickMon { NSEvent.removeMonitor(m); quickMon = nil }
    }
    func openQuick() {
        guard let w = window else { return }
        closeQuick()
        let t = curTheme()
        let items: [(String, () -> Void)] = [
            (sleeping ? "sun|Разбудить" : "moon|Спать", { [weak self] in guard let s = self else { return }; if s.sleeping { s.wake() } else { s.sleep(menu: false) } }),
            ("ball|Дать игрушку", { [weak self] in guard let s = self else { return }; if s.sleeping { s.wake() }; s.startPlay() }),
            ("pin|В угол экрана", { [weak self] in self?.doReset() }),
        ]
        let chips = items.map { it in Chip(it.0) { [weak self] in self?.closeQuick(); it.1() } }
        let cw = chips.map { $0.frame.width }.max() ?? 120
        let W = cw + 24, H = CGFloat(chips.count) * 34 + 18
        let bg = PixelBoxView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        for (i, c) in chips.enumerated() {
            c.frame = NSRect(x: 12, y: H - 12 - 28 - CGFloat(i) * 34, width: cw, height: 28)
            bg.addSubview(c)
        }
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(scr.minX + 8, w.frame.midX - W / 2), scr.maxX - W - 8)
        let y = min(w.frame.maxY + 4, scr.maxY - H - 4)
        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: W, height: H), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.hidesOnDeactivate = false
        p.contentView = bg
        p.orderFrontRegardless()
        quickPanel = p
        quickMon = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.closeQuick() }
    }
    func refreshNameTag() {
        closeQuick()
        nameTag?.orderOut(nil); nameTag = nil
        guard settings.showTag, !settings.name.isEmpty else { return }
        let v = NameTagView(text: settings.name)
        let p = NSPanel(contentRect: v.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        v.onClick = { [weak self] in self?.toggleQuick() }
        p.contentView = v
        p.alphaValue = CGFloat(settings.alpha)
        nameTag = p
        positionNameTag(); p.orderFrontRegardless()
    }
    func positionNameTag() {
        guard let p = nameTag, let w = window else { return }
        let vis = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(vis.minX + 4, w.frame.midX - p.frame.width / 2), vis.maxX - p.frame.width - 4)
        let y = max(vis.minY, w.frame.minY - p.frame.height + 6)
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func gazeStep() {
        guard let w = window else { return }
        positionNameTag()
        tagTick += 1
        if tagTick % 60 == 0 { nameTag?.orderFrontRegardless() }
        let now = Date()
        let m = NSEvent.mouseLocation
        let dtm = now.timeIntervalSince(lastMouseAt)
        let inside = w.frame.insetBy(dx: w.frame.width * 0.12, dy: w.frame.height * 0.12).contains(m)
        let pressed = NSEvent.pressedMouseButtons != 0
        if dtm >= 0.1 {
            let moved = hypot(m.x - lastMouse.x, m.y - lastMouse.y)
            let speed = moved / CGFloat(dtm)
            lastMouse = m; lastMouseAt = now
            if speed > 40 {
                lastMotion = now
                if inside && !pressed && face != nil { petDist += moved; lastPetMove = now }
            }
        }
        // stroking: just move the cursor back and forth over the dog
        if !settings.petReact { petDist = 0 }
        if !petting {
            if !inside || now.timeIntervalSince(lastPetMove) > 1.2 { petDist = 0 }
            if settings.petReact && petDist > 110 && face != nil && !busy && !tripActive && !asking && !sleeping && !chat.isOpen && !dragging {
                petting = true; lastRendered = ""
                if bubble == nil && Int.random(in: 0..<3) == 0 { say(["Ммм…", "Ещё!", "Хорошо-о…", "Приятно"].randomElement()!, for: 2) }
            }
        } else if !inside || pressed || face == nil || busy || asking || sleeping || now.timeIntervalSince(lastPetMove) > 1.2 {
            petting = false; petDist = 0; lastRendered = ""
        }
        guard face != nil else { return }
        let c = NSPoint(x: w.frame.midX, y: w.frame.midY)
        var target: NSPoint? = nil
        if now.timeIntervalSince(lastMotion) < 3 { target = m }
        else if let g = glanceTarget, now < glanceUntil { target = g }
        else if now >= nextGlanceAt {
            nextGlanceAt = now.addingTimeInterval(.random(in: 4...14))
            if Bool.random(), let scr = w.screen?.visibleFrame {
                glance(at: NSPoint(x: .random(in: scr.minX...scr.maxX), y: .random(in: scr.minY...scr.maxY)), for: .random(in: 0.8...2.5))
            } else { glance(at: m, for: .random(in: 0.8...2)) }
        }
        var nx = 0, ny = 0
        if let t = target, canGaze(), !petting, settings.followEyes {
            let vx = t.x - c.x, vy = t.y - c.y, n = hypot(vx, vy)
            if n > 70 {
                nx = abs(vx) > 0.38 * n ? (vx > 0 ? 1 : -1) : 0
                ny = abs(vy) > 0.38 * n ? (vy > 0 ? 1 : -1) : 0   // screen y grows upward
            }
        }
        if nx != wantX || ny != wantY { wantX = nx; wantY = ny; wantSince = now }
        if (qx != wantX || qy != wantY) && now.timeIntervalSince(wantSince) > 0.1 {
            // a big jump of the eyes is often accompanied by a blink
            if abs(wantX - qx) + abs(wantY - qy) >= 2 && Int.random(in: 0..<3) == 0 { blinkUntil = now.addingTimeInterval(0.14) }
            qx = wantX; qy = wantY
        }
        if now >= nextBlinkAt {
            nextBlinkAt = now.addingTimeInterval(.random(in: 2.5...6.5))
            blinkUntil = now.addingTimeInterval(0.14)
        }
        renderFace()
    }
    func canGaze() -> Bool { !sleeping && !asking && !chat.isOpen }
    func startGaze() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.gazeStep() }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let s = self else { return }
            s.glance(at: NSEvent.mouseLocation, for: 1.6)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.glanceAtApp(app.processIdentifier) }
        }
    }
    static func walkDelay() -> TimeInterval {
        switch settings.walkFreq { case 0: return .random(in: 40...90); case 2: return .random(in: 480...900); default: return .random(in: 120...300) }
    }
    static func biteDelay() -> TimeInterval { settings.bite == 1 ? .random(in: 2700...5400) : .random(in: 900...1800) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        iv.frame = bounds; iv.autoresizingMask = [.width, .height]
        iv.imageScaling = .scaleProportionallyUpOrDown; iv.animates = true
        iv.wantsLayer = true; iv.layer?.magnificationFilter = .nearest
        iv.unregisterDraggedTypes()
        addSubview(iv)
        registerForDraggedTypes([.fileURL])
        chat.dog = self
        prefs.dog = self
        if settings.sleeping { sleep(menu: false) } else { show("LookingAround") }
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let s = self, settings.waves, !s.busy, !s.sleeping, Bool.random() else { return }
            s.play("Waving")
        }
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.tick() }
        startGaze()
        DispatchQueue.main.async { self.refreshNameTag() }
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ n: String) {
        curAnim = n
        if let f = GazeFace.get(n) { face = f; renderFace(force: true) }
        else { face = nil; iv.image = gif(n) }
    }
    func play(_ n: String) {
        busy = true; show(n); t?.invalidate()
        let d = min(max((durs[n] ?? 1.5) * 2, 1.2), 5.0)
        t = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { [weak self] _ in
            self?.busy = false; self?.show("LookingAround")
        }
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func toggleChat() {
        lastInteraction = Date(); cancelTrip()
        if sleeping { wake() }
        if let w = window { chat.toggle(near: w) }
    }


    // MARK: toy
    var toyPanel: NSPanel?
    var toyTimer: Timer?
    var nextToyAt = Date().addingTimeInterval(240)
    var toyOrigin = NSPoint.zero
    var playRounds = 0
    var nextHelpAt = Date().addingTimeInterval(Double(max(settings.helpEvery, 1)) * 60)
    var helpBusy = false, askedScreenAccess = false
    static func toyDelay() -> TimeInterval { .random(in: 480...1200) }

    static let toyArt: [(art: [String], pal: [Character: (CGFloat, CGFloat, CGFloat)])] = [
        (["...nnnn...", "..nrrrrn..", ".nrhhrrrn.", "nrhhrrrrrn", "nrhrrrrrrn", "nrrrrrrrrn", "nrrrrrrbrn", ".nrrrrbbn.", "..nbbbbn..", "...nnnn..."],
         ["n": (0.37, 0.12, 0.16), "r": (0.87, 0.28, 0.33), "h": (1, 0.69, 0.69), "b": (0.67, 0.17, 0.24)]),
        (["...nnnn...", "..nrrrrn..", ".nrhhrrrn.", "nrhhrrrrrn", "nrhrrrrrrn", "nrrrrrrrrn", "nrrrrrrbrn", ".nrrrrbbn.", "..nbbbbn..", "...nnnn..."],
         ["n": (0.12, 0.20, 0.37), "r": (0.27, 0.51, 0.88), "h": (0.67, 0.80, 1), "b": (0.17, 0.35, 0.67)]),
        ([".nn......nn.", "nwwnnnnnnwwn", "nwwwwwwwwwwn", "nwsssssssswn", "nwwnnnnnnwwn", ".nn......nn."],
         ["n": (0.59, 0.47, 0.35), "w": (0.98, 0.96, 0.89), "s": (0.88, 0.82, 0.70)]),
    ]
    func makeToy() -> NSPanel {
        let k = DogView.toyArt.randomElement()!
        let rows = k.art.count, cols = k.art[0].count
        let img = NSImage(size: NSSize(width: cols, height: rows))
        img.lockFocus()
        for (r, line) in k.art.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let p = k.pal[ch] else { continue }
                NSColor(calibratedRed: p.0, green: p.1, blue: p.2, alpha: 1).setFill()
                NSRect(x: c, y: rows - 1 - r, width: 1, height: 1).fill()
            }
        }
        img.unlockFocus()
        let sc = max(3, CGFloat(Int(settings.size / 22)))
        let sz = NSSize(width: CGFloat(cols) * sc, height: CGFloat(rows) * sc)
        let iv = NSImageView(frame: NSRect(origin: .zero, size: sz))
        iv.image = img; iv.imageScaling = .scaleAxesIndependently; iv.wantsLayer = true; iv.layer?.magnificationFilter = .nearest
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: sz), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver; p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.hidesOnDeactivate = false
        p.contentView = iv
        p.alphaValue = CGFloat(settings.alpha)
        return p
    }
    func flyToy(to dest: NSPoint, dur: Double, arc: CGFloat, done: @escaping () -> Void) {
        toyTimer?.invalidate()
        guard let tp0 = toyPanel else { done(); return }
        let start = tp0.frame.origin, t0 = Date()
        toyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] tm in
            guard let s = self, let tp = s.toyPanel else { tm.invalidate(); return }
            let k = min(1, CGFloat(Date().timeIntervalSince(t0) / dur))
            tp.setFrameOrigin(NSPoint(x: start.x + (dest.x - start.x) * k, y: start.y + (dest.y - start.y) * k + arc * sin(.pi * k)))
            if k >= 1 { tm.invalidate(); done() }
        }
    }
    func dogSpot(forToy o: NSPoint) -> NSPoint {
        guard let w = window, let tp = toyPanel else { return o }
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = o.x + tp.frame.width / 2 - w.frame.width / 2
        return NSPoint(x: min(max(scr.minX, x), scr.maxX - w.frame.width), y: min(max(scr.minY, o.y - 6), scr.maxY - w.frame.height))
    }
    func startPlay() {
        guard let w = window, let scr = w.screen?.visibleFrame, toyPanel == nil, !sleeping, !asking else { return }
        cancelTrip()
        tripActive = true; busy = true; hideBubble(); t?.invalidate(); homeOrigin = w.frame.origin
        let tp = makeToy(); toyPanel = tp
        let tw = tp.frame.width, th = tp.frame.height
        var spot = NSPoint.zero
        for _ in 0..<12 {
            spot = NSPoint(x: .random(in: scr.minX + 20...max(scr.minX + 20, scr.maxX - tw - 20)), y: .random(in: scr.minY + 10...max(scr.minY + 10, scr.maxY * 0.6)))
            if hypot(spot.x - w.frame.midX, spot.y - w.frame.midY) > 220 { break }
        }
        toyOrigin = spot
        tp.setFrameOrigin(NSPoint(x: spot.x, y: min(spot.y + 240, scr.maxY - th)))
        tp.orderFrontRegardless()
        playRounds = Int.random(in: 4...7)
        show("Excited")
        flyToy(to: spot, dur: 0.6, arc: 0) { [weak self] in
            self?.flyToy(to: spot, dur: 0.35, arc: 36) {
                guard let s = self else { return }
                s.moveTo(s.dogSpot(forToy: spot), speed: 240, mode: "Run") { s.playRound() }
            }
        }
    }
    func playRound() {
        guard toyPanel != nil, let w = window, let tp = toyPanel else { return endPlay() }
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        if playRounds <= 0 { return finishPlay() }
        playRounds -= 1
        show(Bool.random() ? "JumpingHappy" : "Jumping")
        tripTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let s = self, s.toyPanel != nil else { return }
            let ang = Double.random(in: 0..<(2 * .pi)), d = CGFloat.random(in: 120...280)
            var dest = NSPoint(x: s.toyOrigin.x + CGFloat(cos(ang)) * d, y: s.toyOrigin.y + CGFloat(sin(ang)) * d * 0.6)
            dest.x = min(max(scr.minX + 4, dest.x), scr.maxX - tp.frame.width - 4)
            dest.y = min(max(scr.minY, dest.y), scr.maxY - tp.frame.height - 4)
            s.toyOrigin = dest
            s.flyToy(to: dest, dur: .random(in: 0.5...0.8), arc: .random(in: 60...140)) {}
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard s.toyPanel != nil else { return }
                s.moveTo(s.dogSpot(forToy: dest), speed: 270, mode: "Run") { s.playRound() }
            }
        }
    }
    func finishPlay() {
        show("DancingHappy")
        tripTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            guard let s = self else { return }
            s.toyTimer?.invalidate(); s.toyPanel?.orderOut(nil); s.toyPanel = nil
            s.goHome()
        }
    }
    func endPlay() { toyTimer?.invalidate(); toyPanel?.orderOut(nil); toyPanel = nil; goHome() }

    // MARK: "need help?" check-in
    func checkHelp(force: Bool) {
        let now = Date()
        if !force {
            guard !sleeping, !asking, !chat.isOpen, !prefs.isOpen, !helpBusy, bubble == nil else { nextHelpAt = now.addingTimeInterval(300); return }
            let anyInput = CGEventType(rawValue: ~0)!
            if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > 300 { nextHelpAt = now.addingTimeInterval(300); return }
        } else if helpBusy || asking { return }
        guard CGPreflightScreenCaptureAccess() else {
            dlog("help check: no screen recording access")
            if !askedScreenAccess {
                askedScreenAccess = true; CGRequestScreenCaptureAccess()
                say("Чтобы заглядывать на экран, мне нужен доступ к записи экрана 🙏 Включи в системных настройках.", for: 8)
            }
            return
        }
        helpBusy = true
        let shots = home + "/shots"
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let file = "auto.png", path = shots + "/" + file
        try? FileManager.default.removeItem(atPath: path)
        let model = settings.model
        let prompt = persona() + " На приложенном изображении — скриншот экрана пользователя. Коротко и дружелюбно, 1-2 предложения по-русски, скажи, что он, похоже, делает, и спроси, не нужна ли помощь (если видно ошибку или затруднение — предложи конкретную помощь). Если на экране что-то приватное (пароли, личная переписка, банк), не пересказывай это, просто спроси, нужна ли помощь. Если экран заблокирован, пустой, идёт видео или игра и помощь явно не нужна — ответь ровно одним словом NONE."
        DispatchQueue.global().async {
            let cap = Process()
            cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            cap.arguments = ["-x", "-m", path]
            try? cap.run(); cap.waitUntilExit()
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            var ans: String? = nil
            if (size ?? 0) > 0 { ans = runLocal(prompt: prompt, system: nil, files: [path], model: model) }
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async {
                self.helpBusy = false
                dlog("help check result: \(ans.map { String($0.prefix(80)) } ?? "nil")")
                guard let a = ans, !a.uppercased().hasPrefix("NONE") else { return }
                guard !self.sleeping, !self.asking, !self.chat.isOpen else { return }
                self.chat.history.append(("dog", a)); self.chat.append("🐾", a, pinkName: true)
                if !self.busy { self.play("Waving") }
                self.say(a)
                self.bubbleTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in self?.hideBubble() }
            }
        }
    }

    // MARK: walking and biting
    func tick() {
        if settings.autosleep > 0, !sleeping, Date().timeIntervalSince(lastInteraction) > Double(settings.autosleep) * 60 { sleep(menu: false); return }
        if settings.helpEvery > 0, Date() >= nextHelpAt {
            nextHelpAt = Date().addingTimeInterval(Double(settings.helpEvery) * 60 * .random(in: 0.8...1.25))
            checkHelp(force: false)
        }
        if sleeping || busy || asking || chat.isOpen || tripActive || dragging || petting || prefs.isOpen || bubble != nil { return }
        let now = Date()
        if settings.toy, now >= nextToyAt {
            nextToyAt = now.addingTimeInterval(DogView.toyDelay())
            if NSEvent.pressedMouseButtons == 0 { startPlay(); return }
        }
        if settings.game, now >= nextGameAt {
            nextGameAt = now.addingTimeInterval(120)
            if NSEvent.pressedMouseButtons == 0 { startEat(); return }
        }
        if settings.bite > 0, now >= nextBiteAt {
            nextBiteAt = now.addingTimeInterval(DogView.biteDelay())
            if NSEvent.pressedMouseButtons == 0 { startBite(); return }
        }
        if settings.acts, now >= nextActAt {
            nextActAt = now.addingTimeInterval(.random(in: 50...130))
            if !settings.walk || Bool.random() { startAct(); return }
        }
        if settings.walk, now >= nextWalkAt {
            nextWalkAt = now.addingTimeInterval(DogView.walkDelay())
            startTrip()
        }
    }
    func dirAnim(_ dx: CGFloat, _ dy: CGFloat, _ mode: String) -> String {
        if abs(dx) >= abs(dy) * 0.7 {
            let r = dx >= 0
            switch mode { case "Run": return r ? "RunR" : "RunL"; case "Sniff": return r ? "SniffR" : "SniffL"; default: return r ? "WalkR" : "WalkL" }
        }
        if dy > 0 { return "WalkUp" }
        return mode == "Run" ? "Running" : "Walking"
    }
    func moveTo(_ target: NSPoint, speed: CGFloat, mode: String = "Walk", done: @escaping () -> Void) {
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let s = self, let w = s.window else { t.invalidate(); return }
            let o = w.frame.origin
            let dx = target.x - o.x, dy = target.y - o.y, dist = hypot(dx, dy), step = speed / 30
            if dist <= step { w.setFrameOrigin(target); t.invalidate(); done(); return }
            let a = s.dirAnim(dx, dy, mode)
            if a != s.curAnim { s.show(a) }
            w.setFrameOrigin(NSPoint(x: o.x + dx / dist * step, y: o.y + dy / dist * step))
        }
    }
    func restAct(_ done: @escaping () -> Void) {
        let acts: [(String, Double)] = [("Sit", .random(in: 8...16)), ("Lie", .random(in: 10...22)), ("Yawn", 2.4), ("Bark", 1.4), ("LieYawn", 2.2), ("LookingAround", 5), ("Meditating", 5)]
        let (n, hold) = acts.randomElement()!
        show(n)
        tripTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            guard let s = self else { return }
            if n == "Yawn" || n == "Bark" || n == "LieYawn" {
                let nxt = n == "LieYawn" ? "Lie" : "Sit"
                s.show(nxt)
                s.tripTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 4...9), repeats: false) { _ in done() }
            } else { done() }
        }
    }
    func startAct() {
        tripActive = true; busy = true; hideBubble(); t?.invalidate()
        restAct { [weak self] in self?.endTrip() }
    }
    func pickMode() -> (String, CGFloat) {
        let r = Double.random(in: 0...1)
        if r < 0.3 { return ("Run", 170) }
        if r < 0.5 { return ("Sniff", 45) }
        return ("Walk", 75)
    }
    func startTrip() {
        guard let w = window, let scr = w.screen?.visibleFrame else { return }
        tripActive = true; busy = true; hideBubble(); t?.invalidate(); homeOrigin = w.frame.origin
        let tx = CGFloat.random(in: scr.minX...max(scr.minX, scr.maxX - w.frame.width))
        let ty = Bool.random() ? homeOrigin.y : CGFloat.random(in: scr.minY...max(scr.minY, scr.maxY - w.frame.height))
        let (mode, speed) = pickMode()
        moveTo(NSPoint(x: tx, y: ty), speed: speed, mode: mode) { [weak self] in
            guard let s = self else { return }
            s.restAct { s.goHome() }
        }
    }
    func goHome() {
        let (mode, speed) = pickMode()
        moveTo(homeOrigin, speed: speed, mode: mode) { [weak self] in self?.endTrip() }
    }
    func endTrip() { tripActive = false; busy = false; show("LookingAround") }
    func cancelTrip() {
        moveTimer?.invalidate(); tripTimer?.invalidate(); carryTimer?.invalidate()
        toyTimer?.invalidate(); toyPanel?.orderOut(nil); toyPanel = nil
        if tripActive { tripActive = false; busy = false; show("LookingAround") }
    }
    func startEat() {
        guard let w = window else { return }
        tripActive = true; busy = true; hideBubble(); t?.invalidate(); homeOrigin = w.frame.origin
        let m = NSEvent.mouseLocation
        moveTo(NSPoint(x: m.x - w.frame.width / 2 + 28, y: m.y - w.frame.height + 22), speed: 320, mode: "Run") { [weak self] in self?.eat() }
    }
    func eat() {
        guard let w = window else { return }
        show("Excited"); say("Ням! 😋", for: 3.5)
        let off = CGPoint(x: w.frame.width / 2 - 28, y: w.frame.height - 22)
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let deadline = Date().addingTimeInterval(4)
        carryTimer?.invalidate()
        carryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] tm in
            guard let s = self, let w = s.window, Date() < deadline, NSEvent.pressedMouseButtons == 0 else { tm.invalidate(); return }
            let o = w.frame.origin
            CGWarpMouseCursorPosition(CGPoint(x: o.x + off.x, y: mainH - (o.y + off.y)))
        }
        tripTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            self?.moveTo(self?.homeOrigin ?? .zero, speed: 150, mode: "Run") { self?.endTrip() }
        }
    }
    func startBite() {
        guard let w = window else { return }
        tripActive = true; busy = true; hideBubble(); t?.invalidate(); homeOrigin = w.frame.origin
        let m = NSEvent.mouseLocation
        moveTo(NSPoint(x: m.x - w.frame.width / 2 + 28, y: m.y - w.frame.height + 22), speed: 260, mode: "Run") { [weak self] in self?.bite() }
    }
    func bite() {
        show("Excited")
        say("Ам! 🦴", for: 2.5)
        let loc = CGEvent(source: nil)?.location ?? .zero
        var i = 0
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] tm in
            i += 1
            if i > 8 {
                CGWarpMouseCursorPosition(loc); tm.invalidate()
                self?.tripTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in self?.goHome() }
            } else {
                CGWarpMouseCursorPosition(CGPoint(x: loc.x + (i % 2 == 0 ? 9 : -9), y: loc.y + (i % 3 == 0 ? 4 : -4)))
            }
        }
    }

    // MARK: files
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        dlog("dog drag entered")
        lastInteraction = Date()
        if sleeping { sleeping = false; settings.sleeping = false; settings.save() }
        cancelTrip(); t?.invalidate(); busy = true; show("SniffR")
        return .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { if !asking { busy = false; show("LookingAround") } }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        dlog("dog drop: \(urls.map { $0.path })")
        if urls.isEmpty { return false }
        askFiles(urls); return true
    }
    func askFiles(_ urls: [URL]) {
        if asking { return }
        asking = true; busy = true; hideBubble(); t?.invalidate(); show("SniffR")
        let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
        let paths = urls.map { $0.path }.joined(separator: "\n")
        let prompt = "Пользователь перетащил на тебя файлы или папки:\n" + paths + "\n\n" + persona() + " Их содержимое приведено ниже (картинки приложены). Ответь по-русски 2-4 короткими предложениями: что это такое, о чём и что с этим можно сделать. Если папка — опиши, что в ней лежит. Можно мило, но по делу."
        let model = settings.model
        let cwd = dirOf(urls[0]), dirs = Array(Set(urls.map { dirOf($0) }))
        DispatchQueue.global().async {
            let ans = runLocal(prompt: prompt, system: nil, files: urls.map { $0.path }, model: model)
            dlog("askFiles result: \(ans.map { String($0.prefix(120)) } ?? "nil")")
            DispatchQueue.main.async {
                self.asking = false
                let text = ans ?? "Не получилось прочитать эти файлы."
                self.show("Excited"); self.say(text)
                self.chat.history.append(("user", "[файлы: " + names + "]")); self.chat.history.append(("dog", text))
                self.chat.attached = urls; self.chat.refreshAttachBar()
                self.chat.append("📎", names + " — можно попросить изменить в чате (двойной ⌘)", pinkName: false)
                self.chat.append("🐾", text, pinkName: true)
                self.t?.invalidate()
                self.t = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.busy = false; self?.show("LookingAround") }
            }
        }
    }

    // MARK: sleeping
    func sleep(menu: Bool) {
        sleeping = true; settings.sleeping = true; settings.save()
        t?.invalidate(); clickTimer?.invalidate(); hideBubble(); busy = true
        show("Sleep")
        if menu { DispatchQueue.main.async { self.showMenu() } }
    }
    func wake() {
        sleeping = false; settings.sleeping = false; settings.save()
        play("Waving")
    }

    // MARK: mouse
    override func mouseDown(with e: NSEvent) {
        closeQuick(); cancelTrip(); lastInteraction = Date()
        downPt = NSEvent.mouseLocation; winOrigin = window!.frame.origin; moved = false; longFired = false; dragging = true
        pressTimer?.invalidate()
        pressTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let s = self, !s.moved else { return }
            s.longFired = true; s.clickTimer?.invalidate()
            s.sleep(menu: true)
        }
    }
    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downPt.x, dy = p.y - downPt.y
        if !moved && abs(dx) + abs(dy) < 5 { return }
        moved = true; pressTimer?.invalidate(); dragging = true
        window?.setFrameOrigin(NSPoint(x: winOrigin.x + dx, y: winOrigin.y + dy))
    }
    override func mouseUp(with e: NSEvent) {
        pressTimer?.invalidate(); dragging = false
        if longFired { return }
        if moved {
            if let o = window?.frame.origin {
                try? JSONSerialization.data(withJSONObject: ["x": o.x, "y": o.y]).write(to: URL(fileURLWithPath: home + "/pos.json"))
            }
            return
        }
        if e.clickCount >= 2 {
            clickTimer?.invalidate()
            if sleeping { wake() } else { sleep(menu: false) }
            return
        }
        clickTimer?.invalidate()
        clickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
            guard let s = self else { return }
            if s.sleeping { s.wake() } else if !s.busy { s.play(reactions.randomElement()!) }
        }
    }
    override func rightMouseDown(with e: NSEvent) {
        dlog("right click")
        if sleeping { wake() }
        ask()
    }

    // MARK: menu
    func showMenu() { if let w = window { prefs.toggle(near: w) } }
    func showNativeMenu() {
        let m = NSMenu(); m.autoenablesItems = false
        func mk(_ title: String, _ sel: Selector?, on: Bool = false, obj: Any? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self
            i.state = on ? .on : .off; i.representedObject = obj; return i
        }
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sm = NSMenu(); sm.autoenablesItems = false
            items.forEach { sm.addItem($0) }
            it.submenu = sm; m.addItem(it)
        }
        let h = NSMenuItem(title: "🐾 Настройки: " + petName(), action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h)
        m.addItem(.separator())
        m.addItem(mk(settings.name.isEmpty ? "✏️ Дать имя…" : "✏️ Имя: \(settings.name) (сменить)", #selector(doName)))
        sub("Тема чата", Theme.order.map { k in mk(Theme.all[k]!.title, #selector(doTheme(_:)), on: settings.theme == k, obj: k) })
        m.addItem(.separator())
        m.addItem(mk(sleeping ? "Разбудить" : "Уложить спать", sleeping ? #selector(doWake) : #selector(doSleep)))
        m.addItem(.separator())
        sub("Размер", [("Маленькая", 80.0), ("Средняя", 110.0), ("Большая", 150.0), ("Огромная", 200.0)].map { mk($0.0, #selector(doSize(_:)), on: settings.size == $0.1, obj: $0.1) })
        sub("Прозрачность", [("100%", 1.0), ("75%", 0.75), ("50%", 0.5)].map { mk($0.0, #selector(doAlpha(_:)), on: abs(settings.alpha - $0.1) < 0.01, obj: $0.1) })
        sub("Прогулки по экрану", [mk("Гулять по экрану", #selector(doWalk), on: settings.walk), .separator()] +
            [("Часто", 0), ("Иногда", 1), ("Редко", 2)].map { mk($0.0, #selector(doWalkFreq(_:)), on: settings.walkFreq == $0.1, obj: $0.1) })
        sub("Кусать курсор", [("Не кусать", 0), ("Очень редко", 1), ("Редко", 2)].map { mk($0.0, #selector(doBite(_:)), on: settings.bite == $0.1, obj: $0.1) })
        sub("Засыпать, если не трогаю", [("Никогда", 0), ("Через 15 минут", 15), ("Через 30 минут", 30), ("Через час", 60)].map { mk($0.0, #selector(doAuto(_:)), on: settings.autosleep == $0.1, obj: $0.1) })
        sub("Модель для скриншотов", localModels.map { mk($0, #selector(doModel(_:)), on: resolveModel(settings.model) == $0, obj: $0) })
        m.addItem(mk("🎮 Режим игры: жрёт курсор раз в 2 минуты", #selector(doGame), on: settings.game))
        m.addItem(mk("Иногда сидеть, лежать и зевать", #selector(doActs), on: settings.acts))
        m.addItem(mk("Иногда махать лапкой", #selector(doWaves), on: settings.waves))
        sub("Что показывать", [
            mk("Бирка с именем", #selector(doShow(_:)), on: settings.showTag, obj: "tag"),
            mk("Ошейник", #selector(doShow(_:)), on: settings.showCollar, obj: "collar"),
            mk("Реплики-реакции (Ням!, Ммм ♡)", #selector(doShow(_:)), on: settings.showReactions, obj: "react"),
            mk("Следит глазами за курсором и экраном", #selector(doShow(_:)), on: settings.followEyes, obj: "eyes"),
            mk("Жмурится, когда гладишь", #selector(doShow(_:)), on: settings.petReact, obj: "pet"),
        ])
        m.addItem(.separator())
        m.addItem(mk("Вернуть в угол экрана", #selector(doReset)))
        m.addItem(mk("Закрыть собачку", #selector(doQuit)))
        m.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.maxY), in: self)
    }
    func setName(_ raw: String) {
        settings.name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)); settings.save()
        chat.rebuild(); refreshNameTag(); prefs.rebuild()
    }
    @objc func doTheme(_ s: NSMenuItem) { settings.theme = s.representedObject as? String ?? "boy"; settings.save(); chat.rebuild(); refreshNameTag(); prefs.rebuild() }
    @objc func doName() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Как зовут собачку?"; a.informativeText = "Имя сохранится навсегда. Пусто — убрать имя."
            let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.stringValue = settings.name
            a.accessoryView = f; a.addButton(withTitle: "Готово"); a.addButton(withTitle: "Отмена")
            a.window.initialFirstResponder = f
            a.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            if a.runModal() == .alertFirstButtonReturn { self.setName(f.stringValue) }
        }
    }
    @objc func doGame() { settings.game.toggle(); settings.save(); nextGameAt = Date().addingTimeInterval(120) }
    @objc func doActs() { settings.acts.toggle(); settings.save() }
    @objc func doSleep() { sleep(menu: false) }
    @objc func doWalk() { settings.walk.toggle(); settings.save() }
    @objc func doWalkFreq(_ s: NSMenuItem) { settings.walkFreq = s.representedObject as? Int ?? 1; settings.save(); nextWalkAt = Date().addingTimeInterval(DogView.walkDelay()) }
    @objc func doBite(_ s: NSMenuItem) { settings.bite = s.representedObject as? Int ?? 0; settings.save(); nextBiteAt = Date().addingTimeInterval(DogView.biteDelay()) }
    @objc func doAlpha(_ s: NSMenuItem) { settings.alpha = s.representedObject as? Double ?? 1; settings.save(); window?.alphaValue = CGFloat(settings.alpha); nameTag?.alphaValue = CGFloat(settings.alpha) }
    @objc func doAuto(_ s: NSMenuItem) { settings.autosleep = s.representedObject as? Int ?? 0; settings.save(); lastInteraction = Date() }
    @objc func doReset() {
        guard let w = window, let scr = w.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        cancelTrip()
        w.setFrameOrigin(NSPoint(x: scr.maxX - w.frame.width - 24, y: scr.minY + 24))
        try? FileManager.default.removeItem(atPath: home + "/pos.json")
    }
    @objc func doWake() { wake() }
    @objc func doSize(_ s: NSMenuItem) {
        guard let v = s.representedObject as? Double, let w = window else { return }
        settings.size = v; settings.save()
        let f = w.frame
        w.setFrame(NSRect(x: f.minX, y: f.minY, width: v, height: v), display: true)
    }
    @objc func doModel(_ s: NSMenuItem) { settings.model = s.representedObject as? String ?? ""; settings.save() }
    @objc func doWaves() { settings.waves.toggle(); settings.save() }
    @objc func doToy() { settings.toy.toggle(); settings.save(); nextToyAt = Date().addingTimeInterval(DogView.toyDelay()) }
    @objc func doHelpEvery(_ s: NSMenuItem) {
        settings.helpEvery = s.representedObject as? Int ?? 0; settings.save()
        nextHelpAt = Date().addingTimeInterval(Double(max(settings.helpEvery, 1)) * 60)
    }
    @objc func doShow(_ s: NSMenuItem) {
        switch s.representedObject as? String ?? "" {
        case "tag": settings.showTag.toggle(); settings.save(); refreshNameTag()
        case "collar":
            settings.showCollar.toggle(); settings.save()
            GazeFace.cache = [:]; lastRendered = ""
            show(curAnim)
        case "react": settings.showReactions.toggle(); settings.save(); if !settings.showReactions { hideBubble() }
        case "eyes": settings.followEyes.toggle(); settings.save()
        case "pet": settings.petReact.toggle(); settings.save()
        default: break
        }
    }
    @objc func doQuit() { NSApp.terminate(nil) }

    // MARK: bubble + ask
    func hideBubble() { bubbleTimer?.invalidate(); bubble?.orderOut(nil); bubble = nil }
    func say(_ text: String, for dur: Double? = nil) {
        if dur != nil && !settings.showReactions { return }   // short reactions only; real answers always show
        hideBubble()
        guard let w = window else { return }
        let v = BubbleView(text: text)
        let scr = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = w.frame.midX - v.frame.width + 34
        x = min(max(scr.minX + 8, x), scr.maxX - v.frame.width - 8)
        v.tailX = min(max(26, w.frame.midX - x - 6), v.frame.width - 34)
        var y = w.frame.maxY - 10
        if y + v.frame.height > scr.maxY { y = scr.maxY - v.frame.height - 4 }
        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: v.frame.width, height: v.frame.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.hidesOnDeactivate = false
        v.onClick = { [weak self] in self?.hideBubble() }
        p.contentView = v
        p.orderFrontRegardless()
        bubble = p
        if let d = dur { bubbleTimer = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { [weak self] _ in self?.hideBubble() } }
    }
    func ask() {
        if asking { return }
        lastInteraction = Date(); cancelTrip()
        asking = true; busy = true; hideBubble(); t?.invalidate(); show("Thinking")
        let shots = home + "/shots"
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let file = "shot.png"
        let path = shots + "/" + file
        try? FileManager.default.removeItem(atPath: path)
        let model = settings.model
        DispatchQueue.global().async {
            let cap = Process()
            cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            cap.arguments = ["-i", "-x", path]
            try? cap.run(); cap.waitUntilExit()
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            if (size ?? 0) <= 0 { DispatchQueue.main.async { self.finish(nil) }; return }
            DispatchQueue.main.async { self.show("Thinking") }
            let text = runLocal(prompt: "На приложенном изображении — скриншот части экрана пользователя. " + persona() + " Ответь по-русски 1-3 короткими милыми предложениями: скажи, что видишь, или помоги, если на скриншоте вопрос или проблема.", system: nil, files: [path], model: model)
            DispatchQueue.main.async { self.finish(text ?? "Гав! Не получилось посмотреть скриншот. Нужна локальная модель с поддержкой картинок (например qwen2.5vl, llava, gemma3) 🥺") }
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    func finish(_ text: String?) {
        asking = false
        guard let text = text else { busy = false; show("LookingAround"); return }
        show("Excited"); say(text)
        chat.history.append(("user", "[скриншот]")); chat.history.append(("dog", text))
        chat.append("🐾", text, pinkName: true)
        t?.invalidate()
        t = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.busy = false; self?.show("LookingAround") }
    }
}

final class App: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    func applicationDidFinishLaunching(_ n: Notification) {
        refreshLocalModels()
        let SZ = CGFloat(settings.size)
        var o = NSPoint(x: 0, y: 0)
        if let s = NSScreen.main { o = NSPoint(x: s.visibleFrame.maxX - SZ - 24, y: s.visibleFrame.minY + 24) }
        if let d = try? Data(contentsOf: URL(fileURLWithPath: home + "/pos.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Double], let x = j["x"], let y = j["y"] { o = NSPoint(x: x, y: y) }
        panel = NSPanel(contentRect: NSRect(origin: o, size: NSSize(width: SZ, height: SZ)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DogView(frame: NSRect(origin: .zero, size: NSSize(width: SZ, height: SZ)))
        panel.alphaValue = CGFloat(settings.alpha)
        panel.orderFrontRegardless()

        // Double-tap of the Command key (modifier state only, no keystrokes are read)
        dlog("started; AX trusted=\(AXIsProcessTrusted())")
        if let dir = ProcessInfo.processInfo.environment["DOG_SNAP"], let dv = panel.contentView as? DogView {
            // debug: render the UI windows to PNGs and quit (no screen-recording permission needed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                func snap(_ v: NSView?, _ n: String) {
                    guard let v = v, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { dlog("snap \(n): no view"); return }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    do { try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + n + ".png")) } catch { dlog("snap \(n): \(error)") }
                }
                dlog("snap: chat"); dv.chat.open(near: self.panel)
                dv.chat.append("Ты:", "привет, покажи **жирный** и *курсив*", pinkName: false)
                dv.chat.append("🐾", "Привет! Вот список:\n- пункт **один**\n- пункт `код`\n\nИ [ссылка](https://a.b)", pinkName: true)
                dlog("snap: list"); dv.chat.showList()
                dlog("snap: prefs"); dv.prefs.open(near: self.panel)
                dlog("snap: quick"); dv.openQuick()
                dlog("snap: say"); dv.say("Привет! Я тофи. Тебе нужна помощь с чем-нибудь?")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    snap(dv.chat.panel?.contentView, "chat"); dv.chat.hideList(); snap(dv.chat.panel?.contentView, "chat2")
                    snap(dv.prefs.panel?.contentView, "prefs"); snap(dv.quickPanel?.contentView, "quick")
                    snap(dv.bubble?.contentView, "bubble"); snap(dv.nameTag?.contentView, "tag")
                    exit(0)
                }
            }
        }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        var downAt: TimeInterval = 0, lastTap: TimeInterval = 0
        let handleFlags: (NSEvent) -> Void = { [weak self] e in
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let now = Date().timeIntervalSinceReferenceDate
            if f == [.command] { downAt = now }
            else if f.isEmpty && downAt > 0 {
                if now - downAt < 0.3 {
                    if now - lastTap < 0.45 { lastTap = 0; dlog("double cmd"); (self?.panel.contentView as? DogView)?.toggleChat() }
                    else { lastTap = now }
                } else { lastTap = 0 }
                downAt = 0
            } else { downAt = 0; lastTap = 0 }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handleFlags($0) }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { handleFlags($0); return $0 }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            if parentPid > 0 && kill(parentPid, 0) != 0 { NSApp.terminate(nil) }
            self?.panel.orderFrontRegardless()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = App()
app.delegate = del
app.run()
