//
//  TvShowsView.swift
//  s2vids
//

import SwiftUI
import AVKit
import Foundation

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

// MARK: - Poster helpers (Local → TMDB → OMDb)
// … (unchanged helpers omitted for brevity; keep your existing implementations)

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

  // Favorites
  private var favsKey: String { "s2vids:tv-favorites:\(email.isEmpty ? "anon" : email)" }
  @State private var favorites: Set<String> = []
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
        // ⬇️ Pull-to-refresh
        .refreshable { await refreshTv() }
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
    // Settings
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView(email: email, isAdmin: effectiveIsAdmin)
    }
    // Player
    .fullScreenCover(isPresented: $playerOpen, onDismiss: stopObserving) {
      ZStack(alignment: .topTrailing) {
        if let p = player {
          VideoPlayer(player: p).ignoresSafeArea()
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
  // … (unchanged)

  // MARK: Series/Seasons/Episodes grids + sizing helpers
  // … (unchanged)

  // MARK: Networking (with async poster backfill inside Task)
  // … (unchanged fetchSeries / fetchSeasons / fetchEpisodes)

  // MARK: Posters + Player + Favorites + Access bootstrap
  // … (unchanged)

  // MARK: Refresh helper

  private func refreshTv() async {
    await MainActor.run {
      loadFavorites()
      bootstrap()
      if let s = selectedSeries {
        if let sn = selectedSeason {
          // Refresh current episodes view
          fetchEpisodes(seriesId: s.id,
                        season: sn.season,
                        seriesTitle: s.title,
                        year: s.year)
        } else {
          // Refresh seasons for selected series
          fetchSeasons(seriesId: s.id,
                       seriesTitle: s.title,
                       year: s.year)
        }
      } else {
        // Refresh top-level series list
        fetchSeries()
      }
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
