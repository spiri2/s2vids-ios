//
//  DashboardViewModel.swift
//  s2vids
//

import Foundation
import SwiftUI
import AVKit

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

  // MARK: - Networking helpers

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

  func bootstrap(email: String, isAdmin: Bool, subscriptionStatus: String, isTrialing: Bool) {
    self.email = email
    self.isAdmin = isAdmin
    self.subscriptionStatus = subscriptionStatus
    self.isTrialing = isTrialing
    self.showGettingStarted = !(isTrialing || subscriptionStatus == "active") && !isAdmin

    Task {
      await probeAnnouncements()
      await probeJellyfin()
      await loadTrending()
      await loadRecent()
      await loadUpcoming()
    }
  }

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
