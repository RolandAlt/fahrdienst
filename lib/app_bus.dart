// lib/app_bus.dart
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
/// Build-/Laufzeit-Config (per --dart-define übersteuerbar)
class AppConfig {
  static const bool useSupabase =
      bool.fromEnvironment('USE_SUPABASE', defaultValue: false);

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fckacniifbgbtcwyfnta.supabase.co',
  );

  // Anon-Key aus Supabase (Legacy API Keys → anon public)
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZja2FjbmlpZmJnYnRjd3lmbnRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE5ODc3NzMsImV4cCI6MjA3NzU2Mzc3M30.hTJOkXOMvVCpdjo03U46Ps9NFGyzbskdt0n9ngiyYEk',
  );

  // Silent-Login (optional; bleibt leer, wenn nicht genutzt)
  static const String supaEmail =
      String.fromEnvironment('SUPA_EMAIL', defaultValue: '');
  static const String supaPassword =
      String.fromEnvironment('SUPA_PW', defaultValue: '');

  // „Zentrale“ – verhindert Undefined Getter und erlaubt Matching in der Route-Suche
  static const String zentraleName =
      String.fromEnvironment('ZENTRALE_NAME', defaultValue: 'Zentrale');
  static const String zentraleAdresse =
      String.fromEnvironment('ZENTRALE_ADRESSE', defaultValue: '');
  static const String zentraleTelefon =
      String.fromEnvironment('ZENTRALE_TELEFON', defaultValue: '');
}




class Supa {
  static sb.SupabaseClient get client => sb.Supabase.instance.client;
}

class AppAuth {
  static bool _didLogin = false;
  static bool _isLoggingIn = false;

  // Wird durch initRememberFlag() gesetzt
  static bool _remember = true;

static Future<void> clearStoredCredentials({String? newEmail}) async {
  try {
    final sp = await SharedPreferences.getInstance();

    // Sonderfall: neue E-Mail setzen (nur wenn explizit übergeben)
    if (newEmail != null && newEmail.isNotEmpty) {
      await sp.setString('supa_email', newEmail);
    }

    // Passwort IMMER entfernen → beim nächsten Start muss neu eingetippt werden
    await sp.remove('supa_pw');

    // Auto-Login verhindern → Verhalten wie "Nicht speichern" im Login-Dialog
    await sp.setBool('supa_remember', false);

    debugPrint(
      '[AppAuth] clearStoredCredentials(): pw entfernt, remember=false, newEmail=${newEmail ?? '<unchanged>'}',
    );
  } catch (e) {
    debugPrint('[AppAuth] clearStoredCredentials error: $e');
  }
}



  // -----------------------------------------------------------
  // 1) Remember-Flag beim App-Start aus SharedPreferences lesen
  // -----------------------------------------------------------
  static Future<void> initRememberFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _remember = sp.getBool('supa_remember') ?? true;
      debugPrint('[AppAuth] initRememberFlag(): remember=$_remember');
    } catch (e) {
      debugPrint('[AppAuth] initRememberFlag() Fehler: $e');
      _remember = true; // Fallback: merken erlaubt
    }
  }

  // -----------------------------------------------------------
  // 2) "Eingeloggt"-Entscheidung -> rein auf Supabase basierend
  // -----------------------------------------------------------
  static bool get isLoggedIn => Supa.client.auth.currentUser != null;

  // -----------------------------------------------------------
  // 3) NEU: Soll der LoginDialog gezeigt werden?
  // -----------------------------------------------------------

static Future<bool> shouldShowLoginDialog() async {
  debugPrint('--- shouldShowLoginDialog() ENTER ---');
  debugPrint('    _didLogin = $_didLogin');

  // Falls in dieser Session schon eingeloggt -> nie mehr Dialog
  if (_didLogin) {
    debugPrint('    => _didLogin is TRUE -> RETURN false');
    return false;
  }

  try {
    final sp = await SharedPreferences.getInstance();
    final remember = sp.getBool('supa_remember') ?? true;

    debugPrint('    remember flag = $remember');
    final loggedIn = Supa.client.auth.currentUser != null;
    debugPrint('    supabase.loggedIn = $loggedIn');

    if (!remember) {
      debugPrint('    => remember=false & !_didLogin -> RETURN true');
      return true;
    }

    final result = !loggedIn;
    debugPrint('    => RETURN $result  (loggedIn=$loggedIn)');
    return result;

  } catch (e) {
    debugPrint('    ERROR in shouldShowLoginDialog(): $e');
    return true;
  }
}




  // -----------------------------------------------------------
  // 4) Silent-SignIn (SUPA_EMAIL + SUPA_PW)
  // -----------------------------------------------------------
  static Future<void> ensureSignedIn() async {
    if (!AppConfig.useSupabase || _didLogin) return;
    if (_isLoggingIn) return;

    _isLoggingIn = true;

    final auth = Supa.client.auth;

    if (auth.currentUser != null) {
      _didLogin = true;
      _isLoggingIn = false;
      return;
    }

    final email = AppConfig.supaEmail;
    final pw = AppConfig.supaPassword;

    if (email.isEmpty || pw.isEmpty) {
      _isLoggingIn = false;
      return;
    }

    try {
      await auth.signInWithPassword(email: email, password: pw);
      _didLogin = true;
    } catch (_) {
      // nur loggen
    } finally {
      _isLoggingIn = false;
    }
  }

  // -----------------------------------------------------------
  // 5) Normale Anmeldung aus dem LoginDialog
  // -----------------------------------------------------------
  static Future<bool> signInWith(String email, String pw) async {
    try {
      await Supa.client.auth.signInWithPassword(email: email, password: pw);
      _didLogin = true;
      return true;
    } catch (_) {
      return false;
    }
  }

/// Aktuell eingeloggter Supabase-User (oder null).
static sb.User? get currentUser =>
    Supabase.instance.client.auth.currentUser;

  
  /// Aktualisiert E-Mail und/oder Passwort des aktuellen Users.
  ///
  /// Übergib nur die Werte, die wirklich geändert werden sollen
  /// (andere Parameter als null lassen).
static Future<void> updateCredentials({
  String? newEmail,
  String? newPassword,
}) async {
  final attrs = sb.UserAttributes(
    email: newEmail,
    password: newPassword,
  );

  await Supabase.instance.client.auth.updateUser(attrs);
}




}

/// Kleiner globaler Bus / Bridge zwischen TabsWrapper und HomePage
class AppBus {
  // ---- Globale Klienten-Liste (zentrale Quelle) ----
  // ---- Globale Klienten-Liste (zentrale Quelle) ----
  static Map<int, String> clientNameMap = {};
  static List<int> clientIdsSorted = [];
  static String nameById(int? id) =>
      id == null ? '' : (clientNameMap[id] ?? '');

  // Fahrdienst-Flag pro Klient (row_id → true/false)
  static Map<int, bool> clientFahrdienstMap = {};

  static bool isClientFahrdienst(int? id) {
    if (id == null) return true; // Standard: wird gefahren
    return clientFahrdienstMap[id] ?? true;
  }

  // Detail-Cache je Klient (komplette Zeile aus Supabase für Bearbeiten/Info)
  static Map<int, Map<String, dynamic>> clientDetail = {};

  // ---- Login-Dialog Debug/Lock (nur Supabase) ----
  static bool loginDialogOpen = false;
  static int loginDialogOpenCount = 0;
  static String? lastLoginDialogToken;

  // Dialog-Schließ-Callback (falls Login angezeigt wird)
  static VoidCallback? closeLoginDialog;

  // ---- Online/Offline global state ----
  static final ValueNotifier<bool> onlineVN = ValueNotifier<bool>(true);
  static bool get online => onlineVN.value;
  static set online(bool v) => onlineVN.value = v;

  // Tagesplan meldet Moduswechsel (A/M)
  static void Function(bool isMorning)? onDayModeChanged;

  // Optionaler Offline-Banner
  static Widget Function(BuildContext context)? offlineBannerBuilder;

  // Info-Panel Notifier
  static ValueNotifier<int> infoRev = ValueNotifier<int>(0);

  // Topbar-Actions
  static VoidCallback? onRefresh;
  static VoidCallback? onAdd;

  // Bridge zu „Sheets“-Kompat-Adapter (hier Supabase-Bridge)
  static dynamic Function()? getSheets;

  // Editor-/Geräteinfos (optional)
  static String? editorName;
  static String? deviceName;
  static String? deviceId;
  static String? deviceModel;

  // Navigation/Action: Tagesplan → Route
  static void Function(String text)? toRouteWithText;

  // Gemeinsamer Offline-Banner (von HomePage bereitgestellt)
  static Widget Function()? buildOfflineBanner;


  // ------------------------------------------------------------
  // SINGLETON SUPABASE-INIT
  // Verhindert doppelte / parallele Initialisierungen
  // ------------------------------------------------------------
  
}


