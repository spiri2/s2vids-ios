//
//  SignupView.swift
//  s2vids
//

import SwiftUI

struct SignupView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var vm = SignupViewModel()

  var body: some View {
    ZStack {
      Color(red: 0.043, green: 0.063, blue: 0.125).ignoresSafeArea() // #0b1020

      VStack(spacing: 16) {
        // Header
        HStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36)
            Image(systemName: "key.horizontal.fill")
          }
          .foregroundColor(.blue)

          Text("Create your account")
            .font(.headline)
            .bold()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 20)
            .stroke(Color(.sRGB, red: 0.13, green: 0.16, blue: 0.2, opacity: 0.7))
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.043, green: 0.071, blue: 0.125))) // #0b1220
        )

        // Card
        VStack(alignment: .leading, spacing: 12) {
          Text("Sign Up").font(.subheadline).bold().foregroundStyle(Color.blue)

          if !vm.errorMessage.isEmpty {
            Text(vm.errorMessage)
              .font(.footnote)
              .foregroundColor(.red.opacity(0.85))
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.18)))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.35)))
          }

          if !vm.successMessage.isEmpty {
            Text(vm.successMessage)
              .font(.footnote)
              .foregroundColor(.green)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.18)))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.35)))
          }

          // Email
          fieldLabel("Email")
          TextField("you@example.com", text: $vm.email)
#if os(iOS)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#endif
            .fieldStyle

          // Password
          fieldLabel("Password")
          SecureField("••••••••", text: $vm.password)
#if os(iOS)
            .textContentType(.newPassword)
#endif
            .fieldStyle

          // Confirm
          fieldLabel("Confirm Password")
          SecureField("••••••••", text: $vm.confirmPassword)
#if os(iOS)
            .textContentType(.newPassword)
#endif
            .fieldStyle

          // Invite Code
          fieldLabel("Invite Code")
          TextField("ABC123", text: $vm.inviteCode)
            .textCase(.uppercase)
            .fieldStyle

          // Primary CTA(s)
          if !vm.showSendConfirmation && !vm.showResend {
            Button {
              Task { await vm.signUp() }
            } label: {
              Text(vm.isLoading ? "Signing up…" : "Create Account")
                .font(.subheadline).bold()
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green))
                .foregroundColor(.black)
            }
            .disabled(vm.isLoading)
            .padding(.top, 8)
          }

          if vm.showSendConfirmation {
            Button {
              Task { await vm.sendOrResendConfirmation() }
            } label: {
              Text("Send Confirmation Email")
                .font(.subheadline).bold()
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                .foregroundColor(.white)
            }
            .padding(.top, 6)
          }

          if vm.showResend {
            Button {
              Task { await vm.sendOrResendConfirmation() }
            } label: {
              Text("Didn’t receive it? Resend confirmation")
                .font(.subheadline).bold()
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.sRGB, red: 0.28, green: 0.33, blue: 0.41, opacity: 1)))
                .foregroundColor(.white)
            }
            .padding(.top, 6)
          }

          if !vm.resendStatus.isEmpty {
            Text(vm.resendStatus).font(.footnote).foregroundStyle(Color.blue).padding(.top, 2)
          }

          // Already have an account
          HStack {
            Text("Already have an account?")
            Button { dismiss() } label: {
              if #available(iOS 16.0, *) {
                Text("Log in").bold().underline(true, pattern: .solid, color: .purple)
              } else {
                Text("Log in").bold().underline(true).foregroundColor(.purple)
              }
            }
          }
          .font(.footnote)
          .foregroundStyle(Color(.sRGB, red: 0.82, green: 0.64, blue: 1.0, opacity: 1))
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.top, 6)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.059, green: 0.090, blue: 0.165)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(.sRGB, red: 0.10, green: 0.12, blue: 0.16, opacity: 1)))
      }
      .padding(.horizontal, 20)
    }
    .preferredColorScheme(.dark)
  }

  // small helper
  private func fieldLabel(_ text: String) -> some View {
    Text(text).font(.caption).bold().foregroundColor(.blue)
  }
}

// Shared style for fields
fileprivate extension View {
  var fieldStyle: some View {
    self
      .padding(10)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color(.sRGB, red: 0.12, green: 0.14, blue: 0.20, opacity: 1)))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.sRGB, red: 0.20, green: 0.24, blue: 0.30, opacity: 1)))
  }
}

#Preview { SignupView() }
