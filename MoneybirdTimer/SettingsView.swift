import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: TimerViewModel

    @State private var apiToken: String = ""
    @State private var administrationId: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API-token", text: $apiToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiToken) { _ in validationError = nil }

                    TextField("Administratie-ID", text: $administrationId)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .onChange(of: administrationId) { _ in validationError = nil }
                } header: {
                    Text("Moneybird-gegevens")
                } footer: {
                    Text(
                        "Het API-token vind je in Moneybird onder Instellingen \u{2192} API. " +
                        "Het administratie-ID staat in de URL: moneybird.com/{administratie-id}/\u{2026}"
                    )
                }

                if let error = validationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button(action: { Task { await validateAndSave() } }) {
                        HStack {
                            Spacer()
                            if isValidating {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Valideren\u{2026}")
                            } else {
                                Text("Opslaan")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSave || isValidating)
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sluiten") { dismiss() }
                        .disabled(isValidating)
                }
            }
            .overlay(alignment: .bottom) {
                if showConfirmation {
                    Label("Gegevens geverifieerd en opgeslagen", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.green, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.medium))
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showConfirmation)
            .animation(.easeInOut(duration: 0.2), value: validationError)
            .onAppear(perform: loadStoredValues)
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !apiToken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !administrationId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadStoredValues() {
        apiToken = KeychainHelper.load(for: .apiToken) ?? ""
        administrationId = KeychainHelper.load(for: .administrationId) ?? ""
    }

    private func validateAndSave() async {
        let token = apiToken.trimmingCharacters(in: .whitespaces)
        let adminId = administrationId.trimmingCharacters(in: .whitespaces)

        isValidating = true
        validationError = nil

        do {
            try await MoneybirdAPI.shared.validateCredentials(token: token, administrationId: adminId)
        } catch let error as APIError {
            isValidating = false
            validationError = error.errorDescription
            return
        } catch {
            isValidating = false
            validationError = error.localizedDescription
            return
        }

        KeychainHelper.save(token, for: .apiToken)
        KeychainHelper.save(adminId, for: .administrationId)
        isValidating = false

        withAnimation { showConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showConfirmation = false }
            dismiss()
        }
    }
}
