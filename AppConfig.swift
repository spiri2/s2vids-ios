//  AppConfig.swift
//  s2vids

import Foundation

enum AppConfig {
  // Supabase configuration
  static let supabaseURL = URL(string: "https://zguwfdtrmbabxfpexurt.supabase.co")!
  static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpndXdmZHRybWJhYnhmcGV4dXJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDkzNTcxMjgsImV4cCI6MjA2NDkzMzEyOH0.8V7TNBfhT92W-gmYMhU1lG8hF_UiffOqUpszfJAxjSo"

  // API base
  static let apiBase = URL(string: "https://s2vids.org")!

  // Keys
  static let tmdbKey = "acceb5c6c54c9a3c5739312c8dbe01cd"
  static let omdbKey = "af8a42c8"

  // Media scan roots
  static let moviePaths: [String] = [
    "/mnt/radarr",
    "/mnt/sonarr",
  ]

  // 🔐 iOS app admins (ONLY these can open the Admin screen)
  static let adminEmails: Set<String> = [
    "mspiri2@outlook.com",
    // add more here
  ]

  /// Convenience helper used by AdminView
  static func isAdmin(email: String) -> Bool {
    adminEmails.contains(email.lowercased())
  }
}
