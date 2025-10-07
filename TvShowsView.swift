//
//  TvShowsView.swift
//  s2vids
//

import SwiftUI
import AVKit
import Foundation

// MARK: - Local API base shim

private func apiBaseURL() -> URL {
  if let s = Bundle.main.object(forInfoDictionaryKey: "S2_API_BASE") as? String,
     let u = URL(string: s) { return u }
  // Match web app host
  return URL(string: "https://s2vids.org/")!
}

// MARK: - Models

private struct Series: Identifiable, Hashable {
  let id: String
  let title: String
  let posterUrl: String?
  let year: Int?
}

private struct Season: Identifiable, Hashable {
  var id: String { "s\(season)" }
  let season: Int
  let title: String
  let posterUrl: String?
}

private struct Episode: Identifiable, Hashable {
  let id: String
  let title: String
  let episode: Int
  let posterUrl: String?
  let streamUrl: String
  let jellyfinUrl: String?
}

// MARK: - View

struct TvShowsView: View {
  // Inject same as MoviesView
  let email: String
  let isAdmin: Bool
  let subscriptionStatus: String
  let isTrialing: Bool

  @Environment(\.dismiss) private var dismiss

  // Access
  @State private var resolvedStatus: String = ""
  @State private var resolvedTrialing: Bool = false
  @State private var accessResolved = false

  private var effectiveStatus: String { accessResolved ? resolvedStatus : subscriptionStatus }
  private var effectiveTrialing: Bool { accessResolved ? resolvedTrialing : isTrialing }
  private var effectiveIsAdmin: Bool { isAdmin || email.lowercased() == "mspiri2@outlook.com" }
  private var hasAccess: Bool {
    effectiveTrialing || effectiveStatus.lowercased() == "active" || effectiveIsAdmin
  }

  // Data
  @State private var allSeries: [Series] = []
  @State private var loadingSeries = true

  @State private var seasons: [Season] = []
  @State private var loadingSeasons = false

  @State private var episodes: [Episode] = []
  @State private var loadingEpisodes = false

  // Selection
  @State private var selectedSeries: Series? = nil
  @State private var selectedSeason: Season? = nil

  // Search
  @State private var query: String = ""

  // Player
  @State private var playerOpen = false
  @State private var player: AVPlayer? = nil
  @State private var currentEpisode: Episode? = nil
  @State private var timeObserver: Any?

  // Gate / Settings
  @State private var showGettingStarted = false
  @State private var showSettings = false

  // Favorites (series / season / episode via compound keys)
  private var favsKey: String { "s2vids:tv-favorites:\(email.isEmpty ? "anon" : email)" }
  @State private var favorites: Set<String> = [] // keys like "series:<id>", "season:<seriesId>:<season>", "episode:<id>"
  @State private var favoritesOpen = false

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      VStack(spacing: 0) {
        header

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if selectedSeries == nil {
              seriesGrid
            } else if selectedSeason == nil {
              seasonsGrid
            } else {
              episodesGrid
            }
          }
          .padding(16)
        }
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      bootstrap()
      loadFavorites()
      fetchSeries()
    }
    // Getting started
    .sheet(isPresented: $showGettingStarted) {
      GettingStartedSheet(showNoSubNotice: !hasAccess) {
        showGettingStarted = false
      }
      .modifier(MoviesDetentsCompatMediumLarge())
    }
    // Settings full-screen (reusing SettingsView from app)
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: effectiveIsAdmin)
    }
    // Player
    .fullScreenCover(isPresented: $playerOpen, onDismiss: stopObserving) {
      ZStack(alignment: .topTrailing) {
        if let p = player {
          VideoPlayer(player: p)
            .ignoresSafeArea()
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

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      HStack(spacing: 8) {
        if selectedSeries != nil {
          Button("← All Series") { backToSeries() }
            .buttonStyle(MoviesSecondaryButtonStyle())
        }
        if selectedSeries != nil && selectedSeason != nil {
          Button("← Seasons") { backToSeasons() }
            .buttonStyle(MoviesSecondaryButtonStyle())
        }
      }

      Spacer()

      Text(selectedSeries.map { s in
        selectedSeason.map { "\(s.title) — \($0.title)" } ?? s.title
      } ?? "TV Shows")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)

      Spacer()

      if selectedSeries == nil {
        HStack {
          TextField("Search series…", text: $query)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.08, green: 0.10, blue: 0.17)))
            .foregroundColor(.white)
            .frame(width: 210)
        }
      }

      // Favorites button
      Button {
        favoritesOpen.toggle()
      } label: {
        Image(systemName: "heart.circle")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(.white)
      }

      UserMenuButton(
        email: email,
        isAdmin: effectiveIsAdmin,
        onRequireAccess: { showGettingStarted = true },
        onLogout: {
          UserDefaults.standard.removeObject(forKey: favsKey)
          NotificationCenter.default.post(name: .init("S2VidsDidLogout"), object: nil)
        },
        onOpenSettings: { showSettings = true },
        onOpenMovies: { dismiss() },
        onOpenDiscover: {
          dismiss()
          NotificationCenter.default.post(name: Notification.Name("S2OpenDiscover"), object: nil)
        }
      )
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color.black.opacity(0.12))
  }

  // MARK: Series Grid

  private var filteredSeries: [Series] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return allSeries }
    return allSeries.filter { $0.title.lowercased().contains(q) }
  }

  private var seriesGrid: some View {
    Group {
      if loadingSeries {
        Text("Loading series…").foregroundColor(.white.opacity(0.85))
      } else if filteredSeries.isEmpty {
        Text("No series found.").foregroundColor(.white.opacity(0.85))
      } else {
        GeometryReader { proxy in
          let totalSpacing: CGFloat = 12 * 3
          let count = 4
          let cardW = (proxy.size.width - totalSpacing) / CGFloat(count)
          let cardH = cardW * 1.5

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count),
            spacing: 12
          ) {
            ForEach(filteredSeries) { s in
              VStack(alignment: .leading, spacing: 6) {
                ZStack {
                  AsyncImage(url: posterURL(for: s.title, year: s.year, explicit: s.posterUrl)) { phase in
                    switch phase {
                    case .success(let img):
                      img.resizable().scaledToFill().frame(width: cardW, height: cardH).clipped()
                    case .failure(_):
                      Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                        .overlay(Image(systemName: "tv").font(.title2).foregroundColor(.white.opacity(0.6)))
                    case .empty:
                      Color.black.opacity(0.2).frame(width: cardW, height: cardH)
                    @unknown default:
                      Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                    }
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 10))

                  Button { openSeries(s) } label: {
                    Image(systemName: "play.fill")
                      .foregroundColor(.white)
                      .padding(10)
                      .background(.black.opacity(0.6), in: Circle())
                  }
                }
                .overlay(alignment: .topLeading) {
                  let key = "series:\(s.id)"
                  Button {
                    toggleFavorite(key)
                  } label: {
                    Image(systemName: "heart.fill")
                      .foregroundColor(favorites.contains(key) ? .red : .white)
                      .font(.system(size: 12))
                      .padding(8)
                      .background(.black.opacity(0.6), in: Circle())
                  }
                  .padding(6)
                }

                Text(s.title)
                  .font(.system(size: 13))
                  .lineLimit(2)
                  .frame(width: cardW - 12, alignment: .leading)
              }
            }
          }
          .frame(width: proxy.size.width, height: gridHeight(itemCount: filteredSeries.count, cardH: cardH, cols: count))
        }
        .frame(height: dynamicGridOuterHeight(itemCount: filteredSeries.count, cols: 4))
      }
    }
  }

  // MARK: Seasons Grid

  private var seasonsGrid: some View {
    Group {
      if loadingSeasons {
        Text("Loading seasons…").foregroundColor(.white.opacity(0.85))
      } else if seasons.isEmpty {
        Text("No seasons found.").foregroundColor(.white.opacity(0.85))
      } else {
        GeometryReader { proxy in
          let totalSpacing: CGFloat = 12 * 3
          let count = 4
          let cardW = (proxy.size.width - totalSpacing) / CGFloat(count)
          let cardH = cardW * 1.5

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count),
            spacing: 12
          ) {
            ForEach(seasons) { sn in
              VStack(alignment: .leading, spacing: 6) {
                ZStack {
                  AsyncImage(url: posterURL(for: selectedSeries?.title ?? "", year: selectedSeries?.year, explicit: sn.posterUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill().frame(width: cardW, height: cardH).clipped()
                    case .failure(_): Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                    case .empty: Color.black.opacity(0.2).frame(width: cardW, height: cardH)
                    @unknown default: Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                    }
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 10))

                  Button { openSeason(sn) } label: {
                    Image(systemName: "play.fill")
                      .foregroundColor(.white)
                      .padding(10)
                      .background(.black.opacity(0.6), in: Circle())
                  }
                }
                .overlay(alignment: .topLeading) {
                  if let sid = selectedSeries?.id {
                    let key = "season:\(sid):\(sn.season)"
                    Button { toggleFavorite(key) } label: {
                      Image(systemName: "heart.fill")
                        .foregroundColor(favorites.contains(key) ? .red : .white)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(.black.opacity(0.6), in: Circle())
                    }.padding(6)
                  }
                }

                Text(sn.title)
                  .font(.system(size: 13))
                  .lineLimit(2)
                  .frame(width: cardW - 12, alignment: .leading)
              }
            }
          }
          .frame(width: proxy.size.width, height: gridHeight(itemCount: seasons.count, cardH: cardH, cols: count))
        }
        .frame(height: dynamicGridOuterHeight(itemCount: seasons.count, cols: 4))
      }
    }
  }

  // MARK: Episodes Grid

  private var episodesGrid: some View {
    Group {
      if loadingEpisodes {
        Text("Loading episodes…").foregroundColor(.white.opacity(0.85))
      } else if episodes.isEmpty {
        Text("No episodes found.").foregroundColor(.white.opacity(0.85))
      } else {
        GeometryReader { proxy in
          let totalSpacing: CGFloat = 12 * 3
          let count = 4
          let cardW = (proxy.size.width - totalSpacing) / CGFloat(count)
          let cardH = cardW * 1.5

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count),
            spacing: 12
          ) {
            ForEach(episodes) { ep in
              VStack(alignment: .leading, spacing: 6) {
                ZStack {
                  AsyncImage(url: posterURL(for: selectedSeries?.title ?? "", year: selectedSeries?.year, explicit: ep.posterUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill().frame(width: cardW, height: cardH).clipped()
                    case .failure(_): Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                    case .empty: Color.black.opacity(0.2).frame(width: cardW, height: cardH)
                    @unknown default: Color.gray.opacity(0.25).frame(width: cardW, height: cardH)
                    }
                  }
                  .clipShape(RoundedRectangle(cornerRadius: 10))

                  Button {
                    if !hasAccess { showGettingStarted = true; return }
                    openPlayer(for: ep)
                  } label: {
                    Image(systemName: "play.fill")
                      .foregroundColor(.white)
                      .padding(10)
                      .background(.black.opacity(0.6), in: Circle())
                  }
                }
                .overlay(alignment: .topLeading) {
                  let key = "episode:\(ep.id)"
                  Button { toggleFavorite(key) } label: {
                    Image(systemName: "heart.fill")
                      .foregroundColor(favorites.contains(key) ? .red : .white)
                      .font(.system(size: 12))
                      .padding(8)
                      .background(.black.opacity(0.6), in: Circle())
                  }.padding(6)
                }

                Text(ep.title)
                  .font(.system(size: 13))
                  .lineLimit(2)
                  .frame(width: cardW - 12, alignment: .leading)
              }
            }
          }
          .frame(width: proxy.size.width, height: gridHeight(itemCount: episodes.count, cardH: cardH, cols: count))
        }
        .frame(height: dynamicGridOuterHeight(itemCount: episodes.count, cols: 4))
      }
    }
  }

  // MARK: Grid size helpers

  private func rows(for count: Int, cols: Int) -> Int { max(1, Int(ceil(Double(count) / Double(cols)))) }
  private func gridHeight(itemCount: Int, cardH: CGFloat, cols: Int) -> CGFloat {
    CGFloat(rows(for: itemCount, cols: cols)) * (cardH + 34 + 12)
  }
  private func dynamicGridOuterHeight(itemCount: Int, cols: Int) -> CGFloat {
    CGFloat(rows(for: itemCount, cols: cols)) * 260
  }

  // MARK: Networking (liberal parsing like MoviesView)

  private func fetchSeries() {
    loadingSeries = true
    Task {
      defer { loadingSeries = false }
      do {
        let url = apiBaseURL().appendingPathComponent("api/tv/series")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { allSeries = []; return }

        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let rows: [[String: Any]]
        if let arr = parsed as? [[String: Any]] { rows = arr }
        else if let dict = parsed as? [String: Any] {
          rows = (dict["items"] as? [[String: Any]]) ?? (dict["results"] as? [[String: Any]]) ?? []
        } else { rows = [] }

        let list: [Series] = rows.compactMap { o in
          let id = (o["id"] as? String)
            ?? (o["series_id"] as? String)
            ?? (o["id"] as? Int).map(String.init)
          let title = o["title"] as? String
          let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)
          let year: Int? = {
            if let y = o["year"] as? Int { return y }
            if let ys = o["year"] as? String, let yi = Int(ys) { return yi }
            return nil
          }()
          guard let id, let title else { return nil }
          return Series(id: id, title: title, posterUrl: poster, year: year)
        }

        allSeries = list
      } catch {
        allSeries = []
      }
    }
  }

  private func openSeries(_ s: Series) {
    selectedSeries = s
    selectedSeason = nil
    episodes = []
    fetchSeasons(seriesId: s.id, seriesTitle: s.title, year: s.year)
  }

  private func openSeason(_ sn: Season) {
    selectedSeason = sn
    fetchEpisodes(seriesId: selectedSeries?.id ?? "", season: sn.season, seriesTitle: selectedSeries?.title ?? "", year: selectedSeries?.year)
  }

  private func backToSeries() {
    selectedSeries = nil
    seasons = []
    selectedSeason = nil
    episodes = []
  }

  private func backToSeasons() {
    selectedSeason = nil
    episodes = []
  }

  private func fetchSeasons(seriesId: String, seriesTitle: String, year: Int?) {
    loadingSeasons = true
    Task {
      defer { loadingSeasons = false }
      do {
        var comps = URLComponents(url: apiBaseURL().appendingPathComponent("api/tv/seasons"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "series", value: seriesId)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { seasons = []; return }

        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let rows: [[String: Any]]
        if let arr = parsed as? [[String: Any]] { rows = arr }
        else if let dict = parsed as? [String: Any] { rows = (dict["items"] as? [[String: Any]]) ?? [] }
        else { rows = [] }

        let list: [Season] = rows.compactMap { o in
          let seasonNum: Int? = {
            if let n = o["season"] as? Int { return n }
            if let ns = o["season"] as? String, let ni = Int(ns) { return ni }
            return nil
          }()
          let title = (o["title"] as? String)
            ?? (seasonNum.map { "Season \($0)" })
          let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)
          guard let seasonNum, let title else { return nil }
          return Season(season: seasonNum, title: title, posterUrl: poster)
        }

        seasons = list
      } catch {
        seasons = []
      }
    }
  }

  private func fetchEpisodes(seriesId: String, season: Int, seriesTitle: String, year: Int?) {
    loadingEpisodes = true
    Task {
      defer { loadingEpisodes = false }
      do {
        var comps = URLComponents(url: apiBaseURL().appendingPathComponent("api/tv/episodes"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
          URLQueryItem(name: "series", value: seriesId),
          URLQueryItem(name: "season", value: String(season))
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { episodes = []; return }

        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let rows: [[String: Any]]
        if let arr = parsed as? [[String: Any]] { rows = arr }
        else if let dict = parsed as? [String: Any] { rows = (dict["items"] as? [[String: Any]]) ?? [] }
        else { rows = [] }

        let list: [Episode] = rows.compactMap { o in
          let id = (o["id"] as? String)
            ?? (o["episode_id"] as? String)
            ?? (o["id"] as? Int).map(String.init)
          let title = o["title"] as? String
          let epNum: Int? = {
            if let n = o["episode"] as? Int { return n }
            if let ns = o["episode"] as? String, let ni = Int(ns) { return ni }
            return nil
          }()
          let poster = (o["posterUrl"] as? String) ?? (o["poster_url"] as? String)
          let stream = (o["streamUrl"] as? String) ?? (o["stream_url"] as? String)
          let jelly = (o["jellyfinUrl"] as? String) ?? (o["jellyfin_url"] as? String)

          guard let id, let title, let epNum, let stream else { return nil }
          return Episode(id: id, title: title, episode: epNum, posterUrl: poster, streamUrl: stream, jellyfinUrl: jelly)
        }

        episodes = list
      } catch {
        episodes = []
      }
    }
  }

  // MARK: Posters

  /// Prefer explicit http(s) URL; otherwise use /api/poster?title=… (same as Movies)
  private func posterURL(for title: String, year: Int?, explicit: String?) -> URL? {
    if let explicit = explicit,
       let u = URL(string: explicit),
       let scheme = u.scheme,
       (scheme == "http" || scheme == "https") {
      return u
    }
    var c = URLComponents(url: apiBaseURL().appendingPathComponent("api/poster"), resolvingAgainstBaseURL: false)!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    return c.url
  }

  // MARK: Player

  private func openPlayer(for ep: Episode) {
    guard hasAccess else { showGettingStarted = true; return }
    currentEpisode = ep
    let item = AVPlayerItem(url: URL(string: ep.streamUrl)!)
    let p = AVPlayer(playerItem: item)
    player = p
    playerOpen = true
    p.play()
    startObserving()
  }

  private func closePlayer() {
    stopObserving()
    player?.pause()
    player = nil
    playerOpen = false
    currentEpisode = nil
  }

  private func startObserving() {
    guard let p = player else { return }
    let interval = CMTimeMake(value: 1, timescale: 2)
    timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
      // (optional) Hook watch-progress here if you add it later
    }
  }

  private func stopObserving() {
    if let obs = timeObserver, let p = player {
      p.removeTimeObserver(obs)
    }
    timeObserver = nil
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

  private func toggleFavorite(_ key: String) {
    if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
    saveFavorites()
  }

  // MARK: Access bootstrap

  private func bootstrap() {
    guard !email.isEmpty else { accessResolved = true; return }
    Task {
      do {
        var comps = URLComponents(url: apiBaseURL().appendingPathComponent("api/get-stripe-status"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "email", value: email)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        if (resp as? HTTPURLResponse)?.statusCode == 200 {
          struct Stripe: Decodable {
            let status: String?
            let active: Bool?
            let trial_end: Int?
          }
          let s = try? JSONDecoder().decode(Stripe.self, from: data)
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
}

// MARK: - Local helpers reused from Movies

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
