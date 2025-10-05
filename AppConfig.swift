//
//  AppConfig.swift
//  s2vids
//

import Foundation

enum AppConfig {
  // Supabase connection
  static let supabaseURL = URL(string: "https://YOUR-SUPABASE-PROJECT.supabase.co")!
  static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"

  // Your API base (for /api/signup etc)
  static let apiBase = URL(string: "https://s2vids.org")!
}
