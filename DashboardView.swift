//
//  DashboardView.swift
//  s2vids
//

import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#endif

// MARK: - Dashboard

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

      // iOS 15/16 keyboard-dismiss safe ScrollView
      if #available(iOS 16.0, *) {
        ScrollView { content }.scrollDismissesKeyboard(.interactively)
      } else {
        ScrollView { content }
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      vm.bootstrap(
        email: email,
        isAdmin: isAdmin,
        subscriptionStatus: subscriptionStatus,
        isTrialing: isTrialing
      )
    }
    // Getting Started (matches your web modal copy)
    .sheet(isPresented: $vm.showGettingStarted) {
      GettingStartedSheet(showNoSubNotice: !hasAccess) { vm.showGettingStarted = false }
        .modifier(DetentsCompatMediumLarge())
    }
    // Announcements
    .sheet(isPresented: $vm.showAnnouncements) {
      AnnouncementsSheet(isAdmin: isAdmin) { vm.showAnnouncements = false }
        .modifier(DetentsCompatLarge())
    }
    // Player (only presented after we validate access in playOrShowOnboarding)
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

  // MARK: - Scroll Content
  @ViewBuilder
  private var content: some View {
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
        onPlay: { title, year in playOrShowOnboarding(title: title, year: year) },
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
        onPlay: { _, _ in /* no direct play */ },
        onInfo: { title, year in openInfo(title, year: year) }
      )
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 40)
  }

  // MARK: Header
  private var header: some View {
    HStack(spacing: 12) {
      Text("s2vids Dashboard")
        .font(.title2)
        .fontWeight(.bold)

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

      Button { vm.showAnnouncements = true } label: {
        Image(systemName: "megaphone")
          .padding(8)
          .background(Color(red: 0.07, green: 0.09, blue: 0.17), in: Circle())
          .overlay(alignment: .topTrailing) {
            if vm.hasNewAnnouncements {
              Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 4, y: -4)
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
    .foregroundColor(.white)
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
      Text(title).font(.headline).fontWeight(.bold)

      if loading {
        Text("Loading…").foregroundColor(.secondary)
      } else if items.isEmpty {
        Text(emptyText).foregroundColor(.secondary)
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
                    // Still show the play button only if the user has access
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
    var c = URLComponents(
      url: AppConfig.apiBase.appendingPathComponent("api/poster"),
      resolvingAgainstBaseURL: false
    )!
    var q: [URLQueryItem] = [ .init(name: "title", value: title), .init(name: "v", value: "1") ]
    if let y = year { q.append(.init(name: "y", value: String(y))) }
    c.queryItems = q
    return c.string ?? ""
  }

  // MARK: - Access gate for play

  private func playOrShowOnboarding(title: String, year: Int?) {
    guard hasAccess else {
      // Don’t open the player. Show onboarding instead.
      vm.showGettingStarted = true
      return
    }
    openByTitle(title, year: year)
  }

  // MARK: Actions

  private func openInfo(_ title: String, year: Int?) {
    let poster = posterURL(for: title, year: year)
    let text = "\(title)\(year != nil ? " (\(year!))" : "")"
    let sheet = InfoSheetView(title: text, posterURL: poster) { /* close handled by sheet */ }
    UIApplication.shared.present(sheet)
  }

  private func openByTitle(_ title: String, year: Int?) {
    // As a second line of defense, also gate here.
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
        guard let m = match,
              let stream = m["streamUrl"] as? String,
              let streamURL = URL(string: stream)
        else { return }
        vm.openPlayer(title: title, streamURL: streamURL)
      } catch { /* ignore */ }
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
        // Attention banner (matches web)
        if showNoSubNotice {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Image(systemName: "info.circle").foregroundColor(.red.opacity(0.9))
              Text("Attention").font(.headline).fontWeight(.heavy)
            }
            Text("You currently have **no active subscription**.")
          }
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            LinearGradient(
              colors: [Color.red.opacity(0.35), Color.orange.opacity(0.25)],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4)))
          .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        HStack(spacing: 8) {
          Image(systemName: "questionmark.circle").foregroundColor(.indigo)
          Text("Getting started").font(.headline).fontWeight(.heavy)
        }

        // Steps — same copy as your web modal
        VStack(alignment: .leading, spacing: 8) {
          Text("**Welcome,** To start enjoying all of the premium benefits, follow the instructions below.")
          Text("**1.** Select **Subscribe**.")
          Text("**2.** After subscribing, return here and refresh the page.")
          Text("**3.** Select **Create Jellyfin Account** and set a password.")
          Text("**4.** Open the dropdown menu (top right corner).")
          Text("**5.** Select **Launch Jellyfin**.")
          Text("**6.** Sign in using your email + the password you set.")
        }
        .font(.callout)
        .foregroundColor(.secondary)

        Link("Subscribe",
             destination: URL(string: "https://buy.stripe.com/aFa14o8B758CeTnfrjfw406")!)
          .buttonStyle(.borderedProminent)
          .tint(.green)

        Spacer()
      }
      .padding()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Close", action: onClose)
        }
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

struct InfoSheetView: View {
  let title: String
  let posterURL: String
  let onClose: () -> Void

  var body: some View {
    NavigationView {
      VStack(spacing: 16) {
        AsyncImage(url: URL(string: posterURL)) { img in
          img.resizable().scaledToFit()
        } placeholder: {
          Color.gray.opacity(0.2)
        }
        .frame(height: 280)
        Text(title).font(.headline).multilineTextAlignment(.center)
        Spacer()
      }
      .padding()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Close", action: onClose)
        }
      }
    }
  }
}

// MARK: - Presenter helper (so UIApplication.present exists)

#if os(iOS)
extension UIApplication {
  func present<V: View>(_ view: V) {
    guard let scene = connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return }
    let host = UIHostingController(rootView: view)
    host.modalPresentationStyle = .formSheet
    root.present(host, animated: true)
  }
}
#endif

// MARK: - Detents Compatibility Helpers (iOS 16+ only; safe on iOS 15)

private struct DetentsCompatMediumLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) { content.presentationDetents([.medium, .large]) } else { content }
  }
}
private struct DetentsCompatLarge: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) { content.presentationDetents([.large]) } else { content }
  }
}
