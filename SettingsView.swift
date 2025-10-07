//
//  SettingsView.swift
//  s2vids
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

// MARK: - Settings View

struct SettingsView: View {
  // Presented from DashboardView
  let email: String
  let isAdmin: Bool

  // General
  @Environment(\.dismiss) private var dismiss
  private let inviteLimit = 5

  // State (mirrors the web page structure)
  @State private var userId: String = ""
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
    }
    .preferredColorScheme(.dark)
    .task { await bootstrap() }
    .overlay { deleteAccountOverlay() }
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
        onLogout: { /* hook logout */ },
        onOpenSettings: { /* already here */ },
        onOpenMovies: {
          // Go back to Dashboard and let it open Movies
          dismiss()
          NotificationCenter.default.post(
            name: Notification.Name("S2OpenMovies"),
            object: nil
          )
        },
        onOpenDiscover: {
          dismiss()
          NotificationCenter.default.post(
            name: Notification.Name("S2OpenDiscover"),
            object: nil
          )
        },
        onOpenTvShows: {
          // ✅ NEW: route to TV Shows from Settings
          dismiss()
          NotificationCenter.default.post(
            name: Notification.Name("S2OpenTvShows"),
            object: nil
          )
        }
      )
    }
    .zIndex(10_000)
  }

  private var greetingStripe: some View {
    HStack {
      Text("Signed in as ")
        .foregroundColor(.white.opacity(0.8))
        .font(.subheadline)
      Text(email.isEmpty ? "—" : email)
        .foregroundColor(.white)
        .font(.system(size: 15, weight: .bold))
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
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(red: 0.06, green: 0.09, blue: 0.16))
      )
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.25)))
  }

  // Jellyfin / Stripe
  private func jellyfinPanelView() -> some View {
    sectionContainer {
      Text("Jellyfin Access")
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.white)

      labeledRow("Username") {
        Text(jfUsername).foregroundColor(.white)
      }

      if subscriptionStatus == "active" {
        labeledRow("Renews On") {
          Text(renewalText().isEmpty ? "—" : renewalText())
            .foregroundColor(.white)
        }
      }

      WrapHStack(spacing: 10) {
        if !jfExists() && canGenerateJF() {
          primaryButton("Create Account") { await createJellyfin() }
        }
        if jfExists() && canGenerateJF() {
          primaryButton("Change Password") { await changeJellyfinPassword() }
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
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(Color.yellow.opacity(0.15))
          )
      }

      if !jfSuccess.isEmpty { Text(jfSuccess).font(.footnote).foregroundColor(.green) }
      if !jfError.isEmpty { Text(jfError).font(.footnote).foregroundColor(.red) }
    }
  }

  // Discord
  private func discordPanelView() -> some View {
    sectionContainer {
      HStack(spacing: 8) {
        Image(systemName: "person.crop.circle.badge.checkmark")
        Text("Discord")
      }
      .font(.system(size: 17, weight: .bold))
      .foregroundColor(.white)

      Text("Discord Username")
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))

      HStack(spacing: 8) {
        TextField("@YourDiscordName", text: $updatedDiscord)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .padding(.horizontal, 10)
          .frame(height: 36)
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
        Text("Invite Codes")
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.white)
        Spacer()
        Text("\(invitesAvailable) left this month")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))
      }

      HStack(spacing: 8) {
        primaryButton("Generate Invite") { await generateInvite() }
          .disabled(invitesAvailable == 0 && !isFirstOfMonth())
          .opacity((invitesAvailable == 0 && !isFirstOfMonth()) ? 0.5 : 1.0)

        if !inviteNotice.isEmpty {
          Text(inviteNotice)
            .font(.caption)
            .foregroundColor(.yellow)
        }
      }

      if !confirmation.isEmpty {
        Text(confirmation).font(.footnote).foregroundColor(.green)
      }

      if invites.isEmpty {
        Text("No invites generated yet.")
          .foregroundColor(.white.opacity(0.75))
          .font(.subheadline)
      } else {
        VStack(spacing: 8) {
          ForEach(invites) { inv in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(inv.code)
                  .font(.system(.body, design: .monospaced))
                  .foregroundColor(.white)
                Text("(Uses: \(inv.uses)/\(inv.max_uses))")
                  .font(.caption).foregroundColor(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 6) {
                Text("Expires: \(formatExpiration(inv.expires_at))")
                  .font(.caption).foregroundColor(.secondary)
                Button {
                  UIPasteboard.general.string = inv.code
                  copiedCode = inv.code
                  DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copiedCode = "" }
                } label: {
                  HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text(copiedCode == inv.code ? "Copied!" : "Copy")
                  }
                }
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
      Text("Account")
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.white)

      labeledRow("Account Created") {
        Text(createdAt.isEmpty ? "—" : createdAt).foregroundColor(.white)
      }

      // Email
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "envelope.fill")
          Text("Email")
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(.white)

        Text("Current: \(email)")
          .font(.footnote).foregroundColor(.secondary)

        HStack(spacing: 8) {
          TextField("new@example.com", text: $newEmail)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
            .foregroundColor(.white)
          primaryButton("Update") {
            confirmation = "⚠️ Email change from iOS requires auth; please use the web for now."
            newEmail = ""
          }
        }
      }

      // Password
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "lock.fill")
          Text("Change Password")
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(.white)

        SecureField("Current Password", text: $currentPassword)
          .padding(.horizontal, 10).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
          .foregroundColor(.white)

        SecureField("New Password", text: $newPassword)
          .padding(.horizontal, 10).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.12, green: 0.14, blue: 0.19)))
          .foregroundColor(.white)

        primaryButton("Update") {
          confirmation = "⚠️ Password change from iOS requires auth; please use the web for now."
          currentPassword = ""; newPassword = ""
        }
      }

      Divider().background(Color.gray.opacity(0.25))

      destructiveButton("Delete Account") {
        showDeleteModal = true
      }

      Text("Permanently delete your account. This cannot be undone.")
        .font(.caption).foregroundColor(.secondary)
    }
  }

  // MARK: Overlay (delete)

  private func deleteAccountOverlay() -> some View {
    Group {
      if showDeleteModal {
        ZStack {
          Color.black.opacity(0.6).ignoresSafeArea()
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
              Text("Delete Account").font(.system(size: 17, weight: .bold))
            }
            Text("This will permanently delete your account and sign you out. This action cannot be undone.")
              .font(.subheadline)

            if !deleteError.isEmpty {
              Text(deleteError).font(.footnote).foregroundColor(.red)
            }

            HStack(spacing: 8) {
              destructiveButton(deletingAccount ? "Deleting…" : "Delete") {
                await requestAccountDeletion()
              }
              .disabled(deletingAccount)

              Button("Cancel") {
                if !deletingAccount { showDeleteModal = false }
              }
              .buttonStyle(SecondaryButtonStyle())
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
      Text(label)
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))
      Spacer()
      content()
    }
  }

  private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
    Button { Task { await action() } } label: {
      Text(title).font(.system(size: 13, weight: .bold))
    }
    .buttonStyle(PrimaryButtonStyle())
  }

  private func destructiveButton(_ title: String, action: @escaping () async -> Void) -> some View {
    Button { Task { await action() } } label: {
      Text(title).font(.system(size: 13, weight: .bold))
    }
    .buttonStyle(DestructiveButtonStyle())
  }

  private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
      self.spacing = spacing
      self.content = content
    }
    var body: some View {
      HStack(spacing: spacing) { content() }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Networking & derived

  private func apiURL(_ path: String) -> URL {
    AppConfig.apiBase.appendingPathComponent(path)
  }

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

  private func isFirstOfMonth() -> Bool {
    Calendar.current.component(.day, from: Date()) == 1
  }

  private func formatExpiration(_ expires: String?) -> String {
    guard let s = expires, let d = ISO8601DateFormatter().date(from: s) else { return "" }
    let now = Date()
    if d < now { return "Expired" }
    let hours = Int((d.timeIntervalSince(now) / 3600.0).rounded())
    let date = DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
    return "\(date) (\(hours)h left)"
  }

  private func bootstrap() async {
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

  private func postJSON<T: Encodable>(_ url: URL, body: T) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(body)
    let (data, resp) = try await URLSession.shared.data(for: req)
    return (data, resp as! HTTPURLResponse)
  }

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

  private func createJellyfin() async {
    jfSuccess = "Triggered create account (implement server endpoint)."
  }

  private func changeJellyfinPassword() async {
    jfSuccess = "Triggered change password (implement server endpoint)."
  }

  private func cancelSubscription() async {
    guard !email.isEmpty else { return }
    struct Payload: Encodable { let email: String }
    jfLoading = true; defer { jfLoading = false }
    do {
      let (_, resp) = try await postJSON(apiURL("api/cancel-subscription"), body: Payload(email: email))
      if resp.statusCode == 200 {
        jfSuccess = "Subscription canceled successfully."
        cancelAtPeriodEnd = true
      } else {
        jfError = "Failed to cancel subscription."
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
        let s = (try? JSONDecoder().decode(StripeStatusResponse.self, from: data))?.status
        if (s ?? "") != "" {
          subscriptionStatus = "active"
          cancelAtPeriodEnd = false
          jfSuccess = "Subscription restored!"
        } else {
          jfError = "Failed to restore subscription."
        }
      } else {
        jfError = "Failed to restore subscription."
      }
    } catch {
      jfError = "Error restoring subscription."
    }
  }

  private func updateDiscord() async {
    discordUsername = updatedDiscord
    updatedDiscord = ""
    confirmation = "✅ Discord username updated."
  }

  private func generateInvite() async {
    if invites.count >= inviteLimit && !isFirstOfMonth() {
      inviteNotice = "You have generated the maximum of \(inviteLimit) invites this month."
      return
    }
    let code = String(UUID().uuidString.prefix(8)).uppercased()
    let expiresISO = ISO8601DateFormatter().string(from: Date().addingTimeInterval(48 * 3600))
    let new = Invite(code: code, issued_to: "open", max_uses: 1, uses: 0, created_at: ISO8601DateFormatter().string(from: Date()), expires_at: expiresISO)
    invites.insert(new, at: 0)
    invitesAvailable = max(0, invitesAvailable - 1)
    confirmation = "✅ Invite created: \(code)"
  }

  private func requestAccountDeletion() async {
    guard !userId.isEmpty else {
      deleteError = "Missing user id. (Add server endpoint or pass userId.)"
      return
    }
    deletingAccount = true
    defer { deletingAccount = false }
    deleteError = "Implement delete-user endpoint for iOS."
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
