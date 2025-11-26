// lib/tabs_wrapper.dart
import 'package:flutter/material.dart';
import 'app_bus.dart';
import 'main.dart' show HomePage, TagesplanTab, DienstplanTab;
import 'package:flutter/services.dart'; // für HapticFeedback

class TabsWrapper extends StatefulWidget {
  const TabsWrapper({super.key});

  @override
  State<TabsWrapper> createState() => _TabsWrapperState();
}

class _TabsWrapperState extends State<TabsWrapper> {
  int _index = 0;

  // Startzustand des TPlan-Schalters: Morgen (M)
  bool _tplanIsMorning = true;

  // Keys für eingebettete Instanzen
  final GlobalKey _searchKey = GlobalKey(); // Klienten
  final GlobalKey _planKey = GlobalKey(); // Tagesplan
  final GlobalKey _dienstKey = GlobalKey(); // Dienstplan
  final GlobalKey _mapKey = GlobalKey(); // Route

  // Merker: Auto-Refresh pro Tab nur beim ersten Betreten ausführen
  bool _initialRefreshKlienten = false;
  bool _initialRefreshTagesplan = false;
  bool _initialRefreshRoute = false;
  bool _initialRefreshDienst = false;

  // ---------- Utility: sicheres Abrufen dynamischer Getter/Funktionen ----------
  T? _tryGet<T>(T Function() getter) {
    try {
      return getter();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    // Für Info-Panel-Refresh
    AppBus.infoRev.addListener(_onInfoChanged);

    // Optional: Toggle im Header mit internem Wechsel synchronisieren
    AppBus.onDayModeChanged = (bool isMorning) {
      if (!mounted) return;
      setState(() {
        _tplanIsMorning = isMorning;
      });
    };

    // *** WICHTIG: Bridge Tagesplan → Route (damit der Route-Button funktioniert) ***
    AppBus.toRouteWithText = (String text) {
      // Map-Tab State abfragen
      final st = _mapKey.currentState as dynamic; // HomePage (Map)
      // Sicher den Setter holen
      final Function? setFromWrapper = _tryGet<Function>(
        () => st.setRouteInputFromWrapper as Function,
      );
      if (setFromWrapper != null) {
        setFromWrapper(text); // Text in den Map-Tab setzen
        setState(() => _index = 2); // auf "Route" umschalten
      } else {
        // Optionales Debug
        debugPrint('[TabsWrapper] setRouteInputFromWrapper nicht verfügbar');
      }
    };
  }

  @override
  void dispose() {
    // Listener sauber lösen
    AppBus.infoRev.removeListener(_onInfoChanged);
    AppBus.onDayModeChanged = null;

    // Bridge zurücksetzen, um Dangling-Refs zu vermeiden
    AppBus.toRouteWithText = null;

    super.dispose();
  }

  void _onInfoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _triggerRefreshForCurrentTab() async {
    GlobalKey? targetKey;

    // Nur beim ersten Betreten eines Tabs automatisch refreshen
    bool shouldRun = false;

    if (_index == 0) {
      targetKey = _searchKey; // Klienten
      if (!_initialRefreshKlienten) {
        _initialRefreshKlienten = true;
        shouldRun = true;
      }
    } else if (_index == 1) {
      targetKey = _planKey; // Tag
      if (!_initialRefreshTagesplan) {
        _initialRefreshTagesplan = true;
        shouldRun = true;
      }
    } else if (_index == 2) {
      targetKey = _mapKey; // Route
      if (!_initialRefreshRoute) {
        _initialRefreshRoute = true;
        shouldRun = true;
      }
    } else if (_index == 3) {
      targetKey = _dienstKey; // Dienst
      if (!_initialRefreshDienst) {
        _initialRefreshDienst = true;
        shouldRun = true;
      }
    } else {
      return;
    }

    if (!shouldRun) {
      // Für diesen Tab wurde der Initial-Refresh schon ausgeführt.
      // Manuelles Aktualisieren geht weiter über den Refresh-Button
      // (AppBar) bzw. den Auto-Refresh-Timer (AppBus.onRefresh).
      return;
    }

    final st = targetKey.currentState as dynamic;
    if (st == null) return;

    final Function? refresh = _tryGet<Function>(
      () => st.refreshFromWrapper as Function,
    );

    if (refresh != null) {
      try {
        final res = Function.apply(refresh, const []);
        if (res is Future) {
          await res;
        }
      } catch (_) {}
    }
  }

  void _go(int i) {
    if (_index == i) return;

    setState(() {
      _index = i;
    });

    // Nach dem Umschalten den Tab-spezifischen Auto-Load anstoßen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerRefreshForCurrentTab();
    });
  }

  String _fmtDE(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  Widget _buildAppBarTitle() {
    String base;
    switch (_index) {
      case 0:
        base = 'Klienten';
        break;
      case 1:
        base = 'Tag';
        break;
      case 2:
        base = 'Route';
        break;
      case 3:
        base = 'Dienstplan';
        break;
      case 4:
        base = 'Information';
        break;
      default:
        base = 'Fahrdienst';
    }

    // Nur in den Tabs "Tag" (1) und "Dienst" (3) zeigen wir die Datumspille
    if (!(_index == 1 || _index == 3)) {
      return Text(
        base,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );
    }

    // zuständigen State für das Datum ermitteln
    GlobalKey? dateKey;
    if (_index == 1) {
      dateKey = _planKey; // Tag
    } else if (_index == 3) {
      dateKey = _dienstKey; // Dienst
    }

    // Datum vom jeweiligen Tab holen
    String dateText = '';
    final st = dateKey?.currentState as dynamic;
    if (st != null) {
      try {
        // 1. Versuch: echtes DateTime aus selectedDate
        DateTime? d = _tryGet<DateTime>(() => st.selectedDate as DateTime);
        if (d != null) {
          String two(int n) => n.toString().padLeft(2, '0');
          dateText = '${two(d.day)}.${two(d.month)}.${d.year}';
        } else {
          // 2. Versuch: fertiges deutsches Label aus selectedDateLabelDE
          final String? s = _tryGet<String>(
            () => st.selectedDateLabelDE as String,
          );
          if (s != null && s.trim().isNotEmpty) {
            dateText = s.trim();
          }
        }
      } catch (_) {}
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (dateText.isEmpty) {
      return Text(
        base,
        style: theme.textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            base,
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () async {
              final st = dateKey?.currentState as dynamic;
              if (st != null) {
                final Function? pick = _tryGet<Function>(
                  () => st.pickDateFromWrapper as Function,
                );
                final Function? pickLegacy = _tryGet<Function>(
                  () => st._pickDate as Function,
                );
                try {
                  if (pick != null) {
                    await Function.apply(pick, const []);
                  } else if (pickLegacy != null) {
                    await Function.apply(pickLegacy, const []);
                  }
                  if (mounted) setState(() {});
                } catch (_) {}
              }
            },
            onLongPress: () async {
              final st = dateKey?.currentState as dynamic;
              if (st != null) {
                final Function? goToday = _tryGet<Function>(
                  () => st.goToTodayFromWrapper as Function,
                );
                try {
                  if (goToday != null) {
                    await Function.apply(goToday, const []);
                    try {
                      HapticFeedback.selectionClick();
                    } catch (_) {}
                    if (mounted) setState(() {});
                  }
                } catch (_) {}
              }
            },
            onHorizontalDragEnd: (details) async {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() < 50) return;

              final int delta = (v > 0) ? -1 : 1;
              final st = dateKey?.currentState as dynamic;
              if (st != null) {
                final Function? changeBy = _tryGet<Function>(
                  () => st.changeDateByFromWrapper as Function,
                );
                try {
                  if (changeBy != null) {
                    await Function.apply(changeBy, [delta]);
                    try {
                      HapticFeedback.selectionClick();
                    } catch (_) {}
                    if (mounted) setState(() {});
                  }
                } catch (_) {}
              }
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outline, width: 1),
              ),
              child: Text(
                dateText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.95,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Umschalten M/A mit optionaler "Speichern?"-Abfrage aus dem Tagesplan-Tab
  Future<void> _toggleDayMode(bool wantMorning) async {
    // Kein Wechsel nötig?
    if (_tplanIsMorning == wantMorning) return;

    final st = _planKey.currentState as dynamic;

    // 1) Vorab: "Speichern?"-Abfrage anbieten, wenn der Tab das kann
    bool ok = true;
    try {
      if (st != null) {
        final Function? maybeSave = _tryGet<Function>(
          () => st.maybePromptSaveBeforeContextChange as Function,
        );
        final Function? requestSaveIfDirty = _tryGet<Function>(
          () => st.requestSavePromptIfDirty as Function,
        );
        final Function? requestModeChangeBool = _tryGet<Function>(
          () => st.requestModeChange as Function,
        ); // wir versuchen mit bool

        if (maybeSave != null) {
          ok =
              (await (Function.apply(maybeSave, const []) as Future<bool?>)) ==
              true;
        } else if (requestSaveIfDirty != null) {
          ok =
              (await (Function.apply(requestSaveIfDirty, const [])
                  as Future<bool?>)) ==
              true;
        } else if (requestModeChangeBool != null) {
          // falls deine Methode einen bool akzeptiert
          try {
            final res =
                await (Function.apply(requestModeChangeBool, [wantMorning])
                    as Future<bool?>);
            ok = (res == true);
          } catch (_) {
            ok = true;
          } // tolerant
        }
      }
    } catch (_) {}
    if (!ok) return;

    // 2) UI-Status sofort umschalten
    setState(() {
      _tplanIsMorning = wantMorning;
    });

    // 3) Modus im Tagesplan-Tab anwenden
    try {
      if (st != null) {
        final Function? toggle = _tryGet<Function>(
          () => st.toggleMorningEveningFromWrapper as Function,
        );
        final Function? setDayMode = _tryGet<Function>(
          () => st.setDayMode as Function,
        );

        if (toggle != null) {
          await (Function.apply(toggle, const [], {#toMorning: wantMorning})
              as Future?);
        } else if (setDayMode != null) {
          // Einige Implementierungen könnten bool akzeptieren
          try {
            await (Function.apply(setDayMode, [wantMorning]) as Future?);
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 4) AppBar ggf. neu zeichnen
    if (mounted) setState(() {});
  }

  // --- Kompakter, grauer Toggle (final abgestimmt) ---
  List<Widget> get _actions {
    GlobalKey targetKey;
    bool showAdd = false;
    if (_index == 0) {
      targetKey = _searchKey;
      showAdd = true;
    } else if (_index == 1) {
      targetKey = _planKey; // Tag
    } else if (_index == 2) {
      targetKey = _mapKey; // Route
    } else if (_index == 3) {
      targetKey = _dienstKey; // Dienst
    } else {
      targetKey = _searchKey;
    }

    final st = targetKey.currentState as dynamic;

    final Function? refresh = _tryGet<Function>(
      () => st.refreshFromWrapper as Function,
    );
    final Function? printReport = _tryGet<Function>(
      () => st.printFromWrapper as Function,
    );
    final Function? addPerson = showAdd
        ? _tryGet<Function>(() => st.addPersonFromWrapper as Function)
        : null;

    // Globale Auto-Refresh-Aktion für den Timer setzen:
    // - Im Klienten-Tab ruft refreshFromWrapper() intern _pullFromSheet() auf.
    // - Im Tagesplan-Tab ruft refreshFromWrapper() _loadDayPlanSafe() auf.
    // Der Timer benutzt dann immer diese Aktion, so wie der Refresh-Button.
    AppBus.onRefresh = null;
    if (refresh != null) {
      AppBus.onRefresh = () {
        try {
          // Kann sync oder async sein; ein evtl. Future wird bewusst ignoriert.
          Function.apply(refresh, const []);
        } catch (_) {}
      };
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final widgets = <Widget>[];

    // ---------- Kompakter M/A-Toggle nur im TP-Tab ----------
    if (_index == 1) {
      final bool isM = _tplanIsMorning;

      // Schrift etwas kleiner als Datum
      final TextStyle toggleTextStyle =
          (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.88,
            height: 1.0,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          );

      // dezente Grautöne
      final Color activeBg = Colors.grey.shade300;
      final Color inactiveBg = Colors.grey.shade100;
      final Color borderClr = Colors.grey.shade400;

      Widget seg(String label, bool selected, VoidCallback onTap) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? activeBg : inactiveBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? borderClr : Colors.grey.shade300,
                width: selected ? 1.2 : 0.8,
              ),
            ),
            child: Text(
              label,
              style: toggleTextStyle.copyWith(
                color: selected ? Colors.grey.shade900 : Colors.grey.shade700,
              ),
            ),
          ),
        );
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Container(
            height: 26, // wie Datum
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg('M', isM, () async => await _toggleDayMode(true)),
                seg('A', !isM, () async => await _toggleDayMode(false)),
              ],
            ),
          ),
        ),
      );
    }

    // ---------- Kontextmenü (Aktualisieren / Drucken / Neuer Klient) ----------
    //
    // Im Klienten-Tab:
    //   Menü enthält: "Aktualisieren", "Drucken" (falls vorhanden), "Neuer Klient"
    // In anderen Tabs:
    //   Menü enthält: "Aktualisieren", "Drucken" (falls vorhanden)
    //
    if (refresh != null ||
        printReport != null ||
        (showAdd && addPerson != null)) {
      widgets.add(
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'refresh' && refresh != null) {
              refresh();
            } else if (value == 'print' && printReport != null) {
              printReport();
            } else if (value == 'new' && addPerson != null) {
              addPerson();
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[];

            if (refresh != null) {
              items.add(
                PopupMenuItem<String>(
                  value: 'refresh',
                  child: Row(
                    children: const [
                      Icon(Icons.refresh, size: 20),
                      SizedBox(width: 12),
                      Text('Aktualisieren'),
                    ],
                  ),
                ),
              );
            }

            if (printReport != null) {
              items.add(
                PopupMenuItem<String>(
                  value: 'print',
                  child: Row(
                    children: const [
                      Icon(Icons.print, size: 20),
                      SizedBox(width: 12),
                      Text('Drucken'),
                    ],
                  ),
                ),
              );
            }

            // "Neuer Klient" nur im Klienten-Tab (showAdd == true) und wenn Funktion vorhanden
            if (showAdd && addPerson != null) {
              items.add(
                PopupMenuItem<String>(
                  value: 'new',
                  child: Row(
                    children: const [
                      Icon(Icons.person_add, size: 20),
                      SizedBox(width: 12),
                      Text('Neuer Klient'),
                    ],
                  ),
                ),
              );
            }

            return items;
          },
        ),
      );
    }

    // Kleiner Abschlussabstand rechts
    widgets.add(const SizedBox(width: 8));
    return widgets;
  }

  // Info-Tab-Inhalt (greift auf Panel aus HomePage/Suche zu)
  Widget _buildInfoTab() {
    final st = _searchKey.currentState as dynamic;
    final Function? buildInfo = _tryGet<Function>(
      () => st.buildInfoPanelForWrapper as Function,
    );
    if (buildInfo != null) {
      try {
        final Widget? w = buildInfo() as Widget?;
        if (w != null) return SafeArea(child: w);
      } catch (_) {}
    }
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Info derzeit nicht verfügbar'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // verhindert den Farbshift beim Hochscrollen
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // stabiler, neutraler Hintergrund (kontrastiert zum Toggle)
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: _buildAppBarTitle(),
        actions: _actions,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppBus.infoRev,
        builder: (_, __, ___) => IndexedStack(
          index: _index,
          children: <Widget>[
            HomePage(key: _searchKey, showAppBar: false, initialMapMode: false),
            TagesplanTab(key: _planKey),
            HomePage(key: _mapKey, showAppBar: false, initialMapMode: true),
            DienstplanTab(key: _dienstKey),
            _buildInfoTab(),
          ],
        ),
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Klienten',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Tag',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Route',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_ind_outlined),
            selectedIcon: Icon(Icons.assignment_ind),
            label: 'Dienst',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Info',
          ),
        ],
      ),
    );
  }
}
