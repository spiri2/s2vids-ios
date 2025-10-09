//
//  DashboardView.swift
//  s2vids
//

import SwiftUI
import AVKit

// MARK: - Small helpers shared with MoviesView

/// Base used across the app (keeps this file self-contained).
private func apiBaseURL() -> URL {
  // If your AppConfig is present, prefer it. Otherwise fall back to Info.plist or prod host.
  if let base = (AppConfig.apiBase as URL?) { return base }
  if let s = Bundle.main.object(forInfoDictionaryKey: "S2_API_BASE") as? String,
     let u = URL(string: s) { return u }
  return URL(string: "https://s2vids.org/")!
}

/// Resolve absolute/relative stream paths into a playable URL.
private func resolveStreamURL(_ raw: String) -> URL? {
  if let u = URL(string: raw), let scheme = u.scheme?.lowercased(),
     scheme == "https" || scheme == "http" || scheme == "file" {
    return u
  }
  if raw.hasPrefix("/") {
    return URL(string: raw, relativeTo: apiBaseURL())?.absoluteURL
  }
  return apiBaseURL().appendingPathComponent(raw).absoluteURL
}

// MARK: - Welcome (Loading) Screen

private struct WelcomeScreen: View {
  let show: Bool

  var body: some View {
    Group {
      if show {
        ZStack {
          Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

          VStack(spacing: 14) {
            // Gradient “s2vids” title
            LinearGradient(
              colors: [Color(red: 0.67, green: 0.86, blue: 1.0), Color(red: 0.70, green: 0.73, blue: 1.0)],
              startPoint: .leading, endPoint: .trailing
            )
            .mask(
              Text("s2vids")
                .font(.system(size: 44, weight: .black, design: .default))
                .tracking(0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)

            // Animated loading spinner centered
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle())
              .scaleEffect(1.2)
              .tint(.white)

            Text("Your passport to premium cinema.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(Color(red: 0.73, green: 0.78, blue: 0.98).opacity(0.9))
              .padding(.top, 2)
          }
          .padding()
          .transition(.opacity.combined(with: .scale))
        }
      }
    }
    .animation(.easeInOut(duration: 0.35), value: show)
  }
}

// MARK: - Dashboard

struct DashboardView: View {
  @StateObject private var vm = DashboardViewModel()

  // Inject after login:
  var email: String
  var isAdmin: Bool
  var subscriptionStatus: String
  var isTrialing: Bool

  // Resolved from API so gating is correct even if props are placeholders
  @State private var resolvedStatus: String = ""
  @State private var resolvedTrialing: Bool = false
  @State private var accessResolved = false

  // Info sheet state (avoid UIApplication.present)
  struct InfoPayload: Identifiable {
    let id = UUID()
    let title: String
    let year: Int?
    let posterURL: String
  }
  @State private var infoPayload: InfoPayload?

  // Settings / Movies / Discover / TV Shows / Admin
  @State private var showSettings = false
  @State private var showMovies = false
  @State private var showDiscover = false
  @State private var showTvShows = false
  @State private var showAdmin = false                 // ✅

  // Local media player (ported from MoviesView)
  @State private var playerOpen = false
  @State private var player: AVPlayer? = nil
  @State private var itemStatusObserver: NSKeyValueObservation? = nil
  @State private var playerFailObserver: NSObjectProtocol? = nil
  @State private var playerFailed = false
  @State private var playerStatusMsg = ""
  @State private var httpWarning = false

  private var isPlayerError: Bool { playerFailed && !playerStatusMsg.isEmpty }
  private var showHttpWarning: Bool { httpWarning && !isPlayerError }

  // Hardcoded admin email override + prop
  private var effectiveIsAdmin: Bool {
    isAdmin || email.lowercased() == "mspiri2@outlook.com"
  }

  // Loading overlay should show while any primary loads are in-flight
  private var showLoadingOverlay: Bool {
    !accessResolved || vm.loadingTrending || vm.loadingRecent || vm.loadingUpcoming
  }

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(spacing: 20) {
          header

          carousel(
            title: "Trending Movies",
            loading: vm.loadingTrending,
            emptyText: "No trending items available right now.",
            items: vm.trending.map {
              PosterItem(id: $0.id, title: $0.title, year: $0.year,
                         poster: posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { title, year in playOrShowOnboarding(title: title, year: year) },
            onInfo: { title, year in showInfo(title, year: year) }
          )

          carousel(
            title: "Recently Added",
            loading: vm.loadingRecent,
            emptyText: "No recent movies right now.",
            items: vm.recent.map {
              PosterItem(id: $0.id, title: $0.title, year: $0.year,
                         poster: $0.poster ?? posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { title, year in playOrShowOnboarding(title: title, year: year) },
            onInfo: { title, year in showInfo(title, year: year) }
          )

          carousel(
            title: "Upcoming Movies",
            loading: vm.loadingUpcoming,
            emptyText: "No upcoming titles right now.",
            items: vm.upcoming.map {
              PosterItem(id: String($0.id), title: $0.title, year: $0.year,
                         poster: $0.poster ?? posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { _, _ in /* requests not supported here */ },
            onInfo: { title, year in showInfo(title, year: year) }
          )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
      // ⬇️ Pull-to-refresh
      .refreshable {
        await refreshDashboard()
      }

      // ⬆️ Overlay loading screen (s2vids) that stays until content resolves
      WelcomeScreen(show: showLoadingOverlay)
        .zIndex(120) // above everything
        .allowsHitTesting(showLoadingOverlay)
    }
    .preferredColorScheme(.dark)
    // Run initial load via the same async path used by refresh
    .task {
      await initialBootstrap()
    }

    // Getting Started
    .sheet(isPresented: $vm.showGettingStarted) {
      GettingStartedSheet(showNoSubNotice: !hasAccess) {
        vm.showGettingStarted = false
      }
      .modifier(DetentsCompatMediumLarge())
    }

    // Announcements
    .sheet(isPresented: $vm.showAnnouncements) {
      AnnouncementsSheet(isAdmin: effectiveIsAdmin) {
        vm.showAnnouncements = false
      }
      .modifier(DetentsCompatLarge())
    }

    // Player — upgraded (error banner + HTTP warning + cleanup on dismiss)
    .fullScreenCover(
      isPresented: Binding(get: { playerOpen && hasAccess },
                           set: { playerOpen = $0 }),
      onDismiss: { stopPlayerObservers() }
    ) {
      ZStack(alignment: .topTrailing) {
        if let p = player {
          VideoPlayer(player: p).ignoresSafeArea()
        } else {
          Color.black.ignoresSafeArea()
        }

        VStack(alignment: .trailing, spacing: 8) {
          if isPlayerError {
            Text(playerStatusMsg)
              .font(.footnote).bold()
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(Color.red, in: Capsule())
          } else if showHttpWarning {
            Text("HTTP stream — configure ATS or use HTTPS")
              .font(.footnote).bold()
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(Color.orange, in: Capsule())
          }
          Button("Close") { closePlayer() }
            .padding(12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding()
      }
    }

    // Info sheet (SwiftUI-native)
    .sheet(item: $infoPayload) { payload in
      MovieInfoSheet(title: payload.title, year: payload.year, posterURL: payload.posterURL)
        .modifier(DetentsCompatMediumLarge())
    }

    // Settings sheet (opened from dropdown)
    .sheet(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: effectiveIsAdmin)
    }

    // Movies page (opened from dropdown)
    .fullScreenCover(isPresented: $showMovies) {
      MoviesView(
        email: email,
        isAdmin: effectiveIsAdmin,
        subscriptionStatus: effectiveStatus,
        isTrialing: effectiveTrialing
      )
    }

    // Discover page (opened from dropdown)
    .fullScreenCover(isPresented: $showDiscover) {
      DiscoverView(
        email: email,
        isAdmin: effectiveIsAdmin,
        subscriptionStatus: effectiveStatus,
        isTrialing: effectiveTrialing
      )
    }

    // TV Shows page (opened from dropdown)
    .fullScreenCover(isPresented: $showTvShows) {
      TvShowsView(
        email: email,
        isAdmin: effectiveIsAdmin,
        subscriptionStatus: effectiveStatus,
        isTrialing: effectiveTrialing
      )
    }

    // Admin page (opened from dropdown)
    .fullScreenCover(isPresented: $showAdmin) {
      AdminView(email: email)
    }
  }

  // Prefer resolved values from API; fall back to incoming props until resolved.
  private var effectiveStatus: String { accessResolved ? resolvedStatus : subscriptionStatus }
  private var effectiveTrialing: Bool { accessResolved ? resolvedTrialing : isTrialing }
  private var hasAccess: Bool { effectiveTrialing || effectiveStatus == "active" || effectiveIsAdmin }

  // MARK: - Bootstrap / Refresh

  private func initialBootstrap() async {
    await MainActor.run {
      vm.bootstrap(email: email,
                   isAdmin: effectiveIsAdmin,
                   subscriptionStatus: subscriptionStatus,
                   isTrialing: isTrialing)
    }
    await resolveAccessAsync()
  }

  private func refreshDashboard() async {
    // Re-run VM bootstrap to refetch lists, then re-check access from Stripe
    await MainActor.run {
      vm.bootstrap(email: email,
                   isAdmin: effectiveIsAdmin,
                   subscriptionStatus: subscriptionStatus,
                   isTrialing: isTrialing)
    }
    await resolveAccessAsync()
  }

  private func resolveAccessAsync() async {
    guard !email.isEmpty else {
      await MainActor.run { accessResolved = true }
      return
    }
    do {
      var comps = URLComponents(
        url: AppConfig.apiBase.appendingPathComponent("api/get-stripe-status"),
        resolvingAgainstBaseURL: false
      )!
      comps.queryItems = [URLQueryItem(name: "email", value: email)]
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      if (resp as? HTTPURLResponse)?.statusCode == 200,
         let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let status = (obj["status"] as? String) ?? ""
        let active = (obj["active"] as? Bool) ?? false
        let trialEnd = (obj["trial_end"] as? Int) ?? 0
        await MainActor.run {
          resolvedStatus = active ? "active" : status
          resolvedTrialing = (status == "trialing") || trialEnd > 0
          accessResolved = true
          if !hasAccess {
            playerOpen = false
            vm.showGettingStarted = true
          }
        }
      } else {
        await MainActor.run {
          resolvedStatus = ""
          resolvedTrialing = false
          accessResolved = true
        }
      }
    } catch {
      await MainActor.run {
        resolvedStatus = ""
        resolvedTrialing = false
        accessResolved = true
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      Text("s2vids Dashboard")
        .font(.title2)
        .fontWeight(.bold)
      Spacer()

      if !hasAccess && !effectiveIsAdmin {
        Button {
          vm.showGettingStarted = true
        } label: {
          Label("Help", systemImage: "questionmark.circle")
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(red: 0.07, green: 0.09, blue: 0.17), in: Capsule())
        }
      }

      Button {
        vm.showAnnouncements = true
      } label: {
        Image(systemName: "megaphone")
          .padding(8)
          .background(Color(red: 0.07, green: 0.09, blue: 0.17), in: Circle())
          .overlay(alignment: .topTrailing) {
            if vm.hasNewAnnouncements {
              Circle().fill(Color.red)
                .frame(width: 8, height: 8)
                .offset(x: 4, y: -4)
            }
          }
      }

      Menu {
        Button("Donate") { vm.showDonate = true }
      } label: {
        Image(systemName: "ellipsis.circle")
          .padding(8)
          .background(Color(red: 0.07, green: 0.09, blue: 0.17), in: Circle())
      }

      // User dropdown (overlay; no layout shift)
      UserMenuButton(
        email: email,
        isAdmin: effectiveIsAdmin,
        onRequireAccess: { vm.showGettingStarted = true },
        onLogout: { /* hook up to your logout */ },
        onOpenSettings: { showSettings = true },   // open Settings
        onOpenMovies: { showMovies = true },       // open Movies
        onOpenDiscover: { showDiscover = true },   // open Discover
        onOpenTvShows: { showTvShows = true },     // open TV Shows
        onOpenAdmin: { showAdmin = true }          // open Admin
      )
    }
    .foregroundColor(.white)
    .zIndex(10_000) // keep menu above posters
  }

  // MARK: Carousels / Poster

  struct PosterItem: Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let poster: String
  }

  private func carousel(
    title: String,
    loading: Bool,
    emptyText: String,
    items: [PosterItem],
    onPlay: @escaping (_ title: String, _ year: Int?) -> Void,
    onInfo: @escaping (_ title: String, _ year: Int?) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline).fontWeight(.bold)

      if loading {
        Text("Loading…").foregroundColor(.secondary)
      } else if items.isEmpty {
        Text(emptyText).foregroundColor(.secondary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(items) { it in
              ZStack {
                AsyncImage(url: URL(string: it.poster)) { phase in
                  switch phase {
                  case .success(let img):
                    img.resizable()
                      .aspectRatio(2/3, contentMode: .fill)
                      .frame(width: 140, height: 210)
                      .clipped()
                  case .failure(_):
                    Color.gray.frame(width: 140, height: 210)
                  case .empty:
                    Color.black.opacity(0.2).frame(width: 140, height: 210)
                  @unknown default:
                    Color.gray.frame(width: 140, height: 210)
                  }
                }

                Button {
                  onPlay(it.title, it.year)
                } label: {
                  Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.black.opacity(0.60), in: Circle())
                }
              }
              .overlay(alignment: .bottomTrailing) {
                Button {
                  onInfo(it.title, it.year)
                } label: {
                  Image(systemName: "ellipsis")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(.black.opacity(0.60), in: Circle())
                }
                .padding(8)
              }
              .overlay(alignment: .bottomLeading) {
                Text(it.title)
                  .font(.caption)
                  .lineLimit(2)
                  .frame(width: 120, alignment: .leading)
                  .padding(8)
              }
              .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .padding(.top, 4)
  }

  private func posterURL(for title: String, year: Int?) -> String {
    var c = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/poster"),
                          resolvingAgainstBaseURL: false)!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    return c.string ?? ""
  }

  // MARK: Actions

  private func playOrShowOnboarding(title: String, year: Int?) {
    guard hasAccess else {
      playerOpen = false
      vm.showGettingStarted = true
      return
    }
    openByTitle(title, year: year)
  }

  private func showInfo(_ title: String, year: Int?) {
    infoPayload = .init(title: title, year: year, posterURL: posterURL(for: title, year: year))
  }

  /// Finds the stream by title and opens the upgraded player.
  private func openByTitle(_ title: String, year: Int?) {
    guard hasAccess else {
      vm.showGettingStarted = true
      return
    }
    Task {
      do {
        let url = AppConfig.apiBase.appendingPathComponent("api/movies/list")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let simp = title.lowercased()

        let match = arr.first(where: {
          guard let t = $0["title"] as? String else { return false }
          return t.lowercased() == simp
        }) ?? arr.first(where: {
          guard let t = $0["title"] as? String else { return false }
          return t.lowercased().contains(simp)
        })

        guard let m = match, let stream = m["streamUrl"] as? String else { return }
        openPlayer(stream: stream)
      } catch { }
    }
  }

  // MARK: Player logic (ported from MoviesView)

  private func openPlayer(stream: String, resumeAt: Double = 0) {
    playerFailed = false
    playerStatusMsg = ""
    httpWarning = false
    itemStatusObserver?.invalidate()
    itemStatusObserver = nil

    guard let url = resolveStreamURL(stream) else {
      playerFailed = true
      playerStatusMsg = "Bad or relative stream URL."
      playerOpen = true
      return
    }

    if url.scheme?.lowercased() == "http" { httpWarning = true }

    let asset = AVURLAsset(url: url, options: nil)
    let item = AVPlayerItem(asset: asset)
    let p = AVPlayer(playerItem: item)
    player = p
    playerOpen = true

    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif

    itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { itm, _ in
      DispatchQueue.main.async {
        switch itm.status {
        case .readyToPlay:
          if resumeAt > 1 {
            let t = CMTimeMakeWithSeconds(resumeAt, preferredTimescale: 600)
            p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
          } else {
            p.play()
          }
        case .failed:
          self.playerFailed = true
          self.playerStatusMsg = itm.error?.localizedDescription ?? "Failed to load stream."
          if let el = itm.errorLog() { print("📼 errorLog:", el.events) }
          if let al = itm.accessLog() { print("📼 accessLog:", al.events) }
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    playerFailObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: item,
      queue: .main
    ) { n in
      self.playerFailed = true
      let err = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)
      self.playerStatusMsg = err?.localizedDescription ?? "Failed to play to end."
      print("❌ FailedToPlayToEnd:", err ?? "nil")
    }
  }

  private func closePlayer() {
    stopPlayerObservers()
    player?.pause()
    player = nil
    playerOpen = false
  }

  private func stopPlayerObservers() {
    itemStatusObserver?.invalidate()
    itemStatusObserver = nil
    if let token = playerFailObserver {
      NotificationCenter.default.removeObserver(token)
      playerFailObserver = nil
    }
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }
}

// MARK: - Movie Info Sheet (OMDb)

struct MovieInfoSheet: View {
  let title: String
  let year: Int?
  let posterURL: String

  @State private var plot: String = "Loading info..."
  @State private var rating: String = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 16) {
          AsyncImage(url: URL(string: posterURL)) { img in
            img.resizable().scaledToFit()
          } placeholder: {
            Color.gray.opacity(0.2)
          }
          .frame(height: 280)

          Text("\(title)\(year != nil ? " (\(year!))" : "")")
            .font(.headline)
            .multilineTextAlignment(.center)

          if !rating.isEmpty {
            Text("⭐️ IMDb \(rating)")
              .font(.subheadline)
              .foregroundColor(.yellow)
          }

          Text(plot)
            .font(.body)
            .multilineTextAlignment(.leading)
            .padding(.top, 4)

          if let imdbURL = imdbURL {
            Link("View on IMDb", destination: imdbURL)
              .buttonStyle(.bordered)
              .padding(.top, 6)
          }

          Spacer()
        }
        .padding()
      }
      .navigationTitle("Info")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
      .task { await loadInfo() }
    }
  }

  private var imdbURL: URL? {
    if let id = cachedImdbID { return URL(string: "https://www.imdb.com/title/\(id)/") }
    return URL(string: "https://www.imdb.com/find?q=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
  }

  @State private var cachedImdbID: String?

  private func loadInfo() async {
    guard let base = URL(string: "https://www.omdbapi.com/") else { return }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      .init(name: "apikey", value: AppConfig.omdbKey),
      .init(name: "t", value: title),
      .init(name: "plot", value: "full")
    ]
    if let y = year { components.queryItems?.append(.init(name: "y", value: String(y))) }

    do {
      let (data, _) = try await URLSession.shared.data(from: components.url!)
      if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        plot = (obj["Plot"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "No plot available."
        rating = obj["imdbRating"] as? String ?? ""
        cachedImdbID = obj["imdbID"] as? String
      } else {
        plot = "Unable to fetch movie details."
      }
    } catch {
      plot = "Failed to load movie information."
    }
  }
}

// MARK: - Simple Sheets (iOS 15+ friendly)

struct GettingStartedSheet: View {
  var showNoSubNotice: Bool
  var onClose: () -> Void

  var body: some View {
    NavigationView {
      VStack(alignment: .leading, spacing: 12) {
        if showNoSubNotice {
          Text("You currently have no active subscription.")
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        }
        Text("Getting started").font(.headline).fontWeight(.bold)
        Group {
          Text("1. Select Subscribe.")
          Text("2. After subscribing, return here and refresh the page.")
        }
        .foregroundColor(.secondary)

        Link("Subscribe",
             destination: URL(string: "https://buy.stripe.com/aFa14o8B758CeTnfrjfw406")!)
          .buttonStyle(.borderedProminent)

        Spacer()
      }
      .padding()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) { Button("Close", action: onClose) }
      }
    }
  }
}

struct AnnouncementsSheet: View {
  var isAdmin: Bool
  var onClose: () -> Void
  @State private var items: [[String:Any]] = []
  @State private var loading = true

  var body: some View {
    NavigationView {
      Group {
        if loading {
          ProgressView("Loading…")
        } else if items.isEmpty {
          Text("No announcements yet.").foregroundColor(.secondary)
        } else {
          List {
            ForEach(0..<items.count, id: \.self) { i in
              let a = items[i]
              VStack(alignment: .leading, spacing: 6) {
                Text((a["message"] as? String) ?? "—")
                Text((a["author"] as? String) ?? "Admin")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .listRowBackground(Color(red:0.08, green:0.10, blue:0.17))
            }
          }
          .listStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .navigationTitle("Announcements")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Close", action: onClose)
        }
      }
      .task { await load() }
    }
  }

  func load() async {
    loading = true
    defer { loading = false }
    let url = AppConfig.apiBase.appendingPathComponent("api/announcement")
    do {
      let (data, resp) = try await URLSession.shared.data(from: url)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
      let arr = try JSONSerialization.jsonObject(with: data) as? [[String:Any]] ?? []
      items = arr
    } catch { items = [] }
  }
}

// MARK: - Detents Compatibility Helpers (iOS 16+ only; safe on iOS 15)

private struct DetentsCompatMediumLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.presentationDetents([.medium, .large])
    } else {
      content
    }
  }
}

private struct DetentsCompatLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.presentationDetents([.large])
    } else {
      content
    }
  }
}

// MARK: - User Dropdown (with Movies, Discover & TV Shows & Admin callbacks)

struct UserMenuButton: View {
  let email: String
  let isAdmin: Bool
  let onRequireAccess: () -> Void
  let onLogout: () -> Void
  let onOpenSettings: () -> Void
  let onOpenMovies: () -> Void
  let onOpenDiscover: () -> Void
  let onOpenTvShows: () -> Void
  let onOpenAdmin: () -> Void          // ✅

  @State private var open = false
  @State private var hasAccess = false
  @State private var loading = false
  @State private var errorText: String?

  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      toggleOpen()
    } label: {
      Image(systemName: "person.circle.fill")
        .font(.system(size: 26, weight: .regular))
        .foregroundColor(.white)
        .frame(width: 32, height: 32)
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      if open {
        VStack(spacing: 0) {
          HStack {
            Text(email.isEmpty ? "Signed in" : email)
              .font(.footnote)
              .foregroundColor(.gray)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer()
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.25))

          Divider().background(Color.gray.opacity(0.4))

          VStack(spacing: 0) {
            Row(icon: "rectangle.grid.2x2", title: "Dashboard") { open = false }
            Row(icon: "safari", title: "Discover") {
              open = false
              onOpenDiscover()
            }

            Row(icon: "film", title: "Movies") {
              open = false
              onOpenMovies()
            }

            Row(icon: "tv", title: "TV Shows") {
              open = false
              onOpenTvShows()
            }
            Row(icon: "dot.radiowaves.left.and.right", title: "Live TV") { open = false }

            // (Removed: Launch Jellyfin, Request Media, TV Show Calendar)

            Row(icon: "gear", title: "Settings") {
              open = false
              onOpenSettings()
            }

            if isAdmin || email.lowercased() == "mspiri2@outlook.com" {
              Row(icon: "shield.lefthalf.filled", title: "Admin", tint: .yellow) {
                open = false
                onOpenAdmin()
              }
            }

            Row(icon: "arrow.backward.square", title: "Log Out", tint: .red) {
              open = false
              onLogout()
            }
          }

          if loading || errorText != nil {
            Divider().background(Color.gray.opacity(0.4))
            HStack(spacing: 8) {
              if loading { ProgressView().scaleEffect(0.6) }
              Text(loading ? "Checking subscription…" : (errorText ?? ""))
                .font(.caption)
                .foregroundColor(.gray)
              Spacer()
            }
            .padding(10)
          }
        }
        .frame(width: 230)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.09, green: 0.11, blue: 0.17)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35)))
        .offset(y: 36)
        .zIndex(100_000)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
      }
    }
  }

  private func Row(icon: String, title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
    Button(action: { action() }) {
      HStack(spacing: 10) {
        Image(systemName: icon).frame(width: 16)
        Text(title).font(.subheadline)
        Spacer()
      }
      .foregroundColor(tint ?? .white)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func toggleOpen() {
    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
      open.toggle()
    }
    if open { Task { await checkStripeAccess() } }
  }

  private func goOrWarn(_ go: () -> Void) {
    if hasAccess || isAdmin || email.lowercased() == "mspiri2@outlook.com" {
      go()
    } else {
      onRequireAccess()
    }
  }

  private func statusAllowsAccess(_ status: String) -> Bool {
    let s = status.lowercased()
    return s == "active" || s == "trialing"
  }

  private func checkStripeAccess() async {
    guard !email.isEmpty else { hasAccess = false; return }
    loading = true
    errorText = nil
    defer { loading = false }

    do {
      var comps = URLComponents(
        url: AppConfig.apiBase.appendingPathComponent("api/get-stripe-status"),
        resolvingAgainstBaseURL: false
      )!
      comps.queryItems = [ URLQueryItem(name: "email", value: email) ]

      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
        hasAccess = false
        errorText = "Unable to check subscription."
        return
      }
      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let status = (obj?["status"] as? String) ?? ""
      let activeFlag = (obj?["active"] as? Bool) ?? false
      hasAccess = activeFlag || statusAllowsAccess(status)
    } catch {
      hasAccess = false
      errorText = "Network error."
    }
  }
}
