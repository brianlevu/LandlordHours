import SwiftUI
import LucideIcons

// MARK: - Learning Article Model

struct LearningArticle: Identifiable {
    let id = UUID()
    let category: String
    let categoryColor: Color
    let categoryWash: Color
    let title: String
    let description: String
    let readTime: String
    let iconImage: UIImage
    let content: [ArticleSection]
}

struct ArticleSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
    let callout: String?
}

// MARK: - Static Content

private let learningArticles: [LearningArticle] = [
    LearningArticle(
        category: "IRS BASICS",
        categoryColor: AppColors.primary,
        categoryWash: AppColors.primarySurface,
        title: "What Counts as REPS Hours?",
        description: "Understanding which activities qualify for Real Estate Professional Status.",
        readTime: "3 min",
        iconImage: Lucide.bookOpen,
        content: [
            ArticleSection(
                heading: "Qualifying Activities",
                body: "The IRS requires 750 hours of material participation in real estate activities per tax year. Qualifying activities include property management, maintenance and repairs, tenant relations, bookkeeping, legal work, and travel to and from properties.",
                callout: "Key Rule: You must spend more time in real estate than any other profession (the 50% rule) to qualify as a Real Estate Professional."
            ),
            ArticleSection(
                heading: "What Doesn't Count",
                body: "Passive activities like monitoring investments, reading about real estate, or time spent as a tenant do not count. The IRS looks for active, hands-on involvement in your properties.",
                callout: nil
            ),
            ArticleSection(
                heading: "Documentation Tips",
                body: "Keep contemporaneous logs of your activities. Record the date, property, activity type, and duration for each entry. The IRS may ask for detailed records during an audit, so logging in real-time is critical.",
                callout: "Pro Tip: LandlordHours automatically timestamps and categorizes your entries, making audit documentation much easier."
            )
        ]
    ),
    LearningArticle(
        category: "TAX STRATEGY",
        categoryColor: AppColors.sage,
        categoryWash: AppColors.sageWash,
        title: "The 50% Rule Explained",
        description: "How the 50% rule determines your Real Estate Professional Status eligibility.",
        readTime: "5 min",
        iconImage: Lucide.lightbulb,
        content: [
            ArticleSection(
                heading: "What is the 50% Rule?",
                body: "To qualify as a Real Estate Professional, more than 50% of your total working hours for the year must be spent in real estate trades or businesses. This means your RE hours must exceed your hours in any other profession.",
                callout: "Example: If you work 1,500 total hours in a year, at least 751 must be in real estate activities."
            ),
            ArticleSection(
                heading: "Spouse Hours",
                body: "If filing jointly, only one spouse needs to meet the REPS requirements. However, you cannot combine both spouses' hours to meet the 750-hour test. Each spouse's participation is evaluated separately.",
                callout: nil
            ),
            ArticleSection(
                heading: "Tracking Strategy",
                body: "Use the Reports tab to monitor your 50% compliance throughout the year. The inner ring on your dashboard shows your current ratio. Aim to stay above 50% consistently rather than trying to catch up at year-end.",
                callout: nil
            )
        ]
    ),
    LearningArticle(
        category: "RECORD KEEPING",
        categoryColor: AppColors.coral,
        categoryWash: AppColors.coralWash,
        title: "Audit-Proof Your Logs",
        description: "Best practices for keeping records the IRS will accept.",
        readTime: "4 min",
        iconImage: Lucide.shieldCheck,
        content: [
            ArticleSection(
                heading: "Contemporaneous Records",
                body: "The IRS strongly prefers records made at or near the time of the activity. Reconstructed logs created after the fact are viewed with skepticism. Log your hours daily or as activities occur.",
                callout: "Important: Courts have consistently upheld that contemporaneous records are the gold standard for proving material participation."
            ),
            ArticleSection(
                heading: "What to Record",
                body: "For each entry, document the date, start/end time or total hours, specific property, activity category, and a brief description of what you did. The more detail, the better.",
                callout: nil
            ),
            ArticleSection(
                heading: "Export & Backup",
                body: "Regularly export your logs as PDF reports for your accountant. Keep backups in iCloud or another secure location. Tax records should be retained for at least 7 years.",
                callout: "Pro Feature: LandlordHours Pro generates IRS-ready PDF reports organized by property, category, and date range."
            )
        ]
    ),
    LearningArticle(
        category: "TAX STRATEGY",
        categoryColor: AppColors.sage,
        categoryWash: AppColors.sageWash,
        title: "Material Participation Tests",
        description: "The 7 IRS tests for proving material participation in rental activities.",
        readTime: "6 min",
        iconImage: Lucide.scale,
        content: [
            ArticleSection(
                heading: "The 7 Tests",
                body: "The IRS provides 7 tests for material participation. You only need to pass ONE. Test 1 (500 hours) and Test 3 (100 hours with no one participating more) are the most commonly used by landlords.",
                callout: "Test 1: 500+ hours of participation\nTest 3: 100+ hours, and no one else participates more\nTest 4: Significant participation in multiple activities totaling 500+ hours"
            ),
            ArticleSection(
                heading: "REPS vs Material Participation",
                body: "REPS (750 hours + 50% rule) and Material Participation are different requirements. REPS allows you to deduct rental losses against non-passive income. Material Participation determines whether an activity is passive or non-passive.",
                callout: nil
            ),
            ArticleSection(
                heading: "Grouping Election",
                body: "You may elect to group all rental activities as a single activity for material participation purposes. This can make it easier to meet the tests if you own multiple properties. The election must be made on your tax return.",
                callout: nil
            )
        ]
    ),
    LearningArticle(
        category: "IRS BASICS",
        categoryColor: AppColors.primary,
        categoryWash: AppColors.primarySurface,
        title: "STR vs LTR Tax Rules",
        description: "How short-term and long-term rentals are treated differently for taxes.",
        readTime: "4 min",
        iconImage: Lucide.house,
        content: [
            ArticleSection(
                heading: "Short-Term Rentals (STR)",
                body: "Properties with an average guest stay of 7 days or fewer are automatically classified as non-passive activities by the IRS. This means STR income is not subject to passive activity loss limitations, regardless of REPS status.",
                callout: "Key Benefit: STR owners don't need REPS to deduct rental losses against active income — the 7-day rule handles it automatically."
            ),
            ArticleSection(
                heading: "Long-Term Rentals (LTR)",
                body: "LTR income is generally classified as passive income. To deduct losses against active income (like W-2 wages), you need either REPS qualification or the $25,000 special allowance for active participation (income limits apply).",
                callout: nil
            ),
            ArticleSection(
                heading: "Tracking Both",
                body: "If you own both STR and LTR properties, track hours for each separately. LandlordHours lets you set per-property goals so you can focus your tracking effort where it matters most.",
                callout: nil
            )
        ]
    )
]

// MARK: - Learning Center Hub

struct LearningCenterView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedFilter = "All"
    private let filters = ["All", "IRS Basics", "Tax Strategy", "Record Keeping"]

    private var filteredArticles: [LearningArticle] {
        if selectedFilter == "All" { return learningArticles }
        return learningArticles.filter { $0.category.lowercased().contains(selectedFilter.lowercased().replacingOccurrences(of: " ", with: " ")) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Quick filter chips
                filterChips

                // Featured article
                if let featured = learningArticles.first {
                    featuredCard(featured)
                }

                // Article grid
                let remaining = Array(learningArticles.dropFirst())
                if !remaining.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("All Articles")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(remaining) { article in
                                NavigationLink {
                                    ArticleDetailView(article: article)
                                } label: {
                                    articleGridCard(article)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background {
            // Aurora background
            ZStack {
                colors.background.ignoresSafeArea()
                Circle()
                    .fill(AppColors.coralWash.opacity(0.5))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: 100, y: -100)
                Circle()
                    .fill(AppColors.primarySurface.opacity(0.6))
                    .frame(width: 250, height: 250)
                    .blur(radius: 65)
                    .offset(x: -80, y: 100)
                Circle()
                    .fill(AppColors.skyWash.opacity(0.4))
                    .frame(width: 180, height: 180)
                    .blur(radius: 50)
                    .offset(x: 60, y: 300)
            }
        }
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GUIDES, STRATEGY & GROWTH")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.mist)
                .textCase(.uppercase)

            Text("Master Property\nManagement")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(colors.textPrimary)
                .lineSpacing(2)

            Text("Everything you need to qualify for REPS and maximize your tax benefits.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.slate)
                .lineSpacing(2)
                .padding(.top, 2)
        }
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        withAnimation(AppAnimation.quick) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedFilter == filter ? .white : AppColors.slate)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? AppColors.primary : colors.backgroundSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Featured Card
    private func featuredCard(_ article: LearningArticle) -> some View {
        NavigationLink {
            ArticleDetailView(article: article)
        } label: {
            HStack(spacing: 0) {
                // Illustration area
                ZStack {
                    article.categoryWash
                    ZStack {
                        Circle()
                            .fill(AppColors.charcoal)
                            .frame(width: 28, height: 28)
                        LucideIcon(image: Lucide.bookOpen, size: 14)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)

                    LucideIcon(image: article.iconImage, size: 36)
                        .foregroundStyle(article.categoryColor.opacity(0.4))
                }
                .frame(width: 155, height: 160)

                // Body
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.category)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(article.categoryColor)

                    Text(article.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)

                    Text(article.description)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.slate)
                        .lineSpacing(2)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        LucideIcon(image: Lucide.clock, size: 11)
                            .foregroundStyle(AppColors.mist)
                        Text(article.readTime + " read")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AppColors.mist)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color(hex: "F0F0F0").opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 12, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Article Grid Card
    private func articleGridCard(_ article: LearningArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon area
            ZStack {
                article.categoryWash
                ZStack {
                    Circle()
                        .fill(AppColors.charcoal)
                        .frame(width: 26, height: 26)
                    LucideIcon(image: Lucide.bookOpen, size: 12)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

                Circle()
                    .fill(article.categoryColor.opacity(0.15))
                    .frame(width: 68, height: 68)
                    .overlay(
                        LucideIcon(image: article.iconImage, size: 28)
                            .foregroundStyle(article.categoryColor.opacity(0.6))
                    )
            }
            .frame(height: 110)

            // Body
            VStack(alignment: .leading, spacing: 6) {
                Text(article.category)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(article.categoryColor)

                Text(article.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    LucideIcon(image: Lucide.clock, size: 10)
                        .foregroundStyle(AppColors.mist)
                    Text(article.readTime)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(colors.border.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Article Detail View

struct ArticleDetailView: View {
    let article: LearningArticle
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text(article.category)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(article.categoryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(colors.backgroundSecondary)
                        .clipShape(Capsule())

                    Text(article.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)

                    HStack(spacing: 8) {
                        LucideIcon(image: Lucide.clock, size: 12)
                            .foregroundStyle(AppColors.mist)
                        Text(article.readTime + " read")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.mist)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [article.categoryWash, Color(hex: "FAF7F2")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Content sections
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(article.content) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            // Section heading with left border
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.primary)
                                    .frame(width: 3, height: 20)
                                Text(section.heading)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                            }

                            Text(section.body)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink)
                                .lineSpacing(6)

                            // Callout box
                            if let callout = section.callout {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(callout)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.ink)
                                        .lineSpacing(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(AppColors.primarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .background(colors.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Learning Center") {
    NavigationStack {
        LearningCenterView()
    }
}

#Preview("Article Detail") {
    NavigationStack {
        ArticleDetailView(article: learningArticles.first!)
    }
}
