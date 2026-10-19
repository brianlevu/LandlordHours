import SwiftUI

// §1b/§1c locks on real screens, §5 leftovers, and the Settings root that hosts them.

// MARK: - Export (Reports / Records / Settings → Export), .page lock

struct S2ExportPage: View {
    var locked = true
    var onUnlock: () -> Void = {}
    @State private var unlocked = false
    @State private var pdf = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LockedPreview(size: .page, line: "This is the record your accountant gets.", keeps: "Your record keeps growing; export unlocks with Pro.", fold: 236, unlocked: unlocked || !locked, onUnlock: onUnlock) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext").font(.system(size: 22)).foregroundStyle(LHB.action)
                                    .frame(width: 44, height: 44).background(Circle().fill(LHB.actionSurface))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Your 2026 record").font(.headline).foregroundStyle(LHB.textPrimary)
                                    Text("Jan 1 – Oct 19 · 212h confirmed").font(.subheadline).foregroundStyle(LHB.textSecondary)
                                }
                            }
                            HStack(spacing: 2) {
                                fmt("PDF", on: pdf) { pdf = true }
                                fmt("Spreadsheet", on: !pdf) { pdf = false }
                            }
                            .padding(3).background(Capsule().fill(LHB.tertiary))
                            HStack(spacing: 0) {
                                stat("212h", "Confirmed"); stat("41", "Entries"); stat("1", "Property")
                            }
                        }
                        .padding(16).s2Card()
                        VStack(alignment: .leading, spacing: 10) {
                            S2Header("Entries")
                            VStack(spacing: 0) {
                                ForEach(0..<9, id: \.self) { i in
                                    let e = S2Data.recent[i % 3]
                                    HStack(spacing: 12) {
                                        ToolTile(cat: e.cat, size: 36)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(e.title) at Pine Cabin").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                                            Text("\(e.date) · \(e.source)").font(.subheadline).foregroundStyle(LHB.textSecondary)
                                        }
                                        Spacer()
                                        Text(hm(e.hours)).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                                    }
                                    .padding(.horizontal, 16).frame(minHeight: 64)
                                    if i < 8 { InsetDivider(leading: 64) }
                                }
                            }
                            .s2Card()
                        }
                        Button("Export PDF") {}.buttonStyle(S2Primary())
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
            }
            .scrollDisabled(locked && !unlocked)
            .background(LHB.canvas.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "chevron.left").foregroundStyle(LHB.action) } }
        }
    }

    private func fmt(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(on ? LHB.onAction : LHB.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 36).background(Capsule().fill(on ? LHB.action : .clear))
        }.buttonStyle(.plain)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(LHB.textPrimary)
            Text(l).font(.footnote).foregroundStyle(LHB.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings root (Pro card on top, a .row lock for location)

struct S2Settings: View {
    var pro = false
    var onUnlock: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        DisplayTitle(text: "Settings")
                        Spacer()
                        GlassClose()
                    }
                    if !pro {
                        HStack(spacing: 14) {
                            Image("lh_icon_b").resizable().frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LandlordHours Pro").font(.headline).foregroundStyle(LHB.textPrimary)
                                Text("Pay once, $29.99").font(.subheadline).foregroundStyle(LHB.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("See Pro", action: onUnlock).buttonStyle(S2Tinted())
                        }
                        .padding(16).s2Card()
                    }
                    section("Location") {
                        row("Pine Cabin", "On", seal: S2Data.pine)
                        InsetDivider(leading: 60)
                        LockedPreview(size: .row, line: "Location for every rental.", keeps: "Pine Cabin keeps its location. Nothing is lost.", onUnlock: onUnlock) {
                            row("Oak Street Duplex", "Off", seal: S2Data.oak)
                        }
                    }
                    section("Your record") {
                        link("doc.richtext", "Export")
                        InsetDivider(leading: 52)
                        link("person.2", "Spouse hours", value: "On")
                        InsetDivider(leading: 52)
                        link("target", "Goal", value: "750h")
                    }
                    section("Help") {
                        link("bubble.left", "Get help")
                        InsetDivider(leading: 52)
                        link("book", "Learn")
                        InsetDivider(leading: 52)
                        link("arrow.counterclockwise", "Your other records")
                    }
                    section("Data") {
                        link("icloud", "iCloud", value: "On")
                        InsetDivider(leading: 52)
                        HStack { Text("Delete all data").foregroundStyle(LHB.destructive); Spacer() }
                            .padding(.horizontal, 16).frame(minHeight: 52)
                    }
                    Text("LandlordHours 2.0 (1)").font(.footnote).foregroundStyle(LHB.textSecondary).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            }
            .background(LHB.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            S2Header(t)
            VStack(spacing: 0) { c() }.s2Card()
        }
    }

    private func row(_ t: String, _ v: String, seal: S2Property) -> some View {
        HStack(spacing: 12) {
            PropertySeal(seal, size: 32)
            Text(t).foregroundStyle(LHB.textPrimary)
            Spacer()
            Text(v).foregroundStyle(LHB.textSecondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 60)
    }

    private func link(_ sym: String, _ t: String, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sym).font(.system(size: 17)).foregroundStyle(LHB.action).frame(width: 24)
            Text(t).foregroundStyle(LHB.textPrimary)
            Spacer()
            if let value { Text(value).foregroundStyle(LHB.textSecondary) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textTertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }
}

// MARK: - §1c Inbox, free user at the limit

enum LimitState: String { case row, sheet, picker, waiting }

struct S2InboxLimit: View {
    var state: LimitState = .row
    @State private var sheet = false

    private var s: S2Data.Suggestion {
        var x = S2Data.limitSuggestion; x.place = "Oak Street Duplex"; return x
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisplayTitle(text: "Inbox").padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 10) {
                    S2Header("This week")
                    VStack(spacing: 0) {
                        S2SuggestionRow(s: s, meta: state == .waiting ? "Waiting on Pro" : "New place", metaSymbol: state == .waiting ? "clock" : nil)
                        InsetDivider(leading: 124)
                        S2SuggestionRow(s: S2Data.pending[0])
                        InsetDivider(leading: 124)
                        S2SuggestionRow(s: S2Data.pending[2])
                    }
                    .s2Card()
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(LHB.canvas.ignoresSafeArea())
        .sheet(isPresented: $sheet) {
            LimitConfirmSheet(showPicker: state == .picker)
                .presentationDetents([.large])
                .presentationBackground(LHB.canvas)
        }
        .onAppear { if state == .sheet || state == .picker { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sheet = true } } }
    }
}

struct LimitConfirmSheet: View {
    var showPicker = false
    @State private var hours: Double = 1
    @State private var who = 0
    @State private var picker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(LHB.draftingInk)
                        .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LHB.actionSurface))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar · Sat, Oct 18").s2Section()
                        (Text("Showing").fontWeight(.semibold) + Text(" at ") + Text("Oak Street Duplex").fontWeight(.semibold))
                            .font(.title3).foregroundStyle(LHB.textPrimary)
                    }
                    Spacer(); GlassClose()
                }
                VStack(alignment: .leading, spacing: 4) {
                    (Text("Scheduled ") + Text("1h").bold()).font(.headline).foregroundStyle(LHB.textPrimary)
                    Text("Your calendar had this from 5:30 to 6:30. Change it if the work ran long or short.")
                        .font(.subheadline).foregroundStyle(LHB.textSecondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(LHB.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HoursStepper(hours: $hours, label: "How long were you working?")
                VStack(spacing: 0) {
                    HStack {
                        Text("Property"); Spacer()
                        Button { picker = true } label: {
                            HStack(spacing: 6) {
                                PropertySeal(monogram: "OS", size: 24, dashed: true)
                                Text("Oak Street Duplex").foregroundStyle(LHB.textPrimary)
                                Text("New").font(.footnote.weight(.semibold)).foregroundStyle(LHB.informational)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(LHB.informationalSurface))
                            }
                        }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    InsetDivider()
                    HStack { Text("Who"); Spacer(); WhoPicker(who: $who) }.padding(.horizontal, 16).frame(minHeight: 52)
                    InsetDivider()
                    HStack { Text("Category"); Spacer(); ToolTile(cat: .leasing, size: 28); Text("Leasing") }.padding(.horizontal, 16).frame(minHeight: 52)
                    InsetDivider()
                    HStack { Text("Date"); Spacer(); Text("Sat, Oct 18") }.padding(.horizontal, 16).frame(minHeight: 52)
                }
                .foregroundStyle(LHB.textPrimary)
                .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("Free covers one rental. This visit will wait in your inbox.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    Text("Pine Cabin keeps tracking. Nothing is lost.")
                        .font(.footnote).foregroundStyle(LHB.textSecondary)
                }
                .multilineTextAlignment(.center)
                Button {} label: { Label("Unlock Pro to add Oak Street", systemImage: "lock.fill") }
                    .buttonStyle(S2Primary())
                    .accessibilityIdentifier("limit.unlock")
                HStack(spacing: 24) {
                    Button("Keep it in my inbox") {}.foregroundStyle(LHB.action)
                    Button("Not landlord work") {}.foregroundStyle(LHB.destructive)
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
            .background(LHB.canvas.ignoresSafeArea())
        }
        .background(LHB.canvas.ignoresSafeArea())
        .sheet(isPresented: $picker) {
            LimitPicker().presentationDetents([.medium]).presentationBackground(LHB.canvas)
        }
        .onAppear { if showPicker { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { picker = true } } }
    }
}

struct LimitPicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Which rental?").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary); Spacer(); GlassClose() }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    PropertySeal(S2Data.pine, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pine Cabin").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                        Text(S2Data.pine.address).font(.subheadline).foregroundStyle(LHB.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).frame(minHeight: 60)
                InsetDivider(leading: 60)
                LockedPreview(size: .row, line: "Free covers one rental.", keeps: "Pine Cabin keeps tracking. Nothing is lost.") {
                    HStack(spacing: 12) {
                        PropertySeal(monogram: "OS", size: 32, dashed: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Oak Street Duplex").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                            Text("From your calendar").font(.subheadline).foregroundStyle(LHB.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 60)
                }
            }
            .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
        .padding(20)
        .background(LHB.canvas.ignoresSafeArea())
    }
}

// MARK: - §5 Restore other data

struct S2Restore: View {
    var confirm = false
    @State private var ask = false

    private let others: [(String, String, String)] = [
        ("brian.old@icloud.com", "5 entries · 2 properties · last Oct 18", "B"),
        ("hide.me.xyz@privaterelay.appleid.com", "0 entries · 1 property · last Sep 2", "H"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text("Your other records").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    Spacer(); GlassClose()
                }
                Text("Records from another sign-in on this iPhone. Yours stay put, and you can switch back any time.")
                    .font(.body).foregroundStyle(LHB.textSecondary)
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.offset) { i, o in
                        Button { ask = true } label: {
                            HStack(spacing: 12) {
                                PropertySeal(monogram: o.2, palette: i == 0 ? .slate : .brass, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.0).font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary).lineLimit(1).truncationMode(.middle)
                                    Text(o.1).font(.subheadline).foregroundStyle(LHB.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textTertiary)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 72).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i == 0 { InsetDivider(leading: 68) }
                    }
                }
                .s2Card()
            }
            .padding(20)
        }
        .background(LHB.canvas.ignoresSafeArea())
        .alert("Open these records?", isPresented: $ask) {
            Button("Open") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll see brian.old@icloud.com’s 5 entries. Your own records stay put; switch back from Settings.")
        }
        .onAppear { if confirm { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ask = true } } }
    }
}

// MARK: - §5 Delete all data (hold)

struct S2DeleteAll: View {
    var pro = true
    /// Static mid-hold for a still frame (0 = idle).
    var frozenProgress: CGFloat = 0
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @State private var startTick = 0
    @State private var doneTick = 0
    @State private var voAlert = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        NavigationStack {
            ZStack {
                if done {
                    welcome.transition(.opacity)
                } else {
                    page.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: done)
            .background(LHB.canvas.ignoresSafeArea())
            .navigationTitle(done ? "" : "Delete all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !done { ToolbarItem(placement: .topBarLeading) { Image(systemName: "chevron.left").foregroundStyle(LHB.action) } } }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: startTick)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: doneTick)
        .onAppear { progress = frozenProgress }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("This removes everything from this iPhone and iCloud:").font(.body).foregroundStyle(LHB.textPrimary)
                VStack(spacing: 0) {
                    item("house", "4 properties")
                    InsetDivider(leading: 52)
                    item("list.bullet.rectangle", "212 entries")
                    InsetDivider(leading: 52)
                    item("photo", "18 receipt photos")
                    InsetDivider(leading: 52)
                    item("target", "Your goal and tax details")
                }
                .s2Card()
                Text("This can’t be undone.").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                if pro {
                    Button { } label: { Label("Export a copy first", systemImage: "square.and.arrow.up") }
                        .buttonStyle(S2Tinted(fullWidth: true))
                }
                holdButton.padding(.top, 8)
                Text("Hold for a moment to confirm.").font(.footnote).foregroundStyle(LHB.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    private func item(_ s: String, _ t: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s).foregroundStyle(LHB.textSecondary).frame(width: 24)
            Text(t).foregroundStyle(LHB.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }

    private var holdButton: some View {
        let label = Text("Hold to delete everything").font(.body.weight(.semibold))
        return ZStack {
            Capsule().fill(LHB.destructiveSurface.opacity(0.5))
            label.foregroundStyle(LHB.destructive)
            // Fill: a destructive overlay revealed left → right (clip, not width, so text stays put).
            ZStack {
                Capsule().fill(LHB.destructive)
                label.foregroundStyle(Color(light: 0xFFFFFF, dark: 0x0B1230))
            }
            .mask(alignment: .leading) {
                GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
            }
        }
        .overlay(Capsule().strokeBorder(LHB.destructive, lineWidth: 1.5))
        .frame(height: 52)
        .scaleEffect(holding && !reduce ? 0.98 : 1)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 40) {
            doneTick += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { done = true }
        } onPressingChanged: { pressing in
            withAnimation(.easeOut(duration: 0.12)) { holding = pressing }
            if pressing {
                startTick += 1
                withAnimation(.linear(duration: 1.5)) { progress = 1 }
            } else if !done {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    if doneTick == 0 { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Delete everything")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { voAlert = true }
        .accessibilityIdentifier("delete.hold")
        .alert("Delete everything?", isPresented: $voAlert) {
            Button("Delete", role: .destructive) { done = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes everything from this iPhone and iCloud. This can’t be undone.") }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("lh_icon_b").resizable().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            DisplayTitle(text: "LandlordHours")
            Text("Everything’s deleted. Start fresh when you’re ready.").font(.body).foregroundStyle(LHB.textSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Get started") {}.buttonStyle(S2Primary()).padding(.horizontal, 20).padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - §5 Get help

struct S2Help: View {
    var filled = false
    @State private var topic: Int?
    @State private var message = ""
    @State private var details = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Brian reads every message.").font(.title3.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    FlowLayout(spacing: 8) {
                        ForEach(Array(["Something’s broken", "A question", "An idea"].enumerated()), id: \.offset) { i, t in
                            Button { topic = i } label: {
                                Text(t).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(topic == i ? LHB.onAction : LHB.textPrimary)
                                    .padding(.horizontal, 16).frame(minHeight: 40)
                                    .background(Capsule().fill(topic == i ? LHB.action : LHB.card))
                                    .overlay(Capsule().strokeBorder(topic == i ? .clear : LHB.border, lineWidth: 1))
                            }
                            .buttonStyle(S2Press())
                            .accessibilityAddTraits(topic == i ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        S2Header("Your message")
                        ZStack(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("What happened?").foregroundStyle(LHB.textTertiary).padding(16)
                            }
                            TextField("", text: $message, axis: .vertical).lineLimit(5...10).padding(16).foregroundStyle(LHB.textPrimary)
                        }
                        .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LHB.border, lineWidth: 1))
                    }
                    Toggle(isOn: $details) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include app details").foregroundStyle(LHB.textPrimary)
                            Text("App version, iPhone model and iOS. No records.").font(.subheadline).foregroundStyle(LHB.textSecondary)
                        }
                    }
                    .toggleStyle(S2Switch())
                    .padding(16).s2Card(16)
                    VStack(spacing: 10) {
                        Button("Write email") {}.buttonStyle(S2Primary()).disabled(message.count < 10)
                        Button("Copy support address") {}.foregroundStyle(LHB.action).frame(minHeight: 44)
                    }
                }
                .padding(20)
            }
            .background(LHB.canvas.ignoresSafeArea())
            .navigationTitle("Get help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "chevron.left").foregroundStyle(LHB.action) } }
        }
        .onAppear {
            if filled { topic = 0; message = "The timer stopped when I locked my phone yesterday, and the draft showed the wrong property." }
        }
    }
}

// MARK: - §5 Learn

struct S2Learn: View {
    var article = false

    private let start = ["What the 750-hour goal means", "What makes a good entry", "Short stays and long stays"]
    private let all = ["The 50% rule", "Spouse hours", "Material participation", "Grouping your rentals", "Keeping receipts", "Driving to your rentals", "Working with your tax pro"]

    var body: some View {
        NavigationStack {
            Group {
                if article { articleView } else { list }
            }
            .background(LHB.canvas.ignoresSafeArea())
            .navigationTitle(article ? "" : "Learn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "chevron.left").foregroundStyle(LHB.action) } }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    S2Header("Start here")
                    VStack(spacing: 0) {
                        ForEach(Array(start.enumerated()), id: \.offset) { i, t in
                            HStack(spacing: 14) {
                                Text(String(format: "%02d", i + 1)).font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(LHB.draftingInk).frame(width: 24, alignment: .leading)
                                Text(t).font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textTertiary)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                            if i < 2 { InsetDivider(leading: 54) }
                        }
                    }
                    .s2Card()
                }
                VStack(alignment: .leading, spacing: 10) {
                    S2Header("All topics")
                    VStack(spacing: 0) {
                        ForEach(Array(all.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text(t).foregroundStyle(LHB.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textTertiary)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            if i < all.count - 1 { InsetDivider() }
                        }
                    }
                    .s2Card()
                }
            }
            .padding(20)
        }
    }

    private var articleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("01 · Start here").drafting(LHB.draftingInk)
                DisplayTitle(text: "What the 750-hour goal means", size: 28)
                Group {
                    Text("If you work in real estate, the tax rules can treat your rentals differently. One of the tests asks for more than 750 hours of work in a year on real estate you’re part of.")
                    Text("Every hour you confirm here goes on that count. Repairs, showings, bookkeeping and the drive to the property all count when they’re real work on a rental.")
                    Text("It’s more than hours, though. Your real estate work also has to be more than half of all the work you do in the year. That’s the 50% rule, and the app checks it when you add your other work hours.")
                    Text("Keep the entries plain and honest: what you did, where, and for how long. That’s the record your tax pro wants to see.")
                }
                .font(.body).foregroundStyle(LHB.textPrimary).lineSpacing(3)
                Rectangle().fill(LHB.border).frame(height: 0.5).padding(.top, 8)
                Text("General information, not tax advice. Your tax pro has the final word.")
                    .font(.footnote).foregroundStyle(LHB.textSecondary)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}
