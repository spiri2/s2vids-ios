//
//  AuthViewModel.swift
//  s2vids
//
//  Created by Michael Espiritu on 10/5/25.
//

import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
  @Published var email = ""
  @Published var password = ""
  @Published var isLoading = false
  @Published var errorMessage = ""
  @Published var info = ""
  @Published var attemptsLeft: Int? = nil
  @Published var lockRemaining: Int? = nil
  @Published var isSignedIn = false

  func onEmailChange(_ v: String) {
    email = v
    refreshState()
  }

  func refreshState() {
    attemptsLeft = LoginAttemptStore.shared.attemptsLeft(email)
    lockRemaining = LoginAttemptStore.shared.lockRemaining(email)
    if let rem = lockRemaining {
      errorMessage = "Too many attempts. Try again in \(formatCountdown(rem))."
    } else if errorMessage.hasPrefix("Too many attempts.") {
      errorMessage = ""
    }
  }

  func signIn() async {
    self.errorMessage = ""
    self.info = ""

    let em = email.trimmingCharacters(in: .whitespaces)
    guard !em.isEmpty, !password.isEmpty else {
      self.errorMessage = "Please enter both email and password."
      return
    }
    if let rem = LoginAttemptStore.shared.lockRemaining(em) {
      self.errorMessage = "Too many attempts. Try again in \(formatCountdown(rem))."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await SupabaseManager.shared.client.auth.signIn(email: em, password: password)
      LoginAttemptStore.shared.reset(em)
      attemptsLeft = nil
      lockRemaining = nil
      isSignedIn = true
    } catch {
      let rec = LoginAttemptStore.shared.registerFailure(for: em)
      if let until = rec.lockUntil {
        let rem = Int(ceil(until - Date().timeIntervalSince1970))
        self.errorMessage = "Too many attempts. Try again in \(formatCountdown(rem))."
      } else {
        let left = max(0, 3 - rec.count)
        self.errorMessage = "Sign-in failed. You have \(left) attempt\(left == 1 ? "" : "s") left."
      }
      refreshState()
    }
  }

  func forgotPassword(redirectTo: URL) async {
    self.errorMessage = ""
    self.info = ""

    let em = email.trimmingCharacters(in: .whitespaces)
    guard !em.isEmpty else {
      self.errorMessage = "Enter your email first, then tap “Forgot password?”."
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await SupabaseManager.shared.client.auth.resetPasswordForEmail(em, redirectTo: redirectTo)
      self.info = "Password reset email sent. Check your inbox."
    } catch {
      self.errorMessage = error.localizedDescription
    }
  }
}
