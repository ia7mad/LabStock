import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isRegistering {
                        TextField("Display name", text: $displayName)
                            .textContentType(.name).textInputAutocapitalization(.words)
                    }
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        .textContentType(.emailAddress).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(isRegistering ? .newPassword : .password)
                }
                if let message { Section { Text(message).foregroundStyle(.secondary) } }
                Section {
                    Button(isRegistering ? "Create Account" : "Sign In") { authenticate() }
                        .disabled(email.nilIfBlank == nil || password.count < 6 || isWorking)
                    Button(isRegistering ? "Already have an account? Sign In" : "Need an account? Register") {
                        isRegistering.toggle(); message = nil
                    }
                }
            }
            .navigationTitle("LabStock")
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
        }
    }

    private func authenticate() {
        isWorking = true; message = nil
        Task {
            do {
                if isRegistering {
                    let signedIn = try await store.signUp(email: email, password: password, displayName: displayName)
                    if !signedIn { message = "Check your email to confirm the account, then sign in." }
                } else {
                    try await store.signIn(email: email, password: password)
                }
            } catch { message = error.localizedDescription }
            isWorking = false
        }
    }
}
