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

// Flexible Jellyfin log decoder
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

// MARK: - View

struct AdminView: View {
  let email: String
  private var isAdmin: Bool { AppConfig.adminEmails.contains(email.lowercased()) }

  // Data
  @State private var users: [SBUser] = []
  @State private var totalUsers = 0
  @State private var stripeByEmail: [String: StripeStatus] = [:]
  @State private var search = ""

  // Master Invite
  @State private var masterInvite: MasterInvite?
  @State private var miLoading = false
  @State private var miError = ""

  // Activity
  @State private var jfActivity: [JellyfinActivityEntry] = []
  @State private var jfLoading = false
  @State private var jfError = ""

  // Trials
  @State private var selectedUserEmail: String?
  @State private var trialDays = 7
  @State private var savingTrialFor: String?
  @State private var trialFeedback = ""

  // Settings / Menu
  @State private var showSettings = false
  @Environment(\.dismiss) private var dismiss

  // Per-user actions state
  @State private var deletingUser: String? = nil
  @State private var banningUser: String? = nil
  @State private var unbanningUser: String? = nil
  @State private var resettingInvites: String? = nil
  @State private var resetStatus: [String: String] = [:]

  // Confirmations
  private enum PendingAction: Identifiable {
    case delete(id: String, email: String)
    case ban(id: String, email: String)
    case unban(id: String, email: String)
    case resetInvites(id: String)

    var id: String {
      switch self {
      case .delete(let id, _): return "del:\(id)"
      case .ban(let id, _): return "ban:\(id)"
      case .unban(let id, _): return "unban:\(id)"
      case .resetInvites(let id): return "reset:\(id)"
      }
    }
  }
  @State private var pending: PendingAction? = nil

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
            header.zIndex(1000)
            topGrid
            usersSection
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
    .confirmationDialog("", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
      switch pending {
      case .delete(let id, let em):
        Button("Delete \(em)", role: .destructive) { Task { await deleteUser(id, email: em) } }
      case .ban(let id, let em):
        Button("Ban \(em)", role: .destructive) { Task { await banUser(id) } }
      case .unban(let id, _):
        Button("Unban") { Task { await unbanUser(id) } }
      case .resetInvites(let id):
        Button("Reset invites", role: .destructive) { Task { await resetInvites(id) } }
      case .none:
        EmptyView()
      }
    } message: {
      switch pending {
      case .delete(_, let em): Text("Delete user \(em)? This cannot be undone.")
      case .ban(_, let em): Text("Ban \(em)? They will be unable to sign in.")
      case .unban: Text("Unban this user?")
      case .resetInvites: Text("Reset this user’s invites?")
      case .none: Text("")
      }
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
      .zIndex(1000) // make sure dropdown is in front
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color.black.opacity(0.65)) // solid look under the dropdown
    )
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
          HStack {
            Text("Code: ").font(.caption.bold())
            Text(inv.code).font(.caption.monospaced())
            Spacer()
            Button { UIPasteboard.general.string = inv.code } label: {
              Text("Copy").font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.4), in: Capsule())
            }
          }
          Text("Uses: \(inv.uses ?? 0)\(inv.max_uses != nil ? " / \(inv.max_uses!)" : "")").font(.caption)
          Text("Expires: \(inviteExpiry(inv.expires_at))").font(.caption)

          HStack {
            Button { Task { await revokeMasterInvite() } } label: {
              Text("Revoke").font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.red.opacity(0.6), in: Capsule())
            }
            Spacer()
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
        VStack(alignment: .leading, spacing: 6) {
          ForEach(jfActivity.prefix(8)) { e in
            let when = e.Date.flatMap(parseAnyDate)
            let ts = when.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
            Text("• \((e.Overview ?? e.Name ?? e.MediaType ?? "Activity").trimmingCharacters(in: .whitespaces))")
              .font(.caption).foregroundColor(.white)
            Text("\(e.UserName ?? "") \(e.MediaType ?? "")  \(ts)")
              .font(.caption2).foregroundColor(.white.opacity(0.8))
          }
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

  // MARK: Users

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
            userCard(u)
          }
        }
      }
    }
    .padding(.top, 6)
  }

  private func userCard(_ user: SBUser) -> some View {
    let s = stripeByEmail[user.email]
    let renew: Date? = s?.current_period_end.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
    let hasActive = (s?.active == true) || s?.status == "active" || s?.status == "trialing"

    let banned: Bool = {
      guard let b = user.banned_until, let d = parseAnyDate(b) else { return false }
      return d > Date()
    }()

    return VStack(alignment: .leading, spacing: 6) {
      Text(user.email).font(.subheadline.weight(.semibold)).foregroundColor(.white)

      if let d = user.user_metadata?.discord, !d.isEmpty {
        HStack { Text("Discord:").bold(); Text(d) }.font(.caption).foregroundColor(.white.opacity(0.9))
      }

      HStack { Text("Role:").bold(); Text(user.user_metadata?.role ?? "user") }
        .font(.caption).foregroundColor(.white.opacity(0.9))

      HStack { Text("Created:").bold()
        Text(user.created_at.flatMap { shortDate($0) } ?? "N/A")
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack { Text("Last Sign-in:").bold()
        Text(user.last_sign_in_at.flatMap { shortDate($0) } ?? "N/A")
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack(spacing: 4) {
        Text("Subscription:").bold()
        Text(s?.status ?? "—")
        if hasActive, let r = renew {
          Text("• Renews \(DateFormatter.localizedString(from: r, dateStyle: .short, timeStyle: .short))")
        }
      }.font(.caption).foregroundColor(.white.opacity(0.9))

      HStack { Text("Jellyfin Trial Until:").bold()
        Text(user.user_metadata?.jellyfin_trial_until.flatMap { futureShortDate($0) } ?? "—")
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

        Button { pending = .resetInvites(id: user.id) } label: {
          Text(resetButtonTitle(user.id)).font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.yellow.opacity(0.7), in: Capsule())
        }.disabled(resettingInvites == user.id)

        Spacer()

        if !banned {
          Button {
            pending = .ban(id: user.id, email: user.email)
          } label: {
            Text(banningUser == user.id ? "Banning…" : "Ban")
              .font(.caption.bold())
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(Color.red.opacity(0.8), in: Capsule())
          }.disabled(banningUser == user.id)
        } else {
          Button {
            pending = .unban(id: user.id, email: user.email)
          } label: {
            Text(unbanningUser == user.id ? "Unbanning…" : "Unban")
              .font(.caption.bold())
              .padding(.horizontal, 10).padding(.vertical, 6)
              .overlay(Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1))
          }.disabled(unbanningUser == user.id)
        }

        Button {
          pending = .delete(id: user.id, email: user.email)
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

  // MARK: Trial Sheet

  private var trialSheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Set Jellyfin Trial").font(.headline).foregroundColor(.white)
      Text(selectedUserEmail ?? "").font(.subheadline).foregroundColor(.white.opacity(0.9)).lineLimit(2)
      Text("Days").font(.caption.bold()).foregroundColor(.white.opacity(0.9))
      Stepper(value: $trialDays, in: 1...31) { Text("\(trialDays) day\(trialDays == 1 ? "" : "s")") }
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
      if !trialFeedback.isEmpty { Text(trialFeedback).foregroundColor(.white) }
    }
    .padding()
    .background(Color.black.opacity(0.9))
  }

  // MARK: Networking

  private func reloadAll() async {
    await loadUsers()
    await fetchMasterInvite()
    await loadJellyfinActivity()
  }

  private func fetchMasterInvite() async {
    await MainActor.run { miLoading = true; miError = ""; masterInvite = nil }
    defer { Task { await MainActor.run { miLoading = false } } }
    do {
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/master-invite"),
                                resolvingAgainstBaseURL: false)!
      comps.queryItems = [.init(name: "ts", value: "\(Int(Date().timeIntervalSince1970))")]
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
        await MainActor.run { miError = "Failed to load master invite" }
        return
      }
      let p = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run { masterInvite = p.invite }
    } catch {
      await MainActor.run { miError = (error as NSError).localizedDescription }
    }
  }

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
      let p = try JSONDecoder().decode(MasterInvitePayload.self, from: data)
      await MainActor.run { masterInvite = p.invite }
    } catch {
      await MainActor.run { miError = (error as NSError).localizedDescription }
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
      await MainActor.run { miError = (error as NSError).localizedDescription }
    }
  }

  private func loadJellyfinActivity() async {
    await MainActor.run { jfLoading = true; jfError = ""; jfActivity = [] }
    defer { Task { await MainActor.run { jfLoading = false } } }

    let candidates = [
      "api/jellyfin/activity",
      "api/jellyfin/activity/",
      "api/jellyseerr/activity"
    ]

    func hit(_ path: String) async throws -> [JellyfinActivityEntry] {
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent(path),
                                resolvingAgainstBaseURL: false)!
      comps.queryItems = [
        .init(name: "limit", value: "50"),
        .init(name: "ts", value: "\(Int(Date().timeIntervalSince1970))")
      ]
      var req = URLRequest(url: comps.url!)
      req.cachePolicy = .reloadIgnoringLocalCacheData
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

      if let rows = try? JSONDecoder().decode([JellyfinActivityEntry].self, from: data) {
        return rows
      }
      if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let arr = any["Items"] as? [[String: Any]] ?? any["items"] as? [[String: Any]] {
        let re = try JSONSerialization.data(withJSONObject: arr)
        if let rows = try? JSONDecoder().decode([JellyfinActivityEntry].self, from: re) { return rows }
      }
      if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let err = any["error"] as? String, !err.isEmpty {
        await MainActor.run { jfError = err }
      }
      throw URLError(.cannotParseResponse)
    }

    for p in candidates {
      do {
        let items = try await hit(p)
        await MainActor.run { jfActivity = items }
        return
      } catch { /* try next */ }
    }

    await MainActor.run {
      jfActivity = []
      if jfError.isEmpty { jfError = "Failed to load activity." }
    }
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
        await MainActor.run { trialFeedback = "✅ Trial updated" }
        try? await Task.sleep(nanoseconds: 900_000_000)
        await MainActor.run { selectedUserEmail = nil; trialFeedback = "" }
        await loadUsers()
      } else {
        let msg = String(data: data, encoding: .utf8) ?? "Failed"
        await MainActor.run { trialFeedback = "❌ \(msg)" }
      }
    } catch {
      await MainActor.run { trialFeedback = "❌ \((error as NSError).localizedDescription)" }
    }
  }

  private func loadUsers() async {
    do {
      let url = AppConfig.apiBase.appendingPathComponent("api/users")
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

      var list: [SBUser] = []
      if let decoded = try? JSONDecoder().decode([SBUser].self, from: data) {
        list = decoded
      } else if let decoded = try? JSONDecoder().decode(UsersPayload.self, from: data), let u = decoded.users {
        list = u
      } else if
        let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let u = any["users"] as? [[String: Any]] {
        let re = try JSONSerialization.data(withJSONObject: u)
        list = (try? JSONDecoder().decode([SBUser].self, from: re)) ?? []
      }

      list.sort { $0.email < $1.email }
      await MainActor.run {
        self.users = list
        self.totalUsers = list.count
      }

      // (Optional) load Stripe statuses in parallel – keep, or remove if not used
      await withTaskGroup(of: (String, StripeStatus?).self) { group in
        for u in list {
          group.addTask {
            let base = AppConfig.apiBase.appendingPathComponent("api/get-stripe-status")
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
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
        for await (em, st) in group { if let st { next[em] = st } }
        await MainActor.run { self.stripeByEmail = next }
      }

    } catch {
      await MainActor.run { self.users = []; self.totalUsers = 0 }
    }
  }

  private func deleteUser(_ userId: String, email: String) async {
    await MainActor.run { deletingUser = userId }
    defer { Task { await MainActor.run { deletingUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/delete-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      _ = try await URLSession.shared.data(for: req)
      await loadUsers()
    } catch { }
  }

  private func resetInvites(_ userId: String) async {
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
      await MainActor.run {
        resetStatus[userId] = (resp as? HTTPURLResponse)?.statusCode == 200 ? "✅ Reset!" : "❌ Failed"
      }
    } catch {
      await MainActor.run { resetStatus[userId] = "❌ Failed" }
    }
  }

  private func banUser(_ userId: String) async {
    await MainActor.run { banningUser = userId }
    defer { Task { await MainActor.run { banningUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/ban-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      let (_, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 {
        // optimistic UI flip
        await MainActor.run {
          if let idx = users.firstIndex(where: { $0.id == userId }) {
            let u = users[idx]
            let future = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 60*60*24*365*50)) // +50y
            users[idx] = SBUser(id: u.id, email: u.email, user_metadata: u.user_metadata,
                                created_at: u.created_at, last_sign_in_at: u.last_sign_in_at, banned_until: future)
          }
        }
      }
    } catch { }
  }

  private func unbanUser(_ userId: String) async {
    await MainActor.run { unbanningUser = userId }
    defer { Task { await MainActor.run { unbanningUser = nil } } }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/unban-user"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try JSONSerialization.data(withJSONObject: ["id": userId])
      let (_, resp) = try await URLSession.shared.data(for: req)
      if (resp as? HTTPURLResponse)?.statusCode == 200 {
        await MainActor.run {
          if let idx = users.firstIndex(where: { $0.id == userId }) {
            let u = users[idx]
            users[idx] = SBUser(id: u.id, email: u.email, user_metadata: u.user_metadata,
                                created_at: u.created_at, last_sign_in_at: u.last_sign_in_at, banned_until: nil)
          }
        }
      }
    } catch { }
  }

  // MARK: Date helpers

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
    if let d = df.date(from: s) { return d }

    return nil
  }

  private func shortDate(_ iso: String) -> String {
    guard let d = parseAnyDate(iso) else { return "N/A" }
    return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
  }
  private func futureShortDate(_ iso: String) -> String {
    guard let d = parseAnyDate(iso), d > Date() else { return "—" }
    return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
  }
  private func inviteExpiry(_ iso: String?) -> String {
    guard let iso, let d = parseAnyDate(iso) else { return "—" }
    let left = Int((d.timeIntervalSinceNow / 3600).rounded())
    return "\(DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)) (\(max(0,left))h left)"
  }
  private func resetButtonTitle(_ userId: String) -> String {
    if resettingInvites == userId { return "…" }
    if let t = resetStatus[userId], !t.isEmpty { return t }
    return "Invites"
  }
}
