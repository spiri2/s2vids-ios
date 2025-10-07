//
//  DiscoverView.swift
//  s2vids
//

import SwiftUI
import AVKit

// MARK: - Models (match web payloads)

private struct DiscoverItem: Identifiable, Decodable, Hashable {
  let id: Int                 // TMDB id
  let title: String?
  let name: String?
  let releaseDate: String?
  let firstAirDate: String?
  let posterPath: String?
  let mediaType: String?      // "movie" | "tv"

  enum CodingKeys: String, CodingKey {
    case id
    case title, name
    case releaseDate = "releaseDate"
    case firstAirDate = "firstAirDate"
    case posterPath = "posterPath"
    case mediaType = "mediaType"
    // snake_case fallbacks:
    case release_date, first_air_date, poster_path, media_type
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    title = try c.decodeIfPresent(String.self, forKey: .title)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
      ?? (try c.decodeIfPresent(String.self, forKey: .release_date))
    firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
      ?? (try c.decodeIfPresent(String.self, forKey: .first_air_date))
    posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
      ?? (try c.decodeIfPresent(String.self, forKey: .poster_path))
    mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
      ?? (try c.decodeIfPresent(String.self, forKey: .media_type))
  }
}

private struct DiscoverResponse: Decodable {
  let results: [DiscoverItem]?
  let page: Int?
  let totalPages: Int?
  let totalResults: Int?
}

private struct Movie: Identifiable, Decodable, Hashable {
  let id: String
  let title: String
  let streamUrl: String
  let year: Int?
  let posterUrl: String?
}

private struct StripeStatusResponse: Decodable {
  let status: String?
  let active: Bool?
  let trial_end: Int?
}

// MARK: - View

struct DiscoverView: View {
  // Inject from Dashboard like MoviesView
  let email: String
  let isAdmin: Bool
  let subscriptionStatus: String
  let isTrialing: Bool

  @Environment(\.dismiss) private var dismiss

  // Access State
  @State private var resolvedStatus = ""
  @State private var resolvedTrialing = false
  @State private var accessResolved = false

  private var effectiveStatus: String { accessResolved ? resolvedStatus : subscriptionStatus }
  private var effectiveTrialing: Bool { accessResolved ? resolvedTrialing : isTrialing }
  private var effectiveIsAdmin: Bool { isAdmin || email.lowercased() == "mspiri2@outlook.com" }
  private var hasAccess: Bool { effectiveTrialing || effectiveStatus.lowercased() == "active" || effectiveIsAdmin }

  // UI State
  @State private var query = ""
  @State private var page = 1
  @State private var totalPages = 1
  @State private var totalResults = 0
  @State private var items: [DiscoverItem] = []
  @State private var loading = false
  @State private var errText: String? = nil

  // Requests State
  @State private var requestedIds: Set<Int> = []
  @State private var loadingId: Int? = nil

  // Library
  @State private var library: [Movie] = []

  // Sheets / Player
  @State private var showGettingStarted = false
  @State private var infoTitle: String = ""
  @State private var infoYear: Int? = nil
  @State private var infoOpen = false

  @State private var playerOpen = false
  @State private var player: AVPlayer? = nil
  @State private var currentStreamURL: URL? = nil

  // Settings
  @State private var showSettings = false

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(spacing: 16) {
          header
          searchBar
          paginationBar
          gridSection
          paginationBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      bootstrapAccess()
      loadRequestedIds()
      loadLibrary()
      fetchPage()
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
      MovieInfoSheet(title: infoTitle,
                     year: infoYear,
                     posterURL: posterURL(forTitle: infoTitle, year: infoYear)?.absoluteString ?? "")
      .modifier(MoviesDetentsCompatMediumLarge())
    }
    // Settings
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: effectiveIsAdmin)
    }
    // Player
    .fullScreenCover(isPresented: $playerOpen) {
      ZStack(alignment: .topTrailing) {
        if let p = player {
          VideoPlayer(player: p)
            .ignoresSafeArea()
            .onDisappear { p.pause() }
            .onAppear { p.play() }
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
      Text("Discover")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)
      Spacer()

      UserMenuButton(
        email: email,
        isAdmin: effectiveIsAdmin,
        onRequireAccess: { showGettingStarted = true },
        onLogout: {
          UserDefaults.standard.removeObject(forKey: "s2vids:favorites:\(email.isEmpty ? "anon" : email)")
          UserDefaults.standard.removeObject(forKey: "s2vids:progress:\(email.isEmpty ? "anon" : email)")
          NotificationCenter.default.post(name: Notification.Name("S2VidsDidLogout"), object: nil)
        },
        onOpenSettings: { showSettings = true },
        onOpenMovies: { dismiss() },
        onOpenDiscover: { },
        onOpenTvShows: {
          dismiss()
          NotificationCenter.default.post(name: Notification.Name("S2OpenTvShows"), object: nil)
        }
      )
    }
    .zIndex(10_000) // keep menu above everything if a popup appears
  }

  // MARK: Search Bar

  private var searchBar: some View {
    HStack(spacing: 8) {
      TextField("Search movies…", text: $query)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10)
        .fill(Color(red: 0.08, green: 0.10, blue: 0.17)))
        .foregroundColor(.white)
        .onSubmit {
          page = 1
          fetchPage()
        }
      if !query.isEmpty {
        Button("Clear") { query = ""; page = 1; fetchPage() }
          .buttonStyle(MoviesSecondaryButtonStyle())
      }
    }
  }

  // MARK: Pagination (top & bottom)

  private var paginationBar: some View {
    HStack {
      Button("First") { if page > 1 { page = 1; fetchPage() } }
        .buttonStyle(MoviesSecondaryButtonStyle())
        .disabled(loading || page <= 1)

      Button("Prev") { if page > 1 { page -= 1; fetchPage() } }
        .buttonStyle(MoviesSecondaryButtonStyle())
        .disabled(loading || page <= 1)

      Spacer()
      Text(loading ? "Loading…" : "Page \(page) of \(totalPages) • \(totalResults) results")
        .font(.caption)
        .foregroundColor(.white.opacity(0.8))
      Spacer()

      Button("Next") { if page < totalPages { page += 1; fetchPage() } }
        .buttonStyle(MoviesSecondaryButtonStyle())
        .disabled(loading || page >= totalPages)

      Button("Last") { if page < totalPages { page = totalPages; fetchPage() } }
        .buttonStyle(MoviesSecondaryButtonStyle())
        .disabled(loading || page >= totalPages)
    }
  }

  // MARK: Grid (adaptive — no GeometryReader, no zIndex)

  private var gridSection: some View {
    Group {
      if let e = errText {
        Text(e).foregroundColor(.red)
      }
      if items.isEmpty && !loading {
        Text("No titles found.").foregroundColor(.white.opacity(0.85))
      } else {
        let columns = [GridItem(.adaptive(minimum: 118), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(items) { it in
            let pureTitle = (it.title ?? it.name ?? "Unknown").trimmingCharacters(in: .whitespaces)
            let display = displayTitle(it)
            let requested = requestedIds.contains(it.id)
            let maybeStream = streamFor(it)
            let canWatch = requested && (maybeStream != nil)

            VStack(alignment: .leading, spacing: 6) {
              ZStack {
                AsyncImage(url: posterURL(for: it)) { phase in
                  switch phase {
                  case .success(let img):
                    img.resizable().scaledToFill()
                  case .failure(_):
                    Color.gray.opacity(0.25)
                      .overlay(Image(systemName: "film").font(.title2).foregroundColor(.white.opacity(0.6)))
                  case .empty:
                    Color.black.opacity(0.2)
                  @unknown default:
                    Color.gray.opacity(0.25)
                  }
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack {
                  HStack {
                    Spacer()
                    Button { openInfo(it) } label: {
                      Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.black.opacity(0.6), in: Circle())
                    }
                  }
                  Spacer()
                }
                .padding(6)
              }

              Text(display)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

              if canWatch {
                Button { openPlayer(title: pureTitle, urlString: maybeStream!) } label: {
                  Text("Watch").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
              } else {
                Button {
                  Task { await request(it) }
                } label: {
                  Text(requested ? "✅ Requested"
                       : (loadingId == it.id ? "Requesting…"
                          : (hasAccess || effectiveIsAdmin ? "Request" : "Subscribe to Request")))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(requested || loadingId == it.id || !(hasAccess || effectiveIsAdmin))
              }
            }
            .background(Color.clear)
          }
        }
      }
    }
  }

  // MARK: Info / Player Helpers

  private func openInfo(_ it: DiscoverItem) {
    let y = (it.releaseDate?.prefix(4) ?? it.firstAirDate?.prefix(4)) ?? ""
    infoTitle = it.title ?? it.name ?? "Unknown"
    infoYear = Int(y)
    infoOpen = true
  }

  private func openPlayer(title: String, urlString: String) {
    guard let u = URL(string: urlString) else { return }
    currentStreamURL = u
    player = AVPlayer(url: u)
    playerOpen = true
    player?.play()
  }

  private func closePlayer() {
    player?.pause()
    player = nil
    playerOpen = false
  }

  // MARK: Networking

  private func fetchPage() {
    loading = true
    errText = nil
    Task {
      defer { loading = false }
      do {
        var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/jellyseerr/discover"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [ .init(name: "page", value: String(page)) ]
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
          comps.queryItems?.append(.init(name: "query", value: q)) // let URLComponents encode
        }

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(DiscoverResponse.self, from: data)
        items = decoded.results ?? []
        totalPages = max(1, decoded.totalPages ?? 1)
        totalResults = max(0, decoded.totalResults ?? items.count)
      } catch {
        items = []
        totalPages = 1
        totalResults = 0
        errText = "Failed to load discover."
      }
    }
  }

  /// Submit a Jellyseerr request; only allowed for active/trial/admin.
  private func request(_ it: DiscoverItem) async {
    guard hasAccess || effectiveIsAdmin else {
      showGettingStarted = true
      return
    }
    loadingId = it.id
    defer { loadingId = nil }
    do {
      var req = URLRequest(url: AppConfig.apiBase.appendingPathComponent("api/jellyseerr/request"))
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")

      let mediaId = it.id
      let mediaType = it.mediaType ?? "movie"
      let title = (it.title ?? it.name ?? "Unknown")
      req.httpBody = try JSONSerialization.data(withJSONObject: [
        "mediaId": mediaId,
        "mediaType": mediaType,
        "title": title
      ])

      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse else { return }

      let text = String(data: data, encoding: .utf8) ?? ""
      var json: [String: Any] = [:]
      if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        json = obj
      }

      if http.statusCode == 409 {
        requestedIds.insert(it.id)
        return
      }

      guard (200...299).contains(http.statusCode) else {
        print("Request failed (\(http.statusCode)): \(json["error"] as? String ?? text)")
        return
      }

      requestedIds.insert(it.id)
    } catch {
      print("Fatal request error: \(error)")
    }
  }

  private func loadRequestedIds() {
    Task {
      var acc = Set<Int>()
      let pageSize = 100
      for page in 0..<200 {
        do {
          var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/jellyseerr/requests"),
                                    resolvingAgainstBaseURL: false)!
          comps.queryItems = [
            .init(name: "filter", value: "all"),
            .init(name: "take", value: String(pageSize)),
            .init(name: "skip", value: String(page * pageSize))
          ]
          let (data, resp) = try await URLSession.shared.data(from: comps.url!)
          guard (resp as? HTTPURLResponse)?.statusCode == 200 else { break }

          let any = try JSONSerialization.jsonObject(with: data)
          var arr: [[String: Any]] = []
          if let dict = any as? [String: Any], let r = dict["results"] as? [[String: Any]] {
            arr = r
          } else if let r = any as? [[String: Any]] {
            arr = r
          }

          if arr.isEmpty { break }
          for o in arr {
            if let a = (o["media"] as? [String: Any])?["tmdbId"] as? Int { acc.insert(a) }
            if let b = (o["mediaInfo"] as? [String: Any])?["tmdbId"] as? Int { acc.insert(b) }
            if let c = o["tmdbId"] as? Int { acc.insert(c) }
          }
          if arr.count < pageSize { break }
        } catch { break }
      }
      self.requestedIds = acc
    }
  }

  private func loadLibrary() {
    Task {
      do {
        let url = AppConfig.apiBase.appendingPathComponent("api/movies/list")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let list = try JSONDecoder().decode([Movie].self, from: data)
        library = list
      } catch {
        library = []
      }
    }
  }

  private func bootstrapAccess() {
    guard !email.isEmpty else { accessResolved = true; return }
    Task {
      defer { accessResolved = true }
      do {
        var comps = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/get-stripe-status"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [ .init(name: "email", value: email) ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        let s = try? JSONDecoder().decode(StripeStatusResponse.self, from: data)
        let status = (s?.status ?? "")
        let active = (s?.active ?? false)
        let trialEnd = (s?.trial_end ?? 0)
        resolvedStatus = active ? "active" : status
        resolvedTrialing = (status == "trialing") || trialEnd > 0
      } catch { }
    }
  }

  // MARK: - Helpers

  private func streamFor(_ it: DiscoverItem) -> String? {
    let target = canonical((it.title ?? it.name ?? ""))
    guard !target.isEmpty else { return nil }
    let wantYear: Int? = {
      if let s = it.releaseDate, s.count >= 4, let y = Int(String(s.prefix(4))) { return y }
      if let s = it.firstAirDate, s.count >= 4, let y = Int(String(s.prefix(4))) { return y }
      return nil
    }()

    if let y = wantYear,
       let exactY = library.first(where: { canonical($0.title) == target && ($0.year ?? -1) == y }) {
      return exactY.streamUrl
    }
    if let exact = library.first(where: { canonical($0.title) == target }) { return exact.streamUrl }
    if let starts = library.first(where: { canonical($0.title).hasPrefix(target) }) { return starts.streamUrl }
    if let contains = library.first(where: { canonical($0.title).contains(target) }) { return contains.streamUrl }
    return nil
  }

  private func displayTitle(_ it: DiscoverItem) -> String {
    let base = (it.title ?? it.name ?? "Unknown")
    let year = (it.releaseDate?.prefix(4) ?? it.firstAirDate?.prefix(4)) ?? ""
    return year.isEmpty ? base : "\(base) (\(year))"
  }

  private func posterURL(for it: DiscoverItem) -> URL? {
    if let p = it.posterPath, !p.isEmpty {
      if p.hasPrefix("http") { return URL(string: p) }
      return URL(string: "https://image.tmdb.org/t/p/w342\(p.hasPrefix("/") ? p : "/\(p)")")
    }
    return posterURL(forTitle: (it.title ?? it.name ?? ""), year: {
      if let s = it.releaseDate, s.count >= 4, let y = Int(String(s.prefix(4))) { return y }
      if let s = it.firstAirDate, s.count >= 4, let y = Int(String(s.prefix(4))) { return y }
      return nil
    }())
  }

  private func posterURL(forTitle title: String, year: Int?) -> URL? {
    var c = URLComponents(url: AppConfig.apiBase.appendingPathComponent("api/poster"),
                          resolvingAgainstBaseURL: false)!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    return c.url
  }

  private func canonical(_ s: String) -> String {
    var t = s.lowercased()
    t = t.replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
    t = t.replacingOccurrences(of: "&", with: " and ")
    for ch in [":", "-", "–", "—", "_", "/", ".", ",", "!", "?", "(", ")", "\""] {
      t = t.replacingOccurrences(of: ch, with: " ")
    }
    while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    for art in ["the ", "a ", "an "] { if t.hasPrefix(art) { t = String(t.dropFirst(art.count)); break } }
    return t
  }
}

// MARK: - Local helpers reused from MoviesView

private struct MoviesDetentsCompatMediumLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.presentationDetents([.medium, .large])
    } else { content }
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
