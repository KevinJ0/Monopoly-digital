import 'package:flutter/foundation.dart';

class StatsProvider extends ChangeNotifier {
  double totalVolume = 0;
  int txCount = 0;
  int passGoCount = 0;

  void record(double amount, {bool isPassGo = false}) {
    totalVolume += amount;
    txCount += 1;
    if (isPassGo) passGoCount += 1;
    notifyListeners();
  }

  void restore({
    required double volume,
    required int count,
    required int passGo,
  }) {
    totalVolume = volume;
    txCount = count;
    passGoCount = passGo;
    notifyListeners();
  }
}
