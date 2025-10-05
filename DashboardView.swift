//
//  DashboardView.swift
//  s2vids
//

import SwiftUI
import AVKit

struct DashboardView: View {
  @StateObject private var vm = DashboardViewModel()

  // Inject these from Auth after login:
  var email: String
  var isAdmin: Bool
  var subscriptionStatus: String
  var isTrialing: Bool

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(spacing: 20) {
          header

          if shouldShowJellyfinPanel {
            jellyfinPanel
          }

          carousel(
            title: "Trending Movies",
            loading: vm.loadingTrending,
            emptyText: "No trending items available right now.",
            items: vm.trending.map {
              PosterItem(id: $0.id, title: $0.title, year: $0.year,
                         poster: posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { title, year in openByTitle(title, year: year) },
            onInfo: { title, year in openInfo(title, year: year) }
          )

          carousel(
            title: "Recently Added",
            loading: vm.loadingRecent,
            emptyText: "No recent movies right now.",
            items: vm.recent.map {
              PosterItem(id: $0.id, title: $0.title, year: $0.year,
                         poster: $0.poster ?? posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { title, year in openByTitle(title, year: year) },
            onInfo: { title, year in openInfo(title, year: year) }
          )

          carousel(
            title: "Upcoming Movies",
            loading: vm.loadingUpcoming,
            emptyText: "No upcoming titles right now.",
            items: vm.upcoming.map {
              PosterItem(id: String($0.id), title: $0.title, year: $0.year,
                         poster: $0.poster ?? posterURL(for: $0.title, year: $0.year))
            },
            onPlay: { _, _ in },
            onInfo: { title, year in openInfo(title, year: year) }
          )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      vm.bootstrap(email: email, isAdmin: isAdmin,
                   subscriptionStatus: subscriptionStatus, isTrialing: isTrialing)
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
      AnnouncementsSheet(isAdmin: isAdmin) {
        vm.showAnnouncements = false
      }
      .modifier(DetentsCompatLarge())
    }

    // Player
    .fullScreenCover(isPresented: $vm.playerOpen) {
      VideoPlayer(player: vm.player)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
          Button("Close") { vm.closePlayer() }
            .padding(12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding()
        }
    }
  }

  private var hasAccess: Bool { isTrialing || subscriptionStatus == "active" || isAdmin }
  private var shouldShowJellyfinPanel: Bool { hasAccess && !vm.hasJellyfinAccount }

  // MARK: Header
  private var header: some View {
    HStack(spacing: 12) {
      Text("s2vids Dashboard")
        .font(.title2).bold()
      Spacer()

      if !hasAccess && !isAdmin {
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
    }
    .foregroundStyle(.white)
  }

  // MARK: Jellyfin Panel
  private var jellyfinPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Jellyfin Access").font(.title3).bold()
      HStack {
        Text("Username").foregroundStyle(.cyan).font(.caption).bold()
        Spacer()
        Text(email).font(.subheadline)
      }
      .padding(.vertical, 4)

      SecureField("New Password", text: $vm.jellyfinPassword)
        .textContentType(.newPassword)
        .padding(10)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

      SecureField("Confirm Password", text: $vm.jellyfinPassword2)
        .textContentType(.newPassword)
        .padding(10)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

      HStack {
        Button {
          Task { await vm.createOrResetJellyfin() }
        } label: {
          Text(vm.creatingJellyfin ? "Creating…" : "Create Account")
            .bold()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.black)
        }
        .disabled(vm.creatingJellyfin)

        Button("Cancel") {
          vm.jellyfinPassword = ""
          vm.jellyfinPassword2 = ""
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
      }

      if !vm.jellyfinError.isEmpty {
        Text(vm.jellyfinError).foregroundColor(.red)
      }
      if !vm.jellyfinSuccess.isEmpty {
        Text(vm.jellyfinSuccess).foregroundColor(.green)
      }
    }
    .padding(16)
    .background(Color(red: 0.06, green: 0.09, blue: 0.16), in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08)))
  }

  // MARK: Carousels
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
      Text(title).font(.headline).bold()

      if loading {
        Text("Loading…").foregroundStyle(.secondary)
      } else if items.isEmpty {
        Text(emptyText).foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(items) { it in
              VStack(alignment: .leading, spacing: 6) {
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
                .overlay(alignment: .bottomTrailing) {
                  HStack(spacing: 6) {
                    Button { onInfo(it.title, it.year) } label: {
                      Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                    }
                    if hasAccess {
                      Button { onPlay(it.title, it.year) } label: {
                        Image(systemName: "play.fill")
                          .foregroundColor(.white)
                          .padding(8)
                          .background(.black.opacity(0.5), in: Circle())
                      }
                    }
                  }
                  .padding(8)
                }

                Text(it.title)
                  .font(.caption)
                  .lineLimit(2)
                  .frame(width: 140, alignment: .leading)
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
  private func openInfo(_ title: String, year: Int?) {
    vm.infoTitle = title
    vm.infoYear = year
    vm.infoOpen = true
    let poster = posterURL(for: title, year: year)
    let text = "\(title)\(year != nil ? " (\(year!))" : "")"
    let sheet = InfoSheetView(title: text, posterURL: poster) { vm.infoOpen = false }
    UIApplication.shared.present(sheet)
  }

  private func openByTitle(_ title: String, year: Int?) {
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
        guard let m = match,
              let stream = m["streamUrl"] as? String,
              let streamURL = URL(string: stream)
        else { return }
        vm.openPlayer(title: title, streamURL: streamURL)
      } catch { }
    }
  }
}

// MARK: - Simple Sheets + Presenter

#if os(iOS)
import UIKit
#endif

// MARK: Detents Compatibility Helpers
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
