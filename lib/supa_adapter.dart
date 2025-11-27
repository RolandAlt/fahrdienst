// lib/supa_adapter.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_bus.dart';
import 'dart:convert';
// oben (nur falls noch nicht vorhanden)
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

final client = sb.Supabase.instance.client;
final cli = client;

/// Listener-Typ für Änderungen an der Klienten-Tabelle
typedef ClientChangeListener = void Function();

// ==================== Supabase DayPlan Modell (kanonisch) ====================
class SupaDayPlanRow {
  final int rowId; // row_id in "Tagesplan"
  final int klientId; // "Klienten row_id"
  final int? fahrzeugId; // "Fahrzeuge row_id Morgen/Abend"
  final int? reihenfolge; // "Reihenfolge Morgen/Abend"
  final String? bemerkung; // "Bemerkung"

  SupaDayPlanRow({
    required this.rowId,
    required this.klientId,
    required this.fahrzeugId,
    required this.reihenfolge,
    required this.bemerkung,
  });

  // Robuste Factory: zieht die richtigen Spalten anhand des Modus
  factory SupaDayPlanRow.fromMap(
    Map<String, dynamic> r, {
    required bool morning,
  }) {
    final vehCol = morning
        ? 'Fahrzeuge row_id Morgen'
        : 'Fahrzeuge row_id Abend';
    final orderCol = morning ? 'Reihenfolge Morgen' : 'Reihenfolge Abend';

    int _asInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    int? _asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final rowId = _asInt(r['row_id']);
    final klient = _asInt(r['Klienten row_id']);
    final vehId = _asIntOrNull(r[vehCol]);
    final ord = _asIntOrNull(r[orderCol]);
    final remark = (r['Bemerkung'] ?? '').toString().trim();

    return SupaDayPlanRow(
      rowId: rowId,
      klientId: klient,
      fahrzeugId: vehId,
      reihenfolge: ord,
      bemerkung: remark.isEmpty ? null : remark,
    );
  }

  /// Baut aus dem UI-Payload (Map aus main.dart: row_id/fahrzeugId/reihenfolge/bemerkung)
  /// ein SupaDayPlanRow. `klientId` ist fürs Speichern nicht nötig; falls vorhanden, wird er genutzt,
  /// sonst 0 gesetzt.
  factory SupaDayPlanRow.fromUiPayload(Map<String, dynamic> m) {
    int _asInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    int? _asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final rowId = _asInt(m['row_id']);
    final fahrzeug = _asIntOrNull(m['fahrzeugId']);
    final order = _asIntOrNull(m['reihenfolge']);
    final noteStr = (m['bemerkung'] ?? '').toString().trim();
    final klient = _asInt(m['Klienten row_id']); // falls nicht vorhanden -> 0

    return SupaDayPlanRow(
      rowId: rowId,
      klientId: klient,
      fahrzeugId: fahrzeug,
      reihenfolge: order,
      bemerkung: noteStr.isEmpty ? null : noteStr,
    );
  }

  @override
  String toString() =>
      'SupaDayPlanRow(rowId=$rowId, klientId=$klientId, fahrzeugId=$fahrzeugId, reihenfolge=$reihenfolge, bemerkung="${bemerkung ?? ''}")';
}

// Brücke: Die UI darf weiterhin "DayPlanRow" verwenden.
typedef DayPlanRow = SupaDayPlanRow;

// ISO-Datum ohne intl/DateUtils (YYYY-MM-DD)
String _isoDate(DateTime d) =>
    DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

String _isoDateOnly(DateTime d) =>
    DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

// --- Supabase Kompat-Helper: unterstützt alte (filter) und neue (eq) SDKs ---
dynamic supaEq(dynamic q, String column, dynamic value) {
  try {
    return q.eq(column, value); // neue SDKs
  } catch (_) {
    return q.filter(column, 'eq', value); // ältere SDKs
  }
}

dynamic supaOrder(dynamic q, String column, {bool ascending = true}) {
  try {
    return q.order(column, ascending: ascending); // neue SDKs
  } catch (_) {
    // ältere SDKs haben evtl. nur order(name) ohne named params
    try {
      return q.order(column);
    } catch (_) {
      return q; // notfalls no-op
    }
  }
}

class SupaAdapter {
  static final einrichtungen = _SupaEinrichtungenAdapter();
  static final klienten = _SupaKlientenAdapter();
  static final tagesplan = _SupaTagesplanAdapter();

  // NEU: Dienstplan-Adapter (vorbereitet für spätere Nutzung)
  static final dienstplan = _SupaDienstplanAdapter();

  // Mitarbeiter-Adapter
  static final mitarbeiter = _SupaMitarbeiterAdapter();

  // Fahrzeuge-Adapter
  static final fahrzeuge = _SupaFahrzeugeAdapter();

  // Bridge-Adapter …
  static final sheets = SupaSheetsAdapter();
  static final config = sheets;
}

// ================= Dienstplan: Vorbereitung mit Auto-Refresh =================

class _SupaDienstplanAdapter {
  final cli = Supa.client;

  // Hilfsfunktion: Datum auf 00:00 und Wochenbeginn (Montag) normalisieren
  DateTime _asDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _weekStart(DateTime d) {
    final base = _asDateOnly(d);
    final wd = base.weekday; // Mo=1 ... So=7
    return base.subtract(Duration(days: wd - 1));
  }

  // ===================== Laden: Dienstplan für eine Woche ===================

  /// Lädt alle Dienstplan-Zeilen für die Woche des übergebenen Datums.
  /// Es wird immer auf den Montag (Wochenbeginn) normalisiert.

  Future<List<Map<String, dynamic>>> fetchWeekPlan(DateTime date) async {
    await AppAuth.ensureSignedIn();

    final weekStart = _weekStart(date);
    final iso = weekStart.toIso8601String().split('T').first;

    debugPrint('[Supa.Dienstplan.fetchWeekPlan] wochenbeginn=$iso');

    final res = await cli
        .from('Dienstplan')
        .select('''
          row_id,
          "Mitarbeiter row_ID",
          "Fahrzeuge row_id Mo",
          "Fahrzeuge row_id Di",
          "Fahrzeuge row_id Mi",
          "Fahrzeuge row_id Do",
          "Fahrzeuge row_id Fr",
          "Fahrzeuge row_id Sa",
          "Fahrzeuge row_id So",
          "Status_Mo",
          "Status_Di",
          "Status_Mi",
          "Status_Do",
          "Status_Fr",
          "Status_Sa",
          "Status_So",
          "Bemerkung",
          "Wochenbeginn"
          ''')
        .eq('Wochenbeginn', iso)
        .order('Mitarbeiter row_ID', ascending: true);

    final rows = List<Map<String, dynamic>>.from((res as List?) ?? const []);
    debugPrint(
      '[Supa.Dienstplan.fetchWeekPlan] rows=${rows.length} für Woche $iso',
    );
    return rows;
  }

  // ===================== Speichern: Dienstplan-Woche ========================

  /// Speichert die komplette Dienstplan-Woche.
  ///
  /// Das UI gibt eine Liste von Maps, in der jede Map mindestens
  ///  - 'Mitarbeiter row_ID' (int)
  ///  - die sieben Fahrzeug-Spalten
  ///  - optional 'Bemerkung'
  /// enthält.
  ///
  /// Strategie:
  /// 1. Alle vorhandenen Zeilen für diese Woche löschen.
  /// 2. Nur nicht-leere Zeilen (mind. 1 Tag oder Bemerkung) neu einfügen.

  /// Speichert die komplette Dienstplan-Woche.
  ///
  /// Das UI gibt eine Liste von Maps, in der jede Map mindestens
  ///  - 'Mitarbeiter row_ID' (int)
  ///  - die sieben Fahrzeug-Spalten
  ///  - die sieben Status-Spalten (Status_Mo..Status_So, 0=normal,1=U,2=K,3=S)
  ///  - optional 'Bemerkung'
  /// enthält.
  ///
  /// Strategie:
  /// 1. Alle vorhandenen Zeilen für diese Woche löschen.
  /// 2. Nur nicht-leere Zeilen (mind. 1 Fahrzeug ODER 1 Status ODER Bemerkung)
  ///    neu einfügen.
  ///

  /// Speichert die komplette Dienstplan-Woche.
  ///
  /// Neue Strategie:
  /// - keine pauschale Wochen-DELETE mehr!
  /// - pro Mitarbeiter wird gezielt INSERT / UPDATE / DELETE gemacht
  ///   → wenn RLS greift, bleibt der Rest der Woche unangetastet.
  Future<void> saveWeekPlan(
    DateTime date,
    List<Map<String, dynamic>> entries,
  ) async {
    await AppAuth.ensureSignedIn();

    final weekStart = _weekStart(date);
    final iso = weekStart.toIso8601String().split('T').first;

    debugPrint(
      '[Supa.Dienstplan.saveWeekPlan] wochenbeginn=$iso entries=${entries.length}',
    );

    // Hilfsfunktionen lokal, falls nicht global vorhanden
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    int? _asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    int _asStatus(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v.clamp(0, 3);
      if (v is num) return v.toInt().clamp(0, 3);
      final p = int.tryParse('$v') ?? 0;
      return p.clamp(0, 3);
    }

    // ---- Neue Einträge nach Mitarbeiter-ID mappen ----
    final Map<int, Map<String, dynamic>> newByMid = {};

    for (final raw in entries) {
      final mid = _asInt(raw['Mitarbeiter row_ID']);
      if (mid <= 0) continue;
      newByMid[mid] = raw;
    }

    // ---- Bestehende Woche aus DB laden ----
    final existingRows = await cli
        .from('Dienstplan')
        .select()
        .eq('Wochenbeginn', iso);

    final Map<int, Map<String, dynamic>> existingByMid = {};
    for (final r in existingRows) {
      final mid = _asInt(r['Mitarbeiter row_ID']);
      if (mid > 0) {
        existingByMid[mid] = r;
      }
    }

    // ---- Vereinigung aller Mitarbeiter-IDs ----
    final allMids = <int>{...existingByMid.keys, ...newByMid.keys}.toList()
      ..sort();

    debugPrint(
      '[Supa.Dienstplan.saveWeekPlan] existing=${existingByMid.length} new=${newByMid.length} union=${allMids.length}',
    );

    // ---- Pro Mitarbeiter gezielt speichern ----
    for (final mid in allMids) {
      final newData = newByMid[mid];
      final oldRow = existingByMid[mid];

      // Fall 1: Es gibt keinen neuen Datensatz, aber einen alten → löschen
      if (newData == null) {
        if (oldRow != null) {
          final rowId = _asInt(oldRow['row_id']);
          if (rowId > 0) {
            debugPrint(
              '[Supa.Dienstplan.saveWeekPlan] DELETE row_id=$rowId (mid=$mid)',
            );
            await cli.from('Dienstplan').delete().eq('row_id', rowId);
          }
        }
        continue;
      }

      // Neue Werte robust auslesen
      final mo = _asIntOrNull(newData['Fahrzeuge row_id Mo']);
      final di = _asIntOrNull(newData['Fahrzeuge row_id Di']);
      final mi = _asIntOrNull(newData['Fahrzeuge row_id Mi']);
      final doo = _asIntOrNull(newData['Fahrzeuge row_id Do']);
      final fr = _asIntOrNull(newData['Fahrzeuge row_id Fr']);
      final sa = _asIntOrNull(newData['Fahrzeuge row_id Sa']);
      final so = _asIntOrNull(newData['Fahrzeuge row_id So']);

      final statusMo = _asStatus(newData['Status_Mo']);
      final statusDi = _asStatus(newData['Status_Di']);
      final statusMi = _asStatus(newData['Status_Mi']);
      final statusDo = _asStatus(newData['Status_Do']);
      final statusFr = _asStatus(newData['Status_Fr']);
      final statusSa = _asStatus(newData['Status_Sa']);
      final statusSo = _asStatus(newData['Status_So']);

      String remark = '${newData['Bemerkung'] ?? ''}'.trim();
      if (remark.isEmpty) {
        remark = '';
      }

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

      // Vollständig leere Zeilen sollen NICHT gespeichert werden.
      // Wenn es vorher eine Zeile gab -> löschen, sonst nix tun.
      if (allNull) {
        if (oldRow != null) {
          final rowId = _asInt(oldRow['row_id']);
          if (rowId > 0) {
            debugPrint(
              '[Supa.Dienstplan.saveWeekPlan] DELETE (allNull) row_id=$rowId (mid=$mid)',
            );
            await cli.from('Dienstplan').delete().eq('row_id', rowId);
          }
        }
        continue;
      }

      final payload = <String, dynamic>{
        'Wochenbeginn': iso,
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
        'Bemerkung': remark.isEmpty ? null : remark,
      };

      if (oldRow == null) {
        debugPrint(
          '[Supa.Dienstplan.saveWeekPlan] INSERT mid=$mid für Woche $iso',
        );
        await cli.from('Dienstplan').insert(payload);
      } else {
        final rowId = _asInt(oldRow['row_id']);
        debugPrint(
          '[Supa.Dienstplan.saveWeekPlan] UPDATE row_id=$rowId (mid=$mid) für Woche $iso',
        );
        await cli.from('Dienstplan').update(payload).eq('row_id', rowId);
      }
    }

    debugPrint('[Supa.Dienstplan.saveWeekPlan] DONE für Woche $iso');
  }

  // Hilfsfunktion: robust nach int umwandeln
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final p = int.tryParse('${v ?? ''}');
    return p ?? 0;
  }

  // --- Auto-Refresh: Listener-Mechanik für Dienstplan ----------------------

  /// Registrierte Listener aus der UI (z.B. später Dienstplan-Screen)
  final List<ClientChangeListener> _dienstplanListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-"Dienstplan"-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _dienstplanStreamSub;

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    _dienstplanListeners.add(listener);
    _ensureDienstplanStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _dienstplanListeners.remove(listener);
    if (_dienstplanListeners.isEmpty) {
      _dienstplanStreamSub?.cancel();
      _dienstplanStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Dienstplan-Tabelle läuft.
  void _ensureDienstplanStream() {
    if (_dienstplanStreamSub != null) return;

    debugPrint('[Supa.Dienstplan] Starte Stream auf Tabelle "Dienstplan"');

    _dienstplanStreamSub = Supa.client
        .from('Dienstplan')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            // rows = aktueller Snapshot der Dienstplan-Tabelle
            debugPrint(
              '[Supa.Dienstplan] Stream-Update: rows=${rows.length} '
              '-> benachrichtige Listener (${_dienstplanListeners.length})',
            );

            final listenersCopy = List<ClientChangeListener>.from(
              _dienstplanListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint('[Supa.Dienstplan] Listener-Fehler: $e\n$st');
              }
            }
          },
          onError: (error, st) {
            debugPrint(
              '[Supa.Dienstplan] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _dienstplanStreamSub?.cancel();
            _dienstplanStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik für Dienstplan -----------------
}

// ================= Mitarbeiter: eigener Name per Auth-UID =================

class _SupaMitarbeiterAdapter {
  final cli = Supa.client;

  /// Lädt den Mitarbeiter-Datensatz zum aktuell eingeloggten Supabase-User.
  /// Gibt zusätzlich 'funktion_text' zurück (aus Tabelle "Mitarbeiter Funktion").
  /// Return: Map<String, dynamic> oder null.
  Future<Map<String, dynamic>?> fetchCurrentMitarbeiterWithFunktion() async {
    // 1) Supabase-Client holen
    final client = sb.Supabase.instance.client;

    // 2) Aktuellen Auth-User lesen
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      debugPrint(
        '[Supa.Mitarbeiter] fetchCurrentMitarbeiterWithFunktion(): kein auth_user_id vorhanden',
      );
      return null;
    }

    // 3) Mitarbeiter-Zeile für diesen User laden
    final List<dynamic> rows = await client
        .from('Mitarbeiter')
        .select() // KEIN <Map<String, dynamic>> mehr!
        .eq('auth_user_id', uid)
        .limit(1);

    if (rows.isEmpty) {
      debugPrint(
        '[Supa.Mitarbeiter] kein Mitarbeiter für auth_user_id=$uid gefunden',
      );
      return null;
    }

    // 4) In saubere Map casten
    final mit = Map<String, dynamic>.from(rows.first as Map);

    // 5) Funktionstext nachladen
    final funktionId = mit['Funktion'];
    if (funktionId != null) {
      final List<dynamic> fRows = await client
          .from('Mitarbeiter Funktion')
          // Spaltenname heißt bei dir genau "Funktion"
          .select('"Funktion"')
          .eq('row_id', funktionId)
          .limit(1);

      if (fRows.isNotEmpty) {
        final f = Map<String, dynamic>.from(fRows.first as Map);
        mit['funktion_text'] = f['Funktion'] ?? '(unbekannt)';
      } else {
        mit['funktion_text'] = '(unbekannt)';
      }
    } else {
      mit['funktion_text'] = '(keine)';
    }

    return mit;
  }

  /// Aktualisiert eine Mitarbeiter-Zeile.
  Future<void> updateMitarbeiterRow({
    required int rowId,
    required Map<String, dynamic> values,
  }) async {
    if (values.isEmpty) {
      debugPrint(
        '[Supa.Mitarbeiter] updateMitarbeiterRow(): values leer -> skip',
      );
      return;
    }

    await cli.from('Mitarbeiter').update(values).eq('row_id', rowId);

    debugPrint('[Supa.Mitarbeiter] updateMitarbeiterRow(): OK rowId=$rowId');
  }

  // Liste für ggf. alte Dialoge (bleibt drin, aber wir erzwingen Supabase-Flow)
  Future<List<String>> fetchEmployeeNameList() async {
    await AppAuth.ensureSignedIn();
    final res = await cli
        .from('Mitarbeiter')
        .select('Name, Vorname, Aktiv')
        .order('Name', ascending: true);

    final rows = List<Map<String, dynamic>>.from((res as List?) ?? const []);
    final out = <String>[];
    for (final r in rows) {
      // Aktiv-Flag robust auswerten
      final v = r['Aktiv'];
      final bool aktiv;
      if (v is bool) {
        aktiv = v;
      } else {
        final s = '${v ?? ''}'.trim().toLowerCase();
        aktiv = s == 'true' || s == 'ja' || s == '1' || s == 'yes';
      }
      if (!aktiv) continue;

      final n = '${r['Name'] ?? ''}'.trim();
      final vname = '${r['Vorname'] ?? ''}'.trim();
      final full = [n, vname].where((e) => e.isNotEmpty).join(' ').trim();
      if (full.isNotEmpty) out.add(full);
    }
    return out; // << wichtig: immer return!
  }

   // Eigenen Mitarbeiter (per Auth-UID) lesen – für
  //   final n = await SupaAdapter.mitarbeiter.fetchOwnDisplayNameByAuthId();
  Future<String?> fetchOwnDisplayNameByAuthId() async {
    await AppAuth.ensureSignedIn();

    // Supabase-Client IMMER über supabase_flutter holen
    final c = sb.Supabase.instance.client;

    // User-UID holen – robust für unterschiedliche Supabase-SDKs
    String? uid = c.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      try {
        final resp = await c.auth.getUser();
        uid = resp.user?.id;
      } catch (_) {}
    }

    if (uid == null || uid.isEmpty) {
      debugPrint('[Mitarbeiter] fetchOwnDisplayNameByAuthId: keine UID');
      return null;
    }

    // Mitarbeiter-Zeile zu dieser UID lesen
    final List<dynamic> rows = await c
        .from('Mitarbeiter')
        .select('Name, Vorname')
        .eq('auth_user_id', uid)
        .limit(1);

    if (rows.isEmpty) {
      debugPrint('[Mitarbeiter] kein Treffer für uid=$uid');
      return null;
    }

    final r = Map<String, dynamic>.from(rows.first as Map);
    final n = '${r['Name'] ?? ''}'.trim();
    final v = '${r['Vorname'] ?? ''}'.trim();
    final full = [n, v].where((e) => e.isNotEmpty).join(' ').trim();
    return full.isEmpty ? null : full;
  }

  // --- Auto-Refresh: Listener-Mechanik für Mitarbeiter -------------------

  /// Registrierte Listener aus der UI (z.B. HomePageState oder später Dienstplan-Screen)
  final List<ClientChangeListener> _employeeListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-"Mitarbeiter"-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _employeeStreamSub;

  /// Für Dienstplan: alle aktiven Fahrer (Funktion = 1) holen.
  ///
  /// Rückgabe: Liste von Maps mit mindestens
  ///  - 'row_id' (int)
  ///  - 'Name' (String)
  ///  - 'Vorname' (String)
  /// Liefert Mitarbeiter für den Dienstplan-Tab.
  ///
  /// Aktuell:
  ///  - sehr tolerante Filterung auf "aktiv"
  ///  - KEIN hartes Filtern mehr auf Funktion = 1,
  ///    damit auch dann Mitarbeiter erscheinen, wenn das Feld noch nicht
  ///    konsequent gepflegt ist.
  Future<List<Map<String, dynamic>>> fetchDriversForDienstplan() async {
    await AppAuth.ensureSignedIn();

    debugPrint('[Supa.Mitarbeiter] fetchDriversForDienstplan: START');

    final res = await cli
        .from('Mitarbeiter')
        .select('row_id, Name, Vorname, Funktion, Aktiv')
        .order('Name', ascending: true);

    debugPrint(
      '[Supa.Mitarbeiter] fetchDriversForDienstplan: raw result type=${res.runtimeType}',
    );

    final rows = List<Map<String, dynamic>>.from((res as List?) ?? const []);
    debugPrint(
      '[Supa.Mitarbeiter] fetchDriversForDienstplan: rows gesamt=${rows.length}',
    );

    bool _isAktiv(dynamic v) {
      if (v is bool) return v;
      final s = '${v ?? ''}'.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'ja' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'nein' || s == 'no') return false;
      return true; // Fallback: eher aktiv als inaktiv
    }

    int _asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      final p = int.tryParse('${v ?? ''}');
      return p ?? 0;
    }

    final out = <Map<String, dynamic>>[];

    var index = 0;
    for (final r in rows) {
      index++;

      final aktiv = _isAktiv(r['Aktiv']);
      final funktion = _asInt(r['Funktion']);
      final id = _asInt(r['row_id']);
      final name = '${r['Name'] ?? ''}'.trim();
      final vorname = '${r['Vorname'] ?? ''}'.trim();

      debugPrint(
        '[Supa.Mitarbeiter] row $index: '
        'id=$id, aktiv=$aktiv, funktion=$funktion, '
        'name="$name", vorname="$vorname"',
      );

      if (!aktiv) {
        debugPrint('[Supa.Mitarbeiter]  -> übersprungen, weil aktiv=false');
        continue;
      }

      if (funktion != 1) {
        debugPrint('[Supa.Mitarbeiter]  -> übersprungen, weil funktion!=1');
        continue;
      }

      if (id <= 0) {
        debugPrint('[Supa.Mitarbeiter]  -> übersprungen, weil id<=0');
        continue;
      }

      if (name.isEmpty && vorname.isEmpty) {
        debugPrint(
          '[Supa.Mitarbeiter]  -> übersprungen, weil Name+Vorname leer',
        );
        continue;
      }

      out.add({'row_id': id, 'Name': name, 'Vorname': vorname});
    }

    debugPrint(
      '[Supa.Mitarbeiter] fetchDriversForDienstplan: FILTER-Resultat=${out.length} Fahrer',
    );
    return out;
  }

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    // Schutz: denselben Listener nicht mehrfach registrieren
    if (_employeeListeners.contains(listener)) {
      debugPrint(
        '[Supa.Mitarbeiter] Listener bereits registriert – überspringe.',
      );
      return;
    }

    _employeeListeners.add(listener);
    _ensureEmployeeStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _employeeListeners.remove(listener);
    if (_employeeListeners.isEmpty) {
      _employeeStreamSub?.cancel();
      _employeeStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Mitarbeiter-Tabelle läuft.
  void _ensureEmployeeStream() {
    // Wenn schon ein Stream läuft -> nichts tun
    if (_employeeStreamSub != null) return;

    debugPrint('[Supa.Mitarbeiter] Starte Stream auf Tabelle "Mitarbeiter"');

    _employeeStreamSub = Supa.client
        .from('Mitarbeiter')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            // rows enthält immer den aktuellen Snapshot der Tabelle.
            debugPrint(
              '[Supa.Mitarbeiter] Stream-Update: rows=${rows.length} -> '
              'benachrichtige Listener (${_employeeListeners.length})',
            );

            // Kopie der Liste, damit Änderungen während des Iterierens nicht krachen
            final listenersCopy = List<ClientChangeListener>.from(
              _employeeListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint(
                  '[Supa.Mitarbeiter] Fehler im ClientChangeListener: $e\n$st',
                );
              }
            }
          },
          onError: (Object error, StackTrace st) {
            debugPrint(
              '[Supa.Mitarbeiter] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _employeeStreamSub?.cancel();
            _employeeStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik für Mitarbeiter ---------------
}

class _SupaEinrichtungenAdapter {
  final cli = Supa.client;

  Future<Map<String, dynamic>?> fetchById(int rowId) async {
    debugPrint('[Supa.Einr] fetchById($rowId)');
    await AppAuth.ensureSignedIn();
    final res = await cli
        .from('Einrichtungen')
        .select('*')
        .filter('row_id', 'eq', rowId)
        .maybeSingle();
    return res;
  }

  Future<List<Map<String, dynamic>>> fetchAllActive() async {
    debugPrint('[Supa.Einr] fetchAllActive()');
    await AppAuth.ensureSignedIn();
    final res = await cli
        .from('Einrichtungen')
        .select('*')
        .filter('Aktiv', 'eq', true)
        .order('Name der Einrichtung', ascending: true);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<Map<String, String>> readActiveConfig() async {
    const tag = '[Supa.Einr] readActiveConfig';
    debugPrint('$tag: START');

    await AppAuth.ensureSignedIn();

    // EXAKT deine Spaltennamen verwenden:
    final res = await cli
        .from('Einrichtungen')
        .select(
          'row_id, "Name der Einrichtung", "Adresse der Einrichtung", logo_url',
        )
        .eq('Aktiv', true)
        .limit(1);

    if (res is! List || res.isEmpty) {
      debugPrint('$tag: keine aktive Einrichtung gefunden');
      return {};
    }

    final row = res.first as Map<String, dynamic>;
    debugPrint('$tag: raw row = $row');

    final result = <String, String>{
      'row_id': '${row['row_id'] ?? ''}',
      'name': '${row['Name der Einrichtung'] ?? ''}',
      'address': '${row['Adresse der Einrichtung'] ?? ''}',
      'logo_url': '${row['logo_url'] ?? ''}',
    };

    debugPrint('$tag: result=$result');
    return result;
  }

  // --- Auto-Refresh: Listener-Mechanik für Einrichtungen -------------------

  /// Registrierte Listener aus der UI (z. B. HomePageState)
  final List<ClientChangeListener> _einrListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-"Einrichtungen"-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _einrStreamSub;

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    _einrListeners.add(listener);
    _ensureEinrStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _einrListeners.remove(listener);
    if (_einrListeners.isEmpty) {
      _einrStreamSub?.cancel();
      _einrStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Einrichtungen-Tabelle läuft.
  void _ensureEinrStream() {
    // Wenn schon ein Stream läuft -> nichts tun
    if (_einrStreamSub != null) return;

    debugPrint(
      '[Supa.Einrichtungen] Starte Stream auf Tabelle "Einrichtungen"',
    );

    _einrStreamSub = Supa.client
        .from('Einrichtungen')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            debugPrint(
              '[Supa.Einrichtungen] Stream-Update: rows=${rows.length} -> benachrichtige Listener (${_einrListeners.length})',
            );

            final listenersCopy = List<ClientChangeListener>.from(
              _einrListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint('[Supa.Einrichtungen] Listener-Fehler: $e\n$st');
              }
            }
          },
          onError: (error, st) {
            debugPrint(
              '[Supa.Einrichtungen] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _einrStreamSub?.cancel();
            _einrStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik -------------------------------
}

class _SupaFahrzeugeAdapter {
  Future<List<dynamic>> fetchVehicles({
    int? einrRowId,
    bool onlyActive = true,
  }) async {
    // Debug-Haken, damit wir sehen, dass der Call wirklich ankommt
    debugPrint(
      '[Supa.Fahrzeuge] fetchVehicles(einrRowId=$einrRowId, onlyActive=$onlyActive)',
    );

    // Spalten (mit Quotes für Leerzeichen)
    const sel =
        'row_id, "Einrichtungen row_id", "Fahrzeug Kurz", Kennzeichen, '
        'Bezeichnung, Sitzplaetze, Aktiv, Notizen, Anzeigenfarbe';

    // 1) Basis-Select
    final base = Supa.client.from('Fahrzeuge').select(sel);

    // 2) Filter bauen
    final withAktiv = onlyActive ? base.eq('Aktiv', true) : base;
    final withEinr = (einrRowId != null && einrRowId > 0)
        ? withAktiv.eq('"Einrichtungen row_id"', einrRowId)
        : withAktiv;

    // 3) Sortierung
    final ordered = withEinr
        .order('Fahrzeug Kurz', ascending: true)
        .order('Kennzeichen', ascending: true);

    // 4) Abrufen
    final res = await ordered;
    final rows = List<Map<String, dynamic>>.from((res as List?) ?? const []);

    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final anyId = r['row_id'];
      final rowId = (anyId is num)
          ? anyId.toInt()
          : int.tryParse('${anyId ?? 0}') ?? 0;
      if (rowId <= 0) continue;

      final aktiv = r['Aktiv'] is bool
          ? (r['Aktiv'] as bool)
          : ('${r['Aktiv'] ?? ''}'.toLowerCase() == 'true');
      if (onlyActive && !aktiv) continue;

      final kurz = ('${r['Fahrzeug Kurz'] ?? ''}').trim();
      final bez = ('${r['Bezeichnung'] ?? ''}').trim();
      final kennz = ('${r['Kennzeichen'] ?? ''}').trim();
      final sitz = r['Sitzplaetze'];
      final sitzplaetze = (sitz is num)
          ? sitz.toInt()
          : int.tryParse('${sitz ?? ''}');
      final hex = ('${r['Anzeigenfarbe'] ?? ''}').trim();
      final einr = r['Einrichtungen row_id'];
      final einrId = (einr is num)
          ? einr.toInt()
          : int.tryParse('${einr ?? ''}');
      final notes = ('${r['Notizen'] ?? ''}');

      // Map 1:1 kompatibel zur UI
      out.add({
        'row_id': rowId,
        'Fahrzeug Kurz': kurz,
        'bezeichnung': bez,
        'name': bez,
        'kennzeichen': kennz,
        'sitzplaetze': sitzplaetze, // <- UI-Key (ohne Umlaut)
        'anzeigenfarbe': hex.isEmpty ? null : hex,
        'Einrichtungen row_id': einrId,
        'notizen': notes.isEmpty ? null : notes,
        'aktiv': aktiv,
      });
    }

    debugPrint('[Supa.Fahrzeuge] fetched ${out.length} rows');
    return out;
  }

  // --- Auto-Refresh: Listener-Mechanik für Fahrzeuge -----------------------

  /// Registrierte Listener aus der UI
  final List<ClientChangeListener> _vehicleListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-"Fahrzeuge"-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _vehicleStreamSub;

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    _vehicleListeners.add(listener);
    _ensureVehicleStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _vehicleListeners.remove(listener);
    if (_vehicleListeners.isEmpty) {
      _vehicleStreamSub?.cancel();
      _vehicleStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Fahrzeuge-Tabelle läuft.
  void _ensureVehicleStream() {
    if (_vehicleStreamSub != null) return;

    debugPrint('[Supa.Fahrzeuge] Starte Stream auf Tabelle "Fahrzeuge"');

    _vehicleStreamSub = Supa.client
        .from('Fahrzeuge')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            debugPrint(
              '[Supa.Fahrzeuge] Stream-Update: rows=${rows.length} -> benachrichtige Listener (${_vehicleListeners.length})',
            );

            final listenersCopy = List<ClientChangeListener>.from(
              _vehicleListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint('[Supa.Fahrzeuge] Listener-Fehler: $e\n$st');
              }
            }
          },
          onError: (error, st) {
            debugPrint(
              '[Supa.Fahrzeuge] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _vehicleStreamSub?.cancel();
            _vehicleStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik --------------------------------
}

// ---------------- Klienten ----------------
class _SupaKlientenAdapter {
  final cli = Supa.client;

  // ---- Helpers --------------------------------------------------------------

  // tolerant: "Ja"/"Nein", true/false, 1/0, "1"/"0"
  bool _toBoolFlexible(dynamic v) {
    if (v is bool) return v;
    final s = '${v ?? ''}'.trim().toLowerCase();
    return s == 'ja' || s == 'true' || s == '1' || s == 'yes';
  }

  String _toJaNein(dynamic v) => _toBoolFlexible(v) ? 'Ja' : 'Nein';

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  /// Wandelt beliebige Eingaben in "saubere" Strings um:
  /// - null, "" und "EMPTY" (egal welche Groß/Kleinschreibung) -> null
  /// - sonst: getrimmter String
  String? _cleanText(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    if (s.toUpperCase() == 'EMPTY') return null;
    return s;
  }

  /// Normalisiert App-Row -> DB-Row (konvertiert Ja/Nein zu bool, Einr-ID zu int)
  Map<String, dynamic> _normalizeRow(
    Map<String, dynamic> row, {
    bool forInsert = false,
  }) {
    // defensive read mit Null-Schutz
    final map = <String, dynamic>{};

    // row_id nur bei Update/Upsert verwenden
    final rawRowId = row['row_id'];
    if (!forInsert && rawRowId != null) {
      final rid = _toIntOrNull(rawRowId);
      if (rid != null) map['row_id'] = rid;
    }

    // Textfelder: leer oder "EMPTY" -> null
    map['Name'] = _cleanText(row['Name']);
    map['Vorname'] = _cleanText(row['Vorname']);
    map['Adresse'] = _cleanText(row['Adresse']);
    map['Ortsteil'] = _cleanText(row['Ortsteil']);
    map['Telefon'] = _cleanText(row['Telefon']);
    map['Angehörige'] = _cleanText(row['Angehörige']);
    map['Angehörige Tel.'] = _cleanText(row['Angehörige Tel.']);
    map['Betreuer'] = _cleanText(row['Betreuer']);
    map['Betreuer Tel.'] = _cleanText(row['Betreuer Tel.']);
    map['Besonderheiten'] = _cleanText(row['Besonderheiten']);
    map['Infos zur Wohnsituation'] = _cleanText(row['Infos zur Wohnsituation']);
    map['Tagespflege (Wochentage)'] = _cleanText(
      row['Tagespflege (Wochentage)'],
    );
    // ACHTUNG: Feldname exakt mit Leerzeichen
    map['Hilfe bei'] = _cleanText(row['Hilfe bei']);
    map['Schlüssel'] = _cleanText(row['Schlüssel']);
    map['Klingelzeichen'] = _cleanText(row['Klingelzeichen']);
    map['Sonstige Informationen'] = _cleanText(row['Sonstige Informationen']);

    // Booleans (RS, Aktiv, Fahrdienst) robust konvertieren
    map['RS'] = _toBoolFlexible(row['RS']);
    map['Aktiv'] = _toBoolFlexible(row['Aktiv']);
    map['Fahrdienst'] = _toBoolFlexible(row['Fahrdienst']);

    // optionale Felder
    if (row.containsKey('Nr.')) {
      final n = _toIntOrNull(row['Nr.']);
      map['Nr.'] = n;
    }

    // Einrichtung
    final einr = _toIntOrNull(row['Einrichtungen row_id']);
    map['Einrichtungen row_id'] = einr;

    return map;
  }

  // ---- Public API -----------------------------------------------------------

  // --- Auto-Refresh: Listener-Mechanik für Klienten -------------------

  // --- Auto-Refresh: Listener-Mechanik für Klienten -------------------

  /// Registrierte Listener aus der UI (z.B. HomePageState)
  final List<ClientChangeListener> _clientListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-Klienten-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _clientStreamSub;

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    // Schutz: denselben Listener nicht mehrfach registrieren
    if (_clientListeners.contains(listener)) {
      debugPrint('[Supa.Klienten] Listener bereits registriert – überspringe.');
      return;
    }

    _clientListeners.add(listener);
    _ensureClientStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _clientListeners.remove(listener);
    if (_clientListeners.isEmpty) {
      _clientStreamSub?.cancel();
      _clientStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Klienten-Tabelle läuft.
  void _ensureClientStream() {
    // Wenn schon ein Stream läuft -> nichts tun
    if (_clientStreamSub != null) return;

    debugPrint('[Supa.Klienten] Starte Stream auf Tabelle "Klienten"');

    _clientStreamSub = Supa.client
        .from('Klienten')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            // rows enthält immer den aktuellen Snapshot der Tabelle.
            debugPrint(
              '[Supa.Klienten] Stream-Update: rows=${rows.length} -> '
              'benachrichtige Listener (${_clientListeners.length})',
            );

            // Kopie der Liste, damit Änderungen während des Iterierens nicht krachen
            final listenersCopy = List<ClientChangeListener>.from(
              _clientListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint(
                  '[Supa.Klienten] Fehler im ClientChangeListener: $e\n$st',
                );
              }
            }
          },
          onError: (Object error, StackTrace st) {
            debugPrint(
              '[Supa.Klienten] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _clientStreamSub?.cancel();
            _clientStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik ---------------------------

  // --- Ende Auto-Refresh: Listener-Mechanik ---------------------------

  /// Minimale Datensätze für Listen/Bearbeiten laden (clientseitig filtern/sortieren)
  Future<List<Map<String, dynamic>>> fetchClientsForList({
    int? einrRowId,
  }) async {
    await AppAuth.ensureSignedIn();

    final res = await cli
        .from('Klienten')
        .select(
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
          '"Hilfe bei", ' // <-- exakt mit Leerzeichen!
          'Fahrdienst, '
          'Schlüssel, Klingelzeichen, "Sonstige Informationen"',
        )
        .order('Name', ascending: true);

    final list = List<Map<String, dynamic>>.from((res as List?) ?? const []);

    // nur aktive
    Iterable<Map<String, dynamic>> filtered = list.where(
      (r) => _toBoolFlexible(r['Aktiv']) == true,
    );

    // optional Einrichtung
    if (einrRowId != null && einrRowId > 0) {
      filtered = filtered.where((r) {
        final v = _toIntOrNull(r['Einrichtungen row_id']);
        return v == einrRowId;
      });
    }

    final out = filtered.toList(growable: false)
      ..sort(
        (a, b) => ('${a['Name'] ?? ''}'.toLowerCase()).compareTo(
          '${b['Name'] ?? ''}'.toLowerCase(),
        ),
      );

    return out;
  }

   Future<Map<int, String>> fetchClientNameMap() async {
    await AppAuth.ensureSignedIn();

    int? einrId;
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString('einrichtung_row_id')?.trim();
      if (s != null && s.isNotEmpty) einrId = int.tryParse(s);
    } catch (_) {}

    var res = await cli
        .from('Klienten')
        .select('row_id, Name, Vorname, Aktiv, Fahrdienst')
        .order('Name', ascending: true);

    final list = List<Map<String, dynamic>>.from((res as List?) ?? const []);
    Iterable<Map<String, dynamic>> filtered = list.where(
      (r) => _toBoolFlexible(r['Aktiv']) == true,
    );

    if (einrId != null) {
      // wir haben in dieser leichten Abfrage nicht die Einr-Spalte mitgeholt → extra Query wäre möglich,
      // aber für NameMap reicht „alle aktiv“. Wenn du hier filtern willst, nimm die große Abfrage oben.
    }

    final map = <int, String>{};
    final fahrMap = <int, bool>{};

    for (final r in filtered) {
      final id = _toIntOrNull(r['row_id']);
      if (id == null || id <= 0) continue;

      final n = '${r['Name'] ?? ''}'.trim();
      final v = '${r['Vorname'] ?? ''}'.trim();
      final nv = [n, v].where((e) => e.isNotEmpty).join(' ').trim();
      if (nv.isNotEmpty) {
        map[id] = nv;
      }

      // Fahrdienst-Flag: null => true (Standard: fährt mit)
      final rawFd = r['Fahrdienst'];
      final fd = rawFd == null ? true : _toBoolFlexible(rawFd);
      fahrMap[id] = fd;
    }

    // Globale Map im AppBus setzen (für UI-Darstellung wie Durchstreichen)
    AppBus.clientFahrdienstMap = fahrMap;

    return map;
  }

  Future<String> insertClient(Map<String, dynamic> row) async {
    await AppAuth.ensureSignedIn();

    // 1) Versuchen, eine Einrichtungen-ID aus der übergebenen Row zu lesen
    int? einrId = _toIntOrNull(row['Einrichtungen row_id']);

    // 2) Falls keine sinnvolle ID vorhanden: aus SharedPreferences lesen
    if (einrId == null || einrId <= 0) {
      try {
        final sp = await SharedPreferences.getInstance();
        final s = sp.getString('einrichtung_row_id')?.trim();
        if (s != null && s.isNotEmpty) {
          final parsed = int.tryParse(s);
          if (parsed != null && parsed > 0) {
            einrId = parsed;
            debugPrint(
              '[Supa.Klienten] insertClient: Einrichtungen-ID aus SharedPreferences = $einrId',
            );
          }
        }
      } catch (e, st) {
        debugPrint(
          '[Supa.Klienten] insertClient: Fehler beim Lesen von einrichtung_row_id aus SharedPreferences: $e\n$st',
        );
      }
    }

    // 3) Falls immer noch keine ID: erste aktive Einrichtung aus der DB holen
    if (einrId == null || einrId <= 0) {
      try {
        final res = await cli
            .from('Einrichtungen')
            .select('row_id, "Aktiv"')
            .eq('Aktiv', true)
            .order('row_id', ascending: true)
            .limit(1);

        if (res is List && res.isNotEmpty) {
          final raw = res.first['row_id'];
          final candidate = _toIntOrNull(raw);
          if (candidate != null && candidate > 0) {
            einrId = candidate;
            debugPrint(
              '[Supa.Klienten] insertClient: Einrichtungen-ID aus DB = $einrId',
            );

            // einmalig in SharedPreferences merken, damit weitere Inserts sie direkt nutzen
            try {
              final sp = await SharedPreferences.getInstance();
              await sp.setString('einrichtung_row_id', '$einrId');
            } catch (e, st) {
              debugPrint(
                '[Supa.Klienten] insertClient: Fehler beim Schreiben von einrichtung_row_id in SharedPreferences: $e\n$st',
              );
            }
          }
        } else {
          debugPrint(
            '[Supa.Klienten] insertClient: keine aktive Einrichtung in der Tabelle "Einrichtungen" gefunden.',
          );
        }
      } catch (e, st) {
        debugPrint(
          '[Supa.Klienten] insertClient: Fehler beim Lesen aus "Einrichtungen": $e\n$st',
        );
      }
    }

    // 4) Wenn wir jetzt eine brauchbare ID haben, sicherheitshalber in die Row schreiben
    if (einrId != null && einrId > 0) {
      // Kopie der Map anlegen, um Seiteneffekte zu vermeiden
      row = Map<String, dynamic>.from(row);
      row['Einrichtungen row_id'] = einrId;
    } else {
      debugPrint(
        '[Supa.Klienten] insertClient: KEINE gültige Einrichtungen row_id gefunden – '
        'Insert erfolgt ohne FK. (Feld ist bei dir derzeit NULL-able, sonst gäbe es einen Constraint-Fehler.)',
      );
    }

    // 5) Normalisierung (inkl. EMPTY -> null)
    final prepared = _normalizeRow(row, forInsert: true);

    final inserted = await cli
        .from('Klienten')
        .insert(prepared)
        .select('row_id')
        .single();

    final rid = _toIntOrNull(inserted['row_id']) ?? 0;
    return '$rid';
  }

  /// Update per row_id
  Future<void> updateClient(int rowId, Map<String, dynamic> row) async {
    await AppAuth.ensureSignedIn();
    final prepared = _normalizeRow(row);
    await cli.from('Klienten').update(prepared).eq('row_id', rowId);
  }

  /// Upsert (falls du das zentral nutzen möchtest)
  Future<String> upsertClient(Map<String, dynamic> row) async {
    final rid = _toIntOrNull(row['row_id']);
    if (rid == null || rid <= 0) {
      return await insertClient(row);
    } else {
      await updateClient(rid, row);
      return '$rid';
    }
  }

  /// Delete per row_id
  Future<void> deleteClient(int rowId) async {
    await AppAuth.ensureSignedIn();
    await cli.from('Klienten').delete().eq('row_id', rowId);
  }

  // ---- Beispiele/weitere Querys (unverändert, falls bei dir vorhanden) ----

  /// Alle aktiven Klienten einer Einrichtung (optional beibehalten)
  Future<List<Map<String, dynamic>>> fetchByEinrichtung(int einrRowId) async {
    await AppAuth.ensureSignedIn();
    final data = await cli
        .from('Klienten')
        .select('*')
        .eq('Einrichtungen row_id', einrRowId)
        .eq('Aktiv', true)
        .order('Name', ascending: true);
    return List<Map<String, dynamic>>.from((data as List?) ?? const []);
  }

  /// Suche in Name/Vorname innerhalb einer Einrichtung (optional beibehalten)
  Future<List<Map<String, dynamic>>> searchByEinrichtung(
    int einrRowId,
    String query,
  ) async {
    await AppAuth.ensureSignedIn();
    final qstr = query.trim();
    if (qstr.isEmpty) return fetchByEinrichtung(einrRowId);

    final data = await cli
        .from('Klienten')
        .select('*')
        .eq('Einrichtungen row_id', einrRowId)
        .eq('Aktiv', true)
        .or('Name.ilike.%$qstr%,Vorname.ilike.%$qstr%')
        .order('Name', ascending: true);
    return List<Map<String, dynamic>>.from((data as List?) ?? const []);
  }

  Future<Map<String, dynamic>?> fetchById(int rowId) async {
    await AppAuth.ensureSignedIn();
    final res = await cli
        .from('Klienten')
        .select('*')
        .eq('row_id', rowId)
        .maybeSingle();
    return (res == null) ? null : Map<String, dynamic>.from(res as Map);
  }
}

class _SupaTagesplanAdapter {
  Future<void> insertClientsForDateSimple({
    required DateTime date,
    required List<int> clientIds,
  }) async {
    if (clientIds.isEmpty) return;

    await AppAuth.ensureSignedIn();

    final iso = date.toIso8601String().split('T').first;

    final rows = <Map<String, dynamic>>[];

    for (final cid in clientIds) {
      if (cid <= 0) continue;
      rows.add({'Datum': iso, 'Klienten row_id': cid});
    }

    if (rows.isEmpty) return;

    debugPrint(
      '[SupaTagesplanAdapter.insertClientsForDateSimple] '
      'date=$iso, count=${rows.length}',
    );

    await Supa.client.from('Tagesplan').insert(rows);
  }

  Future<void> deleteRowsByIds(List<int> rowIds) async {
    if (rowIds.isEmpty) return;

    await AppAuth.ensureSignedIn();

    debugPrint('[SupaTagesplanAdapter.deleteRowsByIds] rowIds=$rowIds');

    // Deine Postgrest-Version kennt .in_ offenbar nicht → wir löschen einfach pro ID
    for (final id in rowIds) {
      if (id <= 0) continue;
      await Supa.client.from('Tagesplan').delete().eq('row_id', id);
    }
  }
  // ==================== Tagesplan laden ====================
  Future<List<Map<String, dynamic>>> fetchDayPlan(
    DateTime date, {
    required bool morning,
  }) async {
    await AppAuth.ensureSignedIn();

    final iso = date.toIso8601String().split('T').first;
    final vehCol = morning
        ? 'Fahrzeuge row_id Morgen'
        : 'Fahrzeuge row_id Abend';
    final ordCol = morning ? 'Reihenfolge Morgen' : 'Reihenfolge Abend';

    debugPrint(
      '[SupaTagesplanAdapter.fetchDayPlan] date=$iso morning=$morning',
    );

    // Wichtig: die Leerzeichen-Spaltentitel EXAKT angeben
    final sel =
        'row_id, "Klienten row_id", "$vehCol", "$ordCol", Bemerkung, Klienten (Name, Vorname)';

    // WICHTIG: immer den supabase_flutter-Client verwenden
    final List<dynamic> raw = await client
        .from('Tagesplan')
        .select(sel)
        .eq('Datum', iso) // falls deine Spalte anders heißt, hier anpassen
        .order('row_id', ascending: true);

    // Map in neutrales Format für main.dart
    final out = <Map<String, dynamic>>[];

    for (final r in raw) {
      final m = Map<String, dynamic>.from(r as Map);

      final name = (m['Klienten']?['Name'] ?? '').toString().trim();
      final vor = (m['Klienten']?['Vorname'] ?? '').toString().trim();
      final disp = (name.isNotEmpty || vor.isNotEmpty)
          ? '$name, $vor'.trim()
          : null;

      out.add({
        'row_id': m['row_id'],
        'Klienten row_id': m['Klienten row_id'],
        vehCol: m[vehCol], // <- EXAKT die Spaltennamen verwenden
        ordCol: m[ordCol],
        'Bemerkung': m['Bemerkung'],
        '_display': disp ?? 'Klient ${m['Klienten row_id'] ?? ''}',
      });
    }

    debugPrint(
      '[SupaTagesplanAdapter.fetchDayPlan] done count=${out.length} '
      'sample=${out.take(3).toList()}',
    );
    return out;
  }

  // --- Auto-Refresh: Listener-Mechanik für Tagesplan -----------------------

  /// Registrierte Listener aus der UI
  final List<ClientChangeListener> _dayPlanListeners = [];

  /// Aktive Stream-Subscription auf die Supabase-"Tagesplan"-Tabelle
  StreamSubscription<List<Map<String, dynamic>>>? _dayPlanStreamSub;

  /// Listener registrieren – startet bei Bedarf den Stream.
  void addChangeListener(ClientChangeListener listener) {
    _dayPlanListeners.add(listener);
    _ensureDayPlanStream();
  }

  /// Listener wieder entfernen – stoppt den Stream, wenn keiner mehr zuhört.
  void removeChangeListener(ClientChangeListener listener) {
    _dayPlanListeners.remove(listener);
    if (_dayPlanListeners.isEmpty) {
      _dayPlanStreamSub?.cancel();
      _dayPlanStreamSub = null;
    }
  }

  /// Stellt sicher, dass der Stream auf die Tagesplan-Tabelle läuft.
  void _ensureDayPlanStream() {
    if (_dayPlanStreamSub != null) return;

    debugPrint('[Supa.Tagesplan] Starte Stream auf Tabelle "Tagesplan"');

    _dayPlanStreamSub = Supa.client
        .from('Tagesplan')
        .stream(primaryKey: ['row_id'])
        .listen(
          (rows) {
            debugPrint(
              '[Supa.Tagesplan] Stream-Update: rows=${rows.length} -> benachrichtige Listener (${_dayPlanListeners.length})',
            );

            final listenersCopy = List<ClientChangeListener>.from(
              _dayPlanListeners,
            );
            for (final l in listenersCopy) {
              try {
                l();
              } catch (e, st) {
                debugPrint('[Supa.Tagesplan] Listener-Fehler: $e\n$st');
              }
            }
          },
          onError: (error, st) {
            debugPrint(
              '[Supa.Tagesplan] Stream-Fehler: $error\n$st\n'
              '-> Stoppe Stream, versuche bei nächster Listener-Registrierung neu.',
            );
            _dayPlanStreamSub?.cancel();
            _dayPlanStreamSub = null;
          },
        );
  }

  // --- Ende Auto-Refresh: Listener-Mechanik --------------------------------
}

// ==================== Tagesplan: Speichern ====================
extension on String {
  bool get isBlank => trim().isEmpty;
}

// =============== Bridge: gleiche API wie SheetsClient ===============
class SupaSheetsAdapter {
  // --- Datums-Helper ohne Flutter DateUtils ---
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  // === REPLACEMENT 1: kleine Helfer OHNE DateUtils ===
  String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // --------- kleine Kompat-Helper ---------
  dynamic _supaEq(dynamic q, String column, dynamic value) {
    try {
      return q.eq(column, value); // neue SDKs
    } catch (_) {
      return q.filter(column, 'eq', value); // ältere SDKs
    }
  }

  dynamic _supaOrder(dynamic q, String column, {bool ascending = true}) {
    try {
      return q.order(column, ascending: ascending);
    } catch (_) {
      try {
        return q.order(column); // ältere Signatur
      } catch (_) {
        return q; // no-op
      }
    }
  }

  // ---------------------------------------------------------------
  // Fahrzeuge
  // ---------------------------------------------------------------
  Future<List<dynamic>> fetchVehicles({
    int? einrRowId,
    bool onlyActive = true,
  }) async {
    debugPrint(
      '[SupaSheetsAdapter] fetchVehicles(einrRowId=$einrRowId, onlyActive=$onlyActive)',
    );
    await AppAuth.ensureSignedIn();

    // Einrichtungs-ID ggf. aus SP holen
    if (einrRowId == null || einrRowId <= 0) {
      try {
        final sp = await SharedPreferences.getInstance();
        final s = sp.getString('einrichtung_row_id') ?? '';
        final v = int.tryParse(s);
        if (v != null && v > 0) einrRowId = v;
      } catch (_) {}
    }

    final rows = await SupaAdapter.fahrzeuge.fetchVehicles(
      einrRowId: einrRowId,
      onlyActive: onlyActive,
    );

    debugPrint('[SupaSheetsAdapter] fetchVehicles -> ${rows.length} rows');
    return rows;
  }

  // ---------------------------------------------------------------
  // Tagesplan - Lesen
  // ---------------------------------------------------------------
  /// Liefert DayPlanRows für [date]. Wenn [morning] true: M-Felder, sonst A-Felder.

  // ---------------------------------------------------------------
  // Tagesplan - Speichern
  // ---------------------------------------------------------------
  /// Speichert die **aktuell sichtbare** Auswahl (M oder A) zurück.
  /// Wir aktualisieren die passenden M/A-Spalten + Bemerkung und setzen Audit-Felder

  // Bridge: fetchDayPlan (Map-DTO) – delegiert an SupaAdapter.tagesplan
  Future<List<Map<String, dynamic>>> fetchDayPlan(
    DateTime date, {
    required bool morning,
  }) async {
    debugPrint(
      '[SupaSheetsAdapter.fetchDayPlan] date=${_isoDateOnly(date)} morning=$morning',
    );
    return await SupaAdapter.tagesplan.fetchDayPlan(date, morning: morning);
  }

  // In class SupaSheetsAdapter
  Future<void> saveDayPlan(
    DateTime date,
    List<dynamic> entries, {
    required bool morning,
  }) async {
    await AppAuth.ensureSignedIn();

    final vehCol = morning
        ? 'Fahrzeuge row_id Morgen'
        : 'Fahrzeuge row_id Abend';
    final ordCol = morning ? 'Reihenfolge Morgen' : 'Reihenfolge Abend';

    int _asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    int? _asIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    String _iso(DateTime d) => d.toIso8601String().split('T').first;
    debugPrint(
      '[SupaSheetsAdapter.saveDayPlan] date=${_iso(date)} count=${entries.length} morning=$morning',
    );

  
      for (final e in entries) {
      // --- 1) rowId herausziehen ---
      int rowId;
      if (e is Map) {
        rowId = _asInt(e['row_id'] ?? e['RowId'] ?? e['id']);
      } else {
        // _Entry (aus main)
        rowId = _asInt((e as dynamic).rowId);
      }

      // --- 2) Fahrzeug-ID robust lesen ---
      int? vehId;
      if (e is Map) {
        // bevorzugt die generische 'veh' (vom main-Payload),
        // sonst die bereits normalisierten Spaltennamen:
        vehId = _asIntOrNull(
          e['veh'] ??
              e[vehCol] ??
              e['fahrzeuge_row_id'] ??
              e['Fahrzeuge row_id'], // falls jemand mal ohne Morgen/Abend schrieb
        );
      } else {
        vehId = _asIntOrNull((e as dynamic).vehicleRowId);
      }

      // --- 3) Reihenfolge robust lesen ---
      int? ord;
      if (e is Map) {
        ord = _asIntOrNull(
          (morning ? e['ordM'] : e['ordA']) ??
              e[ordCol] ??
              e['order'] ??
              e['Order'],
        );
      } else {
        ord = _asIntOrNull((e as dynamic).order);
      }

      // --- 4) Bemerkung aus Payload lesen ---
      String? remark;
      if (e is Map) {
        // aus main.dart: 'bemerkung': (e.note ?? '').toString()
        final raw = e['bemerkung'] ?? e['Bemerkung'];
        if (raw != null) {
          remark = raw.toString().trim();
        }
      } else {
        // falls irgendwann ein DayPlanRow/SupaDayPlanRow o.Ä. direkt reinkommt
        try {
          final dyn = e as dynamic;
          final raw = dyn.bemerkung ?? dyn.note;
          if (raw != null) {
            remark = raw.toString().trim();
          }
        } catch (_) {
          // ignorieren, dann bleibt remark null
        }
      }
      // leere Bemerkung erlaubt – überschreibt alte Werte
      remark = (remark ?? '').trim();

      // --- 5) Editor-/Geräteinfos (falls im AppBus vorhanden, sonst leer) ---
      final editor = AppBus.editorName ?? '';
      final devName = AppBus.deviceName ?? '';
      final devId = AppBus.deviceId ?? '';
      final devModel = AppBus.deviceModel ?? '';

      // Nur die beabsichtigten Spalten schreiben
      final toWrite = <String, dynamic>{
        vehCol: vehId, // darf null sein (setzt in DB auf NULL)
        ordCol: ord,   // darf null sein
        'Bemerkung': (remark.isEmpty ? null : remark), // <-- NEU: Bemerkung wird immer mitgeschrieben
        'last_editor': editor,
        'last_editor_device': devName,
        'last_editor_device_id': devId,
        // 'last_editor_device_name': devModel, // nur falls du diese Spalte hast
      };

      debugPrint(
        '[SupaSheetsAdapter.saveDayPlan] UPDATE row_id=$rowId keys=[${toWrite.keys.join(', ')}]',
      );

      await Supa.client
          .from('Tagesplan')
          .update(toWrite)
          .eq('row_id', rowId as Object);
    }


    debugPrint('[SupaSheetsAdapter.saveDayPlan] done');
  }

  // ---------------------------------------------------------------
  // Klienten / Mitarbeitende
  // ---------------------------------------------------------------
  Future<Map<int, String>> fetchClientNameMap() async {
    // "row_id -> Name Vorname"
    final map = await SupaAdapter.klienten.fetchClientNameMap();
    debugPrint(
      '[SupaSheetsAdapter] fetchClientNameMap -> ${map.length} entries',
    );
    return map;
  }

  Future<List<String>> fetchEmployeeNameList() async {
    final list = await SupaAdapter.mitarbeiter.fetchEmployeeNameList();
    debugPrint('[SupaSheetsAdapter] fetchEmployeeNameList -> ${list.length}');
    return list;
  }

  Future<String?> fetchOwnDisplayNameByAuthId() async {
    final n = await SupaAdapter.mitarbeiter.fetchOwnDisplayNameByAuthId();
    debugPrint(
      '[SupaSheetsAdapter] fetchOwnDisplayNameByAuthId -> "${n ?? '-'}"',
    );
    return n;
  }

  // ---------------------------------------------------------------
  // Klienten-Liste (für Such-/Auswahl-Views)
  // ---------------------------------------------------------------
  Future<List<Map<String, dynamic>>> fetchClientsForList({
    int? einrRowId,
  }) async {
    await AppAuth.ensureSignedIn();

    final res = await Supa.client
        .from('Klienten')
        .select(
          'row_id, '
          '"Einrichtungen row_id", '
          'Aktiv, Fahrdienst, "RS", '
          '"Nr.", Name, Vorname, '
          'Adresse, Ortsteil, Telefon, '
          '"Angehörige", "Angehörige Tel.", '
          'Betreuer, "Betreuer Tel.", '
          '"Hilfe bei", '
          'Schlüssel, Klingelzeichen, "Sonstige Informationen", '
          '"Infos zur Wohnsituation", '
          '"Tagespflege (Wochentage)"',
        )
        .order('Name', ascending: true);

    final list = List<Map<String, dynamic>>.from(res as List? ?? const []);
    final out = <Map<String, dynamic>>[];

    for (final r in list) {
      final a = r['Aktiv'];
      final isActive = (a is bool)
          ? a
          : (a?.toString().toLowerCase() == 'true');
      if (isActive != true) continue;

      if (einrRowId != null && einrRowId > 0) {
        final anyEinr = r['Einrichtungen row_id'];
        final rid = (anyEinr is num)
            ? anyEinr.toInt()
            : int.tryParse('${anyEinr ?? ''}');
        if (rid != einrRowId) continue;
      }
      out.add(r);
    }
    debugPrint('[SupaSheetsAdapter] fetchClientsForList -> ${out.length} rows');
    return out;
  }

  // ---------------------------------------------------------------
  // Zentrale/Einrichtung lesen/schreiben
  // ---------------------------------------------------------------
  Future<Map<String, String>> readConfig() async {
    await AppAuth.ensureSignedIn();

    dynamic q = Supa.client.from('Einrichtungen').select('*').limit(1);
    try {
      q = _supaEq(q, 'Aktiv', true);
    } catch (_) {}
    final res = await q;
    final list = res as List<dynamic>? ?? const [];
    if (list.isEmpty) return {};
    final row = Map<String, dynamic>.from(list.first as Map);

    String _pick(List<String> keys) {
      for (final k in keys) {
        final found = row.entries.firstWhere(
          (e) => ('${e.key}'.trim().toLowerCase() == k),
          orElse: () => const MapEntry<String, dynamic>('', null),
        );
        if (found.key.isNotEmpty) {
          final v = '${found.value ?? ''}'.trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    final out = <String, String>{
      'name': _pick(['name der einrichtung', 'name', 'einrichtungsname']),
      'address': _pick(['adresse der einrichtung', 'adresse', 'anschrift']),
      'phone1': _pick([
        'telefonnummer der einrichtung 1',
        'telefon 1',
        'telefon1',
        'phone1',
        'telefonnummer 1',
        'telefon',
      ]),
      'phone2': _pick([
        'telefonnummer der einrichtung 2',
        'telefon 2',
        'telefon2',
        'phone2',
      ]),
      'phone3': _pick([
        'telefonnummer der einrichtung 3',
        'telefon 3',
        'telefon3',
        'phone3',
      ]),
    };

    final rid = row['row_id']?.toString();
    if (rid != null && rid.trim().isNotEmpty) out['row_id'] = rid.trim();

    out.removeWhere((k, v) => v.trim().isEmpty);
    return out;
  }

  Future<void> writeConfig({
    String? name,
    String? address,
    String? phone1,
    String? phone2,
    String? phone3,
  }) async {
    await AppAuth.ensureSignedIn();

    final sp = await SharedPreferences.getInstance();
    int? rowId;
    try {
      final s = sp.getString('einrichtung_row_id');
      if (s != null && s.isNotEmpty) rowId = int.tryParse(s);
    } catch (_) {}

    Map<String, dynamic>? current;
    if (rowId != null) {
      current = await SupaAdapter.einrichtungen.fetchById(rowId!);
    }
    if (current == null) {
      final list = await SupaAdapter.einrichtungen.fetchAllActive();
      if (list.isNotEmpty) {
        current = list.first;
        final rid = current['row_id'];
        rowId = (rid is int) ? rid : int.tryParse('$rid');
        if (rowId != null) await sp.setString('einrichtung_row_id', '$rowId');
      }
    }
    if (current == null || rowId == null) {
      debugPrint('[Supa.Einr] writeConfig: kein Eintrag gefunden – Abbruch');
      return;
    }

    String _resolve(List<String> candidates) {
      final lc = {
        for (final k in current!.keys) k.toString().trim().toLowerCase(): k,
      };
      for (final c in candidates) {
        if (lc.containsKey(c)) return lc[c]!;
      }
      return candidates.first;
    }

    final patch = <String, dynamic>{};
    if (name != null) {
      patch[_resolve(['name der einrichtung', 'name', 'einrichtungsname'])] =
          name;
    }
    if (address != null) {
      patch[_resolve(['adresse der einrichtung', 'adresse', 'anschrift'])] =
          address;
    }
    if (phone1 != null) {
      patch[_resolve([
            'telefonnummer der einrichtung 1',
            'telefon 1',
            'telefon1',
            'phone1',
            'telefonnummer 1',
            'telefon',
          ])] =
          phone1;
    }
    if (phone2 != null) {
      patch[_resolve([
            'telefonnummer der einrichtung 2',
            'telefon 2',
            'telefon2',
            'phone2',
          ])] =
          phone2;
    }
    if (phone3 != null) {
      patch[_resolve([
            'telefonnummer der einrichtung 3',
            'telefon 3',
            'telefon3',
            'phone3',
          ])] =
          phone3;
    }

    if (patch.isEmpty) {
      debugPrint('[Supa.Einr] writeConfig: patch leer – nichts zu tun');
      return;
    }

    debugPrint(
      '[Supa.Einr] writeConfig: update row_id=$rowId keys=${patch.keys.toList()}',
    );
    await Supa.client.from('Einrichtungen').update(patch).eq('row_id', rowId);
    debugPrint('[Supa.Einr] writeConfig: ok');
  }

  // --------- kleine Helpers ----------
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    return '$v';
  }
}
