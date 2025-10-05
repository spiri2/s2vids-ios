//
//  AppConfig.swift
//  s2vids
//

import Foundation

enum AppConfig {
  // Supabase configuration
  static let supabaseURL = URL(string: "https://zguwfdtrmbabxfpexurt.supabase.co")!
  static let supabaseAnonKey = " eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpndXdmZHRybWJhYnhmcGV4dXJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDkzNTcxMjgsImV4cCI6MjA2NDkzMzEyOH0.8V7>"

  // API base for custom routes
  static let apiBase = URL(string: "https://s2vids.org")!
}
