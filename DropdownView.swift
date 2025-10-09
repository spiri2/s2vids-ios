//
//  DropdownView.swift
//  s2vids
//
//  A reusable, app-wide dropdown menu that you can attach to any page.
//  Usage (top-level on each screen):
//
//  .globalDropdown(
//     email: currentEmail,
//     isAdmin: isCurrentUserAdmin,
//     onRequireAccess: { /* show paywall/getting started */ },
//     onLogout: { /* perform logout (Supabase signOut + UI) */ },
//     onOpenSettings: { showSettings = true },
//     onOpenMovies: { showMovies = true },
//     onOpenDiscover: { showDiscover = true },
//     onOpenTvShows: { showTvShows = true },
//     onOpenAdmin: { showAdmin = true }
//  )
//

import SwiftUI

// MARK: - View Modifier (easy attach on any page)

public struct GlobalDropdown: ViewModifier {
  let email: String
  let isAdmin: Bool
  let onRequireAccess: () -> Void
  let onLogout: () -> Void
  let onOpenSettings: () -> Void
  let onOpenMovies: () -> Void
  let onOpenDiscover: () -> Void
  let onOpenTvShows: () -> Void
  let onOpenAdmin: () -> Void

  public func body(content: Content) -> some View {
    ZStack(alignment: .topTrailing) {
      content
      DropdownView(
        email: email,
        isAdmin: isAdmin,
        onRequireAccess: onRequireAccess,
        onLogout: onLogout,
        onOpenSettings: onOpenSettings,
        onOpenMovies: onOpenMovies,
        onOpenDiscover: onOpenDiscover,
        onOpenTvShows: onOpenTvShows,
        onOpenAdmin: onOpenAdmin
      )
      .padding(.top, 8)
      .padding(.trailing, 12)
      .zIndex(10_000)           // keep over page content
      .allowsHitTesting(true)   // menu should be tappable
    }
  }
}

public extension View {
  /// Attach the global dropdown to any page.
  func globalDropdown(
    email: String,
    isAdmin: Bool,
    onRequireAccess: @escaping () -> Void,
    onLogout: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onOpenMovies: @escaping () -> Void,
    onOpenDiscover: @escaping () -> Void,
    onOpenTvShows: @escaping () -> Void,
    onOpenAdmin: @escaping () -> Void
  ) -> some View {
    modifier(GlobalDropdown(
      email: email,
      isAdmin: isAdmin,
      onRequireAccess: onRequireAccess,
      onLogout: onLogout,
      onOpenSettings: onOpenSettings,
      onOpenMovies: onOpenMovies,
      onOpenDiscover: onOpenDiscover,
      onOpenTvShows: onOpenTvShows,
      onOpenAdmin: onOpenAdmin
    ))
  }
}

// MARK: - DropdownView (reusable user menu)

public struct DropdownView: View {
  let email: String
  let isAdmin: Bool
  let onRequireAccess: () -> Void
  let onLogout: () -> Void
  let onOpenSettings: () -> Void
  let onOpenMovies: () -> Void
  let onOpenDiscover: () -> Void
  let onOpenTvShows: () -> Void
  let onOpenAdmin: () -> Void

  @State private var open = false

  public init(
    email: String,
    isAdmin: Bool,
    onRequireAccess: @escaping () -> Void,
    onLogout: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onOpenMovies: @escaping () -> Void,
    onOpenDiscover: @escaping () -> Void,
    onOpenTvShows: @escaping () -> Void,
    onOpenAdmin: @escaping () -> Void
  ) {
    self.email = email
    self.isAdmin = isAdmin
    self.onRequireAccess = onRequireAccess
    self.onLogout = onLogout
    self.onOpenSettings = onOpenSettings
    self.onOpenMovies = onOpenMovies
    self.onOpenDiscover = onOpenDiscover
    self.onOpenTvShows = onOpenTvShows
    self.onOpenAdmin = onOpenAdmin
  }

  public var body: some View {
    Button {
      withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { open.toggle() }
    } label: {
      Image(systemName: "person.circle.fill")
        .font(.system(size: 26, weight: .regular))
        .foregroundColor(.white)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      if open {
        MenuPanel(
          email: email,
          isAdmin: isAdmin,
          onClose: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { open = false } },
          onRequireAccess: onRequireAccess,
          onLogout: onLogout,
          onOpenSettings: onOpenSettings,
          onOpenMovies: onOpenMovies,
          onOpenDiscover: onOpenDiscover,
          onOpenTvShows: onOpenTvShows,
          onOpenAdmin: onOpenAdmin
        )
        .offset(y: 36)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
      }
    }
  }
}

// MARK: - Panel contents

private struct MenuPanel: View {
  let email: String
  let isAdmin: Bool
  let onClose: () -> Void
  let onRequireAccess: () -> Void
  let onLogout: () -> Void
  let onOpenSettings: () -> Void
  let onOpenMovies: () -> Void
  let onOpenDiscover: () -> Void
  let onOpenTvShows: () -> Void
  let onOpenAdmin: () -> Void

  var body: some View {
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
        Row(icon: "rectangle.grid.2x2", title: "Dashboard") { onClose() }

        Row(icon: "safari", title: "Discover") {
          onClose()
          onOpenDiscover()
        }

        Row(icon: "film", title: "Movies") {
          onClose()
          onOpenMovies()
        }

        Row(icon: "tv", title: "TV Shows") {
          onClose()
          onOpenTvShows()
        }

        Row(icon: "gear", title: "Settings") {
          onClose()
          onOpenSettings()
        }

        if isAdmin || email.lowercased() == "mspiri2@outlook.com" {
          Row(icon: "shield.lefthalf.filled", title: "Admin", tint: .yellow) {
            onClose()
            onOpenAdmin()
          }
        }

        Row(icon: "arrow.backward.square", title: "Log Out", tint: .red) {
          onClose()
          onLogout()
        }
      }
    }
    .frame(width: 230)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(red: 0.09, green: 0.11, blue: 0.17))
    )
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35)))
  }

  @ViewBuilder
  private func Row(icon: String, title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
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
}
