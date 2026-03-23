import AppKit
import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) private var appState

    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedProvider: AIProvider = .anthropic
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var apiKeyMessage: String?
    @State private var apiKeySaveSucceeded = false
    @State private var didAutoAdvanceAccessibility = false
    @State private var animateStepContent = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case accessibility
        case aiSetup
        case ready
    }

    var body: some View {
        ZStack {
            onboardingBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                ZStack {
                    switch currentStep {
                    case .welcome:
                        stepContainer(icon: "clock.fill", iconColor: .blue, title: "Welcome to TimeSink", bodyText: "Understand where your time goes. TimeSink quietly tracks what you work on and uses AI to categorize your day.") {
                            featureStrip
                        }
                    case .accessibility:
                        stepContainer(icon: appState.isAccessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill", iconColor: appState.isAccessibilityGranted ? .green : .orange, title: "Accessibility Access", bodyText: "TimeSink reads window titles to know what app, page, or terminal you are focused on. macOS needs you to allow this once.") {
                            accessibilityContent
                        }
                    case .aiSetup:
                        stepContainer(icon: selectedProvider.iconName, iconColor: Color(hex: selectedProvider.providerAccentHex), title: "Connect to AI", bodyText: "Choose your preferred provider for activity categorization. Keys are stored securely in the macOS Keychain.") {
                            aiSetupContent
                        }
                    case .ready:
                        stepContainer(icon: "checkmark.circle.fill", iconColor: .green, title: "You're ready", bodyText: "TimeSink is set up and ready to help you understand where your day goes.") {
                            readyContent
                        }
                    }
                }
                .frame(maxWidth: 640)
                .transition(stepTransition)

                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    StepDots(currentStep: currentStep)

                    HStack {
                        if currentStep != .welcome {
                            Button("Back") {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    currentStep = OnboardingStep(rawValue: max(0, currentStep.rawValue - 1)) ?? .welcome
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if currentStep == .accessibility || currentStep == .aiSetup {
                            Button("Skip for now") {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    advanceStep(force: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                        }

                        Spacer()

                        Button(primaryButtonTitle) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                primaryAction()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(primaryButtonDisabled)
                    }
                    .frame(maxWidth: 640)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
            .padding(.top, 12)
        }
        .onAppear {
            selectedProvider = appState.selectedAIProvider
            apiKey = KeychainHelper.apiKey(for: selectedProvider) ?? ""
            triggerStepEntranceAnimation()
        }
        .onChange(of: selectedProvider) { _, newValue in
            appState.setSelectedAIProvider(newValue)
            apiKey = KeychainHelper.apiKey(for: newValue) ?? ""
            apiKeyMessage = nil
        }
        .onChange(of: currentStep) { _, _ in
            triggerStepEntranceAnimation()
        }
        .onChange(of: appState.isAccessibilityGranted) { _, granted in
            guard currentStep == .accessibility, granted, !didAutoAdvanceAccessibility else { return }
            didAutoAdvanceAccessibility = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeInOut(duration: 0.22)) {
                    advanceStep(force: true)
                }
            }
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    stepAccentColor.opacity(0.10),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    stepAccentColor.opacity(0.06),
                    Color.clear,
                ],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
        }
    }

    private var featureStrip: some View {
        HStack(spacing: 14) {
            OnboardingFeatureCard(icon: "clock", title: "Track", text: "Apps, tabs, and terminals automatically")
            OnboardingFeatureCard(icon: "brain", title: "Categorize", text: "AI sorts your time into useful buckets")
            OnboardingFeatureCard(icon: "chart.bar", title: "Reflect", text: "Breakdowns show where your day went")
        }
    }

    private var accessibilityContent: some View {
        VStack(spacing: 14) {
            if appState.isAccessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings") {
                    AccessibilityHelper.requestAccessibility()
                    AccessibilityHelper.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Once you enable TimeSink in Accessibility settings, this step will continue automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
    }

    private var aiSetupContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    ProviderCard(provider: provider, isSelected: provider == selectedProvider)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedProvider = provider
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if showAPIKey {
                        TextField(selectedProvider.placeholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(selectedProvider.placeholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(showAPIKey ? "Hide" : "Show") {
                        showAPIKey.toggle()
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        saveAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let apiKeyMessage {
                    Label(apiKeyMessage, systemImage: apiKeySaveSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(apiKeySaveSucceeded ? .green : .red)
                } else if KeychainHelper.exists(key: selectedProvider.keychainKey) {
                    Label("\(selectedProvider.displayName) key is saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Get a key from \(selectedProvider.displayName)") {
                    NSWorkspace.shared.open(selectedProvider.consoleURL)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: selectedProvider.providerAccentHex))
                .font(.caption)
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStatusRow(label: "Activity tracking", value: appState.isAccessibilityGranted ? "Active" : "Needs accessibility", isPositive: appState.isAccessibilityGranted)
            OnboardingStatusRow(label: "AI categorization", value: KeychainHelper.exists(key: appState.selectedAIProvider.keychainKey) ? appState.selectedAIProvider.displayName : "Not configured", isPositive: KeychainHelper.exists(key: appState.selectedAIProvider.keychainKey))
            OnboardingStatusRow(label: "Menu bar quick view", value: "Always on", isPositive: true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepContainer<Content: View>(icon: String, iconColor: Color, title: String, bodyText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(iconColor)
                .scaleEffect(animateStepContent ? 1 : 0.92)
                .opacity(animateStepContent ? 1 : 0.7)

            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .offset(y: animateStepContent ? 0 : 8)
                    .opacity(animateStepContent ? 1 : 0)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
                    .offset(y: animateStepContent ? 0 : 10)
                    .opacity(animateStepContent ? 1 : 0)
            }

            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(
            LinearGradient(
                colors: [
                    stepAccentColor.opacity(0.085),
                    Color.primary.opacity(0.02),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(stepAccentColor.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.025), radius: 16, y: 6)
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .welcome: return "Get Started"
        case .accessibility: return appState.isAccessibilityGranted ? "Continue" : "Continue"
        case .aiSetup: return "Continue"
        case .ready: return "Open TimeSink"
        }
    }

    private var primaryButtonDisabled: Bool {
        false
    }

    private func primaryAction() {
        switch currentStep {
        case .welcome:
            currentStep = .accessibility
        case .accessibility:
            advanceStep(force: true)
        case .aiSetup:
            advanceStep(force: true)
        case .ready:
            appState.completeOnboarding()
        }
    }

    private func advanceStep(force: Bool) {
        let nextRaw = min(currentStep.rawValue + 1, OnboardingStep.ready.rawValue)
        currentStep = OnboardingStep(rawValue: nextRaw) ?? .ready
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var stepAccentColor: Color {
        switch currentStep {
        case .welcome:
            return .blue
        case .accessibility:
            return appState.isAccessibilityGranted ? .green : .orange
        case .aiSetup:
            return Color(hex: selectedProvider.providerAccentHex)
        case .ready:
            return .green
        }
    }

    private func triggerStepEntranceAnimation() {
        animateStepContent = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                animateStepContent = true
            }
        }
    }

    private func saveAPIKey() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainHelper.setAPIKey(trimmed.isEmpty ? nil : trimmed, for: selectedProvider)
            let savedValue = try? KeychainHelper.loadRequired(key: selectedProvider.keychainKey)
            apiKeySaveSucceeded = savedValue == trimmed || trimmed.isEmpty
            apiKeyMessage = trimmed.isEmpty ? "API key removed" : "\(selectedProvider.displayName) key saved"
        } catch {
            apiKeySaveSucceeded = false
            apiKeyMessage = error.localizedDescription
        }
    }
}

private struct StepDots: View {
    let currentStep: PermissionsView.OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PermissionsView.OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: step == currentStep ? 9 : 7, height: step == currentStep ? 9 : 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentStep)
    }
}

private struct OnboardingFeatureCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: provider.iconName)
                .font(.headline)
                .foregroundStyle(Color(hex: provider.providerAccentHex))

            Text(provider.displayName)
                .font(.headline)
                .fontWeight(.semibold)

            Text(provider.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(isSelected ? 0.07 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color(hex: provider.providerAccentHex) : Color.primary.opacity(0.07), lineWidth: isSelected ? 2 : 1)
        }
    }
}

private struct OnboardingStatusRow: View {
    let label: String
    let value: String
    let isPositive: Bool

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(isPositive ? .primary : .secondary)
            Circle()
                .fill(isPositive ? .green : .orange)
                .frame(width: 8, height: 8)
        }
        .font(.subheadline)
    }
}
