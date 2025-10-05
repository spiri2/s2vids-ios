//
//  SignupViewModel.swift
//  s2vids
//

import Foundation
import Supabase

@MainActor
final class SignupViewModel: ObservableObject {
  @Published var email = ""
  @Published var password = ""
  @Published var confirmPassword = ""
  @Published var inviteCode = ""
  @Published var isLoading = false

  @Published var errorMessage = ""
  @Published var successMessage = ""
  @Published var resendStatus = ""
  @Published var showSendConfirmation = false
  @Published var showResend = false

  func signUp() async {
    // reset UI
    errorMessage = ""; successMessage = ""; resendStatus = ""
    showSendConfirmation = false; showResend = false

    let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !em.isEmpty, !password.isEmpty, !code.isEmpty else {
      errorMessage = "Email, password, and invite code are required."
      return
    }
    guard password == confirmPassword else {
      errorMessage = "Passwords do not match."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      // NOTE: `data:` expects [String: JSON]
      try await SupabaseManager.shared.client.auth.signUp(
        email: em,
        password: password,
        data: ["invite_code": .string(code)]
      )
      successMessage = "✅ Signup successful! Please send a confirmation email."
      showSendConfirmation = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func sendOrResendConfirmation() async {
    let em = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !em.isEmpty else {
      resendStatus = "Enter your email above to send confirmation."
      return
    }
    resendStatus = "Sending confirmation email…"

    do {
      // Correct order: email first, then type
      try await SupabaseManager.shared.client.auth.resend(
        email: em,
        type: .signup
      )
      resendStatus = "Confirmation email sent! Check your inbox."
      showSendConfirmation = false
      showResend = true
    } catch {
      resendStatus = "Failed to send confirmation email: \(error.localizedDescription)"
    }
  }
}
