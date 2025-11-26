// -------------------------------------------------------------------------
// Aufruf über:
// cd "C:\Backups\Fahrdienst App\Supa"
// "C:\Program Files\nodejs\node.exe" restore_auth.js
// -------------------------------------------------------------------------
// ACHTUNG: ES muss die korrekte Datenbank eingestellt werden: Produkton oder Test
// Passwort = gleich Email Adresse - oder unten ändern
// -------------------------------------------------------------------------
// Datei: restore_oneUser_auth_password.js
// -------------------------------------------------------------------------

// → HIER EINTRAGEN: Test Datenbank!!
// const SUPABASE_URL = "https://jjngymzqdylfnpgtypva.supabase.co";
// const SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impqbmd5bXpxZHlsZm5wZ3R5cHZhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2Mzg5MDQ0NSwiZXhwIjoyMDc5NDY2NDQ1fQ.whLuqrgiRRAQ-qEDP5GsFihCoc348lnYKOa_dkl0dqw";  // beginnt mit "eyJhbGciOiJIUzI1NiIsInR5..."
// → HIER EINTRAGEN: Produktion Datenbank!!
const SUPABASE_URL = "https://fckacniifbgbtcwyfnta.supabase.co";
const SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZja2FjbmlpZmJnYnRjd3lmbnRhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MTk4Nzc3MywiZXhwIjoyMDc3NTYzNzczfQ.PACCp7uAOLn-rhp-6lrm1qNMEAomxjtuvGdjwTTLHrc";  // beginnt mit "eyJhbGciOiJIUzI1NiIsInR5..."

async function main() {
  console.log(`Setze Passwort für User ${EMAIL} (${USER_ID})...`);

  const body = {
    password: EMAIL, // Passwort = E-Mail
  };

  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${USER_ID}`, {
    method: "PUT",   // wichtig: PUT, nicht PATCH
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    console.error(`❌ Fehler ${res.status}: ${text}`);
    return;
  }

  console.log("✅ Passwort erfolgreich aktualisiert!");
}

main().catch((e) => console.error("Unerwarteter Fehler:", e));
