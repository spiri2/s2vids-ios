//
//  MoviesView.swift
//  s2vids
//

import SwiftUI
import AVKit
import Foundation

// MARK: - Local API base shim (keeps this file self-contained)

private func apiBaseURL() -> URL {
  if let s = Bundle.main.object(forInfoDictionaryKey: "S2_API_BASE") as? String,
     let u = URL(string: s) { return u }
  // ✅ Fallback updated to the production host used by the web app
  return URL(string: "https://s2vids.org/")!
}

// MARK: - Models matching your web types

private struct Movie: Identifiable, Decodable, Hashable {
  let id: String
  let title: String
  let posterUrl: String?
  let streamUrl: String
  let year: Int?
}

private struct MoviesTrendingItem: Identifiable, Decodable, Hashable {
  let id: String
  let title: String
  let year: Int?
  let poster: String?
}

private struct StripeStatusResponse: Decodable {
  let status: String?
  let active: Bool?
  let current_period_end: Int?
  let cancel_at_period_end: Bool?
  let trial_end: Int?
}

// Local watch progress (per movie)
private struct WatchProgress: Codable, Hashable {
  var position: Double
  var duration: Double
  var updatedAt: Date
}

// MARK: - Movies View

struct MoviesView: View {
  // Inject after login like DashboardView
  let email: String
  let isAdmin: Bool
  let subscriptionStatus: String
  let isTrialing: Bool

  @Environment(\.dismiss) private var dismiss   // used to go back to Dashboard

  // Access resolution (same approach as DashboardView)
  @State private var resolvedStatus: String = ""
  @State private var resolvedTrialing: Bool = false
  @State private var accessResolved = false

  // Data
  @State private var allMovies: [Movie] = []
  @State private var trending: [MoviesTrendingItem] = []
  @State private var freeMonthly: [Movie] = []

  @State private var loadingAll = true
  @State private var loadingTrending = true
  @State private var loadingFree = true

  // UI
  @State private var query: String = ""
  @State private var page: Int = 1
  private let perPage = 60

  // Info + player
  @State private var infoTitle: String = ""
  @State private var infoOpen = false

  @State private var playerOpen = false
  @State private var playerTitle = ""
  @State private var playerYear: Int?
  @State private var playerStream = ""
  @State private var currentMovieId = ""
  @State private var player: AVPlayer? = nil
  @State private var timeObserver: Any?

  // Getting started (gate)
  @State private var showGettingStarted = false

  // Settings
  @State private var showSettings = false     // will be shown full-screen

  // Favorites (persisted per email)
  private var favsKey: String { "s2vids:favorites:\(email.isEmpty ? "anon" : email)" }
  @State private var favorites: Set<String> = []
  @State private var showFavoritesOnly = false

  // Debug (optional; helps if things still look empty)
  @State private var lastMoviesRawJSON: String = ""

  // MARK: Access helpers

  private var effectiveStatus: String { accessResolved ? resolvedStatus : subscriptionStatus }
  private var effectiveTrialing: Bool { accessResolved ? resolvedTrialing : isTrialing }
  private var hasAccess: Bool {
    effectiveTrialing || effectiveStatus.lowercased() == "active" || effectiveIsAdmin
  }
  private var effectiveIsAdmin: Bool {
    isAdmin || email.lowercased() == "mspiri2@outlook.com"
  }

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(spacing: 16) {
          header
          searchBar

          if hasAccess, !continueWatchingItems.isEmpty {
            continueWatchingSection
          }

          trendingSection

          if !hasAccess {
            VStack(spacing: 6) {
              Text("Free to Watch")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
              if loadingFree {
                Text("Updating free selection…")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.7))
              }
            }
            .padding(.top, 6)
          }

          allMoviesSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      bootstrap()
      loadFavorites()
      loadAll()
      loadTrending()
      loadFree()
    }
    // Getting Started
    .sheet(isPresented: $showGettingStarted) {
      GettingStartedSheet(showNoSubNotice: !hasAccess) {
        showGettingStarted = false
      }
      .modifier(MoviesDetentsCompatMediumLarge())
    }
    // Info
    .sheet(isPresented: $infoOpen) {
      MovieInfoSheet(title: infoTitle, year: nil,
                     posterURL: posterURL(for: infoTitle, year: nil)?.absoluteString ?? "")
        .modifier(MoviesDetentsCompatMediumLarge())
    }
    // Settings — FULL SCREEN now
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: effectiveIsAdmin)
    }
    // Player
    .fullScreenCover(isPresented: $playerOpen, onDismiss: stopObserving) {
      ZStack(alignment: .topTrailing) {
        if let p = player {
          VideoPlayer(player: p)
            .ignoresSafeArea()
            .onAppear { startObserving(for: currentMovieId) }
        } else {
          Color.black.ignoresSafeArea()
        }
        Button("Close") { closePlayer() }
          .padding(12)
          .background(.ultraThinMaterial, in: Capsule())
          .padding()
      }
    }
  }

  // MARK: Header + Search

  private var header: some View {
    HStack(spacing: 12) {
      Text("Movies")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)

      Spacer()

      // Favorites toggle — placed LEFT of dropdown/menu button
      Button {
        showFavoritesOnly.toggle()
        page = 1
      } label: {
        Image(systemName: showFavoritesOnly ? "heart.circle.fill" : "heart.circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(showFavoritesOnly ? .red : .white)
      }

      UserMenuButton(
        email: email,
        isAdmin: effectiveIsAdmin,
        onRequireAccess: { showGettingStarted = true },
        onLogout: {
          // Minimal sign-out: clear user-local data & notify app
          UserDefaults.standard.removeObject(forKey: "s2vids:favorites:\(email.isEmpty ? "anon" : email)")
          UserDefaults.standard.removeObject(forKey: "s2vids:progress:\(email.isEmpty ? "anon" : email)")
          NotificationCenter.default.post(name: .init("S2VidsDidLogout"), object: nil)
        },
        onOpenSettings: { showSettings = true }, // full-screen
        onOpenMovies: { dismiss() },             // back to Dashboard
        onOpenDiscover: {
          dismiss()
          NotificationCenter.default.post(name: Notification.Name("S2OpenDiscover"), object: nil)
        }
      )
    }
    .zIndex(10_000) // keep menu above posters
  }

  private var searchBar: some View {
    HStack {
      TextField("Search titles…", text: $query)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.08, green: 0.10, blue: 0.17)))
        .foregroundColor(.white)
      if !query.isEmpty {
        Button("Clear") { query = ""; page = 1 }
          .buttonStyle(MoviesSecondaryButtonStyle())
      }
    }
  }

  // MARK: Trending

  private var trendingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      pillHeader(text: "Trending Movies", tint: .cyan)

      Group {
        if loadingTrending {
          Text("Loading trending…").foregroundColor(.white.opacity(0.8)).font(.subheadline)
        } else if trending.isEmpty {
          Text("No trending right now.").foregroundColor(.white.opacity(0.8)).font(.subheadline)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(trending) { it in
                let posterStr = posterURL(for: it.title, year: it.year, fallback: it.poster)?.absoluteString ?? ""
                posterCard(
                  title: it.title,
                  year: it.year,
                  poster: posterStr,
                  isFav: isFavoriteByTitle(it.title, year: it.year),
                  onFav: {
                    if let m = matchMovieByTitle(it.title, year: it.year) {
                      toggleFavorite(m.id)
                    }
                  },
                  onPlay: {
                    if !hasAccess { showGettingStarted = true; return }
                    if let m = matchMovieByTitle(it.title, year: it.year) {
                      openPlayer(for: m)
                    } else {
                      Task { await reloadAndFindPlay(title: it.title, year: it.year) }
                    }
                  },
                  onInfo: {
                    infoTitle = it.title
                    infoOpen = true
                  }
                )
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
  }

  // MARK: All Movies (3 per row + real posters + favorites filter)

  private var allMoviesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      pillHeader(text: showFavoritesOnly ? "Favorites" : "All Movies", tint: showFavoritesOnly ? .red : .purple)

      Group {
        if loadingAll || (!hasAccess && loadingFree) {
          Text("Loading library…").foregroundColor(.white.opacity(0.85))
        } else {
          // Pagination controls
          HStack {
            Spacer()
            Button("Prev") { page = max(1, page - 1) }
              .buttonStyle(MoviesSecondaryButtonStyle())
            Text("Page \(page) of \(max(1, Int(ceil(Double(filtered.count)/Double(perPage)))))")
              .font(.caption).foregroundColor(.white.opacity(0.8))
            Button("Next") {
              let maxPage = max(1, Int(ceil(Double(filtered.count)/Double(perPage))))
              page = min(maxPage, page + 1)
            }
            .buttonStyle(MoviesSecondaryButtonStyle())
          }

          if filtered.isEmpty {
            // Tiny debug echo so we know we *did* fetch something
            if !lastMoviesRawJSON.isEmpty {
              Text("No movies after filtering. Server responded with \(lastMoviesRawJSON.count) bytes.")
                .font(.caption)
                .foregroundColor(.yellow.opacity(0.9))
                .padding(.bottom, 6)
            }
            Text(showFavoritesOnly ? "No favorites yet." : "No movies found.")
              .foregroundColor(.white.opacity(0.85))
          } else {
            GeometryReader { proxy in
              let totalSpacing: CGFloat = 12 * 2
              let cardW = (proxy.size.width - totalSpacing) / 3.0
              let cardH = cardW * 1.5

              LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
              ) {
                ForEach(paged) { m in
                  VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                      let url = posterURL(for: m.title, year: m.year, explicit: m.posterUrl)
                      AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                          img.resizable().scaledToFill().frame(width: cardW, height: cardH).clipped()
                        case .failure(_):
                          Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                            .overlay(Image(systemName: "film").font(.title2).foregroundColor(.white.opacity(0.6)))
                        case .empty:
                          Color.black.opacity(0.2).frame(width: cardW, height: cardH)
                        @unknown default:
                          Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                        }
                      }
                      .clipShape(RoundedRectangle(cornerRadius: 10))

                      Button {
                        if !hasAccess && !freeMonthly.contains(where: { $0.id == m.id }) {
                          showGettingStarted = true
                          return
                        }
                        openPlayer(for: m)
                      } label: {
                        Image(systemName: "play.fill")
                          .foregroundColor(.white)
                          .padding(10)
                          .background(.black.opacity(0.6), in: Circle())
                      }
                    }
                    .overlay(alignment: .topLeading) {
                      Button {
                        toggleFavorite(m.id)
                      } label: {
                        Image(systemName: "heart.fill")
                          .foregroundColor(favorites.contains(m.id) ? .red : .white)
                          .font(.system(size: 12))
                          .padding(8)
                          .background(.black.opacity(0.6), in: Circle())
                      }
                      .padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                      Button {
                        infoTitle = m.title; infoOpen = true
                      } label: {
                        Image(systemName: "ellipsis")
                          .foregroundColor(.white)
                          .padding(8)
                          .background(.black.opacity(0.6), in: Circle())
                      }
                      .padding(6)
                    }

                    Text(m.title)
                      .font(.system(size: 13))
                      .lineLimit(2)
                      .frame(width: cardW - 12, alignment: .leading)
                  }
                }
              }
              .frame(width: proxy.size.width, height: gridHeight(itemCount: paged.count, cardH: cardH))
            }
            .frame(height: dynamicGridOuterHeight(itemCount: paged.count))
          }
        }
      }
    }
  }

  /// Height helpers so GeometryReader sizes correctly.
  private func rows(for count: Int) -> Int { max(1, Int(ceil(Double(count) / 3.0))) }
  private func gridHeight(itemCount: Int, cardH: CGFloat) -> CGFloat {
    let r = rows(for: itemCount)
    return CGFloat(r) * (cardH + 34 + 12) // card + title + spacing
  }
  private func dynamicGridOuterHeight(itemCount: Int) -> CGFloat {
    let r = rows(for: itemCount)
    return CGFloat(r) * 260
  }

  // MARK: Sections + Components

  private func pillHeader(text: String, tint: Color) -> some View {
    HStack {
      Spacer()
      Text(text)
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(tint.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          Capsule()
            .fill(tint.opacity(0.15))
            .overlay(Capsule().stroke(tint.opacity(0.25)))
        )
      Spacer()
    }
  }

  private func posterCard(
    title: String,
    year: Int?,
    poster: String,
    isFav: Bool,
    onFav: @escaping () -> Void,
    onPlay: @escaping () -> Void,
    onInfo: @escaping () -> Void
  ) -> some View {
    let w: CGFloat = 140
    let h: CGFloat = 210
    return ZStack {
      AsyncImage(url: URL(string: poster)) { phase in
        switch phase {
        case .success(let img):
          img.resizable().scaledToFill().frame(width: w, height: h).clipped()
        case .failure(_):
          Color.gray.opacity(0.25).frame(width: w, height: h)
        case .empty:
          Color.black.opacity(0.2).frame(width: w, height: h)
        @unknown default:
          Color.gray.opacity(0.25).frame(width: w, height: h)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))

      Button(action: onPlay) {
        Image(systemName: "play.fill")
          .foregroundColor(.white)
          .padding(10)
          .background(.black.opacity(0.6), in: Circle())
      }
    }
    .overlay(alignment: .topLeading) {
      Button(action: onFav) {
        Image(systemName: "heart.fill")
          .foregroundColor(isFav ? .red : .white)
          .font(.system(size: 12))
          .padding(8)
          .background(.black.opacity(0.6), in: Circle())
      }
      .padding(6)
    }
    .overlay(alignment: .topTrailing) {
      Button(action: onInfo) {
        Image(systemName: "ellipsis")
          .foregroundColor(.white)
          .padding(8)
          .background(.black.opacity(0.6), in: Circle())
      }
      .padding(6)
    }
    .overlay(alignment: .bottomLeading) {
      Text(title)
        .font(.caption)
        .lineLimit(2)
        .frame(width: w - 20, alignment: .leading)
        .padding(8)
    }
    .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
  }

  // MARK: Filtering / Paging

  private var baseList: [Movie] {
    hasAccess ? allMovies : freeMonthly.filter { m in
      let tset = Set(trending.map { canonical($0.title) })
      return !tset.contains(canonical(m.title))
    }
  }

  private var displayList: [Movie] {
    if showFavoritesOnly {
      let favs = favorites
      return baseList.filter { favs.contains($0.id) }
    } else {
      return baseList
    }
  }

  private var filtered: [Movie] {
    let q = canonical(query)
    guard !q.isEmpty else { return displayList }
    return displayList.filter { canonical($0.title).contains(q) }
  }

  private var paged: [Movie] {
    let start = (page - 1) * perPage
    guard start >= 0 else { return [] }
    return Array(filtered.dropFirst(start).prefix(perPage))
  }

  // MARK: Continue Watching (local store)

  private var progressKey: String { "s2vids:progress:\(email.isEmpty ? "anon" : email)" }
  @State private var progress: [String: WatchProgress] = [:] // movieId -> progress

  private var continueWatchingItems: [Movie] {
    let ids = progress
      .filter { (_, v) in v.duration > 0 && v.position / v.duration < 0.97 }
      .sorted { $0.value.updatedAt > $1.value.updatedAt }
      .map { $0.key }
    return ids.compactMap { id in allMovies.first(where: { $0.id == id }) }
  }

  private var continueWatchingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      pillHeader(text: "Continue Watching", tint: .green)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(continueWatchingItems) { m in
            let prog = progress[m.id]
            let pct = (prog?.duration ?? 0) > 0 ? (prog!.position / prog!.duration) : 0
            let w: CGFloat = 140, h: CGFloat = 210
            ZStack {
              AsyncImage(url: posterURL(for: m.title, year: m.year, explicit: m.posterUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill().frame(width: w, height: h).clipped()
                case .failure(_): Color.gray.opacity(0.25).frame(width: w, height: h)
                case .empty: Color.black.opacity(0.2).frame(width: w, height: h)
                @unknown default: Color.gray.opacity(0.25).frame(width: w, height: h)
                }
              }
              .clipShape(RoundedRectangle(cornerRadius: 10))

              Button { openPlayer(for: m, resumeAt: prog?.position ?? 0) } label: {
                Image(systemName: "play.fill")
                  .foregroundColor(.white)
                  .padding(10)
                  .background(.black.opacity(0.6), in: Circle())
              }
            }
            .overlay(alignment: .bottomLeading) {
              Text(m.title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: w - 20, alignment: .leading)
                .padding(8)
            }
            .overlay(alignment: .bottom) {
              ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 6)
                Rectangle().fill(Color.green).frame(width: CGFloat(pct) * w, height: 6)
              }
            }
            .overlay(alignment: .topTrailing) {
              Button {
                progress[m.id] = nil
                saveProgress()
              } label: {
                Image(systemName: "checkmark")
                  .foregroundColor(.green)
                  .padding(8)
                  .background(.black.opacity(0.6), in: Circle())
              }
              .padding(6)
            }
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
          }
        }
        .padding(.vertical, 2)
      }
    }
  }

  // MARK: Favorites

  private func loadFavorites() {
    if let data = UserDefaults.standard.data(forKey: favsKey),
       let arr = try? JSONDecoder().decode([String].self, from: data) {
      favorites = Set(arr)
    }
  }

  private func saveFavorites() {
    let arr = Array(favorites)
    if let data = try? JSONEncoder().encode(arr) {
      UserDefaults.standard.set(data, forKey: favsKey)
    }
  }

  private func toggleFavorite(_ id: String) {
    if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    saveFavorites()
  }

  private func isFavoriteByTitle(_ title: String, year: Int?) -> Bool {
    if let m = matchMovieByTitle(title, year: year) { return favorites.contains(m.id) }
    return false
  }

  // MARK: Player + Progress

  private func openPlayer(for m: Movie, resumeAt: Double = 0) {
    guard hasAccess || freeMonthly.contains(where: { $0.id == m.id }) else {
      showGettingStarted = true
      return
    }
    playerTitle = m.title
    playerYear = m.year
    playerStream = m.streamUrl
    currentMovieId = m.id

    let item = AVPlayerItem(url: URL(string: m.streamUrl)!)
    let p = AVPlayer(playerItem: item)
    player = p
    playerOpen = true

    if resumeAt > 1 {
      NotificationCenter.default.addObserver(forName: .AVPlayerItemNewAccessLogEntry, object: item, queue: .main) { _ in
        let seconds = CMTimeMakeWithSeconds(resumeAt, preferredTimescale: 600)
        p.seek(to: seconds, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
          p.play()
        }
      }
    } else {
      p.play()
    }
  }

  private func closePlayer() {
    stopObserving()
    player?.pause()
    player = nil
    playerOpen = false
  }

  private func startObserving(for movieId: String) {
    guard let p = player else { return }
    let interval = CMTimeMake(value: 1, timescale: 2) // 0.5s
    timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
      guard let item = p.currentItem else { return }
      let pos = CMTimeGetSeconds(time)
      let dur = CMTimeGetSeconds(item.duration)
      guard dur.isFinite, dur > 0, pos.isFinite, pos >= 0 else { return }
      var prog = self.progress[movieId] ?? WatchProgress(position: 0, duration: dur, updatedAt: Date())
      prog.position = pos
      prog.duration = dur
      prog.updatedAt = Date()
      self.progress[movieId] = prog
      self.saveProgress()
      if pos / dur >= 0.97 {
        self.progress[movieId] = nil
        self.saveProgress()
      }
    }
  }

  private func stopObserving() {
    if let obs = timeObserver, let p = player {
      p.removeTimeObserver(obs)
    }
    timeObserver = nil
  }

  private func saveProgress() {
    if let data = try? JSONEncoder().encode(progress) {
      UserDefaults.standard.set(data, forKey: progressKey)
    }
  }

  private func loadProgress() {
    if let data = UserDefaults.standard.data(forKey: progressKey),
       let map = try? JSONDecoder().decode([String: WatchProgress].self, from: data) {
      progress = map
    }
  }

  // MARK: Networking

  private func loadAll() {
    loadingAll = true
    Task {
      defer { loadingAll = false }
      do {
        let url = apiBaseURL().appendingPathComponent("api/movies/list")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
          allMovies = []
          return
        }

        // Keep a copy for quick debug
        lastMoviesRawJSON = String(data: data, encoding: .utf8) ?? ""

        // ✅ Be liberal in what we accept — array OR wrapped + snake_case keys
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let rows: [[String: Any]]
        if let arr = parsed as? [[String: Any]] {
          rows = arr
        } else if let dict = parsed as? [String: Any] {
          rows =
            (dict["items"] as? [[String: Any]]) ??
            (dict["results"] as? [[String: Any]]) ??
            []
        } else {
          rows = []
        }

        let mapped: [Movie] = rows.compactMap { o in
          // id: "id" | "movie_id"
          let id = (o["id"] as? String)
              ?? (o["movie_id"] as? String)
              ?? (o["id"] as? Int).map(String.init)
              ?? (o["movie_id"] as? Int).map(String.init)

          // title
          let title = (o["title"] as? String)

          // posterUrl: "posterUrl" | "poster_url"
          let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)

          // streamUrl: "streamUrl" | "stream_url"
          let stream = (o["streamUrl"] as? String) ?? (o["stream_url"] as? String)

          // year may be string or int
          let year: Int? = {
            if let y = o["year"] as? Int { return y }
            if let ys = o["year"] as? String, let yi = Int(ys) { return yi }
            return nil
          }()

          guard let idSafe = id, let titleSafe = title, let streamSafe = stream else { return nil }
          return Movie(id: idSafe, title: titleSafe, posterUrl: poster, streamUrl: streamSafe, year: year)
        }

        // If JSON was already a typed array that matches Movie, fall back to decoding directly
        if mapped.isEmpty {
          if let arr = try? JSONDecoder().decode([Movie].self, from: data) {
            allMovies = arr
          } else {
            allMovies = []
          }
        } else {
          allMovies = mapped
        }

        loadProgress()
      } catch {
        allMovies = []
      }
    }
  }

  private func loadTrending() {
    loadingTrending = true
    Task {
      defer { loadingTrending = false }
      do {
        var comps = URLComponents(
          url: apiBaseURL().appendingPathComponent("api/jellyseerr/trending"),
          resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "limit", value: "40")]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { trending = []; return }
        struct Wrap: Decodable { let items: [MoviesTrendingItem]? }
        trending = (try? JSONDecoder().decode(Wrap.self, from: data).items) ?? []
      } catch {
        trending = []
      }
    }
  }

  private func loadFree() {
    loadingFree = true
    Task {
      defer { loadingFree = false }
      do {
        var comps = URLComponents(
          url: apiBaseURL().appendingPathComponent("api/free-monthly"),
          resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "meta", value: nil)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { freeMonthly = []; return }
        let any = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let arr = any as? [[String: Any]] {
          rows = arr
        } else if let dict = any as? [String: Any], let arr = dict["items"] as? [[String: Any]] {
          rows = arr
        } else {
          rows = []
        }
        freeMonthly = rows.compactMap { o in
          let id = (o["id"] as? String) ?? (o["movie_id"] as? String)
          let title = o["title"] as? String
          let stream = (o["streamUrl"] as? String) ?? (o["stream_url"] as? String)
          let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)
          let year: Int? = {
            if let y = o["year"] as? Int { return y }
            if let ys = o["year"] as? String, let yi = Int(ys) { return yi }
            return nil
          }()
          guard let id, let title, let stream else { return nil }
          return Movie(id: id, title: title, posterUrl: poster, streamUrl: stream, year: year)
        }
      } catch {
        freeMonthly = []
      }
    }
  }

  private func bootstrap() {
    guard !email.isEmpty else { accessResolved = true; return }
    Task {
      do {
        var comps = URLComponents(
          url: apiBaseURL().appendingPathComponent("api/get-stripe-status"),
          resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "email", value: email)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        if (resp as? HTTPURLResponse)?.statusCode == 200 {
          let s = try? JSONDecoder().decode(StripeStatusResponse.self, from: data)
          let status = (s?.status ?? "")
          let active = s?.active ?? false
          let trialEnd = s?.trial_end ?? 0
          resolvedStatus = active ? "active" : status
          resolvedTrialing = (status == "trialing") || trialEnd > 0
        }
      } catch {
        resolvedStatus = ""
        resolvedTrialing = false
      }
      accessResolved = true
    }
  }

  // MARK: Helpers

  private func matchMovieByTitle(_ title: String, year: Int?) -> Movie? {
    let want = canonical(title)
    if let y = year {
      if let exact = allMovies.first(where: { canonical($0.title) == want && ($0.year ?? -1) == y }) { return exact }
    }
    return allMovies.first(where: { canonical($0.title) == want }) ??
           allMovies.first(where: { canonical($0.title).contains(want) })
  }

  private func reloadAndFindPlay(title: String, year: Int?) async {
    do {
      var comps = URLComponents(
        url: apiBaseURL().appendingPathComponent("api/movies/list"),
        resolvingAgainstBaseURL: false
      )!
      comps.queryItems = [URLQueryItem(name: "reload", value: "1")]
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
      let parsed = try JSONSerialization.jsonObject(with: data, options: [])
      let rows: [[String: Any]]
      if let arr = parsed as? [[String: Any]] { rows = arr }
      else if let dict = parsed as? [String: Any],
              let arr = dict["items"] as? [[String: Any]] ?? dict["results"] as? [[String: Any]] { rows = arr }
      else { rows = [] }
      let list: [Movie] = rows.compactMap { o in
        let id = (o["id"] as? String) ?? (o["movie_id"] as? String)
        let title = o["title"] as? String
        let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)
        let stream = (o["streamUrl"] as? String) ?? (o["stream_url"] as? String)
        let year: Int? = {
          if let y = o["year"] as? Int { return y }
          if let ys = o["year"] as? String, let yi = Int(ys) { return yi }
          return nil
        }()
        guard let id, let title, let stream else { return nil }
        return Movie(id: id, title: title, posterUrl: poster, streamUrl: stream, year: year)
      }
      allMovies = list
      if let m = matchMovieByTitle(title, year: year) { openPlayer(for: m) }
    } catch { }
  }

  /// Prefer an explicit poster only if it's an absolute http(s) URL; otherwise use /api/poster.
  private func posterURL(for title: String, year: Int?, fallback: String? = nil, explicit: String? = nil) -> URL? {
    if let explicit = explicit,
       let u = URL(string: explicit),
       let scheme = u.scheme,
       (scheme == "http" || scheme == "https") {
      return u
    }
    var c = URLComponents(
      url: apiBaseURL().appendingPathComponent("api/poster"),
      resolvingAgainstBaseURL: false
    )!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    if let u = c.url { return u }
    if let f = fallback, let u = URL(string: f) { return u }
    return nil
  }

  // Canonicalize like web
  private func canonical(_ s: String) -> String {
    var t = s.lowercased()
    t = t.replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
    t = t.replacingOccurrences(of: "&", with: " and ")
    for ch in [":", "-", "–", "—", "_", "/", ".", ",", "!", "?", "(", ")", "\""] {
      t = t.replacingOccurrences(of: ch, with: " ")
    }
    while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    for art in ["the ", "a ", "an "] {
      if t.hasPrefix(art) { t = String(t.dropFirst(art.count)) ; break }
    }
    // Handle trailing ", The" style just like web
    if let m = t.range(of: #"^(.+),\s+(the|a|an)$"#, options: .regularExpression) {
      let parts = t[m].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      if parts.count == 2 { t = "\(parts[1]) \(parts[0])" }
    }
    return t
  }
}

// MARK: - Local helpers (detents + buttons) so we don't depend on other files

private struct MoviesDetentsCompatMediumLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.presentationDetents([.medium, .large])
    } else {
      content
    }
  }
}

private struct MoviesSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.3)))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}
