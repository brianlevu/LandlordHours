import SwiftUI
import LucideIcons

// MARK: - Learning Article Model

struct LearningArticle: Identifiable, Equatable {
    let id: String
    let category: String
    let section: String          // Section grouping (e.g. "Understanding REPS", "Smart Tax Moves")
    let categoryColor: Color
    let categoryWash: Color
    let title: String
    let description: String
    let readTime: String
    let iconImage: UIImage
    let content: [ArticleSection]
    let relatedIds: [String]

    static func == (lhs: LearningArticle, rhs: LearningArticle) -> Bool { lhs.id == rhs.id }
}

struct ArticleSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
    let callout: String?
}

// MARK: - Guide Model

struct LearningGuide: Identifiable {
    let id: String
    let title: String
    let category: String
    let description: String
    let totalTime: String
    let gradient: [Color]
    let blobColor: Color
    let lessons: [GuideLesson]
    let source: String
}

struct GuideLesson: Identifiable {
    let id: Int       // Lesson number
    let title: String
    let duration: String
    let content: [ArticleSection]
}

// MARK: - Quick Read Model

struct QuickRead: Identifiable {
    let id: String
    let title: String
    let readTime: String
    let iconImage: UIImage
    let iconColor: Color
    let iconWash: Color
    let content: [ArticleSection]
}

// MARK: - Static Content

private let allArticles: [LearningArticle] = [
    // --- Section: Understanding REPS ---
    LearningArticle(
        id: "reps-basics",
        category: "IRS BASICS",
        section: "Understanding REPS",
        categoryColor: AppColors.primary,
        categoryWash: AppColors.primarySurface,
        title: "What is Real Estate Professional Status?",
        description: "The 750-hour rule, 50% test, and how to qualify for REPS.",
        readTime: "5 min",
        iconImage: Lucide.house,
        content: [
            ArticleSection(
                heading: "The Basics",
                body: "Real Estate Professional Status (REPS) is an IRS designation that allows qualifying taxpayers to treat all rental real estate losses as non-passive. This means losses can offset your active income \u{2014} W-2 wages, business income, etc.",
                callout: "Key Requirements:\n1. More than 750 hours in real estate activities per year\n2. More than 50% of total working hours in real estate\n3. Material participation in each rental property"
            ),
            ArticleSection(
                heading: "What Counts as RE Hours?",
                body: "The IRS considers these qualifying activities: property management, repairs, tenant screening, bookkeeping, travel to properties, lease negotiations, and more.",
                callout: nil
            ),
            ArticleSection(
                heading: "Documentation Tips",
                body: "Keep contemporaneous logs of your activities. Record the date, property, activity type, and duration for each entry. The IRS may ask for detailed records during an audit, so logging in real-time is critical.",
                callout: "Pro Tip: LandlordHours automatically timestamps and categorizes your entries, making audit documentation much easier."
            )
        ],
        relatedIds: ["50-percent-rule", "hours-that-count"]
    ),
    LearningArticle(
        id: "50-percent-rule",
        category: "TAX STRATEGY",
        section: "Understanding REPS",
        categoryColor: AppColors.successGreen,
        categoryWash: AppColors.sageWash,
        title: "The 50% Rule Explained",
        description: "How the 50% rule determines your REPS eligibility.",
        readTime: "4 min",
        iconImage: Lucide.circleCheck,
        content: [
            ArticleSection(
                heading: "What is the 50% Rule?",
                body: "To qualify as a Real Estate Professional, more than 50% of your total working hours for the year must be spent in real estate trades or businesses. This means your RE hours must exceed your hours in any other profession.",
                callout: "Example: If you work 1,500 total hours in a year, at least 751 must be in real estate activities."
            ),
            ArticleSection(
                heading: "Spouse Hours",
                body: "If filing jointly, only one spouse needs to meet the REPS requirements. However, you cannot combine both spouses\u{2019} hours to meet the 750-hour test. Each spouse\u{2019}s participation is evaluated separately.",
                callout: nil
            ),
            ArticleSection(
                heading: "Tracking Strategy",
                body: "Use the Reports tab to monitor your 50% compliance throughout the year. The inner ring on your dashboard shows your current ratio. Aim to stay above 50% consistently rather than trying to catch up at year-end.",
                callout: nil
            )
        ],
        relatedIds: ["reps-basics", "spouse-hours"]
    ),
    LearningArticle(
        id: "hours-that-count",
        category: "RECORD KEEPING",
        section: "Understanding REPS",
        categoryColor: AppColors.coral,
        categoryWash: AppColors.coralWash,
        title: "Hours That Count for IRS",
        description: "Best practices for keeping records the IRS will accept.",
        readTime: "5 min",
        iconImage: Lucide.fileText,
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
        ],
        relatedIds: ["reps-basics", "audit-red-flags"]
    ),

    // --- Section: Smart Tax Moves ---
    LearningArticle(
        id: "str-vs-ltr",
        category: "TAX STRATEGY",
        section: "Smart Tax Moves",
        categoryColor: AppColors.primary,
        categoryWash: AppColors.primarySurface,
        title: "STR vs LTR: Tax Differences",
        description: "How short-term and long-term rentals are treated differently.",
        readTime: "6 min",
        iconImage: Lucide.house,
        content: [
            ArticleSection(
                heading: "Short-Term Rentals (STR)",
                body: "Properties with an average guest stay of 7 days or fewer are automatically classified as non-passive activities by the IRS. This means STR income is not subject to passive activity loss limitations, regardless of REPS status.",
                callout: "Key Benefit: STR owners don\u{2019}t need REPS to deduct rental losses against active income \u{2014} the 7-day rule handles it automatically."
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
        ],
        relatedIds: ["reps-basics", "spouse-hours"]
    ),
    LearningArticle(
        id: "spouse-hours",
        category: "TAX STRATEGY",
        section: "Smart Tax Moves",
        categoryColor: AppColors.honey,
        categoryWash: AppColors.honeyWash,
        title: "Spouse Hours Strategy",
        description: "How to maximize spouse participation for tax qualification.",
        readTime: "4 min",
        iconImage: Lucide.users,
        content: [
            ArticleSection(
                heading: "Filing Jointly",
                body: "If you file a joint return, only one spouse needs to qualify as a Real Estate Professional. The qualifying spouse must individually meet both the 750-hour test and the 50% rule.",
                callout: nil
            ),
            ArticleSection(
                heading: "Material Participation",
                body: "For material participation tests, both spouses\u{2019} hours can be combined. This is different from the REPS test itself. If both spouses actively work on properties, their combined hours count toward meeting Material Participation Tests 1 through 7.",
                callout: "Strategy: Have one spouse focus on meeting REPS (750h + 50% rule), while both spouses contribute to material participation in each property."
            ),
            ArticleSection(
                heading: "Tracking in LandlordHours",
                body: "Use the participant toggle (Self / Spouse) when logging entries. The Reports tab shows each person\u{2019}s hours separately, making it easy to verify qualification at tax time.",
                callout: nil
            )
        ],
        relatedIds: ["50-percent-rule", "material-participation"]
    ),

    // --- Section: Grow Your Portfolio ---
    LearningArticle(
        id: "add-property-2",
        category: "GROWTH",
        section: "Grow Your Portfolio",
        categoryColor: AppColors.sky,
        categoryWash: AppColors.skyWash,
        title: "When to Add Property #2",
        description: "Timing your portfolio expansion for maximum tax benefit.",
        readTime: "7 min",
        iconImage: Lucide.trendingUp,
        content: [
            ArticleSection(
                heading: "The Right Time",
                body: "Adding a second property can make REPS qualification easier if you\u{2019}re close to the 750-hour threshold. More properties create more legitimate work to log. However, each property must show material participation individually unless you make a grouping election.",
                callout: nil
            ),
            ArticleSection(
                heading: "Financial Considerations",
                body: "Before expanding, ensure you have adequate reserves for both properties, understand the financing implications, and have a clear management plan. Overleveraging is the #1 risk for new landlords scaling up.",
                callout: nil
            ),
            ArticleSection(
                heading: "Grouping Election",
                body: "Once you have multiple properties, consider the IRC \u{00A7}469 grouping election. This lets you treat all rental activities as a single activity for material participation tests, making it much easier to qualify.",
                callout: "Important: The grouping election must be made on your tax return and is generally irrevocable once made."
            )
        ],
        relatedIds: ["grouping-election", "str-vs-ltr"]
    ),
    LearningArticle(
        id: "grouping-election",
        category: "MANAGEMENT",
        section: "Grow Your Portfolio",
        categoryColor: AppColors.rose,
        categoryWash: AppColors.roseWash,
        title: "Grouping Election Guide",
        description: "How to group rental activities for easier qualification.",
        readTime: "5 min",
        iconImage: Lucide.fileText,
        content: [
            ArticleSection(
                heading: "What is the Grouping Election?",
                body: "IRC \u{00A7}469 allows landlords with multiple properties to elect to treat all rental real estate activities as a single activity for material participation purposes. Instead of proving participation in each property individually, you prove it once for the group.",
                callout: nil
            ),
            ArticleSection(
                heading: "How to Make the Election",
                body: "Attach a statement to your tax return identifying all rental activities being grouped, and state that you are electing to treat them as a single activity under Reg. 1.469-9(g). Your tax professional can help with the exact language.",
                callout: "Timing: The election is typically made the first year you have multiple properties. Once made, it generally applies to future years as well."
            ),
            ArticleSection(
                heading: "When It Helps Most",
                body: "Grouping is most beneficial when you have several properties and spend varying amounts of time on each. Without grouping, a property where you logged only 80 hours might fail Test 1 (500h) individually, but passes easily when combined with your other properties.",
                callout: nil
            )
        ],
        relatedIds: ["add-property-2", "material-participation"]
    ),
]

private let allGuides: [LearningGuide] = [
    LearningGuide(
        id: "reps-roadmap",
        title: "REPS Qualification Roadmap",
        category: "IRS BASICS",
        description: "A step-by-step guide to achieving Real Estate Professional Status. Learn the requirements, build your tracking habits, and prepare for tax season.",
        totalTime: "25 min",
        gradient: [AppColors.primaryDark, AppColors.primary],
        blobColor: AppColors.primaryLight,
        lessons: [
            GuideLesson(id: 1, title: "Understanding REPS Requirements", duration: "5 min", content: [
                ArticleSection(heading: "What is REPS?", body: "Real Estate Professional Status is a special IRS designation under IRC \u{00A7}469(c)(7). It allows you to deduct rental real estate losses against active income \u{2014} something passive investors cannot do. This is one of the most powerful tax benefits available to landlords.", callout: nil),
                ArticleSection(heading: "The Two Tests", body: "You must pass BOTH tests in the same tax year:\n\n1. The 750-Hour Test: Spend more than 750 hours in real estate trades or businesses\n2. The 50% Rule: More than half your total working hours must be in real estate\n\nFailing either test means you don\u{2019}t qualify for that year.", callout: "Remember: These are calendar-year tests. Hours don\u{2019}t carry over from one year to the next.")
            ]),
            GuideLesson(id: 2, title: "The 750-Hour Threshold", duration: "6 min", content: [
                ArticleSection(heading: "Breaking Down 750 Hours", body: "750 hours equals roughly 14.5 hours per week, or just over 2 hours per day. While this sounds manageable, it requires consistent tracking and legitimate activities. The IRS has denied REPS status to taxpayers who couldn\u{2019}t prove their hours.", callout: nil),
                ArticleSection(heading: "What Counts", body: "Qualifying activities include: property repairs and maintenance, tenant screening and leasing, rent collection, bookkeeping and financial management, legal and compliance work, travel to and from properties, contractor supervision, and property inspections.", callout: "Tip: Start logging from day one. Even 15-minute tasks add up over a full year.")
            ]),
            GuideLesson(id: 3, title: "Meeting the 50% Rule", duration: "4 min", content: [
                ArticleSection(heading: "The Calculation", body: "Add up ALL your working hours for the year \u{2014} W-2 employment, self-employment, real estate, everything. Your real estate hours must exceed 50% of that total. If you work a full-time job (2,000 hours), you\u{2019}d need over 2,000 hours in real estate too.", callout: "Strategy: Many REPS filers reduce outside employment hours to make the 50% test achievable. Consider going part-time at your day job if feasible."),
                ArticleSection(heading: "Spouse Qualification", body: "Only one spouse needs to qualify. If one spouse works full-time and the other manages the properties, the managing spouse can be the qualifying Real Estate Professional.", callout: nil)
            ]),
            GuideLesson(id: 4, title: "Tracking Hours Effectively", duration: "5 min", content: [
                ArticleSection(heading: "Contemporaneous Logging", body: "The IRS expects \u{201C}contemporaneous\u{201D} records \u{2014} logs made at or near the time of the activity. Courts have rejected reconstructed logs created months or years later. LandlordHours timestamps every entry automatically.", callout: nil),
                ArticleSection(heading: "What to Record", body: "For each activity: date, property address, activity category, time spent, and a brief description. The more specific, the better. \u{201C}Repaired kitchen faucet at 123 Main St \u{2014} 1.5 hours\u{201D} is much stronger than \u{201C}Maintenance \u{2014} 2 hours.\u{201D}", callout: "Pro Tip: Use the AI assistant in Track Time \u{2014} describe your work in plain English and it will categorize and log it for you.")
            ]),
            GuideLesson(id: 5, title: "Tax Season Preparation", duration: "5 min", content: [
                ArticleSection(heading: "Before Filing", body: "Export your full year\u{2019}s log as a PDF report. Review it with your CPA or tax professional. Verify you\u{2019}ve met both the 750-hour test and 50% rule. Check material participation for each property (or group).", callout: nil),
                ArticleSection(heading: "If Audited", body: "The IRS may request your detailed hour logs during an audit. Having organized, contemporaneous records is your best defense. LandlordHours reports include dates, properties, categories, and total hours \u{2014} exactly what the IRS wants to see.", callout: "Keep your records for at least 7 years after filing.")
            ])
        ],
        source: "Sources: IRS Publication 925, IRC \u{00A7}469"
    ),
    LearningGuide(
        id: "first-year-landlord",
        title: "First-Year Landlord Tax Guide",
        category: "TAX STRATEGY",
        description: "Everything new landlords need to know about rental property taxes, from deductions to depreciation.",
        totalTime: "20 min",
        gradient: [AppColors.successGreen, AppColors.success],
        blobColor: AppColors.successGreenSoft,
        lessons: [
            GuideLesson(id: 1, title: "Rental Income Basics", duration: "5 min", content: [
                ArticleSection(heading: "What\u{2019}s Taxable", body: "All rental income must be reported on Schedule E. This includes rent payments, late fees, pet fees, and any other income from the property. Security deposits are generally not income unless you keep them.", callout: nil)
            ]),
            GuideLesson(id: 2, title: "Deductible Expenses", duration: "5 min", content: [
                ArticleSection(heading: "Common Deductions", body: "Mortgage interest, property taxes, insurance, repairs, professional services, travel to the property, and depreciation are all deductible expenses. Keep receipts for everything \u{2014} LandlordHours lets you attach photos of receipts to time entries.", callout: nil)
            ]),
            GuideLesson(id: 3, title: "Depreciation Explained", duration: "5 min", content: [
                ArticleSection(heading: "The Basics", body: "Residential rental property is depreciated over 27.5 years using the straight-line method. This \u{201C}paper loss\u{201D} reduces your taxable income without any cash outflow. It\u{2019}s one of the biggest tax advantages of owning rental property.", callout: "Note: Land cannot be depreciated \u{2014} only the building and improvements.")
            ]),
            GuideLesson(id: 4, title: "Passive Activity Rules", duration: "5 min", content: [
                ArticleSection(heading: "Passive vs Active", body: "By default, rental income is passive. Passive losses can only offset passive income. However, there\u{2019}s a $25,000 special allowance for active participants (phases out between $100K-$150K AGI). REPS qualification removes the passive limitation entirely.", callout: nil)
            ])
        ],
        source: "Sources: IRS Publication 527, Schedule E Instructions"
    ),
    LearningGuide(
        id: "audit-proof",
        title: "Audit-Proof Your Records",
        category: "RECORD KEEPING",
        description: "How to build a documentation system that stands up to IRS scrutiny.",
        totalTime: "15 min",
        gradient: [AppColors.destructive, AppColors.coral],
        blobColor: Color.white.opacity(0.3),
        lessons: [
            GuideLesson(id: 1, title: "The IRS Standard", duration: "5 min", content: [
                ArticleSection(heading: "What They Expect", body: "The IRS expects \u{201C}adequate records\u{201D} to support your claimed hours. In practice, this means contemporaneous logs with specific dates, properties, activities, and durations. Vague entries or after-the-fact reconstructions are routinely rejected in Tax Court.", callout: nil)
            ]),
            GuideLesson(id: 2, title: "Building Good Habits", duration: "5 min", content: [
                ArticleSection(heading: "Daily Logging", body: "The best approach is to log activities the same day they occur. Set a daily reminder to open LandlordHours and record your work. Even a 2-minute entry is better than trying to remember details weeks later.", callout: "Tip: Use the AI assistant \u{2014} just describe what you did in plain English and it auto-fills the fields.")
            ]),
            GuideLesson(id: 3, title: "Export & Archive", duration: "5 min", content: [
                ArticleSection(heading: "Regular Backups", body: "Export quarterly PDF reports and save them with your tax documents. Keep digital and physical copies. Store records for at least 7 years after filing.", callout: nil)
            ])
        ],
        source: "Sources: IRS Publication 925, Tax Court case law"
    ),
]

private let allQuickReads: [QuickRead] = [
    QuickRead(
        id: "what-counts-hour",
        title: "What Counts as an Hour?",
        readTime: "2 min",
        iconImage: Lucide.clock,
        iconColor: AppColors.primary,
        iconWash: AppColors.primarySurface,
        content: [
            ArticleSection(heading: "Minimum Increments", body: "The IRS doesn\u{2019}t specify a minimum increment, but logging in 15-minute blocks is a safe, defensible practice. Don\u{2019}t round up aggressively \u{2014} if you spent 20 minutes, log 0.25 or 0.5 hours, not a full hour.", callout: nil),
            ArticleSection(heading: "Travel Time", body: "Time driving to and from your rental property counts as qualifying hours. Keep a mileage log alongside your time log for additional documentation.", callout: nil)
        ]
    ),
    QuickRead(
        id: "receipt-practices",
        title: "Receipt Best Practices",
        readTime: "3 min",
        iconImage: Lucide.fileText,
        iconColor: AppColors.sage,
        iconWash: AppColors.sageWash,
        content: [
            ArticleSection(heading: "Snap and Attach", body: "Photograph receipts the day you get them \u{2014} thermal paper fades quickly. Attach the photo to the relevant time entry in LandlordHours so it\u{2019}s linked to the activity.", callout: nil),
            ArticleSection(heading: "What to Keep", body: "Keep receipts for materials, contractor invoices, mileage records, and any expense over $75. For expenses under $75, a log entry with the amount, date, and purpose is sufficient.", callout: nil)
        ]
    ),
    QuickRead(
        id: "audit-red-flags",
        title: "Audit Red Flags to Avoid",
        readTime: "2 min",
        iconImage: Lucide.shield,
        iconColor: AppColors.honey,
        iconWash: AppColors.honeyWash,
        content: [
            ArticleSection(heading: "Common Triggers", body: "The IRS flags returns that claim REPS with a full-time W-2 job, show exactly 750 hours (suspiciously precise), or have large rental losses relative to income. Having detailed, contemporaneous logs is your best protection.", callout: nil),
            ArticleSection(heading: "Stay Honest", body: "Never fabricate hours or inflate time. The penalties for fraud far exceed any tax benefit. Focus on legitimate tracking \u{2014} most active landlords are surprised how quickly hours add up when properly logged.", callout: nil)
        ]
    ),
]

// MARK: - Helpers

private let materialParticipationArticle = LearningArticle(
    id: "material-participation",
    category: "TAX STRATEGY",
    section: "Smart Tax Moves",
    categoryColor: AppColors.sage,
    categoryWash: AppColors.sageWash,
    title: "Material Participation Tests",
    description: "The 7 IRS tests for proving material participation.",
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
    ],
    relatedIds: ["50-percent-rule", "grouping-election"]
)

// Combine all articles for lookup
private var allArticlesWithExtra: [LearningArticle] {
    allArticles + [materialParticipationArticle]
}

private func articleById(_ id: String) -> LearningArticle? {
    allArticlesWithExtra.first { $0.id == id }
}

private func articleVisualAssetName(_ article: LearningArticle) -> String {
    if article.section == "Grow Your Portfolio" || article.id == "grouping-election" {
        return "LearningArticlePortfolio"
    }

    if article.category == "RECORD KEEPING" || article.id == "audit-red-flags" || article.id == "receipt-practices" {
        return "LearningArticleRecords"
    }

    return "LearningArticleQualification"
}

// MARK: - Section Grouping

private struct ArticleGroup: Identifiable {
    let id: String
    let kicker: String
    let name: String
    let articles: [LearningArticle]
}

private let articleSections: [ArticleGroup] = {
    let sections = Dictionary(grouping: allArticles, by: \.section)
    let order = ["Understanding REPS", "Smart Tax Moves", "Grow Your Portfolio"]
    let kickers = ["IRS BASICS": "IRS BASICS", "Smart Tax Moves": "TAX STRATEGY", "Grow Your Portfolio": "PROPERTY MANAGEMENT"]
    return order.compactMap { name in
        guard let articles = sections[name], !articles.isEmpty else { return nil }
        return ArticleGroup(id: name, kicker: kickers[name] ?? "ARTICLES", name: name, articles: articles)
    }
}()

// MARK: - Learning Center Hub

struct LearningCenterView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedFilter = "All"
    private let filters = ["All", "Tax Strategy", "IRS Basics", "Record Keeping", "Growth"]

    private var filteredSections: [ArticleGroup] {
        if selectedFilter == "All" { return articleSections }
        return articleSections.compactMap { group in
            let filtered = group.articles.filter {
                $0.category.lowercased().contains(selectedFilter.lowercased()) ||
                $0.section.lowercased().contains(selectedFilter.lowercased())
            }
            return filtered.isEmpty ? nil : ArticleGroup(id: group.id, kicker: group.kicker, name: group.name, articles: filtered)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                learningHeroCard
                startHereSection
                filterChips

                // Sectioned articles
                ForEach(filteredSections) { section in
                    articleSectionView(section)
                }

                // Guides carousel
                guidesSection

                // Quick reads
                quickReadsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background { LHMobileCanvas() }
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learn")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineSpacing(-2)
                .minimumScaleFactor(0.82)

            Text("Plain-English tax guidance, recordkeeping tips, and property management playbooks.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(3)
        }
    }

    private var learningHeroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Image("LearningHero")
                .resizable()
                .scaledToFill()
                .frame(height: 184)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.fileText, size: 14)
                    Text("IRS-ready records")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppColors.onAction)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.onAction.opacity(0.18))
                .clipShape(Capsule())

                Text("Learn what to track before tax time")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.onAction)
                    .lineSpacing(1)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
            }
            .padding(18)
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl, style: .continuous)
                .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.2 : 0.35), lineWidth: 1)
        }
    }

    // MARK: - Start Here
    private var startHereSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Start here")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
            }

            VStack(spacing: 10) {
                startHereRow(
                    articleId: "reps-basics",
                    title: "Know the REPS tests",
                    subtitle: "750 hours, 50% rule, and what the IRS expects.",
                    icon: Lucide.target,
                    color: AppColors.primary,
                    wash: colors.primarySurface
                )
                startHereRow(
                    articleId: "hours-that-count",
                    title: "Log defensible hours",
                    subtitle: "What details make your entries easier to review.",
                    icon: Lucide.clipboardCheck,
                    color: AppColors.sky,
                    wash: colors.skyWash
                )
                startHereRow(
                    articleId: "str-vs-ltr",
                    title: "Understand STR vs LTR",
                    subtitle: "Different property types can change the tax strategy.",
                    icon: Lucide.house,
                    color: AppColors.coral,
                    wash: colors.coralWash
                )
            }
        }
    }

    @ViewBuilder
    private func startHereRow(
        articleId: String,
        title: String,
        subtitle: String,
        icon: UIImage,
        color: Color,
        wash: Color
    ) -> some View {
        if let article = articleById(articleId) {
            NavigationLink {
                ArticleDetailView(article: article)
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(wash.opacity(colorScheme == .dark ? 0.22 : 1))
                        .frame(width: 46, height: 46)
                        .overlay {
                            LucideIcon(image: icon, size: 20)
                                .foregroundStyle(color)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    LucideIcon(image: Lucide.chevronRight, size: 16)
                        .foregroundStyle(colors.textTertiary)
                }
                .padding(14)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(colors.border.opacity(0.28), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        animate(AppAnimation.quick) { selectedFilter = filter }
                    } label: {
                        Text(filter)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedFilter == filter ? AppColors.charcoal : colors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selectedFilter == filter ? colors.sageWash : colors.backgroundSecondary)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selectedFilter == filter ? AppColors.sage.opacity(0.65) : colors.border.opacity(0.35),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // MARK: - Article Section
    private func articleSectionView(_ section: ArticleGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.name)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
                Spacer()
            }

            // Featured first, then grid for the rest
            if let featured = section.articles.first {
                featuredCard(featured)
            }

            let remaining = Array(section.articles.dropFirst())
            if !remaining.isEmpty {
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

    // MARK: - Featured Card
    private func featuredCard(_ article: LearningArticle) -> some View {
        NavigationLink {
            ArticleDetailView(article: article)
        } label: {
            HStack(spacing: 0) {
                learningArticleImage(article, height: 160)
                .frame(width: 140, height: 160)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(article.category)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(article.categoryColor)

                    Text(article.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)

                    Text(article.description)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .stroke(colors.border.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Article Grid Card
    private func articleGridCard(_ article: LearningArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            learningArticleImage(article, height: 104)
            .frame(height: 100)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.category)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(article.categoryColor)

                Text(article.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .stroke(colors.border.opacity(0.35), lineWidth: 1)
        )
    }

    private func learningArticleImage(_ article: LearningArticle, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(articleVisualAssetName(article))
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, .black.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.82))
                .frame(width: 34, height: 34)
                .overlay {
                    LucideIcon(image: article.iconImage, size: 17)
                        .foregroundStyle(article.categoryColor)
                }
                .padding(12)
        }
        .background(article.categoryWash)
    }

    // MARK: - Guides Carousel
    private var guidesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Expert Guides")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allGuides) { guide in
                        NavigationLink {
                            GuideDetailView(guide: guide)
                        } label: {
                            guideCard(guide)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.trailing, -20) // Bleed past padding
        }
    }

    private func guideCard(_ guide: LearningGuide) -> some View {
        ZStack(alignment: .topTrailing) {
            // Background gradient
            LinearGradient(colors: guide.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            // Blob
            Circle()
                .fill(guide.blobColor)
                .frame(width: 60, height: 60)
                .blur(radius: 8)
                .offset(x: 10, y: -10)
                .opacity(0.15)

            // Darkening overlay at bottom
            LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading) {
                Text("\(guide.lessons.count) lessons")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.onAction.opacity(0.82))

                Spacer()

                Text(guide.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.onAction)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(guide.totalTime)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    // Play circle
                    Circle()
                        .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Triangle()
                                .fill(.white.opacity(0.9))
                                .frame(width: 9, height: 10)
                                .offset(x: 1)
                        )
                }
            }
            .padding(20)
        }
        .frame(width: 220, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Quick Reads
    private var quickReadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bite-Sized Tips")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
            }

            ForEach(allQuickReads) { item in
                NavigationLink {
                    QuickReadDetailView(quickRead: item)
                } label: {
                    quickReadRow(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickReadRow(_ item: QuickRead) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(item.iconWash)
                .frame(width: 40, height: 40)
                .overlay(
                    LucideIcon(image: item.iconImage, size: 20)
                        .foregroundStyle(item.iconColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(item.readTime + " read")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            LucideIcon(image: Lucide.chevronRight, size: 16)
                .foregroundStyle(AppColors.cloud)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .stroke(colors.border.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Play Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                        colors: [article.categoryWash, colors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Image(articleVisualAssetName(article))
                    .resizable()
                    .scaledToFill()
                    .frame(height: 214)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 7) {
                            LucideIcon(image: article.iconImage, size: 15)
                            Text(article.section)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(AppColors.onAction)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.28))
                        .clipShape(Capsule())
                        .padding(16)
                    }
                    .accessibilityHidden(true)

                // Content sections
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(article.content) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.heading)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.textPrimary)

                            Text(section.body)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                                .lineSpacing(6)

                            if let callout = section.callout {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(callout)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(colors.textPrimary)
                                        .lineSpacing(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(colors.primarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                            }
                        }
                    }

                    // Related articles
                    if !article.relatedIds.isEmpty {
                        relatedArticlesSection
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .background(colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
    }

    private var relatedArticlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Related Articles")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            ForEach(article.relatedIds, id: \.self) { relatedId in
                if let related = articleById(relatedId) {
                    NavigationLink {
                        ArticleDetailView(article: related)
                    } label: {
                        HStack {
                            Text(related.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)
                            Spacer()
                            Text(related.readTime)
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.mist)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Guide Detail View

struct GuideDetailView: View {
    let guide: LearningGuide
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var completedLessons: Set<Int> = []
    @State private var selectedLesson: GuideLesson?

    private var currentLesson: Int {
        let maxCompleted = completedLessons.max() ?? 0
        return min(maxCompleted + 1, guide.lessons.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    guide.gradient.first?.opacity(0.16) ?? colors.primarySurface

                    Text("\(guide.lessons.count) lessons · \(guide.totalTime)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .padding(20)
                }
                .frame(height: 104)

                // Body
                VStack(alignment: .leading, spacing: 0) {
                    Text(guide.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)

                    Text(guide.category)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(guide.gradient.first ?? AppColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(colors.backgroundSecondary)
                        .clipShape(Capsule())
                        .padding(.top, 8)

                    Text(guide.description)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(4)
                        .padding(.top, 12)

                    // Start button
                    Button {
                        if let first = guide.lessons.first {
                            selectedLesson = first
                        }
                    } label: {
                        Text("Start Guide")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.charcoal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(colors.sageWash)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(AppColors.sage.opacity(0.7), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)

                    // Lessons list
                    Text("Lessons")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .padding(.top, 28)

                    ForEach(guide.lessons) { lesson in
                        Button {
                            selectedLesson = lesson
                        } label: {
                            lessonRow(lesson)
                        }
                        .buttonStyle(.plain)
                    }

                    // Source card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Created with IRS guidance")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.slate)
                        Text(guide.source)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.mist)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.large)
                            .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                    }
                    .padding(.top, 24)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .background(colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .navigationDestination(item: $selectedLesson) { lesson in
            LessonDetailView(
                guide: guide,
                lesson: lesson,
                isCompleted: completedLessons.contains(lesson.id),
                onComplete: {
                    completedLessons.insert(lesson.id)
                }
            )
        }
    }

    private func lessonRow(_ lesson: GuideLesson) -> some View {
        HStack(spacing: 14) {
            // Number badge
            Group {
                if completedLessons.contains(lesson.id) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.sageWash)
                        .frame(width: 30, height: 30)
                        .overlay(
                            LucideIcon(image: Lucide.check, size: 14)
                                .foregroundStyle(AppColors.sage)
                        )
                } else if lesson.id == currentLesson {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: guide.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text("\(lesson.id)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.onAction)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.snow)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text("\(lesson.id)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.mist)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(lesson.duration)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            LucideIcon(image: Lucide.chevronRight, size: 16)
                .foregroundStyle(AppColors.cloud)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if lesson.id < guide.lessons.count {
                Divider().padding(.leading, 44)
            }
        }
    }
}

// MARK: - Lesson Detail View

struct LessonDetailView: View {
    let guide: LearningGuide
    let lesson: GuideLesson
    let isCompleted: Bool
    let onComplete: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lesson \(lesson.id) of \(guide.lessons.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle((guide.gradient.first ?? AppColors.primary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(colors.backgroundSecondary)
                        .clipShape(Capsule())

                    Text(lesson.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)

                    HStack(spacing: 8) {
                        LucideIcon(image: Lucide.clock, size: 12)
                            .foregroundStyle(AppColors.mist)
                        Text(lesson.duration + " read")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.mist)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [(guide.gradient.last ?? AppColors.primary).opacity(0.15), colors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Content
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(lesson.content) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(guide.gradient.first ?? AppColors.primary)
                                    .frame(width: 3, height: 20)
                                Text(section.heading)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                            }

                            Text(section.body)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink)
                                .lineSpacing(6)

                            if let callout = section.callout {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(callout)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.ink)
                                        .lineSpacing(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(colors.primarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }

                    // Complete button
                    if !isCompleted {
                        Button {
                            onComplete()
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                LucideIcon(image: Lucide.circleCheck, size: 18)
                                Text("Mark as Complete")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.onAction)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: guide.gradient, startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
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

// MARK: - Quick Read Detail View

struct QuickReadDetailView: View {
    let quickRead: QuickRead
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(quickRead.iconWash)
                        .frame(width: 44, height: 44)
                        .overlay(
                            LucideIcon(image: quickRead.iconImage, size: 22)
                                .foregroundStyle(quickRead.iconColor)
                        )

                    Text(quickRead.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)

                    HStack(spacing: 8) {
                        LucideIcon(image: Lucide.clock, size: 12)
                            .foregroundStyle(AppColors.mist)
                        Text(quickRead.readTime + " read")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.mist)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [quickRead.iconWash, colors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(quickRead.content) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(quickRead.iconColor)
                                    .frame(width: 3, height: 20)
                                Text(section.heading)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                            }

                            Text(section.body)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.ink)
                                .lineSpacing(6)

                            if let callout = section.callout {
                                VStack(alignment: .leading) {
                                    Text(callout)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.ink)
                                        .lineSpacing(4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(colors.primarySurface)
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

// MARK: - Clean Icon Illustration

/// Minimal icon illustration — solid pastel background + single bold centered icon.
/// Matches Tiimo's clean card aesthetic.
private struct CardIllustration: View {
    let icon: UIImage
    let color: Color
    let wash: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            wash
            LucideIcon(image: icon, size: size * 0.35)
                .foregroundStyle(color.opacity(0.45))
        }
    }
}

// MARK: - Hashable conformance for navigation

extension GuideLesson: Hashable {
    static func == (lhs: GuideLesson, rhs: GuideLesson) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Previews

#Preview("Learning Center") {
    NavigationStack {
        LearningCenterView()
    }
}

#Preview("Article Detail") {
    if let article = allArticles.first {
        NavigationStack {
            ArticleDetailView(article: article)
        }
    }
}

#Preview("Guide Detail") {
    if let guide = allGuides.first {
        NavigationStack {
            GuideDetailView(guide: guide)
        }
    }
}
