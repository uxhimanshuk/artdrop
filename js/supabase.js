import { SUPABASE_ANON_KEY, SUPABASE_URL } from "./config.js";

export const isConfigured =
  SUPABASE_URL &&
  SUPABASE_ANON_KEY &&
  !SUPABASE_URL.includes("REPLACE_ME") &&
  !SUPABASE_ANON_KEY.includes("REPLACE_ME");

export let supabase = null;

if (isConfigured) {
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
  supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
}
