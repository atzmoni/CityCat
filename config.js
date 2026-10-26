// CityCat server settings. Fill both values from Supabase → Project Settings → API (or the "Connect" button).
// The key here is the public "anon" / "publishable" key, which is safe to put on the website.
// Never put the "service_role" / "secret" key here.
// While both are empty the app runs in demo mode with sample data saved only on the device.
window.CITYCAT_CONFIG = {
  supabaseUrl: "",   // e.g. "https://abcdefghijklmnop.supabase.co"
  supabaseKey: "",   // e.g. "eyJhbGciOi..." or "sb_publishable_..."
};
