import SwiftUI
import AuthenticationServices

/// Onboarding shell. Welcome and Staked are full-bleed blueprint; steps 1–5 share one layout: a
/// blueprint band (38% of height) holding the lot scene, a sheet below with one question.
/// The band and the scene are ONE view whose frame morphs between steps.
struct OnbRoot: View {
    @Bindable var flow: OnbFlow
    var embedded = false               // inside the What's-new sheet: no full-bleed, no status bar
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.onbScheme) private var scheme
    @State private var keyboardUp = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var bandFraction: CGFloat {
        if typeSize.isAccessibilitySize { return 0.22 }
        if typeSize >= .xxLarge { return 0.30 }
        if flow.step == .calendar { return embedded ? 0.22 : 0.33 }
        if flow.step == .goal { return 0.23 }
        return 0.38
    }

    var body: some View {
        GeometryReader { g in
            let top = embedded ? 0 : g.safeAreaInsets.top
            let bottom = embedded ? 0 : g.safeAreaInsets.bottom
            let H = g.size.height + top + bottom
            let W = g.size.width
            let full = flow.step.isFullBleed && !embedded
            let bandH = full ? H : (keyboardUp ? top + 50 + 96 : H * (embedded ? bandFraction + 0.02 : bandFraction))
            let scene = sceneFrame(W: W, H: H, top: top, bandH: bandH)

            ZStack(alignment: .top) {
                PC.card.environment(\.colorScheme, scheme)

                HouseBlueprintPaper()
                    .frame(width: W, height: bandH)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 0, bottomTrailingRadius: 0))

                OnbScene(flow: flow, step: flow.step)
                    .environment(\.colorScheme, scheme)      // light/dark house renders follow the app theme
                    .dynamicTypeSize(.large)                  // decorative drawing; the sheet carries the readable copy
                    .frame(width: scene.width, height: scene.width)
                    .position(x: scene.midX, y: scene.midY)

                if !full { chrome(top: top) }

                if !full {
                    sheet(bandH: bandH, H: H)
                        .environment(\.colorScheme, scheme)
                        .transition(.opacity)
                }

                if flow.step == .welcome && !embedded {
                    OnbWelcomeContent(flow: flow, houseBottom: scene.maxY - scene.width * 0.08)
                        .frame(width: W, height: H)
                        .transition(.opacity)
                }
                if flow.step == .staked && !embedded {
                    OnbStakedContent(flow: flow, sceneBottom: scene.maxY)
                        .frame(width: W, height: H)
                        .transition(.opacity)
                }
            }
            .frame(width: W, height: H)
            .environment(\.onbBottomInset, max(bottom, 16))
            .offset(y: -top)
            .overlay { if let p = flow.prompt { OnbSystemPrompt(kind: p, flow: flow).transition(.opacity) } }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: flow.stakeDropped)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.9)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.9)) { keyboardUp = false }
        }
    }

    // MARK: Layout

    private func sceneFrame(W: CGFloat, H: CGFloat, top: CGFloat, bandH: CGFloat) -> CGRect {
        switch flow.step {
        case .welcome where !embedded:
            let s = min(W * 0.92, H * (typeSize >= .xLarge ? 0.30 : 0.42))
            return CGRect(x: (W - s) / 2, y: top + 4, width: s, height: s)
        case .staked where !embedded:
            let s = min(W * 0.96, H * 0.45)
            return CGRect(x: (W - s) / 2, y: top + 18, width: s, height: s)
        default:
            let chromeH: CGFloat = embedded ? 34 : 50
            let avail = bandH - 26 - (top + chromeH)
            let s = min(W * 1.0, avail / 0.84)
            // The render's content sits between y 0.10 (ridge) and 0.93 (lot corner).
            return CGRect(x: (W - s) / 2, y: top + chromeH - 0.09 * s, width: s, height: s)
        }
    }

    // MARK: Progress dimension line + back chevron (in the band, never a skip)

    private func chrome(top: CGFloat) -> some View {
        VStack(spacing: 2) {
            DimensionLine(total: flow.progressTotal, value: flow.progressValue)
                .frame(height: 14)
                .padding(.horizontal, 24)
                .padding(.top, top + (embedded ? 14 : 6))
                .animation(OnbMotion.progress(reduce), value: flow.progressValue)
            HStack {
                if flow.index > 0 {
                    Button { flow.back(reduce: reduce) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("onb-back")
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: The sheet (one question, one primary, one link)

    private func sheet(bandH: CGFloat, H: CGFloat) -> some View {
        let overlap: CGFloat = 22
        return ZStack {
            stepContent
                .id(flow.step)
                .transition(reduce ? .opacity : .asymmetric(
                    insertion: .offset(x: flow.forward ? 36 : -36).combined(with: .opacity),
                    removal: .offset(x: flow.forward ? -36 : 36).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PC.card, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .frame(height: H - bandH + overlap)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var stepContent: some View {
        switch flow.step {
        case .goal: OnbGoalStep(flow: flow)
        case .calendar: OnbCalendarStep(flow: flow)
        case .who: OnbWhoStep(flow: flow)
        case .property: OnbPropertyStep(flow: flow)
        case .notify: OnbNotifyStep(flow: flow)
        case .wnHouse: OnbWhatsNewHouseStep(flow: flow)
        case .welcome, .staked: EmptyView()
        }
    }
}

/// Cyan drafting dimension line: end stops, six ticks, the drawn part grows with `trim`.
struct DimensionLine: View {
    var total: Int
    var value: Int
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, mid = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: w, y: mid))
                }
                .stroke(HouseTokens.drafting.opacity(0.28), lineWidth: 1.5)
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: w, y: mid)) }
                    .trim(from: 0, to: CGFloat(value) / CGFloat(total))
                    .stroke(HouseTokens.drafting, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach(0...total, id: \.self) { i in
                    let on = i <= value
                    Rectangle()
                        .fill(HouseTokens.drafting.opacity(on ? 1 : 0.35))
                        .frame(width: 1.5, height: i == 0 || i == total ? 12 : 7)
                        .position(x: w * CGFloat(i) / CGFloat(total), y: mid)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(value) of \(total)")
    }
}

// MARK: - 0 · Welcome (full-bleed blueprint)

struct OnbWelcomeContent: View {
    let flow: OnbFlow
    var houseBottom: CGFloat
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: max(0, houseBottom))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Every hour builds the house.")
                        .prodDisplay()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("We find the hours you already spend on your rentals. Each one you confirm adds to the house.")
                        .font(.body)
                        .foregroundStyle(HouseTokens.onHeroSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    // One row when it fits; a column at larger text sizes (never truncated).
                    // One row when it fits; otherwise a two-column grid. Never clipped.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { chips }
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow { chip("100h", "Foundation"); chip("500h", "Roof") }
                            GridRow { chip("750h", "Keys") }
                        }
                        VStack(alignment: .leading, spacing: 8) { chips }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 28)          // clears the scrim above the pinned buttons
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 10) {
                Button("Start building") { flow.next(reduce: reduce) }
                    .buttonStyle(ProdHeroPill())
                    .accessibilityIdentifier("onb-start")
                // Apple's own button (App Review): white on the blueprint, small, under the pill.
                HStack(spacing: 10) {
                    Text("Have an account?")
                        .font(.footnote)
                        .foregroundStyle(HouseTokens.onHeroSecondary)
                    SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                        .signInWithAppleButtonStyle(.white)
                        .frame(width: 168, height: 36)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
                Text("Your records stay on your iPhone and in your iCloud.")
                    .font(.footnote)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, bottomInset + 8)
            .background(alignment: .top) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep.opacity(0.85)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                    .padding(.top, -24)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var chips: some View {
        chip("100h", "Foundation")
        chip("500h", "Roof")
        chip("750h", "Keys")
    }

    private func chip(_ h: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(h).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.subheadline).foregroundStyle(HouseTokens.onHeroSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .overlay(Capsule().strokeBorder(HouseTokens.drafting.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - 6 · Staked (full-bleed blueprint)

struct OnbStakedContent: View {
    let flow: OnbFlow
    var sceneBottom: CGFloat
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var countLine: String {
        if let h = flow.goalHours { return "0 of \(h)h" }
        return "0h in the book"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: max(0, sceneBottom - 6))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if flow.calendar == .allowed && flow.scanDone && flow.foundHours > 0 {
                        // The aha leads: what we found, then that it is theirs to confirm.
                        Text("\(flow.name.isEmpty ? "Your rental" : flow.name) is staked").drafting(HouseTokens.drafting)
                        Text("\(flow.foundText) found")
                            .prodDisplay()
                            .foregroundStyle(.white)
                            .padding(.top, 6)
                            .accessibilityAddTraits(.isHeader)
                            .onAppear { flow.countShown = true }
                        Text("From \(flow.suggestions) calendar events in the last 90 days. Confirm the ones that were rental work.")
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        Text("\(countLine) counted so far").drafting(HouseTokens.drafting).padding(.top, 14)
                    } else {
                        Text(countLine).drafting(HouseTokens.drafting)
                        Text("Your house is staked.")
                            .prodDisplay()
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        Text(flow.goal == .record
                             ? "Every hour you confirm from here is saved to your record."
                             : "Every hour you confirm from here adds to your house.")
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        if flow.calendar == .allowed {
                            Text("Looking back 90 days · \(flow.foundText) so far")
                                .drafting(HouseTokens.drafting)
                                .padding(.top, 16)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            let review = flow.calendar == .allowed && flow.scanDone && flow.suggestions > 0
            Button(review ? "Review \(flow.suggestions) suggestions" : "Go to Today") {
                if review { withAnimation(.easeInOut(duration: 0.35)) { flow.stage = .review } } else { flow.finish() }
            }
                .buttonStyle(ProdHeroPill())
                .accessibilityIdentifier("onb-today")
                .padding(.horizontal, 24)
                .padding(.bottom, bottomInset + 8)
        }
    }
}
