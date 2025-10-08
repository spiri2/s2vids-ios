//
//  SettingsView.swift
//  s2vids
//
//  NOTE:
//  - Expects you already have `AppConfig` with `static let apiBase: URL`
//    and a `UserMenuButton` component in your project.
//  - This file contains ONLY `SettingsView` and its local helpers.
//  - Account password change now mirrors web admin reset:
//    POST /api/reset-password { email, newPassword }.
//

import SwiftUI

// MARK: - DTOs (match the web)

private struct Invite: Identifiable, Hashable, Decodable {
  var id: String { code }
  let code: String
  let issued_to: String
  let max_uses: Int
  let uses: Int
  let created_at: String
  let expires_at: String?
}

private struct JellyfinExistsResponse: Decodable {
  let exists: Bool?
  let error: String?
}

private struct StripeStatusResponse: Decodable {
  let status: String?
  let active: Bool?
  let cancel_at_period_end: Bool?
  let current_period_end: Int?
  let trial_end: Int?
}

private struct SessionResponse: Decodable {
  struct User: Decodable { let id: String?; let email: String?; let created_at: String?; let user_metadata: Meta? }
  struct Meta: Decodable { let discord: String? }
  let user: User?
}

private struct GenericOK: Decodable { let ok: Bool?; let message: String?; let status: String? }
private struct GenericErr: Decodable { let error: String? }

// MARK: - iOS 15 sheet detents compat

private struct DetentsCompatMedium: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) { content.presentationDetents([.medium]) } else { content }
  }
}

// MARK: - Settings View

struct SettingsView: View {
  // Presented from parent
  let email: String
  let isAdmin: Bool

  // General
  @Environment(\.dismiss) private var dismiss
  private let inviteLimit = 5

  // App version (shown in System panel)
  private let appVersionDisplay = "1.0.1"

  // State (web parity)
  @State private var userId: String = ""          // from /api/get-session
  @State private var createdAt: String = ""
  @State private var newEmail: String = ""
  @State private var currentPassword: String = ""
  @State private var newPassword: String = ""
  @State private var discordUsername: String = ""
  @State private var updatedDiscord: String = ""

  @State private var confirmation: String = ""
  @State private var invites: [Invite] = []
  @State private var copiedCode: String = ""
  @State private var inviteNotice: String = ""
  @State private var invitesAvailable: Int = 5

  @State private var showDeleteModal = false
  @State private var deletingAccount = false
  @State private var deleteError: String = ""

  // Stripe / Jellyfin
  @State private var subscriptionStatus: String = ""
  @State private var currentPeriodEnd: Int = 0
  @State private var cancelAtPeriodEnd: Bool = false

  @State private var jfUsername: String = "N/A"
  @State private var jfLoading = false
  @State private var jfError = ""
  @State private var jfSuccess = ""

  // Jellyfin password modal
  @State private var showJFPassModal = false
  @State private var jfNewPass = ""
  @State private var jfConfirmPass = ""
  @State private var jfSubmitting = false
  @State private var jfPassError = ""
  @State private var jfIsReset = false   // ← create vs reset intent

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(spacing: 16) {
          header

          greetingStripe

          VStack(spacing: 16) {
            jellyfinPanelView()
            discordPanelView()
            invitePanelView()
            accountPanelView()
            systemPanelView() // NEW: App Version panel at bottom
          }

          if !confirmation.isEmpty {
            Text(confirmation)
              .font(.subheadline)
              .foregroundColor(Color(red: 0.67, green: 0.93, blue: 0.80))
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.top, 6)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 36)
      }
      .refreshable { await refreshSettings() } // Pull to refresh
    }
    .preferredColorScheme(.dark)
    .task { await bootstrap() }
    .overlay { deleteAccountOverlay() }

    // Jellyfin password modal
    .sheet(isPresented: $showJFPassModal) {
      NavigationView {
        VStack(spacing: 14) {
          SecureField("Enter New Password", text: $jfNewPass)
            .textContentType(.newPassword)
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
            .foregroundColor(.white)

          SecureField("Confirm New Password", text: $jfConfirmPass)
            .textContentType(.newPassword)
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
            .foregroundColor(.white)

          if !jfPassError.isEmpty {
            Text(jfPassError)
              .font(.footnote).foregroundColor(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Button(jfSubmitting ? "Updating…" : (jfIsReset ? "Update Password" : "Create"))
          { Task { await submitJellyfinPassword() } }
            .disabled(jfSubmitting)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)

          Spacer()
        }
        .padding()
        .navigationTitle(jfIsReset ? "Reset Jellyfin Password" : "Set Jellyfin Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { showJFPassModal = false } } }
      }
      .modifier(DetentsCompatMedium()) // iOS 15-safe
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      Text("Settings")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)
      Spacer()
      UserMenuButton(
        email: email,
        isAdmin: isAdmin,
        onRequireAccess: { },
        onLogout: { NotificationCenter.default.post(name: Notification.Name("S2VidsDidLogout"), object: nil) },
        onOpenSettings: { /* already here */ },
        onOpenMovies: { dismiss(); NotificationCenter.default.post(name: Notification.Name("S2OpenMovies"), object: nil) },
        onOpenDiscover: { dismiss(); NotificationCenter.default.post(name: Notification.Name("S2OpenDiscover"), object: nil) },
        onOpenTvShows: { dismiss(); NotificationCenter.default.post(name: Notification.Name("S2OpenTvShows"), object: nil) },
        onOpenAdmin: { dismiss(); NotificationCenter.default.post(name: Notification.Name("S2OpenAdmin"), object: nil) }
      )
    }
    .zIndex(10_000)
  }

  private var greetingStripe: some View {
    HStack {
      Text("Signed in as ").foregroundColor(.white.opacity(0.8)).font(.subheadline)
      Text(email.isEmpty ? "—" : email).foregroundColor(.white).font(.system(size: 15, weight: .bold))
      Spacer()
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(red: 0.06, green: 0.09, blue: 0.16))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.2)))
    )
  }

  // MARK: Sections

  private func sectionContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) { content() }
      .padding(14)
      .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.06, green: 0.09, blue: 0.16)))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.25)))
  }

  // Jellyfin / Stripe
  private func jellyfinPanelView() -> some View {
    sectionContainer {
      Text("Jellyfin Access").font(.system(size: 17, weight: .bold)).foregroundColor(.white)

      labeledRow("Username") { Text(jfUsername).foregroundColor(.white) }

      if subscriptionStatus == "active" {
        labeledRow("Renews On") { Text(renewalText().isEmpty ? "—" : renewalText()).foregroundColor(.white) }
      }

      WrapHStack(spacing: 10) {
        if !jfExists() && canGenerateJF() {
          primaryButton("Create Account") {
            jfPassError = ""; jfNewPass = ""; jfConfirmPass = ""
            jfIsReset = false
            showJFPassModal = true
          }
        }
        if jfExists() && canGenerateJF() {
          primaryButton("Change Password") {
            jfPassError = ""; jfNewPass = ""; jfConfirmPass = ""
            jfIsReset = true
            showJFPassModal = true
          }
        }
        if subscriptionStatus == "active" && !cancelAtPeriodEnd {
          destructiveButton("Cancel Subscription") { await cancelSubscription() }
        }
        if (cancelAtPeriodEnd || subscriptionStatus == "canceled") && notExpired() {
          primaryButton("Restore Subscription") { await restoreSubscription() }
        }
      }

      if cancelAtPeriodEnd && notExpired() {
        Text("Your subscription will end at the period’s renewal unless restored.")
          .font(.caption)
          .padding(8)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.15)))
      }

      if !jfSuccess.isEmpty { Text(jfSuccess).font(.footnote).foregroundColor(.green) }
      if !jfError.isEmpty { Text(jfError).font(.footnote).foregroundColor(.red) }
    }
  }

  // Discord
  private func discordPanelView() -> some View {
    sectionContainer {
      HStack(spacing: 8) { Image(systemName: "person.crop.circle.badge.checkmark"); Text("Discord") }
        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)

      Text("Discord Username")
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))

      HStack(spacing: 8) {
        TextField("@YourDiscordName", text: $updatedDiscord)
          .textInputAutocapitalization(.never).disableAutocorrection(true)
          .padding(.horizontal, 10).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
          .foregroundColor(.white)

        primaryButton("Update") { await updateDiscord() }
      }

      Text("Linked: \(discordUsername.isEmpty ? "Not linked" : discordUsername)")
        .font(.subheadline).foregroundColor(.white.opacity(0.85))
    }
  }

  // Invites
  private func invitePanelView() -> some View {
    sectionContainer {
      HStack {
        Text("Invite Codes").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
        Spacer()
        Text("\(invitesAvailable) left this month").font(.system(size: 12, weight: .bold))
          .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))
      }

      HStack(spacing: 8) {
        primaryButton("Generate Invite") { await generateInvite() }
          .disabled(invitesAvailable == 0 && !isFirstOfMonth())
          .opacity((invitesAvailable == 0 && !isFirstOfMonth()) ? 0.5 : 1.0)

        if !inviteNotice.isEmpty {
          Text(inviteNotice).font(.caption).foregroundColor(.yellow)
        }
      }

      if !confirmation.isEmpty { Text(confirmation).font(.footnote).foregroundColor(.green) }

      if invites.isEmpty {
        Text("No invites generated yet.").foregroundColor(.white.opacity(0.75)).font(.subheadline)
      } else {
        VStack(spacing: 8) {
          ForEach(invites) { inv in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(inv.code).font(.system(.body, design: .monospaced)).foregroundColor(.white)
                Text("(Uses: \(inv.uses)/\(inv.max_uses))").font(.caption).foregroundColor(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 6) {
                Text("Expires: \(formatExpiration(inv.expires_at))").font(.caption).foregroundColor(.secondary)
                Button {
                  UIPasteboard.general.string = inv.code
                  copiedCode = inv.code
                  DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copiedCode = "" }
                } label: { HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text(copiedCode == inv.code ? "Copied!" : "Copy") } }
                .buttonStyle(SecondaryButtonStyle())
              }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.05, green: 0.07, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
          }
        }
      }
    }
  }

  // Account
  private func accountPanelView() -> some View {
    sectionContainer {
      Text("Account").font(.system(size: 17, weight: .bold)).foregroundColor(.white)

      labeledRow("Account Created") { Text(createdAt.isEmpty ? "—" : createdAt).foregroundColor(.white) }

      // Email
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) { Image(systemName: "envelope.fill"); Text("Email") }
          .font(.system(size: 15, weight: .bold)).foregroundColor(.white)

        Text("Current: \(email)").font(.footnote).foregroundColor(.secondary)

        HStack(spacing: 8) {
          TextField("new@example.com", text: $newEmail)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
            .foregroundColor(.white)
          primaryButton("Update") { await updateEmail() }
        }
      }

      // Password
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) { Image(systemName: "lock.fill"); Text("Change Password") }
          .font(.system(size: 15, weight: .bold)).foregroundColor(.white)

        SecureField("Current Password", text: $currentPassword)
          .padding(.horizontal, 10).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
          .foregroundColor(.white)

        SecureField("New Password", text: $newPassword)
          .padding(.horizontal, 10).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
          .foregroundColor(.white)

        primaryButton("Update") { await changeAccountPassword() }
      }

      Divider().background(Color.gray.opacity(0.25))

      destructiveButton("Delete Account") { showDeleteModal = true }
      Text("Permanently delete your account. This cannot be undone.").font(.caption).foregroundColor(.secondary)
    }
  }

  // System (App Version)
  private func systemPanelView() -> some View {
    sectionContainer {
      Text("System").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
      labeledRow("App Version") { Text(appVersionDisplay).foregroundColor(.white) }
    }
  }

  // MARK: Overlay (delete)

  private func deleteAccountOverlay() -> some View {
    Group {
      if showDeleteModal {
        ZStack {
          Color.black.opacity(0.6).ignoresSafeArea()
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow); Text("Delete Account").font(.system(size: 17, weight: .bold)) }
            Text("This will permanently delete your account and sign you out. This action cannot be undone.").font(.subheadline)

            if !deleteError.isEmpty { Text(deleteError).font(.footnote).foregroundColor(.red) }

            HStack(spacing: 8) {
              destructiveButton(deletingAccount ? "Deleting…" : "Delete") { await requestAccountDeletion() }.disabled(deletingAccount)
              Button("Cancel") { if !deletingAccount { showDeleteModal = false } }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
          }
          .foregroundColor(.white)
          .padding(16)
          .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.06, green: 0.09, blue: 0.16)))
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.25)))
          .padding(24)
        }
        .transition(.opacity)
      }
    }
  }

  // MARK: Small UI helpers

  private func labeledRow(_ label: String, content: () -> Text) -> some View {
    HStack {
      Text(label).font(.system(size: 13, weight: .bold)).foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))
      Spacer()
      content()
    }
  }

  private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
    Button { Task { await action() } } label: { Text(title).font(.system(size: 13, weight: .bold)) }
      .buttonStyle(PrimaryButtonStyle())
  }

  private func destructiveButton(_ title: String, action: @escaping () async -> Void) -> some View {
    Button { Task { await action() } } label: { Text(title).font(.system(size: 13, weight: .bold)) }
      .buttonStyle(DestructiveButtonStyle())
  }

  private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat; let content: () -> Content
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) { self.spacing = spacing; self.content = content }
    var body: some View { HStack(spacing: spacing) { content() }.frame(maxWidth: .infinity, alignment: .leading) }
  }

  // MARK: Networking & derived

  private func apiURL(_ path: String) -> URL { AppConfig.apiBase.appendingPathComponent(path) }

  private func renewalText() -> String {
    guard currentPeriodEnd > 0 else { return "" }
    let d = Date(timeIntervalSince1970: TimeInterval(currentPeriodEnd))
    return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
  }

  private func jfExists() -> Bool { jfUsername != "" && jfUsername != "N/A" }
  private func canGenerateJF() -> Bool { !email.isEmpty && subscriptionStatus == "active" }
  private func notExpired() -> Bool {
    let ms = currentPeriodEnd > 0 ? currentPeriodEnd * 1000 : 0
    return ms > 0 && Double(ms) > Date().timeIntervalSince1970 * 1000.0
  }

  private func isFirstOfMonth() -> Bool { Calendar.current.component(.day, from: Date()) == 1 }

  private func formatExpiration(_ expires: String?) -> String {
    guard let s = expires, let d = ISO8601DateFormatter().date(from: s) else { return "" }
    let now = Date()
    if d < now { return "Expired" }
    let hours = Int((d.timeIntervalSince(now) / 3600.0).rounded())
    let date = DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
    return "\(date) (\(hours)h left)"
  }

  private func bootstrap() async {
    await fetchSession()
    await fetchStripeStatus()
    await checkJellyfin()
    invitesAvailable = inviteLimit
  }

  private func refreshSettings() async {
    await fetchSession()
    await fetchStripeStatus()
    await checkJellyfin()
    invitesAvailable = inviteLimit
  }

  private func fetchStripeStatus() async {
    guard !email.isEmpty else { return }
    var comps = URLComponents(url: apiURL("api/get-stripe-status"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "email", value: email)]
    do {
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
      let s = try JSONDecoder().decode(StripeStatusResponse.self, from: data)
      subscriptionStatus = s.status ?? ""
      currentPeriodEnd = s.current_period_end ?? 0
      cancelAtPeriodEnd = s.cancel_at_period_end ?? false
    } catch { }
  }

  private func fetchSession() async {
    do {
      let (data, resp) = try await URLSession.shared.data(from: apiURL("api/get-session"))
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
      if let s = try? JSONDecoder().decode(SessionResponse.self, from: data), let u = s.user {
        userId = u.id ?? ""
        if let created = u.created_at {
          let d = ISO8601DateFormatter().date(from: created) ?? Date()
          createdAt = DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
        }
        discordUsername = u.user_metadata?.discord ?? ""
      }
    } catch { }
  }

  private func postJSON<T: Encodable>(_ url: URL, body: T) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(body)
    let (data, resp) = try await URLSession.shared.data(for: req)
    return (data, resp as! HTTPURLResponse)
  }

  private func msgFrom(_ data: Data) -> String? {
    if let g = try? JSONDecoder().decode(GenericOK.self, from: data), let m = g.message, !m.isEmpty { return m }
    if let e = try? JSONDecoder().decode(GenericErr.self, from: data), let m = e.error, !m.isEmpty { return m }
    return nil
  }

  // ---- Jellyfin ----

  private func checkJellyfin() async {
    guard !email.isEmpty else { return }
    jfLoading = true; jfError = ""; jfSuccess = ""
    defer { jfLoading = false }
    struct Payload: Encodable { let username: String }
    do {
      let (data, resp) = try await postJSON(apiURL("api/jellyfin-user-exists"), body: Payload(username: email))
      guard resp.statusCode == 200 else { return }
      let res = try? JSONDecoder().decode(JellyfinExistsResponse.self, from: data)
      jfUsername = (res?.exists == true) ? email : "N/A"
    } catch {
      jfError = "Could not check Jellyfin account."
    }
  }

  // Unified create/reset password (mirrors web: /api/check-or-create-jellyfin)
  private func submitJellyfinPassword() async {
    guard !email.isEmpty else { jfPassError = "Missing email."; return }
    guard !jfNewPass.isEmpty else { jfPassError = "Please enter a new password."; return }
    guard jfNewPass == jfConfirmPass else { jfPassError = "Passwords do not match."; return }

    jfPassError = ""; jfSubmitting = true
    defer { jfSubmitting = false }

    struct Body: Encodable { let email: String; let username: String; let password: String }

    do {
      let (data, resp) = try await postJSON(
        apiURL("api/check-or-create-jellyfin"),
        body: Body(email: email, username: email, password: jfNewPass)
      )
      if resp.statusCode == 200 {
        jfUsername = email
        jfSuccess = jfIsReset ? "Password updated!" : "Jellyfin account generated!"
        showJFPassModal = false
        jfNewPass = ""; jfConfirmPass = ""
        jfIsReset = false
      } else {
        jfPassError = msgFrom(data) ?? "Failed to update password."
      }
    } catch {
      jfPassError = "Error updating password."
    }
  }

  // ---- Stripe ----

  private func cancelSubscription() async {
    guard !email.isEmpty else { return }
    struct Payload: Encodable { let email: String }
    jfLoading = true; defer { jfLoading = false }
    do {
      let (data, resp) = try await postJSON(apiURL("api/cancel-subscription"), body: Payload(email: email))
      if resp.statusCode == 200 {
        jfSuccess = msgFrom(data) ?? "Subscription canceled successfully."
        cancelAtPeriodEnd = true
      } else {
        jfError = msgFrom(data) ?? "Failed to cancel subscription."
      }
    } catch {
      jfError = "Error cancelling subscription."
    }
  }

  private func restoreSubscription() async {
    guard !email.isEmpty else { return }
    struct Payload: Encodable { let email: String }
    jfLoading = true; defer { jfLoading = false }
    do {
      let (data, resp) = try await postJSON(apiURL("api/restore-subscription"), body: Payload(email: email))
      if resp.statusCode == 200 {
        if let s = try? JSONDecoder().decode(StripeStatusResponse.self, from: data),
           (s.status ?? "").isEmpty == false {
          subscriptionStatus = "active"
          cancelAtPeriodEnd = false
          jfSuccess = "Subscription restored!"
        } else {
          jfError = msgFrom(data) ?? "Failed to restore subscription."
        }
      } else {
        jfError = msgFrom(data) ?? "Failed to restore subscription."
      }
    } catch {
      jfError = "Error restoring subscription."
    }
  }

  // ---- Discord & Account ----

  private func updateDiscord() async {
    guard !email.isEmpty else { return }
    struct Body: Encodable { let email: String; let discord: String }
    do {
      let (data, resp) = try await postJSON(apiURL("api/save-user"), body: Body(email: email, discord: updatedDiscord))
      if resp.statusCode == 200 {
        discordUsername = updatedDiscord
        updatedDiscord = ""
        confirmation = msgFrom(data) ?? "✅ Discord username updated."
      } else {
        confirmation = msgFrom(data) ?? "❌ Failed to update Discord username."
      }
    } catch {
      confirmation = "❌ Error updating Discord username."
    }
  }

  private func updateEmail() async {
    guard !newEmail.isEmpty else { confirmation = "❌ Enter a new email."; return }
    struct Body: Encodable { let email: String; let new_email: String }
    do {
      let (data, resp) = try await postJSON(apiURL("api/update-email"), body: Body(email: email, new_email: newEmail))
      if resp.statusCode == 200 {
        confirmation = msgFrom(data) ?? "✅ Email update requested. Check both emails for confirmation."
        newEmail = ""
      } else {
        confirmation = msgFrom(data) ?? "❌ Email update failed."
      }
    } catch {
      confirmation = "❌ Email update failed."
    }
  }

  /// Change account password — Option 1:
  /// Directly call /api/reset-password { email, newPassword }.
  private func changeAccountPassword() async {
    guard !email.isEmpty else { confirmation = "❌ Could not determine your account email."; return }
    guard !currentPassword.isEmpty, !newPassword.isEmpty else {
      confirmation = "❌ Enter current and new password."
      return
    }

    struct ResetBody: Encodable { let email: String; let newPassword: String }
    do {
      let (data, resp) = try await postJSON(apiURL("api/reset-password"), body: ResetBody(email: email, newPassword: newPassword))
      if (200...299).contains(resp.statusCode) {
        confirmation = msgFrom(data) ?? "✅ Password updated successfully."
        currentPassword = ""; newPassword = ""
      } else {
        confirmation = msgFrom(data) ?? "❌ Failed to update password."
      }
    } catch {
      confirmation = "❌ Network error while updating password."
    }
  }

  // ---- Invites (local demo – replace with Supabase-Swift if desired) ----

  private func generateInvite() async {
    if invites.count >= inviteLimit && !isFirstOfMonth() {
      inviteNotice = "You have generated the maximum of \(inviteLimit) invites this month."
      return
    }
    let code = String(UUID().uuidString.prefix(8)).uppercased()
    let expiresISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(48 * 3600))
    let new = Invite(code: code, issued_to: "open", max_uses: 1, uses: 0,
                     created_at: ISO8601DateFormatter().string(from: Date()), expires_at: expiresISO)
    invites.insert(new, at: 0)
    invitesAvailable = max(0, invitesAvailable - 1)
    confirmation = "✅ Invite created: \(code)"
  }

  private func requestAccountDeletion() async {
    guard !userId.isEmpty else { deleteError = "Missing user id."; return }
    deletingAccount = true
    defer { deletingAccount = false }
    struct Body: Encodable { let id: String }
    do {
      let (data, resp) = try await postJSON(apiURL("api/delete-user"), body: Body(id: userId))
      if resp.statusCode == 200 {
        NotificationCenter.default.post(name: .init("S2VidsDidLogout"), object: nil)
      } else {
        deleteError = msgFrom(data) ?? "Failed to delete account."
      }
    } catch {
      deleteError = "Unexpected error deleting account."
    }
  }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}

private struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.3)))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}

private struct DestructiveButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}
