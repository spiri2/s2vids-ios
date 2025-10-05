//
//  AppConfig.swift
//  s2vids
//

import Foundation

enum AppConfig {
  // Supabase configuration
  static let supabaseURL = URL(string: "https://YOUR-SUPABASE-PROJECT.supabase.co")!
  static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"

  // API base for custom routes
  static let apiBase = URL(string: "https://s2vids.org")!
}
