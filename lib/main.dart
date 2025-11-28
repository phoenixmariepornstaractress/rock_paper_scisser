// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Haptic
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const ProRPSApp());
}

/// ----------------- MODELS -----------------
class Opponent {
  final String id;
  final String name;
  final String avatarAsset;
  final String description;
  final int behavior; // 0=random, 1=rocky, 2=papery, 3=scissory, 4=learning

  const Opponent({
    required this.id,
    required this.name,
    required this.avatarAsset,
    required this.description,
    this.behavior = 0,
  });
}

class Achievement {
  final String id;
  final String title;
  final String description;
  bool unlocked;
  Achievement({
    required this.id,
    required this.title,
    required this.description,
    this.unlocked = false,
  });
}

/// Simple enum-like ints for moves
class Move {
  static const int rock = 1;
  static const int paper = 2;
  static const int scissors = 3;
  static const List<int> all = [rock, paper, scissors];
  static String name(int m) {
    switch (m) {
      case rock:
        return 'سنگ';
      case paper:
        return 'کاغذ';
      case scissors:
        return 'قیچی';
      default:
        return '?';
    }
  }
}

/// ----------------- CONTROLLER (ChangeNotifier) -----------------
/// Central game logic and state. Widgets listen to it via AnimatedBuilder.
class GameController extends ChangeNotifier {
  // Game state
  int userChoice = Move.rock;
  int aiChoice = Move.rock;
  int userScore = 0;
  int aiScore = 0;

  // XP / Level
  int xp = 0;
  int level = 1;

  // History & achievements
  final List<String> history = [];
  final List<Achievement> achievements = [];

  // Avatars
  String userAvatar = 'assets/images/avatar_user.png';
  String aiAvatar = 'assets/images/avatar_ai.png';

  // UI flags
  bool fastMode = false;
  bool isNeon = false;
  bool isDark = false;
  bool showParticles = false;

  // Adventure opponents
  final List<Opponent> adventureOpponents = [];
  int adventureStage = 0;

  // Tournament
  List<String> tournamentBracket = [];
  int tournamentStage = 0;

  // AI memory (learning)
  final List<int> userMoves = [];

  // Audio & random
  final AudioPlayer audio = AudioPlayer();
  final Random _rand = Random();

  GameController() {
    // Initialize achievements and opponents
    achievements.addAll([
      Achievement(id: 'first_win', title: 'اولین برد', description: 'اولین برد ثبت شد.'),
      Achievement(id: 'three_wins', title: 'سه برد پشت سرهم', description: '۳ برد متوالی!'),
      Achievement(id: 'fast_mode', title: 'حالت تندرو', description: 'مود سریع را اجرا کردی.'),
      Achievement(id: 'tournament', title: 'قهرمان تورنومنت', description: 'تورنومنت را بردی.'),
    ]);

    adventureOpponents.addAll([
      const Opponent(
          id: 'op1',
          name: 'ربات دفاعی',
          avatarAsset: 'assets/images/opponent1.png',
          description: 'بیشتر سنگ می‌زند',
          behavior: 1),
      const Opponent(
          id: 'op2',
          name: 'جادوگر کاغذی',
          avatarAsset: 'assets/images/opponent2.png',
          description: 'بیشتر کاغذ می‌زند',
          behavior: 2),
      const Opponent(
          id: 'op3',
          name: 'نبوغ قیچی',
          avatarAsset: 'assets/images/opponent3.png',
          description: 'بیشتر قیچی می‌زند',
          behavior: 3),
      const Opponent(
          id: 'op4',
          name: 'مخالف یادگیر',
          avatarAsset: 'assets/images/opponent4.png',
          description: 'سعی در یادگیری تو دارد',
          behavior: 4),
    ]);
  }

  // ----------------- Helpers -----------------
  int randomChoice() => _rand.nextInt(3) + 1;

  int _mostFrequent(List<int> arr) {
    if (arr.isEmpty) return Move.rock;
    final Map<int, int> count = {};
    for (var v in arr) count[v] = (count[v] ?? 0) + 1;
    int best = arr.first;
    int bestCount = 0;
    count.forEach((k, v) {
      if (v > bestCount) {
        best = k;
        bestCount = v;
      }
    });
    return best;
  }

  int aiChoiceAgainstOpponent(Opponent? o) {
    if (o == null) return randomChoice();
    switch (o.behavior) {
      case 1:
        return _rand.nextInt(100) < 60 ? Move.rock : randomChoice();
      case 2:
        return _rand.nextInt(100) < 60 ? Move.paper : randomChoice();
      case 3:
        return _rand.nextInt(100) < 60 ? Move.scissors : randomChoice();
      case 4:
        if (userMoves.isEmpty) return randomChoice();
        final most = _mostFrequent(userMoves);
        // counter:
        if (most == Move.rock) return Move.paper;
        if (most == Move.paper) return Move.scissors;
        return Move.rock;
      default:
        return randomChoice();
    }
  }

  int computeWinner(int user, int ai) {
    if (user == ai) return 0;
    if ((user == Move.rock && ai == Move.scissors) ||
        (user == Move.paper && ai == Move.rock) ||
        (user == Move.scissors && ai == Move.paper)) return 1;
    return 2;
  }

  Future<void> _playSound(String name) async {
    try {
      await audio.play(AssetSource('sounds/$name.mp3'));
    } catch (_) {
      // ignore if asset missing
    }
  }

  void _haptic(bool strong) {
    try {
      if (strong) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
  }

  void _addHistory(String text) {
    history.insert(0, text);
    if (history.length > 8) history.removeLast();
    notifyListeners();
  }

  Achievement? _findAchievement(String id) {
    for (var a in achievements) {
      if (a.id == id) return a;
    }
    return null;
  }

  void unlockAchievement(String id) {
    final a = _findAchievement(id);
    if (a == null) return;
    if (!a.unlocked) {
      a.unlocked = true;
      notifyListeners();
      _playSound('achievement');
      _haptic(true);
      // UI may show a SnackBar manually by listening
    }
  }

  void addXP(int amount) {
    xp += amount;
    // level up loop
    while (xp >= 100) {
      xp -= 100;
      level++;
      _playSound('levelup');
      _addHistory('Level Up! سطح به $level رسید.');
    }
    notifyListeners();
  }

  // ----------------- Actions -----------------
  /// set user choice (from UI) without playing round
  void setUserChoice(int move) {
    userChoice = move;
    notifyListeners();
  }

  /// Play one round (optional opponent)
  void playRound({Opponent? opponent}) {
    aiChoice = aiChoiceAgainstOpponent(opponent);
    // if in fastMode, let userChoice be random to simulate auto-play
    if (fastMode) userChoice = randomChoice();

    userMoves.add(userChoice);
    if (userMoves.length > 30) userMoves.removeAt(0);

    final res = computeWinner(userChoice, aiChoice);
    if (res == 0) {
      _addHistory('مساوی (${Move.name(userChoice)} vs ${Move.name(aiChoice)})');
      _playSound('draw');
      _haptic(false);
      addXP(2);
    } else if (res == 1) {
      userScore++;
      _addHistory('پیروزی شما (${Move.name(userChoice)} vs ${Move.name(aiChoice)})');
      _playSound('win');
      _haptic(true);
      showParticleOnce();
      addXP(10);
      unlockAchievement('first_win');
      // check 3-in-a-row
      if (history.length >= 3 &&
          history[0].startsWith('پیروزی') &&
          history[1].startsWith('پیروزی') &&
          history[2].startsWith('پیروزی')) {
        unlockAchievement('three_wins');
      }
    } else {
      aiScore++;
      _addHistory('باخت (${Move.name(userChoice)} vs ${Move.name(aiChoice)})');
      _playSound('lose');
      _haptic(true);
      addXP(1);
    }

    notifyListeners();
  }

  void showParticleOnce() {
    showParticles = true;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 700), () {
      showParticles = false;
      notifyListeners();
    });
  }

  void toggleFastMode() {
    fastMode = !fastMode;
    notifyListeners();
    if (fastMode) {
      unlockAchievement('fast_mode');
      // schedule a small burst of auto rounds
      for (var i = 0; i < 6; i++) {
        Future.delayed(Duration(milliseconds: 300 * i), () => playRound());
      }
    }
  }

  void toggleThemeNeon() {
    isNeon = !isNeon;
    notifyListeners();
  }

  void toggleDark() {
    isDark = !isDark;
    notifyListeners();
  }

  void chooseUserAvatar(String asset) {
    userAvatar = asset;
    _addHistory('آواتار تغییر یافت');
    notifyListeners();
  }

  /// Adventure: fight next opponent with simulated 5 rounds (best of 5)
  Future<void> fightAdventureNext() async {
    if (adventureStage >= adventureOpponents.length) {
      _addHistory('مود داستانی تمام شد.');
      return;
    }
    final Opponent current = adventureOpponents[adventureStage];
    int userWins = 0, aiWins = 0;

    // Simulate rounds with small delays to avoid UI freeze and allow updates
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      final int u = randomChoice();
      final int a = aiChoiceAgainstOpponent(current);
      final int r = computeWinner(u, a);
      if (r == 1) userWins++;
      if (r == 2) aiWins++;
    }

    if (userWins > aiWins) {
      _addHistory('شما ${current.name} را بردید ($userWins-$aiWins)');
      _playSound('win');
      addXP(30);
      adventureStage++;
      notifyListeners();
    } else {
      _addHistory('شکست در برابر ${current.name} ($userWins-$aiWins)');
      _playSound('lose');
      notifyListeners();
    }
  }

  /// Tournament simple simulation with 'YOU' included
  void startTournament() {
    tournamentBracket = ['YOU', 'AI1', 'AI2', 'AI3', 'AI4'];
    tournamentStage = 0;
    _playSound('tournament_start');
    // Run a simple elimination every 600ms
    Timer.periodic(const Duration(milliseconds: 600), (t) {
      if (tournamentBracket.length <= 1) {
        t.cancel();
        _addHistory('قهرمان تورنومنت: ${tournamentBracket.first}');
        if (tournamentBracket.first == 'YOU') unlockAchievement('tournament');
        notifyListeners();
        return;
      }
      final idx = _rand.nextInt(tournamentBracket.length);
      final removed = tournamentBracket.removeAt(idx);
      _addHistory('حذف شد: $removed');
      notifyListeners();
    });
  }

  void startLocalMatch() {
    _addHistory('شروع مسابقه محلی (Pass-and-Play)');
    notifyListeners();
  }

  void resetAll() {
    userScore = 0;
    aiScore = 0;
    xp = 0;
    level = 1;
    history.clear();
    for (var a in achievements) a.unlocked = false;
    userMoves.clear();
    tournamentBracket.clear();
    adventureStage = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    audio.dispose();
    super.dispose();
  }
}

/// ----------------- UI (single-file modular widgets) -----------------
class ProRPSApp extends StatelessWidget {
  const ProRPSApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = GameController();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'vazir',
          brightness: controller.isDark ? Brightness.dark : Brightness.light,
        ),
        home: GameHome(controller: controller),
      ),
    );
  }
}

class GameHome extends StatelessWidget {
  final GameController controller;
  const GameHome({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use AnimatedBuilder to rebuild on controller changes
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('سنگ — کاغذ — قیچی (Pro)'),
            actions: [
              IconButton(
                icon: Icon(controller.isDark ? Icons.light_mode : Icons.dark_mode),
                onPressed: controller.toggleDark,
              ),
              IconButton(
                icon: Icon(controller.isNeon ? Icons.wb_incandescent : Icons.blur_on),
                onPressed: controller.toggleThemeNeon,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: controller.resetAll,
              ),
            ],
          ),
          body: Stack(
            children: [
              // Animated background
              AnimatedContainer(
                duration: const Duration(seconds: 4),
                decoration: BoxDecoration(
                  gradient: controller.isNeon
                      ? LinearGradient(
                          colors: controller.isDark
                              ? [Colors.deepPurple.shade900, Colors.black]
                              : [Colors.blue.shade200, Colors.purple.shade200],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: controller.isDark
                              ? [Colors.grey.shade900, Colors.grey.shade800]
                              : [Colors.orange.shade100, Colors.deepOrange.shade100],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
              ),

              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Top row: avatars + level/XP
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _avatarColumn('شما', controller.userAvatar, controller.userScore),
                          Expanded(
                            child: Column(
                              children: [
                                Text('Level ${controller.level}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: controller.xp / 100,
                                  minHeight: 8,
                                  backgroundColor: Colors.black12,
                                  color: Colors.greenAccent,
                                ),
                                const SizedBox(height: 6),
                                Text('XP: ${controller.xp}/100'),
                              ],
                            ),
                          ),
                          _avatarColumn('حریف', controller.aiAvatar, controller.aiScore),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Choices display
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Image.asset(
                                'assets/images/${controller.userChoice}.png',
                                height: 80,
                                width: 80,
                                errorBuilder: (c, e, s) => Container(
                                  height: 80,
                                  width: 80,
                                  color: Colors.white24,
                                  child: const Center(child: Text('img')),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('شما: ${Move.name(controller.userChoice)}'),
                            ],
                          ),
                          Column(
                            children: [
                              Image.asset(
                                'assets/images/${controller.aiChoice}.png',
                                height: 80,
                                width: 80,
                                errorBuilder: (c, e, s) => Container(
                                  height: 80,
                                  width: 80,
                                  color: Colors.white24,
                                  child: const Center(child: Text('img')),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('حریف: ${Move.name(controller.aiChoice)}'),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // last history item or prompt
                      Text(
                        controller.history.isNotEmpty ? controller.history.first : 'شروع کنید!',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 12),

                      // Choice buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _choiceButton(context, controller, Move.rock, 'سنگ'),
                          _choiceButton(context, controller, Move.paper, 'کاغذ'),
                          _choiceButton(context, controller, Move.scissors, 'قیچی'),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Controls
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: controller.toggleFastMode,
                            icon: const Icon(Icons.flash_on),
                            label: Text(controller.fastMode ? 'حالت تند: فعال' : 'حالت تند'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => controller.playRound(),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('یک دور بازی'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              await controller.fightAdventureNext();
                            },
                            icon: const Icon(Icons.book),
                            label: const Text('مود داستانی'),
                          ),
                          ElevatedButton.icon(
                            onPressed: controller.startTournament,
                            icon: const Icon(Icons.emoji_events),
                            label: const Text('شروع تورنومنت'),
                          ),
                          ElevatedButton.icon(
                            onPressed: controller.startLocalMatch,
                            icon: const Icon(Icons.wifi_tethering),
                            label: const Text('مسابقه محلی (Pass)'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // History card
                      SizedBox(
                        height: 110,
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListView(
                                children: controller.history.map((h) {
                              final color = h.contains('پیروزی')
                                  ? Colors.green
                                  : h.contains('باخت')
                                      ? Colors.red
                                      : Colors.grey;
                              return Text(h, style: TextStyle(color: color));
                            }).toList()),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Achievements row
                      SizedBox(
                        height: 70,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: controller.achievements.map((a) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: Chip(
                                avatar: Icon(a.unlocked ? Icons.star : Icons.lock),
                                label: Text(a.title),
                                backgroundColor: a.unlocked ? Colors.amber.shade200 : Colors.grey.shade300,
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Avatar & voice controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              controller.chooseUserAvatar('assets/images/avatar_user2.png');
                            },
                            icon: const Icon(Icons.person),
                            label: const Text('تغییر آواتار'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              controller._playSound('voice_welcome');
                              controller._addHistory('گوینده خوش‌آمد گفت');
                            },
                            icon: const Icon(Icons.record_voice_over),
                            label: const Text('گوینده تست'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // particle overlay
              if (controller.showParticles)
                Center(
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: CustomPaint(
                        painter: _ParticlePainter(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarColumn(String title, String avatarAsset, int score) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: AssetImage(avatarAsset),
          onBackgroundImageError: (_, __) {},
          child: Image.asset(
            avatarAsset,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 6),
        Text(title),
        Text('امتیاز: $score'),
      ],
    );
  }

  Widget _choiceButton(BuildContext context, GameController controller, int move, String label) {
    return ElevatedButton(
      onPressed: () {
        controller.setUserChoice(move);
        controller.playRound();
      },
      child: Text(label),
    );
  }
}

/// ----------------- Particle Painter -----------------
class _ParticlePainter extends CustomPainter {
  final Random _r = Random();
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 25; i++) {
      p.color = Colors.primaries[_r.nextInt(Colors.primaries.length)].withOpacity(0.85);
      final x = _r.nextDouble() * size.width;
      final y = _r.nextDouble() * size.height;
      final r = 3 + _r.nextDouble() * 9;
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
