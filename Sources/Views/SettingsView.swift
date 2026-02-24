import SwiftUI
import PhotosUI

enum HourGoalType: String, CaseIterable, Codable {
    case reps = "REPS"
    case str = "STR (Short-Term Rental)"
    case both = "Both"
    
    var description: String {
        switch self {
        case .reps:
            return "750 hours - Full Real Estate Professional Status"
        case .str:
            return "100 hours - STR Material Participation"
        case .both:
            return "Track both REPS and STR goals"
        }
    }
    
    var hoursRequired: Double {
        switch self {
        case .reps:
            return 750
        case .str:
            return 100
        case .both:
            return 750 // Use higher as primary
        }
    }
}

struct PropertyGoal: Identifiable, Codable {
    var id: UUID
    var propertyId: UUID
    var goalType: HourGoalType
    
    init(id: UUID = UUID(), propertyId: UUID, goalType: HourGoalType = .both) {
        self.id = id
        self.propertyId = propertyId
        self.goalType = goalType
    }
}

class GoalManager: ObservableObject {
    static let shared = GoalManager()
    
    @Published var propertyGoals: [PropertyGoal] = []
    @Published var globalGoalType: HourGoalType = .reps
    
    private let goalsKey = "propertyGoals"
    private let globalGoalKey = "globalGoalType"
    
    private init() {
        loadGoals()
    }
    
    func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let goals = try? JSONDecoder().decode([PropertyGoal].self, from: data) {
            propertyGoals = goals
        }
        
        if let raw = UserDefaults.standard.string(forKey: globalGoalKey),
           let type = HourGoalType(rawValue: raw) {
            globalGoalType = type
        }
    }
    
    func saveGoals() {
        if let data = try? JSONEncoder().encode(propertyGoals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
        UserDefaults.standard.set(globalGoalType.rawValue, forKey: globalGoalKey)
    }
    
    func setGoal(for propertyId: UUID, type: HourGoalType) {
        if let index = propertyGoals.firstIndex(where: { $0.propertyId == propertyId }) {
            propertyGoals[index].goalType = type
        } else {
            propertyGoals.append(PropertyGoal(propertyId: propertyId, goalType: type))
        }
        saveGoals()
    }
    
    func getGoal(for propertyId: UUID) -> HourGoalType {
        propertyGoals.first(where: { $0.propertyId == propertyId })?.goalType ?? globalGoalType
    }
    
    func setGlobalGoal(_ type: HourGoalType) {
        globalGoalType = type
        saveGoals()
    }
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var iCloudSyncEnabled = false
    @State private var showingResetAlert = false
    @State private var showingProfileEdit = false
    @State private var showingPaywall = false
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Data?
    @State private var showingPropertyGoals = false
    
    var body: some View {
        NavigationStack {
            List {
                    // Membership Status
                Section {
                    Button {
                        showingPaywall = true
                    } label: {
                        VStack(spacing: 12) {
                            HStack {
                                LHIconView(icon: subscriptionManager.isPro && !subscriptionManager.isTrialActive ? .crown : .clock, size: 24, color: subscriptionManager.isPro && !subscriptionManager.isTrialActive ? AppColors.warning : AppColors.primary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subscriptionManager.isPro && !subscriptionManager.isTrialActive ? "Pro Member" : "Free Trial")
                                        .font(.headline)
                                    if subscriptionManager.isTrialActive {
                                        Text("\(subscriptionManager.trialDaysRemaining) days remaining")
                                            .font(.caption)
                                            .foregroundStyle(AppColors.warning)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Upgrade") {
                                    showingPaywall = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.warning)
                            }
                        }
                        .padding(.vertical, 8)
                        .foregroundStyle(colors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                
                Section("Profile") {
                    Button {
                        userName = appleSignIn.fullName ?? viewModel.userName
                        userEmail = appleSignIn.email ?? ""
                        profileImage = appleSignIn.profileImageData
                        showingProfileEdit = true
                    } label: {
                        HStack {
                            if let imageData = profileImage ?? appleSignIn.profileImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            } else {
                                LHCircleBadge(icon: .person, bgColor: AppColors.primary, fgColor: .white, size: 50)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                let displayName = appleSignIn.fullName ?? (viewModel.userName.isEmpty ? "Your Name" : viewModel.userName)
                                Text(displayName)
                                    .font(.headline)
                                    .foregroundStyle(colors.textPrimary)
                                if let email = appleSignIn.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            LHIconView(icon: .chevronRight, size: 14, color: .secondary, strokeStyle: true)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Goals & Settings") {
                    // Global Goal Type
                    Menu {
                        ForEach(HourGoalType.allCases, id: \.self) { type in
                            Button {
                                goalManager.setGlobalGoal(type)
                            } label: {
                                HStack {
                                    Text(type.rawValue)
                                    if goalManager.globalGoalType == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("Tax Goal", systemImage: "target")
                            Spacer()
                            Text(goalManager.globalGoalType.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Property-specific goals
                    NavigationLink {
                        PropertyGoalsView()
                    } label: {
                        HStack {
                            Label("Property Goals", systemImage: "house.fill")
                            Spacer()
                            Text("\(viewModel.properties.count) properties")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Label("Annual Hour Goal", systemImage: "clock.fill")
                        Spacer()
                        Text("\(Int(goalManager.globalGoalType.hoursRequired)) hours")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Working Time Rule", systemImage: "percent")
                        Spacer()
                        Text("50%")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Categories") {
                    ForEach(categoryManager.allCategories.prefix(5)) { category in
                        HStack {
                            DynamicIconView(name: category.iconName, size: 18, color: Color(hex: category.colorHex))
                                .frame(width: 24)
                            Text(category.name)
                                .font(.subheadline)
                                .foregroundStyle(colors.textPrimary)
                        }
                    }
                }
                
                Section("AI Features") {
                    HStack {
                        Label("Smart Entry", systemImage: "sparkles")
                        Spacer()
                        Text(subscriptionManager.isPro ? "Enabled" : "Pro Only")
                            .font(.caption)
                            .foregroundStyle(subscriptionManager.isPro ? AppColors.success : colors.textTertiary)
                    }
                    
                    HStack {
                        Label("Weekly Summary", systemImage: "chart.bar.doc.horizontal")
                        Spacer()
                        Text(subscriptionManager.isPro ? "Enabled" : "Pro Only")
                            .font(.caption)
                            .foregroundStyle(subscriptionManager.isPro ? AppColors.success : colors.textTertiary)
                    }
                }
                
                Section("Data") {
                    NavigationLink {
                        Text("Export Data")
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    
                    Section("iCloud") {
                        Toggle(isOn: $iCloudSyncEnabled) {
                            Label("iCloud Backup", systemImage: "icloud.fill")
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    NavigationLink {
                        Text("Contact Support")
                    } label: {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                    
                    Button(role: .destructive) {
                        viewModel.signOut()
                        AppleSignInManager.shared.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Settings")
            .alert("Reset All Data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "LandlordHours.properties")
                    UserDefaults.standard.removeObject(forKey: "LandlordHours.entries")
                }
            } message: {
                Text("This will delete all your properties, time entries, and settings.")
            }
            .sheet(isPresented: $showingProfileEdit) {
                ProfileEditView(userName: $userName, userEmail: $userEmail, profileImage: $profileImage)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(showPaywall: $showingPaywall)
            }
        }
    }
}

struct PropertyGoalsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var goalManager = GoalManager.shared
    
    var body: some View {
        List {
            Section {
                Picker("Default Goal", selection: $goalManager.globalGoalType) {
                    ForEach(HourGoalType.allCases, id: \.self) { type in
                        VStack(alignment: .leading) {
                            Text(type.rawValue)
                            Text(type.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(type)
                    }
                }
            } header: {
                Text("Global Setting")
            } footer: {
                Text("This will be the default goal for all properties unless overridden below.")
            }
            
            Section {
                if viewModel.properties.isEmpty {
                    Text("No properties yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.properties) { property in
                        PropertyGoalRow(property: property, goalManager: goalManager)
                    }
                }
            } header: {
                Text("Per-Property Goals")
            } footer: {
                Text("Override the goal for specific properties (e.g., STR properties for 100h goal).")
            }
        }
        .navigationTitle("Property Goals")
    }
}

struct PropertyGoalRow: View {
    let property: RentalProperty
    @ObservedObject var goalManager: GoalManager
    @State private var selectedGoal: HourGoalType = .both
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(property.name)
                    .font(.headline)
                Text(property.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Picker("Goal", selection: $selectedGoal) {
                Text("Default").tag(HourGoalType.both)
                Text("REPS (750h)").tag(HourGoalType.reps)
                Text("STR (100h)").tag(HourGoalType.str)
            }
            .pickerStyle(.menu)
            .onChange(of: selectedGoal) { _, newValue in
                goalManager.setGoal(for: property.id, type: newValue)
            }
        }
        .onAppear {
            selectedGoal = goalManager.getGoal(for: property.id)
        }
    }
}

struct ProfileEditView: View {
    @Binding var userName: String
    @Binding var userEmail: String
    @Binding var profileImage: Data?
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Photo") {
                    HStack {
                        Spacer()
                        if let imageData = profileImage ?? appleSignIn.profileImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            LHCircleBadge(icon: .person, bgColor: AppColors.primary, fgColor: .white, size: 100)
                        }
                        Spacer()
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text("Change Photo")
                            .font(.subheadline)
                    }
                    .onChange(of: selectedPhotoItem) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                profileImage = data
                            }
                        }
                    }
                }
                
                Section("Name") {
                    TextField("Your name", text: $userName)
                }
                
                Section("Email") {
                    TextField("your@email.com", text: $userEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        AppleSignInManager.shared.updateProfile(
                            name: userName.isEmpty ? nil : userName,
                            email: userEmail.isEmpty ? nil : userEmail,
                            imageData: profileImage
                        )
                        dismiss()
                    }
                }
            }
        }
    
}
}

#Preview {
    SettingsView()
        .environmentObject(AppViewModel())
}
