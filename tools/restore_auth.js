
// -------------------------------------------------------------------------
// Aufruf über:
// cd "C:\Backups\Fahrdienst App\Supa"
// "C:\Program Files\nodejs\node.exe" restore_auth.js
// -------------------------------------------------------------------------
// // 1) HIER DEIN NEUES SUPABASE-PROJEKT EINTRAGEN
// -------------------------------------------------------------------------
// Datei: restore_auth.js

const fs = require("fs");

// → HIER EINTRAGEN: Test Datenbank!!
// const SUPABASE_URL = "https://jjngymzqdylfnpgtypva.supabase.co";
// const SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impqbmd5bXpxZHlsZm5wZ3R5cHZhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2Mzg5MDQ0NSwiZXhwIjoyMDc5NDY2NDQ1fQ.whLuqrgiRRAQ-qEDP5GsFihCoc348lnYKOa_dkl0dqw";  // beginnt mit "eyJhbGciOiJIUzI1NiIsInR5..."
// → HIER EINTRAGEN: Produktion Datenbank!!
const SUPABASE_URL = "https://fckacniifbgbtcwyfnta.supabase.co";
const SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZja2FjbmlpZmJnYnRjd3lmbnRhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MTk4Nzc3MywiZXhwIjoyMDc3NTYzNzczfQ.PACCp7uAOLn-rhp-6lrm1qNMEAomxjtuvGdjwTTLHrc";  // beginnt mit "eyJhbGciOiJIUzI1NiIsInR5..."

// 2) Pfad zu deiner CSV (Backslashes müssen doppelt sein!)
const CSV_PATH = "C:\\Backups\\Fahrdienst App\\Supa\\Supabase Snippet User Accounts List.csv";

async function main() {
  console.log("Lese CSV:", CSV_PATH);
  const csv = fs.readFileSync(CSV_PATH, "utf8").trim();

  const lines = csv.split(/\r?\n/);
  const header = lines.shift(); // erste Zeile ist Kopf
  console.log("Header:", header);

  for (const line of lines) {
    if (!line.trim()) continue;

    // Wir brauchen nur id und email
    const [id, email] = line.split(",", 3);
    console.log(`\n→ Erstelle User: ${email} (${id})`);

    const body = {
      id,
      email,
      email_confirm: true,
      password: "Fahrdienst123!", // kannst du später ändern
    };

    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      console.error(`   ❌ Fehler ${res.status}: ${text}`);
    } else {
      console.log("   ✅ User angelegt");
    }
  }

  console.log("\nFertig – alle Zeilen verarbeitet.");
}

main().catch((err) => {
  console.error("Unerwarteter Fehler:", err);
});
