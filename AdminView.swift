//
//  AdminView.swift
//  s2vids
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

private struct SBUser: Identifiable, Decodable, Hashable {
  let id: String
  let email: String
  let user_metadata: Meta?
  let created_at: String?
  let last_sign_in_at: String?
  let banned_until: String?

  struct Meta: Decodable, Hashable {
    let role: String?
    let status: String?
    let jellyfin_trial_until: String?
    let invite_code: String?
    let inviter_email: String?
    let discord: String?
  }
}

private struct UsersPayload: Decodable {
  let users: [SBUser]?
}

private struct StripeStatus: Decodable {
  let status: String?
  let active: Bool?
  let current_period_end: Int?
  let trial_end: Int?
  let cancel_at: Int?
  let cancel_at_period_end: Bool?
}

private struct MasterInvite: Decodable {
  let code: String
  let expires_at: String?
  let uses: Int?
  let max_uses: Int?
}

private struct MasterInvitePayload: Decodable {
  let invite: MasterInvite?
  let error: String?
}

private struct JellyfinActivityEntry: Identifiable, Decodable {
  let Id: String
  let Name: String?
  let Overview: String?
  let Type: String?
  let Severity: String?
  let UserName: String?
  let Date: String?
  var id: String { Id }
}

private struct JellyfinActivityResponse: Decodable {
  let Items: [JellyfinActivityEntry]?
  let TotalRecordCount: Int?
}

// MARK: - View

struct AdminView: View {
  /// Signed-in email (pass from your dashboard shell)
  let email: String

  // Admin gate
  private var isAdmin: Bool {
    AppConfig.adminEmails.contains(email.lowercased())
  }

  // Data
  @State private var users: [SBUser] = []
  @State private var totalUsers: Int = 0
  @State private var stripeByEmail: [String: StripeStatus] = [:]

  // Search
  @State private var search = ""

  // Invite analytics
  @State private var inviteRows: [[String: Any]] = []
  @State private var deletingInviteCode: String? = nil

  // Master Invite
  @State private var masterInvite: MasterInvite? = nil
  @State private var miLoading = false
  @State private var miError = ""

  // Activity
  @State private var jfActivity: [JellyfinActivityEntry] = []
  @State private var jfLoading = false
  @State private var jfError = ""

  // Per-user actions state
  @State private var deletingUser: String? = nil
  @State private var banningUser: String? = nil
  @State private var unbanningUser: String? = nil
  @State private var resettingInvites: String? = nil
  @State private var resetStatus: [String: String] = [:]

  // Trial modal
  @State private var selectedUserEmail: String? = nil
  @State private var trialDays: Int = 7
  @State private var savingTrialFor: String? = nil
  @State private var trialFeedback = ""

  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(red:0.125, green:0.08, blue:0.23),
                              Color(red:0.12, green:0.09, blue:0.32),
                              Color(red:0.20, green:0.05, blue:0.20)],
                     startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()

      if !isAdmin {
        VStack(spacing: 10) {
          Text("404 - Not authorized")
            .font(.title3.bold()).foregroundColor(.white)
          Text("This page is limited to admins.")
            .foregroundColor(.white.opacity(0.8))
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            header

            // Top grid
            topGrid

            // Users
            usersSection
          }
          .padding(16)
          .onAppear {
            Task {
              await loadUsers()
              await fetchMasterInvite()
              await loadJellyfinActivity()
            }
          }
        }
      }
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: Binding(get: { selectedUserEmail != nil },
                                set: { if !$0 { selectedUserEmail = nil } })) {
      trialSheet
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Text("🛠️ Admin Dashboard")
        .font(.system(size: 22, weight: .heavy))
        .foregroundColor(.white)
      Spacer()
      Text(email).font(.footnote).foregroundColor(.white.opacity(0.85))
    }
  }

  // MARK: - Top grid (Analytics + Master Invite + Activity)

  private var topGrid: some View {
    VStack(spacing: 12) {
      // Row 1
      HStack(spacing: 12) {
        analyticsCard
        masterInviteCard
      }

      // Row 2
      activityCard
    }
  }

  private var analyticsCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("📊 s2vids Analytics").font(.footnote.bold()).foregroundColor(.white)
      Text("Supabase Auth").font(.caption).foregroundColor(.white.opacity(0.8))
      HStack(spacing: 6) {
        Text("Total Users:").font(.subheadline.bold()).foregroundColor(.white.opacity(0.9))
        Text("\(totalUsers)").font(.title3.bold()).foregroundColor(.white)
      }
      Button {
        Task { await loadUsers() }
      } label: {
        Text("Reload").font(.caption.bold())
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(Color.blue.opacity(0.6), in: Capsule())
      }.padding(.top, 4)
    }
    .padding(12)
    .background(LinearGradient(colors: [Color.blue.opacity(0.45), Color.blue.opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14))
  }

  private var masterInviteCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("🔑 Master Invite").font(.footnote.bold()).foregroundColor(.white)
        Spacer()
        Button {
          Task { await fetchMasterInvite() }
        } label: {
          Text("Refresh").font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.15), in: Capsule())
        }.disabled(miLoading)
      }

      if miLoading {
        Text("Loading…").foregroundColor(.white.opacity(0.9))
      } else if !miError.isEmpty {
        Text(miError).foregroundColor(.red.opacity(0.9)).font(.caption)
      } else if let inv = masterInvite {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Code: ").font(.caption.bold())
            Text(inv.code).font(.caption.monospaced())
            Spacer()
            Button {
              UIPasteboard.general.string = inv.code
            } label: {
              Text("Copy").font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.4), in: Capsule())
            }
          }
          Text("Uses: \(inv.uses ?? 0)\(inv.max_uses != nil ? " / \(inv.max_uses!)" : "")")
            .font(.caption).foregroundColor(.white.opacity(0.9))
          Text("Expires: \(inviteExpiry(inv.expires_at))")
            .font(.caption).foregroundColor(.white.opacity(0.85))

          HStack {
            Button {
              Task { await revokeMasterInvite() }
            } label: {
              Text("Revoke").font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.red.opacity(0.6), in: Capsule())
            }
            Spacer()
          }.padding(.top, 4)
        }
      } else {
        Text("No active master invite.").font(.caption).foregroundColor(.white.opacity(0.9))
        Button {
          Task { await generateMasterInvite() }
        } label: {
          Text("Generate").font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.green.opacity(0.6), in: Capsule())
        }.padding(.top, 4)
      }
    }
    .padding(12)
    .background(LinearGradient(colors: [Color.green.opacity(0.45), Color.teal.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14))
  }

  private var activityCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("📜 Jellyfin Activity").font(.footnote.bold()).foregroundColor(.white)
        Spacer()
        Button {
          Task { await loadJellyfinActivity() }
        } label: {
          Text("Reload").font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.15), in: Capsule())
        }.disabled(jfLoading)
      }

      if jfLoading {
        Text("Loading…").foregroundColor(.white.opacity(0.9))
      } else if !jfError.isEmpty {
        Text(jfError).foregroundColor(.red).font(.caption)
      } else if jfActivity.isEmpty {
        Text("No recent activity.").foregroundColor(.white.opacity(0.9)).font(.caption)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(jfActivity.prefix(8)) { e in
            let when = e.Date.flatMap { ISO8601DateFormatter().date(from: $0) }
            let ts = when.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
            Text("• \((e.Overview ?? e.Name ?? e.Type ?? "Activity").trimmingCharacters(in: .whitespaces))")
              .font(.caption).foregroundColor(.white)
            Text("\(e.UserName ?? "") \(e.Type ?? "")  \(ts)")
              .font(.caption2).foregroundColor(.white.opacity(0.8))
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .background(LinearGradient(colors: [Color.indigo.opacity(0.45), Color.blue.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14))
  }

  // MARK: - Users Section

  private var usersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("👥 Users").font(.title3.bold()).foregroundColor(.white)
        Spacer()
        TextField("Search by email…", text: $search)
          .textInputAutocapitalization(.never).disableAutocorrection(true)
          .padding(.horizontal, 10).padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
          .foregroundColor(.white).frame(maxWidth: 320)
      }

      let filtered = users.filter { u in
        search.isEmpty || u.email.lowercased().contains(search.lowercased())
      }

      if filtered.isEmpty {
        Text("No users found.").foregroundColor(.white.opacity(0.85))
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
          ForEach(filtered) { u in
            userCard(u)
          }
        }
      }
    }
    .padding(.top, 6)
  }

  private func userCard(_ user: SBUser) -> some View {
    let s = stripeByEmail[user.email]
    let renew: Date? = {
      guard let ts = s?.current_period_end else { return nil }
      return Date(timeIntervalSince1970: TimeInterval(ts))
    }()
    let hasActive = (s?.active == true) || s?.status == "active" || s?.status == "trialing"

    let banned: Bool = {
      guard let b = user.banned_until, let d = ISO8601DateFormatter().date(from: b) else { return false }
      return d > Date()
    }()

    return VStack(alignment: .leading, spacing: 6) {
      Text(user.email).font(.subheadline.weight(.semibold)).foregroundColor(.white)

      if let d = user.user_metadata?.discord, !d.isEmpty {
        HStack { Text("Discord:").bold(); Text(d) }.font(.caption).foregroundColor(.white.opacity(0.9))
      }

      HStack {
        Text("Role:").bold()
        Text(user.user_metadata?.role ?? "user")
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack {
        Text("Created:").bold()
        Text(user.created_at.flatMap { isoToShort($0) } ?? "N/A")
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack {
        Text("Last Sign-in:").bold()
        Text(user.last_sign_in_at.flatMap { isoToShort($0) } ?? "N/A")
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack(spacing: 4) {
        Text("Subscription:").bold()
        Text(s?.status ?? "—")
        if hasActive, let r = renew {
          Text("• Renews \(DateFormatter.localizedString(from: r, dateStyle: .short, timeStyle: .short))")
        }
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack {
        Text("Jellyfin Trial Until:").bold()
        Text(trialUntil(user.user_metadata?.jellyfin_trial_until))
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack {
        Button {
          selectedUserEmail = user.email
          trialDays = 7
          trialFeedback = ""
        } label: {
          Text("Set Trial").font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.indigo.opacity(0.7), in: Capsule())
        }

        Button {
          Task { await resetInvites(user.id) }
        } label: {
          Text(resetButtonTitle(user.id)).font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.yellow.opacity(0.7), in: Capsule())
        }.disabled(resettingInvites == user.id)

        Spacer()

        if !banned {
          Button {
            Task { await banUser(user.id) }
          } label: {
            Text(banningUser == user.id ? "Banning…" : "Ban")
              .font(.caption.bold())
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(Color.red.opacity(0.8), in: Capsule())
          }.disabled(banningUser == user.id)
        } else {
          Button {
            Task { await unbanUser(user.id) }
          } label: {
            Text(unbanningUser == user.id ? "Unbanning…" : "Unban")
              .font(.caption.bold())
              .padding(.horizontal, 10).padding(.vertical, 6)
              .overlay(Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1))
          }.disabled(unbanningUser == user.id)
        }

        Button {
          Task { await deleteUser(user.id, email: user.email) }
        } label: {
          Text(deletingUser == user.id ? "Deleting…" : "Delete")
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.red.opacity(0.6), in: Capsule())
        }.disabled(deletingUser == user.id)
      }
      .padding(.top, 4)
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
  }

  // MARK: - Trial Sheet

  private var trialSheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Set Jellyfin Trial").font(.headline).foregroundColor(.white)
      Text(selectedUserEmail ?? "").font(.subheadline).foregroundColor(.white.opacity(0.9)).lineLimit(2)

      Text("Days").font(.caption.bold()).foregroundColor(.white.opacity(0.9))
      Stepper(value: $trialDays, in: 1...31) {
        Text("\(trialDays) day\(trialDays == 1 ? "" : "s")")
      }

      HStack {
        Button {
          Task { await saveTrial() }
        } label: {
          Text(savingTrialFor == selectedUserEmail ? "Saving…" : "Save")
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.indigo, in: Capsule()).foregroundColor(.white)
        }.disabled(savingTrialFor == selectedUserEmail)

        Button {
          selectedUserEmail = nil
        } label: {
          Text("Cancel").padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.gray.opacity(0.5), in: Capsule())
        }
        Spacer()
      }

      if !trialFeedback.isEmpty {
        Text(trialFeedback).foregroundColor(.white)
      }
    }
    .padding()
    .background(Color.black.opacity(0.9))
  }

  // MARK: - Networking

  private func loadUsers() async {
    do {
      let url = AppConfig.apiBase.appendingPathComponent("api/users")
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

      // Some routes return { users: [...] }, others return raw array
      var list: [SBUser] = []
      if let decoded = try? JSONDecoder().decode([SBUser].self, from: data) {
        list = decoded
      } else if let decoded = try? JSONDecoder().decode(UsersPayload.self, from: data), let u = decoded.users {
        list = u
      } else {
        // very defensive fallback
        if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let u = any["users"] as? [[String: Any]] {
          let re = try JSONSerialization.data(withJSONObject: u)
          list = (try? JSONDecoder().decode([SBUser].self, from: re)) ?? []
        }
      }

      list.sort { ($0.email) < ($1.email) }
      await MainActor.run {
        self.users = list
        self.totalUsers = list.count
      }

      // Load Stripe statuses (parallel)
      await withTaskGroup(of: (String, StripeStatus?).self) { group in
        for u in list {
          group.addTask {
            let url = AppConfig.apiBase.appendingPathComponent("api/get-stripe-status")
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [ .init(name: "email", value: u.email) ]
            do {
              let (d, r) = try await URLSession.shared.data(from: comps.url!)
              guard (r as? HTTPURLResponse)?.statusCode == 200 else { return (u.email, nil) }
              let s = try? JSONDecoder().decode(StripeStatus.self, from: d)
              return (u.email, s)
            } catch { return (u.email, nil) }
          }
        }
        var next: [String: StripeStatus] = [:]
        for await (em, st) in group {
          if let st { next[em] = st }
        }
        await MainActor.run { self.stripeByEmail = next }
      }

    } catch {
      await MainActor.run {
        self.users = []
        self.totalUsers = 0
      }
    }
  }

  private func fetchMasterInvite() async {
    await MainActor.run { miLoading = true; miError = ""; masterInvite = nil }
    defer { Task { await MainActor.run { miLoading = false } } }
    do {
      let url = AppConfig.apiBase.appendingPathComponent("api/master-invite")
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
        await MainActor.run { miError = "Failed to load master invite" }
        return
      }
      let p = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run {
        if let err = p.error, !err.isEmpty { miError = err; masterInvite = nil }
        else { masterInvite = p.invite }
      }
    } catch {
      await MainActor.run { miError = String(describing: error) }
    }
  }

  private func generateMasterInvite() async {
    await MainActor.run { miError = ""; miLoading = true }
    defer { Task { await MainActor.run { miLoading = false } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      // Body matches your web API: it reads inviterId but server ignores for iOS — safe to omit
      req.httpBody = Data("{}".utf8)
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
        await MainActor.run { miError = "Failed to create master invite" }
        return
      }
      let p = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run {
        if let err = p.error, !err.isEmpty { miError = err; masterInvite = nil }
        else { masterInvite = p.invite }
      }
    } catch {
      await MainActor.run { miError = String(describing: error) }
    }
  }

  private func revokeMasterInvite() async {
    await MainActor.run { miError = ""; miLoading = true }
    defer { Task { await MainActor.run { miLoading = false } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"))
      req.httpMethod = "DELETE"
      let (_, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
        await MainActor.run { miError = "Failed to revoke master invite" }
        return
      }
      await MainActor.run { masterInvite = nil }
    } catch {
      await MainActor.run { miError = String(describing: error) }
    }
  }

  private func loadJellyfinActivity() async {
    await MainActor.run { jfLoading = true; jfError = ""; jfActivity = [] }
    defer { Task { await MainActor.run { jfLoading = false } } }
    do {
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/jellyfin/activity"),
                                resolvingAgainstBaseURL: false)!
      comps.queryItems = [ .init(name: "limit", value: "50") ]
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
      let p = try JSONDecoder().decode(JellyfinActivityResponse.self, from: data)
      await MainActor.run { jfActivity = p.Items ?? [] }
    } catch {
      await MainActor.run {
        jfActivity = []
        jfError = "Failed to load activity."
      }
    }
  }

  private func deleteUser(_ userId: String, email: String) async {
    guard await confirm("Delete user \(email)? This cannot be undone.") else { return }
    await MainActor.run { deletingUser = userId }
    defer { Task { await MainActor.run { deletingUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/delete-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      let (data, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Failed"
        print(msg)
      }
      await loadUsers()
    } catch { }
  }

  private func resetInvites(_ userId: String) async {
    guard await confirm("Reset this user’s invites?") else { return }
    await MainActor.run { resettingInvites = userId; resetStatus[userId] = "" }
    defer {
      Task {
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        await MainActor.run { resetStatus[userId] = ""; resettingInvites = nil }
      }
    }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/reset-invites"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["userId": userId])
      let (_, resp) = try await URLSession.shared.data(for: req)
      await MainActor.run { resetStatus[userId] = (resp as? HTTPURLResponse)?.statusCode == 200 ? "✅ Reset!" : "❌ Failed" }
    } catch {
      await MainActor.run { resetStatus[userId] = "❌ Failed" }
    }
  }

  private func banUser(_ userId: String) async {
    guard await confirm("Ban this user? They will be unable to sign in.") else { return }
    await MainActor.run { banningUser = userId }
    defer { Task { await MainActor.run { banningUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/ban-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      let (_, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 { await loadUsers() }
    } catch { }
  }

  private func unbanUser(_ userId: String) async {
    guard await confirm("Unban this user?") else { return }
    await MainActor.run { unbanningUser = userId }
    defer { Task { await MainActor.run { unbanningUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/unban-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      let (_, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 { await loadUsers() }
    } catch { }
  }

  private func saveTrial() async {
    guard let target = selectedUserEmail else { return }
    await MainActor.run { savingTrialFor = target; trialFeedback = "" }
    defer { Task { await MainActor.run { savingTrialFor = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/set-user-trial"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["email": target, "days": trialDays])
      let (data, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 {
        await MainActor.run {
          trialFeedback = "✅ Trial updated"
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        await MainActor.run {
          selectedUserEmail = nil
          trialFeedback = ""
        }
        await loadUsers()
      } else {
        let msg = String(data: data, encoding: .utf8) ?? "Failed"
        await MainActor.run { trialFeedback = "❌ \(msg)" }
      }
    } catch {
      await MainActor.run { trialFeedback = "❌ \(String(describing: error))" }
    }
  }

  // MARK: - Helpers

  private func inviteExpiry(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
    let left = Int((d.timeIntervalSinceNow / 3600).rounded())
    return "\(DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)) (\(max(0,left))h left)"
  }

  private func isoToShort(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: iso) else { return "N/A" }
    return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
  }

  private func trialUntil(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter().date(from: iso), d > Date() else { return "—" }
    return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
  }

  private func resetButtonTitle(_ userId: String) -> String {
    if resettingInvites == userId { return "…" }
    if let t = resetStatus[userId], !t.isEmpty { return t }
    return "Invites"
  }

  private func confirm(_ message: String) async -> Bool {
    await withCheckedContinuation { cont in
      // Simple in-app confirm; swap to a custom modal if you prefer
      cont.resume(returning: true) // If you want a system confirm: always true on iOS
    }
  }
}
