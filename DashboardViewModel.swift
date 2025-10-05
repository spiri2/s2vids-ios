//
//  DashboardViewModel.swift
//  s2vids
//

import Foundation
import SwiftUI
import AVKit

// MARK: - Models

struct TrendingItem: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let jellyfinUrl: String?
  let poster: String?
  let year: Int?
}

struct UpcomingItem: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let year: Int?
  let poster: String?
  let trailerUrl: String?
  let mediaType: String?   // "movie" | "tv"
}

struct RecentItem: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let year: Int?
  let poster: String?
}

// Stripe status payload from your Next.js API
private struct StripeStatusPayload: Decodable {
  let active: Bool?
  let status: String?
  let current_period_end: Int?
  let trial_end: Int?
  let cancel_at: Int?
  let canceled_at: Int?
  let cancel_at_period_end: Bool?
  let plan: String?
}

@MainActor
final class DashboardViewModel: ObservableObject {
  // profile / gating
  @Published var email: String = ""
  @Published var isAdmin: Bool = false
  @Published var subscriptionStatus: String = ""
  @Published var isTrialing: Bool = false

  // UI state
  @Published var showGettingStarted = false
  @Published var showAnnouncements = false
  @Published var showDonate = false
  @Published var hasNewAnnouncements = true

  // Jellyfin
  @Published var hasJellyfinAccount = false
  @Published var creatingJellyfin = false
  @Published var jellyfinPassword = ""
  @Published var jellyfinPassword2 = ""
  @Published var jellyfinError = ""
  @Published var jellyfinSuccess = ""

  // Lists
  @Published var trending: [TrendingItem] = []
  @Published var recent: [RecentItem] = []
  @Published var upcoming: [UpcomingItem] = []
  @Published var loadingTrending = true
  @Published var loadingRecent = true
  @Published var loadingUpcoming = true

  // Info / Player
  @Published var infoOpen = false
  @Published var infoTitle = ""
  @Published var infoYear: Int?
  @Published var playerOpen = false
  @Published var playerTitle = ""
  @Published var playerStream: URL?
  @Published var player = AVPlayer()

  // MARK: - Helpers

  private func apiURL(_ path: String, query: [URLQueryItem]? = nil) -> URL {
    var comps = URLComponents(
      url: AppConfig.apiBase.appendingPathComponent(path),
      resolvingAgainstBaseURL: false
    )!
    if let query {
      comps.queryItems = (comps.queryItems ?? []) + query
    }
    return comps.url!
  }

  // MARK: - Bootstrap

  func bootstrap(email: String, isAdmin: Bool, subscriptionStatus: String, isTrialing: Bool) {
    self.email = email
    self.isAdmin = isAdmin
    self.subscriptionStatus = subscriptionStatus
    self.isTrialing = isTrialing
    // initial gate (will be refined after Stripe check)
    self.showGettingStarted = !(isTrialing || subscriptionStatus == "active") && !isAdmin

    Task {
      await refreshStripeStatus()   // <--- Stripe check first
      await probeAnnouncements()
      await probeJellyfin()
      await loadTrending()
      await loadRecent()
      await loadUpcoming()
    }
  }

  // MARK: - Stripe

  /// Hits /api/get-stripe-status?email=... and updates gating flags.
  func refreshStripeStatus() async {
    guard !email.isEmpty else { return }
    let url = apiURL("api/get-stripe-status", query: [URLQueryItem(name: "email", value: email)])

    do {
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard let http = resp as? HTTPURLResponse else { return }

      if http.statusCode == 404 {
        // No customer—treat as no active sub
        subscriptionStatus = ""
        isTrialing = false
        showGettingStarted = !isAdmin
        return
      }

      guard http.statusCode == 200 else {
        // Any other error => don't block the user, but keep gate visible if not admin
        subscriptionStatus = ""
        isTrialing = false
        showGettingStarted = !isAdmin
        return
      }

      let status = try JSONDecoder().decode(StripeStatusPayload.self, from: data)

      // Update state from payload
      subscriptionStatus = status.status ?? ""
      let now = Date().timeIntervalSince1970
      let trialActiveFromStripe = (status.trial_end ?? 0) > Int(now)
      let isActive = (status.active ?? false) || ["active", "past_due"].contains(subscriptionStatus)
      isTrialing = subscriptionStatus == "trialing" || trialActiveFromStripe

      // Gate: hide Getting Started if active or trialing (or admin)
      showGettingStarted = !(isActive || isTrialing) && !isAdmin

    } catch {
      // Network failure—leave existing values, but keep Getting Started for non-admins
      showGettingStarted = !(isTrialing || subscriptionStatus == "active") && !isAdmin
    }
  }

  // MARK: - Announcements

  func probeAnnouncements() async {
    let url = apiURL("api/announcement")
    var req = URLRequest(url: url); req.httpMethod = "GET"
    do {
      _ = try await URLSession.shared.data(for: req)
      hasNewAnnouncements = true
    } catch {
      hasNewAnnouncements = true
    }
  }

  // MARK: - Jellyfin

  func probeJellyfin() async {
    guard !email.isEmpty else { return }
    let url = apiURL("api/jellyfin-user-exists")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": email], options: [])
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { hasJellyfinAccount = false; return }
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      hasJellyfinAccount = (obj?["exists"] as? Bool) ?? false
    } catch {
      hasJellyfinAccount = false
    }
  }

  func createOrResetJellyfin() async {
    jellyfinError = ""; jellyfinSuccess = ""
    guard !email.isEmpty else { jellyfinError = "Missing email"; return }
    guard jellyfinPassword.count >= 6 else { jellyfinError = "Password must be at least 6 chars"; return }
    guard jellyfinPassword == jellyfinPassword2 else { jellyfinError = "Passwords do not match."; return }

    creatingJellyfin = true
    defer { creatingJellyfin = false }

    let url = apiURL("api/check-or-create-jellyfin")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: [
      "email": email,
      "username": email,
      "password": jellyfinPassword
    ], options: [])

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let ok = (resp as? HTTPURLResponse)?.statusCode == 200
      if ok {
        hasJellyfinAccount = true
        jellyfinSuccess = "Jellyfin account created!"
      } else {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        jellyfinError = (obj?["error"] as? String) ?? "Failed to create Jellyfin account."
      }
    } catch {
      jellyfinError = error.localizedDescription
    }
  }

  // MARK: - Content loads

  func loadTrending() async {
    loadingTrending = true
    defer { loadingTrending = false }
    let url = apiURL("api/jellyseerr/trending", query: [ URLQueryItem(name: "limit", value: "20") ])
    do {
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { trending = []; return }
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let items = obj?["items"] as? [[String: Any]] ?? []
      self.trending = items.compactMap { d in
        TrendingItem(
          id: String(describing: d["id"] ?? UUID().uuidString),
          title: (d["title"] as? String) ?? "",
          jellyfinUrl: d["jellyfinUrl"] as? String,
          poster: d["poster"] as? String,
          year: d["year"] as? Int
        )
      }
    } catch {
      trending = []
    }
  }

  func loadRecent() async {
    loadingRecent = true
    defer { loadingRecent = false }
    let url = apiURL("api/jellyfin/recent", query: [ URLQueryItem(name: "limit", value: "40") ])
    do {
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { recent = []; return }
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let items = obj?["items"] as? [[String: Any]] ?? []
      recent = items.compactMap { d in
        RecentItem(
          id: String(describing: d["id"] ?? UUID().uuidString),
          title: (d["title"] as? String) ?? "",
          year: d["year"] as? Int,
          poster: d["poster"] as? String
        )
      }
    } catch {
      recent = []
    }
  }

  func loadUpcoming() async {
    loadingUpcoming = true
    defer { loadingUpcoming = false }
    let url = apiURL("api/jellyseerr/upcoming", query: [ URLQueryItem(name: "limit", value: "20") ])
    do {
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { upcoming = []; return }
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let items = obj?["items"] as? [[String: Any]] ?? []
      upcoming = items.compactMap { d in
        UpcomingItem(
          id: String(describing: d["id"] ?? UUID().uuidString),
          title: (d["title"] as? String) ?? "",
          year: d["year"] as? Int,
          poster: d["poster"] as? String,
          trailerUrl: d["trailerUrl"] as? String,
          mediaType: d["mediaType"] as? String
        )
      }
    } catch {
      upcoming = []
    }
  }

  // MARK: - Player

  func openPlayer(title: String, streamURL: URL) {
    playerTitle = title
    playerStream = streamURL
    player.replaceCurrentItem(with: AVPlayerItem(url: streamURL))
    player.play()
    playerOpen = true
  }

  func closePlayer() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    playerOpen = false
  }
}
