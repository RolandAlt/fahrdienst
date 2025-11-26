// [GitTest] Minimal Patch applied placeholder — 2025-10-16 09:19:24
// lib/main.dart

// ---------------------------------------------------------------------------
//  15.10.2025 17:50
//
//  Map Liste wird noch nicht positioniert - Speichern der Zentrale Nummern nicht korrekt. Fenster von Fahrer und Zentrale nicht korrekt
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// pubspec.yaml – unnötige Pakete kannst du entfernen:
//   - excel
//   - file_picker
//
// Benötigt bleiben u.a.:
//   connectivity_plus, device_info_plus, googleapis, googleapis_auth,
//   package_info_plus, shared_preferences, path_provider, url_launcher, font_awesome_flutter
//
// flutter:
//   assets:
//     - assets/service_key.json
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'app_bus.dart';
import 'tabs_wrapper.dart';
import 'supa_adapter.dart';
import 'dart:math' show min;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:googleapis/sheets/v4.dart' as gs;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

// Spracheingabe
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart' as stt_sr;
// import 'package:supabase/supabase.dart';
// Device_ID

import 'dart:io';
// dynamische Farben
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // für SystemNavigator.pop()

// Supa Base
import 'package:supabase_flutter/supabase_flutter.dart';

// PDF / Drucken
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

// ---------------------------------------------------
// HIER einfügen:
const _idChannel = MethodChannel('app.device/ids');
// ---------------------------------------------------
// --- Legacy-Compatibility: alter Verweis wird noch irgendwo genutzt ---
// Absichtlich nur leer -> verhindert, dass Namen in "einrichtungen row_id" geraten.

// ---------- Device Helpers (top-level) ----------
Future<String> _getStableDeviceId() async {
  try {
    if (Platform.isAndroid) {
      final s = await _idChannel.invokeMethod<String>('getAndroidId');
      return (s ?? '').trim(); // kann leer sein, wenn das System nichts liefert
    } else if (Platform.isIOS) {
      final info = DeviceInfoPlugin();
      final i = await info.iosInfo;
      return (i.identifierForVendor ?? '').trim();
    }
  } catch (_) {}
  return "";
}

Future<String> _getFriendlyDeviceName() async {
  try {
    if (Platform.isAndroid) {
      final ch = MethodChannel('app.device/friendlyname');
      final s = (await ch.invokeMethod<String>('friendlyName'))?.trim() ?? '';
      return s.isEmpty ? '(unbekannt)' : s;
    } else if (Platform.isIOS) {
      final i = await DeviceInfoPlugin().iosInfo;
      final s = (i.name ?? '').trim();
      return s.isEmpty ? '(unbekannt)' : s;
    }
  } catch (_) {}
  return '(unbekannt)';
}

Future<String> _getDeviceModel() async {
  try {
    if (Platform.isAndroid) {
      final a = await DeviceInfoPlugin().androidInfo;
      final brand = (a.brand ?? a.manufacturer ?? '').trim(); // z. B. "HUAWEI"
      final model = (a.model ?? '').trim(); // z. B. "CLT-L09"
      final composed = [brand, model].where((s) => s.isNotEmpty).join(' ');
      return composed.isEmpty ? '(unbekannt)' : composed; // "HUAWEI CLT-L09"
    } else if (Platform.isIOS) {
      final i = await DeviceInfoPlugin().iosInfo;
      // Bei iOS ist "model" oft generisch; wir nehmen den Maschinen-Namen als Modell
      final machine = (i.utsname.machine ?? '').trim();
      final model = (i.model ?? '').trim();
      final composed = machine.isNotEmpty ? machine : model;
      return composed.isEmpty ? '(unbekannt)' : composed;
    }
  } catch (_) {}
  return '(unbekannt)';
}

// Helper für Chip-Darstellung
class _ChipVisuals {
  final Color border;
  final Color fill;
  final TextStyle labelStyle;
  const _ChipVisuals({
    required this.border,
    required this.fill,
    required this.labelStyle,
  });
}

// ---------------------------------------------------------------------------
// Konfiguration
// ---------------------------------------------------------------------------
class _Config {
  static const defaultCountryCode = '49';
  static const spreadsheetId = '1f94whr7-En3IcbLRw71x-tRKrMqBlpl51du4M8P1yWc';
  static const sheetName = 'Klienten';

  // Config-Sheet-Tab
  static const configSheetTitle = 'Einrichtungen';
  static const serviceKeyAsset = 'assets/service_key.json';
  // Config Supa Tag Datenquelle
  // Config Supa Tag Datenquelle
  static const configSupaText1 = 'Supabase';
  static const configSupaText2 = 'Tabellen Design';
  static const configSupaDesign = 'Public';

  // Hier trägst du die Version ein, die in deiner pubspec.yaml steht!
  static const supabaseDartVersion =
      '2.10.0'; // <== bitte prüfen in pubspec.yaml!

  // Lokaler Cache
  static const localCacheFile = 'stammdaten_cache.json';
  static const cacheSchema = 1;

  // Polling/Timeout
  static const pollInterval = Duration(minutes: 15);
  static const resumeRefreshMaxAge = Duration(seconds: 90);
  // static const resumeRefreshMaxAge = Duration(minutes: 15);

  // Google Maps
  static const mapsMaxStopsHint = 10;

  // -------------------------------------------------------------------------
  // UKS-Statusfarben (global verwendbar)
  // -------------------------------------------------------------------------
  // Basisfarben für Urlaub / Krank / Sonstiges
  static const uksUrlaubColor = Color(0xFFD5F5D5); // hellgrün
  static const uksKrankColor = Color(0xFFFFD6D6); // hellrot
  static const uksSonstigesColor = Color(0xFFDBE9FF); // hellblau
}

// ---------------------------------------------------------------------------
// Datenmodell
// ---------------------------------------------------------------------------
class Person {
  String? rowId;
  String? nr;
  String name;
  String vorname;
  String adresse;
  String ortsteil;
  String telefon;
  String angehoerige;
  String angeTel;
  String betreuer;
  String betreuerTel;
  String rs; // Ja/Nein (Default: Nein)
  String besonderheiten;
  String infosWohn;
  String tagespflege;
  String hilfeBei;
  String schluessel;
  String klingel;
  String sonstiges;

  String aktiv; // Ja/Nein (Default: Ja)
  String fahrdienst; // Ja/Nein (Default: Ja)
  String einrichtungenRowId; // row_id der Einrichtung (Default: '')

  String? updatedAt;
  String? lastEditor;
  String? lastEditorDevice;
  String? lastEditorDeviceId;
  String? lastEditorDeviceName;
  Map<String, String> extra;

  Person({
    this.rowId,
    this.nr,
    required this.name,
    required this.vorname,
    required this.adresse,
    this.ortsteil = '',
    this.telefon = '',
    this.angehoerige = '',
    this.angeTel = '',
    this.betreuer = '',
    this.betreuerTel = '',
    this.rs = 'Nein', // ← Default geändert auf "Nein"
    this.besonderheiten = '',
    this.infosWohn = '',
    this.tagespflege = '',
    this.hilfeBei = '',
    this.schluessel = '',
    this.klingel = '',
    this.sonstiges = '',
    this.aktiv = 'Ja', // ← neu: Default "Ja"
    this.fahrdienst = 'Ja', // ← neu: Default "Ja"
    this.einrichtungenRowId = '', // ← neu
    this.updatedAt,
    this.lastEditor,
    this.lastEditorDevice,
    this.lastEditorDeviceId,
    this.lastEditorDeviceName,
    Map<String, String>? extra,
  }) : extra = extra ?? {};

  String get vollName => '$name, $vorname';

  Map<String, dynamic> toJson() => {
    'row_id': rowId,
    'nr': nr,
    'name': name,
    'vorname': vorname,
    'adresse': adresse,
    'ortsteil': ortsteil,
    'telefon': telefon,
    'angehoerige': angehoerige,
    'angeTel': angeTel,
    'betreuer': betreuer,
    'betreuerTel': betreuerTel,
    'rs': rs,
    'besonderheiten': besonderheiten,
    'infosWohn': infosWohn,
    'tagespflege': tagespflege,
    'hilfeBei': hilfeBei,
    'schluessel': schluessel,
    'klingel': klingel,
    'sonstiges': sonstiges,

    // neu in JSON:
    'aktiv': aktiv,
    'fahrdienst': fahrdienst,
    'einrichtungen row_id': einrichtungenRowId,

    'updated_at': updatedAt,
    'last_editor': lastEditor,
    'last_editor_device': lastEditorDevice,
    'last_editor_device_id': lastEditorDeviceId,
    'last_editor_device_name': lastEditorDeviceName,
    'extra': extra,
  };

  static Person fromJson(Map<String, dynamic> j) {
    String _s(dynamic v) => (v ?? '').toString().trim();
    String _normJN(dynamic v, {required String def}) {
      final t = _s(v).toLowerCase();
      if (t.isEmpty) return def;
      return t == 'ja' ? 'Ja' : 'Nein';
    }

    return Person(
      rowId: _s(j['row_id']),
      nr: _s(j['nr']),
      name: _s(j['name']),
      vorname: _s(j['vorname']),
      adresse: _s(j['adresse']),
      ortsteil: _s(j['ortsteil']),
      telefon: _s(j['telefon']),
      angehoerige: _s(j['angehoerige']),
      angeTel: _s(j['angeTel']),
      betreuer: _s(j['betreuer']),
      betreuerTel: _s(j['betreuerTel']),

      // Ja/Nein normalisiert, Default "Nein"
      rs: _normJN(j['rs'], def: 'Nein'),

      besonderheiten: _s(j['besonderheiten']),
      infosWohn: _s(j['infosWohn']),
      tagespflege: _s(j['tagespflege']),
      hilfeBei: _s(j['hilfeBei']),
      schluessel: _s(j['schluessel']),
      klingel: _s(j['klingel']),
      sonstiges: _s(j['sonstiges']),

      // neu: Ja/Nein normalisiert, Defaults "Ja"
      aktiv: _normJN(j['aktiv'], def: 'Ja'),
      fahrdienst: _normJN(j['fahrdienst'], def: 'Ja'),

      // neu: Einrichtungen row_id
      einrichtungenRowId: _s(j['einrichtungen row_id']),

      updatedAt: _s(j['updated_at']).isEmpty ? null : _s(j['updated_at']),
      lastEditor: _s(j['last_editor']).isEmpty ? null : _s(j['last_editor']),
      lastEditorDevice: _s(j['last_editor_device']).isEmpty
          ? null
          : _s(j['last_editor_device']),
      lastEditorDeviceId: _s(j['last_editor_device_id']).isEmpty
          ? null
          : _s(j['last_editor_device_id']),
      lastEditorDeviceName: _s(j['last_editor_device_name']).isEmpty
          ? null
          : _s(j['last_editor_device_name']),

      extra: (j['extra'] is Map)
          ? (j['extra'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : <String, String>{},
    );
  }
}

Person _personFromSheetRow(Map<String, int> col, List<String> row) {
  String v(String key) {
    final idx = col[key];
    if (idx == null) return '';
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].trim();
  }

  return Person(
    rowId: v('row_id').isNotEmpty ? v('row_id') : null,
    nr: v('nr.').isEmpty ? null : v('nr.'),
    name: v('name'),
    vorname: v('vorname'),
    adresse: v('adresse'),
    ortsteil: v('ortsteil'),
    telefon: v('telefon'),
    angehoerige: v('angehörige'),
    angeTel: v('angehörige tel.'),
    betreuer: v('betreuer'),
    betreuerTel: v('betreuer tel.'),
    rs: v('rs'),
    besonderheiten: v('besonderheiten'),
    infosWohn: v('infos zur wohnsituation'),
    tagespflege: v('tagespflege (wochentage)'),
    hilfeBei: v('hilfe bei'),
    schluessel: v('schlüssel'),
    klingel: v('klingelzeichen'),
    sonstiges: v('sonstige informationen'),
    updatedAt: v('updated_at'),
    lastEditor: v('last_editor'),
    lastEditorDevice: v('last_editor_device'),
    lastEditorDeviceId: v('last_editor_device_id'),
    lastEditorDeviceName: v('last_editor_device_name'),
  );
}

// ---------------------------------------------------------------------------
// Hilfsklassen für Normalisierung & Highlighting (Top-Level!)
// ---------------------------------------------------------------------------
class _NormalizeResult {
  final String norm;
  final List<int> map2orig;
  const _NormalizeResult(this.norm, this.map2orig);
}

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

// =================== REPLACEMENT: main.dart (main) ===================
// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // NEU: Remember-Flag laden, bevor UI losläuft
  await AppAuth.initRememberFlag();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo; // Fallback, wenn keine Systemfarben da sind

    return DynamicColorBuilder(
      builder: (dynamicLight, dynamicDark) {
        // Systemfarben (Material You) verwenden, falls verfügbar – sonst Seed
        final lightScheme =
            (dynamicLight ??
                    ColorScheme.fromSeed(
                      seedColor: seed,
                      brightness: Brightness.light,
                    ))
                .harmonized();

        final darkScheme =
            (dynamicDark ??
                    ColorScheme.fromSeed(
                      seedColor: seed,
                      brightness: Brightness.dark,
                    ))
                .harmonized();

        return MaterialApp(
          title: 'Fahrdienst',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,

          // Erzwingt Deutsch in der App (auch wenn das Handy z.B. auf Englisch steht)
          locale: const Locale('de'),

          // Lokalisierungs-Delegates aktivieren
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          // Welche Sprachen die App grundsätzlich kann
          supportedLocales: const [Locale('de'), Locale('en')],

          // ---------- LIGHT ----------
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
            brightness: Brightness.light,
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: lightScheme.primaryContainer.withOpacity(0.18),
              hintStyle: TextStyle(
                color: lightScheme.onSurface.withOpacity(0.62),
              ),
              prefixIconColor: lightScheme.onSurfaceVariant,
              suffixIconColor: lightScheme.onSurfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: lightScheme.primary.withOpacity(0.30),
                  width: 1,
                ),
              ),
            ),
            searchBarTheme: SearchBarThemeData(
              backgroundColor: WidgetStatePropertyAll(
                lightScheme.primaryContainer.withOpacity(0.18),
              ),
              elevation: const WidgetStatePropertyAll(0),
              hintStyle: WidgetStatePropertyAll(
                TextStyle(color: lightScheme.onSurface.withOpacity(0.62)),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: lightScheme.primary.withOpacity(0.30),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),

          // ---------- DARK ----------
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
            brightness: Brightness.dark,
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: darkScheme.primaryContainer.withOpacity(0.24),
              hintStyle: TextStyle(
                color: darkScheme.onSurface.withOpacity(0.68),
              ),
              prefixIconColor: darkScheme.onSurfaceVariant,
              suffixIconColor: darkScheme.onSurfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: darkScheme.primary.withOpacity(0.35),
                  width: 1,
                ),
              ),
            ),
            searchBarTheme: SearchBarThemeData(
              backgroundColor: WidgetStatePropertyAll(
                darkScheme.primaryContainer.withOpacity(0.24),
              ),
              elevation: const WidgetStatePropertyAll(0),
              hintStyle: WidgetStatePropertyAll(
                TextStyle(color: darkScheme.onSurface.withOpacity(0.68)),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: darkScheme.primary.withOpacity(0.35),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),

          home: const TabsWrapper(),
        );
      },
    );
  }
}

// ---------- InfoPanel (public) ----------
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.appVersion,
    required this.appBuild,
    this.statusText, // optional
    this.deviceName, // optional
    this.deviceModel, // optional
    this.deviceId, // optional
    this.sheetId, // optional
    required this.driverName,
    required this.centralName,
    required this.centralAddress,
    required this.centralPhones,
    this.updatedAt, // optional
    this.onEditDriver, // optional
    this.onEditCentral, // optional
  });

  // Felder (alle final, passend zu oben)
  final String appVersion;
  final String appBuild;
  final String? statusText;
  final String? deviceName;
  final String? deviceModel; // <— Modell (z. B. "HUAWEI CLT-L09")
  final String? deviceId; // <— Geräternummer / ANDROID_ID
  final String? sheetId;
  final String driverName;
  final String centralName;
  final String centralAddress;
  final List<String> centralPhones;
  final DateTime? updatedAt;
  final VoidCallback? onEditDriver;
  final VoidCallback? onEditCentral;

  @override
  Widget build(BuildContext context) {
    String fmt(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keyColor = isDark ? Colors.white70 : Colors.black54;

    // Values & fallbacks
    final versionStr = '${appVersion} (Build ${appBuild})';
    final statusStr = (statusText == null || statusText!.trim().isEmpty)
        ? '–'
        : statusText!.trim();
    final lastSyncStr = (updatedAt != null) ? fmt(updatedAt!) : '–';

    final drv = driverName.trim().isEmpty
        ? '(nicht gesetzt)'
        : driverName.trim();

    final cName = centralName.trim();
    final cAddr = centralAddress.trim();
    final phones = centralPhones.where((s) => s.trim().isNotEmpty).toList();
    final phoneLine = phones.join(' · ');

    final devName = (deviceName == null || deviceName!.trim().isEmpty)
        ? '–'
        : deviceName!.trim();
    final devId = (deviceId == null || deviceId!.trim().isEmpty)
        ? '–'
        : deviceId!.trim();
    final sheet = (sheetId == null || sheetId!.trim().isEmpty)
        ? '–'
        : sheetId!.trim();
    final devModel = (deviceModel == null || deviceModel!.trim().isEmpty)
        ? '–'
        : deviceModel!.trim();

    Widget sectionTitle(String title, {VoidCallback? onEdit}) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );

    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$k:', style: TextStyle(color: keyColor)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((statusText ?? '').toLowerCase() != 'online')
          Container(
            width: double.infinity,
            color: isDark ? Colors.amber.shade700 : Colors.amber.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Offline - Schreibgeschützt',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.black : Colors.black87,
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App-Informationen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                kv('Version', versionStr),
                kv('Status', statusStr),
                kv('Letzter Sync', lastSyncStr),
                const Divider(height: 16),

                // --- Mitarbeiter: immer mit Bearbeiten-Schalter ---
                (() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle('Mitarbeiter', onEdit: onEditDriver),
                      kv('Name', drv),
                    ],
                  );
                })(),

                const Divider(height: 16),

                // --- Zentrale: Bearbeiten-Button bleibt immer sichtbar ---
                sectionTitle('Zentrale', onEdit: onEditCentral),
                kv('Name', cName.isEmpty ? '(nicht gesetzt)' : cName),
                if (cAddr.isNotEmpty) kv('Adresse', cAddr),
                if (phoneLine.isNotEmpty) kv('Telefon', phoneLine),
                const Divider(height: 16),

                sectionTitle('Geräte Informationen'),
                kv('Name', devName),
                kv('Model', devModel),
                kv('Nummer', devId),
                const Divider(height: 16),

                sectionTitle('Datenquelle'),

                kv(
                  _Config.configSupaText1,
                  'Dart ${_Config.supabaseDartVersion}',
                ),

                kv(_Config.configSupaText2, _Config.configSupaDesign),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.showAppBar = true,
    this.initialMapMode = false,
  });
  final bool showAppBar;
  final bool initialMapMode;
  @override
  State<HomePage> createState() => _HomePageState();
}

// =================== ADD (oberhalb class _HomePageState . . .) ===================
String boolToJN(dynamic v) {
  final b = (v is bool) ? v : (v?.toString().toLowerCase() == 'true');
  return b == true ? 'Ja' : 'Nein';
}

bool jnToBool(dynamic v) {
  final s = (v ?? '').toString().trim().toLowerCase();
  return s == 'ja' || s == 'true' || s == '1';
}
// =================== END ADD ===================

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Auto-Refresh: Listener für Klienten-Änderungen
  VoidCallback? _clientChangeListener;
  VoidCallback? _dayPlanChangeListener;
  VoidCallback? _dienstplanChangeListener;
  VoidCallback? _vehicleChangeListener;
  VoidCallback? _einrChangeListener;

  // ===== Helper: erkennen, ob Supabase aktiv ist (ersetzt "USE_SUPABASE") =====
  bool get _isSupabaseMode {
    final sc = AppBus.getSheets?.call();
    return sc
        is SupaSheetsAdapter; // benötigt import von supa_adapter.dart (ist bei dir schon üblich)
    // Falls du den Typ nicht importieren willst:
    // return (sc?.runtimeType.toString().toLowerCase().contains('supa') ?? false);
  }

  // =================== ADD: main.dart -> _HomePageState Felder ===================
  bool _clientsLoading = false;
  int _clientsLoadGen = 0;
  // =================== END ADD ===================
  // Polling während modaler Dialoge aussetzen
  bool _suspendPolling = false;

  // === Klienten-Cache (UI) ===
  // === Klienten-Cache (UI) – zentrale Quelle = AppBus ===

  List<int> get _clientIdsSorted => AppBus.clientIdsSorted;
  String nameById(int? id) => AppBus.nameById(id);

  // Falls noch nicht vorhanden – nur EINMAL einfügen:
  final TextEditingController _routeSearchCtrl = TextEditingController();

  List<Person> _personenAlle = [];
  List<Person> _personenSichtbar = [];

  List<Person> _alle = [];
  List<Person> _sichtbar = [];

  // ======= _rebuildClientListsFromCache (KOMPLETT) =======
  void _rebuildClientListsFromCache() {
    final map =
        AppBus.clientNameMap; // Map<int, String>  (id -> "Name Vorname")
    final ids = AppBus.clientIdsSorted; // List<int>         (sortierte IDs)

    final list = <Person>[];

    // Wenn wir bereits vollständige Personen (inkl. Adresse/Ortsteil) haben,
    // dann verwenden wir DIESE als Quelle – in der Reihenfolge der IDs.
    if (_personenAlle.isNotEmpty && ids.isNotEmpty) {
      final byId = <int, Person>{};
      for (final p in _personenAlle) {
        final id = int.tryParse((p.rowId ?? '').trim());
        if (id != null && id > 0) byId[id] = p;
      }

      for (final id in ids) {
        final p = byId[id];
        if (p != null) {
          list.add(p); // enthält adresse/ortsteil
        } else {
          final full = (map[id] ?? '').trim();
          if (full.isEmpty) continue;
          final parts = full.split(' ').where((e) => e.isNotEmpty).toList();
          String name = '';
          String vorname = '';
          if (parts.isNotEmpty) {
            name = parts.first;
            if (parts.length > 1) vorname = parts.sublist(1).join(' ');
          }
          list.add(
            Person(
              rowId: '$id',
              name: name,
              vorname: vorname,
              adresse: '',
              ortsteil: '',
              telefon: '',
              aktiv: 'Ja',
              fahrdienst: 'Ja',
            ),
          );
        }
      }
    } else {
      // Ursprungslogik (nur NameMap → keine Adressen)
      for (final id in ids) {
        final full = (map[id] ?? '').trim();
        if (full.isEmpty) continue;
        final parts = full.split(' ').where((e) => e.isNotEmpty).toList();
        String name = '';
        String vorname = '';
        if (parts.isNotEmpty) {
          name = parts.first;
          if (parts.length > 1) vorname = parts.sublist(1).join(' ');
        }
        list.add(
          Person(
            rowId: '$id',
            name: name,
            vorname: vorname,
            adresse: '',
            ortsteil: '',
            telefon: '',
            aktiv: 'Ja',
            fahrdienst: 'Ja',
          ),
        );
      }
    }

    list.sort((a, b) {
      final na = ('${a.name} ${a.vorname}').toLowerCase();
      final nb = ('${b.name} ${b.vorname}').toLowerCase();
      return na.compareTo(nb);
    });

    setState(() {
      _alle = list;
    });

    // Route-Tab: Liste anhand des aktuellen Such-/Map-Textes neu aufbauen,
    // damit nach einem Refresh weiterhin die Personen aus der Eingabe sichtbar bleiben.
    _applyFilterEnhanced();

    debugPrint(
      '[KlientenUI] rebuilt: alle=${_alle.length}, sichtbar=${_sichtbar.length}, personenAlle=${_personenAlle.length}',
    );
  }

  // ======= /_rebuildClientListsFromCache =======

  // Aktuell gewählte Einrichtung (row_id) – persistent
  String _einrichtungRowId = '';
  // Einheitlicher Zugriff (niemals null)
  String get _currentEinrichtungRowId => _einrichtungRowId.trim();

  // ------------------------------------------------------------
  // Offline-Banner (gemeinsame Anzeige für alle Tabs)
  // ------------------------------------------------------------
  Widget _offlineBanner() {
    final online = _online; // falls du _isOnline oder _online nutzt
    return Container(
      width: double.infinity,
      color: online ? Colors.green.shade100 : Colors.red.shade100,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            online ? Icons.wifi : Icons.wifi_off,
            color: online ? Colors.green.shade700 : Colors.red.shade700,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'Online' : 'Offline – Schreibgeschützt',
            style: TextStyle(
              color: online ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildInfoPanelForWrapper() {
    return ValueListenableBuilder<int>(
      valueListenable: AppBus.infoRev,
      builder: (context, _, __) => InfoPanel(
        appVersion: _appVersion,
        appBuild: _appBuild,
        statusText: _online ? 'Online' : 'Offline',
        deviceName: _deviceName,
        deviceModel: _deviceModel,
        deviceId: _deviceId,
        sheetId: _Config.spreadsheetId,
        driverName: _driverName,
        centralName: _centralName,
        centralAddress: _centralAddress,
        centralPhones: [
          if (_centralPhone1.trim().isNotEmpty) _centralPhone1.trim(),
          if (_centralPhone2.trim().isNotEmpty) _centralPhone2.trim(),
          if (_centralPhone3.trim().isNotEmpty) _centralPhone3.trim(),
        ],
        updatedAt: _lastSync,
        onEditDriver: _showEditMitarbeiterDialog,
        onEditCentral: _promptEditCentral,
      ),
    );
  }

  // Exposed for TabsWrapper 'Info' tab
  void showAppInfoFromWrapper() => _showAppInfo();

  void refreshFromWrapper() => _pullFromSheet();
  void addPersonFromWrapper() => _addPerson();

  // --- Offline-Banner dem Wrapper/Tagesplan bereitstellen ---
  // Widget buildOfflineBannerForWrapper() => _offlineBanner();

  // Beispiel – bitte GENAU deine alte Zeile wiederherstellen!
  // final _sheets = SheetsBridge();   // <-- ersetze SheetsBridge() durch deinen echten Konstruktor

  // === Wrapper API: wird vom TabsWrapper genutzt, um den Route-Text zu setzen ===
  void setRouteInputFromWrapper(String text) {
    _searchCtrl.text = text;
    _searchCtrl.selection = TextSelection.collapsed(
      offset: _searchCtrl.text.length,
    );

    _applyFilterEnhanced(); // Methode ohne Fragezeichen

    setState(() {});
  }

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // --- Route-Tab: Fokusgesteuerte Eingabegröße ---
  final FocusNode _routeSearchFocus = FocusNode();
  bool _routeSearchFocused = false;

  // === Sheets-Client aus AppBus holen (hält alte _sheets.<. . .>-Aufrufe funktionsfähig)
  // === Zeilenhöhe für Scroll-Berechnung ===
  static const double _rowApproxHeight = 72.0;

  // Dein Sheets-Objekt (konkreter Typ egal, wir verwenden dynamic)
  late final dynamic _sheets;

  /// Hängt einen neuen „Token-Text“ ans Map-Suchfeld an (mit sauberem Trenner).
  String _appendToMapQuery(String addition) {
    final base0 = _searchCtrl.text;
    final add = addition; // keine Auto-Trim/Trenner, wir hängen exakt an
    if (add.isEmpty) return base0;
    // Einheitliches Mikrofon-Verhalten: nichts löschen, keine Auto-Trenner, einfach anhängen
    return base0 + add;
  }

  // Map-Suchmodus & Route
  bool _mapMode = false;
  String? _routeUrl;

  // Online/Offline
  bool _online = true;
  StreamSubscription? _connSub;

  // Auto-Refresh
  Timer? _pollTimer;
  DateTime? _lastSync;
  bool _editOpen = false;

  // Suche Debounce
  Timer? _searchDebounce;

  // Identität/Version
  String _deviceName = '(unbekannt)';
  String _deviceId = '(unbekannt)';
  String _deviceModel = '(unbekannt)';
  String _driverName = '';
  String _appVersion = '';
  String _appBuild = '';

  // Zentrale (aus Config-Tab + lokal)
  String _centralName = '';
  String _centralAddress = '';
  String _centralPhone1 = '';
  String _centralPhone2 = '';
  String _centralPhone3 = '';
  String _centralPhone = ''; // <— Legacy: für Rückwärtskompatibilität

  // Spracheingabe
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _speechWantsMap =
      false; // merkt, ob während Spracheingabe der Map-Modus gewünscht ist

  bool _listening = false;
  String? _speechLocaleId;
  String _lastSpeechText = '';
  int _speechAutoRestarts = 0;
  static const int _maxSpeechAutoRestarts = 3;

  // Entdoppelung (Liste aus Sheet, nicht Map-Route)
  List<Person> _uniquePeople(List<Person> list) {
    final seen = <String>{};
    final out = <Person>[];
    String keyFor(Person p) {
      final rid = (p.rowId ?? '').trim();
      final nr = (p.nr ?? '').trim();
      if (rid.isNotEmpty) return 'rid:$rid';
      if (nr.isNotEmpty) return 'nr:$nr';
      final n = p.name.trim().toLowerCase();
      final v = p.vorname.trim().toLowerCase();
      final ad = p.adresse.trim().toLowerCase();
      return 'nva:$n|$v|$ad';
    }

    for (final p in list) {
      final k = keyFor(p);
      if (seen.add(k)) out.add(p);
    }
    return out;
  }

  // Normalisiert "(unbekannt)" → '' und trimmt.
  String _nz(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '';
    if (s.toLowerCase() == '(unbekannt)') return '';
    return s;
  }

  // Liefert die row_id der aktuell gewählten Einrichtung (nur echte ID, KEIN Name)
  String get _activeEinrichtungRowId {
    try {
      final s = (_einrichtungRowId).toString().trim();
      // row_id ist bei dir numerisch (Sheets-Row-ID / laufende ID)
      final isNumeric = RegExp(r'^\d+$');
      if (s.isNotEmpty && isNumeric.hasMatch(s)) {
        return s;
      }
    } catch (_) {}
    // Niemals auf Namen zurückfallen – lieber leer lassen als falsche Werte schreiben
    debugPrint('[activeEinrichtungRowId] none available, return empty');

    return '';
  }

  // Schreibt die aktuell bekannten Identitätswerte in AppBus.
  void _seedAppBusIdentity() {
    AppBus.editorName = _nz(_driverName); // Mitarbeiter/Fahrername
    AppBus.deviceName = _nz(_deviceName); // freundlicher Gerätename
    AppBus.deviceModel = _nz(_deviceModel); // Modell-Bezeichnung
    AppBus.deviceId = _nz(_deviceId); // stabile Geräte-ID
    debugPrint(
      '[AppBus seed] editor="${AppBus.editorName}" '
      'name="${AppBus.deviceName}" model="${AppBus.deviceModel}" id="${AppBus.deviceId}"',
    );
  }

  bool _loginDialogShown = false; // <— NEU (als Feld der State-Klasse)

  List<Person> _maybeInjectZentrale(List<Person> list, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;

    // Erkenne 'z' / 'zent' / 'zentrale' etc.
    final hit = q == 'z' || q.startsWith('zent') || q.contains('zentrale');
    if (!hit) return list;

    // Einmalig hinzufügen, wenn noch nicht vorhanden
    final already = list.any((p) => (p.name.toLowerCase() == 'zentrale'));
    if (already) return list;

    final zentrale = Person(
      rowId: null,
      nr: null,
      name: 'Zentrale',
      vorname: '',
      adresse: 'Haus am Vierstädtepark, Parkstraße 10, 63679 Schotten',
      ortsteil: '',
      telefon: '',
      angehoerige: '',
      angeTel: '',
      betreuer: '',
      betreuerTel: '',
      rs: 'Nein',
      besonderheiten: '',
      infosWohn: '',
      tagespflege: '',
      hilfeBei: '',
      schluessel: '',
      klingel: '',
      sonstiges: '',
      aktiv: 'Ja',
      fahrdienst: 'Nein',
      einrichtungenRowId: '',
      extra: const {},
    );

    return [zentrale, ...list];
  }

  Future<void> _showEditMitarbeiterDialog() async {
    final mit = await SupaAdapter.mitarbeiter
        .fetchCurrentMitarbeiterWithFunktion();
    if (mit == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Mitarbeiter-Datensatz gefunden.')),
      );
      return;
    }

    final rowId = mit['row_id'] as int;

    // Maske für das Passwortfeld (Anzeige, aber kein echtes Passwort)
    const String _pwMask = '*********';

    // Controller
    final ctrAdresse = TextEditingController(text: mit['Adresse'] ?? '');
    final ctrOrtsteil = TextEditingController(text: mit['Ortsteil'] ?? '');
    final ctrTel1 = TextEditingController(text: mit['Telefonnummer 1'] ?? '');
    final ctrTel2 = TextEditingController(text: mit['Telefonnummer 2'] ?? '');
    final ctrTel3 = TextEditingController(text: mit['Telefonnummer 3'] ?? '');
    final ctrEmail = TextEditingController(text: mit['E-Mail-Adresse'] ?? '');
    final ctrBem = TextEditingController(text: mit['Bemerkung'] ?? '');

    // Passwort nie mit echtem Wert vorbefüllen → nur Maske
    final ctrPassword = TextEditingController(text: _pwMask);

    DateTime? geb = (mit['Geburtsdatum'] as String?) != null
        ? DateTime.tryParse(mit['Geburtsdatum'])
        : null;

    DateTime? arbeitsbeginn = (mit['Arbeitsbeginn Datum'] as String?) != null
        ? DateTime.tryParse(mit['Arbeitsbeginn Datum'])
        : null;

    // Einfache E-Mail-Formatprüfung
    bool _isValidEmail(String email) {
      email = email.trim();
      if (email.isEmpty) return false;
      final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      return regex.hasMatch(email);
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        String? errorText; // Fehlerzeile unter dem Kennwortfeld / E-Mail
        bool pwVisible = false; // Zustand für Auge-Symbol
        bool emailUnlocked = false; // Admin-Freigabe für E-Mail-Feld

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Widget für E-Mail: standardmäßig read-only, per Long-Press freischaltbar
            Widget _emailField() {
              if (emailUnlocked) {
                // jetzt editierbar wie bisher
                return _tf('E-Mail-Adresse (Login)', ctrEmail);
              }

              // read-only + Long-Press zum Freischalten
              return GestureDetector(
                onLongPress: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    barrierDismissible: true,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Admin-Freigabe'),
                      content: const Text(
                        'Die Login-E-Mail sollte nur von einem Administrator '
                        'geändert werden.\n\nE-Mail-Feld zur Bearbeitung freigeben?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Abbrechen'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Freigeben'),
                        ),
                      ],
                    ),
                  );

                  if (ok == true) {
                    setStateDialog(() {
                      emailUnlocked = true;
                    });
                  }
                },
                child: _ro('E-Mail-Adresse (Login)', ctrEmail.text),
              );
            }

            return AlertDialog(
              title: const Text('Mitarbeiter bearbeiten'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // ----- READ-ONLY FELDER -----
                      _ro('Aktiv', mit['Aktiv'] == true ? 'Ja' : 'Nein'),
                      _ro('Nr.', '${mit['Nr.'] ?? ''}'),
                      _ro('Name', '${mit['Name'] ?? ''}'),
                      _ro('Vorname', '${mit['Vorname'] ?? ''}'),
                      _ro('Funktion', '${mit['funktion_text'] ?? ''}'),

                      const SizedBox(height: 10),

                      // ----- EDIT FELDER -----
                      _tf('Adresse', ctrAdresse),
                      _tf('Ortsteil', ctrOrtsteil),
                      _tf('Telefon 1', ctrTel1),
                      _tf('Telefon 2', ctrTel2),
                      _tf('Telefon 3', ctrTel3),
                      // ---- E-MAIL (neu positioniert!) ----
                      _emailField(),

                      const SizedBox(height: 10),
                      // ----- LOGIN KENNWORT MIT AUGE -----
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: ctrPassword,
                              obscureText: !pwVisible,
                              onTap: () {
                                // Wenn nur die Maske drin steht, beim ersten Antippen leeren
                                if (ctrPassword.text == _pwMask) {
                                  ctrPassword.clear();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Login Kennwort',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setStateDialog(() {
                                      pwVisible = !pwVisible;
                                    });
                                  },
                                  icon: Icon(
                                    pwVisible
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                ),
                              ),
                            ),
                            if (errorText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ----- DATUM -----
                      _dateField(
                        context: context,
                        label: 'Geburtsdatum',
                        value: geb,
                        onPicked: (d) {
                          setStateDialog(() => geb = d);
                        },
                      ),
                      _dateField(
                        context: context,
                        label: 'Arbeitsbeginn Datum',
                        value: arbeitsbeginn,
                        onPicked: (d) {
                          setStateDialog(() => arbeitsbeginn = d);
                        },
                      ),

                      const SizedBox(height: 10),
                      _tf('Bemerkung', ctrBem, maxLines: 3),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () async {
                    setStateDialog(() {
                      errorText = null; // alte Fehlermeldung zurücksetzen
                    });

                    try {
                      final updateMap = <String, dynamic>{};

                      void upd(String col, String val, String? old) {
                        if (val.trim() != (old ?? '').trim()) {
                          updateMap[col] = val.trim().isEmpty
                              ? null
                              : val.trim();
                        }
                      }

                      upd('Adresse', ctrAdresse.text, mit['Adresse']);
                      upd('Ortsteil', ctrOrtsteil.text, mit['Ortsteil']);
                      upd(
                        'Telefonnummer 1',
                        ctrTel1.text,
                        mit['Telefonnummer 1'],
                      );
                      upd(
                        'Telefonnummer 2',
                        ctrTel2.text,
                        mit['Telefonnummer 2'],
                      );
                      upd(
                        'Telefonnummer 3',
                        ctrTel3.text,
                        mit['Telefonnummer 3'],
                      );
                      upd('Bemerkung', ctrBem.text, mit['Bemerkung']);

                      // Email → zwei Stellen aktualisieren
                      final newEmail = ctrEmail.text.trim();
                      final oldEmail = (mit['E-Mail-Adresse'] ?? '').trim();
                      final emailChanged = newEmail != oldEmail;

                      if (emailChanged) {
                        if (!_isValidEmail(newEmail)) {
                          setStateDialog(() {
                            errorText =
                                'Bitte eine gültige E-Mail-Adresse eingeben.';
                          });
                          return;
                        }
                        updateMap['E-Mail-Adresse'] = newEmail;
                      }

                      // Datum formatieren
                      String? fmtDate(DateTime? d) => d == null
                          ? null
                          : d.toIso8601String().split('T').first;

                      if (fmtDate(geb) != mit['Geburtsdatum']) {
                        updateMap['Geburtsdatum'] = fmtDate(geb);
                      }

                      if (fmtDate(arbeitsbeginn) !=
                          mit['Arbeitsbeginn Datum']) {
                        updateMap['Arbeitsbeginn Datum'] = fmtDate(
                          arbeitsbeginn,
                        );
                      }

                      // Passwort-Logik mit Maske:
                      final rawPw = ctrPassword.text.trim();
                      final pwChanged = rawPw.isNotEmpty && rawPw != _pwMask;

                      // Mindestlänge-Prüfung vor dem Auth-Call
                      if (pwChanged && rawPw.length < 6) {
                        setStateDialog(() {
                          errorText =
                              'Das Login-Kennwort muss mindestens 6 Zeichen lang sein.';
                        });
                        return;
                      }

                      bool credentialsUpdated = false;

                      // --- AUTH-UPDATE (wenn Email oder Passwort geändert wurde) ---
                      if (emailChanged || pwChanged) {
                        try {
                          await AppAuth.updateCredentials(
                            newEmail: emailChanged ? newEmail : null,
                            newPassword: pwChanged ? rawPw : null,
                          );
                          credentialsUpdated = true;
                        } catch (e) {
                          // Fehler sichtbar im Dialog anzeigen, Dialog bleibt offen
                          setStateDialog(() {
                            errorText =
                                'Fehler beim Aktualisieren der Zugangsdaten: $e';
                          });
                          return;
                        }
                      }

                      // --- Mitarbeiter-Tabelle aktualisieren ---
                      if (updateMap.isNotEmpty) {
                        await SupaAdapter.mitarbeiter.updateMitarbeiterRow(
                          rowId: rowId,
                          values: updateMap,
                        );
                      }

                      // Wenn Zugangsdaten geändert wurden:
                      // 1) gespeicherte Credentials löschen,
                      // 2) Hinweisdialog zeigen,
                      // 3) bei E-Mail-Änderung App beenden
                      if (credentialsUpdated) {
                        try {
                          await AppAuth.clearStoredCredentials(
                            newEmail: emailChanged ? newEmail : null,
                          );
                        } catch (e) {
                          debugPrint(
                            '[MitarbeiterDialog] Fehler beim Löschen/Anpassen gespeicherter Zugangsdaten: $e',
                          );
                        }

                        if (!mounted) return;
                        await showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Zugangsdaten geändert'),
                            content: Text(
                              emailChanged
                                  ? 'Die Login-E-Mail oder das Kennwort wurden geändert.\n\n'
                                        'Bitte bestätigen Sie ggf. die E-Mail über den zugesandten Link '
                                        'und melden Sie sich anschließend erneut an.'
                                  : 'Das Login-Kennwort wurde geändert.\n\n'
                                        'Bitte melden Sie sich beim nächsten Start mit dem neuen Kennwort an.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );

                        if (emailChanged) {
                          // Dialog schließen
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          // Kurz warten und App beenden
                          await Future.delayed(
                            const Duration(milliseconds: 100),
                          );
                          SystemNavigator.pop();
                          return;
                        }
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mitarbeiter gespeichert.'),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // State-Feld (oben in der Klasse):
  Future<void> _enforceDriverFromAuthUid() async {
    // Nur im Supabase-Modus erzwingen
    final sc = AppBus.getSheets?.call();
    final isSupabase =
        sc?.runtimeType.toString().toLowerCase().contains('supa') ?? false;
    if (!isSupabase) return;

    try {
      final displayName = await SupaAdapter.mitarbeiter
          .fetchOwnDisplayNameByAuthId();

      if (displayName == null || displayName.isEmpty) {
        // Fehlermeldung anzeigen und Programm beenden
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Mitarbeiter nicht gefunden'),
            content: const Text(
              'Für den angemeldeten Supabase-Benutzer existiert kein Eintrag in '
              '„Mitarbeiter“ (über auth_user_id). Das Programm wird beendet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        // Beenden
        // import 'package:flutter/services.dart' oben sicherstellen:
        //   import 'package:flutter/services.dart';
        SystemNavigator.pop();
        return;
      }

      // Erfolgsfall: State + SharedPrefs aktualisieren
      if (!mounted) return;
      setState(() {
        _driverName = displayName; // <- das Feld hinter 'driverName'
      });
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('driver_name', displayName);
      } catch (_) {}
      debugPrint('[Driver] enforced from auth uid: $displayName');
    } catch (e, st) {
      debugPrint('[Driver] enforce error: $e\n$st');
    }
  }

  // =================== NEU / ERSETZEN ===================
  /// Wird vom Supabase-Stream aufgerufen, wenn sich in der
  /// Klienten-Tabelle etwas ändert.
  void _onClientTableChanged() {
    if (!mounted) return;

    debugPrint('[SupaUI] Klienten-Änderung erkannt -> _pullFromSheet()');

    // Gleiche Logik wie Timer + Refresh-Button:
    // holt Klienten + Tagesplan neu und baut die Listen neu auf.
    _pullFromSheet();
  }
  // =================== ENDE NEU ===================

  Future<void> _enforceDriverFromAuthUser() async {
    try {
      if (!_isSupabaseMode) return;

      final name = await SupaAdapter.config.fetchOwnDisplayNameByAuthId();

      if (name == null || name.isEmpty) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => const AlertDialog(
              title: Text('Anmeldung ohne Mitarbeiter-Zuordnung'),
              content: Text(
                'Für den angemeldeten Supabase-Benutzer (auth_user_id) wurde in der Tabelle '
                '„Mitarbeiter“ kein aktiver Datensatz gefunden.\n\n'
                'Bitte die Spalte auth_user_id (UUID) korrekt befüllen und RLS-Policy prüfen.',
              ),
            ),
          );
        }
        SystemNavigator.pop();
        return;
      }

      if (mounted) {
        setState(() => _driverName = name);
      }
      debugPrint('[Driver] resolved from auth_user_id -> "$name"');
    } catch (e, st) {
      debugPrint('[Driver] resolve error: $e\n$st');
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Fehler bei Fahrer-Ermittlung'),
            content: Text('$e'),
          ),
        );
      }
      SystemNavigator.pop();
    }
  }

  // ======= ADD: main.dart -> _HomePageState: Row->Person Mapper =======
  Person _personFromRow(Map<String, dynamic> r) {
    final id = (r['row_id'] is num)
        ? (r['row_id'] as num).toInt()
        : int.tryParse('${r['row_id'] ?? '0'}') ?? 0;
    final er = r['Einrichtungen row_id'];
    final einrStr = (er is num) ? '${er.toInt()}' : (er?.toString() ?? '');

    return Person(
      rowId: id > 0 ? '$id' : null,
      nr: ('${r['Nr.'] ?? ''}').trim().isEmpty
          ? null
          : ('${r['Nr.'] ?? ''}').trim(),
      name: ('${r['Name'] ?? ''}').trim(),
      vorname: ('${r['Vorname'] ?? ''}').trim(),
      adresse: ('${r['Adresse'] ?? ''}').trim(),
      ortsteil: ('${r['Ortsteil'] ?? ''}').trim(),
      telefon: ('${r['Telefon'] ?? ''}').trim(),
      angehoerige: ('${r['Angehörige'] ?? ''}').trim(),
      angeTel: ('${r['Angehörige Tel.'] ?? ''}').trim(),
      betreuer: ('${r['Betreuer'] ?? ''}').trim(),
      betreuerTel: ('${r['Betreuer Tel.'] ?? ''}').trim(),
      rs: ('${r['RS'] ?? ''}').toString(),
      besonderheiten: ('${r['Besonderheiten'] ?? ''}').trim(),
      infosWohn: ('${r['Infos zur Wohnsituation'] ?? ''}').trim(),
      tagespflege: ('${r['Tagespflege (Wochentage)'] ?? ''}').trim(),
      hilfeBei: ('${r['Hilfe bei'] ?? ''}').trim(),
      schluessel: ('${r['Schlüssel'] ?? ''}').trim(),
      klingel: ('${r['Klingelzeichen'] ?? ''}').trim(),
      sonstiges: ('${r['Sonstige Informationen'] ?? ''}').trim(),
      aktiv: (r['Aktiv'] == true) ? 'Ja' : 'Nein',
      fahrdienst: (r['Fahrdienst'] == true) ? 'Ja' : 'Nein',
      // WICHTIG: exakt so benannt wie im Person-Konstruktor!
      einrichtungenRowId: einrStr,
      extra: const {},
    );
  }
  // ======= END ADD =======

  Future<void> _saveClientFromForm({
    required String? rowId,
    required String name,
    required String vorname,
    required String adresse,
    required String ortsteil,
    required String telefon,
    required String angehoerige,
    required String angeTel,
    required String betreuer,
    required String betreuerTel,
    required String rsJN, // "Ja"/"Nein" oder bool->String
    required String aktivJN, // "
    required String fahrdienstJN, // "
    required String besonderheiten,
    required String infosWohn,
    required String tagespflege,
    required String hilfeBei,
    required String schluessel,
    required String klingel,
    required String sonstiges,
    required String einrichtungenRowId, // als String (wird konvertiert)
  }) async {
    try {
      final row = <String, dynamic>{
        if (rowId != null && rowId.trim().isNotEmpty)
          'row_id':
              int.tryParse(rowId.trim()) ?? rowId, // wenn neu -> kein row_id
        'Name': name,
        'Vorname': vorname,
        'Adresse': adresse,
        'Ortsteil': ortsteil,
        'Telefon': telefon,
        'Angehörige': angehoerige,
        'Angehörige Tel.': angeTel,
        'Betreuer': betreuer,
        'Betreuer Tel.': betreuerTel,
        'RS': rsJN, // wird im Adapter in bool gewandelt
        'Aktiv': aktivJN, // "
        'Fahrdienst': fahrdienstJN, // "
        'Besonderheiten': besonderheiten,
        'Infos zur Wohnsituation': infosWohn,
        'Tagespflege (Wochentage)': tagespflege,
        'Hilfe bei': hilfeBei,
        'Schlüssel': schluessel,
        'Klingelzeichen': klingel,
        'Sonstige Informationen': sonstiges,
        'Einrichtungen row_id': einrichtungenRowId, // wird zu int gewandelt
      };

      await SupaAdapter.klienten.upsertClient(row);

      // Nach dem Speichern neu laden, damit Liste/Info-Tab aktuell sind
      await _pullFromSheet();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Klient gespeichert')));
      }
    } catch (e) {
      debugPrint('[Klienten] Speichern fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  void _setClientCache(Map<int, String> map, List<int> ids) {
    _logClientUsageInBuild();
    if (!mounted) return;
    setState(() {
      AppBus.clientNameMap = Map<int, String>.from(map);
      AppBus.clientIdsSorted = List<int>.from(ids);
    });
    debugPrint(
      '[Klienten] Cache gesetzt: ${AppBus.clientNameMap.length} Einträge',
    );
  }

  // innerhalb _HomePageState
  Future<void>? _loginDialogFuture; // Dialog-Lock gegen Mehrfachöffnen

  // === Klienten-Helfer für Dropdowns (UI) ===

  // 1) Alle Klientennamen in Anzeige-Reihenfolge (Items für Dropdown)
  List<String> _clientNameItems() {
    final ids = AppBus.clientIdsSorted;
    final map = AppBus.clientNameMap;
    return ids
        .map((id) => (map[id] ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // 2) Name für eine gegebene ID (aktuell gewählte Anzeige)
  String _clientNameById(int? id) {
    if (id == null) return '';
    return (AppBus.clientNameMap[id] ?? '').trim();
  }

  // Route-Tab: Klientenliste nur bei Suchtext (>=2) anzeigen
  List<MapEntry<int, String>> _routeBuildClientEntries() {
    final q = _routeSearchCtrl.text.trim().toLowerCase();

    if (q.length < 2) {
      debugPrint('[Route] query too short -> empty list');
      return const <MapEntry<int, String>>[];
    }

    final entries =
        AppBus.clientNameMap.entries
            .where((e) => e.value.toLowerCase().contains(q))
            .toList()
          ..sort(
            (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
          );

    return entries;
  }

  // 3) ID zu einem gegebenen Namen (für onChanged)
  int? _clientIdByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final target = name.trim().toLowerCase();
    for (final id in AppBus.clientIdsSorted) {
      final n = (AppBus.clientNameMap[id] ?? '').trim().toLowerCase();
      if (n == target) return id;
    }
    return null;
  }

  void _dbgDumpClients([String where = '']) {
    final m = AppBus.clientNameMap;
    final ids = AppBus.clientIdsSorted;
    final first = ids
        .take(5)
        .map((id) => '$id:${(m[id] ?? '').trim()}')
        .join(' | ');
    debugPrint('[DBG clients $where] count=${m.length} first5=[$first]');
  }

  void _logClientUsageInBuild() {
    // Einmal pro Build kurz loggen, was im Cache liegt
    final m = AppBus.clientNameMap;
    final ids = AppBus.clientIdsSorted;
    debugPrint('[UI|build] clientNameMap=${m.length} ids=${ids.length}');
  }

  // ===== ADD: Bool <-> "Ja/Nein" Normalizer =====
  String _jnFrom(dynamic v, {String fallback = 'Nein'}) {
    if (v == null) return fallback;
    if (v is bool) return v ? 'Ja' : 'Nein';
    final s = v.toString().trim().toLowerCase();
    if (s == 'ja' || s == 'true' || s == '1') return 'Ja';
    if (s == 'nein' || s == 'false' || s == '0') return 'Nein';
    // Unerwarteter Wert → debug + fallback
    debugPrint('[BOOL→JN] Unexpected value: $v -> using "$fallback"');
    return fallback;
  }

  bool _boolFromJN(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'ja' || s == 'true' || s == '1') return true;
    if (s == 'nein' || s == 'false' || s == '0') return false;
    debugPrint('[JN→BOOL] Unexpected value: $v -> using $fallback');
    return fallback;
  }
  // ===== END ADD =====

  Future<void> _loadClientNameMap({bool fromTimer = false}) async {
    debugPrint('---------------------------');
    debugPrint('[DEBUG] ENTER _loadClientNameMap');

    // Aktuellen Adapter holen (SupaSheetsAdapter im Supabase-Modus)
    final sheets = AppBus.getSheets?.call();
    debugPrint('[DEBUG] Adapter-Typ: ${sheets.runtimeType}');

    if (sheets == null) {
      debugPrint('[DEBUG] getSheets == null -> breche _loadClientNameMap ab');
      return;
    }

    try {
      if (sheets is SupaSheetsAdapter) {
        debugPrint('[UI] loadClientNameMap via SupaSheetsAdapter');
      } else {
        debugPrint('[UI] loadClientNameMap via Legacy-Adapter');
      }

      // WICHTIG: egal ob SupaSheetsAdapter oder Sheets-Client – beide
      // stellen fetchClientNameMap bereit. Kein vorzeitiges return mehr!
      final nameMap = await sheets.fetchClientNameMap();
      debugPrint('[DEBUG] NameMap erhalten: ${nameMap.length} Einträge');

      if (!mounted) return;

      setState(() {
        AppBus.clientNameMap = nameMap;
      });

      final first5 = nameMap.entries
          .take(5)
          .map((e) => '${e.key}:${e.value}')
          .join(' | ');
      debugPrint('[DEBUG] NameMap first5: $first5');
      debugPrint(
        '[UI] after _loadClientNameMap: AppBus.clientNameMap=${nameMap.length}',
      );
    } catch (e, st) {
      debugPrint('[DEBUG] UNHANDLED ERROR in _loadClientNameMap: $e\n$st');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initSupabaseOrSheets() async {
    final tag = 'initSS@${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[$tag] enter: useSupabase=${AppConfig.useSupabase}');

    if (!AppConfig.useSupabase) {
      // Original Sheets-Pfad
      _sheets = SheetsClient();
      // vorher: AppBus.getSheets = () => _sheets;
      AppBus.getSheets = () =>
          _LoggingSheetsProxy(_sheets); // nur Logging-Proxy
      debugPrint('[$tag] leave: Sheets-Adapter gesetzt (via Proxy)');
      return;
    }

    // Supabase-Pfad
    await AppAuth.ensureSignedIn();
    debugPrint(
      '[$tag] after ensureSignedIn: isLoggedIn=${AppAuth.isLoggedIn} '
      'argsEmailEmpty=${AppConfig.supaEmail.isEmpty} argsPwEmpty=${AppConfig.supaPassword.isEmpty}',
    );

    final needsDialog =
        !AppAuth.isLoggedIn &&
        (AppConfig.supaEmail.isEmpty || AppConfig.supaPassword.isEmpty);

    if (needsDialog) {
      debugPrint(
        '[$tag] needsDialog=true, openFlag=${AppBus.loginDialogOpen}, '
        'openCount=${AppBus.loginDialogOpenCount}, lockFuture=${_loginDialogFuture != null}',
      );

      if (_loginDialogFuture != null) {
        debugPrint('[$tag] wait existing _loginDialogFuture. . .');
        await _loginDialogFuture;
        debugPrint('[$tag] existing _loginDialogFuture done.');
      } else {
        if (!AppBus.loginDialogOpen) {
          AppBus.loginDialogOpen = true;
          AppBus.loginDialogOpenCount++;
          AppBus.lastLoginDialogToken = tag;
          debugPrint(
            '[$tag] showDialog (rootNavigator) openCount=${AppBus.loginDialogOpenCount}',
          );

          _loginDialogFuture =
              showDialog<bool>(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const _SupabaseLoginDialog(),
              ).whenComplete(() {
                debugPrint(
                  '[$tag] dialog whenComplete: wasOpen=${AppBus.loginDialogOpen} '
                  'token=${AppBus.lastLoginDialogToken}',
                );
                AppBus.loginDialogOpen = false;
                AppBus.lastLoginDialogToken = null;
                _loginDialogFuture = null;
              });

          await _loginDialogFuture;
          debugPrint('[$tag] await new _loginDialogFuture done.');
        } else {
          debugPrint(
            '[$tag] another opener detected, waiting while openFlag=true. . .',
          );
          while (AppBus.loginDialogOpen) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          debugPrint('[$tag] openFlag false – continue');
        }
      }
    }

    if (!mounted) {
      debugPrint('[$tag] not mounted anymore, return');
      return;
    }

    // >>> HIER entscheidend: Supa-Bridge auf den vollen Adapter aus supa_adapter.dart setzen <<<
    AppBus.getSheets = () => SupaAdapter.sheets; // <— geändert

    debugPrint(
      '[$tag] leave: Supabase-Adapter gesetzt, isLoggedIn=${AppAuth.isLoggedIn}',
    );
    debugPrint(
      '[$tag] sheets runtimeType = ${AppBus.getSheets?.call().runtimeType}',
    );

    // Direkt danach eine klare Probe fahren:
    await _probeDataPathAndEinrichtung();
    _dbgDumpClients('after initSS');
    // Nach erfolgreichem Setzen des Supabase-Adapters Zentrale/Config neu laden.
    // Hintergrund: Beim Login über den Dialog lief _initIdentityAndVersion()
    // sehr früh, als AppBus.getSheets noch null war. Hier ist der Adapter jetzt
    // sicher gesetzt, also können wir die Zentrale sauber nachziehen.
    try {
      await _initIdentityAndVersion();
      if (mounted) {
        _seedAppBusIdentity();
      }
    } catch (e, st) {
      debugPrint(
        '[INIT] _initIdentityAndVersion nach Login fehlgeschlagen: $e',
      );
      debugPrint('$st');
    }
  }

  Future<void> _loadClientNameMapFromAdapter() async {
    final sc = AppBus.getSheets?.call();
    debugPrint('[UI] loadClientNameMap via ${sc.runtimeType}');
    if (sc == null) {
      debugPrint('[UI] loadClientNameMap: AppBus.getSheets == null');
      return;
    }

    await _loadClientNameMap();
    debugPrint(
      '[UI] after _loadClientNameMap: AppBus.clientNameMap=${AppBus.clientNameMap.length}',
    );

    // Safety-Net: falls leer & Supa aktiv → direkter Supa-Fallback (optional)
    if (AppBus.clientNameMap.isEmpty && AppConfig.useSupabase) {
      try {
        int? einrId;
        try {
          final sp = await SharedPreferences.getInstance();
          final s = sp.getString('einrichtung_row_id')?.trim();
          if (s != null && s.isNotEmpty) einrId = int.tryParse(s);
        } catch (e) {
          debugPrint('[UI] Fallback SP read error: $e');
        }

        final list = (einrId == null || einrId <= 0)
            ? await SupaAdapter.klienten.fetchByEinrichtung(0)
            : await SupaAdapter.klienten.fetchByEinrichtung(einrId);

        final map = <int, String>{};
        for (final r in list) {
          final id = (r['row_id'] as num?)?.toInt() ?? 0;
          if (id <= 0) continue;
          final n = '${r['Name'] ?? ''}'.trim();
          final v = '${r['Vorname'] ?? ''}'.trim();
          final full = [n, v].where((e) => e.isNotEmpty).join(' ').trim();
          if (full.isNotEmpty) map[id] = full;
        }

        final ids = map.keys.toList()
          ..sort((a, b) {
            final na = (map[a] ?? '').toLowerCase();
            final nb = (map[b] ?? '').toLowerCase();
            return na.compareTo(nb);
          });

        _setClientCache(map, ids);
        _dbgDumpClients('after setClientCache');

        debugPrint(
          '[UI] Fallback Supa gesetzt: ${AppBus.clientNameMap.length} Einträge',
        );
      } catch (e, st) {
        debugPrint('[UI] Fallback Supa ERROR: $e');
        debugPrint('$st');
      }
    }
    _dbgDumpClients('after setState');
  }

  Future<void> _probeDataPathAndEinrichtung() async {
    debugPrint('[PROBE] USE_SUPABASE=${AppConfig.useSupabase}');
    final sc = AppBus.getSheets?.call();
    debugPrint('[PROBE] Adapter runtimeType=${sc.runtimeType}');

    // Aktuelle Einrichtung (SP) loggen
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString('einrichtung_row_id');
      debugPrint('[PROBE] SP einrichtung_row_id="$s"');
    } catch (e) {
      debugPrint('[PROBE] SP read error: $e');
    }

    // Einrichtungen nur im Supa-Modus testen
    if (AppConfig.useSupabase) {
      try {
        final rows = await SupaAdapter.einrichtungen.fetchAllActive();
        debugPrint('[PROBE] Supa.Einrichtungen -> ${rows.length} rows');
      } catch (e) {
        debugPrint('[PROBE] Einrichtungen ERROR: $e');
      }
    }

    // Klienten-Namensmap über den gerade gesetzten Adapter (Bridge!)
    try {
      final map = await (sc as dynamic).fetchClientNameMap();
      debugPrint('[PROBE] Adapter.fetchClientNameMap -> ${map.length} entries');
    } catch (e) {
      debugPrint('[PROBE] fetchClientNameMap ERROR: $e');
    }
  }

  /// Gemeinsamer Helfer für automatische Aktualisierungen aus Supabase.
  /// "quelle" wird nur in den Debug-Logs verwendet.
  Future<void> _refreshFromAutoSource(String quelle) async {
    if (!mounted) return;

    debugPrint('[SupaUI] Auto-Refresh ausgelöst durch "$quelle"');

    // WICHTIG:
    // - Für Tagesplan und Dienstplan nutzen wir denselben Weg wie der Refresh-Button:
    //   AppBus.onRefresh wird vom TabsWrapper je nach aktivem Tab auf
    //   die passende refreshFromWrapper()-Funktion gesetzt.
    if (quelle == 'Tagesplan' || quelle == 'Dienstplan') {
      final onRefresh = AppBus.onRefresh;
      if (onRefresh != null) {
        debugPrint('[SupaUI] Auto-Refresh ($quelle) -> AppBus.onRefresh()');
        try {
          onRefresh();
        } catch (e, st) {
          debugPrint('[SupaUI] Fehler in AppBus.onRefresh(): $e\n$st');
        }
        return;
      } else {
        debugPrint(
          '[SupaUI] Auto-Refresh ($quelle): AppBus.onRefresh ist null, '
          'falle zurück auf _pullFromSheet().',
        );
      }
    }

    // Standardfall: komplette Daten neu laden (Klienten, Fahrzeuge, Einrichtungen …)
    await _pullFromSheet();

    debugPrint('[SupaUI] Auto-Refresh "$quelle" abgeschlossen.');
  }


  void _registerClientAutoRefresh() {
    // Nur im Supabase-Modus sinnvoll
    if (!AppConfig.useSupabase) {
      debugPrint(
        '[SupaUI] _registerClientAutoRefresh: nicht im Supabase-Modus -> kein Auto-Refresh',
      );
      return;
    }

    final cliAdapter = SupaAdapter.klienten;
    debugPrint('[SupaUI] _registerClientAutoRefresh() – Adapter=$cliAdapter');

    // Listener nur einmal anlegen
    _clientChangeListener ??= () async {
      if (!mounted) return;

      debugPrint('[SupaUI] Klienten-Änderung erkannt -> Auto-Refresh');
      await _refreshFromAutoSource('Klienten');
    };

    cliAdapter.addChangeListener(_clientChangeListener!);

    // Die anderen Quellen gleich mit registrieren
    _registerDayPlanAutoRefresh();
    _registerDienstplanAutoRefresh();
    _registerVehicleAutoRefresh();
    _registerEinrichtungenAutoRefresh();
  }



  void _registerDayPlanAutoRefresh() {
    if (!AppConfig.useSupabase) {
      debugPrint(
        '[SupaUI] _registerDayPlanAutoRefresh: nicht im Supabase-Modus -> kein Auto-Refresh',
      );
      return;
    }

    final dayAdapter = SupaAdapter.tagesplan;
    debugPrint('[SupaUI] _registerDayPlanAutoRefresh() – Adapter=$dayAdapter');

    _dayPlanChangeListener ??= () async {
      if (!mounted) return;

      debugPrint('[SupaUI] Tagesplan-Änderung erkannt -> Auto-Refresh');
      await _refreshFromAutoSource('Tagesplan');
    };

    dayAdapter.addChangeListener(_dayPlanChangeListener!);
  }


  void _registerDienstplanAutoRefresh() {
    if (!AppConfig.useSupabase) {
      debugPrint(
        '[SupaUI] _registerDienstplanAutoRefresh: nicht im Supabase-Modus -> kein Auto-Refresh',
      );
      return;
    }

    final dienstAdapter = SupaAdapter.dienstplan;
    debugPrint(
      '[SupaUI] _registerDienstplanAutoRefresh() – Adapter=$dienstAdapter',
    );

    _dienstplanChangeListener ??= () async {
      if (!mounted) return;

      debugPrint('[SupaUI] Dienstplan-Änderung erkannt -> Auto-Refresh');
      await _refreshFromAutoSource('Dienstplan');
    };

    dienstAdapter.addChangeListener(_dienstplanChangeListener!);
  }


  void _registerVehicleAutoRefresh() {
    if (!AppConfig.useSupabase) {
      debugPrint(
        '[SupaUI] _registerVehicleAutoRefresh: nicht im Supabase-Modus -> kein Auto-Refresh',
      );
      return;
    }

    final vehAdapter = SupaAdapter.fahrzeuge;
    debugPrint('[SupaUI] _registerVehicleAutoRefresh() – Adapter=$vehAdapter');

    _vehicleChangeListener ??= () async {
      if (!mounted) return;

      debugPrint('[SupaUI] Fahrzeuge-Änderung erkannt -> Auto-Refresh');
      await _refreshFromAutoSource('Fahrzeuge');
    };

    vehAdapter.addChangeListener(_vehicleChangeListener!);
  }

  void _registerEinrichtungenAutoRefresh() {
    if (!AppConfig.useSupabase) {
      debugPrint(
        '[SupaUI] _registerEinrichtungenAutoRefresh: nicht im Supabase-Modus -> kein Auto-Refresh',
      );
      return;
    }

    final einrAdapter = SupaAdapter.einrichtungen;
    debugPrint(
      '[SupaUI] _registerEinrichtungenAutoRefresh() – Adapter=$einrAdapter',
    );

    _einrChangeListener ??= () async {
      if (!mounted) return;

      debugPrint('[SupaUI] Einrichtungen-Änderung erkannt -> Auto-Refresh');
      await _refreshFromAutoSource('Einrichtungen');
    };

    einrAdapter.addChangeListener(_einrChangeListener!);
  }

  @override
  void initState() {
    super.initState();

    // 1) Einheitlicher Offline-Banner für alle Tabs
    AppBus.buildOfflineBanner = () => _offlineBanner();

    // 2) Editor-/Geräte-Infos global spiegeln (wird nach Enforce nochmal aktualisiert)
    AppBus.editorName = _driverName;
    AppBus.deviceName = _deviceName;
    AppBus.deviceId = _deviceId;
    AppBus.deviceModel = _deviceModel;

    // 3) Dein bisheriger init-Code
    try {
      _mapMode = widget.initialMapMode;
    } catch (_) {}

    WidgetsBinding.instance.addObserver(this);
    _initIdentityAndVersion().then((_) => _seedAppBusIdentity());

    _searchCtrl.addListener(_onSearchChanged);

    _routeSearchFocus.addListener(() {
      setState(() {
        _routeSearchFocused = _routeSearchFocus.hasFocus;
      });
    });

    // Connectivität + Polling initialisieren (wie gehabt)
    _initConnectivity(); // initialSync läuft jetzt im postFrame-Callback
    _startPolling();
    _speech = stt.SpeechToText();
    _initSpeech();

    // Topbar-Actions (wie gehabt)
    AppBus.onRefresh = _pullFromSheet;
    AppBus.buildOfflineBanner = buildOfflineBannerForWrapper;
    AppBus.onAdd = _addPerson;

    // Laden der zuletzt gewählten Einrichtung (row_id)
    () async {
      try {
        final sp = await SharedPreferences.getInstance();
        setState(() {
          _einrichtungRowId = sp.getString('einrichtung_row_id')?.trim() ?? '';
        });
      } catch (_) {}
    }();

    // *** WICHTIG: Datenquelle & erster UI-Load erst NACH dem ersten Frame ***
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ZUERST: ggf. Login-Dialog zeigen (nur im Supabase-Mode)
      if (AppConfig.useSupabase) {
        final needLogin = await AppAuth.shouldShowLoginDialog();
        debugPrint('[INITSTATE] shouldShowLoginDialog() returned = $needLogin');
        debugPrint(
          '[INITSTATE] AppBus.loginDialogOpen = ${AppBus.loginDialogOpen}',
        );
        if (!mounted) return;

        if (needLogin && !AppBus.loginDialogOpen) {
          debugPrint('[INITSTATE] >>> OPENING LOGIN DIALOG <<<');
          AppBus.loginDialogOpen = true;
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,

            builder: (_) {
              debugPrint('[DIALOG] LoginDialog BUILDER executed');
              return const _SupabaseLoginDialog();
            },
          );

          debugPrint('[INITSTATE] <<< LOGIN DIALOG CLOSED <<<');
          AppBus.loginDialogOpen = false;
        }
      }

      if (!mounted) return;

      // 4) Supabase oder Sheets initialisieren (setzt AppBus.getSheets)
      await _initSupabaseOrSheets(); // <<< async korrekt abwarten

      // 5) Im Supabase-Mode Fahrername anhand auth_user_id erzwingen (setzt _driverName)
      await _enforceDriverFromAuthUid(); // zeigt ggf. Dialog & beendet App

      // 6) AppBus-Editorname nach evtl. neuem _driverName aktualisieren
      AppBus.editorName = _driverName;

      // 7) Klienten-NameMap vom aktiven Adapter laden (Supa oder Sheets)
      await _loadClientNameMapFromAdapter();

      // 8) Dein bestehender Initial-Sync
      await _initialSync();
    });

    // NEU: Auto-Refresh für Klienten registrieren
    _registerClientAutoRefresh();
  }

  // ---- Gemeinsamer Offline-Banner für andere Tabs ----
  Widget buildOfflineBannerForWrapper() {
    if (_online) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      color: isDark ? Colors.amber.shade700 : Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        'Offline - Schreibgeschützt',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.black : Colors.black87,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Auto-Refresh-Listener deregistrieren
    if (_clientChangeListener != null) {
      SupaAdapter.klienten.removeChangeListener(_clientChangeListener!);
      _clientChangeListener = null;
    }
    if (_dayPlanChangeListener != null) {
      SupaAdapter.tagesplan.removeChangeListener(_dayPlanChangeListener!);
      _dayPlanChangeListener = null;
    }
    if (_dienstplanChangeListener != null) {
      SupaAdapter.dienstplan.removeChangeListener(_dienstplanChangeListener!);
      _dienstplanChangeListener = null;
    }
    if (_vehicleChangeListener != null) {
      SupaAdapter.fahrzeuge.removeChangeListener(_vehicleChangeListener!);
      _vehicleChangeListener = null;
    }
    if (_einrChangeListener != null) {
      SupaAdapter.einrichtungen.removeChangeListener(_einrChangeListener!);
      _einrChangeListener = null;
    }

    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();

    _routeSearchFocus.dispose();

    try {
      _speech.stop();
    } catch (_) {}
    if (AppBus.onRefresh == _pullFromSheet) AppBus.onRefresh = null;
    if (AppBus.onAdd == _addPerson) AppBus.onAdd = null;
    super.dispose();
    AppBus.buildOfflineBanner = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Stoppe periodisches Polling und pausiere die Connectivity-Subscription, um Störereignisse zu vermeiden.
      _pollTimer?.cancel();
      try {
        _connSub?.pause();
      } catch (_) {}
    }
    if (state == AppLifecycleState.resumed) {
      // Beim Zurückkehren in den Vordergrund **immer** den Online-Status neu evaluieren,
      // weil manche Geräte im Hintergrund fälschlich "none" melden.
      _revalidateOnlineAndResume();
    }
  }

  Future<void> _initIdentityAndVersion() async {
    final sp = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;
    _appBuild = info.buildNumber;

    // Freundlichen Gerätenamen ermitteln (deine vorhandene Methode)
    _deviceName = await _getFriendlyDeviceName();

    var did = sp.getString('editor_device_id');
    if (did == null || did.isEmpty) {
      final stable = await _getStableDeviceId();
      did = (stable.isEmpty) ? '(unbekannt)' : stable;
      await sp.setString('editor_device_id', did);
    }
    _deviceId = did;

    await sp.setString('editor_device_name', _deviceName);
    await sp.setString('editor_device_id', _deviceId);

    // Gerätemodell laden
    try {
      _deviceModel = await _getDeviceModel();
    } catch (_) {
      _deviceModel = '(unbekannt)';
    }

    // Fahrername aus Cache
    _driverName = sp.getString('driver_name') ?? '';

    // Zentrale lokal (Cache)
    _centralName = sp.getString('central_name') ?? '';
    _centralAddress = sp.getString('central_address') ?? '';
    _centralPhone1 = sp.getString('central_phone1') ?? '';
    _centralPhone2 = sp.getString('central_phone2') ?? '';
    _centralPhone3 = sp.getString('central_phone3') ?? '';

    // Zentrale aus Sheet/Config holen (über AppBus, ohne _sheets)
    try {
      final sc = AppBus.getSheets?.call();
      if (sc != null && sc.readConfig is Function) {
        final cfg = await sc.readConfig();

        String name = '';
        String address = '';
        String phone1 = '';
        String phone2 = '';
        String phone3 = '';

        if (cfg is Map) {
          name = '${cfg['name'] ?? ''}'.trim();
          address = '${cfg['address'] ?? ''}'.trim();
          phone1 = '${cfg['phone1'] ?? ''}'.trim();
          phone2 = '${cfg['phone2'] ?? ''}'.trim();
          phone3 = '${cfg['phone3'] ?? ''}'.trim();
        } else {
          // Fallback: dynamische Felder versuchen
          try {
            name = '${(cfg as dynamic).name ?? ''}'.trim();
          } catch (_) {}
          try {
            address = '${(cfg as dynamic).address ?? ''}'.trim();
          } catch (_) {}
          try {
            phone1 = '${(cfg as dynamic).phone1 ?? ''}'.trim();
          } catch (_) {}
          try {
            phone2 = '${(cfg as dynamic).phone2 ?? ''}'.trim();
          } catch (_) {}
          try {
            phone3 = '${(cfg as dynamic).phone3 ?? ''}'.trim();
          } catch (_) {}
        }

        // Nur übernehmen, wenn vom Server/Sheet Werte geliefert wurden
        if ([name, address, phone1, phone2, phone3].any((e) => e.isNotEmpty)) {
          _centralName = name.isNotEmpty ? name : _centralName;
          _centralAddress = address.isNotEmpty ? address : _centralAddress;
          _centralPhone1 = phone1.isNotEmpty ? phone1 : _centralPhone1;
          _centralPhone2 = phone2.isNotEmpty ? phone2 : _centralPhone2;
          _centralPhone3 = phone3.isNotEmpty ? phone3 : _centralPhone3;

          // Direkt in den Cache spiegeln
          await sp.setString('central_name', _centralName);
          await sp.setString('central_address', _centralAddress);
          await sp.setString('central_phone1', _centralPhone1);
          await sp.setString('central_phone2', _centralPhone2);
          await sp.setString('central_phone3', _centralPhone3);
        }
      }
    } catch (_) {
      // offline/fehler -> lokal weiter
    }

    if (mounted) setState(() {});
  }

  // ---- Retry (verlängerte Timeouts & Backoff mit Jitter)
  Future<T> _retry<T>(
    Future<T> Function() fn, {
    int tries = 5,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn().timeout(timeout);
      } catch (e) {
        attempt++;
        if (attempt >= tries) rethrow;
        final base = Duration(milliseconds: 400 * (1 << (attempt - 1)));
        final jitter = Duration(
          milliseconds: (100 + (DateTime.now().microsecond % 400)),
        );
        await Future.delayed(base + jitter);
      }
    }
  }

  Future<void> _initialSync() async {
    debugPrint('[INIT] initialSync start');

    try {
      await _pullFromSheet();
    } catch (e, st) {
      debugPrint('[INIT] initialSync error: $e\n$st');

      // DISPLAY ONLINE: bei Supabase ist das ein echter Fehler
      if (AppConfig.useSupabase) {
        _showSnackBar('Fehler beim Initial-Sync (Supabase): $e');
      } else {
        // Bei Legacy-Sheets z.B. Netzwerkprobleme: User-Hinweis, dass
        // man es manuell neu versuchen kann.
        _showSnackBar('Fehler beim Initial-Sync: $e');
      }
    }

    debugPrint('[INIT] initialSync done');
  }

  Future<void> _startPolling() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_Config.pollInterval, (_) async {
      if (!_online || _editOpen) return;

      try {
        // Wenn der aktuell sichtbare Tab eine eigene Refresh-Funktion
        // bereitstellt, diese verwenden – sonst Fallback auf _pullFromSheet().
        final refresh = AppBus.onRefresh;
        if (refresh != null) {
          refresh(); // kann intern async sein, Future wird bewusst ignoriert
        } else {
          await _pullFromSheet();
        }
      } catch (_) {
        // still versuchen beim nächsten Tick
      }
    });
  }

  /// Re-check connectivity and resume polling after the app returns to foreground.
  Future<void> _revalidateOnlineAndResume() async {
    try {
      _connSub?.resume();
    } catch (_) {}

    dynamic raw;
    try {
      raw = await Connectivity().checkConnectivity();
    } catch (_) {
      raw = ConnectivityResult.none;
    }

    final r = _normalizeConnectivityEvent(raw);
    final on = r != ConnectivityResult.none;
    final was = _online;

    if (mounted) {
      setState(() => _online = on);
    }

    try {
      AppBus.infoRev.value++;
    } catch (_) {}

    if (on) {
      // Polling wieder starten (für Nicht-Supabase-Fälle und Fallback)
      await _startPolling();

      // Nur aktualisieren, wenn wir zuvor offline waren ODER das letzte Sync zu alt ist.
      final tooOld =
          _lastSync == null ||
          DateTime.now().difference(_lastSync!) > _Config.resumeRefreshMaxAge;

      final shouldRefresh = !was || (tooOld && !_editOpen);

      if (shouldRefresh) {
        // Im Supabase-Modus KEINE Toast-Meldung mehr – Refresh läuft leise.
        final bool isSupa = AppConfig.useSupabase;
        if (!isSupa) {
          _toast('Online – Daten werden aktualisiert');
        }

        await _pullFromSheet();
      }
    } else {
      // Sicherstellen, dass Polling gestoppt bleibt, wenn wir wirklich offline sind.
      _pollTimer?.cancel();
    }
  }

  Future<void> _loadLocalCache() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _Config.localCacheFile));
      if (await file.exists()) {
        final text = await file.readAsString();
        final data = json.decode(text);
        final schema = data['schema'] ?? 0;
        if (schema == _Config.cacheSchema) {
          final list = (data['people'] as List)
              .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          setState(() {
            _alle = list;
          });
        } else {
          // Schema-Mismatch -> ignorieren
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLocalCache() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _Config.localCacheFile));
      final data = {
        'schema': _Config.cacheSchema,
        'people': _alle.map((p) => p.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent(' ').convert(data),
        flush: true,
      );
    } catch (_) {}
  }

  // =================== REPLACEMENT: main.dart -> _pullFromSheet() ===================
  Future<void> _pullFromSheet() async {
    debugPrint(
      '[SupaUI] _pullFromSheet() gestartet (Quelle: Auto-Refresh / Timer / Refresh)',
    );

    if (_suspendPolling) {
      debugPrint('[POLL] _pullFromSheet() -> ausgesetzt (Dialog offen)');
      return;
    }
    // Kleine lokale Helfer (konfliktfrei, nur in dieser Methode sichtbar)
    String _boolToJN(dynamic v) {
      final b = (v is bool) ? v : (v?.toString().toLowerCase() == 'true');
      return b == true ? 'Ja' : 'Nein';
    }

    try {
      if (!mounted) return;

      // Doppel-Loads verhindern
      if (_clientsLoading) {
        debugPrint('[SupaUI] _pullFromSheet(): already loading -> skip');
        return;
      }
      _clientsLoading = true;
      final int myGen = ++_clientsLoadGen;
      debugPrint('[SupaUI] _pullFromSheet(): start gen=$myGen');

      // ============== SUPABASE-PFAD ==============
      if (AppConfig.useSupabase) {
        final sc = AppBus.getSheets?.call();
        if (sc == null) {
          debugPrint('[SupaUI] getSheets == null – kein Adapter gesetzt');
          _clientsLoading = false;
          return;
        }

        // 1) Namens-Map laden (ID -> "Name Vorname")
        Map<int, String> nameMap = const {};
        List<int> idsSorted = const [];
        try {
          nameMap = await sc.fetchClientNameMap();
          idsSorted = nameMap.keys.toList()
            ..sort((a, b) {
              final na = (nameMap[a] ?? '').toLowerCase();
              final nb = (nameMap[b] ?? '').toLowerCase();
              return na.compareTo(nb);
            });
          debugPrint('[SupaUI] NameMap ok: ${nameMap.length} Einträge');
        } catch (e) {
          debugPrint('[SupaUI] fetchClientNameMap() failed: $e');
        }

        // 2) optionale Einrichtung aus SharedPreferences holen
        int? einrId;
        try {
          final sp = await SharedPreferences.getInstance();
          final s = sp.getString('einrichtung_row_id');
          if (s != null && s.trim().isNotEmpty) {
            einrId = int.tryParse(s.trim());
            debugPrint('[SupaUI] SP einrichtung_row_id="$s" -> parsed=$einrId');
          } else {
            debugPrint('[SupaUI] SP einrichtung_row_id ist null/leer');
          }
        } catch (e) {
          debugPrint('[SupaUI] SharedPrefs error: $e');
        }

        // 3) Vollständige Listenzeilen aus Supabase laden
        List<Map<String, dynamic>> rows = const [];
        try {
          rows = await sc.fetchClientsForList(einrRowId: einrId);
          debugPrint('[SupaUI] fetchClientsForList -> rows=${rows.length}');
        } catch (e) {
          debugPrint('[SupaUI] fetchClientsForList() failed: $e');
        }

        // 4) Personenliste + Detailcache bauen
        final personen = <Person>[];
        final detailCache = <int, Map<String, dynamic>>{};

        if (rows.isNotEmpty) {
          for (final r in rows) {
            final id = (r['row_id'] is num)
                ? (r['row_id'] as num).toInt()
                : int.tryParse('${r['row_id'] ?? '0'}') ?? 0;
            if (id <= 0) continue;

            final name = ('${r['Name'] ?? ''}').trim();
            final vorname = ('${r['Vorname'] ?? ''}').trim();
            final adresse = ('${r['Adresse'] ?? ''}').trim();
            final ortsteil = ('${r['Ortsteil'] ?? ''}').trim();
            final telefon = ('${r['Telefon'] ?? ''}').trim();
            final ange = ('${r['Angehörige'] ?? ''}').trim();
            final angeTel = ('${r['Angehörige Tel.'] ?? ''}').trim();
            final betreuer = ('${r['Betreuer'] ?? ''}').trim();
            final betreuerTel = ('${r['Betreuer Tel.'] ?? ''}').trim();
            final hilfeBei = ('${r['Hilfe bei'] ?? ''}').trim();
            final schluessel = ('${r['Schlüssel'] ?? ''}').trim();
            final klingel = ('${r['Klingelzeichen'] ?? ''}').trim();
            final sonstiges = ('${r['Sonstige Informationen'] ?? ''}').trim();
            final infosWohn = ('${r['Infos zur Wohnsituation'] ?? ''}').trim();
            final tagespflege = ('${r['Tagespflege (Wochentage)'] ?? ''}')
                .trim();

            final aktivStr = _boolToJN(r['Aktiv']);
            final fahrdienstStr = _boolToJN(r['Fahrdienst']);
            final rsStr = _boolToJN(r['RS']);

            final einrRaw = r['Einrichtungen row_id'];
            final einrichtungenRowId = (einrRaw is num)
                ? '${einrRaw.toInt()}'
                : (einrRaw?.toString() ?? '');

            // Detailcache (für Bearbeiten)
            detailCache[id] = Map<String, dynamic>.from(r);

            personen.add(
              Person(
                rowId: '$id',
                nr: ('${r['Nr.'] ?? ''}').trim().isEmpty
                    ? null
                    : ('${r['Nr.'] ?? ''}').trim(),
                name: name,
                vorname: vorname,
                adresse: adresse,
                ortsteil: ortsteil,
                telefon: telefon,
                angehoerige: ange,
                angeTel: angeTel,
                betreuer: betreuer,
                betreuerTel: betreuerTel,
                rs: rsStr,
                besonderheiten: ('${r['Besonderheiten'] ?? ''}').trim(),
                infosWohn: infosWohn,
                tagespflege: tagespflege,
                hilfeBei: hilfeBei,
                schluessel: schluessel,
                klingel: klingel,
                sonstiges: sonstiges,
                aktiv: aktivStr,
                fahrdienst: fahrdienstStr,
                einrichtungenRowId:
                    einrichtungenRowId, // <— wichtig für Info-Tab
                extra: const {},
              ),
            );
          }
          debugPrint(
            '[SupaUI] rows=${rows.length} -> personen=${personen.length}',
          );
        } else {
          // Fallback: nur Namensliste (Adresse fehlt dann → bleibt leer)
          for (final id in idsSorted) {
            final full = (nameMap[id] ?? '').trim();
            if (full.isEmpty) continue;
            final i = full.indexOf(' ');
            final n = i > 0 ? full.substring(0, i).trim() : full;
            final v = i > 0 ? full.substring(i + 1).trim() : '';
            personen.add(
              Person(
                rowId: '$id',
                name: n,
                vorname: v,
                adresse: '',
                ortsteil: '',
                telefon: '',
                aktiv: 'Ja',
                fahrdienst: 'Ja',
                einrichtungenRowId: '',
                extra: const {},
              ),
            );
          }
          debugPrint(
            '[SupaUI] NameMap-Fallback -> personen=${personen.length}',
          );
        }

        // Sortierung wie gehabt
        personen.sort(
          (a, b) => ('${a.name} ${a.vorname}').toLowerCase().compareTo(
            ('${b.name} ${b.vorname}').toLowerCase(),
          ),
        );

        if (!mounted) {
          _clientsLoading = false;
          return;
        }
        // Gen-Guard: falls ein späterer Lauf bereits fertig ist → nix überschreiben
        if (myGen != _clientsLoadGen) {
          debugPrint(
            '[SupaUI] gen mismatch (got $myGen, current $_clientsLoadGen), skip setState',
          );
          _clientsLoading = false;
          return;
        }

        // Zeitpunkt merken, wann wir erfolgreich Daten vom Server geholt haben
        final now = DateTime.now();

        setState(() {
          // Globale Caches updaten
          AppBus.clientNameMap = Map<int, String>.from(nameMap);
          AppBus.clientIdsSorted = List<int>.from(idsSorted);
          AppBus.clientDetail = detailCache;

          // Sichtbarkeits-Listen befüllen
          _personenAlle = personen;
          _personenSichtbar = List<Person>.from(personen);
          _alle = List<Person>.from(personen);

          // Danach Route-Liste wieder aus dem aktuellen Eingabetext aufbauen
          _applyFilterEnhanced();

          // 🔹 Hier: Letzter Sync setzen
          _lastSync = now;
        });

        // 🔹 Info-Panel neu aufbauen lassen (damit "Letzter Sync" aktualisiert wird)
        try {
          AppBus.infoRev.value++;
        } catch (_) {}

        debugPrint(
          '[SupaUI] setState -> nameMap=${AppBus.clientNameMap.length}, '
          'alle=${_alle.length}, sichtbar=${_personenSichtbar.length}',
        );
        _clientsLoading = false;
        return; // Supabase-Pfad fertig

      }

      // ============== LEGACY (Google Sheets) ==============
      await _refreshCentralFromSheet();
      _loadClientNameMapFromAdapter();
      _rebuildClientListsFromCache();

      // Zeitpunkt merken, wann wir erfolgreich Daten vom Server geholt haben
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _lastSync = now;
        });
      }

      // Info-Panel neu aufbauen (damit "Letzter Sync" aktualisiert wird)
      try {
        AppBus.infoRev.value++;
      } catch (_) {}

      _clientsLoading = false;
    } catch (e, st) {
      _clientsLoading = false;
      debugPrint('[SupaUI] _pullFromSheet() error: $e\n$st');
    }
  }

  // =================== END REPLACEMENT ===================

  // =================== ADD: main.dart -> _HomePageState ===================
  /// Speichert/aktualisiert einen Klienten-Datensatz in Supabase.
  /// Erwartet ein Map mit deinen Formularwerten (Strings 'Ja'/'Nein' bei Dropdowns zulässig).
  Future<bool> _saveClientRowToSupabase(Map<String, dynamic> form) async {
    // Lokale Helfer
    bool _jnToBool(dynamic v) {
      final s = (v ?? '').toString().trim().toLowerCase();
      return s == 'ja' || s == 'true' || s == '1';
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    try {
      await AppAuth.ensureSignedIn();

      // row-Map in DB-Spalten umsetzen (EXAKT wie in der Tabelle)
      final row = <String, dynamic>{
        if (form['row_id'] != null && '${form['row_id']}'.trim().isNotEmpty)
          'row_id': _toInt(form['row_id']),

        '"Einrichtungen row_id"': _toInt(
          form['einrichtungenRowId'] ?? form['Einrichtungen row_id'],
        ),

        // Booleans: Ja/Nein → bool
        'Aktiv': _jnToBool(form['Aktiv']),
        'Fahrdienst': _jnToBool(form['Fahrdienst']),
        'RS': _jnToBool(form['RS']),

        // restliche Felder
        '"Nr."': _toInt(form['Nr.'] ?? form['nr']),
        'Name': (form['Name'] ?? form['name'] ?? '').toString().trim(),
        'Vorname': (form['Vorname'] ?? form['vorname'] ?? '').toString().trim(),
        'Adresse': (form['Adresse'] ?? form['adresse'] ?? '').toString().trim(),
        'Ortsteil': (form['Ortsteil'] ?? form['ortsteil'] ?? '')
            .toString()
            .trim(),
        'Telefon': (form['Telefon'] ?? form['telefon'] ?? '').toString().trim(),
        '"Angehörige"': (form['Angehörige'] ?? form['angehoerige'] ?? '')
            .toString()
            .trim(),
        '"Angehörige Tel."': (form['Angehörige Tel.'] ?? form['angeTel'] ?? '')
            .toString()
            .trim(),
        'Betreuer': (form['Betreuer'] ?? form['betreuer'] ?? '')
            .toString()
            .trim(),
        '"Betreuer Tel."': (form['Betreuer Tel.'] ?? form['betreuerTel'] ?? '')
            .toString()
            .trim(),
        '"Hilfe bei"': (form['Hilfe bei'] ?? form['hilfeBei'] ?? '')
            .toString()
            .trim(),
        'Schlüssel': (form['Schlüssel'] ?? form['schluessel'] ?? '')
            .toString()
            .trim(),
        'Klingelzeichen': (form['Klingelzeichen'] ?? form['klingel'] ?? '')
            .toString()
            .trim(),
        '"Sonstige Informationen"':
            (form['Sonstige Informationen'] ?? form['sonstiges'] ?? '')
                .toString()
                .trim(),
        '"Infos zur Wohnsituation"':
            (form['Infos zur Wohnsituation'] ?? form['infosWohn'] ?? '')
                .toString()
                .trim(),
        '"Tagespflege (Wochentage)"':
            (form['Tagespflege (Wochentage)'] ?? form['tagespflege'] ?? '')
                .toString()
                .trim(),
      };

      // Nulls aus Strings entfernen (optional)
      row.updateAll(
        (k, v) => (v is String && v.toLowerCase() == 'null') ? '' : v,
      );

      debugPrint('[SAVE] upsert row -> $row');

      // Upsert in Supabase (liefert die gespeicherte Zeile zurück)
      final res = await Supa.client
          .from('Klienten')
          .upsert(row)
          .select()
          .single();

      final saved = Map<String, dynamic>.from(res as Map);

      // Cache aktualisieren (Adresse/Dropdowns in Anzeigeformat umsetzen)
      final id = (saved['row_id'] is num)
          ? (saved['row_id'] as num).toInt()
          : int.tryParse('${saved['row_id'] ?? '0'}') ?? 0;

      if (id > 0) {
        // Anzeigezüge (Booleans -> 'Ja'/'Nein'), falls du den Cache für Edit nutzt
        saved['Aktiv'] = _jnToBool(saved['Aktiv'])
            ? true
            : false; // im Cache kannst du bool lassen
        saved['Fahrdienst'] = _jnToBool(saved['Fahrdienst']) ? true : false;
        saved['RS'] = _jnToBool(saved['RS']) ? true : false;

        // Globaler Detail-Cache
        AppBus.clientDetail[id] = saved;

        debugPrint('[SAVE] success row_id=$id');
      } else {
        debugPrint('[SAVE] upsert returned invalid id -> $id');
      }

      // Optional: lokale Liste aktualisieren (wenn der Editor offen ist)
      // (hier belassen wir die nächste _pullFromSheet() den Job machen)
      return true;
    } catch (e, st) {
      debugPrint('[SAVE] error: $e\n$st');
      return false;
    }
  }
  // =================== END ADD ===================

  Future<void> _refreshCentralFromSheet() async {
    try {
      final sc = AppBus.getSheets?.call();
      if (sc == null || sc.readConfig is! Function) return;

      final sp = await SharedPreferences.getInstance();
      final cfg = await sc.readConfig();

      // Dynamisch mappen (Map oder Objekt)
      String name = '';
      String addr = '';
      String p1 = '';
      String p2 = '';
      String p3 = '';

      if (cfg is Map) {
        name = '${cfg['name'] ?? ''}'.trim();
        addr = '${cfg['address'] ?? ''}'.trim();
        p1 = '${cfg['phone1'] ?? ''}'.trim();
        p2 = '${cfg['phone2'] ?? ''}'.trim();
        p3 = '${cfg['phone3'] ?? ''}'.trim();
      } else {
        try {
          name = '${(cfg as dynamic).name ?? ''}'.trim();
        } catch (_) {}
        try {
          addr = '${(cfg as dynamic).address ?? ''}'.trim();
        } catch (_) {}
        try {
          p1 = '${(cfg as dynamic).phone1 ?? ''}'.trim();
        } catch (_) {}
        try {
          p2 = '${(cfg as dynamic).phone2 ?? ''}'.trim();
        } catch (_) {}
        try {
          p3 = '${(cfg as dynamic).phone3 ?? ''}'.trim();
        } catch (_) {}
      }

      if ([name, addr, p1, p2, p3].any((e) => e.isNotEmpty)) {
        final changed =
            name != _centralName ||
            addr != _centralAddress ||
            p1 != _centralPhone1 ||
            p2 != _centralPhone2 ||
            p3 != _centralPhone3;

        if (changed && mounted) {
          setState(() {
            _centralName = name;
            _centralAddress = addr;
            _centralPhone1 = p1;
            _centralPhone2 = p2;
            _centralPhone3 = p3;
            // Legacy-Feld weiter pflegen:
            _centralPhone = _centralPhone1;
          });
        }

        // Lokal spiegeln
        await sp.setString('central_name', _centralName);
        await sp.setString('central_address', _centralAddress);
        await sp.setString('central_phone1', _centralPhone1);
        await sp.setString('central_phone2', _centralPhone2);
        await sp.setString('central_phone3', _centralPhone3);

        // Falls wir im Map-Modus sind: Route neu bauen
        if (_mapMode) {
          final addresses = _sichtbar
              .map((p) => _formatMapAddress(p))
              .where((a) => a.isNotEmpty)
              .toList();
          _routeUrl = _buildGoogleMapsRoute(addresses);
        }
      }
    } catch (_) {
      // still – kein Toast im Hintergrund-Refresh
    }
  }

  /// Hilfswandler: "Ja"/"Nein"/true/false → bool
  bool _toBoolFlexible(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'ja' || s == 'true' || s == '1' || s == 'yes';
  }

  /// Baut das Row-Map so, wie Supabase es erwartet (inkl. Bool-Konvertierung)
  Map<String, dynamic> _personToRow(Person p) {
    // row_id nur mitsenden, wenn vorhanden (Update)
    final map = <String, dynamic>{
      if ((p.rowId ?? '').trim().isNotEmpty)
        'row_id': int.tryParse(p.rowId!.trim()) ?? p.rowId,

      'Name': (p.name ?? '').trim(),
      'Vorname': (p.vorname ?? '').trim(),
      'Adresse': (p.adresse ?? '').trim(),
      'Ortsteil': (p.ortsteil ?? '').trim(),
      'Telefon': (p.telefon ?? '').trim(),
      'Angehörige': (p.angehoerige ?? '').trim(),
      'Angehörige Tel.': (p.angeTel ?? '').trim(),
      'Betreuer': (p.betreuer ?? '').trim(),
      'Betreuer Tel.': (p.betreuerTel ?? '').trim(),

      // Achtung: RS/Aktiv/Fahrdienst sind in DB BOOL
      'RS': _toBoolFlexible(p.rs),
      'Aktiv': _toBoolFlexible(p.aktiv),
      'Fahrdienst': _toBoolFlexible(p.fahrdienst),

      'Besonderheiten': (p.besonderheiten ?? '').trim(),
      'Infos zur Wohnsituation': (p.infosWohn ?? '').trim(),
      'Tagespflege (Wochentage)': (p.tagespflege ?? '').trim(),
      'Hilfe bei': (p.hilfeBei ?? '').trim(),
      'Schlüssel': (p.schluessel ?? '').trim(),
      'Klingelzeichen': (p.klingel ?? '').trim(),
      'Sonstige Informationen': (p.sonstiges ?? '').trim(),
    };

    // Einrichtung (FK) korrekt setzen: Feld heißt in DB exakt "Einrichtungen row_id"
    final eraw = (p.einrichtungenRowId ?? '').trim();
    if (eraw.isNotEmpty) {
      final eid = int.tryParse(eraw);
      if (eid != null) {
        map['Einrichtungen row_id'] = eid;
      } else {
        // lieber weglassen als kaputt senden
      }
    }

    return map;
  }

  Future<String> _pushNew(Person p) async {
    final row = _personToRow(p);
    row.remove('row_id'); // Insert erzwingen
    final newId = await SupaAdapter.klienten.upsertClient(
      row,
    ); // <-- liefert int
    return '$newId';
  }

  Future<void> _pushUpdate(Person p) async {
    final row = _personToRow(p);
    if (!row.containsKey('row_id')) {
      throw Exception('Update ohne row_id');
    }
    await SupaAdapter.klienten.upsertClient(row); // Rückgabewert hier egal
  }

  Future<void> _pushDelete(Person p) async {
    final id = int.tryParse((p.rowId ?? '').trim());
    if (id == null) throw Exception('Delete ohne gültige row_id');
    await SupaAdapter.klienten.deleteClient(
      id,
    ); // <-- existiert jetzt im Adapter
  }
  // =================== END REPLACEMENT ===================

  // Normalisiert das Event aus onConnectivityChanged (neue/alte APIs, Web/Native)
  ConnectivityResult _normalizeConnectivityEvent(dynamic event) {
    if (event is ConnectivityResult) {
      return event;
    }
    if (event is List<ConnectivityResult>) {
      return event.isNotEmpty ? event.last : ConnectivityResult.none;
    }
    return ConnectivityResult.none;
  }

  // Online/Offline
  Future<void> _initConnectivity() async {
    final conn = Connectivity();
    final first = await conn.checkConnectivity();
    setState(() => _online = first != ConnectivityResult.none);
    try {
      AppBus.infoRev.value++;
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((event) async {
      final r = _normalizeConnectivityEvent(event);
      final on = r != ConnectivityResult.none;
      final was = _online;
      if (mounted) setState(() => _online = on);
      try {
        AppBus.infoRev.value++;
      } catch (_) {}
      if (on && !was) {
        _toast('Online – Daten werden aktualisiert');
        await _pullFromSheet();
      }
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------
  // Such-Utilities: Normalisierung & Tippfehler-Toleranz
  // ---------------------------------------------------------
  static String _stripDiacritics(String t) {
    final map = <RegExp, String>{
      RegExp(r'[àáâãāăą]'): 'a',
      RegExp(r'[çćčĉċ]'): 'c',
      RegExp(r'[ďđḑ]'): 'd',
      RegExp(r'[èéêëēĕėęě]'): 'e',
      RegExp(r'[ĝğġģ]'): 'g',
      RegExp(r'[ĥħ]'): 'h',
      RegExp(r'[ìíîïĩīĭįı]'): 'i',
      RegExp(r'[ĵ]'): 'j',
      RegExp(r'[ķĸ]'): 'k',
      RegExp(r'[ĺļľŀł]'): 'l',
      RegExp(r'[ñńņňŉŋ]'): 'n',
      RegExp(r'[òóôõōŏő]'): 'o',
      RegExp(r'[ŕŗř]'): 'r',
      RegExp(r'[śŝşšș]'): 's',
      RegExp(r'[ţťŧț]'): 't',
      RegExp(r'[ùúûüũūŭůűų]'): 'u',
      RegExp(r'[ŵ]'): 'w',
      RegExp(r'[ýÿŷ]'): 'y',
      RegExp(r'[źżž]'): 'z',
    };
    var out = t;
    map.forEach((re, rep) => out = out.replaceAll(re, rep));
    return out;
  }

  static String _normalize(String s) {
    var t = s.toLowerCase();
    t = t
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    t = _stripDiacritics(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static int _lev(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = min(
          min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }
    return dp[m][n];
  }

  static bool _tokenMatches(String hay, String tok) {
    final tokLen = tok.length;
    final tokIsNum = RegExp(r'^\d+$').hasMatch(tok);
    final tokIsAlpha = RegExp(r'^[a-z]+$').hasMatch(tok);

    if (tokLen == 1) {
      return hay.contains(tok);
    }
    if (tokIsNum) {
      return hay.contains(tok);
    }
    if (hay.contains(tok)) return true;

    final words = hay.split(RegExp(r'[\s,;:/\-]+')).where((w) => w.isNotEmpty);
    final thresh = (tokLen <= 3) ? 1 : 2;
    for (final w in words) {
      final wIsAlpha = RegExp(r'^[a-z]+$').hasMatch(w);
      if (!wIsAlpha) continue;
      final d = _lev(w, tok);
      if (d <= thresh) return true;
    }
    return false;
  }

  _NormalizeResult _normalizeWithMap(String s) {
    const Map<String, String> accent1 = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ā': 'a',
      'ă': 'a',
      'ą': 'a',
      'ç': 'c',
      'ć': 'c',
      'č': 'c',
      'ĉ': 'c',
      'ċ': 'c',
      'ď': 'd',
      'đ': 'd',
      'ḑ': 'd',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ē': 'e',
      'ĕ': 'e',
      'ė': 'e',
      'ę': 'e',
      'ě': 'e',
      'ĝ': 'g',
      'ğ': 'g',
      'ġ': 'g',
      'ģ': 'g',
      'ĥ': 'h',
      'ħ': 'h',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ĩ': 'i',
      'ī': 'i',
      'ĭ': 'i',
      'į': 'i',
      'ı': 'i',
      'ĵ': 'j',
      'ķ': 'k',
      'ĸ': 'k',
      'ĺ': 'l',
      'ļ': 'l',
      'ľ': 'l',
      'ŀ': 'l',
      'ł': 'l',
      'ñ': 'n',
      'ń': 'n',
      'ņ': 'n',
      'ň': 'n',
      'ŉ': 'n',
      'ŋ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ō': 'o',
      'ŏ': 'o',
      'ő': 'o',
      'ŕ': 'r',
      'ŗ': 'r',
      'ř': 'r',
      'ś': 's',
      'ŝ': 's',
      'ş': 's',
      'š': 's',
      'ș': 's',
      'ţ': 't',
      'ť': 't',
      'ŧ': 't',
      'ț': 't',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ũ': 'u',
      'ū': 'u',
      'ŭ': 'u',
      'ů': 'u',
      'ű': 'u',
      'ų': 'u',
      'ŵ': 'w',
      'ý': 'y',
      'ÿ': 'y',
      'ŷ': 'y',
      'ź': 'z',
      'ż': 'z',
      'ž': 'z',
    };

    final src = s.toLowerCase();
    final buf = StringBuffer();
    final map = <int>[];

    for (int i = 0; i < src.length; i++) {
      final ch = src[i];
      final isWs = ch.trim().isEmpty;
      if (isWs) {
        if (buf.isEmpty) continue;
        if (buf.isNotEmpty && buf.toString().codeUnitAt(buf.length - 1) == 0x20)
          continue;
        buf.write(' ');
        map.add(i);
        continue;
      }
      if (ch == 'ä') {
        buf.write('ae');
        map
          ..add(i)
          ..add(i);
        continue;
      }
      if (ch == 'ö') {
        buf.write('oe');
        map
          ..add(i)
          ..add(i);
        continue;
      }
      if (ch == 'ü') {
        buf.write('ue');
        map
          ..add(i)
          ..add(i);
        continue;
      }
      if (ch == 'ß') {
        buf.write('ss');
        map
          ..add(i)
          ..add(i);
        continue;
      }
      final rep = accent1[ch];
      if (rep != null && rep.length == 1) {
        buf.write(rep);
        map.add(i);
        continue;
      }
      buf.write(ch);
      map.add(i);
    }

    var out = buf.toString();
    int dropFront = 0, dropBack = 0;
    if (out.isNotEmpty && out.codeUnitAt(0) == 0x20) {
      out = out.substring(1);
      dropFront = 1;
    }
    if (out.isNotEmpty && out.codeUnitAt(out.length - 1) == 0x20) {
      out = out.substring(0, out.length - 1);
      dropBack = 1;
    }
    final trimmedMap = map.sublist(dropFront, map.length - dropBack);
    return _NormalizeResult(out, trimmedMap);
  }

  List<_Span> _mergeSpans(List<_Span> spans) {
    if (spans.isEmpty) return spans;
    spans.sort((a, b) => a.start.compareTo(b.start));
    final out = <_Span>[];
    var cur = spans.first;
    for (int i = 1; i < spans.length; i++) {
      final s = spans[i];
      if (s.start <= cur.end) {
        cur = _Span(cur.start, s.end > cur.end ? s.end : cur.end);
      } else {
        out.add(cur);
        cur = s;
      }
    }
    out.add(cur);
    return out;
  }

  List<_Span> _exactSpansInOriginal(String original, List<String> tokens) {
    final n = _normalizeWithMap(original);
    final spans = <_Span>[];
    for (final tok in tokens) {
      if (tok.isEmpty) continue;
      int pos = 0;
      while (true) {
        pos = n.norm.indexOf(tok, pos);
        if (pos == -1) break;
        final startOrig = n.map2orig[pos];
        final endOrig = n.map2orig[pos + tok.length - 1] + 1;
        spans.add(_Span(startOrig, endOrig));
        pos += tok.length;
      }
    }
    return _mergeSpans(spans);
  }

  List<_Span> _wordRanges(String s) {
    final re = RegExp(r'[^ \t\r\n,;:\/\-]+');
    return re.allMatches(s).map((m) => _Span(m.start, m.end)).toList();
  }

  Set<int> _fuzzyWordIndexes(
    String original,
    List<String> tokens,
    List<_Span> exactSpans,
  ) {
    final words = _wordRanges(original);
    final exactPerWord = List<bool>.filled(words.length, false);
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      for (final ex in exactSpans) {
        if (ex.start < w.end && w.start < ex.end) {
          exactPerWord[i] = true;
          break;
        }
      }
    }
    final out = <int>{};
    for (int i = 0; i < words.length; i++) {
      if (exactPerWord[i]) continue;
      final w = words[i];
      final wText = original.substring(w.start, w.end);
      final wNorm = _normalize(wText);
      final wIsAlpha = RegExp(r'^[a-z]+$').hasMatch(wNorm);
      for (final rawTok in tokens) {
        if (rawTok.isEmpty) continue;
        final tok = rawTok;
        final tokLen = tok.length;
        final tokIsAlpha = RegExp(r'^[a-z]+$').hasMatch(tok);
        final tokIsNum = RegExp(r'^\d+$').hasMatch(tok);
        if (tokLen == 1) continue;
        if (tokIsNum) continue;
        if (!(tokIsAlpha && wIsAlpha)) continue;
        final th = (tokLen <= 3) ? 1 : 2;
        final d = _lev(wNorm, tok);
        if (d <= th) {
          out.add(i);
          break;
        }
      }
    }
    return out;
  }

  List<TextSpan> _buildSpans({
    required String original,
    required List<_Span> exact,
    required Set<int> fuzzyWordIdx,
    required TextStyle base,
    required TextStyle exactStyle,
    required TextStyle fuzzyStyle,
  }) {
    final words = _wordRanges(original);
    final fuzzySpans = <_Span>[for (final idx in fuzzyWordIdx) words[idx]];
    final allCuts = <int>{0, original.length};
    for (final s in exact) {
      allCuts
        ..add(s.start)
        ..add(s.end);
    }
    for (final s in fuzzySpans) {
      allCuts
        ..add(s.start)
        ..add(s.end);
    }
    final cuts = allCuts.toList()..sort();

    final out = <TextSpan>[];
    for (int i = 0; i < cuts.length - 1; i++) {
      final a = cuts[i], b = cuts[i + 1];
      if (b <= a) continue;
      final segText = original.substring(a, b);
      TextStyle style = base;
      final isExact = exact.any((s) => s.start <= a && b <= s.end);
      final isFuzzy =
          !isExact && fuzzySpans.any((s) => s.start <= a && b <= s.end);
      if (isExact) {
        style = base.merge(exactStyle);
      } else if (isFuzzy) {
        style = base.merge(fuzzyStyle);
      }
      out.add(TextSpan(text: segText, style: style));
    }
    return out;
  }

  // Tokens für Highlight
  List<String> _currentHighlightTokens() {
    final raw = _searchCtrl.text.trim();
    final isMap = RegExp(r'^\s*map\s+', caseSensitive: false).hasMatch(raw);
    final searchPart = isMap
        ? (RegExp(
                r'^\s*map\s+(.*)$',
                caseSensitive: false,
              ).firstMatch(raw)?.group(1) ??
              '')
        : raw;

    var norm = _normalize(searchPart).replaceAll(RegExp(r'[,\;|/\\]+'), ' ');
    // Exakte Tokens (ohne #/zentrale und ohne NOT)
    final tokens = norm
        .split(RegExp(r'\s+'))
        .where(
          (t) =>
              t.isNotEmpty && t != '#' && t != 'zentrale' && !t.startsWith('-'),
        )
        .toList();
    return tokens;
  }

  // MAP: pro Token Person wählen (mit Mehrfach-Nennungen erlaubt!)
  Person? _pickForMapToken(String tokenNorm) {
    for (final p in _alle) {
      if (_normalize(p.name) == tokenNorm) return p;
    }
    for (final p in _alle) {
      final full = _normalize('${p.name} ${p.vorname}');
      if (full.contains(tokenNorm)) return p;
    }
    for (final p in _alle) {
      if (_normalize(p.adresse).contains(tokenNorm)) return p;
    }
    Person? best;
    var bestD = 999;
    for (final p in _alle) {
      final cand = _normalize('${p.name} ${p.vorname}');
      final d = _lev(cand, tokenNorm);
      final th = (tokenNorm.length <= 3) ? 1 : 2;
      if (d <= th && d < bestD) {
        best = p;
        bestD = d;
      }
    }
    return best;
  }

  // Vereinheitlichte Suche inkl. NOT (-token) + Zentrale (#/zentrale)
  List<Person> _filterPeople(String query) {
    final raw = query.trim();
    final isMapQuery = _mapMode;
    final searchPart = raw;

    var norm = _normalize(searchPart);
    final allTokens = norm
        .replaceAll(RegExp(r'[,\;|/\\]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final wantsCentral = allTokens.any(
      (t) => t == '#' || t == 'zentrale' || t == 'z',
    );
    final negatives = allTokens
        .where((t) => t.startsWith('-'))
        .map((t) => t.substring(1))
        .toList();
    final positives = allTokens
        .where(
          (t) => t != '#' && t != 'zentrale' && t != 'z' && !t.startsWith('-'),
        )
        .toList();

    final list = _alle.where((p) {
      if (positives.isEmpty && negatives.isEmpty) return true;

      final hay = _normalize(
        '${p.name} ${p.vorname} ${p.vorname} ${p.name} ${p.adresse} ${p.ortsteil} ${p.telefon} ${(p.nr ?? '')}',
      );

      // Positiv-Bedingungen
      for (final tok in positives) {
        final isNumeric = RegExp(r'^\d+$').hasMatch(tok);
        if (isNumeric) {
          final nr = _normalize(p.nr ?? '');
          if (nr != tok && !hay.contains(tok)) return false;
        } else if (!_tokenMatches(hay, tok)) {
          return false;
        }
      }

      // Negativ-Bedingungen
      for (final tok in negatives) {
        if (tok.isEmpty) continue;
        final isNumeric = RegExp(r'^\d+$').hasMatch(tok);
        if (isNumeric) {
          if ((_normalize(p.nr ?? '') == tok) || hay.contains(tok))
            return false;
        } else {
          if (_tokenMatches(hay, tok)) return false;
        }
      }

      return true;
    }).toList();

    if (wantsCentral && _centralAddress.trim().isNotEmpty) {
      final centralPerson = Person(
        rowId: '__central__',
        nr: null,
        name: 'Zentrale',
        vorname: _centralName.isEmpty ? '' : _centralName,
        adresse: _centralAddress,
        ortsteil: '',
        telefon: (_centralPhone1.isNotEmpty
            ? _centralPhone1
            : (_centralPhone2.isNotEmpty ? _centralPhone2 : _centralPhone3)),
      );
      final hasSame = list.any(
        (p) => _normalize(p.adresse) == _normalize(_centralAddress),
      );
      if (!hasSame) list.insert(0, centralPerson);
    }
    return list;
  }

  void _applyFilterEnhanced() {
    final raw = _searchCtrl.text.trim();
    final isMapQuery = _mapMode;

    if (isMapQuery) {
      // MAP-MODUS: Tokenliste -> konkrete Auswahl in Reihenfolge
      final searchPart = raw
          .replaceFirst(RegExp(r'^\s*map\s+', caseSensitive: false), '')
          .trim();
      final parts = searchPart
          .split(',')
          .map((s) => _normalize(s))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final picked = <Person>[];

      for (final part in parts) {
        if (part == '#' || part == 'zentrale' || part == 'z') {
          if (_centralAddress.trim().isNotEmpty) {
            final central = Person(
              rowId: '__central__',
              nr: null,
              name: 'Zentrale',
              vorname: _centralName.isEmpty ? '' : _centralName,
              adresse: _centralAddress,
              ortsteil: '',
              telefon: (_centralPhone1.isNotEmpty
                  ? _centralPhone1
                  : (_centralPhone2.isNotEmpty
                        ? _centralPhone2
                        : _centralPhone3)),
            );
            // WICHTIG: keine Entdoppelung im Map-Modus -> erlaubt gleiche Einträge mehrfach
            picked.add(central);
          }
          continue;
        }
        final p = _pickForMapToken(part);
        if (p != null) picked.add(p); // bewusst ohne Deduplizierung
      }

      // ⬇️ Vorherige Länge merken, um neues Ziel zu erkennen
      final prevLen = _sichtbar.length;

      setState(() {
        _sichtbar = picked;
        _mapMode = true;
        final addresses = picked
            .map((p) => _formatMapAddress(p))
            .where((a) => a.isNotEmpty)
            .toList();
        _routeUrl = _buildGoogleMapsRoute(addresses); // keine Dedup!
        if ((addresses.length) >= _Config.mapsMaxStopsHint) {
          _toast('Hinweis: Viele Stopps – ggf. Route in Etappen öffnen.');
        }
      });

      // ⬇️ Nach dem Build automatisch ans Ende scrollen, wenn Liste gewachsen ist
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollCtrl.hasClients && picked.length > prevLen) {
          final max = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.animateTo(
            max,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
          // Alternativ (falls du lieber grob rechnest):
          // final target = (picked.length - 1) * _rowApproxHeight;
          // _scrollCtrl.animateTo(
          //   target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
          //   duration: const Duration(milliseconds: 350),
          //   curve: Curves.easeOut,
          // );
        }
        _seedAppBusIdentity(); // ← HIER EINMALIG SEEDEN
      });

      return;
    }

    // Normaler Modus
    final list = _filterPeople(raw);
    setState(() {
      _sichtbar = list;
      _mapMode = false;
      _routeUrl = null;
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      _applyFilterEnhanced,
    );
  }

  void _scrollToRowId(String rowId) {
    final i = _sichtbar.indexWhere((p) => (p.rowId ?? '') == rowId);
    if (i >= 0 && _scrollCtrl.hasClients) {
      final offset = (i * _rowApproxHeight);
      _scrollCtrl.animateTo(
        offset.clamp(0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _noopUnusedToggle() {
    if (!mounted) return;

    setState(() {
      _mapMode = !_mapMode;

      if (_mapMode) {
        // in den Map-Modus wechseln
        _searchCtrl.text = '';
        _searchCtrl.selection = TextSelection.collapsed(
          offset: _searchCtrl.text.length,
        );
      } else {
        // zurück zur normalen Suche
        _searchCtrl.clear();
      }

      _applyFilterEnhanced();
    });
  }

  // ---- Map-Address Formatting (Ortsteil + Ort) ----
  String _formatMapAddress(Person p) {
    final parts = <String>[];
    final addr = (p.adresse).trim();
    if (addr.isNotEmpty) parts.add(addr);
    final ost = (p.ortsteil).trim();
    if (ost.isNotEmpty) parts.add(ost);
    // Standard-Ort
    parts.add('Schotten');
    return parts.join(', ');
  }

  // ----------- Google Maps Route-Builder --------

  String? _buildGoogleMapsRoute(List<String> stops) {
    if (stops.isEmpty) return null;

    if (stops.length > 100) {
      _toast('Zu viele Stopps für eine Route. Bitte in Etappen teilen.');
    }

    final dest = Uri.encodeComponent(stops.last);
    final waypoints = (stops.length > 1)
        ? stops
              .sublist(0, stops.length - 1)
              .map((s) => Uri.encodeComponent(s))
              .join('|')
        : '';

    // Web-URL exakt wie in rel18 (KEIN origin=, KEIN entry=, KEIN utm=, KEIN coh=)
    final base =
        'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';
    return waypoints.isEmpty ? base : '$base&waypoints=$waypoints';
  }

  // ==== Map-Token-Utilities (für Reorder/Swipe) ====

  bool _isMapQueryText(String raw) => false;

  /// Liefert die Roh-Tokens NACH "Map", mit Original-Schreibweise (für UI)
  List<String> _mapTokensRaw(String raw) {
    // Akzeptiere Eingaben ohne 'Map '-Präfix; entferne es nur optional.
    final tail = raw.replaceFirst(
      RegExp(r'^\s*map\s*', caseSensitive: false),
      '',
    );
    return tail
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Schreibt die Tokens wieder zurück als "Map <tok1>, <tok2>, "
  void _setMapTokensRaw(List<String> tokens) {
    // Schreibe die Reihenfolge ohne 'Map ' zurück ins Eingabefeld.
    final text = tokens.isEmpty ? '' : tokens.join(', ');
    _searchCtrl.text = text;
    _searchCtrl.selection = TextSelection.collapsed(
      offset: _searchCtrl.text.length,
    );
    // direkt neue Filter anwenden
    _applyFilterEnhanced();
  }

  /// Prüft, ob ein einzelner Map-Token zu dieser Person passt
  bool _tokenMatchesPersonForMap(String token, Person p) {
    final t = _normalize(token);
    if (t.isEmpty) return false;

    // Zentrale: # / z / zentrale sowie Name/Adresse der Zentrale
    if (p.rowId == '__central__') {
      if (t == '#' || t == 'z' || t == 'zentrale') return true;
      if (_normalize(_centralAddress).contains(t)) return true;
      if (_normalize(_centralName).contains(t)) return true;
    }

    // Exakter Nachname
    if (_normalize(p.name) == t) return true;

    // "Name Vorname" enthält Token
    final full = _normalize('${p.name} ${p.vorname}');
    if (full.contains(t)) return true;

    // Adresse enthält Token
    if (_normalize(p.adresse).contains(t)) return true;

    // Fuzzy-Fallback
    final d = _lev(full, t);
    final th = (t.length <= 3) ? 1 : 2;
    return d <= th;
  }

  /// Entfernt GENAU EINEN passenden Token für die Person aus dem „Map“-Suchtext
  void _removeOneMapTokenFor(Person p) {
    final raw = _searchCtrl.text;
    if (!_isMapQueryText(raw)) return;

    final tokens = _mapTokensRaw(raw);
    if (tokens.isEmpty) return;

    // Bevorzugte Tokens für Zentrale
    if (p.rowId == '__central__') {
      final pref = ['#', 'z', 'zentrale'];
      for (final t in pref) {
        final idx = tokens.indexWhere((x) => _normalize(x) == t);
        if (idx != -1) {
          tokens.removeAt(idx);
          _setMapTokensRaw(tokens);
          return;
        }
      }
    }

    // Ersten passenden Token entfernen
    for (int i = 0; i < tokens.length; i++) {
      if (_tokenMatchesPersonForMap(tokens[i], p)) {
        tokens.removeAt(i);
        _setMapTokensRaw(tokens);
        return;
      }
    }

    // Fallback: exaktes "Nachname Vorname"
    final fallback = '${p.name} ${p.vorname}'.trim();
    final idx2 = tokens.indexWhere(
      (x) => _normalize(x) == _normalize(fallback),
    );
    if (idx2 != -1) {
      tokens.removeAt(idx2);
      _setMapTokensRaw(tokens);
      return;
    }

    // Letzter Fallback: ganz vorne
    tokens.removeAt(0);
    _setMapTokensRaw(tokens);
  }

  /// Baut die Map-Tokenliste aus der aktuell sichtbaren Reihenfolge neu auf.
  /// Bevorzugt vorhandene Tokens (Original-Schreibweise bleibt erhalten).
  void _rebuildMapTokensFromVisible() {
    final raw = _searchCtrl.text;
    if (raw.trim().isEmpty) return;

    final original = _mapTokensRaw(raw);
    final used = List<bool>.filled(original.length, false);

    final newTokens = <String>[];
    for (final p in _sichtbar) {
      int found = -1;

      // 1) Zentrale: bevorzuge #, z, zentrale
      if (p.rowId == '__central__') {
        for (int i = 0; i < original.length; i++) {
          if (used[i]) continue;
          final t = original[i].trim();
          final n = _normalize(t);
          if (n == '#' || n == 'z' || n == 'zentrale') {
            found = i;
            break;
          }
        }
      }

      // 2) Allgemeine Zuordnung
      if (found == -1) {
        for (int i = 0; i < original.length; i++) {
          if (used[i]) continue;
          if (_tokenMatchesPersonForMap(original[i], p)) {
            found = i;
            break;
          }
        }
      }

      // 3) Fallback: exaktes "Nachname Vorname"
      if (found == -1) {
        final target = _normalize('${p.name} ${p.vorname}'.trim());
        for (int i = 0; i < original.length; i++) {
          if (used[i]) continue;
          if (_normalize(original[i]) == target) {
            found = i;
            break;
          }
        }
      }

      // 4) Letzter Fallback: nimm den ersten freien Token – oder erzeuge einen plausiblen
      if (found == -1) {
        found = used.indexOf(false);
        if (found == -1) {
          final fallback = (p.rowId == '__central__')
              ? '#'
              : ('${p.name} ${p.vorname}'.trim().isNotEmpty
                    ? '${p.name} ${p.vorname}'.trim()
                    : p.adresse.trim());
          newTokens.add(fallback);
          continue;
        }
      }

      used[found] = true;
      newTokens.add(original[found]);
    }

    _setMapTokensRaw(newTokens);
  }

  // ---------- Telefon / SMS / WhatsApp ----------
  bool _looksLikePhone(String s) => s.replaceAll(RegExp(r'\D'), '').length >= 7;

  String _normalizePhone(String number) {
    final digits = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits.substring(1);
    if (digits.startsWith('00')) return digits.substring(2);
    if (digits.startsWith('0')) {
      return '${_Config.defaultCountryCode}${digits.substring(1)}';
    }
    if (!digits.startsWith(_Config.defaultCountryCode)) {
      return '${_Config.defaultCountryCode}$digits';
    }
    return digits;
  }

  String _formatTel(String number) {
    final digits = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('0')) {
      return '+${_Config.defaultCountryCode}${digits.substring(1)}';
    }
    if (!digits.startsWith(_Config.defaultCountryCode)) {
      return '+${_Config.defaultCountryCode}$digits';
    }
    return '+$digits';
  }

  Future<void> _safeLaunch(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: mode);
      } else {
        _toast('Aktion nicht möglich: ${uri.toString()}');
      }
    } catch (e) {
      _toast('Fehler beim Starten: $e');
    }
  }

  // Deaktiviert: keine App-Öffnung, immer Web-Fallback benutzen
  Future<bool> _tryOpenGoogleMapsApp({
    String? singleDestination,
    String? searchQuery,
  }) async {
    return false;
  }

  // Route starten: erst App versuchen (offlinefähig), dann Web-URL als Fallback
  Future<void> _openRoute(List<String> addresses) async {
    if (addresses.isEmpty) {
      _toast('Keine Adressen vorhanden.');
      return;
    }

    final dest = Uri.encodeComponent(addresses.last.trim());
    final waypoints = (addresses.length > 1)
        ? addresses
              .sublist(0, addresses.length - 1)
              .map((s) => Uri.encodeComponent(s.trim()))
              .join('|')
        : '';

    final base =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=My+Location'
        '&destination=$dest'
        '&travelmode=driving';

    final url = waypoints.isEmpty ? base : '$base&waypoints=$waypoints';

    await _safeLaunch(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String number) async =>
      _safeLaunch(Uri(scheme: 'tel', path: _formatTel(number)));

  Future<void> _sms(String number, {String? body}) async {
    final uri = Uri(
      scheme: 'sms',
      path: _formatTel(number),
      queryParameters: (body != null && body.isNotEmpty)
          ? {'body': body}
          : null,
    );
    await _safeLaunch(uri);
  }

  Future<void> _whatsApp(String number, {String? text}) async {
    final n = _normalizePhone(number);
    final base = 'https://wa.me/$n';
    final url = text == null || text.isEmpty
        ? base
        : '$base?text=${Uri.encodeComponent(text)}';
    await _safeLaunch(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<String?> _chooseQuickText() async {
    const t1 = 'Wir sind gleich da';
    const t2 = 'Wir kommen in etwa 10 Minuten';
    const t3 = 'Wir verspäten uns etwas aber bitte bereit halten';
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Text auswählen',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: const Text(t1),
              onTap: () => Navigator.pop(ctx, t1),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text(t2),
              onTap: () => Navigator.pop(ctx, t2),
            ),
            ListTile(
              leading: const FaIcon(
                FontAwesomeIcons.whatsapp,
                color: Colors.green,
              ),
              title: const Text(t3),
              onTap: () => Navigator.pop(ctx, t3),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _choosePhoneAction(String number) async {
    final clean = number.trim();
    if (!_looksLikePhone(clean)) {
      _toast('Ungültige oder fehlende Telefonnummer.');
      return;
    }

    final sel = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.call),
              title: const Text('Anrufen'),
              onTap: () => Navigator.pop(ctx, 'call'),
            ),
            ListTile(
              leading: const Icon(Icons.sms),
              title: const Text('SMS senden'),
              onTap: () => Navigator.pop(ctx, 'sms'),
            ),
            ListTile(
              leading: const FaIcon(
                FontAwesomeIcons.whatsapp,
                color: Colors.green,
              ),
              title: const Text('WhatsApp'),
              onTap: () => Navigator.pop(ctx, 'wa'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || sel == null) return;

    switch (sel) {
      case 'call':
        await _call(clean);
        break;
      case 'sms':
        final text = await _chooseQuickText();
        if (text != null) await _sms(clean, body: text);
        break;
      case 'wa':
        final text = await _chooseQuickText();
        if (text != null) await _whatsApp(clean, text: text);
        break;
    }
  }

  Future<void> _chooseCentralPhoneAndAction({String action = 'call'}) async {
    final options = <String>[
      if (_centralPhone1.trim().isNotEmpty) _centralPhone1.trim(),
      if (_centralPhone2.trim().isNotEmpty) _centralPhone2.trim(),
      if (_centralPhone3.trim().isNotEmpty) _centralPhone3.trim(),
      if (_centralPhone.trim().isNotEmpty)
        _centralPhone.trim(), // Legacy-Einzelnummer
    ].toSet().toList(); // dedup

    if (options.isEmpty) {
      _toast('Keine Zentrale-Telefonnummer hinterlegt.');
      return;
    }

    String? chosen;
    if (options.length == 1) {
      chosen = options.first;
    } else {
      chosen = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Zentrale – Nummer auswählen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              for (final n in options)
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: Text(n),
                  onTap: () => Navigator.pop(ctx, n),
                ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      );
    }
    if (!mounted || chosen == null) return;

    switch (action) {
      case 'call':
        await _call(chosen);
        break;
      case 'sms':
        final text = await _chooseQuickText();
        if (text != null) await _sms(chosen, body: text);
        break;
      case 'wa':
        final text = await _chooseQuickText();
        if (text != null) await _whatsApp(chosen, text: text);
        break;
    }
  }

  Future<void> _showItemMenu(Person p) async {
    final isCentral = p.rowId == '__central__';
    final hasAddr = p.adresse.trim().isNotEmpty;
    final hasPhone = isCentral
        ? (_centralPhone.trim().isNotEmpty ||
              _centralPhone1.trim().isNotEmpty ||
              _centralPhone2.trim().isNotEmpty ||
              _centralPhone3.trim().isNotEmpty)
        : p.telefon.trim().isNotEmpty;

    final sel = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.directions),
              title: const Text('Navigieren'),
              enabled: hasAddr,
              onTap: hasAddr ? () => Navigator.pop(ctx, 'nav') : null,
            ),
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text(
                isCentral
                    ? 'Zentrale anrufen / SMS / WhatsApp'
                    : 'Anrufen / SMS / WhatsApp',
              ),
              enabled: hasPhone,
              onTap: hasPhone ? () => Navigator.pop(ctx, 'call') : null,
            ),
          ],
        ),
      ),
    );
    if (sel == null) return;

    switch (sel) {
      case 'nav':
        if (hasAddr) await _openMaps(_formatMapAddress(p));
        break;
      case 'call':
        if (isCentral) {
          final sub = await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.call),
                    title: const Text('Anrufen'),
                    onTap: () => Navigator.pop(ctx, 'call'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sms),
                    title: const Text('SMS senden'),
                    onTap: () => Navigator.pop(ctx, 'sms'),
                  ),
                  ListTile(
                    leading: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Colors.green,
                    ),
                    title: const Text('WhatsApp'),
                    onTap: () => Navigator.pop(ctx, 'wa'),
                  ),
                ],
              ),
            ),
          );
          if (sub != null) {
            await _chooseCentralPhoneAndAction(action: sub);
          }
        } else if (p.telefon.trim().isNotEmpty) {
          await _choosePhoneAction(p.telefon.trim());
        }
        break;
    }
  }

  // ---------- Spracheingabe – robust ----------
  bool _isRecoverableSpeechError(String msg) {
    final m = (msg).toLowerCase();
    return m.contains('error_no_match') ||
        m.contains('no match') ||
        m.contains('no-match') ||
        m.contains('timeout') ||
        m.contains('speech timeout') ||
        m.contains('try again') ||
        m.contains('insufficient') ||
        m.contains('network');
  }

  Future<void> _initSpeech() async {
    if (kIsWeb) {
      setState(() => _speechAvailable = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (s) async {
        if (s == 'notListening' && _listening) {
          // wenn kaum Text erkannt wurde, bis zu N mal automatisch neu starten
          if (_lastSpeechText.trim().length < 3 &&
              _speechAutoRestarts < _maxSpeechAutoRestarts) {
            _speechAutoRestarts++;
            await Future.delayed(const Duration(milliseconds: 250));
            if (mounted) _startListening(restart: true);
            return;
          }
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (e) async {
        final msg = e.errorMsg ?? '';
        final recoverable = _isRecoverableSpeechError(msg);
        if (_listening &&
            recoverable &&
            _speechAutoRestarts < _maxSpeechAutoRestarts) {
          _speechAutoRestarts++;
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) _startListening(restart: true);
          return;
        }
        if (mounted) setState(() => _listening = false);
        if (recoverable) {
          _toast(
            'Nichts verstanden – bitte nochmal kurz und deutlich sprechen.',
          );
        } else if (e.permanent) {
          _toast('Spracheingabe nicht verfügbar ($msg).');
        } else {
          _toast('Fehler bei der Spracheingabe ($msg).');
        }
      },
    );

    String? loc;
    try {
      final sys = await _speech.systemLocale();
      loc = sys?.localeId;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _speechLocaleId = loc;
      });
    }
  }

  void _onSpeechResult(stt_sr.SpeechRecognitionResult result) {
    final spoken = result.recognizedWords;

    // Einheitlich: immer nur den Delta-Teil anhängen (keine Auto-Trenner, nichts löschen)
    String delta;
    if (spoken.startsWith(_lastSpeechText)) {
      delta = spoken.substring(_lastSpeechText.length);
    } else {
      // Fallback (z. B. bei Erkennungs-Reset)
      delta = spoken;
    }
    _lastSpeechText = spoken;

    final newText = _searchCtrl.text + delta;
    _searchCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );

    _applyFilterEnhanced();
  }

  Future<void> _startListening({bool restart = false}) async {
    if (!_speechAvailable) return;

    final isMapText = _isMapQueryText(_searchCtrl.text);

    if (!restart) {
      _speechAutoRestarts = 0;
      _lastSpeechText = '';
      // Merken: wollen wir Map während der Spracheingabe beibehalten?
      _speechWantsMap = _mapMode || isMapText;
      // Einheitliches Verhalten: keine automatischen Prefixe oder Löschungen.
      _applyFilterEnhanced();
    }

    final ok = await _speech.listen(
      onResult: _onSpeechResult,
      localeId: _speechLocaleId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      cancelOnError: false,
    );
    if (ok && mounted) setState(() => _listening = true);
  }

  Future<void> _stopListening() async {
    try {
      // Add new Person from Route/Wrapper

      await _speech.stop();
    } catch (_) {}
    if (mounted) setState(() => _listening = false);
  }

  void _addPerson() async {
    final p = Person(
      rowId: null,
      nr: '',
      name: '',
      vorname: '',
      adresse: '',
      ortsteil: '',
      telefon: '',
      angehoerige: '',
      angeTel: '',
      betreuer: '',
      betreuerTel: '',
      rs: 'Nein', // Dropdown-Default
      besonderheiten: '',
      infosWohn: '',
      tagespflege: '',
      hilfeBei: '',
      schluessel: '',
      klingel: '',
      sonstiges: '',
      aktiv: 'Ja', // NEU: Default Ja
      fahrdienst: 'Ja', // NEU: Default Ja
      einrichtungenRowId: (_einrichtungRowId)
          .toString()
          .trim(), // NEU: Row-ID aus Auswahl
      updatedAt: null,
      lastEditor: null,
      lastEditorDevice: null,
      lastEditorDeviceId: null,
    );

    await _editPerson(p);
  }

  // ---------- CRUD Dialoge (unverändert mit robustem Flow) ----------
  Future<void> _editPerson(Person p, {int? index}) async {
    _editOpen = true;
    _pollTimer?.cancel();

    final res = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditDialog(
        person: p,
        onCall: _choosePhoneAction,
        canDelete: index != null,
        canEdit: _online,
      ),
    );

    // Freundlicher Gerätename aus dem System (Android via MethodChannel, iOS: iosInfo.name)
    Future<String> _getFriendlyDeviceName() async {
      Future<String> _getDeviceModel() async {
        try {
          final info = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final a = await info.androidInfo;
            final s = (a.model ?? '').trim();
            if (s.isNotEmpty) return s;
          } else if (Platform.isIOS) {
            final i = await info.iosInfo;
            final s = (i.utsname.machine ?? i.model ?? '').trim();
            if (s.isNotEmpty) return s;
          }
        } catch (_) {}
        return '(unbekannt)';
      }

      try {
        if (Platform.isAndroid) {
          final ch = MethodChannel('app.device/friendlyname');
          final s =
              (await ch.invokeMethod<String>('friendlyName'))?.trim() ?? '';
          return s.isEmpty ? '(unbekannt)' : s;
        } else if (Platform.isIOS) {
          final i = await DeviceInfoPlugin().iosInfo;
          final s = (i.name ?? '').trim();
          return s.isEmpty ? '(unbekannt)' : s;
        }
      } catch (_) {}
      return '(unbekannt)';
    }

    if (res == 'save') {
      // Letzte Bearbeiter-Geräteinfos setzen (kein Flow-Change)
      try {
        final sp = await SharedPreferences.getInstance();
        // Gerätename: zuerst aus SharedPreferences 'editor_device_name', sonst _deviceName, sonst '(unbekannt)'
        final devNamePref = sp.getString('editor_device_name')?.trim();
        final friendlyName = (devNamePref != null && devNamePref.isNotEmpty)
            ? devNamePref
            : _deviceName.trim();
        final fname = await _getFriendlyDeviceName();
        p.lastEditorDeviceName = fname.isEmpty ? '(unbekannt)' : fname;
        p.lastEditorDeviceId = await _getStableDeviceId();
      } catch (_) {
        p.lastEditorDeviceName = '(unbekannt)';
        (_deviceName.trim().isEmpty) ? '(unbekannt)' : _deviceName.trim();
      }

      try {
        if ((p.rowId ?? '').isEmpty && (p.nr ?? '').isEmpty) {
          final newId = await _pushNew(p);
          p.rowId = newId;
        } else {
          await _pushUpdate(p);
        }
        await _pullFromSheet();

        // Nach Speichern: zu neuem Datensatz scrollen
        if ((p.rowId ?? '').isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToRowId(p.rowId!);
          });
        }
      } catch (e) {
        _toast('Speichern fehlgeschlagen.');
      }
    } else if (res == 'delete') {
      // Optimistisch sofort lokal entfernen
      setState(() {
        _alle.removeWhere((x) => identical(x, p) || x.rowId == p.rowId);
        _sichtbar.removeWhere((x) => identical(x, p) || x.rowId == p.rowId);
      });
      try {
        if ((p.rowId ?? '').isNotEmpty) {
          await _pushDelete(p);
          await _pullFromSheet();
        } else {
          _toast('Löschen nicht möglich: row_id fehlt.');
        }
      } catch (e) {
        _toast('Löschen fehlgeschlagen.');
      }
    }
    _editOpen = false;
    _startPolling();
  }

  Future<void> _openMaps(String address) async {
    final a = address.trim();
    if (a.isEmpty) return;

    // rel18-Stil: origin=My+Location + destination + travelmode
    final url =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=My+Location'
        '&destination=${Uri.encodeComponent(a)}'
        '&travelmode=driving';

    await _safeLaunch(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _promptEditDriverName({VoidCallback? onSaved}) async {
    // ===== Supabase: Kein Dialog. Fahrername wird strikt über auth_user_id erzwungen. =====
    if (_isSupabaseMode) {
      debugPrint(
        '[DriverDialog] Supabase aktiv → Dialog unterdrückt, Fahrer wird aus auth_user_id erzwungen.',
      );
      try {
        await _enforceDriverFromAuthUid(); // zeigt ggf. Fehlermeldung und beendet die App
        onSaved
            ?.call(); // optional: Callback aufrufen, falls deine UI damit rechnet
      } catch (e, st) {
        debugPrint('[DriverDialog] _enforceDriverFromAuthUid ERROR: $e\n$st');
      }
      return;
    }

    // ===== Sheets-Modus: alter Dialog-Flow =====
    _suspendPolling =
        true; // Polling pausieren, um Race Conditions zu vermeiden
    List<String> opts = const [];
    try {
      // 1) Primär direkt über die Registry (umgeht Proxy/Getter-Probleme)
      debugPrint('[InfoTab] fetchEmployeeNameList (direct)');
      final r1 = await SupaAdapter.config.fetchEmployeeNameList();
      if (r1 is List && r1.isNotEmpty) {
        opts = r1.map((e) => '$e').toList();
        debugPrint(
          '[InfoTab] fetchEmployeeNameList (direct) <- ${opts.length}',
        );
      } else {
        debugPrint(
          '[InfoTab] fetchEmployeeNameList (direct) <- leer, fallback',
        );
      }

      // 2) Fallback über getSheets(), nur wenn noch leer
      if (opts.isEmpty) {
        final sc = AppBus.getSheets?.call();
        debugPrint(
          '[InfoTab] fetchEmployeeNameList (fallback) -> ${sc?.runtimeType}',
        );
        if (sc != null) {
          try {
            final r2 = await (sc as dynamic).fetchEmployeeNameList();
            if (r2 is List && r2.isNotEmpty) {
              opts = r2.map((e) => '$e').toList();
              debugPrint(
                '[InfoTab] fetchEmployeeNameList (fallback) <- ${opts.length}',
              );
            } else {
              debugPrint('[InfoTab] fetchEmployeeNameList (fallback) <- leer');
            }
          } catch (e, st) {
            debugPrint(
              '[InfoTab] fetchEmployeeNameList (fallback) ERROR: $e\n$st',
            );
          }
        }
      }

      // Sicherheit: Duplikate entfernen + sortieren
      if (opts.isNotEmpty) {
        final s = {...opts}; // Set entfernt Duplikate
        opts = s.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }

      // 3) Dialog anzeigen (nur wenn es auch Optionen gibt)
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Fahrer wählen'),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: (opts.isEmpty)
                  ? const Center(child: Text('Keine Mitarbeiter gefunden.'))
                  : ListView.builder(
                      itemCount: opts.length,
                      itemBuilder: (_, i) {
                        final name = opts[i];
                        return ListTile(
                          title: Text(name),
                          onTap: () => Navigator.of(ctx).pop(name),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Abbrechen'),
              ),
            ],
          );
        },
      );

      // 4) Auswahl übernehmen
      if (selected != null && selected.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _driverName = selected; // <- dein State-Feld für den Fahrer
        });
        debugPrint('[DriverDialog] Fahrer gesetzt: $_driverName');
        onSaved?.call();
      } else {
        debugPrint(
          '[DriverDialog] Keine Auswahl getroffen oder Dialog abgebrochen.',
        );
      }
    } catch (e, st) {
      debugPrint('[DriverDialog] UNHANDLED ERROR: $e\n$st');
    } finally {
      _suspendPolling = false; // Polling wieder aktivieren
    }
  }

  Future<void> _promptEditCentral({VoidCallback? onSaved}) async {
    final res = await showDialog<_CentralResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CentralDialog(
        initName: _centralName,
        initAddress: _centralAddress,
        initPhone1: _centralPhone1,
        initPhone2: _centralPhone2,
        initPhone3: _centralPhone3,
        onCall: _choosePhoneAction,
        onOpenMaps: _openMaps,
      ),
    );

    if (res != null && res.saved) {
      // mounted prüfen, bevor setState/Scaffold etc. verwendet wird
      if (!mounted) return;

      final sp = await SharedPreferences.getInstance();
      await sp.setString('central_name', res.name);
      await sp.setString('central_address', res.address);
      await sp.setString('central_phone1', res.phone1);
      await sp.setString('central_phone2', res.phone2);
      await sp.setString('central_phone3', res.phone3);

      if (mounted) {
        setState(() {
          _centralName = res.name;
          _centralAddress = res.address;
          _centralPhone1 = res.phone1;
          _centralPhone2 = res.phone2;
          _centralPhone3 = res.phone3;
          _centralPhone = res.phone1; // Legacy
        });
      }

      // SheetsClient über AppBus nutzen (statt _sheets)
      try {
        final sc = AppBus.getSheets?.call();
        debugPrint(
          '[InfoTab] writeConfig -> ${sc?.runtimeType} name="${_centralName}"',
        );
        if (sc != null) {
          try {
            debugPrint('[InfoTab] writeConfig (direct) -> SupaAdapter.config');
            await SupaAdapter.config.writeConfig(
              name: _centralName,
              address: _centralAddress,
              phone1: _centralPhone1,
              phone2: _centralPhone2,
              phone3: _centralPhone3,
            );
            debugPrint('[InfoTab] writeConfig <- ok');
          } catch (e, st) {
            debugPrint(
              '[InfoTab] writeConfig (fallback): getSheets() returned null',
            );
          }
        } else {
          debugPrint('[InfoTab] writeConfig: getSheets() returned null');
        }
      } catch (e, st) {
        debugPrint('[InfoTab] writeConfig (fallback) FAIL: $e\n$st');
      }

      onSaved?.call();

      // Info-Refresh
      try {
        AppBus.infoRev.value++;
      } catch (_) {}
      Future.microtask(() {
        try {
          AppBus.infoRev.value++;
        } catch (_) {}
      });

      // Route-URL ggf. neu aufbauen
      if (_mapMode) {
        final addresses = _sichtbar
            .map((p) => _formatMapAddress(p))
            .where((a) => a.isNotEmpty)
            .toList();
        _routeUrl = _buildGoogleMapsRoute(addresses);
      }

      try {
        AppBus.infoRev.value++;
      } catch (_) {}
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    debugPrint('[LOGIN DIALOG] build() START');
    _logClientUsageInBuild();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hlTokens = _currentHighlightTokens();

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: GestureDetector(
                onTap: _showAppInfo,
                child: const Text('Fahrdienst'),
              ),
              actions: [



IconButton(
  tooltip: 'Aktualisieren',
  icon: const Icon(Icons.refresh),
  onPressed: () async {
    try {
      // 1️⃣ Online-Status wie beim Lifecycle-Check normalisieren
      dynamic raw;
      try {
        raw = await Connectivity().checkConnectivity();
      } catch (_) {
        raw = ConnectivityResult.none;
      }

      final r = _normalizeConnectivityEvent(raw);
      final on = r != ConnectivityResult.none;

      if (mounted) {
        setState(() => _online = on);
      }

      // Info-Panel aktualisieren
      try {
        AppBus.infoRev.value++;
      } catch (_) {}

      // 2️⃣ Wenn wirklich offline → Hinweis und abbrechen
      if (!on) {
        _toast('Offline – Aktualisierung nicht möglich.');
        return;
      }

      // 3️⃣ Wenn online → Daten ziehen
      await _pullFromSheet();

      // 4️⃣ Erfolgsmeldung
      _toast('Daten wurden aktualisiert.');
    } catch (_) {
      // Falls irgendwas schiefgeht, vorsichtige Meldung
      _toast('Verbindung unklar – versuche zu aktualisieren …');
    }
  },
),




                IconButton(
                  tooltip: _online ? 'Neuer Datensatz' : 'Offline (gesperrt)',
                  icon: const Icon(Icons.person_add),
                  onPressed: _online ? _addPerson : null,
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,

      body: Column(
        children: [
          if (!_online)
            Container(
              width: double.infinity,
              color: isDark ? Colors.amber.shade700 : Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Offline - Schreibgeschützt',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.black : Colors.black87,
                ),
              ),
            ),

          // Suchfeld
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchCtrl,
              builder: (context, value, _) {
                return TextField(
                  controller: _searchCtrl,

                  // ↓↓↓ Fokus nur im Route-Tab, steuert die Höhe ↓↓↓
                  focusNode: _mapMode ? _routeSearchFocus : null,
                  minLines: 1,
                  maxLines: (_mapMode && _routeSearchFocused) ? 3 : 1,
                  keyboardType: (_mapMode && _routeSearchFocused)
                      ? TextInputType.multiline
                      : TextInputType.text,
                  textInputAction: _mapMode
                      ? TextInputAction.newline
                      : TextInputAction.search,
                  onTapOutside: (_) {
                    if (_mapMode && _routeSearchFocus.hasFocus) {
                      _routeSearchFocus.unfocus();
                    }
                  },
                  onEditingComplete: () {
                    if (_mapMode && _routeSearchFocus.hasFocus) {
                      _routeSearchFocus.unfocus();
                    }
                  },
                  onSubmitted: (_) {
                    if (_mapMode && _routeSearchFocus.hasFocus) {
                      _routeSearchFocus.unfocus();
                    }
                    _applyFilterEnhanced();
                  },

                  decoration: InputDecoration(
                    // Links: im Route-Tab nur das Route-Icon (keine Lupe)
                    prefixIcon: _mapMode
                        ? Icon(
                            Icons.alt_route,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : Icon(
                            Icons.search,
                            color: Theme.of(context).colorScheme.primary,
                          ),

                    // Höhe links stabilisieren
                    prefixIconConstraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),

                    // Hint: auf 1 Zeile begrenzen
                    hintText: _mapMode
                        ? 'Namensliste für Map'
                        : 'Suche in Klienten',
                    hintMaxLines: 1,

                    // Material 3 Optik
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),

                    // kompakte, stabile Einzeiler-Höhe
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    isDense: true,

                    // Rechts: Icons EXKLUSIV & höhenstabil
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchCtrl,
                      builder: (context, v, _) {
                        final hasText = v.text.trim().isNotEmpty;

                        if (!hasText) {
                          // Nur Mikrofon wenn leer
                          return IconButton(
                            tooltip: 'Spracheingabe',
                            onPressed: _startListening,
                            icon: const Icon(Icons.mic),
                          );
                        }

                        // Bei Text: Löschen (links) + Map (rechts, ganz außen)
                        return ConstrainedBox(
                          constraints: const BoxConstraints.tightFor(
                            height: 48,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1) Löschen zuerst (damit Map am weitesten rechts sitzt)
                              IconButton(
                                tooltip: 'Löschen',
                                onPressed: () {
                                  _searchCtrl.clear();
                                },
                                icon: const Icon(Icons.close),
                              ),
                              // 2) Map ganz rechts – NUR bei Text im Route-Tab
                              if (_mapMode && hasText && _routeUrl != null)
                                IconButton(
                                  tooltip: 'Route öffnen',
                                  onPressed: () => _safeLaunch(
                                    Uri.parse(_routeUrl!),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  icon: const Icon(Icons.directions),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    // Höhe rechts stabilisieren
                    suffixIconConstraints: const BoxConstraints(
                      minHeight: 48,
                      maxHeight: 48,
                      minWidth: 48,
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // ====== LISTE (mit Container-Hintergrund) ======
          Expanded(
            child: Container(
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? const Color(
                      0xFF2A2A2A,
                    ) // leicht helleres Dunkelgrau als Scaffold
                  : const Color(
                      0xFFE6E6E6,
                    ), // unverändert hellgrau im Light Mode

              child: _sichtbar.isEmpty
                  ? const Center(
                      child: Text(
                        'Keine Einträge (Eingabe im Suchfeld ändern).',
                      ),
                    )
                  : (_mapMode
                        // ---------------- MAP-MODUS: Reorder + Swipe (mit Divider & kleinerer Schrift) ----------------
                        ? PrimaryScrollController(
                            controller: _scrollCtrl,
                            child: ReorderableListView.builder(
                              padding: EdgeInsets.zero,
                              buildDefaultDragHandles:
                                  false, // Drag nur am Griff
                              itemCount: _sichtbar.length,

                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final item = _sichtbar.removeAt(oldIndex);
                                  _sichtbar.insert(newIndex, item);

                                  // Map-Token-Reihenfolge exakt an _sichtbar angleichen:
                                  _rebuildMapTokensFromVisible();

                                  // Optional: Route-URL live updaten
                                  final addresses = _sichtbar
                                      .map((x) => _formatMapAddress(x))
                                      .where((a) => a.isNotEmpty)
                                      .toList();
                                  _routeUrl = _buildGoogleMapsRoute(addresses);
                                });
                              },

                              proxyDecorator: (child, index, animation) {
                                return Material(
                                  elevation: 3,
                                  color: Colors.transparent,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              itemBuilder: (ctx, i) {
                                final p = _sichtbar[i];
                                final isCentral = p.rowId == '__central__';
                                final titleText = '${p.name}, ${p.vorname}'
                                    .trim()
                                    .replaceAll(RegExp(r', $'), '');
                                final subLine = p.ortsteil.trim().isEmpty
                                    ? p.adresse
                                    : '${p.adresse} – ${p.ortsteil}';

                                // stabiler Key pro Instanz (auch bei Duplikaten)
                                final itemKey = ValueKey(
                                  'map-${identityHashCode(p)}-${p.rowId ?? ''}',
                                );

                                // Inhalt: Divider (wie „Suchen“) + Zeile mit kleinerer Schrift
                                final row = Material(
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Column(
                                    children: [
                                      if (i > 0)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Theme.of(
                                            context,
                                          ).dividerColor.withOpacity(0.8),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            // Griff links
                                            SizedBox(
                                              width: 40,
                                              height: 56,
                                              child: Center(
                                                child: (isCentral
                                                    ? const Icon(
                                                        Icons.apartment,
                                                        size: 20,
                                                      )
                                                    : const Icon(
                                                        Icons.person_outline,
                                                        size: 20,
                                                      )),
                                              ),
                                            ),

                                            // Tappbarer Inhalt
                                            Expanded(
                                              child: InkWell(
                                                onTap: () {
                                                  if (isCentral) {
                                                    _promptEditCentral();
                                                  } else {
                                                    _editPerson(p, index: i);
                                                  }
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        titleText.isEmpty
                                                            ? (p.name.isNotEmpty
                                                                  ? p.name
                                                                  : 'Zentrale')
                                                            : titleText,
                                                        style: const TextStyle(
                                                          fontSize:
                                                              13, // kleiner
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        subLine,
                                                        style: const TextStyle(
                                                          fontSize:
                                                              11, // kleiner
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // rechte Aktions-Icons
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: isCentral
                                                      ? 'Zentrale anrufen / SMS / WhatsApp'
                                                      : (p.telefon
                                                                .trim()
                                                                .isNotEmpty
                                                            ? 'Anrufen / SMS / WhatsApp'
                                                            : 'Keine Telefonnummer'),
                                                  onPressed: isCentral
                                                      ? () async {
                                                          final sub = await showModalBottomSheet<String>(
                                                            context: context,
                                                            builder: (ctx) => SafeArea(
                                                              child: Wrap(
                                                                children: [
                                                                  ListTile(
                                                                    leading:
                                                                        const Icon(
                                                                          Icons
                                                                              .call,
                                                                        ),
                                                                    title: const Text(
                                                                      'Anrufen',
                                                                    ),
                                                                    onTap: () =>
                                                                        Navigator.pop(
                                                                          ctx,
                                                                          'call',
                                                                        ),
                                                                  ),
                                                                  ListTile(
                                                                    leading:
                                                                        const Icon(
                                                                          Icons
                                                                              .sms,
                                                                        ),
                                                                    title: const Text(
                                                                      'SMS senden',
                                                                    ),
                                                                    onTap: () =>
                                                                        Navigator.pop(
                                                                          ctx,
                                                                          'sms',
                                                                        ),
                                                                  ),
                                                                  ListTile(
                                                                    leading: const FaIcon(
                                                                      FontAwesomeIcons
                                                                          .whatsapp,
                                                                      color: Colors
                                                                          .green,
                                                                    ),
                                                                    title: const Text(
                                                                      'WhatsApp',
                                                                    ),
                                                                    onTap: () =>
                                                                        Navigator.pop(
                                                                          ctx,
                                                                          'wa',
                                                                        ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                          if (sub != null) {
                                                            await _chooseCentralPhoneAndAction(
                                                              action: sub,
                                                            );
                                                          }
                                                        }
                                                      : (p.telefon
                                                                .trim()
                                                                .isNotEmpty
                                                            ? () =>
                                                                  _choosePhoneAction(
                                                                    p.telefon
                                                                        .trim(),
                                                                  )
                                                            : null),
                                                  icon: Icon(
                                                    Icons.phone,
                                                    color:
                                                        (isCentral ||
                                                            p.telefon
                                                                .trim()
                                                                .isNotEmpty)
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                        : Colors.grey,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  tooltip:
                                                      'Route (ab aktuellem Standort)',
                                                  onPressed:
                                                      p.adresse
                                                          .trim()
                                                          .isNotEmpty
                                                      ? () => _openMaps(
                                                          _formatMapAddress(p),
                                                        )
                                                      : null,
                                                  icon: Icon(
                                                    Icons.directions,
                                                    color:
                                                        p.adresse
                                                            .trim()
                                                            .isNotEmpty
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                        : Colors.grey,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );

// Swipe: entfernen + Token löschen + Route neu
if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
  // DESKTOP: Drag & Drop mit Maus über ReorderableDragStartListener
  final dismissible = Dismissible(
    key: ValueKey('dismiss_${itemKey.value}'),
    direction: DismissDirection.horizontal,
    background: Container(
      color: Theme.of(context).colorScheme.errorContainer,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(Icons.delete_outline),
    ),
    secondaryBackground: Container(
      color: Theme.of(context).colorScheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(Icons.delete_outline),
    ),
    onDismissed: (_) {
      setState(() {
        final removed = _sichtbar.removeAt(i);
        _removeOneMapTokenFor(removed);
        _rebuildMapTokensFromVisible();
        final addresses = _sichtbar
            .map((x) => _formatMapAddress(x))
            .where((a) => a.isNotEmpty)
            .toList();
        _routeUrl = _buildGoogleMapsRoute(addresses);
      });
    },
    child: row,
  );

  return ReorderableDragStartListener(
    key: itemKey,
    index: i,
    child: dismissible,
  );
}

// MOBILE (Android/iOS): wie bisher mit Swipe + Long-Press-Drag
return Dismissible(
  key: itemKey,
  direction: DismissDirection.horizontal,
  background: Container(
    color: Theme.of(context).colorScheme.errorContainer,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: const Icon(Icons.delete_outline),
  ),
  secondaryBackground: Container(
    color: Theme.of(context).colorScheme.errorContainer,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: const Icon(Icons.delete_outline),
  ),
  onDismissed: (_) {
    setState(() {
      final removed = _sichtbar.removeAt(i);
      _removeOneMapTokenFor(removed);
      _rebuildMapTokensFromVisible();
      final addresses = _sichtbar
          .map((x) => _formatMapAddress(x))
          .where((a) => a.isNotEmpty)
          .toList();
      _routeUrl = _buildGoogleMapsRoute(addresses);
    });
  },
  child: ReorderableDelayedDragStartListener(
    index: i,
    child: row,
  ),
);

                              },
                            ),
                          )
                        // ---------------- NORMALER MODUS ----------------
                        : ListView.separated(
                            controller: _scrollCtrl, // ⬅️ neu
                            itemCount: _sichtbar.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final p = _sichtbar[i];
                              final isCentral = p.rowId == '__central__';

                              final titleText = '${p.name}, ${p.vorname}'
                                  .trim()
                                  .replaceAll(RegExp(r', $'), '');
                              final subLine = p.ortsteil.trim().isEmpty
                                  ? p.adresse
                                  : '${p.adresse} – ${p.ortsteil}';

                              final baseTitle = TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              );
                              final baseSub = TextStyle(
                                fontSize: 15,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color,
                              );
                              final exactStyle = TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.16),
                              );
                              final fuzzyStyle = TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.secondary,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.secondary.withOpacity(0.20),
                              );

                              final exactName = _exactSpansInOriginal(
                                titleText.isEmpty
                                    ? (p.name.isNotEmpty ? p.name : 'Zentrale')
                                    : titleText,
                                _currentHighlightTokens(),
                              );
                              final fuzzyName = _fuzzyWordIndexes(
                                titleText.isEmpty
                                    ? (p.name.isNotEmpty ? p.name : 'Zentrale')
                                    : titleText,
                                _currentHighlightTokens(),
                                exactName,
                              );
                              final exactSub = _exactSpansInOriginal(
                                subLine,
                                _currentHighlightTokens(),
                              );
                              final fuzzySub = _fuzzyWordIndexes(
                                subLine,
                                _currentHighlightTokens(),
                                exactSub,
                              );

                              final hasAddr = p.adresse.trim().isNotEmpty;
                              final hasPhone = isCentral
                                  ? (_centralPhone.trim().isNotEmpty ||
                                        _centralPhone1.trim().isNotEmpty ||
                                        _centralPhone2.trim().isNotEmpty ||
                                        _centralPhone3.trim().isNotEmpty)
                                  : p.telefon.trim().isNotEmpty;

                              return ListTile(
                                leading: isCentral
                                    ? const Icon(Icons.apartment, size: 22)
                                    : const Icon(
                                        Icons.person_outline,
                                        size: 22,
                                      ),
                                title: RichText(
                                  text: TextSpan(
                                    children: _buildSpans(
                                      original: titleText.isEmpty
                                          ? (p.name.isNotEmpty
                                                ? p.name
                                                : 'Zentrale')
                                          : titleText,
                                      exact: exactName,
                                      fuzzyWordIdx: fuzzyName,
                                      base: baseTitle,
                                      exactStyle: exactStyle,
                                      fuzzyStyle: fuzzyStyle,
                                    ),
                                  ),
                                ),
                                subtitle: RichText(
                                  text: TextSpan(
                                    children: _buildSpans(
                                      original: subLine,
                                      exact: exactSub,
                                      fuzzyWordIdx: fuzzySub,
                                      base: baseSub,
                                      exactStyle: exactStyle.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                      fuzzyStyle: fuzzyStyle,
                                    ),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: isCentral
                                          ? 'Zentrale anrufen / SMS / WhatsApp'
                                          : (hasPhone
                                                ? 'Anrufen / SMS / WhatsApp'
                                                : 'Keine Telefonnummer'),
                                      onPressed: isCentral
                                          ? () async {
                                              final sub =
                                                  await showModalBottomSheet<
                                                    String
                                                  >(
                                                    context: context,
                                                    builder: (ctx) => SafeArea(
                                                      child: Wrap(
                                                        children: [
                                                          ListTile(
                                                            leading: const Icon(
                                                              Icons.call,
                                                            ),
                                                            title: const Text(
                                                              'Anrufen',
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  'call',
                                                                ),
                                                          ),
                                                          ListTile(
                                                            leading: const Icon(
                                                              Icons.sms,
                                                            ),
                                                            title: const Text(
                                                              'SMS senden',
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  'sms',
                                                                ),
                                                          ),
                                                          ListTile(
                                                            leading: const FaIcon(
                                                              FontAwesomeIcons
                                                                  .whatsapp,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                            title: const Text(
                                                              'WhatsApp',
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  'wa',
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                              if (sub != null) {
                                                await _chooseCentralPhoneAndAction(
                                                  action: sub,
                                                );
                                              }
                                            }
                                          : (hasPhone
                                                ? () => _choosePhoneAction(
                                                    p.telefon.trim(),
                                                  )
                                                : null),
                                      icon: Icon(
                                        Icons.phone,
                                        color: (isCentral || hasPhone)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.grey,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'Route (ab aktuellem Standort)',
                                      onPressed: hasAddr
                                          ? () =>
                                                _openMaps(_formatMapAddress(p))
                                          : null,
                                      icon: Icon(
                                        Icons.directions,
                                        color: hasAddr
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.grey,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  if (!_online)
                                    _toast('Offline - Schreibgeschützt');
                                  if (isCentral) {
                                    if (hasAddr)
                                      _openMaps(_formatMapAddress(p));
                                    return;
                                  }
                                  final realIndex = _alle.indexOf(p);
                                  _editPerson(p, index: realIndex);
                                },
                                // onLongPress removed (was: _showItemMenu)
                              );
                            },
                          )),
            ),
          ),
        ],
      ),
    );
  }
  // ===== Delegations für TagesplanTab (AppBus.getSheets → this) =====

  Future<List<dynamic>> fetchVehicles({bool onlyActive = true}) async {
    final sc = AppBus.getSheets?.call();
    if (sc == null) return const <dynamic>[];
    try {
      // Methode tear-off: funktioniert, wenn SupaSheetsAdapter.fetchVehicles existiert
      final r = await sc.fetchVehicles(onlyActive: onlyActive);
      if (r is List) return r;
    } catch (e) {
      debugPrint('[UI] fetchVehicles error: $e');
    }
    return const <dynamic>[];
  }

  Future<List<dynamic>> fetchDayPlan(DateTime date) async {
    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      debugPrint('[AppBus.fetchDayPlan] SheetsClient==null');
      return const <dynamic>[];
    }

    try {
      // Prüfen, ob die Methode existiert
      if (sc.fetchDayPlan is Function) {
        final result = await sc.fetchDayPlan(date);

        // Debug-Ausgabe, um zu sehen, ob was zurückkommt
        if (result is List) {
          debugPrint(
            '[AppBus.fetchDayPlan] OK – ${result.length} Einträge empfangen',
          );
          return result;
        } else {
          debugPrint(
            '[AppBus.fetchDayPlan] Kein List-Resultat (${result.runtimeType})',
          );
        }
      } else {
        debugPrint(
          '[AppBus.fetchDayPlan] fetchDayPlan ist keine Funktion im SheetsClient',
        );
      }
    } catch (e, st) {
      // Falls in SheetsClient.fetchDayPlan ein Fehler (z. B. fehlende Spalte) auftritt
      debugPrint('[AppBus.fetchDayPlan] FEHLER: $e\n$st');
    }

    // Fallback, falls nichts brauchbares zurückkam
    return const <dynamic>[];
  }

  // Tagesplan für ein Datum speichern (Batch)

  // (Optional) Config lesen/schreiben via this – falls Tagesplan das mal braucht
  Future<dynamic> readConfig() async {
    try {
      if (_sheets.readConfig is Function) {
        return await _sheets.readConfig();
      }
    } catch (_) {}
    return null;
  }

  Future<void> writeConfig({
    required String name,
    required String address,
    required String phone1,
    required String phone2,
    required String phone3,
  }) async {
    try {
      if (_sheets.writeConfig is Function) {
        await _sheets.writeConfig(
          name: name,
          address: address,
          phone1: phone1,
          phone2: phone2,
          phone3: phone3,
        );
      }
    } catch (_) {}
  }

  // ---------- Info-Dialog ----------
  Future<void> _showAppInfo() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final driver = _driverName.isEmpty ? '(nicht gesetzt)' : _driverName;

          String centralText() {
            final phones = [
              if (_centralPhone1.trim().isNotEmpty) _centralPhone1.trim(),
              if (_centralPhone2.trim().isNotEmpty) _centralPhone2.trim(),
              if (_centralPhone3.trim().isNotEmpty) _centralPhone3.trim(),
            ];
            final namePart = _centralName.isEmpty ? '' : _centralName;
            final addrPart = _centralAddress.isEmpty ? '' : _centralAddress;
            final phonePart = phones.isEmpty ? '' : phones.join(' · ');
            final head = [
              namePart,
              addrPart,
            ].where((s) => s.isNotEmpty).join(' — ');
            return head + (phonePart.isNotEmpty ? ' · $phonePart' : '');
          }

          String _fmt(DateTime dt) =>
              '${dt.day.toString().padLeft(2, '0')}.'
              '${dt.month.toString().padLeft(2, '0')}.'
              '${dt.year} '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';

          return AlertDialog(
            title: const Text('App-Informationen'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Version:', '$_appVersion (Build $_appBuild)'),
                  _infoRow('Status:', _online ? 'Online' : 'Offline'),
                  _infoRow(
                    'Letzter Sync:',
                    _lastSync == null ? '–' : _fmt(_lastSync!.toLocal()),
                  ),
                  const SizedBox(height: 8),

                  // Fahrerzeile: je nach Modus mit Edit oder Credentials-Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 130,
                        child: Text(
                          'Fahrername:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          driver,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // --- Nur im SHEETS-Modus: Fahrername ändern ---
                      if (!_isSupabaseMode)
                        IconButton(
                          tooltip: 'Fahrername ändern',
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _promptEditDriverName(
                            onSaved: () => setStateDialog(() {}),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),

                      // --- Nur im SUPABASE-Modus: E-Mail / Passwort ändern ---
                      if (_isSupabaseMode)
                        IconButton(
                          tooltip: 'E-Mail / Passwort ändern',
                          icon: const Icon(Icons.lock_reset, size: 20),
                          onPressed: () {
                            Navigator.pop(context); // Info-Dialog schließen
                            _showChangeCredentialsDialog(context);
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),

                  const Divider(height: 16),
                  _infoRow('Name:', _deviceName),
                  _infoRow('Model:', _deviceModel),
                  _infoRow('Nummer:', _deviceId),

                  const SizedBox(height: 8),

                  // Sheets-spezifische Infos nur anzeigen, wenn NICHT Supabase
                  if (!_isSupabaseMode) ...[
                    const Text(
                      'Google Sheet ID:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SelectableText(_Config.spreadsheetId),
                    const SizedBox(height: 6),
                    const Text(
                      'Tabellenblatt:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(_Config.sheetName),
                    const SizedBox(height: 8),
                  ],

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 130,
                        child: Text(
                          'Zentrale:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          centralText().isEmpty
                              ? 'nicht gesetzt'
                              : centralText(),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zentrale bearbeiten',
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _promptEditCentral(
                          onSaved: () => setStateDialog(() {}),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  if (_routeUrl != null && _mapMode) ...[
                    const Divider(height: 16),
                    const Text(
                      'Aktuelle Route:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(_routeUrl!),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: () => _safeLaunch(
                        Uri.parse(_routeUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.directions),
                      label: const Text('Route öffnen (Web)'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangeCredentialsDialog(BuildContext context) {
    final user = AppAuth.currentUser;
    final emailController = TextEditingController(text: user?.email ?? '');
    final pwController = TextEditingController();
    final pw2Controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Zugangsdaten ändern'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Neues Passwort',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pw2Controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passwort wiederholen',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lasse das Passwort leer, wenn du nur die E-Mail ändern möchtest.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () async {
                final newEmail = emailController.text.trim();
                final pw = pwController.text.trim();
                final pw2 = pw2Controller.text.trim();

                if (pw.isNotEmpty && pw.length < 6) {
                  _toast('Passwort muss mindestens 6 Zeichen haben.');
                  return;
                }
                if (pw.isNotEmpty && pw != pw2) {
                  _toast('Passwörter stimmen nicht überein.');
                  return;
                }

                Navigator.of(dialogContext).pop();

                try {
                  await AppAuth.updateCredentials(
                    newEmail: newEmail != user?.email ? newEmail : null,
                    newPassword: pw.isNotEmpty ? pw : null,
                  );

                  _toast('Zugangsdaten aktualisiert.');
                } catch (e) {
                  debugPrint('Fehler updateCredentials: $e');
                  _toast('Fehler beim Aktualisieren der Zugangsdaten.');
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
// ===== Ende _HomePageState =====

// ---------------------------------------------------------------------------
// Bearbeiten-Dialog (mit Aktiv / Fahrdienst / RS - Feldern integriert)
// ---------------------------------------------------------------------------
class _EditDialog extends StatefulWidget {
  final Person person;
  final Future<void> Function(String number) onCall;
  final bool canDelete;
  final bool canEdit;
  const _EditDialog({
    required this.person,
    required this.onCall,
    required this.canDelete,
    required this.canEdit,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

Widget _ro(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextFormField(
      enabled: false, // „abgeblendet“ und nicht editierbar
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
    ),
  );
}

Widget _tf(
  String label,
  TextEditingController ctr, {
  int maxLines = 1,
  bool obscureText = false,
}) {
  // Normales Textfeld im gleichen Stil wie z. B. im Zentrale-Dialog
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextField(
      controller: ctr,
      maxLines: maxLines,
      obscureText: obscureText,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ).copyWith(labelText: label),
    ),
  );
}

Widget _dateField({
  required BuildContext context,
  required String label,
  required DateTime? value,
  required Function(DateTime?) onPicked,
}) {
  final text = value == null
      ? '–'
      : '${value.day.toString().padLeft(2, '0')}.'
            '${value.month.toString().padLeft(2, '0')}.'
            '${value.year}';

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        onPicked(d);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          filled: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ).copyWith(labelText: label),
        child: Align(alignment: Alignment.centerLeft, child: Text(text)),
      ),
    ),
  );
}

class _EditDialogState extends State<_EditDialog> {
  // Helper: Adresse mit Ortsteil + Ort (Schotten) für Maps im Dialog
  String _formatMapAddressFromText(String adresse, String ortsteil) {
    final parts = <String>[];
    final a = adresse.trim();
    if (a.isNotEmpty) parts.add(a);
    final o = ortsteil.trim();
    if (o.isNotEmpty) parts.add(o);
    parts.add('Schotten');
    return parts.join(', ');
  }

  late final TextEditingController nrCtrl;
  late final TextEditingController nameCtrl;
  late final TextEditingController vornameCtrl;
  late final TextEditingController adresseCtrl;
  late final TextEditingController ortsteilCtrl;
  late final TextEditingController telefonCtrl;
  late final TextEditingController angeCtrl;
  late final TextEditingController angeTelCtrl;
  late final TextEditingController betreuerCtrl;
  late final TextEditingController betreuerTelCtrl;
  late final TextEditingController rsCtrl;
  late final TextEditingController besonderCtrl;
  late final TextEditingController infosCtrl;
  late final TextEditingController tagespflegeCtrl;
  late final TextEditingController hilfeCtrl;
  late final TextEditingController schluesselCtrl;
  late final TextEditingController klingelCtrl;
  late final TextEditingController sonstCtrl;

  bool _dirty = false;
  late String _initialSig;

  // Signatur inkl. Dropdown-Zuständen
  String _sig() => [
    nrCtrl.text,
    nameCtrl.text,
    vornameCtrl.text,
    adresseCtrl.text,
    ortsteilCtrl.text,
    telefonCtrl.text,
    angeCtrl.text,
    angeTelCtrl.text,
    betreuerCtrl.text,
    betreuerTelCtrl.text,
    rsCtrl.text,
    besonderCtrl.text,
    infosCtrl.text,
    tagespflegeCtrl.text,
    hilfeCtrl.text,
    schluesselCtrl.text,
    klingelCtrl.text,
    sonstCtrl.text,
    // Dropdown-Zustände:
    widget.person.aktiv,
    widget.person.fahrdienst,
    widget.person.rs,
  ].map((s) => s.trim()).join('\u0001');

  bool get _hasContent => [
    nameCtrl,
    vornameCtrl,
    adresseCtrl,
    ortsteilCtrl,
    telefonCtrl,
    angeCtrl,
    angeTelCtrl,
    betreuerCtrl,
    betreuerTelCtrl,
    rsCtrl,
    besonderCtrl,
    infosCtrl,
    tagespflegeCtrl,
    hilfeCtrl,
    schluesselCtrl,
    klingelCtrl,
    sonstCtrl,
    nrCtrl,
  ].any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    nrCtrl = TextEditingController(text: p.nr ?? '');
    nameCtrl = TextEditingController(text: p.name);
    vornameCtrl = TextEditingController(text: p.vorname);
    adresseCtrl = TextEditingController(text: p.adresse);
    ortsteilCtrl = TextEditingController(text: p.ortsteil);
    telefonCtrl = TextEditingController(text: p.telefon);
    angeCtrl = TextEditingController(text: p.angehoerige);
    angeTelCtrl = TextEditingController(text: p.angeTel);
    betreuerCtrl = TextEditingController(text: p.betreuer);
    betreuerTelCtrl = TextEditingController(text: p.betreuerTel);
    rsCtrl = TextEditingController(text: p.rs);
    besonderCtrl = TextEditingController(text: p.besonderheiten);
    infosCtrl = TextEditingController(text: p.infosWohn);
    tagespflegeCtrl = TextEditingController(text: p.tagespflege);
    hilfeCtrl = TextEditingController(text: p.hilfeBei);
    schluesselCtrl = TextEditingController(text: p.schluessel);
    klingelCtrl = TextEditingController(text: p.klingel);
    sonstCtrl = TextEditingController(text: p.sonstiges);

    _initialSig = _sig();
    for (final c in [
      nrCtrl,
      nameCtrl,
      vornameCtrl,
      adresseCtrl,
      ortsteilCtrl,
      telefonCtrl,
      angeCtrl,
      angeTelCtrl,
      betreuerCtrl,
      betreuerTelCtrl,
      rsCtrl,
      besonderCtrl,
      infosCtrl,
      tagespflegeCtrl,
      hilfeCtrl,
      schluesselCtrl,
      klingelCtrl,
      sonstCtrl,
    ]) {
      c.addListener(() {
        final now = _sig();
        if (now != _initialSig && !_dirty) setState(() => _dirty = true);
        if (now == _initialSig && _dirty) setState(() => _dirty = false);
      });
    }
  }

  // Für Dropdowns: Dirty-Status aktualisieren
  void _bumpDirty() {
    final now = _sig();
    if (now != _initialSig && !_dirty) setState(() => _dirty = true);
    if (now == _initialSig && _dirty) setState(() => _dirty = false);
  }

  void _applyBack() {
    final p = widget.person;

    // --- Textfelder übernehmen ---
    p.nr = nrCtrl.text.trim().isNotEmpty ? nrCtrl.text.trim() : null;
    p.name = nameCtrl.text.trim();
    p.vorname = vornameCtrl.text.trim();
    p.adresse = adresseCtrl.text.trim();
    p.ortsteil = ortsteilCtrl.text.trim();
    p.telefon = telefonCtrl.text.trim();
    p.angehoerige = angeCtrl.text.trim();
    p.angeTel = angeTelCtrl.text.trim();
    p.betreuer = betreuerCtrl.text.trim();
    p.betreuerTel = betreuerTelCtrl.text.trim();

    // RS kommt aus dem Dropdown; falls leer -> "Nein"
    p.rs = (p.rs.trim().isNotEmpty ? p.rs.trim() : 'Nein');

    p.besonderheiten = besonderCtrl.text.trim();
    p.infosWohn = infosCtrl.text.trim();
    p.tagespflege = tagespflegeCtrl.text.trim();
    p.hilfeBei = hilfeCtrl.text.trim();
    p.schluessel = schluesselCtrl.text.trim();
    p.klingel = klingelCtrl.text.trim();
    p.sonstiges = sonstCtrl.text.trim();

    // --- Defaults für Dropdown-Felder absichern ---
    if (p.aktiv.trim().isEmpty) p.aktiv = 'Ja';
    if (p.fahrdienst.trim().isEmpty) p.fahrdienst = 'Ja';
    if (p.rs.trim().isEmpty) p.rs = 'Nein';

    // --- Einrichtungen-RowId NUR numerisch zulassen; Namen nie zurückschreiben ---
    final rawEinr = p.einrichtungenRowId.trim();
    if (rawEinr.isEmpty) {
      // Leer bleibt leer; append/update schreiben dann auch nichts
      debugPrint(
        '[EditDialog._applyBack] einrichtungenRowId leer -> bleibt leer',
      );
    } else if (!RegExp(r'^\d+$').hasMatch(rawEinr)) {
      // Falls doch ein Name o.ä. drinsteht: verwerfen (Sicherheit)
      debugPrint(
        '[EditDialog._applyBack] nicht-numerisch "$rawEinr" -> leeren',
      );
      p.einrichtungenRowId = '';
    } else {
      // sauber numerisch
      p.einrichtungenRowId = rawEinr;
      debugPrint('[EditDialog._applyBack] einrichtungenRowId = $rawEinr');
    }
  }

  Color? _fillEditable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.grey[900] : Colors.grey[50];
  }

  Color? _fillReadOnly(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.grey[800] : Colors.grey[200];
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    int minLines = 1,
    int? maxLines,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: ctrl,
        readOnly: !widget.canEdit,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: (maxLines == null || (maxLines ?? 1) > 1)
            ? TextInputAction.newline
            : TextInputAction.next,
        decoration: const InputDecoration(
          labelText: '',
          border: OutlineInputBorder(),
          isDense: true,
          filled: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ).copyWith(labelText: label),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: value,
        items: items
            .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
            .toList(),
        onChanged: enabled ? onChanged : null,
        menuMaxHeight: 320,
        style: theme.textTheme.bodyMedium,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          filled: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ).copyWith(labelText: label),
      ),
    );
  }

  Widget _phoneField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (context, value, _) {
          final active = value.text.trim().isNotEmpty;
          return TextField(
            controller: ctrl,
            readOnly: !widget.canEdit,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                tooltip: active ? 'Anrufen / SMS / WhatsApp' : 'Keine Nummer',
                onPressed: active
                    ? () => widget.onCall(value.text.trim())
                    : null,
                icon: Icon(
                  Icons.phone,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          );
        },
      ),
    );
  }

  Widget _addressField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: adresseCtrl,
        builder: (context, value, _) {
          final hasAddress = value.text.trim().isNotEmpty;
          return TextField(
            controller: adresseCtrl,
            readOnly: !widget.canEdit,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'Adresse',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                tooltip: 'Route (ab aktuellem Standort)',
                onPressed: hasAddress
                    ? () => launchUrl(
                        Uri.parse(
                          'https://www.google.com/maps/dir/?api=1'
                          '&destination=${Uri.encodeComponent(adresseCtrl.text.trim())}'
                          '&travelmode=driving',
                        ),
                        mode: LaunchMode.externalApplication,
                      )
                    : null,
                icon: const Icon(Icons.directions),
                visualDensity: VisualDensity.compact,
                color: hasAddress
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteFromDialog() async {
    final name = '${widget.person.vorname} ${widget.person.name}'.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Löschen?'),
        content: Text('Datensatz von $name wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      Navigator.pop(context, 'delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.9;

    return AlertDialog(
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actionsOverflowDirection: VerticalDirection.up,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Stamm Fahrdienst',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: (widget.canDelete && _hasContent && widget.canEdit)
                ? _confirmDeleteFromDialog
                : null,
            iconSize: 20,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: (maxWidth.clamp(360.0, 640.0) as double),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field('Nr.', nrCtrl),
              _field('Name', nameCtrl),
              _field('Vorname', vornameCtrl),
              _addressField(),
              _field('Ortsteil', ortsteilCtrl),

              const Divider(),

              _phoneField('Telefon', telefonCtrl),
              _field('Angehörige', angeCtrl),
              _phoneField('Angehörige Tel.', angeTelCtrl),
              _field('Betreuer', betreuerCtrl),
              _phoneField('Betreuer Tel.', betreuerTelCtrl),

              // --- Dropdowns im exakt gleichen Stil wie Textfelder ---
              _dropdownField(
                label: 'Aktiv',
                value: (widget.person.aktiv.isNotEmpty
                    ? widget.person.aktiv
                    : 'Ja'),
                items: const ['Ja', 'Nein'],
                enabled: widget.canEdit,
                onChanged: (v) {
                  widget.person.aktiv = v ?? 'Ja';
                  _bumpDirty();
                },
              ),
              _dropdownField(
                label: 'Fahrdienst',
                value: (widget.person.fahrdienst.isNotEmpty
                    ? widget.person.fahrdienst
                    : 'Ja'),
                items: const ['Ja', 'Nein'],
                enabled: widget.canEdit,
                onChanged: (v) {
                  widget.person.fahrdienst = v ?? 'Ja';
                  _bumpDirty();
                },
              ),
              _dropdownField(
                label: 'RS',
                value: (widget.person.rs.isNotEmpty
                    ? widget.person.rs
                    : 'Nein'),
                items: const ['Ja', 'Nein'],
                enabled: widget.canEdit,
                onChanged: (v) {
                  final val = v ?? 'Nein';
                  widget.person.rs = val;
                  rsCtrl.text = val; // hält _applyBack() kompatibel
                  _bumpDirty();
                },
              ),

              // --- Ende Dropdowns ---
              _field(
                'Besonderheiten',
                besonderCtrl,
                minLines: 2,
                maxLines: null,
              ),
              _field(
                'Infos zur Wohnsituation',
                infosCtrl,
                minLines: 2,
                maxLines: null,
              ),
              _field(
                'Tagespflege (Wochentage)',
                tagespflegeCtrl,
                minLines: 2,
                maxLines: null,
              ),
              _field('Hilfe bei', hilfeCtrl, minLines: 2, maxLines: null),
              _field('Schlüssel', schluesselCtrl),
              _field(
                'Klingelzeichen',
                klingelCtrl,
                minLines: 2,
                maxLines: null,
              ),
              _field(
                'Sonstige Informationen',
                sonstCtrl,
                minLines: 2,
                maxLines: null,
              ),

              if (!widget.canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Offline - Schreibgeschützt',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Abbrechen', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          onPressed: (_dirty && widget.canEdit)
              ? () {
                  _applyBack();
                  Navigator.pop(context, 'save');
                }
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Speichern', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
// ===== Dialoge/Hilfsklassen: TOP-LEVEL (außerhalb von _EditDialogState) =====

class _DriverDialog extends StatefulWidget {
  final String initialName;
  final List<String> options;
  const _DriverDialog({required this.initialName, required this.options});

  @override
  State<_DriverDialog> createState() => _DriverDialogState();
}

class _DriverDialogState extends State<_DriverDialog> {
  String? _selected;

  late final TextEditingController _nameCtrl;
  late String _initialSig;
  bool _dirty = false;

  String _sig() => _nameCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _initialSig = _sig();
    _nameCtrl.addListener(() {
      final now = _sig();
      if (now != _initialSig && !_dirty) setState(() => _dirty = true);
      if (now == _initialSig && _dirty) setState(() => _dirty = false);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    return AlertDialog(
      title: const Text('Fahrername'),
      content: SizedBox(
        width: (maxWidth.clamp(360.0, 640.0) as double),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: DropdownButtonFormField<String>(
              value: (widget.options.contains(widget.initialName)
                  ? widget.initialName
                  : null),
              isExpanded: true,
              items: [
                for (final o in widget.options)
                  DropdownMenuItem<String>(value: o, child: Text(o)),
              ],
              onChanged: (val) {
                setState(() {
                  _selected = val;
                  _dirty =
                      (_selected != _initialSig &&
                      (_selected ?? '').trim().isNotEmpty);
                });
              },
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Fahrer wählen',
                border: OutlineInputBorder(),
                isDense: true,
                filled: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Abbrechen', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          onPressed: (_dirty && ((_selected ?? '').trim().isNotEmpty))
              ? () async {
                  final sp = await SharedPreferences.getInstance();
                  final val = (_selected ?? '').trim();
                  await sp.setString('driver_name', val);
                  if (context.mounted) Navigator.pop(context, 'save');
                }
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Speichern', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _CentralResult {
  final bool saved;
  final String name;
  final String address;
  final String phone1;
  final String phone2;
  final String phone3;
  const _CentralResult({
    required this.saved,
    required this.name,
    required this.address,
    required this.phone1,
    required this.phone2,
    required this.phone3,
  });
}

class _CentralDialog extends StatefulWidget {
  final String initName;
  final String initAddress;
  final String initPhone1;
  final String initPhone2;
  final String initPhone3;
  final Future<void> Function(String number) onCall;
  final Future<void> Function(String address) onOpenMaps;

  const _CentralDialog({
    required this.initName,
    required this.initAddress,
    required this.initPhone1,
    required this.initPhone2,
    required this.initPhone3,
    required this.onCall,
    required this.onOpenMaps,
  });

  @override
  State<_CentralDialog> createState() => _CentralDialogState();
}

class _CentralDialogState extends State<_CentralDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addrCtrl;
  late final TextEditingController _p1Ctrl;
  late final TextEditingController _p2Ctrl;
  late final TextEditingController _p3Ctrl;
  late String _initialSig;
  bool _dirty = false;

  String _sig() => [
    _nameCtrl.text,
    _addrCtrl.text,
    _p1Ctrl.text,
    _p2Ctrl.text,
    _p3Ctrl.text,
  ].map((s) => s.trim()).join('\u0001');

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initName);
    _addrCtrl = TextEditingController(text: widget.initAddress);
    _p1Ctrl = TextEditingController(text: widget.initPhone1);
    _p2Ctrl = TextEditingController(text: widget.initPhone2);
    _p3Ctrl = TextEditingController(text: widget.initPhone3);
    _initialSig = _sig();

    for (final c in [_nameCtrl, _addrCtrl, _p1Ctrl, _p2Ctrl, _p3Ctrl]) {
      c.addListener(() {
        final now = _sig();
        if (now != _initialSig && !_dirty) setState(() => _dirty = true);
        if (now == _initialSig && _dirty) setState(() => _dirty = false);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    _p3Ctrl.dispose();
    super.dispose();
  }

  Widget _phoneField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: ctrl,
        builder: (context, value, _) {
          final active = value.text.trim().isNotEmpty;
          return TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                tooltip: active ? 'Anrufen / SMS / WhatsApp' : 'Keine Nummer',
                onPressed: active
                    ? () => widget.onCall(value.text.trim())
                    : null,
                icon: Icon(
                  Icons.phone,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          );
        },
      ),
    );
  }

  Widget _addressField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _addrCtrl,
        builder: (context, value, _) {
          final hasAddress = value.text.trim().isNotEmpty;
          return TextField(
            controller: _addrCtrl,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'Adresse',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              suffixIcon: IconButton(
                tooltip: 'Route (ab aktuellem Standort)',
                onPressed: hasAddress
                    ? () => widget.onOpenMaps(_addrCtrl.text.trim())
                    : null,
                icon: const Icon(Icons.directions),
                visualDensity: VisualDensity.compact,
                color: hasAddress
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.9;
    return AlertDialog(
      title: const Text('Zentrale'),
      content: SizedBox(
        width: (maxWidth.clamp(360.0, 640.0) as double),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name der Einrichtung',
                    border: OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              _addressField(),
              _phoneField('Telefonnummer 1', _p1Ctrl),
              _phoneField('Telefonnummer 2', _p2Ctrl),
              _phoneField('Telefonnummer 3', _p3Ctrl),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _CentralResult(
              saved: false,
              name: '',
              address: '',
              phone1: '',
              phone2: '',
              phone3: '',
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Abbrechen', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          onPressed: _dirty
              ? () {
                  Navigator.pop(
                    context,
                    _CentralResult(
                      saved: true,
                      name: _nameCtrl.text.trim(),
                      address: _addrCtrl.text.trim(),
                      phone1: _p1Ctrl.text.trim(),
                      phone2: _p2Ctrl.text.trim(),
                      phone3: _p3Ctrl.text.trim(),
                    ),
                  );
                }
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Speichern', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class TagesplanTab extends StatefulWidget {
  final Widget Function()? bannerBuilder;

  const TagesplanTab({Key? key, this.bannerBuilder}) : super(key: key);

  @override
  State<TagesplanTab> createState() => _TagesplanTabState();
}

// Top-Level (außerhalb aller Klassen):
enum _DateChangeDecision { cancel, discard, saveFirst, proceed }

class _TagesplanTabState extends State<TagesplanTab> {
  bool _suppressDirty = false; // während Reload keine Dirty-Events zulassen
  DateTime _selectedDate = DateTime.now();
  int? _activeVehicleId;
  bool _hasChanges = false;
  bool _isDark(BuildContext ctx) => Theme.of(ctx).brightness == Brightness.dark;

  bool _didInitialLoad = false;
  bool _isLoading = false;

  bool _dayModeIsMorning = true; // Start: Morgen
  bool _isSavingDayPlan = false;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  TextStyle get _titleStyle =>
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  TextStyle get _noteStyle =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
      );
  String _firstFilled(List<String?> xs, {String fallback = 'unbekannt'}) {
    for (final s in xs) {
      if (s != null && s.trim().isNotEmpty) return s.trim();
    }
    return fallback;
  }

  Color _rowFillColor(_Entry e, BuildContext ctx) {
    final theme = Theme.of(ctx);

    // Unzugeordnet → dezente Standardfläche
    if (e.vehicleRowId == null) {
      // leichtes Surface-Variant, damit Text gut lesbar bleibt
      final base = theme.colorScheme.surfaceVariant;
      return _isDark(ctx) ? base.withOpacity(0.20) : base.withOpacity(0.12);
    }

    // Zugeordnet → gleiche Logik wie Chip-Inneres
    final base = _colorForVehId(
      e.vehicleRowId!,
    ); // nutzt Hex aus Tabelle oder Palette
    final dark = _isDark(ctx);
    // exakt wie bei _chipVisuals: Dark kräftiger, Light etwas sanfter
    return dark ? base.withOpacity(0.35) : base.withOpacity(0.20);
  }

  // Map: Fahrzeug-ID -> endgültige Farbe (aus Hex oder Palette)
  final Map<int, Color> _vehColorById = {};

  // 12er-Palette (Material-ähnliche Töne)
  Color _vehicleColor(int idx) {
    const palette = <Color>[
      Color(0xFF5C6BC0), // Indigo 400
      Color(0xFF26A69A), // Teal 400
      Color(0xFF7E57C2), // Deep Purple 400
      Color(0xFF66BB6A), // Green 400
      Color(0xFFFFB74D), // Orange 300
      Color(0xFF546E7A), // Blue Grey 600
      Color(0xFF42A5F5), // Blue 400
      Color(0xFFAB47BC), // Purple 400
      Color(0xFFEC407A), // Pink 400
      Color(0xFF26C6DA), // Cyan 400
      Color(0xFFFF7043), // Deep Orange 400
      Color(0xFF9CCC65), // Light Green 400
    ];
    return palette[idx % palette.length];
  }

  // Stabiler Index aus String-Key (z. B. Kurzname oder "FZ<id>")
  int _stableIndexFor(String key, int mod) {
    int h = 0;
    for (int i = 0; i < key.length; i++) {
      h = 0x1fffffff & (h * 33 + key.codeUnitAt(i));
    }
    return (h & 0x7fffffff) % mod;
  }

  // Hex -> Color (unterstützt "#RRGGBB" und "RRGGBB", ergänzt volle Alpha)
  Color? _vehColorFromHex(String? hex) {
    if (hex == null) return null;
    var s = hex.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  // Hilfszugriff: Farbe für Fahrzeug-Objekt
  Color _colorForVeh(_Veh v) =>
      _vehColorById[v.id] ?? _vehicleColor(v.colorIndex);

  Color _vehicleColorForId(int? vehRowId) {
    if (vehRowId == null) {
      return Colors.transparent;
    }

    // 1) nach _veh suchen wie im Tagesplan
    _Veh? veh;
    for (final v in _vehicles) {
      if (v.id == vehRowId) {
        veh = v;
        break;
      }
    }

    // 2) Fahrzeug gefunden → Farbe exakt wie im Tagesplan
    if (veh != null) {
      return _colorForVeh(veh);
    }

    // 3) Fahrzeug nicht gefunden → stabiler Fallback über ID
    return _vehicleColor(vehRowId % 12);
  }

  // Hilfszugriff: Farbe für Fahrzeug-ID (für Listeneinträge)
  Color _colorForVehId(int vid) {
    final inMap = _vehColorById[vid];
    if (inMap != null) return inMap;
    final v = _vehicles.firstWhere(
      (x) => x.id == vid,
      orElse: () => _Veh(0, '', '', 0),
    );
    return (v.id == 0)
        ? Theme.of(context).colorScheme.outline
        : _vehicleColor(v.colorIndex);
  }

  void _dumpEntries(String tag) {
    // Gruppiert nach Fahrzeug, zeigt Reihenfolge (order) und rowIds
    final byVeh = <int?, List<_Entry>>{};
    for (final e in _entries) {
      (byVeh[e.vehicleRowId] ??= <_Entry>[]).add(e);
    }
    debugPrint(
      '[TGL] DUMP [$tag] mode=${_dayModeIsMorning ? 'M' : 'A'} groups=${byVeh.length}',
    );
    byVeh.forEach((vid, list) {
      list.sort((a, b) => (a.order ?? 1 << 30).compareTo(b.order ?? 1 << 30));
      final ids = list.map((e) => e.rowId).toList();
      final ord = list.map((e) => e.order ?? 0).toList();
      debugPrint(
        '  veh=${vid ?? 0} rows=${list.length} rowIds=$ids orders=$ord',
      );
    });
  }

  void _logLineLoad(
    int r,
    int rid,
    int? kid,
    int? fzgId,
    int? ordM,
    int? ordA,
    int? use,
    String bem,
  ) {
    debugPrint(
      '[LOAD] r=$r rid=$rid kid=${kid ?? 0} fzg=${fzgId ?? 0} '
      'ordM=${ordM ?? 0} ordA=${ordA ?? 0} use=${use ?? 0} bem="${bem.replaceAll('\n', ' ')}"',
    );
  }

  void _setDirty(bool v) {
    if (_suppressDirty) return; // Unterdrückt Dirty während Reload
    if (_hasChanges == v) return; // Kein unnötiges setState
    setState(() => _hasChanges = v);
  }
Future<void> _saveDayPlan() async {
  final sc = AppBus.getSheets?.call();
  if (sc == null) {
    debugPrint('[TagesplanTab._save] SheetsClient == null');
    return;
  }

  final bool isMorning = (_dayModeIsMorning == true);

  // Payload exakt so bauen, wie der Adapter ihn erwartet
  final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
  for (final e in _entries) {
    payload.add({
      'row_id': e.rowId,

      // Fahrzeug-Spalten werden im Adapter aufgelöst
      'fahrzeuge_row_id': e.vehicleRowId,

      // Reihenfolge-Spalten
      if (isMorning)
        'Reihenfolge Morgen': e.order
      else
        'Reihenfolge Abend': e.order,

      // BEMERKUNG – KORRIGIERT: Großes B!
      'Bemerkung': (e.note ?? '').toString(),

      // Meta
      'last_editor': AppBus.editorName ?? '',
      'last_editor_device': AppBus.deviceName ?? '',
      'last_editor_device_id': AppBus.deviceId ?? '',
    });
  }

  debugPrint(
    '[TagesplanTab._save] date=${_selectedDate.toIso8601String().split("T").first} '
    'mode=${isMorning ? "M" : "A"} entries=${_entries.length}',
  );

  try {
    await sc.saveDayPlan(
      _selectedDate,
      payload,
      morning: isMorning,
    );

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gespeichert')),
      );
    }
  } catch (e, st) {
    debugPrint('[TagesplanTab._save] Fehler: $e\n$st');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e')),
      );
    }
  }
}

  // kleine Hilfe, entspricht deiner Loader-Stelle
  Future<void> _ensureVehiclesLoadedIfNeeded() async {
    if (_vehicles.isEmpty) {
      try {
        await _loadVehiclesIfNeeded();
      } catch (_) {}
    }
  }

  Future<bool> _checkUnsavedChangesBeforeDateChange(DateTime _) async {
    if (_hasChanges != true) return true;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen speichern?'),
        content: const Text(
          'Es liegen ungespeicherte Änderungen vor. '
          'Möchtest du diese zuerst speichern?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Verwerfen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (choice == 'save') {
      try {
        await _saveDayPlan();
        _hasChanges = false;
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
          );
        }
        return false;
      }
    } else if (choice == 'discard') {
      _hasChanges = false;
      return true;
    }
    return false; // cancel
  }

  // 1) Einheitliche Speicher-Abfrage – wir nutzen deine vorhandene Funktion:
  Future<bool> requestSavePromptIfDirty() async {
    // nutzt deine bestehende Dialoglogik
    return await _checkUnsavedChangesBeforeDateChange(_selectedDate);
  }

  // Optionaler Alias (falls TabsWrapper zuerst das probiert):
  Future<bool> maybePromptSaveBeforeContextChange() async {
    return await requestSavePromptIfDirty();
  }

  // oder diese:
  Future<void> setDayMode(bool morning) async {
    await _onDayModeToggle(morning);
  }

  // TabsWrapper ruft ggf. diese Signatur auf:
  Future<void> toggleMorningEveningFromWrapper({
    required bool toMorning,
  }) async {
    await _onDayModeToggle(toMorning);
  }

  // ==== Toggle Morgen/Abend mit Vorbelegung für leeren Abend ====
  Future<void> _onDayModeToggle(bool morning) async {
    // 0) Kein Wechsel nötig?
    if (_dayModeIsMorning == morning) return;

    // 1) Wenn von M -> A umgeschaltet wird, erst einen Snapshot der aktuellen
    //    UI-Reihenfolge UND der Fahrzeug-Zuordnung (Morgen) sichern.
    //    (Wenn von A -> M, brauchen wir keinen Snapshot.)
    final Map<int /*vehId*/, List<int> /*rowIds in UI-Order*/> snapIdsByVeh =
        {};
    final Map<int /*rowId*/, int? /*vehId*/> snapVehByRowId = {};
    if (_dayModeIsMorning && !morning) {
      final byVeh = <int?, List<_Entry>>{};
      for (final e in _entries) {
        (byVeh[e.vehicleRowId] ??= <_Entry>[]).add(e);
        snapVehByRowId[e.rowId] = e.vehicleRowId;
      }
      // stabile Sortierung pro Fahrzeug wie in der UI (order -> name -> rowId)
      byVeh.forEach((vehId, list) {
        if (vehId == null) return; // nur zugeordnete
        list.sort((a, b) {
          final ao = a.order ?? 0x3fffffff;
          final bo = b.order ?? 0x3fffffff;
          if (ao != bo) return ao.compareTo(bo);
          final an = (a.name ?? '').toLowerCase();
          final bn = (b.name ?? '').toLowerCase();
          final nc = an.compareTo(bn);
          if (nc != 0) return nc;
          return a.rowId.compareTo(b.rowId);
        });
        snapIdsByVeh[vehId] = list.map((e) => e.rowId).toList(growable: false);
      });
    }

    // 2) Modus lokal umschalten
    setState(() {
      _dayModeIsMorning = morning;
    });

    // 3) Neu laden gemäß neuem Modus (liest jetzt die passenden Spalten)
    await _loadDayPlan();

    // 4) Nur wenn gerade von M -> A gewechselt wurde:
    if (!_dayModeIsMorning) {
      // Prüfen, ob Abend KOMPLETT leer ist (keine Order > 0 für zugeordnete Einträge).
      final bool eveningEmpty =
          _entries.isEmpty ||
          _entries.every((e) => (e.order == null || (e.order ?? 0) <= 0));

      if (eveningEmpty) {
        // → Abend vorbereiten:
        //    a) Fahrzeug-Zuordnungen aus dem Morgen übernehmen
        //    b) Reihenfolge pro Fahrzeug GRUPPENWEISE invertieren (1..N rückwärts)
        //    Hinweis: Wir fassen nur die Einträge an, die im Morgen-Snapshot vorkamen.
        final idxByRowId = <int, int>{};
        for (var i = 0; i < _entries.length; i++) {
          idxByRowId[_entries[i].rowId] = i;
        }

        bool changed = false;

        // a) Fahrzeuge übernehmen
        snapVehByRowId.forEach((rowId, vehId) {
          final idx = idxByRowId[rowId];
          if (idx != null) {
            // nur setzen, wenn aktuell (Abend) noch keine Zuordnung vorhanden ist
            if (_entries[idx].vehicleRowId != vehId) {
              _entries[idx].vehicleRowId = vehId;
              changed = true;
            }
          }
        });

        // b) Reihenfolge je Fahrzeug rückwärts aus snapIdsByVeh
        snapIdsByVeh.forEach((vehId, idsInUiOrder) {
          final len = idsInUiOrder.length;
          for (int newPos = 1; newPos <= len; newPos++) {
            final rowId = idsInUiOrder[len - newPos]; // rückwärts
            final idx = idxByRowId[rowId];
            if (idx == null) continue;
            // nur auf die Einträge anwenden, die auch diesem Fahrzeug zugeordnet sind
            if (_entries[idx].vehicleRowId == vehId) {
              _entries[idx].order = newPos;
              changed = true;
            }
          }
        });

        if (changed) {
          // wie in der UI üblich sortieren: vehicle -> order -> name -> rowId
          if (_vehicles.isEmpty) {
            try {
              await _loadVehiclesIfNeeded();
            } catch (_) {}
          }
          int grpIdx(int? vid) {
            if (vid == null) return 1000000;
            final ix = _vehicles.indexWhere((v) => v.id == vid);
            return (ix < 0) ? 900000 : ix;
          }

          _entries.sort((a, b) {
            final ga = grpIdx(a.vehicleRowId), gb = grpIdx(b.vehicleRowId);
            if (ga != gb) return ga.compareTo(gb);

            final ao = a.order ?? 1 << 30, bo = b.order ?? 1 << 30;
            if (ao != bo) return ao.compareTo(bo);

            final an = (a.name ?? '').toLowerCase(),
                bn = (b.name ?? '').toLowerCase();
            final nc = an.compareTo(bn);
            return (nc != 0) ? nc : a.rowId.compareTo(b.rowId);
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Abend vorbereitet – bitte speichern.'),
                duration: Duration(milliseconds: 1600),
              ),
            );
          }
        } else {
          // Nichts zu tun (z. B. keine Morgen-Zuordnung vorhanden)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Abend geladen.'),
                duration: Duration(milliseconds: 1200),
              ),
            );
          }
        }

        // Abend wurde (ggf. aus dem Morgen) vorbereitet/initialisiert –
        // in jedem Fall kann jetzt sinnvoll gespeichert werden → Button aktivieren.
        // Abend wurde (ggf. aus dem Morgen) vorbereitet/initialisiert –
        // in jedem Fall kann jetzt sinnvoll gespeichert werden → Button aktivieren.
        if (mounted) {
          // Direkt Dirty setzen
          _setDirty(true);
          // Und nach dem nächsten Frame noch einmal sicherstellen,
          // dass _hasChanges nicht durch _loadDayPlan() wieder auf false gesetzt wird.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _hasChanges = true;
            });
          });
        }
      } else {
        // Abend hatte bereits Werte → normaler Hinweis
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Abend geladen.'),
              duration: Duration(milliseconds: 1200),
            ),
          );
        }
      }
    } else {
      // Wechsel A -> M: nur Hinweis
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Morgen geladen.'),
            duration: Duration(milliseconds: 1200),
          ),
        );
      }
    }
  }

  // Für TabsWrapper: Datum abrufen
  DateTime get selectedDate => _selectedDate;
  String selectedDateLabelDE() {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_selectedDate.day)}.${two(_selectedDate.month)}.${_selectedDate.year}';
  }

  // Für TabsWrapper: denselben Date-Picker auslösen wie bisher
  void pickDateFromWrapper() => _pickDate();

  // === TP-DATE-API START (Wrapper-Aufrufe) ===
  // Aus TabsWrapper: Datum um ±deltaDays wechseln (inkl. Save-Nachfrage & Reload)

  Future<void> changeDateByFromWrapper(int deltaDays) async {
    if (deltaDays == 0) return;
    final target = _selectedDate.add(Duration(days: deltaDays));
    await _changeDateWithDirtyHandling(target);
  }

  /// Aus TabsWrapper: auf „Heute“ springen (inkl. Save-Nachfrage & Reload)
  Future<void> goToTodayFromWrapper() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(today, _selectedDate)) return;
    await _changeDateWithDirtyHandling(today);
  }

  /// Interne Routine: Datumswechsel mit „Änderungen speichern?“-Dialog und Reload
  Future<void> _changeDateWithDirtyHandling(DateTime d) async {
    if (_sameDay(d, _selectedDate)) return;

    final decision = await _confirmDateChangeIfDirty();
    if (decision == _DateChangeDecision.cancel) return;

    if (decision == _DateChangeDecision.saveFirst) {
      try {
        await _save(); // setzt _hasChanges=false und lädt danach frisch
      } catch (_) {
        // Speichern fehlgeschlagen -> nicht wechseln
        return;
      }
    }
    // discard: einfach weiter

    setState(() => _selectedDate = d);
    await _loadVehiclesIfNeeded();
    await _loadDayPlan();
    await _loadDriverAssignmentsForSelectedDate();
    await _autoSwitchToMorningIfEveningEmpty();
  }
  // === TP-DATE-API END ===

  Future<void> _exportTagesplanPdf() async {
    try {
      debugPrint('[TagesplanTab] _exportTagesplanPdf(): START');

      // Supabase-Login sicherstellen
      await AppAuth.ensureSignedIn();

      // --------------------------------------------------
      // 1) Woche anhand _selectedDate bestimmen
      // --------------------------------------------------
      final base = _selectedDate; // aktuelles Datum im Tagesplan

      DateTime weekStart(DateTime d) {
        final wd = d.weekday; // 1 = Mo..7 = So
        return DateTime(
          d.year,
          d.month,
          d.day,
        ).subtract(Duration(days: wd - DateTime.monday));
      }

      String fmt(DateTime d) {
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(d.day)}.${two(d.month)}.${d.year}';
      }

      final weekStartDate = weekStart(base);
      final weekEndDate = weekStartDate.add(const Duration(days: 6));

      // Mo..So Liste
      final days = List<DateTime>.generate(
        7,
        (i) => DateTime(
          weekStartDate.year,
          weekStartDate.month,
          weekStartDate.day + i,
        ),
      );

      // Modus aus Toggle: true = Morgen, false = Abend
      final bool isMorning = (_dayModeIsMorning == true);

      // --------------------------------------------------
      // 2) Einrichtung + Logo (wie Dienstplan)
      // --------------------------------------------------
      final einrConfig = await SupaAdapter.einrichtungen.readActiveConfig();
      final einrName = einrConfig['name'] ?? '';
      final einrAddress = einrConfig['address'] ?? '';
      final einrRowIdStr = einrConfig['row_id'];
      final int? einrRowId = einrRowIdStr != null
          ? int.tryParse(einrRowIdStr)
          : null;

      final rawLogoUrl = (einrConfig['logo_url'] ?? '').toString().trim();
      pw.MemoryImage? logoImage;

      debugPrint('[TagesplanTab] rawLogoUrl="$rawLogoUrl"');

      if (rawLogoUrl.isNotEmpty &&
          (rawLogoUrl.startsWith('http://') ||
              rawLogoUrl.startsWith('https://'))) {
        try {
          final resp = await http.get(Uri.parse(rawLogoUrl));
          debugPrint('[TagesplanTab] logo HTTP status=${resp.statusCode}');
          if (resp.statusCode == 200) {
            logoImage = pw.MemoryImage(resp.bodyBytes);
            debugPrint(
              '[TagesplanTab] Logo geladen (Bytes=${resp.bodyBytes.length})',
            );
          } else {
            debugPrint('[TagesplanTab] Logo konnte nicht geladen werden.');
          }
        } catch (e) {
          debugPrint('[TagesplanTab] Fehler beim Laden des Logos: $e');
        }
      } else {
        debugPrint(
          '[TagesplanTab] rawLogoUrl leer oder kein http(s) → kein Logo angezeigt',
        );
      }

      // --------------------------------------------------
      // 3) Fahrzeuge + Farben (wie Dienstplan)
      // --------------------------------------------------
      final fahrzeugRows = await SupaAdapter.fahrzeuge.fetchVehicles(
        einrRowId: einrRowId,
        onlyActive: true,
      );
      final vehColorMap = <int, PdfColor>{};
      final vehLabelMap = <int, String>{};

      for (final v in fahrzeugRows) {
        if (v is! Map<String, dynamic>) continue;
        final id = (v['row_id'] is int)
            ? v['row_id'] as int
            : int.tryParse('${v['row_id'] ?? ''}') ?? 0;
        if (id <= 0) continue;

        final kurz =
            ('${v['Fahrzeug Kurz'] ?? v['fahrzeug_kurz'] ?? v['kurz'] ?? ''}')
                .trim();
        final nameFz =
            ('${v['Bezeichnung'] ?? v['bezeichnung'] ?? v['name'] ?? ''}')
                .trim();
        final label = kurz.isNotEmpty
            ? kurz
            : (nameFz.isNotEmpty ? nameFz : 'FZ $id');

        final rawHex = ('${v['Anzeigenfarbe'] ?? v['anzeigenfarbe'] ?? ''}')
            .trim();
        final hexColor = _vehColorFromHex(rawHex);
        final keyForIndex = kurz.isNotEmpty ? kurz : 'FZ$id';
        final stableIdx = _stableIndexFor(keyForIndex, 12);
        final baseColor = hexColor ?? _vehicleColor(stableIdx);

        vehColorMap[id] = PdfColor.fromInt(baseColor.value);
        vehLabelMap[id] = label;
      }

      // --------------------------------------------------
      // 4) Styles (vom Dienstplan übernommen)
      // --------------------------------------------------
      const double boxHeight = 24;
      const double logoBoxHeight = 50;

      final doc = pw.Document();

      final headerStyle = pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      );
      final subHeaderStyle = pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      );
      final normalStyle = const pw.TextStyle(fontSize: 9);
      final nameStyle = const pw.TextStyle(fontSize: 11);
      final tinyStyle = const pw.TextStyle(fontSize: 7);

      // --------------------------------------------------
      // 5) Hilfsfunktionen für Supabase/Parsing
      // --------------------------------------------------
      int? _asIntOrNull(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse('$v');
      }

      String _toDateStr(DateTime d) {
        // yyyy-MM-dd
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      // Kompatible "IN"-Funktion für verschiedene SDK-Versionen
      dynamic supaIn(dynamic q, String column, List values) {
        try {
          // neue SDKs
          return q.inFilter(column, values);
        } catch (_) {
          try {
            // ältere SDKs (supabase-dart v1.x)
            return q.in_(column, values);
          } catch (_) {
            // letzter Fallback
            return q.filter(column, 'in', values);
          }
        }
      }

      // --------------------------------------------------
      // 6) Tagesplan aus Supabase holen (Woche)
      // --------------------------------------------------
      final fromStr = _toDateStr(weekStartDate);
      final toStr = _toDateStr(weekEndDate);

      final supa = Supa.client;

      final rawTages = await supa
          .from('Tagesplan')
          .select()
          .gte('Datum', fromStr)
          .lte('Datum', toStr);

      final tagesplanRows = List<Map<String, dynamic>>.from(
        rawTages as List<dynamic>,
      );

      // --------------------------------------------------
      // 7) Klienten-Namen aus "Klienten" holen
      // --------------------------------------------------
      final clientIdSet = <int>{};
      for (final r in tagesplanRows) {
        final cid = _asIntOrNull(r['Klienten row_id']);
        if (cid != null && cid > 0) {
          clientIdSet.add(cid);
        }
      }

      final klientNameById = <int, String>{};

      if (clientIdSet.isNotEmpty) {
        final klientQuery = supaIn(
          supa.from('Klienten').select('row_id, Name, Vorname'),
          'row_id',
          clientIdSet.toList(),
        );

        final rawKlienten = List<Map<String, dynamic>>.from(
          await klientQuery as List<dynamic>,
        );

        for (final k in rawKlienten) {
          final id = _asIntOrNull(k['row_id']);
          if (id == null || id <= 0) continue;
          final name = (k['Name'] ?? '').toString().trim();
          final vorname = (k['Vorname'] ?? '').toString().trim();
          final display = [
            name,
            vorname,
          ].where((s) => s.isNotEmpty).join(', ').trim();
          klientNameById[id] = display.isNotEmpty ? display : 'Klient $id';
        }
      }

      // --------------------------------------------------
      // 8) weekData[Datum] = geordnete Liste von Klienten
      //    { name, vehRowId }
      // --------------------------------------------------
      final Map<DateTime, List<Map<String, dynamic>>> weekData = {
        for (final d in days) d: <Map<String, dynamic>>[],
      };

      String weekdayNameDe(int weekday) {
        switch (weekday) {
          case DateTime.monday:
            return 'Montag';
          case DateTime.tuesday:
            return 'Dienstag';
          case DateTime.wednesday:
            return 'Mittwoch';
          case DateTime.thursday:
            return 'Donnerstag';
          case DateTime.friday:
            return 'Freitag';
          case DateTime.saturday:
            return 'Samstag';
          case DateTime.sunday:
            return 'Sonntag';
          default:
            return '$weekday';
        }
      }

      for (final d in days) {
        final dateStr = _toDateStr(d);
        final rowsForDay = tagesplanRows.where((r) {
          final rd = (r['Datum'] ?? '').toString();
          return rd.startsWith(dateStr);
        }).toList();

        final withVeh = <Map<String, dynamic>>[];
        final noVeh = <Map<String, dynamic>>[];

        for (final r in rowsForDay) {
          final cid = _asIntOrNull(r['Klienten row_id']);
          if (cid == null || cid <= 0) continue;

          final vehField = isMorning
              ? 'Fahrzeuge row_id Morgen'
              : 'Fahrzeuge row_id Abend';
          final orderField = isMorning
              ? 'Reihenfolge Morgen'
              : 'Reihenfolge Abend';

          final vehId = _asIntOrNull(r[vehField]);
          final order = _asIntOrNull(r[orderField]);
          final name = klientNameById[cid] ?? 'Klient $cid';

          final entry = <String, dynamic>{
            'clientId': cid,
            'name': name,
            'vehRowId': vehId,
            'order': order,
          };

          if (vehId != null && vehId > 0) {
            withVeh.add(entry);
          } else {
            noVeh.add(entry);
          }
        }

        // Sortierung: mit Fahrzeug nach Fahrzeug, dann Reihenfolge, dann Name
        withVeh.sort((a, b) {
          final va = _asIntOrNull(a['vehRowId']) ?? 0;
          final vb = _asIntOrNull(b['vehRowId']) ?? 0;
          if (va != vb) return va.compareTo(vb);

          final oa = _asIntOrNull(a['order']) ?? 9999;
          final ob = _asIntOrNull(b['order']) ?? 9999;
          if (oa != ob) return oa.compareTo(ob);

          final na = (a['name'] ?? '').toString();
          final nb = (b['name'] ?? '').toString();
          return na.compareTo(nb);
        });

        // ohne Fahrzeug nach Klienten-row_id
        noVeh.sort((a, b) {
          final ca = _asIntOrNull(a['clientId']) ?? 0;
          final cb = _asIntOrNull(b['clientId']) ?? 0;
          return ca.compareTo(cb);
        });

        final combined = <Map<String, dynamic>>[];
        combined.addAll(withVeh);
        combined.addAll(noVeh);

        weekData[d] = combined;
        debugPrint(
          '[TagesplanTab] Tag ${_toDateStr(d)}: ${combined.length} Einträge',
        );
      }

      // --------------------------------------------------
      // 9) Tabellenkopf & Datenzeilen (Klient 1..N)
      // --------------------------------------------------
      pw.TableRow buildHeaderRow() {
        final cells = <pw.Widget>[];

        // Spalte 0: "Klienten"
        cells.add(
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text('Klienten', style: subHeaderStyle),
          ),
        );

        // Spalten 1..7: Wochentag + Datum
        for (final d in days) {
          final wname = weekdayNameDe(d.weekday);
          final dateText = fmt(d);

          cells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2,
                horizontal: 1,
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    wname,
                    style: subHeaderStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    dateText,
                    style: tinyStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return pw.TableRow(children: cells);
      }

      int maxRows = 0;
      for (final d in days) {
        final len = weekData[d]?.length ?? 0;
        if (len > maxRows) maxRows = len;
      }

      pw.TableRow buildDataRow(int rowIndex) {
        final rowCells = <pw.Widget>[];

        // Spalte 0: "Klient X"
        final label = 'Klient ${rowIndex + 1}';
        rowCells.add(
          pw.Container(
            height: boxHeight,
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: pw.Text(label, style: nameStyle),
          ),
        );

        // Spalten 1..7: pro Tag
        for (final d in days) {
          final list = weekData[d] ?? const <Map<String, dynamic>>[];

          String nameKlient = '';
          int? vehRowId;

          if (rowIndex < list.length) {
            final entry = list[rowIndex];
            nameKlient = (entry['name'] ?? '').toString();
            vehRowId = _asIntOrNull(entry['vehRowId']);
          }

          final PdfColor? bg = (vehRowId != null)
              ? vehColorMap[vehRowId]
              : null;

          rowCells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2,
                horizontal: 1,
              ),
              child: pw.Container(
                height: boxHeight,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.3, color: PdfColors.grey),
                  color: bg,
                ),
                // WICHTIG: Nur Klientenname, KEIN Fahrzeug-Kürzel!
                child: (nameKlient.isNotEmpty)
                    ? pw.Text(
                        nameKlient,
                        style: nameStyle,
                        textAlign: pw.TextAlign.center,
                      )
                    : null,
              ),
            ),
          );
        }

        return pw.TableRow(children: rowCells);
      }

      // --------------------------------------------------
      // 10) Legende (Fahrzeuge + Modus M/A)
      // --------------------------------------------------
      final modusText = isMorning ? 'Morgenfahrt (M)' : 'Abendfahrt (A)';

      pw.Widget buildLegend() {
        final vehLegend = vehLabelMap.entries
            .map(
              (e) => pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(
                    width: 10,
                    height: 10,
                    color: vehColorMap[e.key],
                  ),
                  pw.SizedBox(width: 3),
                  pw.Text(e.value, style: tinyStyle),
                ],
              ),
            )
            .toList();

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Fahrzeuge:', style: subHeaderStyle),
            pw.Wrap(spacing: 8, runSpacing: 4, children: vehLegend),
            pw.SizedBox(height: 6),
            pw.Text('Modus:', style: subHeaderStyle),
            pw.Text(modusText, style: tinyStyle),
          ],
        );
      }

      // --------------------------------------------------
      // 11) Seite aufbauen – Kopf, Tabelle, Seitenfuß
      // --------------------------------------------------
      final fahrerplanTitle =
          'Fahrerplan ${fmt(weekStartDate)} - ${fmt(weekEndDate)}';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(16),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Seite ${context.pageNumber} / ${context.pagesCount}',
              style: tinyStyle,
            ),
          ),
          build: (ctx) {
            final tableRows = <pw.TableRow>[];
            tableRows.add(buildHeaderRow());
            for (var i = 0; i < maxRows; i++) {
              tableRows.add(buildDataRow(i));
            }

            return [
              // Kopf: Logo links, Überschrift mittig, Legende rechts
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // links: Logo + Name + Adresse
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null) ...[
                        pw.Container(
                          width: 80,
                          height: logoBoxHeight,
                          alignment: pw.Alignment.topLeft,
                          child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
                        ),
                        pw.SizedBox(height: 2),
                      ],
                      pw.Text(
                        einrName.isEmpty ? 'Fahrdienst Tagespflege' : einrName,
                        style: normalStyle,
                      ),
                      if (einrAddress.isNotEmpty) ...[
                        pw.Text(einrAddress, style: normalStyle),
                      ],
                    ],
                  ),

                  pw.Spacer(),

                  // Mitte: Überschriften
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        fahrerplanTitle,
                        style: headerStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        'Fahrdienst Tagespflege - Stand ${fmt(DateTime.now())}',
                        style: normalStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),

                  pw.Spacer(),

                  // rechts: Legende (leicht nach unten verschoben, wie Dienstplan)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [pw.SizedBox(height: 20), buildLegend()],
                  ),
                ],
              ),

              // Abstand vor Tabelle: 20 (wie im Dienstplan)
              pw.SizedBox(height: 20),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey, width: 0.4),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  for (var i = 1; i <= 7; i++) i: const pw.FlexColumnWidth(3),
                },
                children: tableRows,
              ),
            ];
          },
        ),
      );

      // --------------------------------------------------
      // 12) PDF-Vorschau öffnen
      // --------------------------------------------------
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            appBar: AppBar(title: const Text('Fahrerplan PDF')),
            body: PdfPreview(
              build: (format) async => doc.save(),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName:
                  'fahrerplan_${weekStartDate.year.toString().padLeft(4, '0')}_'
                  '${weekStartDate.month.toString().padLeft(2, '0')}_'
                  '${weekStartDate.day.toString().padLeft(2, '0')}',
            ),
          ),
        ),
      );

      debugPrint('[TagesplanTab] _exportTagesplanPdf(): ENDE OK');
    } catch (e, st) {
      debugPrint('[TagesplanTab] _exportTagesplanPdf(): FEHLER $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Erstellen des Fahrerplans: $e')),
      );
    }
  }

  /// M/A-Umschalter – theme-adaptiv (Light & Dark)
  Widget _buildMAToggle() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bool isM = _dayModeIsMorning == true;

    final ButtonStyle style = ButtonStyle(
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      visualDensity: VisualDensity.compact,
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      side: MaterialStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(MaterialState.selected)
              ? cs.primary
              : cs.outlineVariant,
          width: 1,
        ),
      ),
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return cs.primaryContainer;
        }
        // Unselected: leicht helleres Grau im Dark Mode, hell im Light Mode
        return isDark ? const Color(0xFF2A2A2A) : cs.surfaceVariant;
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return cs.onPrimaryContainer;
        }
        return cs.onSurfaceVariant;
      }),
    );

    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(value: true, label: Text('M')),
        ButtonSegment<bool>(value: false, label: Text('A')),
      ],
      selected: {isM},
      showSelectedIcon: false,
      style: style,
      onSelectionChanged: (set) {
        final val = set.first;
        if (val != _dayModeIsMorning) {
          _onDayModeToggle(val);
        }
      },
    );
  }

  /// Kleiner Umschalter "M / A" (Morgen / Abend) – Dark/Light sichtbar unabhängig vom Theme
  Widget _buildDayModeToggle() {
    final bool isM = _dayModeIsMorning == true;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color activeColor = isDark
        ? const Color(0xFF80B3FF)
        : const Color(0xFF1565C0);
    final Color inactiveBg = isDark
        ? const Color(0xFF2E2E2E)
        : const Color(0xFFE0E0E0);
    final Color inactiveText = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          const Text('Modus:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: true, label: Text('M')),
              ButtonSegment<bool>(value: false, label: Text('A')),
            ],
            selected: {isM},
            showSelectedIcon: false,
            style: ButtonStyle(
              padding: MaterialStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              visualDensity: VisualDensity.compact,
              shape: MaterialStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              backgroundColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) return activeColor;
                return inactiveBg;
              }),
              foregroundColor: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected))
                  return Colors.white;
                return inactiveText;
              }),
              side: MaterialStateProperty.all(
                BorderSide(
                  color: isDark ? Colors.white24 : Colors.black26,
                  width: 1,
                ),
              ),
            ),
            onSelectionChanged: (set) {
              final val = set.first;
              if (val != _dayModeIsMorning) _onDayModeToggle(val);
            },
          ),
        ],
      ),
    );
  }

  // Name links (2 Teile), Bemerkung rechts (3 Teile) – läuft bis kurz vor 'Bearbeiten'
  Widget _buildTitleRow(_Entry e, BuildContext context) {
    final theme = Theme.of(context);
    final name = e.name.trim();
    final note = e.note.trim();

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        // Name links – ellipsen falls lang
        Flexible(
          flex: 2,
          child: Text(
            name.isEmpty ? '–' : name,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),

        // Bemerkung rechts – dicht vor dem Edit-Icon, ohne Umbruch
        if (note.isNotEmpty)
          Flexible(
            flex: 3,
            child: Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
      ],
    );
  }

  Widget _buildTitle(_Entry e) {
    final name = e.name;
    final note = e.note.trim();

    final TextStyle titleStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final TextStyle noteStyle = titleStyle.copyWith(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ~2/3: Name
        Expanded(
          flex: 2,
          child: Text(
            name,
            style: titleStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // ~1/3: Bemerkung (einzeilig, abgeschnitten)
        Expanded(
          flex: 1,
          child: Text(
            note,
            style: noteStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }

  // ---- Chip-Visuals (einzige gültige Version) ----
  _ChipVisuals _chipVisuals(Color base, bool active, BuildContext ctx) {
    final dark = _isDark(ctx);
    final border = base;
    // deutlichere Füllung im Dark-Mode wenn aktiv
    final fill = active
        ? (dark ? base.withOpacity(0.35) : base.withOpacity(0.20))
        : Colors.transparent;
    final labelStyle = TextStyle(
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
    );
    return _ChipVisuals(border: border, fill: fill, labelStyle: labelStyle);
  }

  final List<_Veh> _vehicles = <_Veh>[];
  final List<_Entry> _entries = <_Entry>[];
  final Map<int, String> _clientNameById = {}; // row_id → "Nachname Vorname"

  final Map<int, int> _dayRowIdByClientId =
      {}; // Klienten row_id -> Tagesplan row_id

  // Dienstplan: pro Tag -> Map<Fahrzeug-ID, Fahrername]
  final Map<int, String> _driverNameByVehicleId = {};

  /// Spaltenname im Dienstplan für den aktuellen Wochentag ermitteln.
  /// Basis: Tabelle "Dienstplan" mit Spalten:
  /// "Fahrzeuge row_id Mo", "Fahrzeuge row_id Di", ..., "Fahrzeuge row_id So"
  String _dienstplanVehicleColumnForWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Fahrzeuge row_id Mo';
      case DateTime.tuesday:
        return 'Fahrzeuge row_id Di';
      case DateTime.wednesday:
        return 'Fahrzeuge row_id Mi';
      case DateTime.thursday:
        return 'Fahrzeuge row_id Do';
      case DateTime.friday:
        return 'Fahrzeuge row_id Fr';
      case DateTime.saturday:
        return 'Fahrzeuge row_id Sa';
      case DateTime.sunday:
        return 'Fahrzeuge row_id So';
      default:
        return 'Fahrzeuge row_id Mo';
    }
  }

  /// Fahrer-Zuordnung aus "Dienstplan" für das aktuell gewählte Datum laden.
  /// Ergebnis: _driverNameByVehicleId[fahrzeugId] = "Nachname Vorname"
  Future<void> _loadDriverAssignmentsForSelectedDate() async {
    debugPrint(
      '[DP] _loadDriverAssignmentsForSelectedDate ENTER '
      'selectedDate=${_selectedDate.toIso8601String().split("T").first}',
    );

    if (!AppConfig.useSupabase) {
      debugPrint('[DP] Supabase disabled -> skip Fahrer-Mapping');
      return;
    }

    // ---------- 1) Fahrer-Namen aus "Mitarbeiter" holen ----------
    final Map<int, String> driverNameByMitId = {};

    try {
      final mitRows = await SupaAdapter.mitarbeiter.fetchDriversForDienstplan();
      debugPrint('[DP] fetchDriversForDienstplan -> ${mitRows.length} rows');

      for (final r in mitRows) {
        if (r is! Map) {
          debugPrint('[DP] skip non-Map mitRow: $r');
          continue;
        }

        final mitId = (r['row_id'] as num?)?.toInt();
        if (mitId == null || mitId <= 0) continue;

        final nach = '${r['Name'] ?? r['Nachname'] ?? ''}'.trim();
        final vor = '${r['Vorname'] ?? ''}'.trim();
        final display = [nach, vor].where((e) => e.isNotEmpty).join(' ').trim();

        debugPrint('[DP] mitRow: id=$mitId name="$display" keys=${r.keys}');

        if (display.isEmpty) continue;
        driverNameByMitId[mitId] = display;
      }

      debugPrint(
        '[DP] driverNameByMitId size=${driverNameByMitId.length} -> $driverNameByMitId',
      );
    } catch (e, st) {
      debugPrint('[DP] fetchDriversForDienstplan ERROR: $e\n$st');
    }

    // ---------- 2) Dienstplan-Woche holen und Fahrzeug→Fahrer mappen ----------
    final Map<int, String> map = {};

    try {
      // Wochenbeginn (Montag) berechnen
      final int delta = _selectedDate.weekday - DateTime.monday;
      final DateTime weekStart = _selectedDate.subtract(
        Duration(days: delta < 0 ? 6 : delta),
      );

      debugPrint('[DP] computed weekStart=$weekStart');

      final rows = await SupaAdapter.dienstplan.fetchWeekPlan(weekStart);
      debugPrint('[DP] fetchWeekPlan -> ${rows.length} rows');

      final col = _dienstplanVehicleColumnForWeekday(_selectedDate.weekday);
      debugPrint(
        '[DP] using vehicle column "$col" for weekday=${_selectedDate.weekday}',
      );

      for (final r in rows) {
        if (r is! Map) {
          debugPrint('[DP] skip non-Map row: $r');
          continue;
        }

        final vehId = (r[col] as num?)?.toInt();
        final mitId = (r['Mitarbeiter row_ID'] as num?)?.toInt();

        debugPrint('[DP] row: mitId=$mitId vehId=$vehId keys=${r.keys}');

        if (vehId == null || vehId <= 0) continue;
        if (mitId == null || mitId <= 0) continue;

        final display = driverNameByMitId[mitId] ?? '';
        debugPrint('[DP]   resolved name for mitId=$mitId -> "$display"');

        if (display.isEmpty) continue;

        // Falls mehrere Zeilen dasselbe Fahrzeug haben, gewinnt der erste Eintrag.
        map.putIfAbsent(vehId, () => display);
      }

      debugPrint(
        '[DP] result _driverNameByVehicleId size=${map.length} -> $map',
      );
    } catch (e, st) {
      debugPrint('[DP] _loadDriverAssignmentsForSelectedDate ERROR: $e\n$st');
    }

    if (!mounted) return;

    setState(() {
      _driverNameByVehicleId
        ..clear()
        ..addAll(map);
    });
  }

  // --- Warten bis Sheets verfügbar ist (HomePage setzt AppBus.getSheets in initState) ---
  int _sheetWaitTries = 0;
  Future<void> _waitForSheetsThenLoad() async {
    for (; _sheetWaitTries < 10; _sheetWaitTries++) {
      final g = AppBus.getSheets;
      if (g != null && g.call() != null) {
        await _loadVehiclesIfNeeded();
        await _loadDayPlan();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    debugPrint('TagesplanTab: AppBus.getSheets blieb null (10 Versuche).');
  }

  Future<void> _ensureInitialLoad() async {
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    await _loadDayPlan(); // nutzt aktuell gewählten Modus + Datum
  }

  Future<void> _loadDayPlanSafe({int retry = 0}) async {
    if (!mounted) return;
    if (_isLoading) return;

    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      // SheetsClient noch nicht bereit -> kurze, begrenzte Retry-Schleife
      if (retry < 10) {
        debugPrint(
          '[LOADSAFE] SheetsClient=null, retry ${retry + 1}/10 in 250ms',
        );
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _loadDayPlanSafe(retry: retry + 1);
        });
      } else {
        debugPrint('[LOADSAFE] Abbruch: SheetsClient blieb null.');
      }
      return;
    }

    _isLoading = true;
    try {
      await _loadDayPlan(); // deine bestehende _loadDayPlan (mit M/A Logik)
      await _loadDriverAssignmentsForSelectedDate(); // Dienstplan-Fahrer
      _didInitialLoad = true; // Erstladung abgeschlossen
    } catch (e) {
      debugPrint('[LOADSAFE] _loadDayPlan() error: $e');
    } finally {
      _isLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Nach erstem Frame sanft anstoßen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDayPlanSafe(); // garantiert genau einmal
    });
  }

  @override
  void dispose() {
    debugPrint('[TagesplanTab] dispose');
    super.dispose();
  }

  Future<void> _confirmDeleteEntry(_Entry entry) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text(
          'Soll der Eintrag für "${entry.name}" an diesem Tag wirklich gelöscht werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (res != true) return;

    // Fall 1: Eintrag existiert bereits in der DB (row_id > 0)
    if (entry.rowId > 0) {
      try {
        // Direkt aus der Tabelle "Tagesplan" löschen
        await SupaAdapter.tagesplan.deleteRowsByIds([entry.rowId]);

        // Danach den Tagesplan frisch laden
        await _loadDayPlan();
        _setDirty(false); // frisch aus DB
      } catch (e, st) {
        debugPrint(
          '[TagesplanTab] _confirmDeleteEntry Supa-Delete Fehler: $e\n$st',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fehler beim Löschen des Tagesplan-Eintrags.'),
            ),
          );
        }
      }
      return;
    }

    // Fall 2: "Nur lokal" existierender Eintrag (rowId <= 0)
    // (sollte bei deiner aktuellen Logik kaum vorkommen, aber zur Sicherheit)
    setState(() {
      _entries.remove(entry);
    });
    _setDirty(true);
  }

  Future<void> _onAddEntryRequested() async {
    // Namensliste sicherstellen
    if (AppBus.clientNameMap.isEmpty) {
      final sc = AppBus.getSheets?.call();
      if (sc != null) {
        try {
          await _loadClientNameMap(sc);
        } catch (_) {}
      }
    }

    final nameMap = AppBus.clientNameMap;
    if (nameMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Klienten verfügbar.')),
      );
      return;
    }

    // Bereits im Tagesplan sichtbare IDs (wir verwenden hier wie bisher rowId = Klienten-ID)
    final existingIds = _entries.map((e) => e.rowId).toSet();

    // Kandidaten: alle Klienten, die noch nicht im Tagesplan sind
    final candidateIds =
        nameMap.keys.where((id) => !existingIds.contains(id)).toList()..sort(
          (a, b) => (nameMap[a] ?? '').toLowerCase().compareTo(
            (nameMap[b] ?? '').toLowerCase(),
          ),
        );

    if (candidateIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alle Klienten sind bereits im Tagesplan.'),
        ),
      );
      return;
    }

    final searchCtrl = TextEditingController();
    final Set<int> selectedIds =
        <int>{}; // Set in Dart = LinkedHashSet → behält Klick-Reihenfolge

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        List<int> filtered = List<int>.from(candidateIds);

        void applyFilter(String txt) {
          final t = txt.trim().toLowerCase();
          filtered =
              candidateIds.where((id) {
                final n = (nameMap[id] ?? '').toLowerCase();
                return n.contains(t);
              }).toList()..sort(
                (a, b) => (nameMap[a] ?? '').toLowerCase().compareTo(
                  (nameMap[b] ?? '').toLowerCase(),
                ),
              );
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Klienten auswählen',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: (txt) {
                          setModalState(() {
                            applyFilter(txt);
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Suchen',
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
itemBuilder: (ctx, index) {
  final id = filtered[index];
  final rawName = nameMap[id] ?? '';
  final checked = selectedIds.contains(id);

  // Fahrdienst-Status aus AppBus nutzen → false = durchgestrichen
  final bool isFahrdienst = AppBus.isClientFahrdienst(id);

  final baseStyle = DefaultTextStyle.of(ctx).style;
  final nameStyle = isFahrdienst
      ? baseStyle
      : baseStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        );

  return CheckboxListTile(
    value: checked,
    onChanged: (val) {
      setModalState(() {
        if (val == true) {
          selectedIds.add(id);        // Klick-Reihenfolge bleibt erhalten
        } else {
          selectedIds.remove(id);
        }
      });
    },
    title: Text(
      rawName,
      style: nameStyle,
    ),
  );
},

                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Abbrechen'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: selectedIds.isEmpty
                                ? null
                                : () {
                                    Navigator.of(ctx).pop();
                                  },
                            child: const Text('Übernehmen'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Wenn der Dialog ohne Auswahl beendet wurde → nichts tun
    if (selectedIds.isEmpty) {
      return;
    }

    // WICHTIG:
    // Jetzt NICHT lokal _entries verändern,
    // sondern direkt in die DB schreiben und dann neu laden:
    await _addClientsToDayplanAndReload(selectedIds);
  }

  Future<void> _addClientsToDayplanAndReload(Set<int> clientIds) async {
    if (clientIds.isEmpty) return;

    try {
      // dieselben Variablen, die du auch beim Speichern verwendest
      final date = _selectedDate; // oder wie deine Datumsvariable heißt
      final isMorning = _dayModeIsMorning; // dein Flag für Morgen/Abend

      // in Supabase einfache Zeilen anlegen
      await SupaAdapter.tagesplan.insertClientsForDateSimple(
        date: date,
        clientIds: List<int>.from(clientIds), // Reihenfolge = Klick-Reihenfolge
      );

      // danach den Tagesplan komplett neu laden
      await _loadDayPlan();
      _setDirty(false); // frisch geladen = nicht "dirty"
    } catch (e, st) {
      debugPrint(
        '[TagesplanTab] _addClientsToDayplanAndReload Fehler: $e\n$st',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Hinzufügen der Klienten zum Tagesplan.'),
          ),
        );
      }
    }
  }

  Future<void> refreshFromWrapper() async {
    // Während eines Speichervorgangs keine Auto-Reloads ausführen,
    // um doppeltes Neuladen / Flackern zu vermeiden.
    if (_isSavingDayPlan) {
      debugPrint(
        '[TagesplanTab] refreshFromWrapper(): ignoriert, isSavingDayPlan=true',
      );
      return;
    }

    await _loadDayPlanSafe();
  }

  void addPersonFromWrapper() {} // Tagesplan braucht das nicht

  // --- Druck-API für TabsWrapper (Tagesplan) ---
  Future<void> printFromWrapper() async {
    await _exportTagesplanPdf();
  }

  Future<void> _loadClientNameMap(dynamic sc) async {
    // 1) Erst der bisherige Weg: wenn der Adapter (Sheets ODER Supa-Bridge)
    //    eine fetchClientNameMap() hat, diese nutzen.
    try {
      if (sc.fetchClientNameMap is Function) {
        final m = await sc.fetchClientNameMap();
        if (m is Map && m.isNotEmpty) {
          // Globale Datenstruktur in AppBus aktualisieren
          final map = m.map(
            (k, v) => MapEntry(int.tryParse('$k') ?? (k as int), '$v'),
          );

          final sorted = map.keys.toList()
            ..sort((a, b) {
              final na = (map[a] ?? '').toLowerCase();
              final nb = (map[b] ?? '').toLowerCase();
              return na.compareTo(nb);
            });

          if (!mounted) return;
          setState(() {
            AppBus.clientNameMap = Map<int, String>.from(map);
            AppBus.clientIdsSorted = List<int>.from(sorted);
          });

          debugPrint(
            '[Klienten] via sc.fetchClientNameMap -> ${AppBus.clientNameMap.length}',
          );
          return; // Erfolg -> fertig
        }
      }
    } catch (e) {
      debugPrint('[Klienten] sc.fetchClientNameMap ERROR: $e');
      // Fällt unten in Fallback
    }

    // 2) Fallback NUR, wenn oben nichts lieferte: direkt über Supabase ziehen.
    try {
      int? einrId;
      try {
        final sp = await SharedPreferences.getInstance();
        final s = sp.getString('einrichtung_row_id')?.trim();
        if (s != null && s.isNotEmpty) einrId = int.tryParse(s);
      } catch (e) {
        debugPrint('[Klienten] SP read error: $e');
      }

      // Klientenliste holen
      List<Map<String, dynamic>> list;
      if (einrId == null || einrId <= 0) {
        debugPrint(
          '[Klienten] Fallback: keine gültige Einrichtung gesetzt – lade alle AKTIVEN',
        );
        list = await SupaAdapter.klienten.fetchByEinrichtung(0);
      } else {
        list = await SupaAdapter.klienten.fetchByEinrichtung(einrId);
      }

      // Map + Sortierung erzeugen
      final map = <int, String>{};
      for (final r in list) {
        final id = (r['row_id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final n = '${r['Name'] ?? ''}'.trim();
        final v = '${r['Vorname'] ?? ''}'.trim();
        final full = [n, v].where((e) => e.isNotEmpty).join(' ').trim();
        if (full.isNotEmpty) map[id] = full;
      }

      final sorted = map.keys.toList()
        ..sort((a, b) {
          final na = (map[a] ?? '').toLowerCase();
          final nb = (map[b] ?? '').toLowerCase();
          return na.compareTo(nb);
        });

      if (!mounted) return;
      setState(() {
        AppBus.clientNameMap = Map<int, String>.from(map);
        AppBus.clientIdsSorted = List<int>.from(sorted);
      });

      debugPrint('[Klienten] Fallback Supa -> ${AppBus.clientNameMap.length}');
    } catch (e, st) {
      debugPrint('[Klienten] Supa-Fallback ERROR: $e');
      debugPrint('$st');
    }
  }

  Future<_DateChangeDecision> _confirmDateChangeIfDirty() async {
    if (!_hasChanges) return _DateChangeDecision.proceed;

    final res = await showDialog<_DateChangeDecision>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen speichern?'),
        content: const Text(
          'Es liegen ungespeicherte Änderungen vor.\n'
          'Möchtest du vor dem Datumswechsel speichern?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DateChangeDecision.cancel),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DateChangeDecision.discard),
            child: const Text('Nicht speichern'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_DateChangeDecision.saveFirst),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    return res ?? _DateChangeDecision.cancel;
  }

  Future<void> _loadVehiclesIfNeeded() async {
    if (_vehicles.isNotEmpty) return;

    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      debugPrint('[Tagesplan] getSheets() lieferte null');
      return;
    }
    debugPrint('[Tagesplan] getSheets() -> ${sc.runtimeType}');

    List items = const [];
    try {
      if ((sc as dynamic).fetchVehicles is Function) {
        debugPrint('[Tagesplan] rufe sc.fetchVehicles(onlyActive:true) auf …');
        items = await sc.fetchVehicles(onlyActive: true);
      } else {
        debugPrint('[Tagesplan] sc.fetchVehicles existiert NICHT!');
      }
    } catch (e, st) {
      debugPrint('[Tagesplan] fetchVehicles Fehler: $e\n$st');
      items = const [];
    }

    final list = <_Veh>[];
    final colorMap = <int, Color>{};

    int _asIndex(dynamic v, {required int fallback, int mod = 12}) {
      if (v is int) return v % mod;
      final p = int.tryParse('${v ?? ''}');
      return (p == null) ? fallback : (p % mod);
    }

    for (final v in items) {
      try {
        if (v is Map) {
          final id = int.tryParse('${v['row_id'] ?? v['rowId'] ?? 0}') ?? 0;
          if (id <= 0) continue;

          // WICHTIG: hier jetzt die echte Supabase-Spalte "Fahrzeug Kurz" verwenden
          final kurz =
              '${v['Fahrzeug Kurz'] ?? v['fahrzeug_kurz'] ?? v['kurz'] ?? ''}'
                  .trim();

          final name = '${v['bezeichnung'] ?? v['name'] ?? ''}'.trim();

          // Anzeigenfarbe aus Tabelle
          final hex =
              '${v['Anzeigenfarbe'] ?? v['anzeigenfarbe'] ?? v['anzeige_farbe'] ?? ''}'
                  .trim();
          final hexColor = _vehColorFromHex(hex);

          // Index aus Datensatz oder stabil aus Kurz/ID
          final stableIdx = _stableIndexFor(
            kurz.isNotEmpty ? kurz : 'FZ$id',
            12,
          );
          final colorIndex = _asIndex(v['colorIndex'], fallback: stableIdx);

          // Label: bevorzugt Kurzbezeichnung, sonst Name, sonst FZ+ID
          final label = kurz.isNotEmpty
              ? kurz
              : (name.isNotEmpty ? name : 'FZ $id');

          list.add(_Veh(id, label, name, colorIndex));

          if (hexColor != null) {
            colorMap[id] = hexColor;
            debugPrint(
              '[Tagesplan] HexColor für ID=$id gesetzt: 0x${hexColor.value.toRadixString(16).padLeft(8, '0')}',
            );
          }
        } else {
          // Objekt-Zweig (falls fetchVehicles Klassen-Instanzen liefert)
          final id = (v.rowId as int?) ?? 0;
          if (id <= 0) continue;

          // hier bleibt es bei den Properties des Objekts
          final kurz = '${v.kurz ?? ''}'.trim();
          final name = '${v.bezeichnung ?? v.name ?? ''}'.trim();

          String? rawHex;
          try {
            rawHex = (v.anzeigenfarbe as String?)?.trim();
          } catch (_) {}
          final hexColor = _vehColorFromHex(rawHex);

          final stableIdx = _stableIndexFor(
            kurz.isNotEmpty ? kurz : 'FZ$id',
            12,
          );
          final colorIndex = _asIndex(v.colorIndex, fallback: stableIdx);

          final label = kurz.isNotEmpty
              ? kurz
              : (name.isNotEmpty ? name : 'FZ $id');

          list.add(_Veh(id, label, name, colorIndex));

          if (hexColor != null) {
            colorMap[id] = hexColor;
            debugPrint(
              '[Tagesplan] HexColor (Objekt) für ID=$id gesetzt: 0x${hexColor.value.toRadixString(16).padLeft(8, '0')}',
            );
          }
        }
      } catch (e, st) {
        debugPrint('[Tagesplan] skip kaputte Zeile: $e\n$st');
      }
    }

    list.sort((a, b) => a.kurz.toLowerCase().compareTo(b.kurz.toLowerCase()));

    setState(() {
      _vehicles
        ..clear()
        ..addAll(list);
      _vehColorById
        ..clear()
        ..addAll(colorMap); // Hex-Farben aus der Tabelle übernehmen

      if (_activeVehicleId != null &&
          !_vehicles.any((x) => x.id == _activeVehicleId)) {
        _activeVehicleId = null;
      }
    });

    debugPrint(
      '[Tagesplan] Fahrzeuge geladen: ${_vehicles.length}, HexColors: ${_vehColorById.length}',
    );
  }

  Future<void> _loadDayPlan() async {
    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      debugPrint('[LOAD] SheetsClient==null');
      return;
    }

    // 1) Namen laden und als Snapshot sichern (Timing-Probleme vermeiden)
    try {
      await _loadClientNameMap(AppBus.getSheets?.call());
    } catch (_) {}
    final Map<int, String> _nameMapSnapshot = Map<int, String>.from(
      _clientNameById,
    );
    debugPrint('[LOAD] nameMapSnapshot size=${_nameMapSnapshot.length}');

    // 1b) Fahrer-Zuordnung aus Dienstplan für den aktuellen Tag laden
    await _loadDriverAssignmentsForSelectedDate();

    final bool isMorning = (_dayModeIsMorning == true);

    // 2) Tagesplan holen
    List<dynamic> items;
    try {
      final fetched = await sc.fetchDayPlan(_selectedDate, morning: isMorning);
      if (fetched is! List) {
        debugPrint('[LOAD] fetchDayPlan returned non-list -> $fetched');
        return;
      }
      items = List<dynamic>.from(fetched);
    } catch (e, st) {
      debugPrint('[LOAD] fetchDayPlan error: $e\n$st');
      return;
    }

    // 3) Helper (lokale Closures)
    int? _asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = '$v'.trim();
      if (s.isEmpty) return null;
      return int.tryParse(s);
    }

    String? _asString(dynamic v) => (v == null) ? null : '$v';

    int? _getRowId(dynamic it) {
      if (it is Map) {
        return _asInt(it['row_id']) ?? _asInt(it['RowId']) ?? _asInt(it['id']);
      }
      try {
        return it.rowId as int?;
      } catch (_) {
        return null;
      }
    }

    int? _getKlientId(dynamic it) {
      if (it is Map) {
        return _asInt(it['Klienten row_id']) ??
            _asInt(it['klienten_row_id']) ??
            _asInt(it['KlientId']) ??
            _asInt(it['client_id']);
      }
      try {
        return it.klientId as int?;
      } catch (_) {
        return null;
      }
    }

    int? _getFzgId(dynamic it, bool morning) {
      if (it is Map) {
        return morning
            ? (_asInt(it['Fahrzeuge row_id Morgen']) ??
                  _asInt(it['fzg_morgen_id']) ??
                  _asInt(it['fahrzeuge_row_id_morgen']))
            : (_asInt(it['Fahrzeuge row_id Abend']) ??
                  _asInt(it['fzg_abend_id']) ??
                  _asInt(it['fahrzeuge_row_id_abend']));
      }
      try {
        return morning ? it.fzgMorningId as int? : it.fzgAbendId as int?;
      } catch (_) {
        return null;
      }
    }

    int? _getOrder(dynamic it, bool morning) {
      if (it is Map) {
        return morning
            ? (_asInt(it['Reihenfolge Morgen']) ??
                  _asInt(it['order_morgen']) ??
                  _asInt(it['OrderMorning']))
            : (_asInt(it['Reihenfolge Abend']) ??
                  _asInt(it['order_abend']) ??
                  _asInt(it['OrderEvening']));
      }
      try {
        return morning
            ? it.reihenfolgeMorgen as int?
            : it.reihenfolgeAbend as int?;
      } catch (_) {
        return null;
      }
    }

    String _formatNachnameVorname(String raw) {
      final parts = raw.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final nach = parts.first;
        final vor = parts.sublist(1).join(' ');
        return '$nach, $vor';
      }
      return raw;
    }

    String _pickDisplay(dynamic it, int? klientId, Map<int, String> nameMap) {
      // 1) Bevorzugt vom Adapter (_display) – das ist bereits "Nachname, Vorname"
      if (it is Map) {
        final disp = _asString(it['_display']);
        if (disp != null && disp.trim().isNotEmpty) {
          final dd = disp.trim();
          debugPrint('[LOAD|name] use _display="$dd"');
          return dd;
        }
      }
      // 2) Snapshot der NameMap: "Name Vorname" -> drehen
      if (klientId != null) {
        final nv = nameMap[klientId];
        if (nv != null && nv.trim().isNotEmpty) {
          final fmt = _formatNachnameVorname(nv);
          debugPrint('[LOAD|name] use map id=$klientId "$fmt"');
          return fmt;
        }
      }
      // 3) Fallback
      final fb = (klientId != null) ? 'Klient $klientId' : '—';
      debugPrint('[LOAD|name] fallback "$fb"');
      return fb;
    }

    // 4) Items -> _Entry

    // 4) Items -> _Entry
    final List<_Entry> list = <_Entry>[];
    final Map<int, int> rowIdByKlientTmp = {};
    for (final dynamic it in items) {
      final int rowId = _getRowId(it) ?? 0;
      final int? klientId = _getKlientId(it);
      final int? vehicleId = _getFzgId(it, isMorning);
      final int? order = _getOrder(it, isMorning);
      final String name = _pickDisplay(it, klientId, _nameMapSnapshot);
      // Bemerkung aus dem Ergebnis holen (Map oder DTO)
      String note = '';
      if (it is Map) {
        final raw = it['Bemerkung'] ?? it['bemerkung'];
        if (raw != null) {
          note = raw.toString().trim();
        }
      } else {
        try {
          final dyn = it as dynamic;
          final raw = dyn.bemerkung ?? dyn.note;
          if (raw != null) {
            note = raw.toString().trim();
          }
        } catch (_) {
          // ignore, dann bleibt note = ''
        }
      }

      list.add(
        _Entry(
          rowId,
          klientId,
          name,
          vehicleId,
          order,
          note,
        ),
      );
      // Mapping Klient → Tagesplan-Zeile merken
      if (klientId != null && rowId > 0) {
        rowIdByKlientTmp[klientId] = rowId;
      }
    }

    // 5) Fahrzeuge laden (für Gruppierung)
    if (_vehicles.isEmpty) {
      try {
        await _loadVehiclesIfNeeded();
      } catch (_) {}
    }

    int grpIdx(int? vid) {
      if (vid == null) return 1000000;
      final ix = _vehicles.indexWhere((v) => v.id == vid);
      return (ix < 0) ? 900000 : ix;
    }

    // 6) Sortierung:
    //    - Gruppe
    //    - wenn BEIDE order == null -> row_id
    //    - sonst nach order (null groß) und dann row_id
    list.sort((a, b) {
      final ga = grpIdx(a.vehicleRowId), gb = grpIdx(b.vehicleRowId);
      if (ga != gb) return ga.compareTo(gb);

      final int? ao = a.order;
      final int? bo = b.order;
      if (ao == null && bo == null) {
        return a.rowId.compareTo(b.rowId);
      }

      final av = ao ?? (1 << 30);
      final bv = bo ?? (1 << 30);
      if (av != bv) return av.compareTo(bv);

      return a.rowId.compareTo(b.rowId);
    });

    // 7) Anwenden + doppelte Sicherung, dass _hasChanges false bleibt
    setState(() {
      _entries
        ..clear()
        ..addAll(list);

      _dayRowIdByClientId
        ..clear()
        ..addAll(rowIdByKlientTmp);

      _dayRowIdByClientId
        ..clear()
        ..addAll(rowIdByKlientTmp);

      _hasChanges = false; // Laden darf nicht 'dirty' setzen
    });

    // Falls der Rebuild interne Listener triggert, die _hasChanges wieder auf true setzen würden:
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _hasChanges = false);
    });

    final iso = _selectedDate.toIso8601String().split('T').first;
    debugPrint(
      '[LOAD] done: date=$iso mode=${isMorning ? 'M' : 'A'} entries=${_entries.length}',
    );

    // Probeausgabe
    final int maxS = _entries.length < 3 ? _entries.length : 3;
    for (var i = 0; i < maxS; i++) {
      final e = _entries[i];
      debugPrint(
        '[LOAD] sample[$i] rowId=${e.rowId} name="${e.name}" vId=${e.vehicleRowId} order=${e.order}',
      );
    }
  }

  /// Wenn Abend aktiv ist und KEINE Abend-Reihenfolge vorhanden ist,
  /// automatisch auf Morgen umschalten, neu laden und Nutzer informieren.
  /// Bestehende Sortierlogik bleibt unberührt.
  Future<void> _autoSwitchToMorningIfEveningEmpty() async {
    try {
      // Nur relevant, wenn aktuell Abend aktiv ist
      if (_dayModeIsMorning == true) return;

      // Gibt es irgendeinen zugeordneten Eintrag mit gesetzter order (>0)?
      final bool anyEveningOrder = _entries.any(
        (e) => e.vehicleRowId != null && ((e.order ?? 0) > 0),
      );
      if (anyEveningOrder) return; // Abend hat Werte → nichts tun

      // Fallback: auf Morgen umstellen und erneut laden
      setState(() {
        _dayModeIsMorning = true;
      });

      // Header-Toggle synchronisieren (falls Listener gesetzt)
      try {
        AppBus.onDayModeChanged?.call(true);
      } catch (_) {}

      await _loadDayPlan(); // lädt jetzt die Morgen-Spalte

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Abend-Reihenfolge vorhanden – auf „Morgen“ umgestellt.',
          ),
          duration: Duration(milliseconds: 1600),
        ),
      );
    } catch (_) {
      // bewusst still – kein Crash bei Fallback
    }
  }

  Future<void> _undoChanges() async {
    try {
      // Lädt den Tagesplan für das aktuell ausgewählte Datum und den aktuellen Modus (M/A)
      await _loadDayPlan();
      // _loadDayPlan setzt intern _hasChanges wieder auf false und baut die Liste neu
      debugPrint(
        '[TagesplanTab._undoChanges] Änderungen verworfen und neu geladen.',
      );
    } catch (e, st) {
      debugPrint('[TagesplanTab._undoChanges] FEHLER: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zurücksetzen fehlgeschlagen: $e')),
      );
    }
  }
Future<void> _save() async {
  // Mehrfach-Aufrufe beim Speichern verhindern
  if (_isSavingDayPlan) {
    debugPrint('[TagesplanTab] _save(): bereits im Fortschritt, Abbruch');
    return;
  }

  _isSavingDayPlan = true;
  final sc = AppBus.getSheets?.call();
  if (sc == null) {
    debugPrint('[TagesplanTab._save] SheetsClient==null');
    _isSavingDayPlan = false;
    return;
  }

  final bool isMorning = (_dayModeIsMorning == true);

  // Payload in deinem gewohnten Format (Index = Reihung)
  final payload = <Map<String, dynamic>>[];
  for (var i = 0; i < _entries.length; i++) {
    final e = _entries[i];
    final ordM = isMorning ? (i + 1) : null;
    final ordA = isMorning ? null : (i + 1);

    payload.add({
      'row_id': e.rowId,
      'veh': e.vehicleRowId,
      'ordM': ordM,
      'ordA': ordA,
      // 🔴 NEU: Bemerkung mitgeben – das ist der Text aus deinem Dialog
      'bemerkung': (e.note ?? '').toString(),
    });
  }

  final iso = _selectedDate.toIso8601String().split('T').first;
  debugPrint(
    '[TagesplanTab._save] date=$iso mode=${isMorning ? 'M' : 'A'} entries=${_entries.length} '
    'veh(null)=${_entries.where((e) => e.vehicleRowId == null).length}',
  );
  if (payload.isNotEmpty) {
    final s = payload.first;
    debugPrint(
      '  raw sample: row_id=${s['row_id']} veh=${s['veh']} '
      'ordM=${s['ordM']} ordA=${s['ordA']} note="${s['bemerkung']}"',
    );
  }

  try {
    await sc.saveDayPlan(_selectedDate, payload, morning: isMorning);
    // 2) Reload (zeigt Gruppierung/Sortierung aus DB) — unterdrückt Dirty (siehe _loadDayPlan)
    await _loadDayPlan();

    // 1) Dirty sofort aus
    _setDirty(false);

    debugPrint(
      '[TagesplanTab._save] save OK -> _hasChanges=false -> reload done',
    );
  } catch (e, st) {
    debugPrint('[TagesplanTab] _save(): Fehler: $e\n$st');
  } finally {
    // Sperre immer wieder aufheben
    if (mounted) {
      setState(() {
        _isSavingDayPlan = false;
      });
    } else {
      _isSavingDayPlan = false;
    }
  }
}

  Future<void> _editNoteDialog(_Entry e) async {
    final ctrl = TextEditingController(text: e.note);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bemerkung bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Bemerkung eingeben …',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (res != null) {
      setState(() {
        e.note = res.trim();
        _setDirty(true); // Save-Button aktivieren
      });
    }
  }

  InlineSpan _composeTitle(_Entry e) {
    final hasNote = (e.note.trim().isNotEmpty);
    if (!hasNote) {
      return TextSpan(text: e.name);
    }
    return const TextSpan(); // wird unten überschrieben
  }

  // kompakter Titel inkl. Note (Italics)
  // (separat, um oben die Logik einfach zu halten)
  InlineSpan _composeTitleWithNote(_Entry e) {
    final hasNote = (e.note.trim().isNotEmpty);
    if (!hasNote) return TextSpan(text: e.name);
    return TextSpan(
      children: [
        TextSpan(text: e.name),
        const TextSpan(
          text: ' — ',
          style: TextStyle(fontWeight: FontWeight.w300),
        ),
        TextSpan(
          text: e.note.trim(),
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ==== Datum wählen (mit Save-Nachfrage bei Dirty-State) ====
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDate: _selectedDate,
    );

    if (d == null || _sameDay(d, _selectedDate)) {
      // Kein Wechsel nötig
      return;
    }

    // Falls es ungespeicherte Änderungen gibt: nachfragen
    final decision = await _confirmDateChangeIfDirty();
    if (decision == _DateChangeDecision.cancel) return;

    if (decision == _DateChangeDecision.saveFirst) {
      try {
        await _save(); // setzt _hasChanges=false und lädt danach frisch
      } catch (_) {
        // Falls Speichern scheitert, Abbruch (kein Datum ändern)
        return;
      }
    }
    // Bei discard einfach fortfahren

    setState(() => _selectedDate = d);
    await _loadVehiclesIfNeeded();
    await _loadDayPlan(); // lädt gemäß aktuellem Modus
    await _loadDriverAssignmentsForSelectedDate();
    // NEU: Wenn Abend aktiv und die Abend-Spalte leer ist → automatisch auf Morgen
    await _autoSwitchToMorningIfEveningEmpty();
  }

  // ==== Interaktion ====
  void _toggleVehicle(int id) {
    setState(() => _activeVehicleId = (_activeVehicleId == id) ? null : id);
  }

  void _assignOrClear(_Entry e) {
    setState(() {
      if (_activeVehicleId == null || e.vehicleRowId == _activeVehicleId) {
        e.vehicleRowId = null; // entfernen
      } else {
        e.vehicleRowId = _activeVehicleId; // neu setzen
      }
      _setDirty(true);
    });
  }

  void _setNote(_Entry e, String v) {
    setState(() {
      e.note = v;
      _setDirty(true);
    });
  }

  void _sendToRoute(int vehicleId) {
    // 1) Alle Namen der Einträge für dieses Fahrzeug holen
    final rawNames = _entries
        .where((e) => e.vehicleRowId == vehicleId)
        .map((e) => e.name) // aktuell "Nachname, Vorname"
        .toList();

    // 2) Komma zwischen Nachname und Vorname entfernen,
    //    nur Leerzeichen lassen, Mehrfach-Leerzeichen glattziehen
    final names = rawNames
        .map(
          (n) => n
              .replaceAll(',', ' ') // "Müller, Hans" -> "Müller  Hans"
              .replaceAll(
                RegExp(r'\s+'),
                ' ',
              ) // "Müller  Hans" -> "Müller Hans"
              .trim(),
        )
        .where((n) => n.isNotEmpty)
        .toList();

    // 3) Namen mit Komma trennen – aber JETZT ist nur zwischen den
    //    Personen ein Komma, nicht mehr zwischen Nachname und Vorname
    String text = names.join(', ');

    // 4) Optional: "Zentrale" anhängen
    if (text.trim().isNotEmpty) {
      text = '$text, Zentrale';
    }

    // 5) An Route-Tab übergeben
    AppBus.toRouteWithText?.call(text);
  }

  Color _dividerColorForIndex(int i) {
    if (i < 0 || i >= _entries.length) {
      return Colors.black12;
    }
    final e = _entries[i];
    if (e.vehicleRowId == null) {
      return Colors.black12; // neutraler Trenner für unzugeordnet
    }
    final base = _colorForVehId(e.vehicleRowId!);
    return base.withOpacity(0.45); // etwas kräftiger als Flächenfarbe
  }

    // --- Titel-Builder: Name vollbreit wenn keine Bemerkung, sonst 75/25-Split ---
  Widget _buildRowTitle(_Entry e, BuildContext context) {
    final theme = Theme.of(context);
    final name = e.name.trim().isEmpty ? '–' : e.name.trim();
    final note = e.note.trim();

    // Fahrdienst-Flag aus AppBus: false => Name durchgestrichen
    final bool isFahrdienst = AppBus.isClientFahrdienst(e.klientId);
    final baseNameStyle = theme.textTheme.titleMedium;
    final nameStyle = isFahrdienst
        ? baseNameStyle
        : baseNameStyle?.copyWith(decoration: TextDecoration.lineThrough);

    return LayoutBuilder(
      builder: (ctx, cons) {
        // Wenn keine Bemerkung → Name nimmt komplette Titelbreite
        if (note.isEmpty) {
          return Text(
            name,
            style: nameStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Mit Bemerkung → fester Split Name 75% / Note 25%
        const gap = 8.0;
        final w = cons.maxWidth;
        if (w <= gap + 40) {
          // zur Sicherheit: alles untereinander
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: nameStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );
        }

        final nameW = (w - gap) * 0.75;
        final noteW = (w - gap) * 0.25;

        return Row(
          children: [
            SizedBox(
              width: nameW,
              child: Text(
                name,
                style: nameStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: noteW,
              child: Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  // Reihenfolge immer im einen Feld `order` pflegen – kein Morning/Evening mehr.
  void _setActiveOrder(_Entry e, int ord) {
    e.order = ord;
  }

  @override
  Widget build(BuildContext context) {
    // Fallback: Wenn noch nie erfolgreich geladen wurde UND wir gerade nicht laden
    // und inzwischen ein Supabase-Adapter da ist, dann einmalig nachladen.
    if (!_didInitialLoad && !_isLoading) {
      final sc = AppBus.getSheets?.call();
      if (sc != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_didInitialLoad && !_isLoading) {
            _loadDayPlanSafe();
          }
        });
      }
    }

    final banner = AppBus.buildOfflineBanner?.call();

    // lokales Theme für die Liste (kleinere Schrift)
    final base = Theme.of(context);
    final compactTextTheme = base.textTheme.copyWith(
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
    );

    return Column(
      children: [
        if (banner != null) banner,

        // ---------- Fahrzeug-Chips ----------
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final v = _vehicles[i];
              final active = _activeVehicleId == v.id;
              final baseColor = _colorForVeh(v); // Hex oder Palette
              final vis = _chipVisuals(baseColor, active, context);

              // Fahrer aus Dienstplan für Tooltip
              final driver = _driverNameByVehicleId[v.id];
              debugPrint(
                '[Tooltip] vehId=${v.id} kurz="${v.kurz}" name="${v.name}" driver="$driver"',
              );

              final tooltipText = (driver == null || driver.isEmpty)
                  ? v.name
                  : '${v.name} – Fahrer: $driver';

              return Tooltip(
                message: tooltipText,
                waitDuration: const Duration(milliseconds: 600),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      color: vis.fill,
                      border: Border.all(
                        color: vis.border,
                        width: active ? 3.0 : 2.0,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _toggleVehicle(v.id),
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: vis.border,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(v.kurz, style: vis.labelStyle),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 22,
                          color: vis.border.withOpacity(0.35),
                        ),
                        InkWell(
                          onTap: () => _sendToRoute(v.id),
                          borderRadius: BorderRadius.circular(999),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Icon(Icons.redo, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // ---------- Liste (kompakter) ----------
        Expanded(
          child: _entries.isEmpty
              // LEERER TAG → Long-Press irgendwo auf den Hintergrund öffnet die Auswahl
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: _onAddEntryRequested,
                  child: const Center(
                    child: Text('Keine Einträge für den gewählten Tag'),
                  ),
                )


              // TAG MIT EINTRÄGEN → normale Reorder-Liste
              : Theme(
                  data: base.copyWith(textTheme: compactTextTheme),
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
                    // Desktop: eigene Drag-Handles, Mobile: Flutter-Standard
                    buildDefaultDragHandles:
                        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS),
                    physics: const ClampingScrollPhysics(),
                    itemCount: _entries.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;

                        final moved = _entries.removeAt(oldIndex);
                        _entries.insert(newIndex, moved);

                        // Reihenfolge pro Fahrzeug-Gruppe neu durchnummerieren
                        final vehOrder = _vehicles
                            .map((v) => v.id)
                            .toList(growable: false);

                        for (final vid in vehOrder) {
                          final group = _entries
                              .where((e) => e.vehicleRowId == vid)
                              .toList();
                          for (int i = 0; i < group.length; i++) {
                            group[i].order = i + 1;
                          }
                        }
                        final unassigned = _entries
                            .where((e) => e.vehicleRowId == null)
                            .toList();
                        for (int i = 0; i < unassigned.length; i++) {
                          unassigned[i].order = i + 1;
                        }

                        _setDirty(true);
                      });
                    },
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final vColor = (e.vehicleRowId == null)
                          ? Theme.of(context).colorScheme.outline
                          : _colorForVehId(e.vehicleRowId!);

                      final tile = ListTile(
                        key: ValueKey('entry_${e.rowId}'),
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: 0,
                          vertical: -0.8,
                        ),
                        minVerticalPadding: 4,
                        contentPadding: const EdgeInsets.only(
                          left: 10,
                          right: 4,
                        ),
                        tileColor: _rowFillColor(e, context),
                        leading: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () async {
                            final choice = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Aktion wählen'),
                                content: const Text('Was möchten Sie tun?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop('add'),
                                    child: const Text('Klienten hinzufügen'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop('delete'),
                                    child: const Text('Eintrag löschen'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(null),
                                    child: const Text('Abbrechen'),
                                  ),
                                ],
                              ),
                            );

                            if (choice == 'delete') {
                              await _confirmDeleteEntry(e);
                            } else if (choice == 'add') {
                              await _onAddEntryRequested();
                            }
                          },
                          child: Icon(
                            Icons.directions_car_filled,
                            color: vColor,
                            size: 18,
                          ),
                        ),
                        title: _buildRowTitle(e, context),
                        trailing: IconButton(
                          tooltip: 'Bemerkung bearbeiten',
                          icon: const Icon(Icons.edit),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -2,
                          ),
                          onPressed: () => _editNoteDialog(e),
                        ),
                        onTap: () => _assignOrClear(e),
                      );

                      // Inhalt mit Divider wie bisher
                      final content = (i == 0)
                          ? tile
                          : Column(
                              key: ValueKey('entry_wrap_${e.rowId}'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _dividerColorForIndex(
                                    i - 1,
                                  ).withOpacity(0.85),
                                ),
                                tile,
                              ],
                            );

                      // Desktop: ganze Zeile ist Drag-Handle
                      if (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS) {
                        return ReorderableDragStartListener(
                          key: ValueKey('entry_drag_${e.rowId}'),
                          index: i,
                          child: content,
                        );
                      }

                      // Mobile (Android/iOS): unverändert
                      return content;
                    },
                  ),
                ),



        ),

        // ---------- Rückgängig + Speichern ----------
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _hasChanges ? _undoChanges : null,
                      child: const Text('Rückgängig'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _hasChanges ? _save : null,
                      child: const Text('Speichern'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DienstplanTab extends StatefulWidget {
  const DienstplanTab({Key? key}) : super(key: key);

  @override
  State<DienstplanTab> createState() => _DienstplanTabState();
}

class _DienstplanTabState extends State<DienstplanTab> {
  DateTime _selectedDate = DateTime.now();
  bool _hasChanges = false;
  bool _isLoading = false;
  int? _activeVehicleId; // aktuell gewähltes Fahrzeug (Chip-Leiste)
  int _activeStatus = 0; // 0 = keiner, 1 = Urlaub, 2 = Krank, 3 = Sonstiges

  // Fahrzeugliste (Chips oben – später noch mit echter Logik)
  final List<_Veh> _vehicles = <_Veh>[];

  // Zeilen im Dienstplan: alle Fahrer
  final List<_DienstRow> _rows = <_DienstRow>[];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

    DateTime _mondayOfWeek(DateTime date) {
    return date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
  }

  DateTime _easterSunday(int year) {
    // Berechnung nach Meeus/Jones/Butcher
    final int a = year % 19;
    final int b = year ~/ 100;
    final int c = year % 100;
    final int d = b ~/ 4;
    final int e = b % 4;
    final int f = (b + 8) ~/ 25;
    final int g = (b - f + 1) ~/ 3;
    final int h = (19 * a + b - d - g + 15) % 30;
    final int i = c ~/ 4;
    final int k = c % 4;
    final int l = (32 + 2 * e + 2 * i - h - k) % 7;
    final int m = (a + 11 * h + 22 * l) ~/ 451;
    final int month = (h + l - 7 * m + 114) ~/ 31;
    final int day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  String? _hessenHolidayName(DateTime date) {
    final int year = date.year;
    final int month = date.month;
    final int day = date.day;

    // Feste Feiertage (Hessen)
    if (month == 1 && day == 1) return 'Neujahr';
    if (month == 5 && day == 1) return 'Tag der Arbeit';
    if (month == 10 && day == 3) return 'Tag der Deutschen Einheit';
    if (month == 12 && day == 25) return '1. Weihnachtstag';
    if (month == 12 && day == 26) return '2. Weihnachtstag';

    // Bewegliche Feiertage (ausgehend von Ostersonntag)
    final DateTime easter = _easterSunday(year);
    final DateTime goodFriday = easter.subtract(const Duration(days: 2));
    final DateTime easterMonday = easter.add(const Duration(days: 1));
    final DateTime ascension = easter.add(const Duration(days: 39));
    final DateTime pentecostMonday = easter.add(const Duration(days: 50));
    final DateTime corpusChristi = easter.add(const Duration(days: 60));

    if (_sameDay(date, goodFriday)) return 'Karfreitag';
    if (_sameDay(date, easterMonday)) return 'Ostermontag';
    if (_sameDay(date, ascension)) return 'Christi Himmelfahrt';
    if (_sameDay(date, pentecostMonday)) return 'Pfingstmontag';
    if (_sameDay(date, corpusChristi)) return 'Fronleichnam';

    return null;
  }

  bool _isHessenHoliday(DateTime date) => _hessenHolidayName(date) != null;

  void _applyHolidayStatusDefaults() {
    // Feiertage der aktuellen Woche (Mo–So) automatisch als "Sonstiges" (3)
    // vorbelegen, wenn die Zelle noch leer ist (kein Fahrzeug, kein Status).
    final DateTime mondayOfWeek = _mondayOfWeek(_selectedDate);

    for (final row in _rows) {
      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final DateTime date = mondayOfWeek.add(Duration(days: dayIndex));
        if (!_isHessenHoliday(date)) continue;

        final bool hasVehicle =
            dayIndex < row.fahrzeugRowIds.length &&
            row.fahrzeugRowIds[dayIndex] != null;
        final bool hasStatus =
            dayIndex < row.statusByDay.length &&
            row.statusByDay[dayIndex] != 0;

        if (!hasVehicle && !hasStatus && dayIndex < row.statusByDay.length) {
          // "Sonstiges" (3) als Standard für gesetzliche Feiertage
          row.statusByDay[dayIndex] = 3;
        }
      }
    }
  }

  // --- Init & Laden ---
  @override
  void initState() {
    super.initState();
    debugPrint('[DienstplanTab] initState(): selectedDate=$_selectedDate');

    // Genau wie im Tagesplan: erst nach dem ersten Frame
    // den "sicheren" Loader anstoßen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[DienstplanTab] postFrameCallback -> _loadDienstplanSafe()');
      if (!mounted) return;
      _loadDienstplanSafe();
    });
  }

  // --- Datum-API für TabsWrapper ---
  DateTime get selectedDate => _selectedDate;

  String selectedDateLabelDE() {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_selectedDate.day)}.${two(_selectedDate.month)}.${_selectedDate.year}';
  }

  Future<bool> _confirmWeekChangeIfDirty() async {
    if (_hasChanges != true) return true;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen speichern?'),
        content: const Text(
          'Es liegen ungespeicherte Änderungen vor.\n'
          'Möchtest du vor dem Datumswechsel speichern?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Nicht speichern'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (choice == 'save') {
      try {
        await _save();
        _hasChanges = false;
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
          );
        }
        return false;
      }
    } else if (choice == 'discard') {
      _hasChanges = false;
      return true;
    }

    // cancel oder Dialog geschlossen
    return false;
  }

  Future<void> pickDateFromWrapper() async {
    final now = DateTime.now();
    final initial = _selectedDate;
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Woche auswählen',
      // keine explizite locale → identisch zum Tagesplan
    );

    if (picked == null) return;
    if (_sameDay(picked, _selectedDate)) return;

    final canChange = await _confirmWeekChangeIfDirty();
    if (!canChange) return;

    setState(() {
      _selectedDate = picked;
    });

    // Neue Woche für das gewählte Datum laden
    await _loadWeekPlan();
  }

  Future<void> _exportDienstplanPdf() async {
    try {
      debugPrint('[DienstplanTab] _exportDienstplanPdf(): START');

      // Sicherstellen, dass Supabase bereit ist
      await AppAuth.ensureSignedIn();

      // ------------------------------
      // 1) Monat & Wochenbereich
      // ------------------------------
      final base = _selectedDate;
      final month = base.month;
      final year = base.year;
      final firstOfMonth = DateTime(year, month, 1);
      final lastOfMonth = DateTime(year, month + 1, 0);

      DateTime weekStart(DateTime d) {
        final wd = d.weekday; // 1=Mo..7=So
        return DateTime(
          d.year,
          d.month,
          d.day,
        ).subtract(Duration(days: wd - DateTime.monday));
      }

      String fmt(DateTime d) {
        String two(int n) => n.toString().padLeft(2, '0');
        return '${two(d.day)}.${two(d.month)}.${d.year}';
      }

      String fmtShort(DateTime d) {
        String two(int n) => n.toString().padLeft(2, '0');
        final yy = (d.year % 100).toString().padLeft(2, '0');
        return '${two(d.day)}.${two(d.month)}.$yy';
      }

      String monthNameDe(int m) {
        const names = [
          '',
          'Januar',
          'Februar',
          'März',
          'April',
          'Mai',
          'Juni',
          'Juli',
          'August',
          'September',
          'Oktober',
          'November',
          'Dezember',
        ];
        return (m >= 1 && m <= 12) ? names[m] : '$m';
      }

      final lastWeekStart = weekStart(lastOfMonth);
      final firstWeekStart = lastWeekStart.subtract(
        const Duration(days: 5 * 7),
      );

      final allWeeks = <DateTime>[];
      for (var i = 0; i < 6; i++) {
        allWeeks.add(firstWeekStart.add(Duration(days: 7 * i)));
      }

      // Nur Wochen, die den Monat schneiden
      var weeks = allWeeks.where((ws) {
        final we = ws.add(const Duration(days: 6));
        final before = we.isBefore(firstOfMonth);
        final after = ws.isAfter(lastOfMonth);
        return !(before || after);
      }).toList();

      // Spezialfall: Februar mit exakt 4 Wochen (Mo–So, 28 Tage)
      if (weeks.length == 4 &&
          month == 2 &&
          firstOfMonth.weekday == DateTime.monday &&
          lastOfMonth.day == 28) {
        final extraWeek = lastWeekStart.add(const Duration(days: 7));
        weeks.add(extraWeek);
      }

      if (weeks.isEmpty) {
        weeks.add(weekStart(firstOfMonth));
      }

      // ------------------------------
      // 2) Einrichtung + Logo
      // ------------------------------
      final einrConfig = await SupaAdapter.einrichtungen.readActiveConfig();
      final einrName = einrConfig['name'] ?? '';
      final einrAddress = einrConfig['address'] ?? '';
      final einrRowIdStr = einrConfig['row_id'];
      final int? einrRowId = einrRowIdStr != null
          ? int.tryParse(einrRowIdStr)
          : null;

      final rawLogoUrl = (einrConfig['logo_url'] ?? '').toString().trim();
      pw.MemoryImage? logoImage;

      debugPrint('[DienstplanTab] rawLogoUrl="$rawLogoUrl"');

      if (rawLogoUrl.isNotEmpty &&
          (rawLogoUrl.startsWith('http://') ||
              rawLogoUrl.startsWith('https://'))) {
        try {
          final resp = await http.get(Uri.parse(rawLogoUrl));
          debugPrint('[DienstplanTab] logo HTTP status=${resp.statusCode}');
          if (resp.statusCode == 200) {
            logoImage = pw.MemoryImage(resp.bodyBytes);
            debugPrint(
              '[DienstplanTab] Logo geladen (Bytes=${resp.bodyBytes.length})',
            );
          } else {
            debugPrint('[DienstplanTab] Logo konnte nicht geladen werden.');
          }
        } catch (e) {
          debugPrint('[DienstplanTab] Fehler beim Laden des Logos: $e');
        }
      } else {
        debugPrint(
          '[DienstplanTab] rawLogoUrl leer oder kein http(s) → kein Logo angezeigt',
        );
      }

      // ------------------------------
      // 3) Fahrer-Liste (Dienstplan)
      // ------------------------------
      final mitarbeiterRows = await SupaAdapter.mitarbeiter
          .fetchDriversForDienstplan();
      final fahrer = <int, Map<String, String>>{};
      for (final r in mitarbeiterRows) {
        if (r is! Map<String, dynamic>) continue;
        final id = (r['row_id'] is int)
            ? r['row_id'] as int
            : int.tryParse('${r['row_id'] ?? ''}') ?? 0;
        if (id <= 0) continue;
        final name = '${r['Name'] ?? ''}'.trim();
        final vorname = '${r['Vorname'] ?? ''}'.trim();
        fahrer[id] = {'name': name, 'vorname': vorname};
      }

      // ------------------------------
      // 4) Fahrzeuge + Farben (stabil)
      // ------------------------------
      final fahrzeugRows = await SupaAdapter.fahrzeuge.fetchVehicles(
        einrRowId: einrRowId,
        onlyActive: true,
      );
      final vehColorMap = <int, PdfColor>{};
      final vehLabelMap = <int, String>{};

      for (final v in fahrzeugRows) {
        if (v is! Map<String, dynamic>) continue;
        final id = (v['row_id'] is int)
            ? v['row_id'] as int
            : int.tryParse('${v['row_id'] ?? ''}') ?? 0;
        if (id <= 0) continue;

        final kurz =
            ('${v['Fahrzeug Kurz'] ?? v['fahrzeug_kurz'] ?? v['kurz'] ?? ''}')
                .trim();
        final name =
            ('${v['Bezeichnung'] ?? v['bezeichnung'] ?? v['name'] ?? ''}')
                .trim();
        final label = kurz.isNotEmpty
            ? kurz
            : (name.isNotEmpty ? name : 'FZ $id');

        final rawHex = ('${v['Anzeigenfarbe'] ?? v['anzeigenfarbe'] ?? ''}')
            .trim();
        final hexColor = _vehColorFromHex(rawHex);
        final keyForIndex = kurz.isNotEmpty ? kurz : 'FZ$id';
        final stableIdx = _stableIndexFor(keyForIndex, 12);
        final baseColor = hexColor ?? _vehicleColor(stableIdx);

        vehColorMap[id] = PdfColor.fromInt(baseColor.value);
        vehLabelMap[id] = label;
      }

      // ------------------------------
      // 5) Dienstplan-Daten laden
      // ------------------------------
      final planByMid = <int, Map<DateTime, Map<String, dynamic>>>{};

      int? _asIntOrNull(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse('$v');
      }

      int _asStatus(dynamic v) {
        final i = _asIntOrNull(v) ?? 0;
        if (i < 0) return 0;
        if (i > 3) return 3;
        return i;
      }

      for (final ws in weeks) {
        final rows = await SupaAdapter.dienstplan.fetchWeekPlan(ws);
        for (final r in rows) {
          if (r is! Map<String, dynamic>) continue;
          final mid = _asIntOrNull(r['Mitarbeiter row_ID']);
          if (mid == null || mid <= 0) continue;

          planByMid.putIfAbsent(mid, () => {});
          planByMid[mid]![ws] = r;
        }
      }

      // ------------------------------
      // 6) Farben & Styles
      // ------------------------------
      PdfColor pdfColorFromFlutter(Color c) => PdfColor.fromInt(c.value);

      PdfColor pdfLightFromFlutter(Color c, double strength) {
        final s = strength.clamp(0.0, 1.0);
        double mix(double channel) {
          return 1.0 - (1.0 - channel) * s;
        }

        final r = mix(c.red / 255.0);
        final g = mix(c.green / 255.0);
        final b = mix(c.blue / 255.0);
        return PdfColor(r, g, b);
      }

      // Statusfarben – sichtbar, aber nicht zu kräftig
      final pdfU = pdfLightFromFlutter(_Config.uksUrlaubColor, 0.50);
      final pdfK = pdfLightFromFlutter(_Config.uksKrankColor, 0.50);
      final pdfS = pdfLightFromFlutter(_Config.uksSonstigesColor, 0.50);

      PdfColor? statusColor(int status) {
        switch (status) {
          case 1:
            return pdfU;
          case 2:
            return pdfK;
          case 3:
            return pdfS;
          default:
            return null;
        }
      }

      const dayVehCols = [
        'Fahrzeuge row_id Mo',
        'Fahrzeuge row_id Di',
        'Fahrzeuge row_id Mi',
        'Fahrzeuge row_id Do',
        'Fahrzeuge row_id Fr',
        'Fahrzeuge row_id Sa',
        'Fahrzeuge row_id So',
      ];
      const dayStatusCols = [
        'Status_Mo',
        'Status_Di',
        'Status_Mi',
        'Status_Do',
        'Status_Fr',
        'Status_Sa',
        'Status_So',
      ];

      const double boxHeight = 24;
      const double logoBoxHeight = 50;

      final doc = pw.Document();

      final headerStyle = pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
      );
      final subHeaderStyle = pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      );
      final normalStyle = const pw.TextStyle(fontSize: 9);
      final nameStyle = const pw.TextStyle(fontSize: 11);
      final tinyStyle = const pw.TextStyle(fontSize: 7);

      final weekDateStyle = pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

      // ------------------------------
      // 7) Legende
      // ------------------------------
      pw.Widget buildLegend() {
        final vehLegend = vehLabelMap.entries
            .map(
              (e) => pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(
                    width: 10,
                    height: 10,
                    color: vehColorMap[e.key],
                  ),
                  pw.SizedBox(width: 3),
                  pw.Text(e.value, style: tinyStyle),
                ],
              ),
            )
            .toList();

        final statusLegend = [
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 10, height: 10, color: pdfU),
              pw.SizedBox(width: 3),
              pw.Text('U = Urlaub', style: tinyStyle),
            ],
          ),
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 10, height: 10, color: pdfK),
              pw.SizedBox(width: 3),
              pw.Text('K = Krank', style: tinyStyle),
            ],
          ),
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 10, height: 10, color: pdfS),
              pw.SizedBox(width: 3),
              pw.Text('S = Sonstiges', style: tinyStyle),
            ],
          ),
        ];

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Fahrzeuge:', style: subHeaderStyle),
            pw.Wrap(spacing: 8, runSpacing: 4, children: vehLegend),
            pw.SizedBox(height: 6),
            pw.Text('Status:', style: subHeaderStyle),
            pw.Wrap(spacing: 8, runSpacing: 4, children: statusLegend),
          ],
        );
      }

      // ------------------------------
      // 8) Tabellen-Header (Mitarbeiter + Wochen)
      // ------------------------------
      pw.TableRow buildHeaderRow() {
        final cells = <pw.Widget>[];

        // Spalte 0: Mitarbeiter
        cells.add(
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text('Mitarbeiter', style: subHeaderStyle),
          ),
        );

        // Spalten: Wochen (Bereich + Tageszahlen)
        for (final ws in weeks) {
          final we = ws.add(const Duration(days: 6));

          final dayNums = <pw.Widget>[];
          for (var i = 0; i < 7; i++) {
            final d = ws.add(Duration(days: i));
            dayNums.add(
              pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    d.day.toString(),
                    style: tinyStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ),
            );
          }

          final rangeText = '${fmtShort(ws)} - ${fmtShort(we)}';

          cells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2,
                horizontal: 1,
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    rangeText,
                    style: weekDateStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: dayNums,
                  ),
                ],
              ),
            ),
          );
        }

        return pw.TableRow(children: cells);
      }

      // ------------------------------
      // 9) Datenzeile pro Mitarbeiter
      // ------------------------------
      pw.TableRow buildDataRow(int mid, Map<String, String> data) {
        final name = data['name'] ?? '';
        final vorname = data['vorname'] ?? '';
        final displayName = [
          name,
          vorname,
        ].where((s) => s.trim().isNotEmpty).join(', ');

        final rowCells = <pw.Widget>[];

        // Spalte 0: Name – leicht nach unten versetzt
        rowCells.add(
          pw.Container(
            height: boxHeight,
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: pw.Text(displayName, style: nameStyle),
          ),
        );

        // Spalten: Wochen – 7 Tageskästchen pro Woche
        for (final ws in weeks) {
          final weekRow = planByMid[mid]?[ws];

          final colors = List<PdfColor?>.filled(7, null);
          final labels = List<String?>.filled(7, null);
          final keys = List<String>.filled(7, '');

          if (weekRow != null) {
            for (var i = 0; i < 7; i++) {
              final status = _asStatus(weekRow[dayStatusCols[i]]);
              final stColor = statusColor(status);

              if (stColor != null) {
                colors[i] = stColor;
                String txt;
                switch (status) {
                  case 1:
                    txt = 'U';
                    break;
                  case 2:
                    txt = 'K';
                    break;
                  case 3:
                  default:
                    txt = 'S';
                    break;
                }
                labels[i] = txt;
                keys[i] = 'S$status';
              } else {
                final vehId = _asIntOrNull(weekRow[dayVehCols[i]]);
                if (vehId != null && vehId > 0) {
                  colors[i] = vehColorMap[vehId];
                  final labelFull = (vehLabelMap[vehId] ?? '').trim();
                  final shortLabel = labelFull.length <= 2
                      ? labelFull
                      : labelFull.substring(0, 2);
                  labels[i] = shortLabel;
                  keys[i] = 'V$vehId';
                } else {
                  colors[i] = null;
                  labels[i] = null;
                  keys[i] = '';
                }
              }
            }
          }

          final dayBoxes = <pw.Widget>[];
          String prevKey = '';
          for (var i = 0; i < 7; i++) {
            final key = keys[i];
            final bg = colors[i];
            String? text;

            if (key.isNotEmpty && key != prevKey) {
              text = labels[i];
            }
            prevKey = key;

            dayBoxes.add(
              pw.Expanded(
                child: pw.Container(
                  height: boxHeight,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.3, color: PdfColors.grey),
                    color: bg,
                  ),
                  child: (text != null && text.isNotEmpty)
                      ? pw.Text(text, style: tinyStyle)
                      : null,
                ),
              ),
            );
          }

          rowCells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 2,
                horizontal: 1,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: dayBoxes,
              ),
            ),
          );
        }

        return pw.TableRow(children: rowCells);
      }

      // Fahrer sortieren
      final fahrerList = fahrer.entries.toList()
        ..sort((a, b) {
          final na = a.value['name'] ?? '';
          final nb = b.value['name'] ?? '';
          return na.compareTo(nb);
        });

      // ------------------------------
      // 10) Seite aufbauen – EIN gemeinsamer Kopf + Footer
      // ------------------------------
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(16),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Seite ${context.pageNumber} / ${context.pagesCount}',
              style: tinyStyle,
            ),
          ),
          build: (ctx) {
            final tableRows = <pw.TableRow>[];
            tableRows.add(buildHeaderRow());
            for (final entry in fahrerList) {
              tableRows.add(buildDataRow(entry.key, entry.value));
            }

            return [
              // EIN Kopf-Widget: Logo links, Überschrift mittig, Legende rechts
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // links: Logo + Name + Adresse (oben)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null) ...[
                        pw.Container(
                          width: 80,
                          height: logoBoxHeight,
                          alignment: pw.Alignment.topLeft,
                          child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
                        ),
                        pw.SizedBox(height: 2),
                      ],
                      pw.Text(
                        einrName.isEmpty ? 'Fahrdienst Tagespflege' : einrName,
                        style: normalStyle,
                      ),
                      if (einrAddress.isNotEmpty) ...[
                        pw.Text(einrAddress, style: normalStyle),
                      ],
                    ],
                  ),

                  pw.Spacer(),

                  // Mitte: Überschriften zentriert, oben beginnend
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Dienstplan ${monthNameDe(month)} $year',
                        style: headerStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        'Fahrdienst Tagespflege - Stand ${fmt(DateTime.now())}',
                        style: normalStyle,
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),

                  pw.Spacer(),

                  // rechts: Legende – mit Top-Abstand nach unten geschoben (20)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [pw.SizedBox(height: 20), buildLegend()],
                  ),
                ],
              ),

              // Abstand vor der ersten Tabellen-Linie (20, wie bei dir)
              pw.SizedBox(height: 20),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey, width: 0.4),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  for (var i = 1; i <= weeks.length; i++)
                    i: const pw.FlexColumnWidth(3),
                },
                children: tableRows,
              ),
            ];
          },
        ),
      );

      // ------------------------------
      // 11) PDF-Vorschau öffnen
      // ------------------------------
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            appBar: AppBar(title: const Text('Dienstplan PDF')),
            body: PdfPreview(
              build: (format) async => doc.save(),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName:
                  'dienstplan_${year.toString().padLeft(4, '0')}_${month.toString().padLeft(2, '0')}.pdf',
            ),
          ),
        ),
      );

      debugPrint('[DienstplanTab] _exportDienstplanPdf(): ENDE OK');
    } catch (e, st) {
      debugPrint('[DienstplanTab] _exportDienstplanPdf(): FEHLER $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Erstellen des PDF: $e')),
      );
    }
  }

  Widget _buildDriverTitleRow(_DienstRow row, BuildContext context) {
    final theme = Theme.of(context);

    final hasVorname = row.vorname.trim().isNotEmpty;
    final rawName = hasVorname ? '${row.name}, ${row.vorname}' : row.name;
    final name = rawName.trim().isEmpty ? '–' : rawName.trim();
    final note = row.bemerkung.trim();

    return LayoutBuilder(
      builder: (ctx, cons) {
        // Keine Bemerkung → Name über die ganze Breite
        if (note.isEmpty) {
          return Text(
            name,
            style: theme.textTheme.titleMedium, // wie Tagesplan
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Mit Bemerkung → 75 % Name / 25 % Bemerkung (wie _buildRowTitle)
        const gap = 8.0;
        final w = cons.maxWidth;
        final nameW = (w - gap) * 0.75;
        final noteW = (w - gap) * 0.25;

        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            SizedBox(
              width: nameW,
              child: Text(
                name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: noteW,
              child: Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editRemarkDialog(_DienstRow row) async {
    final ctrl = TextEditingController(text: row.bemerkung);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bemerkung bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Bemerkung eingeben …',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (res != null) {
      setState(() {
        row.bemerkung = res.trim();
        _setDirty(); // Save-Button aktiv
      });
    }
  }

  Color _vehicleColorForId(int? vehRowId, BuildContext ctx) {
    if (vehRowId == null) {
      return Colors.transparent;
    }

    _Veh? veh;
    for (final v in _vehicles) {
      if (v.id == vehRowId) {
        veh = v;
        break;
      }
    }

    if (veh != null) {
      return _colorForVeh(veh, ctx); // ← KORREKT: 2 Parameter!
    }

    return _vehicleColor(vehRowId % 12);
  }

  Future<void> _editBemerkung(_DienstRow row) async {
    final ctrl = TextEditingController(text: row.bemerkung);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bemerkung bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Bemerkung für diese Woche',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (res != null) {
      setState(() {
        row.bemerkung = res.trim();
        _setDirty();
      });
    }
  }

  Widget _buildDienstplanSubtitle(BuildContext context, _DienstRow row) {
    final theme = Theme.of(context);

    // dezente senkrechte Divider (du hast aktuell ~0.25)
    final Color lightDivider = theme.dividerColor.withOpacity(0.25);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(7, (index) {
        final vehId = index < row.fahrzeugRowIds.length
            ? row.fahrzeugRowIds[index]
            : null;

        final int status = index < row.statusByDay.length
            ? row.statusByDay[index]
            : 0;

        final col = _vehicleColorForId(vehId, context);
        final bool hasVehicle = vehId != null;
        final bool hasStatus = status != 0;

        Color cellColor;

        if (hasStatus) {
          // Status hat Vorrang vor Fahrzeug – nur Farbe, kein Text
          switch (status) {
            case 1: // Urlaub
              cellColor = _Config.uksUrlaubColor.withOpacity(0.25);
              break;
            case 2: // Krank
              cellColor = _Config.uksKrankColor.withOpacity(0.25);
              break;
            case 3: // Sonstiges
              cellColor = _Config.uksSonstigesColor.withOpacity(0.25);
              break;
            default:
              cellColor = theme.colorScheme.onSurface.withOpacity(0.08);
          }
        } else if (hasVehicle) {
          // Fahrzeug-Farbe wie bisher
          cellColor = col.withOpacity(0.25);
        } else {
          cellColor = Colors.transparent;
        }

        return Expanded(
          child: InkWell(
            onTap: () => _onTapDienstDay(row, index),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cellColor,
                border: Border(
                  // linker Rand nur vor Montag
                  left: index == 0
                      ? BorderSide(color: lightDivider, width: 0.5)
                      : BorderSide.none,
                  // rechter Rand bei jedem Tag → auch nach Sonntag ein Strich
                  right: BorderSide(color: lightDivider, width: 0.5),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Future<void> changeDateByFromWrapper(int delta) async {
    // delta kommt vom Swipe (links/rechts), wir interpretieren das als Wochenwechsel
    if (delta == 0) return;

    final newDate = _selectedDate.add(Duration(days: 7 * delta));

    final canChange = await _confirmWeekChangeIfDirty();
    if (!canChange) return;

    setState(() {
      _selectedDate = newDate;
    });

    await _loadWeekPlan();
  }

  Future<void> goToTodayFromWrapper() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (_sameDay(todayDate, _selectedDate)) return;

    final canChange = await _confirmWeekChangeIfDirty();
    if (!canChange) return;

    setState(() {
      _selectedDate = todayDate;
    });

    await _loadWeekPlan();
  }

  Future<void> _loadDrivers() async {
    debugPrint('[DienstplanTab] _loadDrivers(): START');
    setState(() {
      _isLoading = true;
    });

    try {
      final list = await SupaAdapter.mitarbeiter.fetchDriversForDienstplan();

      debugPrint(
        '[DienstplanTab] _loadDrivers(): fetchDriversForDienstplan lieferte ${list.length} Einträge',
      );

      final newRows = <_DienstRow>[];
      var index = 0;
      for (final m in list) {
        index++;
        final rawId = m['row_id'];
        final id = (rawId is num)
            ? rawId.toInt()
            : int.tryParse('${rawId ?? 0}') ?? 0;
        if (id <= 0) {
          debugPrint(
            '[DienstplanTab] Eintrag $index übersprungen, weil id<=0 (rawId=$rawId)',
          );
          continue;
        }

        final name = ('${m['Name'] ?? ''}').trim();
        final vorname = ('${m['Vorname'] ?? ''}').trim();

        debugPrint(
          '[DienstplanTab] Eintrag $index -> id=$id, name="$name", vorname="$vorname"',
        );

        newRows.add(
          _DienstRow(
            mitarbeiterId: id,
            name: name,
            vorname: vorname,
            // bemerkung und fahrzeugRowIds laufen über Defaultwerte im Konstruktor
          ),
        );
      }

      if (!mounted) {
        debugPrint('[DienstplanTab] _loadDrivers(): nicht mehr mounted, abort');
        return;
      }

      setState(() {
        _rows
          ..clear()
          ..addAll(newRows);
        _hasChanges = false;
      });

      debugPrint(
        '[DienstplanTab] _loadDrivers(): fertig, _rows.length=${_rows.length}',
      );
    } catch (e, st) {
      debugPrint('[DienstplanTab] Fehler beim Laden der Mitarbeiter: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dienstplan: Mitarbeiter konnten nicht geladen werden.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint('[DienstplanTab] _loadDrivers(): END');
    }
  }

  Future<void> _loadDienstplanSafe({int retry = 0}) async {
    if (!mounted) return;

    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      if (retry < 10) {
        debugPrint(
          '[LOADSAFE-Dienst] SheetsClient=null, retry ${retry + 1}/10 in 250ms',
        );
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _loadDienstplanSafe(retry: retry + 1);
        });
      } else {
        debugPrint('[LOADSAFE-Dienst] Abbruch: SheetsClient blieb null.');
      }
      return;
    }

    // Jetzt ist Supabase / SupaSheetsAdapter initialisiert:
    // 1) Mitarbeiter laden
    // 2) Fahrzeuge laden (für die Chips oben)
    // 3) Dienstplan-Woche aus der Tabelle "Dienstplan" holen
    await _loadDrivers();
    await _loadVehiclesIfNeeded();
    await _loadWeekPlan();
  }

  Future<void> _loadVehiclesIfNeeded() async {
    if (_vehicles.isNotEmpty) {
      debugPrint(
        '[Dienstplan] _loadVehiclesIfNeeded(): Fahrzeuge bereits geladen (${_vehicles.length})',
      );
      return;
    }

    final sc = AppBus.getSheets?.call();
    if (sc == null) {
      debugPrint('[Dienstplan] getSheets() lieferte null');
      return;
    }
    debugPrint('[Dienstplan] getSheets() -> ${sc.runtimeType}');

    List items = const [];
    try {
      if ((sc as dynamic).fetchVehicles is Function) {
        debugPrint('[Dienstplan] rufe sc.fetchVehicles(onlyActive:true) auf …');
        items = await sc.fetchVehicles(onlyActive: true);
      } else {
        debugPrint('[Dienstplan] sc.fetchVehicles existiert NICHT!');
      }
    } catch (e, st) {
      debugPrint('[Dienstplan] fetchVehicles Fehler: $e\n$st');
      items = const [];
    }

    final list = <_Veh>[];
    final colorMap = <int, Color>{};

    int _asIndex(dynamic v, {required int fallback, int mod = 12}) {
      if (v is int) return v % mod;
      final p = int.tryParse('${v ?? ''}');
      return (p == null) ? (fallback % mod) : (p % mod);
    }

    for (final v in items) {
      try {
        if (v is Map<String, dynamic>) {
          final id = int.tryParse('${v['row_id'] ?? v['rowId'] ?? 0}') ?? 0;
          if (id <= 0) continue;

          final kurz =
              ('${v['Fahrzeug Kurz'] ?? v['fahrzeug_kurz'] ?? v['kurz'] ?? ''}')
                  .trim();
          final name = ('${v['bezeichnung'] ?? v['name'] ?? ''}').trim();

          // Anzeigenfarbe wie im Tagesplan
          final hex =
              '${v['Anzeigenfarbe'] ?? v['anzeigenfarbe'] ?? v['anzeige_farbe'] ?? ''}'
                  .trim();
          final hexColor = _vehColorFromHex(hex);

          // Index aus Datensatz oder stabil aus Kurz/ID – identisch zum Tagesplan
          final stableIdx = _stableIndexFor(
            kurz.isNotEmpty ? kurz : 'FZ$id',
            12,
          );
          final colorIndex = _asIndex(
            v['colorIndex'],
            fallback: stableIdx,
            mod: 12,
          );

          // Label: bevorzugt Kurzbezeichnung, sonst Name, sonst FZ+ID
          final label = kurz.isNotEmpty
              ? kurz
              : (name.isNotEmpty ? name : 'FZ $id');

          list.add(_Veh(id, label, name, colorIndex));

          if (hexColor != null) {
            colorMap[id] = hexColor;
            debugPrint(
              '[Dienstplan] HexColor für ID=$id gesetzt: 0x${hexColor.value.toRadixString(16).padLeft(8, '0')}',
            );
          }
        } else {
          // Objekt-Zweig (falls der Adapter Klassen-Instanzen liefert)
          final dynamic dv = v;
          final id = (dv.rowId as int?) ?? 0;
          if (id <= 0) continue;

          final kurz = '${dv.kurz ?? ''}'.trim();
          final name = '${dv.bezeichnung ?? dv.name ?? ''}'.trim();

          String? rawHex;
          try {
            rawHex = (dv.anzeigenfarbe as String?)?.trim();
          } catch (_) {}
          final hexColor = _vehColorFromHex(rawHex);

          final stableIdx = _stableIndexFor(
            kurz.isNotEmpty ? kurz : 'FZ$id',
            12,
          );
          final colorIndex = _asIndex(
            dv.colorIndex,
            fallback: stableIdx,
            mod: 12,
          );

          final label = kurz.isNotEmpty
              ? kurz
              : (name.isNotEmpty ? name : 'FZ $id');

          list.add(_Veh(id, label, name, colorIndex));

          if (hexColor != null) {
            colorMap[id] = hexColor;
            debugPrint(
              '[Dienstplan] HexColor (Objekt) für ID=$id gesetzt: 0x${hexColor.value.toRadixString(16).padLeft(8, '0')}',
            );
          }
        }
      } catch (e, st) {
        debugPrint('[Dienstplan] skip kaputte Zeile: $e\n$st');
      }
    }

    list.sort((a, b) => a.kurz.toLowerCase().compareTo(b.kurz.toLowerCase()));

    setState(() {
      _vehicles
        ..clear()
        ..addAll(list);
      _vehColorById
        ..clear()
        ..addAll(colorMap); // Hex-Farben wie im Tagesplan übernehmen

      // Aktives Fahrzeug ggf. zurücksetzen, wenn es nicht mehr existiert
      if (_activeVehicleId != null &&
          !_vehicles.any((x) => x.id == _activeVehicleId)) {
        _activeVehicleId = null;
      }
    });

    debugPrint(
      '[Dienstplan] Fahrzeuge geladen: ${_vehicles.length}, HexColors: ${_vehColorById.length}',
    );
  }
  Future<void> _loadWeekPlan() async {
    debugPrint(
      '[DienstplanTab] _loadWeekPlan(): START für Datum $_selectedDate',
    );

    try {
      // Vorbereitend: alle bisherigen Zuordnungen zurücksetzen,
      // damit keine Reste aus vorherigen Wochen/Updates stehen bleiben.
      for (final row in _rows) {
        row.bemerkung = '';
        row.fahrzeugRowIds.fillRange(0, row.fahrzeugRowIds.length, null);
        row.statusByDay.fillRange(0, row.statusByDay.length, 0);
      }

      // Holt bereits "Wochenbeginn" (Montag) intern im Adapter
      final rows = await SupaAdapter.dienstplan.fetchWeekPlan(_selectedDate);

      debugPrint(
        '[DienstplanTab] _loadWeekPlan(): Supabase lieferte ${rows.length} Zeilen',
      );

      if (!mounted) return;

      // Map: Mitarbeiter row_ID -> Datensatz aus der Dienstplan-Tabelle
      final byMid = <int, Map<String, dynamic>>{};
      for (final r in rows) {
        final rawMid = r['Mitarbeiter row_ID'];
        int? mid;
        if (rawMid is int) {
          mid = rawMid;
        } else if (rawMid is num) {
          mid = rawMid.toInt();
        } else {
          mid = int.tryParse('${rawMid ?? ''}');
        }
        if (mid == null || mid <= 0) continue;
        byMid[mid] = r;
      }

      setState(() {
        int _asId(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v;
          if (v is num) return v.toInt();
          return int.tryParse('$v') ?? 0;
        }

        int _asStatus(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v.clamp(0, 3);
          if (v is num) return v.toInt().clamp(0, 3);
          final parsed = int.tryParse('$v') ?? 0;
          return parsed.clamp(0, 3);
        }

        for (final row in _rows) {
          final r = byMid[row.mitarbeiterId];
          if (r == null) {
            // Keine Zeile in der Tabelle → alles frei
            row.bemerkung = '';
            row.fahrzeugRowIds.fillRange(0, row.fahrzeugRowIds.length, null);
            row.statusByDay.fillRange(0, row.statusByDay.length, 0);
            continue;
          }

          row.bemerkung = '${r['Bemerkung'] ?? ''}'.trim();

          // Fahrzeuge
          final colsVeh = <String>[
            'Fahrzeuge row_id Mo',
            'Fahrzeuge row_id Di',
            'Fahrzeuge row_id Mi',
            'Fahrzeuge row_id Do',
            'Fahrzeuge row_id Fr',
            'Fahrzeuge row_id Sa',
            'Fahrzeuge row_id So',
          ];

          for (var i = 0;
              i < colsVeh.length && i < row.fahrzeugRowIds.length;
              i++) {
            final id = _asId(r[colsVeh[i]]);
            row.fahrzeugRowIds[i] = id > 0 ? id : null;
          }

          // Status
          final colsStatus = <String>[
            'Status_Mo',
            'Status_Di',
            'Status_Mi',
            'Status_Do',
            'Status_Fr',
            'Status_Sa',
            'Status_So',
          ];

          for (var i = 0;
              i < colsStatus.length && i < row.statusByDay.length;
              i++) {
            row.statusByDay[i] = _asStatus(r[colsStatus[i]]);
          }
        }

        // Nach Laden aus der DB: zunächst Feiertags-Status vorbelegen
        _applyHolidayStatusDefaults();

        // Nach Laden aus der DB: nichts ist "dirty"
        _hasChanges = false;
      });

      debugPrint('[DienstplanTab] _loadWeekPlan(): fertig');
    } catch (e, st) {
      debugPrint('[DienstplanTab] Fehler in _loadWeekPlan(): $e\n$st');
    }
  }



  // --- Datumsauswahl per Dialog ---

  Future<void> _pickDate() async {
    final initial = _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && !_sameDay(picked, _selectedDate)) {
      setState(() {
        _selectedDate = picked;
      });
      // Auch hier: kein Reload der Mitarbeiter nötig.
    }
  }

  // --- Refresh-API für TabsWrapper ---
  Future<void> refreshFromWrapper() async {
    debugPrint('[DienstplanTab] refreshFromWrapper() → _loadDienstplanSafe()');
    await _loadDienstplanSafe();
  }

  // --- Druck-API für TabsWrapper ---
  Future<void> printFromWrapper() async {
    await _exportDienstplanPdf();
  }

  // --- Speichern / Rückgängig ---
  Future<void> _save() async {
    debugPrint('[DienstplanTab] _save(): START');

    try {
      final entries = <Map<String, dynamic>>[];

      for (final row in _rows) {
        final mid = row.mitarbeiterId;
        if (mid <= 0) continue;

        final remark = row.bemerkung.trim();

        int? mo, di, mi, doo, fr, sa, so;
        final len = row.fahrzeugRowIds.length;

        if (len > 0) mo = row.fahrzeugRowIds[0];
        if (len > 1) di = row.fahrzeugRowIds[1];
        if (len > 2) mi = row.fahrzeugRowIds[2];
        if (len > 3) doo = row.fahrzeugRowIds[3];
        if (len > 4) fr = row.fahrzeugRowIds[4];
        if (len > 5) sa = row.fahrzeugRowIds[5];
        if (len > 6) so = row.fahrzeugRowIds[6];

        int statusMo = row.statusByDay[0];
        int statusDi = row.statusByDay[1];
        int statusMi = row.statusByDay[2];
        int statusDo = row.statusByDay[3];
        int statusFr = row.statusByDay[4];
        int statusSa = row.statusByDay[5];
        int statusSo = row.statusByDay[6];

        statusMo = statusMo.clamp(0, 3);
        statusDi = statusDi.clamp(0, 3);
        statusMi = statusMi.clamp(0, 3);
        statusDo = statusDo.clamp(0, 3);
        statusFr = statusFr.clamp(0, 3);
        statusSa = statusSa.clamp(0, 3);
        statusSo = statusSo.clamp(0, 3);

        final allVehiclesNull =
            mo == null &&
            di == null &&
            mi == null &&
            doo == null &&
            fr == null &&
            sa == null &&
            so == null;

        final allStatusZero =
            statusMo == 0 &&
            statusDi == 0 &&
            statusMi == 0 &&
            statusDo == 0 &&
            statusFr == 0 &&
            statusSa == 0 &&
            statusSo == 0;

        final allNull = allVehiclesNull && allStatusZero && remark.isEmpty;

        // Vollständig leere Zeilen werden nicht gespeichert
        if (allNull) continue;

        entries.add(<String, dynamic>{
          'Mitarbeiter row_ID': mid,
          'Fahrzeuge row_id Mo': mo,
          'Fahrzeuge row_id Di': di,
          'Fahrzeuge row_id Mi': mi,
          'Fahrzeuge row_id Do': doo,
          'Fahrzeuge row_id Fr': fr,
          'Fahrzeuge row_id Sa': sa,
          'Fahrzeuge row_id So': so,
          'Status_Mo': statusMo,
          'Status_Di': statusDi,
          'Status_Mi': statusMi,
          'Status_Do': statusDo,
          'Status_Fr': statusFr,
          'Status_Sa': statusSa,
          'Status_So': statusSo,
          'Bemerkung': remark,
        });
      }

      await SupaAdapter.dienstplan.saveWeekPlan(_selectedDate, entries);

      // Nach dem Speichern den Stand noch einmal aus der DB laden,
      // damit "Rückgängig" auf diesen Zustand zurückspringt.
      await _loadWeekPlan();

      debugPrint('[DienstplanTab] _save(): OK – entries=${entries.length}');
    } catch (e, st) {
      debugPrint('[DienstplanTab] _save(): Fehler: $e\n$st');
      // Wichtig: _hasChanges NICHT zurücksetzen, wenn Speichern schief geht.

      final raw = '$e';
      final lower = raw.toLowerCase();

      final isPermissionProblem =
          lower.contains('permission denied') ||
          lower.contains('not authorized') ||
          lower.contains('row-level security') ||
          lower.contains('row level security') ||
          lower.contains('rls') ||
          lower.contains(
            '42501',
          ) || // klassischer Postgres-Code für „insufficient privilege“
          lower.contains('nosuchmethoderror'); // Fallback: aktuelles Verhalten

      final String userMsg = isPermissionProblem
          ? 'Sie haben keine Berechtigung, den Dienstplan zu ändern.'
          : 'Fehler beim Speichern des Dienstplans.\nDetails: $raw';

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMsg)));
    }
  }

  Future<void> _undoChanges() async {
    debugPrint('[DienstplanTab] _undoChanges(): START → _loadWeekPlan()');
    await _loadWeekPlan();
  }

  void _setDirty() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  void _onTapDienstDay(_DienstRow row, int dayIndex) {
    if (dayIndex < 0 || dayIndex >= row.fahrzeugRowIds.length) {
      return;
    }

    setState(() {
      final bool vehicleMode = _activeVehicleId != null;
      final bool statusMode = _activeStatus != 0;

      // Hilfsfunktion: hat die Zeile überhaupt Einträge?
      bool hasAny() {
        final hasVeh = row.fahrzeugRowIds.any((id) => id != null);
        final hasStatus = row.statusByDay.any((s) => s != 0);
        final hasRemark = row.bemerkung.trim().isNotEmpty;
        return hasVeh || hasStatus || hasRemark;
      }

      // Fall 1: Kein Fahrzeug + kein Status ausgewählt -> Tag leeren
      if (!vehicleMode && !statusMode) {
        bool changed = false;
        if (row.fahrzeugRowIds[dayIndex] != null) {
          row.fahrzeugRowIds[dayIndex] = null;
          changed = true;
        }
        if (row.statusByDay[dayIndex] != 0) {
          row.statusByDay[dayIndex] = 0;
          changed = true;
        }
        if (changed) {
          _setDirty();
        }
        return;
      }

      // Ab hier: entweder Fahrzeug-Modus ODER Status-Modus aktiv
      if (vehicleMode) {
        final int vehId = _activeVehicleId!;
        final bool any = hasAny();

        // Fall 2: Zeile bisher komplett leer → Standardfall Mo–Fr mit Fahrzeug
        if (!any) {
          final int len = row.fahrzeugRowIds.length;
          for (int i = 0; i < 5 && i < len; i++) {
            row.fahrzeugRowIds[i] = vehId;
            row.statusByDay[i] = 0; // Status löschen
          }
          _setDirty();
          return;
        }

        // Fall 3: Einzeltag setzen → Status an diesem Tag löschen
        if (row.fahrzeugRowIds[dayIndex] == vehId &&
            row.statusByDay[dayIndex] == 0) {
          // schon gleicher Zustand
          return;
        }

        row.fahrzeugRowIds[dayIndex] = vehId;
        row.statusByDay[dayIndex] = 0;
        _setDirty();
        return;
      }

      if (statusMode) {
        final int st = _activeStatus;
        final bool any = hasAny();

        // Fall 2: Zeile bisher komplett leer → Standardfall Mo–Fr mit Status
        if (!any) {
          final int len = row.statusByDay.length;
          for (int i = 0; i < 5 && i < len; i++) {
            row.statusByDay[i] = st;
            row.fahrzeugRowIds[i] = null; // Fahrzeug löschen
          }
          _setDirty();
          return;
        }

        // Fall 3: Einzeltag setzen → Fahrzeug an diesem Tag löschen
        if (row.statusByDay[dayIndex] == st &&
            row.fahrzeugRowIds[dayIndex] == null) {
          // schon gleicher Zustand
          return;
        }

        row.statusByDay[dayIndex] = st;
        row.fahrzeugRowIds[dayIndex] = null;
        _setDirty();
        return;
      }
    });
  }

  // --- Chip-Optik für Fahrzeuge (wie Tagesplan, aber aktuell nur vorbereitet) ---

  _ChipVisuals _chipVisuals(Color base, bool active, BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    final border = base;
    final fill = active
        ? (dark ? base.withOpacity(0.35) : base.withOpacity(0.20))
        : Colors.transparent;
    final labelStyle = TextStyle(
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
    );
    return _ChipVisuals(border: border, fill: fill, labelStyle: labelStyle);
  }

  Widget _buildStatusChip(BuildContext context, int status, String label) {
    final theme = Theme.of(context);
    final bool active = _activeStatus == status;

    // Pastellfarben für die drei Status
    Color base;
    switch (status) {
      case 1: // Urlaub
        base = _Config.uksUrlaubColor;
        break;
      case 2: // Krank
        base = _Config.uksKrankColor;
        break;
      case 3: // Sonstiges
        base = _Config.uksSonstigesColor;
        break;
      default:
        base = theme.colorScheme.outline.withOpacity(0.4);
    }

    final Color borderColor = base.withOpacity(0.9);
    final Color fillColor = active ? base.withOpacity(0.8) : Colors.transparent;

    final TextStyle textStyle =
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle();

    return Expanded(
      child: Container(
        height: 32,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            setState(() {
              if (active) {
                // Status wieder ausschalten
                _activeStatus = 0;
              } else {
                // Status auswählen, Fahrzeugmodus deaktivieren
                _activeStatus = status;
                _activeVehicleId = null;
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor, width: active ? 2.0 : 1.0),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(label, style: textStyle),
          ),
        ),
      ),
    );
  }

  // Map: Fahrzeug-ID -> endgültige Farbe (aus Hex oder Palette)
  final Map<int, Color> _vehColorById = {};

  // 12er-Palette (Material-ähnliche Töne) – identisch zum Tagesplan
  Color _vehicleColor(int idx) {
    const palette = <Color>[
      Color(0xFF5C6BC0), // Indigo 400
      Color(0xFF26A69A), // Teal 400
      Color(0xFF7E57C2), // Deep Purple 400
      Color(0xFF66BB6A), // Green 400
      Color(0xFFFFB74D), // Orange 300
      Color(0xFF546E7A), // Blue Grey 600
      Color(0xFF42A5F5), // Blue 400
      Color(0xFFAB47BC), // Purple 400
      Color(0xFFEC407A), // Pink 400
      Color(0xFF26C6DA), // Cyan 400
      Color(0xFFFF7043), // Deep Orange 400
      Color(0xFF9CCC65), // Light Green 400
    ];
    return palette[idx % palette.length];
  }

  // Stabiler Index aus String-Key (wie im Tagesplan)
  int _stableIndexFor(String key, int mod) {
    int h = 0;
    for (int i = 0; i < key.length; i++) {
      h = 0x1fffffff & (h * 33 + key.codeUnitAt(i));
    }
    return (h & 0x7fffffff) % mod;
  }

  // Hex -> Color (unterstützt "#RRGGBB" und "RRGGBB")
  Color? _vehColorFromHex(String? hex) {
    if (hex == null) return null;
    var s = hex.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  // Farbe für Fahrzeug-Objekt – identisch zur Logik im Tagesplan:
  Color _colorForVeh(_Veh v, BuildContext ctx) {
    final mapped = _vehColorById[v.id];
    if (mapped != null) return mapped;
    return _vehicleColor(v.colorIndex);
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[DienstplanTab] build(): rows=${_rows.length}, isLoading=$_isLoading',
    );
    // Offline-Banner wie im Tagesplan
    final banner = AppBus.buildOfflineBanner?.call();

    final base = Theme.of(context);
    final compactTextTheme = base.textTheme.copyWith(
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
    );

    return Column(
      children: [
        if (banner != null) banner,

        // ---------- Fahrzeug-Chips ----------
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: _vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final v = _vehicles[i];
              final active = _activeVehicleId == v.id;

              final baseColor = _colorForVeh(v, context);
              final vis = _chipVisuals(baseColor, active, context);

              return Tooltip(
                message: v.name,
                waitDuration: const Duration(milliseconds: 600),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      color: vis.fill,
                      border: Border.all(
                        color: vis.border,
                        width: active ? 3.0 : 2.0,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (active) {
                            // Fahrzeug ausschalten
                            _activeVehicleId = null;
                          } else {
                            // Fahrzeug-Modus aktivieren → Status-Modus zurücksetzen
                            _activeVehicleId = v.id;
                            _activeStatus = 0;
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: vis.border,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(v.kurz, style: vis.labelStyle),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 4),

        // ---------- UKS-Schalter (Urlaub / Krank / Sonstiges) ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusChip(context, 1, 'Urlaub'),
              const SizedBox(width: 8),
              _buildStatusChip(context, 2, 'Krank'),
              const SizedBox(width: 8),
              _buildStatusChip(context, 3, 'Sonstiges'),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ---------- Wochenkopf: Mo–So + Kalendertage ----------
        Container(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          padding: const EdgeInsets.only(
            left: 10.0,
            right: 10.0,
            top: 4.0,
            bottom: 4.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zeile 1: Wochentage (Mo–So)
              Row(
                children: [
                  // linker Icon-Bereich – gleiche Breite wie in _buildDriverRow
                  const SizedBox(width: 36),

                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final DateTime mondayOfWeek =
                            _mondayOfWeek(_selectedDate);
                        final DateTime date =
                            mondayOfWeek.add(Duration(days: index));
                        final bool isHoliday = _isHessenHoliday(date);
                        const labels = <String>[
                          'Mo',
                          'Di',
                          'Mi',
                          'Do',
                          'Fr',
                          'Sa',
                          'So',
                        ];
                        return _DayHeaderCell(
                          labels[index],
                          isHoliday: isHoliday,
                          isWeekend: index >= 5, // Sa/So dunkelgrau
                        );
                      }),
                    ),
                  ),

                  // rechter Icon-Bereich – gleiche Breite wie in _buildDriverRow
                  const SizedBox(width: 36),
                ],
              ),

              const SizedBox(height: 2),

              // Zeile 2: Kalendertage (17, 18, 19, …)
              Row(
                children: [
                  const SizedBox(width: 36),

                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final DateTime mondayOfWeek =
                            _mondayOfWeek(_selectedDate);
                        final DateTime date =
                            mondayOfWeek.add(Duration(days: index));
                        final bool isHoliday = _isHessenHoliday(date);
                        return _DayHeaderCell(
                          '${date.day}',
                          isHoliday: isHoliday,
                          isWeekend: index >= 5, // Sa/So dunkelgrau
                        );
                      }),
                    ),
                  ),

                  const SizedBox(width: 36),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),
        const Divider(height: 1),

        // ---------- Liste mit Mitarbeitern ----------
        Expanded(
          child: Theme(
            data: base.copyWith(textTheme: compactTextTheme),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _rows.length,
                    itemBuilder: (ctx, index) {
                      final row = _rows[index];
                      return _buildDriverRow(ctx, row);
                    },
                    separatorBuilder: (ctx, index) => Divider(
                      height: 1,
                      thickness: 0.8,
                      color: Theme.of(ctx).dividerColor,
                    ),
                  ),
          ),
        ),

        // ---------- Buttons Speichern / Rückgängig ----------
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _hasChanges ? _undoChanges : null,
                    child: const Text('Rückgängig'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _hasChanges ? _save : null,
                    child: const Text('Speichern'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverRow(BuildContext context, _DienstRow row) {
    final theme = Theme.of(context);
    final headerColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.04);

    // gleiche Breite vorne und hinten
    const double iconAreaWidth = 36;

    return Container(
      // unterer Divider wie bisher
      decoration: BoxDecoration(
        border: Border(bottom: Divider.createBorderSide(context, width: 0.8)),
      ),
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // --------------------------------------
          // LINKER ICON-BEREICH – jetzt 100 % bündig!
          // --------------------------------------
          Container(
            width: iconAreaWidth,
            height: 40,
            color: headerColor,
            alignment: Alignment.center,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Woche für diesen Mitarbeiter löschen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              onPressed: () {
                setState(() {
                  // Fahrzeuge löschen
                  row.fahrzeugRowIds.fillRange(
                    0,
                    row.fahrzeugRowIds.length,
                    null,
                  );
                  // NEU: auch Status löschen (alles wieder normal)
                  row.statusByDay.fillRange(0, row.statusByDay.length, 0);
                  // Bemerkung löschen
                  row.bemerkung = '';
                  _setDirty();
                });
              },
            ),
          ),

          const SizedBox(width: 4),

          // --------------------------------------
          // MITTLERER BEREICH – Kästchen + Name
          // --------------------------------------
          Expanded(
            child: SizedBox(
              height: 40,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Name / Vorname / Bemerkungs-Layout
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildDriverTitleRow(row, context),
                    ),
                  ),
                  // FARBKÄSTCHEN (Mo–So) – hier werden Fahrzeug- oder UKS-Farben gemalt
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildDienstplanSubtitle(context, row),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 4),

          // --------------------------------------
          // RECHTER ICON-BEREICH – exakt gleich wie links
          // --------------------------------------
          Container(
            width: iconAreaWidth,
            height: 40,
            color: headerColor,
            alignment: Alignment.center,
            child: IconButton(
              tooltip: 'Bemerkung bearbeiten',
              icon: const Icon(Icons.edit),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              onPressed: () => _editRemarkDialog(row),
            ),
          ),
        ],
      ),
    );
  }
}

class _DienstRow {
  final int mitarbeiterId;
  final String name;
  final String vorname;
  String bemerkung;

  // Index 0..6 => Mo..So, Fahrzeug-Zuordnung
  final List<int?> fahrzeugRowIds;

  // Index 0..6 => Mo..So, 0=normal, 1=U, 2=K, 3=S
  final List<int> statusByDay;

  _DienstRow({
    required this.mitarbeiterId,
    required this.name,
    required this.vorname,
    String? bemerkung,
    List<int?>? fahrzeugRowIds,
    List<int>? statusByDay,
  }) : bemerkung = bemerkung ?? '',
       fahrzeugRowIds =
           fahrzeugRowIds ?? List<int?>.filled(7, null, growable: false),
       statusByDay = statusByDay ?? List<int>.filled(7, 0, growable: false);
}
class _DayHeaderCell extends StatelessWidget {
  final String label;
  final bool isHoliday;
  final bool isWeekend;

  const _DayHeaderCell(
    this.label, {
    Key? key,
    this.isHoliday = false,
    this.isWeekend = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Basisstil: keine feste Farbe → nimmt automatisch hell/dunkel aus dem Theme
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    // Feiertag → rot
    TextStyle? style = isHoliday
        ? baseStyle?.copyWith(
            color: theme.colorScheme.error,
          )
        : baseStyle;

    // Wochenende (Sa, So) → dunkelgrau, aber nur wenn NICHT Feiertag
    if (!isHoliday && isWeekend) {
      style = style?.copyWith(
        color: Colors.grey.shade600,
      );
    }

    return Expanded(
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: style,
        ),
      ),
    );
  }
}

// --- Kleine Hilfsmodelle ---
class _Veh {
  final int id;
  final String kurz;
  final String name;
  final int colorIndex;
  _Veh(this.id, this.kurz, this.name, this.colorIndex);
}

class _Entry {
  final int rowId;
  final int? klientId;
  final String name;
  int? vehicleRowId;
  int? order; // <- dieses Feld muss existieren
  String note;

  _Entry(
    this.rowId,
    this.klientId,
    this.name,
    this.vehicleRowId,
    this.order,
    this.note,
  );
}

// ---------------------------------------------------------------------------
// Google Sheets Client (inkl. Config-Tab mit 3 Telefonnummern)
// ---------------------------------------------------------------------------
class SheetsClient {
  gs.SheetsApi? _api;
  Map<String, int> _headerIndex = {};
  final Map<String, int> _rowIndexByRowId = {};

  // Config-Labels (lower-case)
  static const _cfgColNameLower = 'name der einrichtung';
  static const _cfgColAddrLower = 'adresse der einrichtung';
  static const _cfgColPhone1Lower = 'telefonnummer der einrichtung 1';
  static const _cfgColPhone2Lower = 'telefonnummer der einrichtung 2';
  static const _cfgColPhone3Lower = 'telefonnummer der einrichtung 3';
  // Mappt Fahrzeug-row_id -> Dropdown-Anzeigetext "id – <kurz> <bezeichnung>"

  Future<void> _ensure() async {
    if (_api != null) return;
    final jsonStr = await rootBundle.loadString(_Config.serviceKeyAsset);
    final creds = auth.ServiceAccountCredentials.fromJson(json.decode(jsonStr));
    final client = await auth.clientViaServiceAccount(creds, [
      gs.SheetsApi.spreadsheetsScope,
    ]);
    _api = gs.SheetsApi(client);
  }

  Future<({List<Person> people, DateTime fetchedAt})> fetchAll() async {
    await _ensure();
    final range = '${_Config.sheetName}!A:ZZ';
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      range,
    );
    final values = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (values.isEmpty) {
      return (people: <Person>[], fetchedAt: DateTime.now());
    }
    final headers = values.first.map((h) => h.trim().toLowerCase()).toList();
    _headerIndex = {for (int i = 0; i < headers.length; i++) headers[i]: i};

    final people = <Person>[];
    _rowIndexByRowId.clear();

    for (int r = 1; r < values.length; r++) {
      final row = values[r];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final p = _personFromSheetRow(_headerIndex, row);
      if ((p.name + p.vorname + p.adresse).trim().isEmpty) continue;
      people.add(p);

      final rowIdx = r + 1;
      final rid = (p.rowId ?? '').trim();
      if (rid.isNotEmpty) _rowIndexByRowId[rid] = rowIdx;
      final nr = (p.nr ?? '').trim();
      if (nr.isNotEmpty) _rowIndexByRowId['nr:$nr'] = rowIdx;
    }
    return (people: people, fetchedAt: DateTime.now());
  }

  String _colLetterFromIndex(int idx) {
    int n = idx;
    String s = '';
    while (true) {
      final rem = n % 26;
      s = String.fromCharCode(65 + rem) + s;
      n = (n ~/ 26) - 1;
      if (n < 0) break;
    }
    return s;
  }

  String _colLetterFor(String headerKey) {
    final idx = _headerIndex[headerKey];
    if (idx == null) return '';
    return _colLetterFromIndex(idx);
  }

  Future<void> _ensureHeadersLoaded() async {
    if (_api == null) await _ensure();
    if (_headerIndex.isNotEmpty) return;
    final range = '${_Config.sheetName}!A:ZZ';
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      range,
    );
    final values = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (values.isEmpty) return;
    final headers = values.first.map((h) => h.trim().toLowerCase()).toList();
    _headerIndex = {for (int i = 0; i < headers.length; i++) headers[i]: i};
  }

  Future<void> _ensureRowIdColumn() async {
    await _ensureHeadersLoaded();
    if (_headerIndex.containsKey('row_id')) return;
    final nextIdx = _headerIndex.values.isEmpty
        ? 0
        : (_headerIndex.values.reduce((a, b) => a > b ? a : b) + 1);
    final colLetter = _colLetterFromIndex(nextIdx);
    final headerRange = '${_Config.sheetName}!${colLetter}1:${colLetter}1';
    final vr = gs.ValueRange(
      values: [
        ['row_id'],
      ],
    );
    await _api!.spreadsheets.values.update(
      vr,
      _Config.spreadsheetId,
      headerRange,
      valueInputOption: 'RAW',
    );
    _headerIndex['row_id'] = nextIdx;
  }

  Future<int?> _findLastDataRow() async {
    await _ensure();
    final range = '${_Config.sheetName}!A:ZZ';
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      range,
    );
    final values = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (values.isEmpty || values.length == 1) return null;
    for (int i = values.length - 1; i >= 1; i--) {
      final row = values[i];
      final hasAny = row.any((c) => c.trim().isNotEmpty);
      if (hasAny) return i + 1;
    }
    return 1;
  }

  String _nowLocal() {
    final dt = DateTime.now().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _newRowId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ---- Append Person
  Future<String> appendPerson(
    Person p, {
    required String editorName,
    required String deviceName,
    required String deviceId,
  }) async {
    await _ensure();
    await _ensureHeadersLoaded();
    await _ensureRowIdColumn();

    // Defaults absichern (keine leeren Felder schreiben)
    if (p.aktiv.trim().isEmpty) p.aktiv = 'Ja';
    if (p.fahrdienst.trim().isEmpty) p.fahrdienst = 'Ja';
    if (p.rs.trim().isEmpty) p.rs = 'Nein';

    // Nur numerische Einrichtungs-ID zulassen (nie Namen schreiben)
    String _normEinrId(String s) {
      final v = s.trim();
      return RegExp(r'^\d+$').hasMatch(v) ? v : '';
    }

    final newRowId = (p.rowId?.trim().isNotEmpty == true)
        ? p.rowId!.trim()
        : _newRowId();
    final nowIso = _nowLocal();
    final last = await _findLastDataRow();
    final expectedRow = (last ?? 1) + 1;

    final width = _headerIndex.values.isEmpty
        ? 23
        : (_headerIndex.values.reduce((a, b) => a > b ? a : b) + 1);
    final row = List<String>.filled(width, '');

    String v(String? s) => (s ?? '').trim();
    void setVal(String key, String value) {
      final idx = _headerIndex[key];
      if (idx == null) return;
      if (idx >= 0 && idx < row.length) row[idx] = value.trim();
    }

    // Einrichtungs-ID schreiben (nur numerisch)
    final _rawEinr = p.einrichtungenRowId.trim();
    final _normEinr = _normEinrId(_rawEinr);
    debugPrint(
      '[appendPerson] einrichtungenRowId raw="$_rawEinr" -> norm="$_normEinr"',
    );
    if (_headerIndex.containsKey('einrichtungen row_id')) {
      setVal('einrichtungen row_id', _normEinr);
    }

    setVal('nr.', v(p.nr));
    setVal('name', v(p.name));
    setVal('vorname', v(p.vorname));
    setVal('adresse', v(p.adresse));
    setVal('ortsteil', v(p.ortsteil));
    setVal('telefon', v(p.telefon));
    setVal('angehörige', v(p.angehoerige));
    setVal('angehörige tel.', v(p.angeTel));
    setVal('betreuer', v(p.betreuer));
    setVal('betreuer tel.', v(p.betreuerTel));
    setVal('rs', v(p.rs));
    setVal('besonderheiten', v(p.besonderheiten));
    setVal('infos zur wohnsituation', v(p.infosWohn));
    setVal('tagespflege (wochentage)', v(p.tagespflege));
    setVal('hilfe bei', v(p.hilfeBei));
    setVal('schlüssel', v(p.schluessel));
    setVal('klingelzeichen', v(p.klingel));
    setVal('sonstige informationen', v(p.sonstiges));
    setVal('aktiv', v(p.aktiv));
    setVal('fahrdienst', v(p.fahrdienst));
    setVal('row_id', newRowId);
    setVal('updated_at', nowIso);
    setVal('last_editor', editorName);
    setVal('last_editor_device', deviceName);
    setVal('last_editor_device_id', deviceId);
    if (_headerIndex.containsKey('last_editor_device_name')) {
      setVal('last_editor_device_name', v(p.lastEditorDeviceName));
    }

    final range = '${_Config.sheetName}!A1';
    final req = gs.ValueRange(values: [row]);

    final resp = await _api!.spreadsheets.values.append(
      req,
      _Config.spreadsheetId,
      range,
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
      includeValuesInResponse: true,
    );

    int? targetRow;
    final updatedRange = resp.updates?.updatedRange;
    if (updatedRange != null) {
      final m = RegExp(r'.*![A-Z]+(\d+):').firstMatch(updatedRange);
      if (m != null) targetRow = int.tryParse(m.group(1)!);
    }
    targetRow ??= expectedRow;

    // row_id explizit sichern (falls nötig)
    if (_headerIndex.containsKey('row_id')) {
      final col = _colLetterFor('row_id');
      if (col.isNotEmpty && targetRow != null) {
        final vr = gs.ValueRange(
          range: '${_Config.sheetName}!$col$targetRow:$col$targetRow',
          values: [
            [newRowId],
          ],
        );
        await _api!.spreadsheets.values.batchUpdate(
          gs.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: [vr]),
          _Config.spreadsheetId,
        );
      }
    }
    return newRowId;
  }

  // ---- Update Person
  Future<void> updatePerson(
    Person p, {
    required String editorName,
    required String deviceName,
    required String deviceId,
  }) async {
    await _ensure();
    await _ensureHeadersLoaded();

    String rowKey = (p.rowId ?? '').trim();
    int? rowIndex = rowKey.isNotEmpty ? _rowIndexByRowId[rowKey] : null;

    if (rowIndex == null) {
      final nr = (p.nr ?? '').trim();
      if (nr.isNotEmpty) {
        rowIndex = _rowIndexByRowId['nr:$nr'];
      }
      if (rowIndex == null) {
        await fetchAll();
        rowIndex = rowKey.isNotEmpty
            ? _rowIndexByRowId[rowKey]
            : ((p.nr ?? '').trim().isNotEmpty
                  ? _rowIndexByRowId['nr:${(p.nr ?? '').trim()}']
                  : null);
        if (rowIndex == null) {
          throw Exception('Datensatz nicht gefunden (weder row_id noch Nr.).');
        }
      }
    }

    // Defaults absichern
    if (p.aktiv.trim().isEmpty) p.aktiv = 'Ja';
    if (p.fahrdienst.trim().isEmpty) p.fahrdienst = 'Ja';
    if (p.rs.trim().isEmpty) p.rs = 'Nein';

    // Nur numerische Einrichtungs-ID zulassen (nie Namen schreiben)
    String _normEinrId(String? s) {
      final v = (s ?? '').trim();
      return RegExp(r'^\d+$').hasMatch(v) ? v : '';
    }

    final updates = <gs.ValueRange>[];
    void setCell(String headerKey, String value) {
      final col = _colLetterFor(headerKey);
      if (col.isEmpty) return;
      final range = '${_Config.sheetName}!$col$rowIndex:$col$rowIndex';
      updates.add(
        gs.ValueRange(
          range: range,
          values: [
            [value],
          ],
        ),
      );
    }

    String v(String s) => s.trim();

    // Einrichtungs-ID schreiben (nur numerisch)
    final _rawEinr = p.einrichtungenRowId.trim();
    final _normEinr = _normEinrId(_rawEinr);
    debugPrint(
      '[updatePerson] einrichtungenRowId raw="$_rawEinr" -> norm="$_normEinr"',
    );
    if (_headerIndex.containsKey('einrichtungen row_id')) {
      setCell('einrichtungen row_id', _normEinr);
    }

    setCell('nr.', v(p.nr ?? ''));
    setCell('name', v(p.name));
    setCell('vorname', v(p.vorname));
    setCell('adresse', v(p.adresse));
    setCell('ortsteil', v(p.ortsteil));
    setCell('telefon', v(p.telefon));
    setCell('angehörige', v(p.angehoerige));
    setCell('angehörige tel.', v(p.angeTel));
    setCell('betreuer', v(p.betreuer));
    setCell('betreuer tel.', v(p.betreuerTel));
    setCell('rs', v(p.rs));
    setCell('besonderheiten', v(p.besonderheiten));
    setCell('infos zur wohnsituation', v(p.infosWohn));
    setCell('tagespflege (wochentage)', v(p.tagespflege));
    setCell('hilfe bei', v(p.hilfeBei));
    setCell('schlüssel', v(p.schluessel));
    setCell('klingelzeichen', v(p.klingel));
    setCell('sonstige informationen', v(p.sonstiges));
    setCell('aktiv', v(p.aktiv));
    setCell('fahrdienst', v(p.fahrdienst));

    if (_headerIndex.containsKey('last_editor_device_name')) {
      setCell('last_editor_device_name', v(p.lastEditorDeviceName ?? ''));
    }

    final nowIso = _nowLocal();
    setCell('updated_at', nowIso);
    setCell('last_editor', editorName);
    setCell('last_editor_device', deviceName);
    setCell('last_editor_device_id', deviceId);

    if (updates.isEmpty) return;
    await _api!.spreadsheets.values.batchUpdate(
      gs.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: updates),
      _Config.spreadsheetId,
    );
  }

  // ---- Sheet-ID by Title
  Future<int?> _sheetIdByTitle(String title) async {
    await _ensure();
    final ss = await _api!.spreadsheets.get(_Config.spreadsheetId);
    for (final s in ss.sheets ?? <gs.Sheet>[]) {
      if ((s.properties?.title ?? '').trim().toLowerCase() ==
          title.trim().toLowerCase()) {
        return s.properties?.sheetId;
      }
    }
    return null;
  }

  // ---- Delete by row_id (robust, holt gid dynamisch)
  Future<void> deleteByRowId(String rowId) async {
    await _ensure();
    if (!_rowIndexByRowId.containsKey(rowId)) {
      await fetchAll();
    }
    final rowIndex = _rowIndexByRowId[rowId];
    if (rowIndex == null) throw Exception('row_id $rowId nicht gefunden');

    final sheetId = await _sheetIdByTitle(_Config.sheetName);
    if (sheetId == null)
      throw Exception('Tab "${_Config.sheetName}" nicht gefunden');

    final req = gs.BatchUpdateSpreadsheetRequest(
      requests: [
        gs.Request(
          deleteDimension: gs.DeleteDimensionRequest(
            range: gs.DimensionRange(
              sheetId: sheetId,
              dimension: 'ROWS',
              startIndex: rowIndex - 1,
              endIndex: rowIndex,
            ),
          ),
        ),
      ],
    );
    await _api!.spreadsheets.batchUpdate(req, _Config.spreadsheetId);
  }

  // ----------------------- Config-Tab: Existenz & Header -----------------------
  Future<void> _ensureConfigSheetExists() async {
    await _ensure();
    final ss = await _api!.spreadsheets.get(_Config.spreadsheetId);
    final has = (ss.sheets ?? []).any(
      (s) =>
          (s.properties?.title ?? '').trim().toLowerCase() ==
          _Config.configSheetTitle.toLowerCase(),
    );
    if (has) return;

    await _api!.spreadsheets.batchUpdate(
      gs.BatchUpdateSpreadsheetRequest(
        requests: [
          gs.Request(
            addSheet: gs.AddSheetRequest(
              properties: gs.SheetProperties(title: _Config.configSheetTitle),
            ),
          ),
        ],
      ),
      _Config.spreadsheetId,
    );

    final header = [
      'Name der Einrichtung',
      'Adresse der Einrichtung',
      'Telefonnummer der Einrichtung 1',
      'Telefonnummer der Einrichtung 2',
      'Telefonnummer der Einrichtung 3',
    ];
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: [header]),
      _Config.spreadsheetId,
      '${_Config.configSheetTitle}!A1:E1',
      valueInputOption: 'RAW',
    );
  }

  /// Liest Config-Werte (Name, Adresse, 3x Telefon) aus Tab "Config".
  Future<
    ({String name, String address, String phone1, String phone2, String phone3})
  >
  readConfig() async {
    await _ensure();
    await _ensureConfigSheetExists();
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      '${_Config.configSheetTitle}!A:Z',
    );
    final values = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (values.isEmpty) {
      await _ensureConfigSheetExists();
      return (name: '', address: '', phone1: '', phone2: '', phone3: '');
    }

    final headers = values.first.map((h) => h.trim().toLowerCase()).toList();
    final colIndex = <String, int>{
      for (int i = 0; i < headers.length; i++) headers[i]: i,
    };

    String valAt(int? idx) {
      if (idx == null) return '';
      if (values.length < 2) return '';
      final row = values[1];
      if (idx < 0 || idx >= row.length) return '';
      return row[idx].toString().trim();
    }

    final idxName = colIndex[_cfgColNameLower];
    final idxAddr = colIndex[_cfgColAddrLower];
    final idxP1 = colIndex[_cfgColPhone1Lower];
    final idxP2 = colIndex[_cfgColPhone2Lower];
    final idxP3 = colIndex[_cfgColPhone3Lower];

    final name = valAt(idxName);
    final addr = valAt(idxAddr);
    final p1 = valAt(idxP1);
    final p2 = valAt(idxP2);
    final p3 = valAt(idxP3);

    return (name: name, address: addr, phone1: p1, phone2: p2, phone3: p3);
  }

  /// Schreibt/überschreibt die Werte in Zeile 2. Legt Tab/Headers an, falls nötig.
  Future<void> writeConfig({
    required String name,
    required String address,
    required String phone1,
    required String phone2,
    required String phone3,
  }) async {
    await _ensure();
    await _ensureConfigSheetExists();

    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      '${_Config.configSheetTitle}!A:Z',
    );
    final values = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();

    List<String> headers;
    if (values.isEmpty) {
      headers = [
        'Name der Einrichtung',
        'Adresse der Einrichtung',
        'Telefonnummer der Einrichtung 1',
        'Telefonnummer der Einrichtung 2',
        'Telefonnummer der Einrichtung 3',
      ];
    } else {
      headers = values.first.map((h) => h.toString()).toList();
    }

    final hdrLower = headers.map((h) => h.trim().toLowerCase()).toList();
    bool headerChanged = false;

    int ensureHeader(String title, String lowerKey) {
      int idx = hdrLower.indexOf(lowerKey);
      if (idx == -1) {
        headers.add(title);
        hdrLower.add(lowerKey);
        idx = headers.length - 1;
        headerChanged = true;
      }
      return idx;
    }

    final idxName = ensureHeader('Name der Einrichtung', _cfgColNameLower);
    final idxAddr = ensureHeader('Adresse der Einrichtung', _cfgColAddrLower);
    final idxP1 = ensureHeader(
      'Telefonnummer der Einrichtung 1',
      _cfgColPhone1Lower,
    );
    final idxP2 = ensureHeader(
      'Telefonnummer der Einrichtung 2',
      _cfgColPhone2Lower,
    );
    final idxP3 = ensureHeader(
      'Telefonnummer der Einrichtung 3',
      _cfgColPhone3Lower,
    );

    if (values.isEmpty || headerChanged) {
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: [headers]),
        _Config.spreadsheetId,
        '${_Config.configSheetTitle}!A1:${_colLetterFromIndex(headers.length - 1)}1',
        valueInputOption: 'RAW',
      );
    }

    final row = List<String>.filled(headers.length, '');
    row[idxName] = name;
    row[idxAddr] = address;
    row[idxP1] = phone1;
    row[idxP2] = phone2;
    row[idxP3] = phone3;

    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: [row]),
      _Config.spreadsheetId,
      '${_Config.configSheetTitle}!A2:${_colLetterFromIndex(headers.length - 1)}2',
      valueInputOption: 'RAW',
    );
  }

  /// Liest die Mitarbeiterliste aus dem Tab "Mitarbeiter" (Spalten: Name, Vorname)
  /// und liefert eine alphabetisch (Nachname) sortierte Liste im Format "Nachname, Vorname".
  Future<List<String>> fetchEmployeeNameList() async {
    await _ensure();
    try {
      final vr = await _api!.spreadsheets.values.get(
        _Config.spreadsheetId,
        'Mitarbeiter!A:Z',
      );
      final rows = (vr.values ?? [])
          .map((r) => r.map((e) => e.toString()).toList())
          .toList();
      if (rows.isEmpty) return <String>[];

      final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();
      int idxName = headers.indexOf('name');
      int idxVorname = headers.indexOf('vorname');
      if (idxName < 0) idxName = headers.indexOf('nachname');
      if (idxVorname < 0) idxVorname = headers.indexOf('first name');

      final list = <String>[];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        String n = (idxName >= 0 && idxName < row.length)
            ? row[idxName].trim()
            : '';
        String v = (idxVorname >= 0 && idxVorname < row.length)
            ? row[idxVorname].trim()
            : '';
        final s = [n, v].where((e) => e.isNotEmpty).join(', ');
        if (s.isNotEmpty) list.add(s);
      }
      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return list;
    } catch (_) {
      return <String>[];
    }
  }

  // ================== KLIENTEN-NAMENSMAP ==================
  Future<Map<int, String>> fetchClientNameMap() async {
    await AppAuth.ensureSignedIn();
    final cli = Supa.client;

    // Einrichtungs-ID aus SharedPreferences laden
    int? einrId;
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString('einrichtung_row_id')?.trim();
      if (s != null && s.isNotEmpty) einrId = int.tryParse(s);
    } catch (_) {}

    // Grundabfrage aufbauen: FILTER zuerst
    var q = cli.from('Klienten').select('row_id, Name, Vorname');

    q = q.eq('Aktiv', true);
    if (einrId != null) {
      q = q.eq('Einrichtungen row_id', einrId);
    }

    // Jetzt erst sortieren (order() wandelt in Transform-Builder)
    final result = await q.order('Name', ascending: true);
    final data = result as List<dynamic>? ?? [];

    // Map bauen: row_id -> "Name Vorname"
    final map = <int, String>{};
    for (final row in data) {
      final rid = int.tryParse('${row['row_id']}') ?? 0;
      if (rid <= 0) continue;
      final n = '${row['Name'] ?? ''}'.trim();
      final v = '${row['Vorname'] ?? ''}'.trim();
      final full = [n, v].where((e) => e.isNotEmpty).join(' ').trim();
      if (full.isNotEmpty) map[rid] = full;
    }
    return map;
  }

  // ================== FAHRZEUGE LESEN ==================
  Future<List<dynamic>> fetchVehicles({bool onlyActive = true}) async {
    await _ensure();

    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      'Fahrzeuge!A:Z',
    );

    final rows = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (rows.isEmpty) return <dynamic>[];

    // Header in lowercase für robuste Indexsuche
    final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();

    // Spalten-Indizes tolerant ermitteln
    int idx(String name) => headers.indexOf(name);

    int idxRowId = idx('row_id');
    int idxKurz = idx('fahrzeug kurz');
    if (idxKurz < 0) idxKurz = idx('kurz');

    int idxBez = idx('bezeichnung');
    if (idxBez < 0) idxBez = idx('anzeige'); // dein Sheet nutzt "Anzeige"
    if (idxBez < 0) idxBez = idx('name');

    int idxAktiv = idx('aktiv');

    // NEU: Anzeigenfarbe (genau so wie im Sheet)
    int idxAnzf = idx('anzeigenfarbe');

    // kleiner Helper für sicheren Zugriff
    String sAt(List<String> r, int i) =>
        (i >= 0 && i < r.length) ? r[i].trim() : '';

    // stabiler Hash → Index 0..(mod-1)
    int stableIndexFor(String key, int mod) {
      int h = 0;
      for (final c in key.codeUnits) {
        h = 0x1fffffff & (h * 33 + c);
      }
      return (h & 0x7fffffff) % mod;
    }

    final list = <Map<String, dynamic>>[];

    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];

      final rid = int.tryParse(sAt(r, idxRowId)) ?? 0;
      if (rid <= 0) continue;

      final kurz = sAt(r, idxKurz);
      final bez = sAt(r, idxBez);

      final aktivStr = sAt(r, idxAktiv).toLowerCase();
      final aktiv = (aktivStr == 'ja' || aktivStr == 'true' || aktivStr == '1');

      if (onlyActive && !aktiv) continue;

      // Anzeigenfarbe aus Sheet (Roh-String, z. B. "#5C6BC0")
      final anzeigenfarbe = sAt(r, idxAnzf);

      // stabiler 12er-Farbindex: aus Kurzname oder Fallback "FZ<id>"
      final colorIndex = stableIndexFor(
        (kurz.isNotEmpty ? kurz : 'FZ$rid'),
        12,
      );

      list.add({
        'row_id': rid,
        'kurz': kurz.isEmpty ? 'FZ $rid' : kurz,
        'bezeichnung': bez,
        'aktiv': aktiv,
        'colorIndex': colorIndex, // stabiler Index (0..11)
        'Anzeigenfarbe': anzeigenfarbe, // <<--- wichtig für deine UI
      });
    }

    list.sort((a, b) {
      final k = (a['kurz'] as String).toLowerCase().compareTo(
        (b['kurz'] as String).toLowerCase(),
      );
      if (k != 0) return k;
      return (a['row_id'] as int).compareTo(b['row_id'] as int);
    });

    return list;
  }

  // ================== TAGESPLAN LESEN ==================
  // sehr tolerante Zahl-Parsing-Hilfe, akzeptiert "1", "1.0", " 1 ", "1,0"
  int? _toIntFlexible(String v) {
    v = v.trim();
    if (v.isEmpty) return null;
    final n = num.tryParse(v.replaceAll(',', '.'));
    return n?.round();
  }

  // kompakter Debug-Tag für Tagesplan
  void _dbgTP(String msg) => debugPrint('[Tagesplan] $msg');

  Future<List<DayPlanRow>> fetchDayPlan(
    DateTime date, {
    bool morning = true,
  }) async {
    await _ensure();

    String two(int n) => n.toString().padLeft(2, '0');
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
    final wantedKey = key(DateTime(date.year, date.month, date.day));

    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      'Tagesplan!A:ZZ',
    );
    final rows = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (rows.isEmpty) return <DayPlanRow>[];

    // Header normalisieren (Lowercase + Trim + NBSP->Space)
    String norm(String s) => s.replaceAll('\u00A0', ' ').trim().toLowerCase();
    final rawHeader = rows.first;
    final header = rawHeader.map(norm).toList();

    int idxOf(String name) => header.indexOf(norm(name));

    final iDatum = idxOf('datum');
    final iRowId = idxOf('row_id');
    final iKid = idxOf('klienten row_id');
    // WICHTIG: Fahrzeug-Spalte je Modus wählen
    final iFzgMorning = idxOf('fahrzeuge row_id morgen');
    final iFzgEvening = idxOf('fahrzeuge row_id abend');
    final iFzg = morning ? iFzgMorning : iFzgEvening;

    final iOrderMorning = idxOf('reihenfolge morgen');
    final iOrderEvening = idxOf('reihenfolge abend');
    final iBem = idxOf('bemerkung');

    // Debug (sichtbar)
    debugPrint('[fetchDayPlan] wanted=$wantedKey morning=$morning');
    debugPrint('[fetchDayPlan] header: ${rawHeader.join(' | ')}');
    debugPrint(
      '[fetchDayPlan] iFzgM=$iFzgMorning iFzgA=$iFzgEvening iFzgUsed=$iFzg',
    );

    // Harte Checks (nichts schlucken)
    if (iDatum < 0 || iRowId < 0 || iKid < 0) {
      throw StateError('Pflichtspalten fehlen (Datum/row_id/Klienten row_id).');
    }
    if (iFzg < 0) {
      throw StateError(
        morning
            ? 'Spalte "Fahrzeuge row_id Morgen" fehlt.'
            : 'Spalte "Fahrzeuge row_id Abend" fehlt.',
      );
    }
    if (morning && iOrderMorning < 0) {
      throw StateError('Spalte "Reihenfolge Morgen" fehlt.');
    }
    if (!morning && iOrderEvening < 0) {
      throw StateError('Spalte "Reihenfolge Abend" fehlt.');
    }

    int? toIntFlexible(String s) {
      s = s.trim();
      if (s.isEmpty) return null;
      final n = num.tryParse(s.replaceAll(',', '.'));
      return n?.round();
    }

    DateTime? parseDate(String raw) {
      raw = raw.trim();
      if (raw.isEmpty) return null;
      final iso = DateTime.tryParse(raw);
      if (iso != null) return DateTime(iso.year, iso.month, iso.day);
      if (raw.contains('.')) {
        final p = raw.split('.');
        if (p.length >= 3) {
          final dd = int.tryParse(p[0]);
          final mm = int.tryParse(p[1]);
          final yy = int.tryParse(p[2]);
          if (dd != null && mm != null && yy != null) {
            return DateTime(yy, mm, dd);
          }
        }
      }
      return null;
    }

    int? leadingInt(String s) {
      final m = RegExp(r'^\s*(\d{1,9})').firstMatch(s);
      if (m == null) return null;
      return int.tryParse(m.group(1)!);
    }

    String at(List<String> row, int i) =>
        (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

    final out = <DayPlanRow>[];

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];

      final d = parseDate(at(row, iDatum));
      if (d == null || key(d) != wantedKey) continue;

      final rid = toIntFlexible(at(row, iRowId)) ?? 0;
      if (rid <= 0) continue;

      final kid =
          leadingInt(at(row, iKid)) ?? toIntFlexible(at(row, iKid)) ?? 0;
      if (kid <= 0) continue;

      // Fahrzeug-ID je Modus aus der passenden Spalte
      final fzgId = leadingInt(at(row, iFzg)) ?? toIntFlexible(at(row, iFzg));

      final ord = morning
          ? toIntFlexible(at(row, iOrderMorning))
          : toIntFlexible(at(row, iOrderEvening));

      final bem = at(row, iBem);

      out.add(
        DayPlanRow(
          rowId: rid,
          datum: d,
          klientId: kid,
          fahrzeugId: fzgId,
          reihenfolge: ord,
          bemerkung: bem,
        ),
      );
    }

    out.sort((a, b) {
      final ao = a.reihenfolge ?? 0x3fffffff;
      final bo = b.reihenfolge ?? 0x3fffffff;
      if (ao != bo) return ao.compareTo(bo);
      return a.rowId.compareTo(b.rowId);
    });

    debugPrint('[fetchDayPlan] rows=${out.length}');
    return out;
  }

  // Mappt Fahrzeug-row_id -> Dropdown-Anzeigetext "id – <kurz> <bezeichnung>"
  Future<Map<int, String>> _vehicleDisplayById() async {
    await _ensure();
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      'Fahrzeuge!A:Z',
    );
    final rows = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (rows.isEmpty) return <int, String>{};

    final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();
    int idxRowId = headers.indexOf('row_id');
    int idxKurz = headers.indexOf('fahrzeug kurz');
    int idxBez = headers.indexOf('bezeichnung');

    String sAt(List<String> r, int i) =>
        (i >= 0 && i < r.length) ? r[i].trim() : '';

    final map = <int, String>{};
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = int.tryParse(sAt(r, idxRowId)) ?? 0;
      if (id <= 0) continue;
      final kurz = sAt(r, idxKurz);
      final bez = sAt(r, idxBez);
      // Format wie im Tagesplan-Dropdown
      final display = '$id – ${(kurz.isEmpty ? '' : '$kurz ').trim()}$bez'
          .trim();
      map[id] = display;
    }
    return map;
  }

  Future<void> saveDayPlan(
    DateTime date,
    List<Map<String, dynamic>> entries, {
    String editorName = '',
    String deviceName = '',
    String deviceId = '',
    String deviceModel = '',
  }) async {
    await _ensure();

    String two(int n) => n.toString().padLeft(2, '0');
    final dateDE = '${two(date.day)}.${two(date.month)}.${date.year}';
    final nowIso = _nowLocal();

    // Fahrzeuganzeige-Mapping
    Map<int, String> vehMap = const <int, String>{};
    try {
      vehMap = await _vehicleDisplayById();
    } catch (e, st) {
      debugPrint('[SheetsClient.saveDayPlan] Vehicle map FEHLER: $e\n$st');
    }

    // Tagesplan lesen
    final vr = await _api!.spreadsheets.values.get(
      _Config.spreadsheetId,
      'Tagesplan!A:ZZ',
    );
    final all = (vr.values ?? [])
        .map((r) => r.map((e) => e.toString()).toList())
        .toList();
    if (all.isEmpty) {
      debugPrint('[SheetsClient.saveDayPlan] Tagesplan leer – Abbruch');
      return;
    }

    String norm(String s) => s.replaceAll('\u00A0', ' ').trim().toLowerCase();
    final rawHeader = all.first;
    final headerLower = rawHeader.map(norm).toList();
    int idxOf(String name) => headerLower.indexOf(norm(name));
    String col(int zeroBased) => _colLetterFromIndex(zeroBased);

    final iDatum = idxOf('datum');
    final iRowId = idxOf('row_id');
    final iBem = idxOf('bemerkung');

    final iOrderLegacy = idxOf('reihenfolge'); // alt -> leeren
    final iOrderMorning = idxOf('reihenfolge morgen');
    final iOrderEvening = idxOf('reihenfolge abend');

    // Fahrzeuge
    final iFzgLegacy = idxOf('fahrzeuge row_id'); // alt -> leeren
    final iFzgMorning = idxOf('fahrzeuge row_id morgen');
    final iFzgEvening = idxOf('fahrzeuge row_id abend');

    if (iRowId < 0) {
      throw StateError('Spalte "row_id" fehlt.');
    }
    if (iFzgMorning < 0 && iFzgEvening < 0) {
      throw StateError('Spalten "Fahrzeuge row_id Morgen/Abend" fehlen.');
    }

    // Modus heuristisch (aus Payload):
    final hasM = entries.any((m) => m.containsKey('Reihenfolge Morgen'));
    final hasA = entries.any((m) => m.containsKey('Reihenfolge Abend'));
    final bool isMorning =
        (hasM && !hasA) || (!hasM && !hasA); // default M, wenn nix enthalten
    final int iFzgTarget = isMorning ? iFzgMorning : iFzgEvening;
    final int iOrdTarget = isMorning ? iOrderMorning : iOrderEvening;

    debugPrint(
      '[SheetsClient.saveDayPlan] mode=${isMorning ? 'M' : 'A'} '
      'iFzgM=$iFzgMorning iFzgA=$iFzgEvening target=$iFzgTarget '
      'iOrdM=$iOrderMorning iOrdA=$iOrderEvening target=$iOrdTarget',
    );

    // row_id -> A1 Zeile
    final rowIndexByRid = <int, int>{};
    for (int r = 1; r < all.length; r++) {
      final row = all[r];
      if (iRowId >= 0 && iRowId < row.length) {
        final rid = int.tryParse(row[iRowId].toString().trim()) ?? 0;
        if (rid > 0) rowIndexByRid[rid] = r + 1;
      }
    }

    final updates = <gs.ValueRange>[];
    void setCell(int rowIndex, int idxHeader, String value) {
      if (idxHeader < 0) return;
      final range =
          'Tagesplan!${col(idxHeader)}$rowIndex:${col(idxHeader)}$rowIndex';
      updates.add(
        gs.ValueRange(
          range: range,
          values: [
            [value],
          ],
        ),
      );
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString().trim());
    }

    // Debug-Zählung
    int uVeh = 0,
        uOrd = 0,
        uBem = 0,
        uMeta = 0,
        uClrLegacyOrd = 0,
        uClrLegacyVeh = 0;

    for (final e in entries) {
      final rid = (e['row_id'] is int)
          ? (e['row_id'] as int)
          : int.tryParse('${e['row_id'] ?? ''}') ?? 0;
      final rowIndex = rowIndexByRid[rid];
      if (rowIndex == null) {
        debugPrint('[saveDayPlan] WARN: row_id $rid nicht gefunden – skip.');
        continue;
      }

      // Datum
      if (iDatum >= 0) setCell(rowIndex, iDatum, dateDE);

      // Fahrzeug: Dropdown-Text der Zielspalte setzen (oder löschen)
      final vId = _toInt(e['fahrzeuge_row_id']); // null -> löschen
      final vehDisplay = (vId != null && vId > 0)
          ? (vehMap[vId] ?? '$vId')
          : '';
      if (iFzgTarget >= 0) {
        setCell(rowIndex, iFzgTarget, vehDisplay);
        uVeh++;
      }
      // Alt-Spalte leeren, wenn vorhanden (zur Sicherheit)
      if (iFzgLegacy >= 0) {
        setCell(rowIndex, iFzgLegacy, '');
        uClrLegacyVeh++;
      }

      // Reihenfolge
      final int? vOrderMorning = _toInt(
        e['Reihenfolge Morgen'] ??
            e['reihenfolge_morgen'] ??
            e['orderMorning'] ??
            e['order_morning'],
      );
      final int? vOrderEvening = _toInt(
        e['Reihenfolge Abend'] ??
            e['reihenfolge_abend'] ??
            e['orderEvening'] ??
            e['order_evening'],
      );
      final int? vOrd = isMorning ? vOrderMorning : vOrderEvening;
      if (iOrdTarget >= 0 && vOrd != null) {
        setCell(rowIndex, iOrdTarget, vOrd.toString());
        uOrd++;
      }
      // Alt-Order-Spalte leeren
      if (iOrderLegacy >= 0) {
        setCell(rowIndex, iOrderLegacy, '');
        uClrLegacyOrd++;
      }

      // Bemerkung
      final note = '${e['bemerkung'] ?? ''}';
      if (iBem >= 0) {
        setCell(rowIndex, iBem, note);
        uBem++;
      }

      // Meta
      final ed = '${e['last_editor'] ?? editorName}';
      final dev = '${e['last_editor_device'] ?? deviceName}';
      final did = '${e['last_editor_device_id'] ?? deviceId}';
      final dnm = '${e['last_editor_device_name'] ?? deviceModel}';
      if (idxOf('last_edit_ts') >= 0)
        setCell(rowIndex, idxOf('last_edit_ts'), nowIso);
      if (idxOf('last_editor') >= 0 && ed.isNotEmpty)
        setCell(rowIndex, idxOf('last_editor'), ed);
      if (idxOf('last_editor_device_id') >= 0 && did.isNotEmpty)
        setCell(rowIndex, idxOf('last_editor_device_id'), did);
      if (idxOf('last_editor_device') >= 0 && dev.isNotEmpty)
        setCell(rowIndex, idxOf('last_editor_device'), dev);
      if (idxOf('last_editor_device_name') >= 0 && dnm.isNotEmpty)
        setCell(rowIndex, idxOf('last_editor_device_name'), dnm);
      uMeta++;

      // Pro Zeile Debug
      debugPrint(
        '[saveDayPlan] row_id=$rid veh="${vehDisplay.isEmpty ? '(leer)' : vehDisplay}" '
        'ord=${vOrd ?? '(null)'} mode=${isMorning ? 'M' : 'A'}',
      );
    }

    debugPrint(
      '[SheetsClient.saveDayPlan] prepared updates=${updates.length} '
      '(veh=$uVeh ord=$uOrd bem=$uBem meta=$uMeta clrOrd=$uClrLegacyOrd clrVeh=$uClrLegacyVeh)',
    );

    if (updates.isNotEmpty) {
      await _api!.spreadsheets.values.batchUpdate(
        gs.BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: updates,
        ),
        _Config.spreadsheetId,
      );
      debugPrint(
        '[SheetsClient.saveDayPlan] BatchUpdate OK (${updates.length} Zellen).',
      );
    } else {
      debugPrint('[SheetsClient.saveDayPlan] Nichts zu aktualisieren.');
    }
  }

  // === COPY & PASTE: END (SheetsClient) =======================================
}

// =============== Bridge: gleiche API wie SheetsClient ===============
class SupaSheetsAdapter {
  /// Map: row_id -> "Name Vorname"
  Future<Map<int, String>> fetchClientNameMap() async {
    return await SupaAdapter.klienten.fetchClientNameMap();
  }

  /// Minimale Datensätze für die Klientenliste (optional nach Einrichtung filtern)
  /// Kompatibel zu main.dart: gibt List<Map<String,dynamic>> zurück.
  Future<List<Map<String, dynamic>>> fetchClientsForList({
    int? einrRowId,
  }) async {
    return await SupaAdapter.klienten.fetchClientsForList(einrRowId: einrRowId);
  }

  /// Optional – falls im Code benötigt (Key/Value-Konfiguration)
  Future<Map<String, String>> readConfig() async {
    return await SupaAdapter.config.readConfig();
  }
}

// ================== MODELS für Fahrzeuge & Tagesplan ==================
class VehicleRow {
  final int rowId; // Fahrzeuge.row_id
  final String kurz; // "Fahrzeug Kurz"
  final String bezeichnung; // "Bezeichnung"
  final bool aktiv; // "Aktiv" (Ja/Nein)
  final int colorIndex; // einfache stabile Farbe (z.B. rowId % 6)

  VehicleRow({
    required this.rowId,
    required this.kurz,
    required this.bezeichnung,
    required this.aktiv,
    required this.colorIndex,
  });
}

// ================== HILFE: Datum normalisieren (yyyy-mm-dd) ==================
String _fmtDateKey(DateTime d) {
  final dd = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dd.year}-${two(dd.month)}-${two(dd.day)}';
}

// ================== TAGESPLAN SPEICHERN ==================
// Schreibt NUR Fahrzeuge row_id, Reihenfolge, Bemerkung + Meta-Felder für einen Tag.
// ===================== Model: DayPlanRow =====================
class DayPlanRow {
  final int rowId; // row_id aus "Tagesplan"
  final DateTime datum; // Datum
  final int klientId; // Klienten row_id
  final int? fahrzeugId; // Fahrzeuge row_id (nullable)
  final int? reihenfolge; // Reihenfolge (nullable)
  final String bemerkung; // Bemerkung

  DayPlanRow({
    required this.rowId,
    required this.datum,
    required this.klientId,
    this.fahrzeugId,
    this.reihenfolge,
    this.bemerkung = '',
  });
}

class _SupabaseLoginDialog extends StatefulWidget {
  const _SupabaseLoginDialog();

  @override
  State<_SupabaseLoginDialog> createState() => _SupabaseLoginDialogState();
}

class _SupabaseLoginDialogState extends State<_SupabaseLoginDialog> {
  final _mail = TextEditingController();
  final _pw = TextEditingController();
  final _pwNode = FocusNode();

  bool _busy = false;
  bool _remember = true;
  bool _pwVisible = false;
  String? _err;

  bool _resetRequested = false; // verhindert mehrfaches Klicken
  String? _info; // neutrale/Erfolgs-Meldung

  Future<void> _doLogin() async {
    if (_busy) return;
    // Tastatur schließen
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _busy = true;
      _err = null;
      _info = null;
    });

    final ok = await AppAuth.signInWith(_mail.text.trim(), _pw.text);
    if (!mounted) return;

    if (ok) {
      final sp = await SharedPreferences.getInstance();

      // E-Mail wird IMMER gemerkt (für Komfort)
      final email = _mail.text.trim();
      await sp.setString('supa_email', email);

      if (_remember) {
        // Passwort + Flag merken
        await sp.setString('supa_pw', _pw.text);
        await sp.setBool('supa_remember', true);
      } else {
        // Passwort NICHT merken, aber E-Mail bleibt erhalten
        await sp.remove('supa_pw');
        await sp.setBool('supa_remember', false);
      }

      debugPrint('[LoginDlg] success – closing dialogs (rootNavigator)');
      final navRoot = Navigator.of(context, rootNavigator: true);
      if (navRoot.canPop()) {
        navRoot.pop(true);
      }

      int pops = 0;
      while (navRoot.canPop()) {
        navRoot.pop(true);
        pops++;
      }
      debugPrint('[LoginDlg] popped $pops extra dialogs (rootNavigator)');
    } else {
      setState(() {
        _err = 'Anmeldung fehlgeschlagen. Bitte Zugangsdaten prüfen.';
      });
    }

    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _doResetPassword() async {
    if (_busy || _resetRequested) return;

    // Tastatur schließen
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _busy = false;
      _resetRequested = true;
      _err = null;
      _info =
          'Für eine Passwortänderung wenden Sie sich bitte an die '
          'Systemverwaltung / den Administrator.';
    });

    // Hier dieser ganze Block ist für den Email Versand eingerichtet und geprüft.
    // es braucht aber eine Homepage, auf der das mit dem Password erledigt wird
    //    // Tastatur schließen
    //    FocusManager.instance.primaryFocus?.unfocus();

    //    final email = _mail.text.trim();
    //    if (email.isEmpty) {
    //      setState(() {
    //        _err = 'Bitte zuerst die E-Mail-Adresse eingeben.';
    //        _info = null;
    //      });
    //      return;
    //    }

    //    setState(() {
    //      _busy = true;
    //      _err = null;
    //      _info = null;
    //    });

    //    try {
    //      debugPrint('[LoginDlg] Passwort-Reset angefordert für $email');

    //      await Supa.client.auth.resetPasswordForEmail(email);

    //      if (!mounted) return;

    //      setState(() {
    //        _resetRequested = true;
    //        _info =
    //            'Es wurde eine E-Mail zum Zurücksetzen des Passworts an\n'
    //            '$email gesendet. Bitte prüfe dein Postfach.';
    //        _err = null;
    //      });
    //      // Kein SnackBar mehr – alles im Dialog sichtbar
    //    } catch (e, st) {
    //      debugPrint('[LoginDlg] Passwort-Reset fehlgeschlagen: $e\n$st');
    //      if (!mounted) return;

    //      String msg =
    //          'Passwort-Reset fehlgeschlagen. Bitte später erneut versuchen.';

    //      if (e is AuthApiException) {
    //        final em = (e.message ?? '').toLowerCase();

    //        // 1) Rate-Limit (429)
    //        if (e.statusCode == 429 &&
    //            (e.code == 'over_email_send_rate_limit' ||
    //                em.contains('rate') ||
    //                em.contains('only request this'))) {
    //          msg = 'Es wurde bereits eine E-Mail zum Zurücksetzen gesendet.\n'
    //              'Bitte warte kurz, bevor du es erneut versuchst.';
    //          // in diesem Fall Button auch blockieren, damit nicht gespammt wird
    //          _resetRequested = true;
    //        }
    //        // 2) Link abgelaufen / ungültig (falls Supabase sowas meldet)
    //        else if (em.contains('expired') || em.contains('invalid')) {
    //          msg = 'Der Link zum Zurücksetzen ist ungültig oder abgelaufen.\n'
    //              'Bitte fordere eine neue E-Mail an.';
    //        }
    //        // 3) generischer Auth-Fehler mit Nachricht
    //        else if (e.message != null && e.message!.trim().isNotEmpty) {
    //          msg = 'Fehler: ${e.message}';
    //        }
    //      }

    //      setState(() {
    //        _err = msg;
    //        // _info bleibt null
    //      });
    //    } finally {
    //      if (mounted) {
    //        setState(() {
    //          _busy = false;
    //        });
    //      }
    //    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[LOGIN DIALOG] initState() called');

    AppBus.loginDialogOpen = true;
    AppBus.lastLoginDialogToken = DateTime.now().millisecondsSinceEpoch
        .toString();

    () async {
      try {
        final sp = await SharedPreferences.getInstance();
        final e = sp.getString('supa_email') ?? '';
        final p = sp.getString('supa_pw') ?? '';
        final r = sp.getBool('supa_remember');

        if (e.isNotEmpty) _mail.text = e;
        if (p.isNotEmpty) _pw.text = p;
        if (r != null) {
          _remember = r;
        }
      } catch (_) {}
    }();
  }

  @override
  void dispose() {
    debugPrint('[LoginDlg] dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = (MediaQuery.of(context).size.width * 0.9).clamp(280.0, 420.0);

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.copyWith(
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: const TextStyle(fontSize: 14),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(fontSize: 13),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        titlePadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        title: const Text('Anmeldung Fahrdienst'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _mail,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _pwNode.requestFocus(),
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  enabled: !_busy,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pw,
                  focusNode: _pwNode,
                  obscureText: !_pwVisible,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _doLogin(),
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _pwVisible ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _pwVisible = !_pwVisible;
                              });
                            },
                    ),
                  ),
                  enabled: !_busy,
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _remember,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _remember = v ?? true),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Anmeldedaten merken (lokal)'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: (_busy || _resetRequested)
                        ? null
                        : _doResetPassword,
                    child: const Text('Passwort vergessen / ändern'),
                  ),
                ),
                if (_info != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _info!,
                    style: const TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_err != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _err!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    // App sofort komplett beenden
                    SystemNavigator.pop();
                  },
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: _busy ? null : _doLogin,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Anmelden'),
          ),
        ],
      ),
    );
  }
}

class _LoggingSheetsProxy {
  final dynamic _inner; // SupaSheetsAdapter oder SheetsClient
  _LoggingSheetsProxy(this._inner);

  Future<List<String>> fetchEmployeeNameList() async {
    debugPrint('[Proxy] fetchEmployeeNameList() -> ${_inner.runtimeType}');
    final t0 = DateTime.now();
    try {
      final res = await (_inner as dynamic).fetchEmployeeNameList();
      final out = List<String>.from(res ?? const []);
      debugPrint(
        '[Proxy] fetchEmployeeNameList() <- ${out.length} in ${DateTime.now().difference(t0).inMilliseconds}ms',
      );
      return out;
    } catch (e, st) {
      debugPrint('[Proxy] fetchEmployeeNameList ERROR: $e\n$st');
      rethrow;
    }
  }

  // ---- Map<int,String> für die schnelle Namenliste ----
  Future<Map<int, String>> fetchClientNameMap() async {
    debugPrint('[Proxy] fetchClientNameMap() -> ${_inner.runtimeType}');
    final t0 = DateTime.now();
    try {
      final Map<int, String> res = Map<int, String>.from(
        await (_inner as dynamic).fetchClientNameMap(),
      );
      debugPrint(
        '[Proxy] fetchClientNameMap() <- ${res.length} in ${DateTime.now().difference(t0).inMilliseconds}ms',
      );
      return res;
    } catch (e, st) {
      debugPrint('[Proxy] fetchClientNameMap ERROR: $e\n$st');
      rethrow;
    }
  }

  // ======= fetchClientsForList (KORRIGIERT) =======
  Future<List<Map<String, dynamic>>> fetchClientsForList({
    int? einrRowId,
  }) async {
    await AppAuth.ensureSignedIn();

    final res = await Supa.client
        .from('Klienten')
        .select(
          // ⚠️ ALLE FELDER GENAU WIE IN DER DB, mit Anführungszeichen bei Spalten mit Leerzeichen/Punkt
          'row_id, '
          '"Einrichtungen row_id", '
          'Aktiv, '
          '"Nr.", '
          'Name, Vorname, '
          'Adresse, Ortsteil, '
          'Telefon, '
          '"Angehörige", "Angehörige Tel.", '
          'Betreuer, "Betreuer Tel.", '
          'RS, '
          '"Besonderheiten", '
          '"Infos zur Wohnsituation", '
          '"Tagespflege (Wochentage)", '
          '"Hilfe bei", ' // <-- richtig!
          'Fahrdienst, '
          'Schlüssel, Klingelzeichen, "Sonstige Informationen"',
        )
        .order('Name', ascending: true);

    final list = List<Map<String, dynamic>>.from(res as List);

    // Nur aktive
    final onlyActive = list.where((r) {
      final v = r['Aktiv'];
      if (v is bool) return v;
      final s = (v ?? '').toString().trim().toLowerCase();
      return s == 'ja' || s == 'true' || s == '1';
    });

    // Optional nach Einrichtung
    Iterable<Map<String, dynamic>> filtered = onlyActive;
    if (einrRowId != null && einrRowId > 0) {
      filtered = onlyActive.where((r) {
        final v = r['Einrichtungen row_id'];
        if (v is num) return v.toInt() == einrRowId;
        final p = int.tryParse('${v ?? ''}');
        return p == einrRowId;
      });
    }

    final out = filtered.toList(growable: false)
      ..sort(
        (a, b) => ('${a['Name'] ?? ''}'.toLowerCase()).compareTo(
          ('${b['Name'] ?? ''}'.toLowerCase()),
        ),
      );

    return out;
  }
  // ======= /fetchClientsForList =======

  // ---- Optional: Konfiguration ----
  Future<Map<String, String>> readConfig() async {
    debugPrint('[Proxy] readConfig() -> ${_inner.runtimeType}');
    final t0 = DateTime.now();
    try {
      final res = Map<String, String>.from(
        await (_inner as dynamic).readConfig(),
      );
      debugPrint(
        '[Proxy] readConfig() <- ${res.length} keys in ${DateTime.now().difference(t0).inMilliseconds}ms',
      );
      return res;
    } catch (e, st) {
      debugPrint('[Proxy] readConfig ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<void> writeConfig({
    String? name,
    String? address,
    String? phone1,
    String? phone2,
    String? phone3,
  }) async {
    debugPrint('[Proxy] writeConfig() -> ${_inner.runtimeType}');
    final t0 = DateTime.now();
    try {
      await (_inner as dynamic).writeConfig(
        name: name,
        address: address,
        phone1: phone1,
        phone2: phone2,
        phone3: phone3,
      );
      debugPrint(
        '[Proxy] writeConfig() <- ok in ${DateTime.now().difference(t0).inMilliseconds}ms',
      );
    } catch (e, st) {
      debugPrint('[Proxy] writeConfig ERROR: $e\n$st');
      rethrow;
    }
  }
}
