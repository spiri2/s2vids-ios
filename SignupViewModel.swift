//
//  SignupViewModel.swift
//  s2vids
//

import Foundation

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
    // Reset UI
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
      // Build the URL to your Next.js signup endpoint
      let url = AppConfig.apiBase.appendingPathComponent("api/signup")

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body: [String: String] = [
        "email": em,
        "password": password,
        "inviteCode": code
      ]
      request.httpBody = try JSONEncoder().encode(body)

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      if httpResponse.statusCode == 200 {
        // ✅ Show confirmation button after success
        successMessage = "✅ Signup successful! Please send a confirmation email."
        showSendConfirmation = true
        showResend = false
      } else {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        errorMessage = json?["error"] as? String ?? "Signup failed. Try again."
      }
    } catch {
      errorMessage = "Failed to connect: \(error.localizedDescription)"
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
      let url = AppConfig.apiBase.appendingPathComponent("api/resend-confirmation")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let body = ["email": em]
      request.httpBody = try JSONEncoder().encode(body)

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }

      if httpResponse.statusCode == 200 {
        resendStatus = "Confirmation email sent! Check your inbox."
        showSendConfirmation = false
        showResend = true
      } else {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        resendStatus = json?["error"] as? String ?? "Failed to send confirmation email."
      }
    } catch {
      resendStatus = "Failed: \(error.localizedDescription)"
    }
  }
}
