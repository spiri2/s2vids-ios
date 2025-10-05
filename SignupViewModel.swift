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
    errorMessage = ""
    successMessage = ""
    resendStatus = ""
    showSendConfirmation = false
    showResend = false

    let em = email.trimmingCharacters(in: .whitespaces)
    let pass = password
    let confirm = confirmPassword
    let code = inviteCode.trimmingCharacters(in: .whitespaces)

    guard !em.isEmpty, !pass.isEmpty, !code.isEmpty else {
      errorMessage = "Email, password, and invite code are required."
      return
    }
    guard pass == confirm else {
      errorMessage = "Passwords do not match."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      // Optionally: validate invite code via RPC or Edge Function before sign up.
      // try await SupabaseManager.shared.client.functions.invoke("validate_invite", arguments: ["code": code])

      // Attach the invite code as user metadata so your backend can verify on sign-in.
      try await SupabaseManager.shared.client.auth.signUp(
        email: em,
        password: pass,
        data: ["invite_code": code]   // stored as user_metadata
      )

      // If your project has email confirmations enabled, the SDK sends it automatically.
      successMessage = "✅ Signup successful! Please send a confirmation email."
      showSendConfirmation = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func sendOrResendConfirmation() async {
    resendStatus = ""
    let em = email.trimmingCharacters(in: .whitespaces)

    guard !em.isEmpty else {
      resendStatus = "Enter your email above to send confirmation."
      return
    }

    resendStatus = "Sending confirmation email…"
    do {
      // Supabase will re-send the signup confirmation email
      try await SupabaseManager.shared.client.auth.resend(
        type: .signup,
        email: em
      )
      resendStatus = "Confirmation email sent! Check your inbox."
      showSendConfirmation = false
      showResend = true
    } catch {
      resendStatus = "Failed to send confirmation email: \(error.localizedDescription)"
    }
  }
}
