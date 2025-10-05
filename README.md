# Now that they’re in your Info.plist, you can safely access them anywhere in your Swift files like this:
let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""

let client = SupabaseClient(
    supabaseURL: URL(string: supabaseURL)!,
    supabaseKey: supabaseAnonKey
)
