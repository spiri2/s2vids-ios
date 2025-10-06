//
//  MoviesView.swift
//  s2vids
//

import SwiftUI
import AVKit

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

  // Favorites (persisted per email)
  private var favsKey: String { "s2vids:favorites:\(email.isEmpty ? "anon" : email)" }
  @State private var favorites: Set<String> = []

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
      UserMenuButton(
        email: email,
        isAdmin: effectiveIsAdmin,
        onRequireAccess: { showGettingStarted = true },
        onLogout: { /* hook logout */ },
        onOpenSettings: { /* push settings from parent */ }
      )
    }
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

  // MARK: All Movies

  private var allMoviesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      pillHeader(text: "All Movies", tint: .purple)

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
            Text("No movies found.").foregroundColor(.white.opacity(0.85))
          } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
              ForEach(paged) { m in
                VStack(alignment: .leading, spacing: 6) {
                  ZStack {
                    AsyncImage(url: posterURL(for: m.title, year: m.year, explicit: m.posterUrl)) { phase in
                      switch phase {
                      case .success(let img):
                        img.resizable().aspectRatio(2/3, contentMode: .fill)
                      case .failure(_):
                        Color.gray.opacity(0.2)
                      case .empty:
                        Color.black.opacity(0.2)
                      @unknown default:
                        Color.gray.opacity(0.2)
                      }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Play center
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
                }
              }
            }
          }
        }
      }
    }
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
    ZStack {
      AsyncImage(url: URL(string: poster)) { phase in
        switch phase {
        case .success(let img):
          img.resizable().aspectRatio(2/3, contentMode: .fill)
        case .failure(_):
          Color.gray.opacity(0.2)
        case .empty:
          Color.black.opacity(0.2)
        @unknown default:
          Color.gray.opacity(0.2)
        }
      }
      .frame(width: 140, height: 210)
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
        .frame(width: 120, alignment: .leading)
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

  private var filtered: [Movie] {
    let q = canonical(query)
    guard !q.isEmpty else { return baseList }
    return baseList.filter { canonical($0.title).contains(q) }
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
            ZStack {
              AsyncImage(url: posterURL(for: m.title, year: m.year, explicit: m.posterUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(2/3, contentMode: .fill)
                case .failure(_): Color.gray.opacity(0.2)
                case .empty: Color.black.opacity(0.2)
                @unknown default: Color.gray.opacity(0.2)
                }
              }
              .frame(width: 140, height: 210)
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
                .frame(width: 120, alignment: .leading)
                .padding(8)
            }
            .overlay(alignment: .bottom) {
              ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 6)
                Rectangle().fill(Color.green).frame(width: CGFloat(pct) * 140, height: 6)
              }
            }
            .overlay(alignment: .topTrailing) {
              Button {
                // mark watched
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
      // seek after metadata
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
        let url = AppConfig.apiBase.appendingPathComponent("api/movies/list")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let list = try JSONDecoder().decode([Movie].self, from: data)
        allMovies = list
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
        var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/jellyseerr/trending"),
                                  resolvingAgainstBaseURL: false)!
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
        var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/free-monthly"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "meta", value: nil)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { freeMonthly = []; return }
        let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        let mapped: [Movie] = items.compactMap { o in
          guard let id = o["id"] as? String ?? o["movie_id"] as? String,
                let title = o["title"] as? String,
                let stream = o["streamUrl"] as? String ?? o["stream_url"] as? String else { return nil }
          let poster = o["posterUrl"] as? String ?? o["poster_url"] as? String
          let year = o["year"] as? Int
          return Movie(id: id, title: title, posterUrl: poster, streamUrl: stream, year: year)
        }
        freeMonthly = mapped
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
          url: AppConfig.apiBase.appendingPathComponent("api/get-stripe-status"),
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
      var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/movies/list"),
                                resolvingAgainstBaseURL: false)!
      comps.queryItems = [URLQueryItem(name: "reload", value: "1")]
      let (data, resp) = try await URLSession.shared.data(from: comps.url!)
      guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
      let list = try JSONDecoder().decode([Movie].self, from: data)
      allMovies = list
      if let m = matchMovieByTitle(title, year: year) { openPlayer(for: m) }
    } catch { }
  }

  private func posterURL(for title: String, year: Int?, fallback: String? = nil, explicit: String? = nil) -> URL? {
    if let explicit = explicit, let u = URL(string: explicit) { return u }
    var c = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/poster"),
                          resolvingAgainstBaseURL: false)!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    if let built = c.string, let u = URL(string: built) { return u }
    if let f = fallback, let u = URL(string: f) { return u }
    return nil
  }

  // Canonicalize like web
  private func canonical(_ s: String) -> String {
    var t = s.lowercased()
    t = t.replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
    t = t.replacingOccurrences(of: "&", with: " and ")
    t = t.replacingOccurrences(of: ":", with: " ").replacingOccurrences(of: "-", with: " ")
    while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    for art in ["the ", "a ", "an "] {
      if t.hasPrefix(art) { t = String(t.dropFirst(art.count)) ; break }
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
