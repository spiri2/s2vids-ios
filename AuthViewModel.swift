//
//  AuthViewModel.swift
//  s2vids
//

import Foundation
import Supabase
import Security

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

  // Email confirmation
  @Published var needsEmailConfirmation: Bool = false
  @Published var resendStatus: String = ""

  // Remember me
  @Published var rememberMe: Bool = UserDefaults.standard.bool(forKey: "S2RememberMe") {
    didSet { UserDefaults.standard.set(rememberMe, forKey: "S2RememberMe") }
  }

  // MARK: - Public API

  func onEmailChange(_ value: String) {
    email = value.trimmingCharacters(in: .whitespacesAndNewlines)
    errorMessage = ""
    info = ""
    needsEmailConfirmation = false
    resendStatus = ""
  }

  /// Standard sign-in from the form.
  func signIn() async {
    await signIn(withEmail: email, password: password, silently: false)
  }

  /// Auto-restore on app launch if Remember Me is enabled (no session juggling).
  func restoreSession() async {
    guard rememberMe, let creds = KeychainAuthStorage.load() else { return }
    // Pre-fill for UI continuity
    if email.isEmpty { email = creds.email }
    if password.isEmpty { password = creds.password }
    await signIn(withEmail: creds.email, password: creds.password, silently: true)
  }

  func signOut() async {
    isLoading = true
    defer { isLoading = false }
    do {
      try await SupabaseManager.shared.client.auth.signOut()
    } catch {
      // We still clear local state even if network signout fails
    }
    KeychainAuthStorage.clear()
    password = ""
    isSignedIn = false
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

  // MARK: - Private

  private func signIn(withEmail emRaw: String, password pw: String, silently: Bool) async {
    errorMessage = silently ? "" : ""
    info = ""
    needsEmailConfirmation = false
    resendStatus = ""

    let em = emRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !em.isEmpty, !pw.isEmpty else {
      if !silently { errorMessage = "Email and password are required." }
      return
    }

    isLoading = !silently
    defer { isLoading = false }

    do {
      // Supabase sign-in with email+password
      _ = try await SupabaseManager.shared.client.auth.signIn(email: em, password: pw)

      // Persist creds only if Remember Me is ON
      if rememberMe {
        KeychainAuthStorage.save(email: em, password: pw)
      } else {
        KeychainAuthStorage.clear()
      }

      // Update UI state
      email = em
      isSignedIn = true

    } catch {
      let msg = (error as NSError).localizedDescription.lowercased()

      if msg.contains("email not confirmed") ||
         msg.contains("email needs to be confirmed") ||
         msg.contains("user is not confirmed") ||
         msg.contains("not confirmed") {
        needsEmailConfirmation = true
        if !silently { errorMessage = "Email not confirmed. Please confirm your email first." }
      } else if msg.contains("invalid login credentials") ||
                msg.contains("invalid login") ||
                msg.contains("invalid email or password") {
        if !silently { errorMessage = "Invalid email or password." }
      } else if !silently {
        errorMessage = error.localizedDescription
      }
    }
  }
}

// MARK: - Simple Keychain wrapper for Remember Me

private enum KeychainAuthStorage {
  struct Creds: Codable { let email: String; let password: String }

  private static let service = "org.s2vids.remember"
  private static let account = "primary"
  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()

  static func save(email: String, password: String) {
    let creds = Creds(email: email, password: password)
    guard let data = try? encoder.encode(creds) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attrs: [String: Any] = [
      kSecValueData as String: data
    ]

    // Update if exists, else add
    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      SecItemAdd(addQuery as CFDictionary, nil)
    }
  }

  static func load() -> Creds? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return try? decoder.decode(Creds.self, from: data)
  }

  static func clear() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }
}
