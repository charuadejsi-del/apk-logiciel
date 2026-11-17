import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';

class MyArg {
  final String id;
  String title;
  String text;
  MyArg(this.id, this.title, this.text);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'text': text};
  static MyArg fromJson(Map<String, dynamic> j) => MyArg(j['id'], j['title'] ?? '', j['text'] ?? '');
}

/// État global persistant : réglages, favoris, notes, arguments personnels, entraînement.
class AppState extends ChangeNotifier {
  static final AppState I = AppState();
  SharedPreferences? _p;

  double fontScale = 1.0;
  ThemeMode themeMode = ThemeMode.system;
  final Set<String> favorites = {};
  final Map<String, String> notes = {};
  final List<MyArg> myArgs = [];
  int trainKnown = 0, trainUnknown = 0;
  String updateUrl = Brand.defaultUpdateUrl;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      fontScale = p.getDouble('fontScale') ?? 1.0;
      themeMode = ThemeMode.values[(p.getInt('themeMode') ?? 0).clamp(0, 2).toInt()];
      favorites.addAll(p.getStringList('favorites') ?? const []);
      final n = p.getString('notes');
      if (n != null) notes.addAll(Map<String, String>.from(jsonDecode(n) as Map));
      final a = p.getString('myArgs');
      if (a != null) {
        myArgs.addAll((jsonDecode(a) as List).map((e) => MyArg.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      trainKnown = p.getInt('trainKnown') ?? 0;
      trainUnknown = p.getInt('trainUnknown') ?? 0;
      updateUrl = p.getString('updateUrl') ?? Brand.defaultUpdateUrl;
    } catch (_) {
      // Pas de stockage disponible : on garde les valeurs par défaut.
    }
  }

  void _save() {
    final p = _p;
    if (p == null) return;
    p.setDouble('fontScale', fontScale);
    p.setInt('themeMode', themeMode.index);
    p.setStringList('favorites', favorites.toList());
    p.setString('notes', jsonEncode(notes));
    p.setString('myArgs', jsonEncode(myArgs.map((e) => e.toJson()).toList()));
    p.setInt('trainKnown', trainKnown);
    p.setInt('trainUnknown', trainUnknown);
    p.setString('updateUrl', updateUrl);
  }

  void setFontScale(double v) {
    fontScale = v;
    _save();
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save();
    notifyListeners();
  }

  bool isFav(String tag) => favorites.contains(tag);

  void toggleFav(String tag) {
    if (!favorites.remove(tag)) favorites.add(tag);
    _save();
    notifyListeners();
  }

  String note(String tag) => notes[tag] ?? '';

  void setNote(String tag, String text) {
    if (text.trim().isEmpty) {
      notes.remove(tag);
    } else {
      notes[tag] = text.trim();
    }
    _save();
    notifyListeners();
  }

  void saveArg(MyArg a) {
    final i = myArgs.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      myArgs[i] = a;
    } else {
      myArgs.insert(0, a);
    }
    _save();
    notifyListeners();
  }

  void deleteArg(String id) {
    myArgs.removeWhere((x) => x.id == id);
    _save();
    notifyListeners();
  }

  void train(bool known) {
    if (known) {
      trainKnown++;
    } else {
      trainUnknown++;
    }
    _save();
    notifyListeners();
  }

  void resetTraining() {
    trainKnown = 0;
    trainUnknown = 0;
    _save();
    notifyListeners();
  }

  void setUpdateUrl(String u) {
    updateUrl = u.trim().isEmpty ? Brand.defaultUpdateUrl : u.trim();
    _save();
    notifyListeners();
  }

  /// Appelé après une mise à jour du contenu pour rafraîchir l'interface.
  void contentChanged() => notifyListeners();
}
