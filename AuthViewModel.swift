//
//  AuthViewModel.swift
//  s2vids
//

import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
  // Inputs
  @Published var email: String = ""
  @Published var password: String = ""

  // UI state
  @Published var isLoading: Bool = false
  @Published var errorMessage: String = ""
  @Published var info: String = ""
  @Published var isSignedIn: Bool = false

  // Lockout / attempts (optional – keep if you used it)
  @Published var lockRemaining: TimeInterval?
  @Published var attemptsLeft: Int?

  // Show resend CTA if we detect the account isn’t confirmed
  @Published var needsEmailConfirmation: Bool = false
  @Published var resendStatus: String = ""

  func onEmailChange(_ value: String) {
    email = value.trimmingCharacters(in: .whitespacesAndNewlines)
    errorMessage = ""
    info = ""
    needsEmailConfirmation = false
    resendStatus = ""
  }

  func signIn() async {
    errorMessage = ""
    info = ""
    needsEmailConfirmation = false
    resendStatus = ""

    let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let pw = password

    guard !em.isEmpty, !pw.isEmpty else {
      errorMessage = "Email and password are required."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      // Supabase sign-in with email+password
      let _ = try await SupabaseManager.shared.client.auth.signIn(email: em, password: pw)

      // If we get here without throwing, user is signed in.
      isSignedIn = true

    } catch {
      // Common Supabase error reasons we want to map:
      // - Email not confirmed
      // - Invalid login credentials
      // - Rate limits/OTP, etc.

      let msg = (error as NSError).localizedDescription.lowercased()

      if msg.contains("email not confirmed") ||
         msg.contains("email needs to be confirmed") ||
         msg.contains("user is not confirmed") ||
         msg.contains("not confirmed") {

        needsEmailConfirmation = true
        errorMessage = "Email not confirmed. Please confirm your email first."

      } else if msg.contains("invalid login credentials") ||
                msg.contains("invalid login") ||
                msg.contains("invalid email or password") {
        errorMessage = "Invalid email or password."
      } else {
        errorMessage = error.localizedDescription
      }
    }
  }

  func forgotPassword(redirectTo: URL) async {
    errorMessage = ""
    info = ""
    needsEmailConfirmation = false
    resendStatus = ""

    let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !em.isEmpty else {
      errorMessage = "Enter your email to reset your password."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await SupabaseManager.shared.client.auth.resetPasswordForEmail(em, redirectTo: redirectTo)
      info = "Password reset link sent if the email exists."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Call your Next.js `/api/resend-confirmation` to resend the signup email.
  func resendConfirmation() async {
    resendStatus = ""
    let em = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !em.isEmpty else {
      resendStatus = "Enter your email above to resend."
      return
    }
    resendStatus = "Sending…"

    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/resend-confirmation"))
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["email": em], options: [])

      let (data, resp) = try await URLSession.shared.data(for: req)
      let ok = (resp as? HTTPURLResponse)?.statusCode == 200
      if ok {
        resendStatus = "Confirmation email sent! Check your inbox."
      } else {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        resendStatus = json?["error"] as? String ?? "Failed to send confirmation."
      }
    } catch {
      resendStatus = "Failed: \(error.localizedDescription)"
    }
  }
}
