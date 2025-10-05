//
//  SupabaseManager.swift
//  s2vids
//
//  Created by Michael Espiritu on 10/5/25.
//

import Foundation
import Supabase

final class SupabaseManager {
  static let shared = SupabaseManager()
  let client: SupabaseClient

  private init() {
    // Uses the centralized AppConfig.swift
    client = SupabaseClient(
      supabaseURL: AppConfig.supabaseURL,
      supabaseKey: AppConfig.supabaseAnonKey
    )
  }
}
