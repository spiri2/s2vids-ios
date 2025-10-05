//
//  LoginView.swift
//  s2vids
//
//  Created by Michael Espiritu on 10/5/25.
//

import SwiftUI

struct LoginView: View {
  @StateObject private var vm = AuthViewModel()

  var body: some View {
    ZStack {
      background
      content
    }
    .preferredColorScheme(.dark)
#if os(iOS)
    .fullScreenCover(isPresented: $vm.isSignedIn) {
      HomeView()
    }
#else
    .sheet(isPresented: $vm.isSignedIn) {
      HomeView().frame(minWidth: 480, minHeight: 320)
    }
#endif
  }

  private var background: some View {
    Color(red: 0.043, green: 0.063, blue: 0.125)
      .ignoresSafeArea()
  }

  private var content: some View {
    VStack(spacing: 16) {
      HeaderCard()
      LoginCard(vm: vm)
    }
    .padding(.horizontal, 20)
  }
}

// MARK: - HeaderCard
private struct HeaderCard: View {
  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.blue.opacity(0.2))
          .frame(width: 36, height: 36)
        Image(systemName: "arrow.right.to.line")
      }
      .foregroundColor(.blue)

      Text("Sign in to your account")
        .font(.headline)
        .bold()
    }
    .padding(10)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 20)
        .stroke(Color(.sRGB, red: 0.13, green: 0.16, blue: 0.2, opacity: 0.7))
        .background(
          RoundedRectangle(cornerRadius: 20)
            .fill(Color(red: 0.043, green: 0.071, blue: 0.125))
        )
    )
  }
}

// MARK: - LoginCard
private struct LoginCard: View {
  @ObservedObject var vm: AuthViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      title
      errorBanner
      infoBanner
      emailField
      passwordField
      forgotButton
      statusText
      signInButton
      signupPrompt
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color(red: 0.059, green: 0.090, blue: 0.165))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 24)
        .stroke(Color(.sRGB, red: 0.10, green: 0.12, blue: 0.16, opacity: 1))
    )
  }

  private var title: some View {
    Text("Sign In")
      .font(.subheadline)
      .bold()
      .foregroundStyle(Color.blue)
  }

  private var errorBanner: some View {
    Group {
      if !vm.errorMessage.isEmpty {
        Text(vm.errorMessage)
          .font(.footnote)
          .foregroundColor(.red.opacity(0.85))
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.18)))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.35)))
      }
    }
  }

  private var infoBanner: some View {
    Group {
      if !vm.info.isEmpty {
        Text(vm.info)
          .font(.footnote)
          .foregroundColor(.green)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.18)))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.35)))
      }
    }
  }

  private var emailField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Email")
        .font(.caption)
        .bold()
        .foregroundColor(.blue)

      TextField("you@example.com", text: Binding(
        get: { vm.email },
        set: { vm.onEmailChange($0) }
      ))
#if os(iOS)
      .textContentType(.emailAddress)
      .keyboardType(.emailAddress)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
#endif
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(Color(.sRGB, red: 0.12, green: 0.14, blue: 0.20, opacity: 1))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color(.sRGB, red: 0.20, green: 0.24, blue: 0.30, opacity: 1))
      )
    }
  }

  private var passwordField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Password")
        .font(.caption)
        .bold()
        .foregroundColor(.blue)

      SecureField("••••••••", text: $vm.password)
#if os(iOS)
      .textContentType(.password)
#endif
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(Color(.sRGB, red: 0.12, green: 0.14, blue: 0.20, opacity: 1))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color(.sRGB, red: 0.20, green: 0.24, blue: 0.30, opacity: 1))
      )
    }
  }

  private var forgotButton: some View {
    Button {
      Task {
        await vm.forgotPassword(
          redirectTo: URL(string: "https://your-site.example.com/auth/reset")!
        )
      }
    } label: {
      Text("Forgot password?")
        .font(.caption)
        .foregroundStyle(Color.blue)
        .underline(true)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .disabled(vm.isLoading)
  }

  private var statusText: some View {
    Group {
      if let lock = vm.lockRemaining, lock > 0 {
        Text("Locked. Try again in \(formatCountdown(lock)).")
          .font(.caption2)
          .foregroundStyle(Color.red.opacity(0.85))
      } else if let left = vm.attemptsLeft {
        Text("\(left) attempt\(left == 1 ? "" : "s") remaining")
          .font(.caption2)
          .foregroundStyle(Color.orange)
      }
    }
  }

  private var signInButton: some View {
    Button {
      Task { await vm.signIn() }
    } label: {
      Text(vm.isLoading ? "Signing in…" : "Sign In")
        .font(.subheadline)
        .bold()
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green))
        .foregroundColor(.black)
    }
    .disabled(vm.isLoading)
  }

  private var signupPrompt: some View {
    HStack {
      Text("Don’t have an account?")
      Text("Sign up").bold().underline(true)
    }
    .font(.footnote)
    .foregroundStyle(Color(.sRGB, red: 0.82, green: 0.64, blue: 1.0, opacity: 1))
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.top, 6)
  }
}

// MARK: - HomeView
struct HomeView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("✅ Signed In")
        .font(.title2)
        .bold()
      Text("Welcome to your movie dashboard!")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }
}

#Preview { LoginView() }
