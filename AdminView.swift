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

private struct UsersPayload: Decodable { let users: [SBUser]? }

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
  let MediaType: String?
  let Severity: String?
  let UserName: String?
  let Date: String?
  var id: String { Id }

  enum CodingKeys: String, CodingKey {
    case Id, Name, Overview, Severity, UserName, Date
    case MediaType = "Type"
    case id, name, overview, severity, username, date, type
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    Id = try c.decodeIfPresent(String.self, forKey: .Id)
      ?? c.decodeIfPresent(String.self, forKey: .id)
      ?? UUID().uuidString
    Name      = try c.decodeIfPresent(String.self, forKey: .Name)      ?? c.decodeIfPresent(String.self, forKey: .name)
    Overview  = try c.decodeIfPresent(String.self, forKey: .Overview)  ?? c.decodeIfPresent(String.self, forKey: .overview)
    Severity  = try c.decodeIfPresent(String.self, forKey: .Severity)  ?? c.decodeIfPresent(String.self, forKey: .severity)
    UserName  = try c.decodeIfPresent(String.self, forKey: .UserName)  ?? c.decodeIfPresent(String.self, forKey: .username)
    Date      = try c.decodeIfPresent(String.self, forKey: .Date)      ?? c.decodeIfPresent(String.self, forKey: .date)
    MediaType = try c.decodeIfPresent(String.self, forKey: .MediaType) ?? c.decodeIfPresent(String.self, forKey: .type)
  }
}

// MARK: - Admin View

struct AdminView: View {
  let email: String
  private var isAdmin: Bool { AppConfig.adminEmails.contains(email.lowercased()) }

  @State private var users: [SBUser] = []
  @State private var totalUsers = 0
  @State private var stripeByEmail: [String: StripeStatus] = [:]
  @State private var search = ""

  @State private var masterInvite: MasterInvite?
  @State private var miLoading = false
  @State private var miError = ""

  @State private var jfActivity: [JellyfinActivityEntry] = []
  @State private var jfLoading = false
  @State private var jfError = ""

  @State private var selectedUserEmail: String?
  @State private var trialDays = 7
  @State private var savingTrialFor: String?
  @State private var trialFeedback = ""
  @State private var showSettings = false

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red:0.125, green:0.08, blue:0.23),
                 Color(red:0.12, green:0.09, blue:0.32),
                 Color(red:0.20, green:0.05, blue:0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      ).ignoresSafeArea()

      if !isAdmin {
        VStack(spacing: 8) {
          Text("🚫 Not Authorized").font(.title3.bold()).foregroundColor(.white)
          Text("This page is restricted to admins.").foregroundColor(.white.opacity(0.8))
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            header
            topGrid.zIndex(0)
            usersSection.zIndex(0)
          }
          .padding(16)
        }
        .refreshable { await reloadAll() }
        .task { await reloadAll() }
      }
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: Binding(get: { selectedUserEmail != nil }, set: { if !$0 { selectedUserEmail = nil } })) {
      trialSheet
    }
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: true)
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      Text("🛠️ Admin Dashboard")
        .font(.system(size: 22, weight: .heavy))
        .foregroundColor(.white)
      Spacer()
      UserMenuButton(
        email: email, isAdmin: true,
        onRequireAccess: { },
        onLogout: { NotificationCenter.default.post(name: .init("S2VidsDidLogout"), object: nil) },
        onOpenSettings: { showSettings = true },
        onOpenMovies: { dismiss(); NotificationCenter.default.post(name: .init("S2OpenMovies"), object: nil) },
        onOpenDiscover: { dismiss(); NotificationCenter.default.post(name: .init("S2OpenDiscover"), object: nil) },
        onOpenTvShows: { dismiss(); NotificationCenter.default.post(name: .init("S2OpenTvShows"), object: nil) },
        onOpenAdmin: { }
      )
      .zIndex(1000) // keep dropdown above all
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color.black.opacity(0.65))
    )
    .zIndex(1000)
  }

  // MARK: Top Grid

  private var topGrid: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        analyticsCard
        masterInviteCard
      }
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
      Button { Task { await loadUsers() } } label: {
        Text("Reload").font(.caption.bold())
          .padding(.horizontal, 10).padding(.vertical, 6)
          .background(Color.blue.opacity(0.6), in: Capsule())
      }.padding(.top, 4)
    }
    .padding(12)
    .background(
      LinearGradient(colors: [Color.blue.opacity(0.45), Color.blue.opacity(0.3)],
                     startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 14)
    )
  }

  private var masterInviteCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("🔑 Master Invite").font(.footnote.bold()).foregroundColor(.white)
        Spacer()
        Button { Task { await fetchMasterInvite() } } label: {
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
          Text("Code: \(inv.code)").font(.caption.monospaced())
          Text("Uses: \(inv.uses ?? 0)/\(inv.max_uses ?? 0)").font(.caption)
          Text("Expires: \(inviteExpiry(inv.expires_at))").font(.caption)
          Button {
            UIPasteboard.general.string = inv.code
          } label: {
            Text("Copy").font(.caption.bold())
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(Color.green.opacity(0.4), in: Capsule())
          }.padding(.top, 4)
        }
      } else {
        Text("No active master invite.").font(.caption).foregroundColor(.white.opacity(0.9))
        Button { Task { await generateMasterInvite() } } label: {
          Text("Generate").font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.green.opacity(0.6), in: Capsule())
        }.padding(.top, 4)
      }
    }
    .padding(12)
    .background(
      LinearGradient(colors: [Color.green.opacity(0.45), Color.teal.opacity(0.35)],
                     startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 14)
    )
  }

  private var activityCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("📜 Jellyfin Activity").font(.footnote.bold()).foregroundColor(.white)
        Spacer()
        Button { Task { await loadJellyfinActivity() } } label: {
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
        ForEach(jfActivity.prefix(6)) { e in
          Text("• \((e.Overview ?? e.Name ?? e.MediaType ?? "Activity"))").font(.caption)
          if let user = e.UserName { Text("by \(user)").font(.caption2).foregroundColor(.white.opacity(0.8)) }
        }
      }
    }
    .padding(12)
    .background(
      LinearGradient(colors: [Color.indigo.opacity(0.45), Color.blue.opacity(0.35)],
                     startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 14)
    )
  }

  // MARK: Users Section

  private var usersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("👥 Users").font(.title3.bold()).foregroundColor(.white)
        Spacer()
        TextField("Search by email…", text: $search)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .padding(.horizontal, 10).padding(.vertical, 8)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
          .foregroundColor(.white).frame(maxWidth: 320)
      }

      let filtered = users.filter { search.isEmpty || $0.email.lowercased().contains(search.lowercased()) }

      if filtered.isEmpty {
        Text("No users found.").foregroundColor(.white.opacity(0.85))
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
          ForEach(filtered) { u in
            Text(u.email).foregroundColor(.white)
          }
        }
      }
    }
  }

  // MARK: Trial Sheet

  private var trialSheet: some View {
    VStack(spacing: 12) {
      Text("Set Jellyfin Trial").font(.headline).foregroundColor(.white)
      Text(selectedUserEmail ?? "").foregroundColor(.white.opacity(0.9))
      Stepper(value: $trialDays, in: 1...31) { Text("\(trialDays) days") }
      Button("Save") { Task { await saveTrial() } }
        .padding().background(Color.indigo, in: Capsule())
      if !trialFeedback.isEmpty { Text(trialFeedback).foregroundColor(.white) }
    }
    .padding().background(Color.black.opacity(0.9))
  }

  // MARK: - Networking

  private func reloadAll() async {
    await loadUsers()
    await fetchMasterInvite()
    await loadJellyfinActivity()
  }

  private func fetchMasterInvite() async {
    await MainActor.run { miLoading = true; miError = "" }
    defer { Task { await MainActor.run { miLoading = false } } }
    do {
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"), resolvingAgainstBaseURL: false)!
      comps.queryItems = [.init(name: "ts", value: "\(Int(Date().timeIntervalSince1970))")]
      let (data, _) = try await URLSession.shared.data(from: comps.url!)
      let p = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run { masterInvite = p.invite }
    } catch {
      if let e = error as? URLError, e.code == .cancelled { return }
      await MainActor.run { miError = "Failed to load" }
    }
  }

  // MARK: Generate & Revoke Master Invite

  private func generateMasterInvite() async {
    await MainActor.run { miError = ""; miLoading = true }
    defer { Task { await MainActor.run { miLoading = false } } }

    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = Data("{}".utf8)

      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
        await MainActor.run { miError = "Failed to create master invite" }
        return
      }

      let payload = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run {
        if let err = payload.error, !err.isEmpty {
          miError = err
          masterInvite = nil
        } else {
          masterInvite = payload.invite
        }
      }
    } catch {
      if let e = error as? URLError, e.code == .cancelled { return }
      await MainActor.run { miError = "Error: \(error.localizedDescription)" }
    }
  }

  private func revokeMasterInvite() async {
    await MainActor.run { miError = ""; miLoading = true }
    defer { Task { await MainActor.run { miLoading = false } } }

    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"))
      req.httpMethod = "DELETE"

      let (_, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 {
        await MainActor.run { masterInvite = nil }
      } else {
        await MainActor.run { miError = "Failed to revoke master invite" }
      }
    } catch {
      if let e = error as? URLError, e.code == .cancelled { return }
      await MainActor.run { miError = "Error: \(error.localizedDescription)" }
    }
  }

  // MARK: Jellyfin Activity

  private func loadJellyfinActivity() async {
    await MainActor.run { jfLoading = true; jfError = "" }
    defer { Task { await MainActor.run { jfLoading = false } } }
    do {
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/jellyfin/activity"), resolvingAgainstBaseURL: false)!
      comps.queryItems = [.init(name: "ts", value: "\(Int(Date().timeIntervalSince1970))")]
      let (data, _) = try await URLSession.shared.data(from: comps.url!)
      let decoded = try JSONDecoder().decode([JellyfinActivityEntry].self, from: data)
      await MainActor.run { jfActivity = decoded }
    } catch {
      if let e = error as? URLError, e.code == .cancelled { return }
      await MainActor.run { jfError = "Failed to load activity." }
    }
  }

  private func saveTrial() async {
    guard let email = selectedUserEmail else { return }
    await MainActor.run { savingTrialFor = email; trialFeedback = "" }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/set-user-trial"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "days": trialDays])
      let (_, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 200 {
          await MainActor.run { trialFeedback = "✅ Trial updated" }
          try? await Task.sleep(nanoseconds: 900_000_000)
          await MainActor.run { selectedUserEmail = nil; trialFeedback = "" }
          await loadUsers()
        } else {
          await MainActor.run { trialFeedback = "❌ Failed to update" }
        }
      } catch {
        await MainActor.run { trialFeedback = "❌ \(error.localizedDescription)" }
      }
    }

    // MARK: Load Users

    private func loadUsers() async {
      do {
        let (data, resp) = try await URLSession.shared.data(from: AppConfig.apiBase.appendingPathComponent("api/users"))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
          throw URLError(.badServerResponse)
        }

        var list: [SBUser] = []
        if let decoded = try? JSONDecoder().decode([SBUser].self, from: data) {
          list = decoded
        } else if let decoded = try? JSONDecoder().decode(UsersPayload.self, from: data), let u = decoded.users {
          list = u
        }

        list.sort { $0.email < $1.email }
        await MainActor.run {
          self.users = list
          self.totalUsers = list.count
        }

      } catch {
        await MainActor.run {
          self.users = []
          self.totalUsers = 0
        }
      }
    }

    // MARK: Helpers

    private func inviteExpiry(_ iso: String?) -> String {
      guard let s = iso else { return "—" }
      let df = ISO8601DateFormatter()
      if let d = df.date(from: s) {
        return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
      }
      return "—"
    }

    private func parseAnyDate(_ s: String) -> Date? {
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let d = iso.date(from: s) { return d }
      iso.formatOptions = [.withInternetDateTime]
      if let d = iso.date(from: s) { return d }

      if let n = Double(s) {
        if n > 1_000_000_000_000 {
          return Date(timeIntervalSince1970: n / 1000)
        } else if n > 1_000_000_000 {
          return Date(timeIntervalSince1970: n)
        }
      }

      let df = DateFormatter()
      df.locale = .init(identifier: "en_US_POSIX")
      df.timeZone = .init(secondsFromGMT: 0)
      df.dateFormat = "yyyy-MM-dd HH:mm:ss"
      return df.date(from: s)
    }

    private func shortDate(_ iso: String) -> String {
      guard let d = parseAnyDate(iso) else { return "N/A" }
      return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
    }

    private func futureShortDate(_ iso: String) -> String {
      guard let d = parseAnyDate(iso), d > Date() else { return "—" }
      return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
    }
  }
