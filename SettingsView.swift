//
//  SettingsView.swift
//  s2vids
//

import SwiftUI

struct SettingsView: View {
  // Passed in by the presenter (DashboardView.sheet)
  var email: String
  var isAdmin: Bool

  // Local
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .top) {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header

          // --- Example panels (stubbed) ---
          GroupBox {
            VStack(alignment: .leading, spacing: 8) {
              Text("Account")
                .font(.headline).fontWeight(.bold)
              LabeledRow(label: "Signed in as", value: email.isEmpty ? "—" : email)
              Button("Close Settings") { dismiss() }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .groupBoxStyle(S2GroupBox())

          GroupBox {
            VStack(alignment: .leading, spacing: 8) {
              Text("Subscription")
                .font(.headline).fontWeight(.bold)
              Text("Manage your subscription from the Dashboard’s menu.")
                .foregroundColor(.secondary)
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .groupBoxStyle(S2GroupBox())

          if isAdmin {
            GroupBox {
              VStack(alignment: .leading, spacing: 8) {
                Text("Admin")
                  .font(.headline).fontWeight(.bold)
                Text("You have admin privileges.")
                  .foregroundColor(.yellow)
                  .font(.subheadline)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupBoxStyle(S2GroupBox())
          }

          Spacer(minLength: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 32)
      }
    }
    .preferredColorScheme(.dark)
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      Text("Settings")
        .font(.title2)
        .fontWeight(.bold)
      Spacer()

      // Reuse the shared dropdown button from DashboardView.swift
      UserMenuButton(
        email: email,
        isAdmin: isAdmin,
        onRequireAccess: { /* could present Getting Started if needed */ },
        onLogout: { /* hook to your logout */ },
        onOpenSettings: { /* already here; no-op */ }
      )
    }
    .foregroundColor(.white)
    .zIndex(10_000)
  }
}

// MARK: - Small helpers local to SettingsView

fileprivate struct LabeledRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack {
      Text(label)
        .foregroundColor(Color(red: 0.55, green: 0.78, blue: 0.96))
        .font(.footnote)
        .fontWeight(.bold)
      Spacer()
      Text(value).font(.subheadline).foregroundColor(.white)
    }
  }
}

fileprivate struct S2GroupBox: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      configuration.content
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color(red: 0.06, green: 0.09, blue: 0.16))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.gray.opacity(0.25))
    )
  }
}
