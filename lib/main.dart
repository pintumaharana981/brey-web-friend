import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const BreyApp());
}


// ============================================================
// CARD
// ============================================================

class CardModel {
  final String suit;
  final String rank;
  final int value;
  final int penalty;

  const CardModel({
    required this.suit,
    required this.rank,
    required this.value,
    required this.penalty,
  });

  String get symbol {
    switch (suit) {
      case 'Hearts':
        return '♥';
      case 'Diamonds':
        return '♦';
      case 'Clubs':
        return '♣';
      case 'Spades':
        return '♠';
      default:
        return '';
    }
  }

  String get shortName {
    return '$rank$symbol';
  }

  bool get isSpadeQueen {
    return suit == 'Spades' && rank == 'Q';
  }
}

// ============================================================
// BOT DIFFICULTY
// ============================================================

enum BotDifficulty {
  easy,
  medium,
  hard,
}

// ============================================================
// PLAYER
// ============================================================

class Player {
  final String name;
  final bool isHuman;
  final int avatarIndex;

  List<CardModel> cards = [];

  int score = 0;
  int handsWon = 0;
  bool eliminated = false;

  Player({
    required this.name,
    required this.isHuman,
    this.avatarIndex = 0,
  });
}

// ============================================================
// PLAYED CARD
// ============================================================

class PlayedCard {
  final int playerIndex;
  final CardModel card;

  PlayedCard({
    required this.playerIndex,
    required this.card,
  });
}

// ============================================================
// APP
// ============================================================

class BreyApp extends StatefulWidget {
  const BreyApp({super.key});

  @override
  State<BreyApp> createState() => _BreyAppState();
}

class _BreyAppState extends State<BreyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String value = prefs.getString('brey_settings_appearance') ?? 'system';
      if (!mounted) return;
      setState(() {
        _themeMode = _themeModeFromString(value);
      });
    } catch (_) {}
  }

  ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void _changeAppearance(String value) {
    setState(() {
      _themeMode = _themeModeFromString(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BREY',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff8a651e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xffeef0ed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffc29a45),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff11110f),
        useMaterial3: true,
      ),
      home: BreyGame(onAppearanceChanged: _changeAppearance),
    );
  }
}

// ============================================================
// GAME
// ============================================================

class BreyGame extends StatefulWidget {
  final ValueChanged<String>? onAppearanceChanged;

  const BreyGame({
    super.key,
    this.onAppearanceChanged,
  });

  @override
  State<BreyGame> createState() => _BreyGameState();
}

class _BreyGameState extends State<BreyGame> {
  @override
  void initState() {
    super.initState();
    _loadPlayerProfile();
    _loadGameStatistics();
    _loadSettings();
  }

  final Random random = Random();

  late List<Player> players;

  // Current trick / Hand.
  List<PlayedCard> currentHand = [];

  // Round and Hand numbers.
  int roundNumber = 1;
  int handNumber = 1;

  // Dealer.
  int dealerIndex = 0;

  // Whose turn.
  int currentPlayerIndex = 0;

  // Led suit.
  String? ledSuit;

  // Game state.
  bool gameStarted = false;
  bool _firstHandHintShown = false;
  final Set<String> _shownRuleHints = <String>{};
  bool _isBackGameMenuOpen = false;
  bool exchangePhase = false;
  bool roundFinished = false;
  bool gameOver = false;

  // ==========================================================
  // PLAYER PROFILE — V1.10 STEP A
  // First-session name and cartoon avatar selection. Persistence
  // will be added as a separate step so this change stays focused.
  // ==========================================================
  bool profileCreated = false;
  bool _profileLoaded = false;
  String _playerName = '';
  int _selectedAvatarIndex = 0;

  static const String _profileCreatedStorageKey = 'brey_profile_created';
  static const String _profileNameStorageKey = 'brey_profile_name';
  static const String _profileAvatarStorageKey = 'brey_profile_avatar';
  final TextEditingController _profileNameController =
      TextEditingController();

  // ==========================================================
  // PLAYER GAME STATISTICS — V1.13
  // Persistent statistics are updated only when a game actually ends.
  // ==========================================================
  int _gamesPlayed = 0;
  int _gamesWon = 0;
  int _gamesLost = 0;
  int _totalHandsPlayed = 0;
  int _totalHandsWon = 0;
  int _bestScore = -1; // Lowest completed-game score is best.
  int _totalPenaltyPointsReceived = 0;
  int _highestScoreReached = 0;
  bool _gameStatsLoaded = false;
  bool _currentGameStatsRecorded = false;

  // ==========================================================
  // SETTINGS — V1.18
  // Preferences are saved locally. V1.17 wires gameplay convenience preferences
  // feedback into the existing game events without changing gameplay.
  // ==========================================================
  bool _vibrationEnabled = true;
  String _appearanceMode = 'system';
  bool _cardAnimationEnabled = true;
  String _animationSpeed = 'normal';
  bool _autoNextHand = true;
  bool _beginnerHintsEnabled = true;
  bool _ruleRemindersEnabled = true;
  bool _keepScreenAwake = true;

  static const String _settingsVibrationKey = 'brey_settings_vibration';
  static const String _settingsAppearanceKey = 'brey_settings_appearance';
  static const String _settingsCardAnimationKey = 'brey_settings_card_animation';
  static const String _settingsAnimationSpeedKey = 'brey_settings_animation_speed';
  static const String _settingsAutoNextHandKey = 'brey_settings_auto_next_hand';
  static const String _settingsHintsKey = 'brey_settings_hints';
  static const String _settingsRuleRemindersKey = 'brey_settings_rule_reminders';
  static const String _settingsKeepAwakeKey = 'brey_settings_keep_awake';
  bool _settingsLoaded = false;

  static const String _gamesPlayedStorageKey = 'brey_stats_games_played';
  static const String _gamesWonStorageKey = 'brey_stats_games_won';
  static const String _gamesLostStorageKey = 'brey_stats_games_lost';
  static const String _totalHandsPlayedStorageKey = 'brey_stats_hands_played';
  static const String _totalHandsWonStorageKey = 'brey_stats_hands_won';
  static const String _bestScoreStorageKey = 'brey_stats_best_score';
  static const String _totalPenaltyStorageKey = 'brey_stats_penalty_received';
  static const String _highestScoreStorageKey = 'brey_stats_highest_score';

  static const List<Map<String, String>> _playerAvatars = [
    {'gender': 'Male', 'emoji': '🧑🏻‍🎨', 'name': 'Artist'},
    {'gender': 'Male', 'emoji': '🧑🏽‍🚀', 'name': 'Explorer'},
    {'gender': 'Male', 'emoji': '🧑🏿‍🎓', 'name': 'Scholar'},
    {'gender': 'Female', 'emoji': '👩🏻‍🎨', 'name': 'Artist'},
    {'gender': 'Female', 'emoji': '👩🏽‍🚀', 'name': 'Explorer'},
    {'gender': 'Female', 'emoji': '👩🏿‍🎓', 'name': 'Scholar'},
  ];

  // Cartoon avatars used for the three BOTs in the scoreboard.
  // These are intentionally separate from the user's six profile avatars.
  static const List<String> _botAvatars = [
    '🤖',
    '👾',
    '🦾',
  ];

  String _botAvatarForPlayer(Player player) {
    final int playerIndex = players.indexOf(player);
    final int botNumber = playerIndex >= 1 ? playerIndex - 1 : 0;
    return _botAvatars[botNumber.clamp(0, _botAvatars.length - 1).toInt()];
  }

  // Hand-completion animation state. Cards remain visible while they
  // smoothly collect toward the winner before the next Hand begins.
  bool handCollecting = false;
  int? collectingWinnerIndex;

  // Total penalty points collected by each player during the CURRENT Round.
  // This is used for the Round-level 35-point rule.
  final Map<int, int> roundPenaltyByPlayer = <int, int>{
    0: 0,
    1: 0,
    2: 0,
    3: 0,
  };

  // Round dealing animation state. The actual 52-card deal is completed
  // immediately in memory, while the UI reveals the deal progressively.
  bool dealingPhase = false;
  int dealtCardCount = 0;
  int dealingStartingPlayer = 0;
  int _dealingGeneration = 0;

  String message = '';

  // Selected BOT difficulty. The UI intentionally shows only the
  // difficulty names; the strength calibration is kept internal.
  BotDifficulty botDifficulty = BotDifficulty.medium;

  // Strategic memory for each BOT.
  final Map<int, List<CardModel>> passedCardsByPlayer = {};
  final Map<int, List<CardModel>> receivedCardsByPlayer = {};
  final List<CardModel> playedCardsThisRound = [];
  // Suit voids inferred from a player failing to follow a led suit.
  final List<Set<String>> voidSuitsByPlayer = [
    <String>{},
    <String>{},
    <String>{},
    <String>{},
  ];

  // Strategic card-ownership memory. This stores only information the BOT
  // could legitimately know from the exchange or cards publicly played.
  // It never reads an opponent's hidden hand to make a decision.
  final Map<String, int> knownCardOwner = {};

  // Publicly observed suit counts: cards of this suit already seen during
  // this Round. Used with void information to estimate what remains.
  final Map<String, int> playedSuitCounts = {
    'Hearts': 0,
    'Diamonds': 0,
    'Clubs': 0,
    'Spades': 0,
  };

  // ==========================================================
  // EXCHANGE
  // ==========================================================

  List<CardModel> selectedExchangeCards = [];

  // Each player chooses 4 cards.
  Map<int, List<CardModel>> exchangeSelections = {};

  // ==========================================================
  // ♠Q TRACKING
  // ==========================================================

  bool spadeQueenPlayedThisRound = false;

  int? spadeQueenCollector;

  // ==========================================================
  // LEAD-SUIT TRACKING
  // ==========================================================

  List<String?> lastLedSuitByPlayer = [
    null,
    null,
    null,
    null,
  ];

  List<int> consecutiveLeadCountByPlayer = [
    0,
    0,
    0,
    0,
  ];

  // ==========================================================
  // CREATE DECK
  // ==========================================================

  List<CardModel> createDeck() {
    const List<String> suits = [
      'Hearts',
      'Diamonds',
      'Clubs',
      'Spades',
    ];

    const List<String> ranks = [
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
      'A',
    ];

    List<CardModel> deck = [];

    for (String suit in suits) {
      for (int i = 0; i < ranks.length; i++) {
        String rank = ranks[i];

        int penalty = 0;

        // Every Heart = 1.
        if (suit == 'Hearts') {
          penalty = 1;
        }

        // ♦J = 4.
        if (suit == 'Diamonds' && rank == 'J') {
          penalty = 4;
        }

        // ♣K = 6.
        if (suit == 'Clubs' && rank == 'K') {
          penalty = 6;
        }

        // ♠Q = 12.
        if (suit == 'Spades' && rank == 'Q') {
          penalty = 12;
        }

        deck.add(
          CardModel(
            suit: suit,
            rank: rank,
            value: i + 2,
            penalty: penalty,
          ),
        );
      }
    }

    return deck;
  }

  Widget _hintCard({
    required String rank,
    required String suit,
    bool highlighted = false,
  }) {
    final bool red = suit == 'Hearts' || suit == 'Diamonds';
    final String symbol = suit == 'Hearts'
        ? '♥'
        : suit == 'Diamonds'
            ? '♦'
            : suit == 'Clubs'
                ? '♣'
                : '♠';

    return Container(
      width: 54,
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? const Color(0xffc8a45d)
              : Colors.black12,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rank$symbol',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: red ? Colors.red.shade700 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintScenario({
    required String label,
    required List<Widget> cards,
    String? arrow,
  }) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...cards,
            if (arrow != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  arrow,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showSmoothHint({
    required String title,
    required String message,
    Widget? scenario,
  }) async {
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: title,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 390),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dialogTheme.backgroundColor ??
                        Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 17, 18, 13),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            message,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: Colors.black87,
                            ),
                          ),
                          if (scenario != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
                              decoration: BoxDecoration(
                                color: const Color(0xfff7f1e4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xffdcc58e),
                                ),
                              ),
                              child: scenario,
                            ),
                          ],
                          const SizedBox(height: 13),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('GOT IT'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRuleHintOnce({
    required String key,
    required String title,
    required String message,
    Widget? scenario,
  }) async {
    if (!mounted || !_ruleRemindersEnabled || _shownRuleHints.contains(key)) return;

    _shownRuleHints.add(key);

    await _showSmoothHint(
      title: title,
      message: message,
      scenario: scenario,
    );
  }

  Future<void> _showFirstHandHint() async {
    if (!mounted ||
        !_beginnerHintsEnabled ||
        _firstHandHintShown ||
        roundNumber != 1 ||
        handNumber != 1) {
      return;
    }

    _firstHandHintShown = true;

    await _showSmoothHint(
      title: 'FIRST HAND — EASY START',
      message:
          'Three things to remember:\n\n'
          '1. The first card must be a safe ♣ or ♦ card.\n'
          '2. If someone leads a suit you have, follow that suit.\n'
          '3. If you cannot follow suit in Hand 1, play a non-penalty card when you have one.',
      scenario: _hintScenario(
        label: 'Example: a safe opening',
        cards: [
          _hintCard(rank: '7', suit: 'Clubs', highlighted: true),
          _hintCard(rank: '5', suit: 'Hearts'),
        ],
        arrow: '→',
      ),
    );
  }

  // ==========================================================
  // V42.57 - Final Gameplay Audit baseline
// No gameplay behavior is changed in this audit build.
// V42.56 STABILITY BASELINE CHECKS
  // ==========================================================

  void _runGameplayStabilityChecks() {
    assert(() {
      // Each player can never hold more than 13 cards.
      for (final Player player in players) {
        assert(player.cards.length <= 13);
      }

      // A Hand can contain at most four played cards.
      assert(currentHand.length <= 4);

      // Turn indexes must always point to one of the four players.
      assert(currentPlayerIndex >= 0 && currentPlayerIndex < 4);
      assert(dealerIndex >= 0 && dealerIndex < 4);

      // The cards still in players' hands plus cards already played in the
      // Round must always represent the complete 52-card deck exactly once.
      final Set<String> seen = <String>{};
      int totalCards = playedCardsThisRound.length;

      for (final Player player in players) {
        totalCards += player.cards.length;
        for (final CardModel card in player.cards) {
          assert(seen.add(cardKey(card)));
        }
      }

      for (final CardModel card in playedCardsThisRound) {
        assert(seen.add(cardKey(card)));
      }


      assert(totalCards == 52);
      return true;
    }());
  }

  // ==========================================================
  // START NEW GAME
  // ==========================================================

  void startNewGame() {
    players = [
      Player(
        name: _playerName.isEmpty ? 'YOU' : _playerName,
        isHuman: true,
        avatarIndex: _selectedAvatarIndex,
      ),
      Player(
        name: 'BOT 1',
        isHuman: false,
      ),
      Player(
        name: 'BOT 2',
        isHuman: false,
      ),
      Player(
        name: 'BOT 3',
        isHuman: false,
      ),
    ];

    roundNumber = 1;
    handNumber = 1;
    _currentGameStatsRecorded = false;

    // Random dealer for Round 1.
    dealerIndex = random.nextInt(4);

    currentPlayerIndex = 0;

    spadeQueenCollector = null;
    spadeQueenPlayedThisRound = false;

    for (int i = 0; i < 4; i++) {
      roundPenaltyByPlayer[i] = 0;
    }

    currentHand.clear();
    ledSuit = null;

    roundFinished = false;
    gameOver = false;
    exchangePhase = false;
    handCollecting = false;
    collectingWinnerIndex = null;
    dealingPhase = false;
    dealtCardCount = 0;
    dealingStartingPlayer = 0;
    _dealingGeneration++;

    selectedExchangeCards.clear();
    exchangeSelections.clear();

    passedCardsByPlayer.clear();
    receivedCardsByPlayer.clear();
    playedCardsThisRound.clear();
    knownCardOwner.clear();
    playedSuitCounts.addAll({
      'Hearts': 0,
      'Diamonds': 0,
      'Clubs': 0,
      'Spades': 0,
    });
    resetVoidMemory();

    resetLeadTracking();

    gameStarted = true;
    

    dealRound();

    setState(() {});
  }

  // ==========================================================
  // DEALER POPUP
  // ==========================================================

  Future<bool> showDealerPopup() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'DEALER',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '${players[dealerIndex].name} is the dealer for this round.',
            textAlign: TextAlign.center,
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('SHUFFLE & DEAL'),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  // ==========================================================
  // DEAL ROUND
  // ==========================================================

  Future<void> dealRound() async {
    final shouldDeal = await showDealerPopup();
    if (!shouldDeal || !mounted) {
      return;
    }

    List<CardModel> deck = createDeck();

    deck.shuffle(random);

    // Clear all hands.
    for (Player player in players) {
      player.cards.clear();
    }

    // A new Round starts a fresh 35-point penalty pool.
    for (int i = 0; i < 4; i++) {
      roundPenaltyByPlayer[i] = 0;
    }

    // A new Round must start with a completely fresh played-card
    // collection. This is important because the previous Round already
    // contains 52 cards in playedCardsThisRound. Clearing it here, before
    // the stability check below, prevents Round 2+ from being seen as a
    // 104-card state (52 old + 52 newly dealt) in debug mode.
    playedCardsThisRound.clear();
    knownCardOwner.clear();
    playedSuitCounts.clear();
    playedSuitCounts.addAll({
      'Hearts': 0,
      'Diamonds': 0,
      'Clubs': 0,
      'Spades': 0,
    });
    resetVoidMemory();

    // Dealer's RIGHT-side player starts.
    int startingPlayer = (dealerIndex + 1) % 4;

    int playerIndex = startingPlayer;

    // Deal one card at a time anticlockwise.
    for (CardModel card in deck) {
      players[playerIndex].cards.add(card);

      playerIndex = (playerIndex + 1) % 4;
    }

    // Every player should have exactly 13.
    for (Player player in players) {
      assert(player.cards.length == 13);
    }

    _runGameplayStabilityChecks();

    currentHand.clear();
    ledSuit = null;
    handCollecting = false;
    collectingWinnerIndex = null;

    handNumber = 1;

    currentPlayerIndex = startingPlayer;

    resetLeadTracking();

    spadeQueenPlayedThisRound = false;

    // ========================================================
    // BEGIN DEALING ANIMATION
    // ========================================================

    exchangePhase = false;
    dealingPhase = true;
    dealtCardCount = 0;
    dealingStartingPlayer = startingPlayer;
    selectedExchangeCards.clear();

    final int generation = ++_dealingGeneration;

    // IMPORTANT: publish the dealing state before starting the animation.
    // On later Rounds the dealer dialog is awaited, so relying on the
    // caller's setState can leave the UI on the Round summary while the
    // asynchronous dealing sequence is already running.
    message = 'Dealing cards...';
    exchangeSelections.clear();

    passedCardsByPlayer.clear();
    receivedCardsByPlayer.clear();

    if (mounted) {
      setState(() {});
    }

    // Start only after the dealing screen has been rendered.
    await _runDealingAnimation(generation);
  }

  // ==========================================================
  // DEALING ANIMATION
  // ==========================================================

  Future<void> _runDealingAnimation(int generation) async {
    // A short pause lets the table settle before the first card moves.
    await Future.delayed(const Duration(milliseconds: 180));

    for (int count = 1; count <= 52; count++) {
      await Future.delayed(const Duration(milliseconds: 72));

      if (!mounted || generation != _dealingGeneration) {
        return;
      }

      setState(() {
        dealtCardCount = count;
      });

      if (count == 1 || count % 4 == 0 || count == 52) {
        
      }
    }

    await Future.delayed(const Duration(milliseconds: 360));

    if (!mounted || generation != _dealingGeneration) {
      return;
    }

    setState(() {
      dealingPhase = false;
      exchangePhase = true;
      message =
          'Select exactly 4 cards to pass to the player on your LEFT.';
    });
  }

  int dealtCountForPlayer(int playerIndex) {
    if (dealtCardCount <= 0) {
      return 0;
    }

    final int offset =
        (playerIndex - dealingStartingPlayer + 4) % 4;

    if (dealtCardCount <= offset) {
      return 0;
    }

    final int count =
        ((dealtCardCount - 1 - offset) ~/ 4) + 1;

    return min(13, count);
  }

  Widget _buildShuffleCardBack({required double opacity}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 58,
        height: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff173f35),
              Color(0xff09261f),
            ],
          ),
          border: Border.all(
            color: const Color(0xffc8a45d),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '♠',
            style: TextStyle(
              color: Color(0xffe3c27a),
              fontSize: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildDealingPanel() {
    final int currentDealTarget =
        dealtCardCount == 0
            ? -1
            : (dealingStartingPlayer + dealtCardCount - 1) % 4;

    final List<String> positions = [
      'YOU',
      'BOT 1',
      'BOT 2',
      'BOT 3',
    ];

    final List<Alignment> alignments = [
      Alignment.bottomCenter,
      Alignment.centerRight,
      Alignment.topCenter,
      Alignment.centerLeft,
    ];

    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          children: [
            Text(
              'DEALING THE ROUND',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Round $roundNumber • 52 cards',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 82,
                      height: 106,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(-9, 5),
                            child: Transform.rotate(
                              angle: -0.12,
                              child: _buildShuffleCardBack(
                                opacity: 0.72,
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(9, 3),
                            child: Transform.rotate(
                              angle: 0.12,
                              child: _buildShuffleCardBack(
                                opacity: 0.86,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: (dealtCardCount % 8) / 8,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: _buildShuffleCardBack(
                              opacity: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (int i = 0; i < 4; i++)
                    Align(
                      alignment: alignments[i],
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: i == currentDealTarget ? 92 : 86,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: i == currentDealTarget
                              ? const Color(0xfff5e3b2)
                              : const Color(0xfff4f5f2),
                          border: Border.all(
                            color: i == currentDealTarget
                                ? const Color(0xffc8a45d)
                                : const Color(0xffd2d6d0),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              positions[i],
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                                '${dealtCountForPlayer(i)} / 13',                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (currentDealTarget >= 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: alignments[currentDealTarget],
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xffc8a45d),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
                dealtCardCount >= 52
                    ? 'Deal complete'
                    : '$dealtCardCount / 52 cards dealt',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82),
                ),
              ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: dealtCardCount / 52,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // RESET SUIT-VOID MEMORY
  // ==========================================================

  void resetVoidMemory() {
    for (int i = 0; i < voidSuitsByPlayer.length; i++) {
      voidSuitsByPlayer[i].clear();
    }
  }

  // ==========================================================
  // RESET LEAD TRACKING
  // ==========================================================

  void resetLeadTracking() {
    lastLedSuitByPlayer = [
      null,
      null,
      null,
      null,
    ];

    consecutiveLeadCountByPlayer = [
      0,
      0,
      0,
      0,
    ];
  }

  // ==========================================================
  // EXCHANGE CARD SELECTION
  // ==========================================================

  void toggleExchangeCard(CardModel card) {
    if (!exchangePhase) {
      return;
    }

    if (selectedExchangeCards.contains(card)) {
      selectedExchangeCards.remove(card);
      unawaited(_playFeedback());
    } else {
      if (selectedExchangeCards.length >= 4) {
        message = 'You can select only 4 cards.';
        setState(() {});
        return;
      }

      selectedExchangeCards.add(card);
      unawaited(_playFeedback());

      // Show the ♠Q exchange reminder immediately when ♠Q is selected
      // by itself while another Spade is still in the player's hand.
      if (card.isSpadeQueen &&
          players[0].cards.where((c) => c.suit == 'Spades').length > 1 &&
          selectedExchangeCards.where((c) => c.suit == 'Spades').length == 1 &&
          _ruleRemindersEnabled) {
        unawaited(
          _showSmoothHint(
            title: '♠Q EXCHANGE RULE',
            message:
                'You cannot pass ♠Q alone when you have another Spade. '
                'Select at least one more Spade with ♠Q. '
                'If ♠Q is your only Spade, no additional Spade is required.',
            scenario: _hintScenario(
              label: 'Pass ♠Q + another Spade',
              cards: [
                _hintCard(rank: 'Q', suit: 'Spades', highlighted: true),
                _hintCard(rank: 'A', suit: 'Spades', highlighted: true),
              ],
              arrow: '✓',
            ),
          ),
        );
      }
    }

    setState(() {});
  }

  // ==========================================================
  // CHECK EXCHANGE RULE
  // ==========================================================

  bool isLegalExchangeSelection(
    List<CardModel> selected,
    List<CardModel> hand,
  ) {
    // Must be exactly 4.
    if (selected.length != 4) {
      return false;
    }

    // Check whether ♠Q is being passed.
    bool containsQueen = selected.any(
      (card) => card.isSpadeQueen,
    );

    // If ♠Q isn't being passed, everything is fine.
    if (!containsQueen) {
      return true;
    }

    // Count Spades in the player's complete hand.
    int spadesInHand = hand.where(
      (card) => card.suit == 'Spades',
    ).length;

    // Count Spades being passed.
    int spadesSelected = selected.where(
      (card) => card.suit == 'Spades',
    ).length;

    // If ♠Q is the only Spade,
    // it can be passed with any other 3 cards.
    if (spadesInHand == 1) {
      return true;
    }

    // If there is another Spade in the hand,
    // at least one other Spade must go with ♠Q.
    return spadesSelected >= 2;
  }

  // ==========================================================
  // HUMAN CONFIRMS EXCHANGE
  // ==========================================================

  void confirmHumanExchange() {
    if (selectedExchangeCards.length != 4) {
      message = 'Please select exactly 4 cards.';
      setState(() {});
      return;
    }

    bool legal = isLegalExchangeSelection(
      selectedExchangeCards,
      players[0].cards,
    );

    if (!legal) {
      message =
          '♠Q rule: if you have another Spade, you must pass at least one more Spade with ♠Q.';
      setState(() {});
      return;
    }

    // Store YOUR selection.
    exchangeSelections[0] =
        List<CardModel>.from(selectedExchangeCards);

    // ========================================================
    // BOT SELECTIONS
    // ========================================================

    for (int i = 1; i < 4; i++) {
      exchangeSelections[i] =
          chooseBotExchangeCards(players[i]);
    }

    // Now perform the simultaneous exchange.
    performExchange();

    setState(() {});
  }

  // ==========================================================
  // BOT EXCHANGE
  // ==========================================================

  double scoreStrategicExchange(
    int botIndex,
    List<CardModel> selection,
    List<CardModel> hand,
  ) {
    double score = 0;
    final int targetIndex = (botIndex + 3) % 4;
    final int targetScore = players[targetIndex].score;
    final List<CardModel> remaining = List<CardModel>.from(hand)
      ..removeWhere((card) => selection.contains(card));

    // The four cards are passed LEFT. Favor cards that are dangerous for us
    // when the recipient is already under heavy score pressure.
    for (final CardModel card in selection) {
      if (targetScore >= 94) {
        score += card.penalty * 34;
      } else if (targetScore >= 88) {
        score += card.penalty * 22;
      } else if (targetScore >= 70) {
        score += card.penalty * 9;
      }

      // High zero-point cards can become forced winners later. Passing one
      // away is useful, but less important than passing an actual penalty.
      if (card.penalty == 0 && card.value >= 12) {
        score += targetScore >= 88 ? 15 : 7;
      }
    }

    // Prefer exchange packages that create a future void. A void can let the
    // BOT discard a penalty when that suit is led later.
    const suits = ['Hearts', 'Diamonds', 'Clubs', 'Spades'];
    for (final String suit in suits) {
      final int before = hand.where((c) => c.suit == suit).length;
      final int after = remaining.where((c) => c.suit == suit).length;
      if (before > 0 && after == 0) {
        score += suit == 'Spades' ? 145 : 105;
      }

      // Removing a singleton high card is particularly useful because it
      // eliminates a likely forced winner.
      if (before == 1 && after == 0) {
        final CardModel single = hand.firstWhere((c) => c.suit == suit);
        if (single.value >= 11) {
          score += 95;
        }
      }
    }

    // Protect compact low-card structures in the remaining hand.
    for (final String suit in suits) {
      final List<CardModel> left =
          remaining.where((c) => c.suit == suit).toList();
      if (left.length >= 2 && left.every((c) => c.value <= 7)) {
        score += left.length * 18;
      }
    }

    // Do not exchange away too much of a useful low-Spade structure merely
    // to remove ♠Q. The existing legality rule remains authoritative.
    final List<CardModel> selectedSpades =
        selection.where((c) => c.suit == 'Spades').toList();
    final List<CardModel> remainingSpades =
        remaining.where((c) => c.suit == 'Spades').toList();
    if (selectedSpades.any((c) => c.isSpadeQueen) &&
        remainingSpades.length >= 2 &&
        remainingSpades.every((c) => c.value <= 7)) {
      score -= 260;
    }

    // In the final part of a Round, immediate penalty removal becomes more
    // important than preserving a speculative future combination.
    if (isLateRound()) {
      for (final CardModel card in selection) {
        score += card.penalty * 18;
      }
    }

    return score;
  }

  List<CardModel> chooseBotExchangeCards(Player bot) {
    List<CardModel> hand = List<CardModel>.from(bot.cards);

    List<CardModel> bestSelection = [];
    double bestScore = -double.infinity;

    // Examine every legal 4-card combination. The scoring intentionally
    // balances immediate penalty removal with future suit control.
    for (int a = 0; a < hand.length - 3; a++) {
      for (int b = a + 1; b < hand.length - 2; b++) {
        for (int c = b + 1; c < hand.length - 1; c++) {
          for (int d = c + 1; d < hand.length; d++) {
            List<CardModel> selection = [
              hand[a],
              hand[b],
              hand[c],
              hand[d],
            ];

            if (!isLegalExchangeSelection(selection, hand)) {
              continue;
            }

            final int botIndex = players.indexOf(bot);
            double score = 0;

            // V42.33: score the exchange as a four-card strategic package.
            // This considers the recipient on the LEFT, future void creation,
            // dangerous cards, and the strength of the hand that remains.
            score += scoreStrategicExchange(botIndex, selection, hand);

            int passedPenalty = selection.fold(
              0,
              (sum, card) => sum + card.penalty,
            );

            // The BOT passes LEFT.  Prefer sending dangerous penalty cards
            // to an opponent who is already under the greatest score pressure.
            final int exchangeTarget =
                botIndex >= 0 ? (botIndex + 3) % 4 : -1;
            if (exchangeTarget >= 0 && exchangeTarget != botIndex) {
              final int targetScore = players[exchangeTarget].score;
              final double targetMultiplier = targetScore >= 94
                  ? 75
                  : targetScore >= 88
                      ? 48
                      : targetScore >= 70
                          ? 18
                          : 5;
              score += passedPenalty * targetMultiplier;

              // A high-score target is also a good reason to give away
              // dangerous zero-point cards that could otherwise force the BOT
              // to win a later Hand.
              if (targetScore >= 88) {
                for (final CardModel card in selection) {
                  if (card.penalty == 0 && card.value >= 12) {
                    score += 12;
                  }
                }
              }
            }

            // Penalty cards are valuable to pass, but not at the expense of
            // destroying a useful low-card suit unnecessarily.
            score += passedPenalty * 140;

            // Explicit danger ordering: ♠Q, ♣K, ♦J, then Hearts.
            for (CardModel card in selection) {
              if (card.isSpadeQueen) {
                score += 700;
              } else if (card.suit == 'Clubs' && card.rank == 'K') {
                score += 360;
              } else if (card.suit == 'Diamonds' && card.rank == 'J') {
                score += 240;
              } else if (card.suit == 'Hearts') {
                score += 35;
              }
            }

            // Look at the hand that remains after the exchange.
            List<CardModel> remaining = List<CardModel>.from(hand)
              ..removeWhere((card) => selection.contains(card));

            const suits = ['Hearts', 'Diamonds', 'Clubs', 'Spades'];
            for (String suit in suits) {
              int before = hand.where((c) => c.suit == suit).length;
              int after = remaining.where((c) => c.suit == suit).length;

              // A void can be extremely valuable for future penalty dumping.
              if (before > 0 && after == 0) {
                score += suit == 'Spades' ? 300 : 180;
              }

              // Especially valuable: removing a singleton high card and
              // creating a void without throwing away a long low suit.
              if (before == 1 && after == 0) {
                CardModel single = hand.firstWhere((c) => c.suit == suit);
                if (single.value >= 11) {
                  score += 190;
                }
              }
            }

            // Keep low-card followers when they give us future control.
            for (String suit in suits) {
              List<CardModel> remainingSuit = remaining
                  .where((c) => c.suit == suit)
                  .toList();
              if (remainingSuit.length >= 3 &&
                  remainingSuit.every((c) => c.value <= 7)) {
                score += 130;
              }
            }

            // Do not strip a useful set of tiny Spades merely to shed ♠Q.
            List<CardModel> selectedSpades = selection
                .where((c) => c.suit == 'Spades')
                .toList();
            List<CardModel> remainingSpades = remaining
                .where((c) => c.suit == 'Spades')
                .toList();
            if (selectedSpades.any((c) => c.isSpadeQueen) &&
                remainingSpades.length >= 2 &&
                remainingSpades.every((c) => c.value <= 7)) {
              score -= 420;
            }

            // Mild preference for moving isolated high zero-point cards that
            // could otherwise force us to win a later trick.
            for (CardModel card in selection) {
              if (card.penalty == 0 && card.value >= 12) {
                score += 22;
              }
            }

            if (score > bestScore) {
              bestScore = score;
              bestSelection = List<CardModel>.from(selection);
            }
          }
        }
      }
    }

    if (bestSelection.length == 4) {
      return bestSelection;
    }

    // Safety fallback.
    for (int a = 0; a < hand.length - 3; a++) {
      for (int b = a + 1; b < hand.length - 2; b++) {
        for (int c = b + 1; c < hand.length - 1; c++) {
          for (int d = c + 1; d < hand.length; d++) {
            List<CardModel> selection = [
              hand[a],
              hand[b],
              hand[c],
              hand[d],
            ];
            if (isLegalExchangeSelection(selection, hand)) {
              return selection;
            }
          }
        }
      }
    }

    return bestSelection;
  }

  // ==========================================================
  // PERFORM EXCHANGE
  // ==========================================================

  void performExchange() {
    // Make sure every player has a selection.
    for (int i = 0; i < 4; i++) {
      if (!exchangeSelections.containsKey(i)) {
        return;
      }

      if (exchangeSelections[i]!.length != 4) {
        return;
      }
    }

    // Make independent copies.
    List<List<CardModel>> passedCards = [];

    for (int i = 0; i < 4; i++) {
      passedCards.add(
        List<CardModel>.from(
          exchangeSelections[i]!,
        ),
      );
    }

    // Remember exactly what each player gave away. This becomes strategic
    // knowledge for future Hands.
    for (int i = 0; i < 4; i++) {
      passedCardsByPlayer[i] =
          List<CardModel>.from(passedCards[i]);
    }

    // ========================================================
    // REMOVE ALL 4 CARDS FROM EACH PLAYER FIRST.
    // ========================================================

    for (int i = 0; i < 4; i++) {
      for (CardModel card in passedCards[i]) {
        players[i].cards.remove(card);
      }
    }

    // ========================================================
    // PASS LEFT
    //
    // Player 0 → Player 3
    // Player 1 → Player 0
    // Player 2 → Player 1
    // Player 3 → Player 2
    // ========================================================

    for (int giver = 0; giver < 4; giver++) {
      int receiver = (giver + 3) % 4;

      players[receiver].cards.addAll(
        passedCards[giver],
      );

      receivedCardsByPlayer[receiver] =
          List<CardModel>.from(passedCards[giver]);
    }

    // The exact exchanged cards are now known information.
    rememberOwnershipFromExchange();

    // ========================================================
    // VERIFY 13 CARDS
    // ========================================================

    for (Player player in players) {
      if (player.cards.length != 13) {
        debugPrint(
          'ERROR: ${player.name} has ${player.cards.length} cards after exchange.',
        );
      }
    }

    // ========================================================
    // FINISH EXCHANGE
    // ========================================================

    // Explicitly leave the dealing/exchange screens before rebuilding.
    // This prevents later-round state from leaving the human hand hidden.
    dealingPhase = false;
    exchangePhase = false;
    dealtCardCount = 52;

    selectedExchangeCards.clear();
    exchangeSelections.clear();

    currentHand.clear();
    ledSuit = null;

    // Dealer's right-side player starts Hand 1.
    currentPlayerIndex =
        (dealerIndex + 1) % 4;

    message =
        'Exchange complete. Hand 1 begins.';

    // Ensure the human hand is visible after every exchange, including
    // Round 4 and later.
    if (mounted) {
      setState(() {
        dealingPhase = false;
        exchangePhase = false;
        dealtCardCount = 52;
      });
    }

    if (roundNumber == 1 && handNumber == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstHandHint();
      });
    }

    // If the starting player is a BOT,
    // let the BOT begin.
    if (currentPlayerIndex != 0) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () {
          if (mounted &&
              !exchangePhase &&
              !roundFinished &&
              currentHand.isEmpty) {
            playBotTurn();
          }
        },
      );
    }
  }

  // ==========================================================
  // CARD LEGALITY
  // ==========================================================

  bool isLegalCard(
    int playerIndex,
    CardModel card,
  ) {
    Player player = players[playerIndex];

    if (!player.cards.contains(card)) {
      return false;
    }

    // ========================================================
    // SPECIAL RULE:
    // FIRST CARD OF EVERY ROUND (HAND 1)
    // ========================================================

    if (
      handNumber == 1 &&
      currentHand.isEmpty
    ) {
      // First card must be a non-penalty
      // Club or Diamond.
      return (
        (card.suit == 'Clubs' ||
            card.suit == 'Diamonds') &&
        card.penalty == 0
      );
    }

    // ========================================================
    // A SUIT HAS BEEN LED
    // ========================================================

    if (ledSuit != null) {
      bool hasLedSuit = player.cards.any(
        (c) => c.suit == ledSuit,
      );

      // Must follow suit if possible.
      if (hasLedSuit) {
        return card.suit == ledSuit;
      }

      // ======================================================
      // HAND 1 OF EVERY ROUND
      // If unable to follow suit, a non-penalty card is mandatory
      // when available. This special Hand-1 rule takes priority
      // over the BREY penalty-transfer rule.
      // ======================================================

      if (handNumber == 1) {
        bool hasNonPenalty = player.cards.any(
          (c) => c.penalty == 0,
        );

        if (hasNonPenalty) {
          return card.penalty == 0;
        }
      }

      // ======================================================
      // ♠Q BREY PENALTY-TRANSFER RULE
      //
      // When void in the led suit, if ♠Q is available and a
      // penalty card must be played, ♠Q MUST be used first.
      // A Heart, ♦J or ♣K cannot be used instead.
      //
      // This prevents a player from "missing" the BREY transfer
      // and then throwing ♠Q on a later unrelated-suit Hand.
      // The only normal way to play ♠Q on another-suit Hand is
      // therefore blocked by this rule; ♠Q is meant to be
      // transferred at the first eligible penalty opportunity.
      // ======================================================

      bool hasSpadeQueen = player.cards.any(
        (c) => c.isSpadeQueen,
      );

      if (hasSpadeQueen) {
        // If Hand 1 still has a non-penalty option, the Hand-1
        // rule above already returned true for that card and
        // false for penalty cards.
        return card.isSpadeQueen;
      }

      // ======================================================
      // ALL OTHER HANDS
      // If no ♠Q is available, any legal off-suit card may be used.
      // ======================================================

      return true;
    }

    // ========================================================
    // LEADING A HAND
    // ========================================================

    // Until ♠Q has been played:
    // same player cannot lead the same suit
    // for 3 consecutive Hands.
    if (!spadeQueenPlayedThisRound) {
      String? previousSuit =
          lastLedSuitByPlayer[playerIndex];

      int previousCount =
          consecutiveLeadCountByPlayer[playerIndex];

      if (
        previousSuit == card.suit &&
        previousCount >= 2
      ) {
        return false;
      }
    }

    return true;
  }

  // ==========================================================
  // ILLEGAL CARD MESSAGE
  // ==========================================================

  String getIllegalMessage(
    int playerIndex,
    CardModel card,
  ) {
    if (
      handNumber == 1 &&
      currentHand.isEmpty
    ) {
      return 'First card of every Round must be a non-penalty ♣ or ♦.';
    }

    if (ledSuit != null) {
      bool hasLedSuit = players[playerIndex]
          .cards
          .any((c) => c.suit == ledSuit);

      if (hasLedSuit && card.suit != ledSuit) {
        return 'You must follow the led suit.';
      }

      if (
        !hasLedSuit &&
        handNumber == 1
      ) {
        bool hasNonPenalty = players[playerIndex]
            .cards
            .any((c) => c.penalty == 0);

        if (hasNonPenalty && card.penalty > 0) {
          return 'In Hand 1, if you cannot follow suit, you must play a non-penalty card if you have one.';
        }
      }

      if (!hasLedSuit) {
        bool hasSpadeQueen = players[playerIndex]
            .cards
            .any((c) => c.isSpadeQueen);

        if (hasSpadeQueen) {
          return 'You are void in the led suit, so ♠Q must be used first to transfer the BREY penalty.';
        }
      }
    }

    if (!spadeQueenPlayedThisRound &&
        currentHand.isEmpty) {
      String? previousSuit =
          lastLedSuitByPlayer[playerIndex];

      int previousCount =
          consecutiveLeadCountByPlayer[playerIndex];

      if (
        previousSuit == card.suit &&
        previousCount >= 2
      ) {
        return 'You cannot lead the same suit 3 Hands in a row until ♠Q is played.';
      }
    }

    return 'That card cannot be played now.';
  }

  Future<void> _showHintForIllegalPlay(CardModel card) async {
    if (!mounted) return;

    if (handNumber == 1 && currentHand.isEmpty) {
      await _showRuleHintOnce(
        key: 'first_lead',
        title: 'START WITH A SAFE CARD',
        message:
            'In Hand 1, the opening card must be a non-penalty ♣ or ♦. '
            'Hearts, ♦J, ♣K and ♠Q are penalty cards.',
        scenario: _hintScenario(
          label: 'Choose this ✓, not this ✗',
          cards: [
            _hintCard(rank: '7', suit: 'Clubs', highlighted: true),
            _hintCard(rank: 'Q', suit: 'Spades'),
          ],
          arrow: '  ✓   ✗',
        ),
      );
      return;
    }

    if (ledSuit != null &&
        players[0].cards.any((c) => c.suit == ledSuit) &&
        card.suit != ledSuit) {
      await _showRuleHintOnce(
        key: 'follow_suit',
        title: 'FOLLOW THE SUIT',
        message:
            'When a suit is led, you must play that suit if you have it. '
            'You can play another suit only when you have no card of the led suit.',
        scenario: _hintScenario(
          label: 'Example: ♦ is led',
          cards: [
            _hintCard(rank: '8', suit: 'Diamonds'),
            _hintCard(rank: 'K', suit: 'Diamonds', highlighted: true),
            _hintCard(rank: 'A', suit: 'Spades'),
          ],
          arrow: '→  play ♦K',
        ),
      );
      return;
    }

    if (ledSuit != null &&
        !players[0].cards.any((c) => c.suit == ledSuit) &&
        handNumber == 1 &&
        players[0].cards.any((c) => c.penalty == 0) &&
        card.penalty > 0) {
      await _showRuleHintOnce(
        key: 'hand_one_safe_discard',
        title: 'HAND 1 — AVOID PENALTY',
        message:
            'You cannot follow the led suit. Because this is Hand 1, '
            'play a non-penalty card if you have one.',
        scenario: _hintScenario(
          label: 'No ♦ cards → choose a safe card',
          cards: [
            _hintCard(rank: '5', suit: 'Clubs', highlighted: true),
            _hintCard(rank: '5', suit: 'Hearts'),
          ],
          arrow: '  ✓   ✗',
        ),
      );
      return;
    }

    if (ledSuit != null &&
        !players[0].cards.any((c) => c.suit == ledSuit) &&
        players[0].cards.any((c) => c.isSpadeQueen) &&
        card.penalty > 0 &&
        !card.isSpadeQueen) {
      await _showRuleHintOnce(
        key: 'queen_transfer',
        title: '♠Q TRANSFERS THE BREY PENALTY',
        message:
            'If you cannot follow suit and a penalty card must be played, '
            '♠Q has priority. Playing ♠Q sends its 12-point penalty to the Hand winner.',
        scenario: _hintScenario(
          label: 'You are void in the led suit',
          cards: [
            _hintCard(rank: 'Q', suit: 'Spades', highlighted: true),
            _hintCard(rank: 'K', suit: 'Clubs'),
          ],
          arrow: '→  play ♠Q first',
        ),
      );
      return;
    }

    if (!spadeQueenPlayedThisRound &&
        currentHand.isEmpty &&
        lastLedSuitByPlayer[0] != null &&
        lastLedSuitByPlayer[0] == card.suit &&
        consecutiveLeadCountByPlayer[0] >= 2) {
      await _showRuleHintOnce(
        key: 'lead_limit',
        title: 'CHANGE THE LEAD SUIT',
        message:
            'Until ♠Q is played, you cannot lead the same suit 3 Hands in a row. '
            'Try another legal suit.',
        scenario: _hintScenario(
          label: 'Same suit twice → change suit',
          cards: [
            _hintCard(rank: '6', suit: card.suit, highlighted: true),
          ],
          arrow: '→  choose another suit',
        ),
      );
    }
  }

  // ==========================================================
  // HUMAN PLAY
  // ==========================================================

  void playHumanCard(CardModel card) {
    if (!gameStarted ||
        exchangePhase ||
        roundFinished) {
      return;
    }

    if (currentPlayerIndex != 0) {
      return;
    }

    if (!isLegalCard(0, card)) {
      message = getIllegalMessage(0, card);
      unawaited(_playIllegalMoveFeedback());
      setState(() {});
      if (_beginnerHintsEnabled) {
        _showHintForIllegalPlay(card);
      }
      return;
    }
    playCard(0, card);

    setState(() {});

    // If another BOT needs to play.
    if (
      !exchangePhase &&
      !roundFinished &&
      currentHand.length < 4 &&
      currentPlayerIndex != 0
    ) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () {
          if (mounted) {
            playBotTurn();
          }
        },
      );
    }
  }

  // ==========================================================
  // PLAY CARD
  // ==========================================================

  void playCard(
    int playerIndex,
    CardModel card,
  ) {
    // ========================================================
    // FIRST CARD OF HAND = LEAD
    // ========================================================

    if (currentHand.isEmpty) {
      ledSuit = card.suit;

      if (
        lastLedSuitByPlayer[playerIndex] ==
        card.suit
      ) {
        consecutiveLeadCountByPlayer[playerIndex]++;
      } else {
        lastLedSuitByPlayer[playerIndex] =
            card.suit;

        consecutiveLeadCountByPlayer[playerIndex] = 1;
      }
    }

    // If a player failed to follow the led suit, we learn with certainty
    // that the player was void in that suit. This is valuable memory for
    // future lead and penalty-transfer decisions.
    if (ledSuit != null && currentHand.isNotEmpty && card.suit != ledSuit) {
      voidSuitsByPlayer[playerIndex].add(ledSuit!);
    }

    // Every successful card play gets haptic feedback. This also covers BOT card plays.
    unawaited(_playFeedback());

    // Remove card from player's hand.
    players[playerIndex].cards.remove(card);

    // Add to current Hand.
    currentHand.add(
      PlayedCard(
        playerIndex: playerIndex,
        card: card,
      ),
    );

    playedCardsThisRound.add(card);
    playedSuitCounts[card.suit] = (playedSuitCounts[card.suit] ?? 0) + 1;
    knownCardOwner.remove(cardKey(card));

    // ========================================================
    // ♠Q PLAYED
    // ========================================================

    if (card.isSpadeQueen) {
      unawaited(_playFeedback(strongVibration: true));
      spadeQueenPlayedThisRound = true;

      // The player who collects the Hand containing ♠Q
      // becomes the next dealer.
    }

    // ========================================================
    // HAND NOT COMPLETE
    // ========================================================

    if (currentHand.length < 4) {
      currentPlayerIndex =
          (playerIndex + 1) % 4;

      message =
          '${players[currentPlayerIndex].name} to play.';

      _runGameplayStabilityChecks();
      return;
    }

    // ========================================================
    // HAND COMPLETE
    // ========================================================

    _runGameplayStabilityChecks();
    unawaited(completeHand());
  }

  // ==========================================================
  // BOT TURN
  // ==========================================================

  void playBotTurn() {
    if (!mounted) {
      return;
    }

    if (exchangePhase ||
        roundFinished ||
        currentHand.length >= 4) {
      return;
    }

    if (currentPlayerIndex == 0) {
      return;
    }

    Player bot = players[currentPlayerIndex];

    CardModel chosenCard =
        chooseBotCard(
      currentPlayerIndex,
      bot,
    );

    playCard(
      currentPlayerIndex,
      chosenCard,
    );

    setState(() {});

    // Continue BOT turns.
    if (
      !exchangePhase &&
      !roundFinished &&
      currentHand.length < 4 &&
      currentPlayerIndex != 0
    ) {
      Future.delayed(
        const Duration(milliseconds: 550),
        () {
          if (mounted) {
            playBotTurn();
          }
        },
      );
    }
  }


  String cardKey(CardModel card) => '${card.suit}|${card.rank}';

  void rememberOwnershipFromExchange() {
    knownCardOwner.clear();
    for (int receiver = 0; receiver < 4; receiver++) {
      final List<CardModel> received =
          receivedCardsByPlayer[receiver] ?? const <CardModel>[];
      for (final CardModel card in received) {
        knownCardOwner[cardKey(card)] = receiver;
      }
    }
  }

  // ==========================================================
  // V1.2.1 PUBLIC CARD MEMORY / REMAINING-CARD INTELLIGENCE
  // ==========================================================
  // The BOT remembers every card that has been publicly played in the
  // current Round and derives the cards that are still unseen. It never
  // treats an opponent's hidden hand as public information.

  List<CardModel> remainingUnseenCards() {
    final List<CardModel> deck = createDeck();
    final Set<String> seen = <String>{
      ...playedCardsThisRound.map(cardKey),
    };
    return deck.where((card) => !seen.contains(cardKey(card))).toList();
  }

  List<CardModel> remainingUnseenSuitCards(String suit) {
    return remainingUnseenCards()
        .where((card) => card.suit == suit)
        .toList();
  }

  bool isCardStillUnseen(CardModel card) {
    return !playedCardsThisRound.any(
      (played) => cardKey(played) == cardKey(card),
    );
  }

  int remainingCardsOfSuitAbove(String suit, int value) {
    return remainingUnseenSuitCards(suit)
        .where((card) => card.value > value)
        .length;
  }

  int remainingPenaltyInSuit(String suit) {
    return remainingUnseenSuitCards(suit)
        .fold<int>(0, (sum, card) => sum + card.penalty);
  }

  // Estimate which player can realistically win the current Hand using
  // only cards already visible on the table plus each player's known voids.
  // This is deliberately conservative: unknown cards remain unknown.
  int likelyCurrentHandWinnerFor(int botIndex) {
    if (currentHand.isEmpty || ledSuit == null) return -1;

    final int currentWinner = determineCurrentWinner();
    if (currentHand.length >= 4) return currentWinner;

    final int winningValue = currentHand
        .where((played) => played.card.suit == ledSuit)
        .fold<int>(-1, (best, played) =>
            played.card.value > best ? played.card.value : best);

    // If every unplayed card above the current winner is already known to be
    // unavailable (publicly played or held by this BOT), the current winner
    // is effectively protected.
    final int higherRemaining = remainingCardsOfSuitAbove(
      ledSuit!,
      winningValue,
    );

    final int higherInBot = players[botIndex]
        .cards
        .where((card) => card.suit == ledSuit && card.value > winningValue)
        .length;

    if (higherRemaining <= higherInBot) {
      return currentWinner;
    }

    return currentWinner;
  }

  // Score a candidate according to the cards that are still alive.
  // The key idea is: if a candidate can safely lose, allow another player
  // to retain the Hand; if the current winner is protected by card-counting,
  // do not waste a higher card trying to overtake them.
  double scoreRemainingCardMemory(
    int botIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    final int higherRemaining = remainingCardsOfSuitAbove(
      candidate.suit,
      candidate.value,
    );

    // A high card becomes safer after all cards above it disappear.
    if (higherRemaining == 0) {
      score += winning ? 20 : -20;
    } else if (higherRemaining == 1) {
      score += winning ? 8 : -6;
    }

    // Preserve low cards when many cards of the suit remain; they are useful
    // exits for future Hands. Conversely, when the suit is nearly exhausted,
    // spending a low card can manufacture control/void opportunities.
    final int suitRemaining = remainingUnseenSuitCards(candidate.suit).length;
    if (candidate.value <= 7 && candidate.penalty == 0) {
      score += suitRemaining >= 6 ? 8 : 16;
    }

    // If the candidate is a penalty card and another player is currently
    // winning, unloading it onto that winner can be valuable.
    final int currentWinner = likelyCurrentHandWinnerFor(botIndex);
    if (!winning && currentWinner >= 0 && currentWinner != botIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94) {
        score += candidate.penalty * 18;
      } else if (targetScore >= 88) {
        score += candidate.penalty * 10;
      } else {
        score += candidate.penalty * 3;
      }
    }

    // When a Hand already contains penalty, deliberately keeping another
    // player ahead can be preferable to taking the Hand ourselves.
    final int visiblePenalty = currentHandPenaltyTotal().round();
    if (!winning && currentWinner >= 0 && currentWinner != botIndex) {
      score += visiblePenalty * 4;
    }

    return score;
  }

  // Public-memory decision: determine whether a bot should deliberately
  // avoid overtaking the current winner. This is the central behaviour the
  // previous random strategy was missing.
  bool shouldLetCurrentWinnerKeepHand(int botIndex) {
    if (currentHand.isEmpty) return false;
    final int winner = determineCurrentWinner();
    if (winner < 0 || winner == botIndex) return false;

    final int penalty = currentHandPenaltyTotal().round();
    final int targetScore = players[winner].score;

    // A loaded Hand should normally stay with another player, particularly
    // when that player is approaching the danger zone.
    if (penalty >= 6) return true;
    if (targetScore >= 94 && penalty >= 2) return true;
    if (targetScore >= 88 && penalty >= 3) return true;

    // If the visible card count says the current winner has no realistic
    // higher-card threat, there is no reason to overtake them.
    return remainingCardsOfSuitAbove(
          ledSuit!,
          currentHand.first.card.value,
        ) <= 1;
  }

  int unseenCardsOfSuit(String suit) {
    final int played = playedSuitCounts[suit] ?? 0;
    return 13 - played;
  }

  bool knownDangerousCardWithOpponent(
    int opponent,
    String suit,
  ) {
    final List<CardModel> known =
        receivedCardsByPlayer[opponent] ?? const <CardModel>[];
    return known.any((card) =>
        card.suit == suit && card.penalty > 0 &&
        !playedCardsThisRound.any((c) => cardKey(c) == cardKey(card)));
  }

  int countKnownCardsOfSuitForOpponent(
    int opponent,
    String suit,
  ) {
    final List<CardModel> known =
        receivedCardsByPlayer[opponent] ?? const <CardModel>[];
    return known.where((card) =>
        card.suit == suit &&
        !playedCardsThisRound.any((c) => cardKey(c) == cardKey(card))).length;
  }

  double futureDangerScore(CardModel card, int botIndex) {
    double score = 0;
    if (card.isSpadeQueen) {
      score += 1000;
    }
    if (card.suit == 'Clubs' && card.rank == 'K') {
      score += 520;
    }
    if (card.suit == 'Diamonds' && card.rank == 'J') {
      score += 360;
    }
    if (card.suit == 'Hearts') {
      score += 55;
    }

    // A high card in a short suit is more dangerous because it is harder to
    // shed without taking the Hand.
    final int suitCount = players[botIndex].cards
        .where((c) => c.suit == card.suit).length;
    if (suitCount <= 2 && card.value >= 11) {
      score += 120;
    }

    // A singleton high card is especially likely to become a forced winner
    // after the BOT becomes void elsewhere.
    if (suitCount == 1 && card.value >= 11) {
      score += 170;
    }

    return score;
  }

  double evaluateFutureSuitControl(
    int botIndex,
    CardModel candidate,
  ) {
    final Player bot = players[botIndex];
    double score = 0;
    final String suit = candidate.suit;
    final List<CardModel> ownSuit =
        bot.cards.where((c) => c.suit == suit).toList();

    // Prefer having low followers in a suit.
    final int lowCount = ownSuit.where((c) => c.value <= 7).length;
    score += lowCount * 9;

    // Prefer creating a void in an otherwise awkward suit, but do not break
    // a strong low-card structure just to remove one zero-point card.
    if (ownSuit.length == 1) {
      score += 95;
    }
    if (ownSuit.length == 2) {
      score += 25;
    }

    // Spade structure is special because ♠Q is the biggest single threat.
    if (suit == 'Spades' && !spadeQueenPlayedThisRound) {
      final bool hasQueen = ownSuit.any((c) => c.isSpadeQueen);
      if (hasQueen && ownSuit.length >= 3 &&
          ownSuit.where((c) => c.value <= 7).length >= 2) {
        score += 110;
      }
    }

    return score;
  }

  // Estimates which player is most likely to win a Hand with the candidate
  // lead. This uses only public play history, exchange knowledge and voids.
  double estimateLeadTargetValue(int botIndex, String suit) {
    double score = 0;
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) {
        continue;
      }
      if (voidSuitsByPlayer[opponent].contains(suit)) {
        // A void player is a likely outlet for a penalty card when the suit
        // is led; this is useful when that player is near 100.
        if (players[opponent].score >= 88) {
          score += 32;
        }
        if (knownDangerousCardWithOpponent(opponent, suit)) {
          score += 18;
        }
      }

      final int known = countKnownCardsOfSuitForOpponent(opponent, suit);
      score += known * (players[opponent].score >= 88 ? 6.0 : 1.5);
    }
    return score;
  }

  // ==========================================================
  // ==========================================================
  // FULL HAND SIMULATION — ESTIMATE THE OUTCOME AFTER THIS CARD
  // ==========================================================

  double scoreFullHandSimulation(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    if (currentHand.isEmpty) return 0;

    final String suit = ledSuit!;
    final List<PlayedCard> simulated = List<PlayedCard>.from(currentHand)
      ..add(PlayedCard(playerIndex: playerIndex, card: candidate));

    int winner = simulated.first.playerIndex;
    int winningValue = simulated.first.card.suit == suit
        ? simulated.first.card.value
        : -1;
    for (final PlayedCard played in simulated) {
      if (played.card.suit == suit && played.card.value >= winningValue) {
        winner = played.playerIndex;
        winningValue = played.card.value;
      }
    }

    final int penalty = simulated.fold<int>(
      0,
      (total, played) => total + played.card.penalty,
    );
    final int winnerScore = players[winner].score;
    double score = 0;

    if (winning && winner == playerIndex) {
      if (penalty == 0) {
        score += 70;
      } else if (penalty <= 4) {
        score += 45;
      } else if (penalty <= 10) {
        score += 12;
      } else {
        score -= penalty * 4.0;
      }
      // Winning the Hand gives the BOT the next lead.
      score += 30;
      if (handNumber >= 11) score += 15;
    }

    if (!winning && winner != playerIndex) {
      if (penalty >= 12) score += 30;
      if (winnerScore >= 94) {
        score += penalty * 3.5;
      } else if (winnerScore >= 88) {
        score += penalty * 1.8;
      }
    }

    // The fourth player has the most complete information about this Hand.
    final int leadPlayer = currentHand.first.playerIndex;
    final int turnPosition = ((playerIndex - leadPlayer) + 4) % 4 + 1;
    if (turnPosition == 4) {
      if (penalty == 0) score += winning ? 35 : -12;
      if (penalty >= 12) score += winning ? -25 : 20;
    }

    score += evaluatePostPlayPosition(playerIndex, candidate) * 0.6;
    return score;
  }

  // BOT CARD CHOICE — FULL STRATEGIC ENGINE
  // ==========================================================

  int remainingCardsOfSuit(String suit, {CardModel? exclude}) {
    int remaining = 13 - (playedSuitCounts[suit] ?? 0);
    for (final Player player in players) {
      remaining -= player.cards.where((c) => c.suit == suit).length;
    }
    // The human hand and all BOT hands are included above, so this is the
    // number not currently visible in any player's hand. Keep it bounded.
    if (exclude != null && exclude.suit == suit) {
      remaining = max(0, remaining - 1);
    }
    return max(0, remaining);
  }

  int cardsHigherThanInUnseen(String suit, int value, int botIndex) {
    int count = 0;
    const ranks = <String>[
      '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'
    ];

    for (final String rank in ranks) {
      final int rankValue = rank == 'A'
          ? 14
          : rank == 'K'
              ? 13
              : rank == 'Q'
                  ? 12
                  : rank == 'J'
                      ? 11
                      : int.parse(rank);

      if (rankValue <= value) continue;

      final CardModel? knownCard = _findCardBySuitAndValue(suit, rankValue);
      if (knownCard == null) continue;

      final String key = cardKey(knownCard);
      final bool played = playedCardsThisRound.any(
        (c) => cardKey(c) == key,
      );
      final bool inOwnHand = players[botIndex].cards.any(
        (c) => cardKey(c) == key,
      );
      final bool knownWithOpponent = knownCardOwner.containsKey(key) &&
          knownCardOwner[key] != botIndex;

      // Only count a card as genuinely unseen when the BOT has no public
      // knowledge placing it in the played pile, its own hand, or a known
      // opponent hand. This prevents the card counter from looking through
      // hidden BOT/player hands.
      if (!played && !inOwnHand && !knownWithOpponent) {
        count++;
      }
    }

    return count;
  }

  CardModel? _findCardBySuitAndValue(String suit, int value) {
    for (final Player player in players) {
      for (final CardModel card in player.cards) {
        if (card.suit == suit && card.value == value) {
          return card;
        }
      }
    }

    for (final CardModel card in playedCardsThisRound) {
      if (card.suit == suit && card.value == value) {
        return card;
      }
    }

    for (final List<CardModel> cards in receivedCardsByPlayer.values) {
      for (final CardModel card in cards) {
        if (card.suit == suit && card.value == value) {
          return card;
        }
      }
    }

    return null;
  }

  int knownOpponentPenaltyInSuit(String suit, int exceptPlayer) {
    int total = 0;
    for (int i = 0; i < 4; i++) {
      if (i == exceptPlayer) continue;
      final List<CardModel> known = receivedCardsByPlayer[i] ?? const <CardModel>[];
      total += known.where((c) =>
          c.suit == suit &&
          c.penalty > 0 &&
          !playedCardsThisRound.any((p) => cardKey(p) == cardKey(c))).length;
    }
    return total;
  }

  double opponentRisk(int botIndex) {
    double risk = 0;
    for (int i = 0; i < 4; i++) {
      if (i == botIndex) continue;
      final int score = players[i].score;
      if (score >= 99) {
        risk += 12;
      } else if (score >= 94) {
        risk += 9;
      } else if (score >= 88) {
        risk += 6;
      } else if (score >= 75) {
        risk += 2;
      }
    }
    return risk;
  }

  bool isLateRound() {
    return handNumber >= 10 ||
        players.every((p) => p.cards.length <= 4);
  }

  bool opponentNearElimination(int botIndex) {
    for (int i = 0; i < 4; i++) {
      if (i == botIndex) continue;
      if (players[i].score >= 94) return true;
    }
    return false;
  }

  // ==========================================================
  // CARD COMBINATION / SEQUENCE INTELLIGENCE
  // ==========================================================

  int _suitSequenceStrength(
    List<CardModel> cards,
    String suit,
    CardModel removed,
  ) {
    final values = cards
        .where((c) => c.suit == suit && cardKey(c) != cardKey(removed))
        .map((c) => c.value)
        .toList()
      ..sort();

    if (values.isEmpty) return 0;

    int strength = 0;
    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 7) strength += 1;
      if (i > 0 && values[i] - values[i - 1] == 1) strength += 3;
      if (i > 1 && values[i] - values[i - 2] == 2) strength += 2;
    }
    return strength;
  }

  double evaluateCardCombination(
    int botIndex,
    CardModel candidate,
  ) {
    final Player bot = players[botIndex];
    final List<CardModel> remaining = bot.cards
        .where((c) => cardKey(c) != cardKey(candidate))
        .toList();

    double score = 0;
    final int suitCount =
        remaining.where((c) => c.suit == candidate.suit).length;
    final int lowCount = remaining
        .where((c) => c.suit == candidate.suit && c.value <= 7)
        .length;
    final int highCount = remaining
        .where((c) => c.suit == candidate.suit && c.value >= 11)
        .length;
    final int sequenceStrength =
        _suitSequenceStrength(bot.cards, candidate.suit, candidate);

    // Preserve connected low cards: they are useful for safely following
    // and can create a controlled exit later.
    if (lowCount >= 2) score += 12;
    if (lowCount >= 3) score += 10;
    if (sequenceStrength >= 4) score += 14;
    if (sequenceStrength >= 7) score += 12;

    // Do not casually break a strong suit combination.
    if (suitCount >= 3 && sequenceStrength >= 5 && candidate.penalty == 0) {
      score -= 20;
    }

    // A high card isolated in a short suit is dangerous; shedding it is
    // valuable, particularly when it also carries penalty points.
    if (suitCount <= 1 && candidate.value >= 11) score += 30;
    if (suitCount <= 2 && highCount >= 1 && candidate.value >= 11) score += 12;

    // A singleton can be strategically valuable because it can create a void,
    // but singleton high cards are much more urgent to unload.
    if (suitCount == 0) {
      score += candidate.penalty > 0 ? 28 : 16;
    }

    // Keep multiple low exits in other suits when possible.
    int lowExitSuits = 0;
    for (final String suit in const ['Hearts', 'Diamonds', 'Clubs', 'Spades']) {
      final int count = remaining
          .where((c) => c.suit == suit && c.value <= 7 && c.penalty == 0)
          .length;
      if (count >= 1) lowExitSuits++;
    }
    score += lowExitSuits * 5;

    return score;
  }

  double strategicCardValue(
    int botIndex,
    CardModel card, {
    bool leading = false,
    bool forcedWinner = false,
  }) {
    final Player bot = players[botIndex];
    double score = 0;
    final int suitCount = bot.cards.where((c) => c.suit == card.suit).length;
    final int lowCards = bot.cards
        .where((c) => c.suit == card.suit && c.value <= 7)
        .length;

    // --------------------------------------------------------
    // Immediate penalty management
    // --------------------------------------------------------
    score -= card.penalty * 95;
    score -= futureDangerScore(card, botIndex) * 0.16;

    if (card.isSpadeQueen && !spadeQueenPlayedThisRound) {
      score -= 260;
      if (bot.cards.where((c) => c.suit == 'Spades').length <= 2) {
        score -= 100;
      }
    }

    // --------------------------------------------------------
    // Endgame planning
    // --------------------------------------------------------
    // When only a few cards remain, immediate card safety matters more than
    // preserving a long-term suit structure. The BOT therefore becomes more
    // focused on unloading penalties and avoiding forced winners.
    if (isLateRound()) {
      if (card.penalty > 0) {
        score += card.penalty * 42;
      }

      if (card.value >= 12 && card.penalty == 0) {
        score -= 22;
      }

      if (suitCount == 1 && card.penalty == 0 && card.value <= 7) {
        score += 30;
      }

      // Keep a useful low card when it can serve as a safe follower later.
      if (suitCount >= 2 && card.value <= 7 && card.penalty == 0) {
        score -= 18;
      }

      // With a dangerous opponent close to 100, shedding a penalty is worth
      // more than preserving ordinary card strength.
      if (opponentNearElimination(botIndex) && card.penalty > 0) {
        score += card.penalty * 28;
      }
    }

    // --------------------------------------------------------
    // Suit structure / future control
    // --------------------------------------------------------
    if (suitCount == 1) score += 100;
    if (suitCount == 2) score += 42;
    if (lowCards >= 3) score += 28;
    if (lowCards >= 4) score += 18;

    // Keeping high cards is dangerous when a suit is already short.
    if (suitCount <= 2 && card.value >= 11) score -= 48;
    if (suitCount == 1 && card.value >= 11) score -= 35;

    // Prefer cards that leave a flexible low-card exit in another suit.
    int flexibleLowSuits = 0;
    for (final String suit in const ['Hearts', 'Diamonds', 'Clubs', 'Spades']) {
      if (suit == card.suit) continue;
      final int count = bot.cards.where((c) => c.suit == suit && c.value <= 7).length;
      if (count >= 2) flexibleLowSuits++;
    }
    score += flexibleLowSuits * 8;

    // --------------------------------------------------------
    // Card combination / sequence intelligence
    // --------------------------------------------------------
    score += evaluateCardCombination(botIndex, card) * 1.35;

    // --------------------------------------------------------
    // Card-counting information
    // --------------------------------------------------------
    final int higherUnseen = cardsHigherThanInUnseen(card.suit, card.value, botIndex);
    if (leading) {
      // A low lead is easier to lose; a high lead has a greater chance of
      // taking control of the Hand.
      score += (15 - card.value) * 7;
      score -= higherUnseen * 4.0;
    } else if (forcedWinner) {
      // When a win is unavoidable, use the smallest useful winning card.
      score -= card.value * 7;
      score += higherUnseen * 3.0;
    }

    // --------------------------------------------------------
    // Known opponent holdings / voids
    // --------------------------------------------------------
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final bool voidHere = voidSuitsByPlayer[opponent].contains(card.suit);
      final int knownCount = countKnownCardsOfSuitForOpponent(
        opponent,
        card.suit,
      );

      if (voidHere) {
        score += players[opponent].score >= 88 ? 20 : 8;
      }
      if (knownCount > 0) {
        score += knownCount * (players[opponent].score >= 88 ? 5 : 1.5);
      }

      final List<CardModel> received =
          receivedCardsByPlayer[opponent] ?? const <CardModel>[];
      for (final CardModel known in received) {
        if (known.suit == card.suit && known.penalty > 0 &&
            !playedCardsThisRound.any((p) => cardKey(p) == cardKey(known))) {
          score += penaltyPriority(known) * 9;
        }
      }
    }

    // --------------------------------------------------------
    // Opponent threat / score-aware targeting
    // --------------------------------------------------------
    // Prefer decisions that put penalty risk onto the most dangerous
    // opponent, while avoiding unnecessary aggression against safe players.
    score += opponentRisk(botIndex) * 1.2;

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int targetScore = players[opponent].score;
      final int knownPenalty =
          knownOpponentPenaltyInSuit(card.suit, opponent);

      if (targetScore >= 94) {
        score += knownPenalty * 14;
        if (card.penalty > 0) score += card.penalty * 12;
      } else if (targetScore >= 88) {
        score += knownPenalty * 8;
        if (card.penalty > 0) score += card.penalty * 7;
      }
    }

    if (opponentNearElimination(botIndex)) {
      score += scoreTargetingOpponent(botIndex, card.suit) * 10;
      if (card.penalty > 0) score += card.penalty * 18;
    }

    if (isLateRound()) {
      score += evaluateFutureSuitControl(botIndex, card) * 0.8;
      if (card.penalty == 0) score += 12;
    }

    // Taking a Hand with a large visible penalty is usually bad unless it
    // denies those points to a dangerous opponent.
    if (forcedWinner) {
      final double visiblePenalty = currentHandPenaltyTotal();
      score -= visiblePenalty * 24;
      if (players.any((p) => p.score >= 94 && p != bot)) {
        score += visiblePenalty * 17;
      }
    }

    return score;
  }

  // ==========================================================
  // ADVANCED HAND OUTCOME EVALUATION
  // ==========================================================

  double evaluateHandOutcomeChoice(
    int botIndex,
    CardModel card, {
    bool leading = false,
    bool winning = false,
  }) {
    double score = 0;
    final double penaltyOnTable = currentHandPenaltyTotal();

    // A penalty-free hand is worth protecting; a loaded hand is something
    // the BOT should actively try to avoid winning.
    if (winning) {
      score -= penaltyOnTable * 20;
      if (penaltyOnTable >= 8) score -= 45;
      if (penaltyOnTable >= 15) score -= 70;

      // Taking a loaded hand becomes worthwhile when the current winner is a
      // dangerous opponent close to the elimination threshold.
      final int currentWinner = determineCurrentWinner();
      if (currentWinner >= 0 && currentWinner != botIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += penaltyOnTable * 15;
        } else if (targetScore >= 88) {
          score += penaltyOnTable * 8;
        }
      }
    }

    if (leading) {
      // A low lead is safer when many higher cards remain unseen. A high lead
      // is more likely to take control and should therefore be justified.
      final int higherUnseen =
          cardsHigherThanInUnseen(card.suit, card.value, botIndex);
      score -= higherUnseen * 2.5;

      if (card.value <= 7) score += 18;
      if (card.value >= 12 && higherUnseen > 0) score -= 28;

      // Short suits are useful because they can create future voids.
      final int suitCount =
          players[botIndex].cards.where((c) => c.suit == card.suit).length;
      if (suitCount == 1) score += 24;
      if (suitCount == 2) score += 10;
    }

    // In the closing Hands, shedding penalty cards has greater value than
    // preserving long-term suit control.
    if (isLateRound()) {
      score += card.penalty * 16;
      if (card.penalty == 0 && card.value <= 7) score -= 8;
    }

    return score;
  }

  // ==========================================================
  // DYNAMIC RISK / REWARD — VALUE THE WHOLE CURRENT HAND
  // ==========================================================

  double scoreDynamicRiskReward(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    final Player bot = players[playerIndex];
    final double handPenalty = currentHandPenaltyTotal();
    final int currentWinner = determineCurrentWinner();
    double score = 0;

    score += scoreMultiHandPlanning(
      playerIndex,
      candidate,
      winning: winning,
    );

    // A card is not judged only by its face value.  The BOT compares the
    // immediate Hand result with the position it creates afterward.
    if (winning) {
      // Taking a clean Hand can be useful because the BOT receives the next
      // lead.  Taking a loaded Hand is normally expensive.
      if (handPenalty == 0) {
        score += 38;
      } else if (handPenalty <= 3) {
        score += 14;
      } else if (handPenalty >= 8) {
        score -= 55;
      } else if (handPenalty >= 4) {
        score -= 25;
      }

      // Winning with a penalty card means accepting that penalty ourselves.
      score -= candidate.penalty * 18;

      // If we are taking the Hand with a high card, make sure that the gain
      // in future control is actually worth spending that card.
      if (candidate.value >= 11) {
        score -= 10;
        final int remainingSameSuit = bot.cards
            .where((c) => c.suit == candidate.suit)
            .length - 1;
        if (remainingSameSuit == 0) {
          // Becoming void in this suit can be strategically powerful later.
          score += 22;
        }
      }

      // Denying a dangerous opponent can justify taking a loaded Hand.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += handPenalty * 13;
        } else if (targetScore >= 88) {
          score += handPenalty * 7;
        }
      }

      // The fourth player has seen the complete Hand, so a clean Hand is a
      // much stronger opportunity to take control deliberately.
      if (currentHand.length == 3 && handPenalty <= 2) {
        score += 30;
      }
    } else {
      // Losing is valuable when it leaves the BOT with a stronger future hand.
      score += 18;
      score += evaluatePostPlayPosition(playerIndex, candidate) * 0.75;

      // Shedding a penalty while deliberately losing becomes increasingly
      // valuable late in the Round.
      if (candidate.penalty > 0) {
        score += candidate.penalty * (isLateRound() ? 32 : 14);
      }

      // If a dangerous opponent is already winning, keeping them as the
      // current winner can be better than taking the Hand ourselves.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += 20 + candidate.penalty * 9;
        } else if (targetScore >= 88) {
          score += 12 + candidate.penalty * 5;
        }
      }

      // Do not blindly sacrifice a useful low card just because it loses.
      final int suitCount = bot.cards
          .where((c) => c.suit == candidate.suit)
          .length;
      if (suitCount >= 3 && candidate.value <= 7 && candidate.penalty == 0) {
        score -= 18;
      }

      // Conversely, an isolated dangerous card is often exactly what should
      // be released now rather than preserved for a later forced Hand.
      if (suitCount == 1 && (candidate.value >= 11 || candidate.penalty > 0)) {
        score += 24;
      }
    }

    // Preserve useful low-card exits, but only as a secondary consideration.
    // This prevents the old "always play the smallest card" behaviour.
    if (candidate.value <= 5 && candidate.penalty == 0) {
      score += 5;
    }
    if (candidate.value >= 12 && candidate.penalty == 0) {
      score -= 4;
    }

    return score;
  }

CardModel chooseBotCard(
    int playerIndex,
    Player bot,
  ) {
    if (currentHand.isEmpty) {
      return chooseBotLeadCard(playerIndex, bot);
    }

    final String suit = ledSuit!;
    final List<CardModel> sameSuit = bot.cards
        .where((c) => c.suit == suit)
        .toList();

    if (sameSuit.isNotEmpty) {
      return chooseSmartFollowingCard(playerIndex, bot, sameSuit);
    }

    return chooseSmartDiscardCard(playerIndex, bot);
  }

  // ==========================================================
  // ADAPTIVE VOID TARGETING
  // ==========================================================

  double scoreVoidTargetingLead(int botIndex, String suit) {
    double score = 0;

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      if (!voidSuitsByPlayer[opponent].contains(suit)) continue;

      final int targetScore = players[opponent].score;
      final int knownPenalty = knownOpponentPenaltyInSuit(suit, opponent);

      // A void opponent can discard any card when this suit is led.
      // This is especially valuable when that opponent is already carrying
      // a dangerous score or is known to hold penalty cards.
      if (targetScore >= 94) {
        score += 55;
        score += knownPenalty * 14;
      } else if (targetScore >= 88) {
        score += 34;
        score += knownPenalty * 9;
      } else {
        score += 10;
        score += knownPenalty * 4;
      }

      // A void player becomes a stronger target in the closing Hands because
      // there are fewer opportunities left to transfer unwanted penalties.
      if (isLateRound()) {
        score += 12;
      }
    }

    return score;
  }

  // ==========================================================
  // BOT LOOKAHEAD — VALUE THE POSITION AFTER THIS CARD
  // ==========================================================

  double evaluatePostPlayPosition(
    int botIndex,
    CardModel card, {
    bool leading = false,
  }) {
    final Player bot = players[botIndex];
    final List<CardModel> remaining = bot.cards
        .where((c) => cardKey(c) != cardKey(card))
        .toList();

    if (remaining.isEmpty) return 0;

    double score = 0;

    // Preserve low exits and useful future voids.
    for (final String suit in const ['Hearts', 'Diamonds', 'Clubs', 'Spades']) {
      final List<CardModel> suitCards =
          remaining.where((c) => c.suit == suit).toList();
      final int low = suitCards.where((c) => c.value <= 7).length;

      if (suitCards.isEmpty) {
        score += 34;
      } else if (suitCards.length == 1) {
        score += 18;
      }

      score += low * 3.0;
    }

    // Do not leave a dangerous high card isolated unless doing so creates a
    // useful void.
    for (final CardModel remainingCard in remaining) {
      if (remainingCard.value >= 12 && remainingCard.penalty == 0) {
        final int count =
            remaining.where((c) => c.suit == remainingCard.suit).length;
        if (count == 1) score -= 16;
      }
    }

    // A lead should ideally leave the BOT with a safe low exit in another suit.
    if (leading && card.penalty == 0 && card.value <= 7) {
      score += 10;
    }

    // Unloading a penalty becomes increasingly valuable as the Round closes.
    if (isLateRound() && card.penalty > 0) {
      score += card.penalty * 8;
    }

    // If a dangerous opponent is near 100, preserving the ability to shed
    // another penalty on the next Hand is especially valuable.
    if (opponentNearElimination(botIndex)) {
      final bool stillHasPenalty = remaining.any((c) => c.penalty > 0);
      if (stillHasPenalty) score += 10;
    }

    return score;
  }

  // ==========================================================
  // BOT QUEEN RISK — PROTECT / RELEASE THE SPADES QUEEN INTELLIGENTLY
  // ==========================================================

  double evaluateQueenRisk(int playerIndex, CardModel card) {
    if (!card.isSpadeQueen) return 0;

    double score = 0;
    final int winner = determineCurrentWinner();
    final double handPenalty = currentHandPenaltyTotal();
    final int spadesRemaining = players[playerIndex]
        .cards
        .where((c) => c.suit == 'Spades' && c.value != 12)
        .length;

    // When the current winner is already highly scored, transferring the
    // Queen is much more valuable than merely avoiding it ourselves.
    if (winner >= 0 && winner != playerIndex) {
      final int targetScore = players[winner].score;
      if (targetScore >= 94) {
        score += 95;
      } else if (targetScore >= 88) {
        score += 60;
      } else {
        score += 18;
      }
    }

    // A loaded Hand makes the Queen more dangerous to take ourselves.
    if (handPenalty >= 8) {
      score -= 75;
    } else if (handPenalty >= 4) {
      score -= 35;
    }

    // If other spades remain, playing the Queen can create useful future
    // control; if it is the last spade, losing control is more significant.
    if (spadesRemaining >= 3) {
      score += 18;
    } else if (spadesRemaining == 0) {
      score -= 22;
    }

    // The Queen is more valuable as a transfer in the closing Hands.
    if (isLateRound()) {
      score += 24;
    }

    return score;
  }

  // ==========================================================
  // ADVANCED PENALTY TIMING — SHED NOW OR HOLD FOR A BETTER HAND
  // ==========================================================

  double scorePenaltyTiming(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    final Player bot = players[playerIndex];
    final double handPenalty = currentHandPenaltyTotal();
    final int currentWinner = determineCurrentWinner();
    final int handsRemaining = max(0, 13 - handNumber);

    if (candidate.penalty <= 0) {
      // Zero-point cards are normally better kept when they give control.
      // They should not be thrown away merely because they are small.
      score -= 3;
      if (!winning && isLateRound()) score -= 5;
      return score;
    }

    // A penalty is more valuable to shed when there are fewer Hands left.
    final double urgency = handsRemaining <= 2
        ? 42
        : handsRemaining <= 4
            ? 27
            : handsRemaining <= 7
                ? 15
                : 6;
    score += candidate.penalty * urgency;

    // A penalty card that is currently safe to lose is a strong candidate for
    // immediate disposal. Taking a loaded Hand with it is a different matter.
    if (!winning) {
      score += candidate.penalty * 22;
      if (handPenalty >= 6) score += candidate.penalty * 12;
      if (handPenalty <= 2) score += candidate.penalty * 5;
    } else {
      // If winning would make us collect the current Hand, the penalty is
      // costly unless there is a strong reason to take the Hand.
      score -= candidate.penalty * 18;
      if (handPenalty >= 6) score -= candidate.penalty * 20;
    }

    // A high-score opponent winning the current Hand is a special opportunity:
    // shedding our penalty into that Hand is much better than saving it.
    if (currentWinner >= 0 && currentWinner != playerIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94) {
        score += candidate.penalty * 36;
      } else if (targetScore >= 88) {
        score += candidate.penalty * 22;
      } else {
        score += candidate.penalty * 7;
      }
    }

    // If this is the last card of its suit, shedding a penalty can also create
    // a future void, which is often more valuable than the face value suggests.
    final int suitCount = bot.cards.where((c) => c.suit == candidate.suit).length;
    if (suitCount == 1) {
      score += 24;
    } else if (suitCount == 2) {
      score += 9;
    }

    // Preserve the useful low-card exit unless the card being shed is a major
    // penalty or the Round is nearly finished.
    if (candidate.value <= 7 && candidate.penalty < 4 && !isLateRound()) {
      score -= 16;
    }

    if (candidate.isSpadeQueen) {
      score += 45;
    } else if (candidate.suit == 'Clubs' && candidate.rank == 'K') {
      score += 28;
    } else if (candidate.suit == 'Diamonds' && candidate.rank == 'J') {
      score += 18;
    }

    return score;
  }

  // ==========================================================
  // TABLE POSITION & TURN-ORDER INTELLIGENCE
  // ==========================================================

  double scoreTablePosition(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    final int cardsPlayed = currentHand.length;
    final int position = cardsPlayed + 1;
    final int playersAfter = 4 - position;
    final int currentWinner = determineCurrentWinner();
    final double handPenalty = currentHandPenaltyTotal();

    // Later positions have more information.  In particular, the fourth
    // player can see the complete current Hand before deciding whether to win.
    if (position == 4) {
      score += 28;
      if (handPenalty <= 2) {
        score += winning ? 48 : -8;
      } else if (handPenalty >= 6) {
        score += winning ? -38 : 18;
      }
    } else if (position == 3) {
      score += 12;
    }

    // If we win, we become the next lead player.  That control is more useful
    // when we still have several suits/cards that can be led safely.
    if (winning) {
      final Player bot = players[playerIndex];
      final int distinctSuits = bot.cards.map((c) => c.suit).toSet().length;
      score += distinctSuits * 4.0;
      score += playersAfter * 5.0;

      if (candidate.penalty > 0) {
        score -= candidate.penalty * 9;
      }

      // Taking a small, safe Hand is more attractive when the current Hand is
      // light and we gain the lead afterward.
      if (handPenalty <= 2) score += 22;
      if (handPenalty >= 6) score -= 24;
    } else {
      // Losing preserves the current winner's lead. This can be useful when
      // that player is a dangerous high-score opponent who can be made to
      // absorb the current Hand.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += 24 + candidate.penalty * 7;
        } else if (targetScore >= 88) {
          score += 14 + candidate.penalty * 4;
        }
      }

      // Do not automatically lose when doing so leaves us with a very poor
      // future lead structure.
      final int sameSuitRemaining = players[playerIndex].cards
          .where((c) => c.suit == candidate.suit)
          .length - 1;
      if (sameSuitRemaining == 0) score += 10;
      if (sameSuitRemaining >= 4 && candidate.penalty == 0) score -= 6;
    }

    // The player immediately before us has already revealed information;
    // being last therefore deserves more weight than being early.
    if (position == 4 && currentWinner == playerIndex) {
      score += winning ? 18 : -18;
    }

    return score;
  }

  // ==========================================================
  // OPPONENT BEHAVIOR PREDICTION
  // ==========================================================

  double scorePredictedOpponentBehavior(
    int botIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    final int currentWinner = determineCurrentWinner();
    final int position = currentHand.length + 1;

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final bool opponentIsNext =
          ((botIndex + (position == 4 ? 1 : 1)) % 4) == opponent;
      final bool opponentIsLast = currentHand.length == 3 &&
          opponent == ((botIndex + 1) % 4);

      // A player who is void in the led suit is much more likely to dump a
      // penalty. This is public information learned from earlier Hands.
      final bool voidInCandidateSuit =
          voidSuitsByPlayer[opponent].contains(candidate.suit);
      if (voidInCandidateSuit) {
        final int knownPenalty =
            knownOpponentPenaltyInSuit(candidate.suit, opponent);
        if (players[opponent].score >= 94) {
          score += knownPenalty * 12;
          score += 8;
        } else if (players[opponent].score >= 88) {
          score += knownPenalty * 7;
          score += 5;
        }
      }

      // If we are about to leave an opponent in a position where they can
      // safely win the Hand, take that possibility into account. Do not assume
      // their hidden cards; only use known cards, voids and public position.
      final int knownSuitCards =
          countKnownCardsOfSuitForOpponent(opponent, candidate.suit);
      if (knownSuitCards > 0 && currentWinner >= 0 &&
          currentWinner != botIndex && !winning) {
        score += knownSuitCards *
            (players[opponent].score >= 88 ? 3.0 : 0.8);
      }

      // The next player has the strongest immediate influence on whether our
      // candidate will remain the winner. Earlier revealed cards matter more
      // when the next player is already close to the current winning value.
      if (opponentIsNext) {
        if (winning) {
          score -= knownSuitCards * 1.5;
          if (players[opponent].score >= 94) score += 8;
          else if (players[opponent].score >= 88) score += 4;
        } else if (currentWinner == opponent) {
          score += 10;
        }
      }

      // When the opponent will be last, they have maximum information and can
      // often decide whether to take or avoid the Hand. Reward choices that
      // make that decision predictable from public information.
      if (opponentIsLast) {
        if (voidInCandidateSuit && candidate.penalty > 0) {
          score += players[opponent].score >= 88 ? 14 : 4;
        }
        if (winning && players[opponent].score >= 94) {
          score += 7;
        }
      }

      // Known exchanged penalties are especially informative: a player who
      // received a penalty in this suit is a more likely target when that suit
      // becomes a discard outlet.
      if (knownDangerousCardWithOpponent(opponent, candidate.suit)) {
        score += penaltyPriority(candidate) *
            (players[opponent].score >= 94 ? 5.0 : 2.0);
      }
    }

    // Do not let prediction overwhelm actual Hand value. It is a tie-breaker
    // that helps the BOT choose between strategically similar cards.
    return score;
  }

  // ==========================================================
  // ADVANCED CARD COUNTING
  // ==========================================================

  double scoreAdvancedCardCounting(
    int playerIndex,
    CardModel candidate, {
    bool leading = false,
  }) {
    double score = 0;

    // Count only information that is publicly available to the BOT.
    final int playedInSuit = playedSuitCounts[candidate.suit] ?? 0;
    final int suitRemaining = 13 - playedInSuit;

    // A candidate becomes safer when the cards above it have already been
    // publicly played. This is especially important when deciding whether
    // to win a Hand with a medium/high card.
    int higherPlayed = 0;
    for (final card in playedCardsThisRound) {
      if (card.suit == candidate.suit && card.value > candidate.value) {
        higherPlayed++;
      }
    }

    score += higherPlayed * 9.0;

    // Count known cards held by other players. These are legitimate public
    // observations from exchange/previous play, never hidden-hand guesses.
    int higherKnownElsewhere = 0;
    for (final entry in knownCardOwner.entries) {
      if (entry.value == playerIndex) continue;
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      if (parts[0] != candidate.suit) continue;
      final int? knownValue = _rankValueForCounting(parts[1]);
      if (knownValue != null && knownValue > candidate.value) {
        higherKnownElsewhere++;
      }
    }

    // A known higher card is not an immediate threat to this candidate if
    // it is already accounted for as public information; keep a small
    // uncertainty cost because that player may still control the suit.
    score -= higherKnownElsewhere * 2.5;

    // If very few cards of the suit remain unseen, counting becomes much
    // more reliable and medium cards can safely become winning cards.
    if (suitRemaining <= 3) {
      score += 18;
      if (higherPlayed >= 2) score += 14;
    } else if (suitRemaining <= 5) {
      score += 8;
    }

    // A high card is much safer when almost all higher cards are already
    // visible. Conversely, an uncounted higher-card threat is dangerous.
    if (candidate.value >= 10) {
      if (higherPlayed >= 3) {
        score += 22;
      } else if (higherPlayed == 0) {
        score -= 18;
      }
    }

    // Low cards are useful exits. Do not automatically spend one simply
    // because it is low, particularly when counting says it is unusually
    // safe for a future Hand.
    if (candidate.value <= 7 && higherPlayed >= 3) {
      score += 10;
    }

    // When leading, suit exhaustion is strategically valuable because it can
    // help create a future void. When following, current winning safety is
    // more important than manufacturing a void immediately.
    if (leading) {
      if (suitRemaining <= 4) score += 12;
      if (candidate.value >= 11 && higherPlayed == 0) score -= 10;
    } else {
      if (candidate.value >= 11 && higherPlayed >= 2) score += 12;
    }

    return score;
  }

  int? _rankValueForCounting(String rank) {
    switch (rank) {
      case '2': return 2;
      case '3': return 3;
      case '4': return 4;
      case '5': return 5;
      case '6': return 6;
      case '7': return 7;
      case '8': return 8;
      case '9': return 9;
      case '10': return 10;
      case 'J': return 11;
      case 'Q': return 12;
      case 'K': return 13;
      case 'A': return 14;
      default: return null;
    }
  }

  // ==========================================================
  // MULTI-HAND PLANNING
  // ==========================================================

  double scoreMultiHandPlanning(
    int botIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    final Player bot = players[botIndex];
    final int remainingHands = max(0, 13 - handNumber);
    final int position = currentHand.length + 1;
    final double currentPenalty = currentHandPenaltyTotal();
    double score = 0;

    // A Round is a sequence of Hands.  Prefer moves that leave the BOT
    // with useful control for the Hands that are still to come.
    if (remainingHands <= 2) {
      score += candidate.penalty * 24;
      if (candidate.value >= 12 && candidate.penalty == 0) score -= 7;
      if (winning) score += 10;
    } else if (remainingHands <= 5) {
      score += candidate.penalty * 12;
    }

    // Winning gives the BOT the next lead.  That lead is particularly
    // valuable when the current Hand is clean or nearly clean.
    if (winning) {
      if (currentPenalty <= 2) score += 24;
      if (remainingHands >= 4) score += 10;
      if (position == 4) score += 18;
    } else {
      // Losing can be better when it preserves a strong future lead card.
      if (candidate.penalty == 0 && candidate.value <= 7) score += 8;
    }

    // Creating a short/void suit can give future Hands more control,
    // especially when the BOT still has several Hands to play.
    final int suitCount = bot.cards.where((c) => c.suit == candidate.suit).length;
    if (suitCount == 1) score += remainingHands >= 3 ? 18 : 8;
    if (suitCount == 2) score += remainingHands >= 5 ? 8 : 3;

    // Preserve low-card exits when there is time to use them later.
    if (remainingHands >= 4 && candidate.penalty == 0 && candidate.value <= 7) {
      score += 5;
    }

    // If an opponent is under pressure, denying them a loaded Hand becomes
    // more important than protecting a small amount of future convenience.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      if (players[opponent].score >= 94) {
        score += winning ? 16 : 4;
      } else if (players[opponent].score >= 88) {
        score += winning ? 9 : 2;
      }
    }

    return score;
  }

  // ==========================================================
  // OPPONENT MODEL SCORING
  // ==========================================================

  double scoreOpponentModel(
    int botIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    score += scoreMultiHandPlanning(
      botIndex,
      candidate,
      winning: winning,
    );
    final int position = currentHand.length + 1;
    final int currentWinner = determineCurrentWinner();

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int distance = (opponent - botIndex + 4) % 4;
      final bool isNext = distance == 1;
      final bool isPrevious = distance == 3;
      final bool isLast = position == 4 && isPrevious;
      final bool highPressure = players[opponent].score >= 94;
      final bool pressure = players[opponent].score >= 88;
      final bool voidInSuit =
          voidSuitsByPlayer[opponent].contains(candidate.suit);

      final int knownPenalty =
          knownOpponentPenaltyInSuit(candidate.suit, opponent);
      final int knownSuitCards =
          countKnownCardsOfSuitForOpponent(opponent, candidate.suit);

      // A void opponent is a potential penalty outlet. This becomes much more
      // valuable when that opponent is already close to elimination.
      if (voidInSuit) {
        if (highPressure) {
          score += candidate.penalty * 10;
          score += knownPenalty * 7;
        } else if (pressure) {
          score += candidate.penalty * 6;
          score += knownPenalty * 4;
        } else {
          score += candidate.penalty * 1.5;
        }
      }

      // If an opponent is known to hold cards in the led suit, they have a
      // greater chance of influencing the current winner. Use this only as a
      // probability adjustment; hidden cards are never assumed.
      if (knownSuitCards > 0) {
        final double factor = highPressure ? 2.2 : pressure ? 1.3 : 0.5;
        score += knownSuitCards * factor;
      }

      // The next player is the most immediate threat to a winning candidate.
      if (isNext) {
        if (winning) {
          score -= knownSuitCards * 3.0;
          if (highPressure) score += 5;
          else if (pressure) score += 2.5;
        } else if (currentWinner == opponent) {
          // Letting a dangerous opponent keep the current lead can be useful
          // when the Hand is carrying penalties they should receive.
          score += candidate.penalty * (highPressure ? 8 : pressure ? 4 : 1);
        }
      }

      // The last player has complete public information about the Hand and
      // therefore deserves special treatment in the BOT's prediction model.
      if (isLast) {
        if (winning && currentWinner == botIndex) {
          score += highPressure ? 8 : pressure ? 4 : 1;
        }
        if (!winning && voidInSuit && candidate.penalty > 0) {
          score += highPressure ? 12 : pressure ? 6 : 2;
        }
      }

      // A previous player who has already played cannot change their card, so
      // their revealed choice is useful information rather than an immediate
      // threat. Reward using that information without over-weighting it.
      if (isPrevious) {
        score += knownSuitCards * 0.8;
        if (voidInSuit) score += pressure ? 2.0 : 0.5;
      }

      // Known dangerous cards exchanged to this opponent are strong evidence
      // that the opponent can become a useful penalty target later.
      if (knownDangerousCardWithOpponent(opponent, candidate.suit)) {
        score += penaltyPriority(candidate) * (highPressure ? 4.0 : 1.5);
      }
    }

    // Keep this layer subordinate to the core card evaluation.
    return score;
  }

  // ==========================================================
  // V42.34 GRANDMASTER ARBITER
  // ==========================================================

  // This is the final decision layer for PLAYING a card. It does not replace
  // the specialised strategy engines above. Instead, it resolves conflicts
  // between them using the current Hand state, turn position, score pressure,
  // penalty load, and future-control priorities.
  double scoreGrandmasterDecision(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    double score = 0;
    final int cardsPlayed = currentHand.length;
    final int turnPosition = cardsPlayed + 1;
    final int currentWinner = determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();
    final bool lateHand = turnPosition >= 3;

    // Core principle: avoid collecting a loaded Hand unless doing so protects
    // us from a dangerous opponent or removes a major penalty from our hand.
    if (winning) {
      if (visiblePenalty >= 8) {
        score -= 65;
      } else if (visiblePenalty >= 4) {
        score -= 28;
      }

      if (candidate.penalty > 0 && isLateRound()) {
        score += candidate.penalty * 10;
      }

      // Taking the Hand becomes more attractive when the current winner is
      // already close to elimination.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += visiblePenalty * 12;
          score += 38;
        } else if (targetScore >= 88) {
          score += visiblePenalty * 6;
          score += 18;
        }
      }
    } else {
      // If we can lose, preserving the ability to lose is normally the first
      // priority, especially when the Hand already contains penalty.
      score += 24;
      if (visiblePenalty >= 6) {
        score += 24;
      } else if (visiblePenalty >= 3) {
        score += 10;
      }

      // A low, clean loser is valuable because it preserves control cards.
      if (candidate.penalty == 0 && candidate.value <= 7) {
        score += 22;
      }
    }

    // Turn-order arbitration: the final player has complete information about
    // the current Hand and can make the strongest penalty-routing decision.
    if (turnPosition == 4) {
      score += winning ? 4 : 14;
      if (!winning && candidate.penalty > 0 && currentWinner >= 0 &&
          currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        score += targetScore >= 94
            ? candidate.penalty * 20
            : targetScore >= 88
                ? candidate.penalty * 10
                : candidate.penalty * 3;
      }
    } else if (turnPosition == 3) {
      score += winning ? 2 : 7;
    }

    // Leading is a separate decision: reward leads that create future voids
    // only when the candidate itself is not an obviously dangerous control
    // card. This prevents the final arbiter from undoing specialised lead
    // planning.
    if (leading) {
      final int suitCount = players[playerIndex]
          .cards
          .where((c) => c.suit == candidate.suit)
          .length;
      if (suitCount == 1) {
        score += candidate.value <= 10 ? 14 : -10;
      }
      if (candidate.penalty == 0 && candidate.value <= 7) {
        score += 10;
      }
      if (candidate.value >= 12) {
        score -= 12;
      }
    }

    // Endgame arbitration: with fewer Hands left, immediate penalty handling
    // matters more than speculative long-term structure.
    if (isLateRound()) {
      score += candidate.penalty * (winning ? 8 : 15);
      if (candidate.penalty == 0 && candidate.value <= 7) {
        score += 6;
      }
    }

    // Protect against spending a useful high control card merely to improve a
    // single Hand when the current Hand is clean.
    if (visiblePenalty == 0 && candidate.penalty == 0 && candidate.value >= 12) {
      score -= 16;
    }

    // Small final tie-break based on how much of the current Hand is known.
    // This is intentionally modest so it cannot overpower the specialised
    // card-counting and opponent-model layers.
    if (lateHand) {
      score += winning ? -2 : 3;
    }

    return score;
  }

  // ==========================================================
  // V42.37 BOT BEHAVIORAL INTELLIGENCE
  // ==========================================================

  // Adds a small context-sensitive behavioral layer. It is deterministic,
  // not random: the existing strategy engines remain the primary decision
  // makers, while this layer helps avoid repeating the same legal pattern
  // when another option is strategically close.
  double scoreBehavioralIntelligence(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    double score = 0;
    final Player bot = players[playerIndex];
    final String? previousLead = lastLedSuitByPlayer[playerIndex];
    final int previousLeadCount =
        consecutiveLeadCountByPlayer[playerIndex];
    final int currentWinner = determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();

    if (leading && previousLead != null) {
      if (candidate.suit == previousLead) {
        score -= previousLeadCount >= 2 ? 16 : 7;
      } else {
        score += previousLeadCount >= 2 ? 12 : 5;
      }
    }

    if (!leading && visiblePenalty >= 6 && candidate.penalty == 0) {
      score += 8;
    }

    if (!leading && currentWinner >= 0 && currentWinner != playerIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94 && candidate.penalty > 0) {
        score += candidate.penalty * (winning ? 2 : 5);
      } else if (targetScore >= 88 && candidate.penalty > 0) {
        score += candidate.penalty * (winning ? 1 : 3);
      }
    }

    if (candidate.penalty == 0 && candidate.value <= 7) {
      final int suitCount =
          bot.cards.where((card) => card.suit == candidate.suit).length;
      if (suitCount == 1) {
        score -= 6;
      }
    }

    if (isLateRound() && candidate.penalty > 0) {
      score += candidate.penalty * 2;
    }

    return score;
  }

  // ==========================================================
  // V42.38 BOT INFORMATION-CONFIDENCE INTELLIGENCE
  // ==========================================================

  // Uses the amount of public information revealed in the current Hand to
  // keep early decisions conservative and allow stronger counting/model
  // signals later in the Hand. This is deliberately a small adjustment.
  double scoreInformationConfidence(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    final int visibleCards = playedCardsThisRound.length;
    final double confidence =
        (visibleCards / 18.0).clamp(0.0, 1.0).toDouble();

    if (confidence <= 0) return 0;

    double score = 0;
    final int currentWinner = determineCurrentWinner();

    if (currentWinner >= 0 && currentWinner != playerIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94) {
        score += candidate.penalty * confidence * (winning ? 1.5 : 3.0);
      } else if (targetScore >= 88) {
        score += candidate.penalty * confidence * (winning ? 0.75 : 1.8);
      }
    }

    if (leading && candidate.penalty == 0 && candidate.value <= 7) {
      score += confidence * 2.0;
    }

    return score;
  }

  // ==========================================================
  // V42.35 BOT BALANCING — KEEP THE FINAL ARBITER STABLE
  // ==========================================================

  double balanceGrandmasterScore(double score, CardModel candidate) {
    // Gently compress unusually large final scores so one strategic layer
    // cannot overpower all of the other decision systems.
    if (score > 220) {
      score = 220 + (score - 220) * 0.55;
    } else if (score < -220) {
      score = -220 + (score + 220) * 0.55;
    }

    // A deliberately tiny late-round preference for unloading penalty cards.
    // It is intentionally too small to overturn a meaningful strategic edge.
    if (isLateRound() && candidate.penalty > 0) {
      score += 0.25;
    }
    return score;
  }

  // ==========================================================
  // BOT DECISION STABILITY — DETERMINISTIC TIE BREAKING
  // ==========================================================

  bool isBetterBotTieBreak(CardModel candidate, CardModel currentBest) {
    if (candidate.penalty != currentBest.penalty) {
      if (isLateRound()) {
        return candidate.penalty > currentBest.penalty;
      }
      return candidate.penalty < currentBest.penalty;
    }

    if (candidate.value != currentBest.value) {
      return candidate.value < currentBest.value;
    }

    return cardKey(candidate).compareTo(cardKey(currentBest)) < 0;
  }

  // ==========================================================
  // V1.2 BOT STRATEGIC SITUATION ENGINE
  // ==========================================================
  // A compact final layer that makes the bots react to the actual state of
  // the Round: penalty concentration, 88-99 protection, suit exhaustion,
  // dangerous high cards and the current Hand winner.
  double scoreStrategicSituation(
    int playerIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    final Player bot = players[playerIndex];
    double score = 0;
    final int currentWinner = determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();

    // --------------------------------------------------------
    // 1. Protect players in the 88-99 window from ♠Q.
    // --------------------------------------------------------
    if (currentWinner >= 0 && currentWinner != playerIndex) {
      final int target = players[currentWinner].score;
      if (target >= 88 && target <= 99) {
        if (candidate.isSpadeQueen) {
          score += winning ? -180 : 150;
        }
        if (candidate.penalty > 0) {
          score += winning ? -candidate.penalty * 8 : candidate.penalty * 9;
        }
      }
    }

    // --------------------------------------------------------
    // 2. Break a developing 35-point shoot.
    // --------------------------------------------------------
    int largestRoundPenalty = 0;
    int largestCollector = -1;
    for (final MapEntry<int, int> entry in roundPenaltyByPlayer.entries) {
      if (entry.value > largestRoundPenalty) {
        largestRoundPenalty = entry.value;
        largestCollector = entry.key;
      }
    }

    if (largestCollector >= 0 && largestCollector != playerIndex) {
      final int remainingPenalty = max(0, 35 - largestRoundPenalty);
      final bool shootThreat = largestRoundPenalty >= 10 ||
          (largestRoundPenalty >= 7 && handNumber >= 7);

      if (shootThreat) {
        // Do not voluntarily feed the suspected collector a penalty.
        if (candidate.penalty > 0) {
          score -= candidate.penalty * 18;
        }

        // Prefer a move that makes another player capable of winning the
        // current loaded Hand instead of extending the collector's run.
        if (currentWinner == largestCollector && visiblePenalty >= 3) {
          score += winning ? 42 : -18;
        }

        // As the shoot gets closer, protecting the remaining penalty pool
        // becomes more important.
        if (remainingPenalty <= 12 && candidate.penalty > 0) {
          score -= candidate.penalty * 12;
        }
      }
    }

    // --------------------------------------------------------
    // 3. Create and exploit voids.
    // --------------------------------------------------------
    if (leading) {
      final List<CardModel> suitCards = bot.cards
          .where((c) => c.suit == candidate.suit)
          .toList();
      if (suitCards.length == 1) score += 26;
      if (suitCards.length == 2) score += 10;

      // A suit with many already-played cards is close to exhaustion.
      final int playedOfSuit = playedCardsThisRound
          .where((c) => c.suit == candidate.suit)
          .length;
      if (playedOfSuit >= 7) score += 12;
    }

    // --------------------------------------------------------
    // 4. Preserve low exits, but not when a dangerous penalty can be shed.
    // --------------------------------------------------------
    final int suitCount = bot.cards
        .where((c) => c.suit == candidate.suit)
        .length;
    if (!leading && candidate.penalty == 0 && candidate.value <= 7 &&
        suitCount >= 3) {
      score -= 14;
    }
    if (candidate.penalty > 0 && suitCount <= 2) {
      score += candidate.penalty * 7;
    }

    // --------------------------------------------------------
    // 5. Endgame: unload dangerous cards and avoid unnecessary control.
    // --------------------------------------------------------
    if (isLateRound()) {
      if (!winning && candidate.penalty > 0) {
        score += candidate.penalty * 16;
      }
      if (winning && visiblePenalty >= 3) {
        score -= visiblePenalty * 5;
      }
      if (candidate.value >= 12 && candidate.penalty == 0) {
        score -= 8;
      }
    }

    // --------------------------------------------------------
    // 6. High-card danger based on cards already played.
    // --------------------------------------------------------
    final int higherPlayed = playedCardsThisRound.where((c) =>
        c.suit == candidate.suit && c.value > candidate.value).length;
    if (candidate.value >= 11 && higherPlayed >= 2) {
      score += 8;
    } else if (candidate.value >= 11 && higherPlayed == 0) {
      score -= 8;
    }

    // Never allow this small layer to overpower the specialised engines.
    return score.clamp(-90.0, 90.0).toDouble();
  }

  // ==========================================================
  // V1.2.2 PROBABILITY-BASED OPPONENT CARD PREDICTION
  // ==========================================================
  // Uses public card memory to estimate hidden-card risk. Unknown cards
  // remain probabilistic; no hidden hand is treated as certain.

  List<CardModel> _unknownCardsForProbability(int botIndex) {
    final Set<String> excluded = <String>{
      ...playedCardsThisRound.map(cardKey),
      ...players[botIndex].cards.map(cardKey),
    };
    return createDeck()
        .where((card) => !excluded.contains(cardKey(card)))
        .toList();
  }

  double probabilityOpponentHasSuit(
    int botIndex,
    int opponentIndex,
    String suit,
  ) {
    final List<CardModel> unknown = _unknownCardsForProbability(botIndex);
    final int suitCount = unknown.where((c) => c.suit == suit).length;
    final int handSize = players[opponentIndex].cards.length;
    if (unknown.isEmpty || suitCount <= 0 || handSize <= 0) return 0.0;

    double noSuit = 1.0;
    final int draws = min(handSize, unknown.length);
    for (int i = 0; i < draws; i++) {
      final int denominator = unknown.length - i;
      final int nonSuit = max(0, unknown.length - suitCount - i);
      if (denominator <= 0) break;
      noSuit *= nonSuit / denominator;
    }
    return (1.0 - noSuit).clamp(0.0, 1.0).toDouble();
  }

  double probabilityOpponentHasCard(
    int botIndex,
    int opponentIndex,
    CardModel target,
  ) {
    if (playedCardsThisRound.any((c) => cardKey(c) == cardKey(target))) {
      return 0.0;
    }
    if (players[botIndex].cards.any((c) => cardKey(c) == cardKey(target))) {
      return 0.0;
    }
    final List<CardModel> unknown = _unknownCardsForProbability(botIndex);
    if (!unknown.any((c) => cardKey(c) == cardKey(target))) return 0.0;
    final int handSize = players[opponentIndex].cards.length;
    if (unknown.isEmpty || handSize <= 0) return 0.0;
    return (handSize / unknown.length).clamp(0.0, 1.0).toDouble();
  }

  double probabilityOpponentHasHigher(
    int botIndex,
    int opponentIndex,
    String suit,
    int value,
  ) {
    final List<CardModel> unknown = _unknownCardsForProbability(botIndex);
    final List<CardModel> higher = unknown
        .where((c) => c.suit == suit && c.value > value)
        .toList();
    if (higher.isEmpty) return 0.0;

    final int handSize = players[opponentIndex].cards.length;
    double noHigher = 1.0;
    for (int i = 0; i < min(handSize, unknown.length); i++) {
      final int denominator = unknown.length - i;
      final int nonHigher = max(0, unknown.length - higher.length - i);
      if (denominator <= 0) break;
      noHigher *= nonHigher / denominator;
    }
    return (1.0 - noHigher).clamp(0.0, 1.0).toDouble();
  }

  double probabilityAnyOpponentHasHigher(
    int botIndex,
    String suit,
    int value,
  ) {
    double none = 1.0;
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      final double p = probabilityOpponentHasHigher(
        botIndex, opponent, suit, value,
      );
      none *= (1.0 - p).clamp(0.0, 1.0);
    }
    return (1.0 - none).clamp(0.0, 1.0).toDouble();
  }

  double scoreOpponentProbability(
    int botIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    double score = 0.0;
    final double higherThreat = probabilityAnyOpponentHasHigher(
      botIndex, candidate.suit, candidate.value,
    );

    if (winning) {
      // Do not waste a control card when an unseen higher card is still likely.
      score -= higherThreat * 34.0;
    } else if (leading && candidate.value <= 8) {
      // A low lead becomes more attractive when it is unlikely to be covered.
      score += (1.0 - higherThreat) * 14.0;
    }

    // Estimate whether a dangerous opponent can follow this suit.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      final double pSuit = probabilityOpponentHasSuit(
        botIndex, opponent, candidate.suit,
      );
      if (players[opponent].score >= 94) {
        score += pSuit * (candidate.penalty + currentHandPenaltyTotal()) * 3.0;
      } else if (players[opponent].score >= 88) {
        score += pSuit * (candidate.penalty + currentHandPenaltyTotal()) * 1.5;
      }
    }

    // Remaining dangerous cards make the bot more cautious about consuming
    // high cards early in the Round.
    final int remainingHigher = remainingCardsOfSuitAbove(
      candidate.suit, candidate.value,
    );
    if (remainingHigher == 0) score += winning ? 18.0 : 5.0;

    return score;
  }

  // ==========================================================
  // V1.2.3 EXACT CARD-COUNTING / OWNER-CONSTRAINT ENGINE
  // ==========================================================
  // This layer converts the memory gathered so far into hard constraints.
  // A card is either publicly gone, in the BOT's own hand, known to an
  // exchanged owner, or still genuinely uncertain. Void suits further reduce
  // the possible owners of every unseen card in that suit.

  List<int> possibleOwnersForCard(int botIndex, CardModel card) {
    final List<int> owners = <int>[];
    if (playedCardsThisRound.any((c) => cardKey(c) == cardKey(card))) {
      return owners;
    }
    for (int player = 0; player < 4; player++) {
      if (player == botIndex) {
        if (players[player].cards.any((c) => cardKey(c) == cardKey(card))) {
          owners.add(player);
        }
        continue;
      }
      final int? knownOwner = knownCardOwner[cardKey(card)];
      if (knownOwner != null && knownOwner != player) continue;
      if (voidSuitsByPlayer[player].contains(card.suit)) continue;
      owners.add(player);
    }
    return owners;
  }

  double cardOwnershipConfidence(
    int botIndex,
    CardModel card,
    int targetPlayer,
  ) {
    final List<int> owners = possibleOwnersForCard(botIndex, card);
    if (owners.isEmpty || !owners.contains(targetPlayer)) return 0.0;

    final int? knownOwner = knownCardOwner[cardKey(card)];
    if (knownOwner == targetPlayer) return 1.0;

    // If only one legal owner remains, the card is effectively counted.
    if (owners.length == 1) return 1.0;
    return 1.0 / owners.length;
  }

  double scoreExactCardCounting(
    int botIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    double score = 0.0;

    final List<CardModel> higher = remainingUnseenSuitCards(candidate.suit)
        .where((c) => c.value > candidate.value)
        .toList();

    int forcedHigherOwners = 0;
    for (final CardModel card in higher) {
      final List<int> owners = possibleOwnersForCard(botIndex, card);
      if (owners.length == 1 && owners.first != botIndex) {
        forcedHigherOwners++;
      }
      if (owners.contains(botIndex)) {
        continue;
      }
    }

    if (winning) {
      // A candidate is less attractive as a winner when a higher card has a
      // uniquely determined opponent owner.
      score -= forcedHigherOwners * 12.0;
      if (higher.isEmpty) score += 24.0;
    } else {
      // If all remaining higher cards are already accounted for, the BOT can
      // confidently judge whether its card will lose or win.
      if (higher.isEmpty) score -= 18.0;
      if (forcedHigherOwners == higher.length && higher.isNotEmpty) {
        score += leading ? 10.0 : 22.0;
      }
    }

    // Penalty-card ownership is especially valuable information. If a known
    // high-score opponent owns a remaining penalty card in this suit, leading
    // that suit can create a deliberate transfer opportunity.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      final int targetScore = players[opponent].score;
      if (targetScore < 88) continue;

      for (final CardModel card in remainingUnseenSuitCards(candidate.suit)) {
        if (card.penalty <= 0) continue;
        final double confidence = cardOwnershipConfidence(
          botIndex, card, opponent,
        );
        score += confidence * card.penalty * (targetScore >= 94 ? 10.0 : 5.0);
      }
    }

    // A void is stronger than a probability estimate: that player cannot
    // follow this suit. This makes suit leads more purposeful.
    if (leading) {
      int knownVoids = 0;
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent != botIndex &&
            voidSuitsByPlayer[opponent].contains(candidate.suit)) {
          knownVoids++;
        }
      }
      score += knownVoids * 9.0;
    }

    return score.clamp(-100.0, 100.0).toDouble();
  }

  // ==========================================================
  // BOT LEAD — PLAN AHEAD, NOT JUST LOWEST CARD
  // ==========================================================

  CardModel chooseBotLeadCard(
    int playerIndex,
    Player bot,
  ) {
    final List<CardModel> legalCards = bot.cards
        .where((card) => isLegalCard(playerIndex, card))
        .toList();

    if (legalCards.isEmpty) return bot.cards.first;

    // Hand 1 has a special opening rule. Among legal cards, choose the safest
    // opening while preserving the strongest future structure.
    if (handNumber == 1) {
      legalCards.sort((a, b) {
        final int penaltyCompare = a.penalty.compareTo(b.penalty);
        if (penaltyCompare != 0) return penaltyCompare;
        final double sa = strategicCardValue(playerIndex, a, leading: true);
        final double sb = strategicCardValue(playerIndex, b, leading: true);
        return sb.compareTo(sa);
      });
      return maybeUseDifficultyCard(legalCards.first, legalCards);
    }

    CardModel best = legalCards.first;
    double bestScore = -double.infinity;

    for (final CardModel candidate in legalCards) {
      double score = strategicCardValue(
        playerIndex,
        candidate,
        leading: true,
      );
      score += scoreTablePosition(playerIndex, candidate, winning: false);
      score += scoreAdvancedCardCounting(playerIndex, candidate, leading: true);
      score += scoreStrategicSituation(
        playerIndex,
        candidate,
        leading: true,
        winning: false,
      );

      final List<CardModel> ownSuit = bot.cards
          .where((c) => c.suit == candidate.suit)
          .toList();

      // Leading from a short suit can manufacture a future void, but avoid
      // doing it when the suit contains dangerous high cards that we still
      // need to shed safely.
      if (ownSuit.length == 1) {
        score += 38;
        if (candidate.value >= 11) score -= 25;
      }

      // A lead that is likely to be won by an opponent with a high score can
      // deliberately move penalty risk away from the BOT.
      score += estimateLeadTargetValue(playerIndex, candidate.suit) * 1.8;
      score += scoreTargetingOpponent(playerIndex, candidate.suit) * 6;
      score += scorePredictedOpponentBehavior(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreOpponentModel(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreVoidTargetingLead(playerIndex, candidate.suit);
      score += scoreAdaptiveLead(playerIndex, candidate);
      score += evaluateHandOutcomeChoice(
        playerIndex,
        candidate,
        leading: true,
      );
      score += evaluatePostPlayPosition(
        playerIndex,
        candidate,
        leading: true,
      ) * 1.15;
      score += scoreGrandmasterDecision(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score += evaluateQueenRisk(playerIndex, candidate);

      if (isLateRound()) {
        // In the endgame, lead low safe cards when possible, but use a
        // penalty lead when it gives a high-score opponent a likely outlet.
        if (candidate.penalty == 0 && candidate.value <= 7) {
          score += 24;
        }
        if (candidate.penalty > 0 && opponentNearElimination(playerIndex)) {
          score += candidate.penalty * 16;
        }
      }

      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == playerIndex) continue;
        final int targetScore = players[opponent].score;
        if (targetScore >= 94) {
          score += knownOpponentPenaltyInSuit(candidate.suit, opponent) * 9;
        } else if (targetScore >= 88) {
          score += knownOpponentPenaltyInSuit(candidate.suit, opponent) * 5;
        }
      }

      // Preserve a safe suit with several low followers.
      if (ownSuit.length >= 4 && ownSuit.where((c) => c.value <= 7).length >= 3) {
        score -= 35;
      }

      score += scoreBehavioralIntelligence(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score += scoreInformationConfidence(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score += scoreRemainingCardMemory(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreOpponentProbability(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreExactCardCounting(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score = balanceGrandmasterScore(score, candidate);


      if (score > bestScore ||



          (score == bestScore && isBetterBotTieBreak(candidate, best))) {



        bestScore = score;



        best = candidate;



      }
    }

    final CardModel chosen = maybeUseDifficultyCard(best, legalCards);
    return chosen;
  }

  // ==========================================================
  // ADAPTIVE LEAD — CHOOSE THE SUIT, NOT JUST THE CARD
  // ==========================================================

  double scoreAdaptiveLead(
    int playerIndex,
    CardModel candidate,
  ) {
    final Player bot = players[playerIndex];
    final List<CardModel> suitCards = bot.cards
        .where((card) => card.suit == candidate.suit)
        .toList();

    double score = 0;

    if (suitCards.length == 1) {
      score += 34;
    } else if (suitCards.length == 2) {
      score += 16;
    } else if (suitCards.length >= 5) {
      score -= 10;
    }

    if (candidate.value <= 5 && candidate.penalty == 0) {
      score += 22;
    }
    if (candidate.value >= 12) {
      score -= 24;
    }

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == playerIndex) continue;

      final List<CardModel> opponentSuit = players[opponent].cards
          .where((card) => card.suit == candidate.suit)
          .toList();

      if (opponentSuit.isEmpty) {
        if (players[opponent].score >= 94) {
          score += 32;
        } else if (players[opponent].score >= 88) {
          score += 20;
        } else {
          score += 8;
        }
      } else if (opponentSuit.length == 1 && players[opponent].score >= 88) {
        score += 9;
      }
    }

    final int dangerousHigh = suitCards
        .where((card) => card.value >= 11 && card.penalty > 0)
        .length;
    score -= dangerousHigh * 14;

    final int lowFollowers = suitCards
        .where((card) => card.value <= 7 && card.penalty == 0)
        .length;
    if (lowFollowers >= 3) {
      score -= 12;
    }

    if (isLateRound() && candidate.penalty > 0) {
      score += candidate.penalty * 10;
    }

    return score;
  }

  // ==========================================================
  // BOT FOLLOWING — WIN ONLY WHEN IT MAKES SENSE
  // ==========================================================

  CardModel chooseSmartFollowingCard(
    int playerIndex,
    Player bot,
    List<CardModel> sameSuit,
  ) {
    final int currentWinningValue = currentHand.fold<int>(
      -1,
      (highest, played) =>
          played.card.suit == ledSuit && played.card.value > highest
              ? played.card.value
              : highest,
    );

    final int currentWinner = determineCurrentWinner();

    // ♠Q SAFE PENALTY TRANSFER:
    // If K♠ or A♠ is already on the table and this bot holds ♠Q,
    // ♠Q cannot win. Play it now so the Hand winner receives 12 points.
    if (ledSuit == 'Spades' && currentWinningValue >= 13) {
      final CardModel queen = sameSuit.firstWhere(
        (card) => card.isSpadeQueen,
        orElse: () => sameSuit.first,
      );
      if (queen.isSpadeQueen && queen.value < currentWinningValue) {
        return queen;
      }
    }

    final List<CardModel> losing = sameSuit
        .where((c) => c.value < currentWinningValue)
        .toList();

    // If we can safely lose the Hand, choose the card that gives us the best
    // future position rather than simply throwing the lowest card.
    if (losing.isNotEmpty) {
      CardModel best = losing.first;
      double bestScore = -double.infinity;

      for (final CardModel candidate in losing) {
        double score = strategicCardValue(playerIndex, candidate);
        score += scoreDynamicRiskReward(
          playerIndex,
          candidate,
          winning: false,
        );
        score += scoreStrategicSituation(
          playerIndex,
          candidate,
          leading: false,
          winning: false,
        );
        score += scorePenaltyTiming(
          playerIndex,
          candidate,
          winning: false,
        );
        score += scoreTablePosition(playerIndex, candidate, winning: false);
      score += scoreAdvancedCardCounting(playerIndex, candidate, leading: false);
        score += evaluateHandOutcomeChoice(playerIndex, candidate);
        score += evaluatePostPlayPosition(playerIndex, candidate) * 1.25;
        score += scoreGrandmasterDecision(
          playerIndex,
          candidate,
          winning: false,
        );
        score += scoreFullHandSimulation(playerIndex, candidate, winning: false);
        score += scoreRemainingCardMemory(
          playerIndex,
          candidate,
          winning: false,
        );
        score += evaluateQueenRisk(playerIndex, candidate);
        score += scorePredictedOpponentBehavior(
          playerIndex,
          candidate,
          winning: false,
        );
        score += scorePenaltyTransferTarget(playerIndex, candidate);

        // Losing is normally preferable when it avoids taking the Hand.
        score += 42;

        // Prefer the smallest losing card, but not at the expense of a useful
        // penalty transfer or a much better future hand structure.
        score += (15 - candidate.value) * 7;

        if (candidate.penalty == 0) {
          score += 58;
        } else if (isLateRound()) {
          score += candidate.penalty * 24;
        }

        if (currentWinner >= 0 && currentWinner != playerIndex) {
          final int targetScore = players[currentWinner].score;
          if (targetScore >= 94) {
            score += candidate.penalty * 105;
          } else if (targetScore >= 88) {
            score += candidate.penalty * 60;
          } else {
            score += candidate.penalty * 18;
          }

          // If the current winner is already dangerous, preserving our own
          // higher cards while allowing that player to keep the Hand is often
          // strategically better.
          if (candidate.penalty == 0) score += 12;
        }

        // Do not spend a useful control card just to lose a single Hand when
        // the remaining hand would become structurally dangerous.
        final List<CardModel> remaining = bot.cards
            .where((c) => cardKey(c) != cardKey(candidate))
            .toList();
        final int remainingDanger = remaining
            .where((c) => c.penalty > 0 || c.value >= 12)
            .length;
        if (remainingDanger >= 5 && candidate.penalty == 0) {
          score -= 12;
        }

        score += scoreBehavioralIntelligence(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreInformationConfidence(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreRemainingCardMemory(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreOpponentProbability(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreExactCardCounting(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score = balanceGrandmasterScore(score, candidate);


        if (score > bestScore ||



            (score == bestScore && isBetterBotTieBreak(candidate, best))) {



          bestScore = score;



          best = candidate;



        }
      }

      final CardModel chosen = maybeUseDifficultyCard(best, losing);
      return chosen;
    }

    // Every card wins. Choose the smallest winning card unless taking the
    // Hand has a strategic benefit (for example, protecting against a
    // high-score opponent or shedding a dangerous card).
    CardModel best = sameSuit.first;
    double bestScore = -double.infinity;

    final double visiblePenalty = currentHandPenaltyTotal();

    for (final CardModel candidate in sameSuit) {
      if (candidate.value < currentWinningValue) continue;

      double score = strategicCardValue(
        playerIndex,
        candidate,
        forcedWinner: true,
      );
      score += scoreDynamicRiskReward(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scorePenaltyTiming(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreTablePosition(playerIndex, candidate, winning: true);
      score += evaluateHandOutcomeChoice(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreForWinningCurrentHand(playerIndex, candidate);
      score += evaluatePostPlayPosition(playerIndex, candidate) * 0.85;
      score += scoreGrandmasterDecision(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreFullHandSimulation(playerIndex, candidate, winning: true);
      score += scoreRemainingCardMemory(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreOpponentProbability(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreExactCardCounting(
        playerIndex,
        candidate,
        winning: true,
      );
      if (shouldLetCurrentWinnerKeepHand(playerIndex)) {
        score -= 55;
      }
      score += scorePredictedOpponentBehavior(
        playerIndex,
        candidate,
        winning: true,
      );
      score += evaluateQueenRisk(playerIndex, candidate);

      // When the Hand is loaded, winning it is usually undesirable.
      // Prefer the smallest winning card so that the BOT minimizes its
      // control cost and preserves larger cards for later Hands.
      score -= candidate.value * 5;
      if (visiblePenalty >= 6) {
        score -= 45;
      } else if (visiblePenalty >= 3) {
        score -= 18;
      }

      // Taking a loaded Hand can still be correct when it prevents a very
      // high-score opponent from collecting the penalty.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        if (targetScore >= 94) {
          score += visiblePenalty * 11;
          score += 40;
        } else if (targetScore >= 88) {
          score += visiblePenalty * 6;
          score += 20;
        }
      }

      // A penalty card can be worth taking if it removes a dangerous card
      // from our hand in the late game.
      if (isLateRound() && candidate.penalty > 0) {
        score += candidate.penalty * 14;
      }

      score += scoreStrategicSituation(
        playerIndex,
        candidate,
        leading: false,
        winning: true,
      );
      score += scoreBehavioralIntelligence(
        playerIndex,
        candidate,
        winning: true,
      );
      score += scoreInformationConfidence(
        playerIndex,
        candidate,
        winning: true,
      );
      score = balanceGrandmasterScore(score, candidate);


      if (score > bestScore ||



          (score == bestScore && isBetterBotTieBreak(candidate, best))) {



        bestScore = score;



        best = candidate;



      }
    }

    final CardModel chosen = maybeUseDifficultyCard(best, sameSuit);
    return chosen;
  }

  // ==========================================================
  // BOT DISCARD / BREY TRANSFER — USE THE BEST TARGET
  // ==========================================================

  CardModel chooseSmartDiscardCard(
    int playerIndex,
    Player bot,
  ) {
    final List<CardModel> legalCards = bot.cards
        .where((card) => isLegalCard(playerIndex, card))
        .toList();

    if (legalCards.isEmpty) return bot.cards.first;

    // This is mandatory under the BREY rule whenever ♠Q is legal.
    final List<CardModel> legalQueen = legalCards
        .where((c) => c.isSpadeQueen)
        .toList();
    if (legalQueen.isNotEmpty) return legalQueen.first;

    CardModel best = legalCards.first;
    double bestScore = -double.infinity;

    for (final CardModel candidate in legalCards) {
      double score = 0;
      final int currentWinner = determineCurrentWinner();
      score += scoreDynamicRiskReward(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scorePenaltyTiming(
        playerIndex,
        candidate,
        winning: false,
      );

      // If an opponent currently wins, maximize the value transferred to that
      // opponent, especially when they are close to 100.
      if (currentWinner >= 0 && currentWinner != playerIndex) {
        final int targetScore = players[currentWinner].score;
        final double multiplier = targetScore >= 94
            ? 95
            : targetScore >= 88
                ? 58
                : 22;
        score += candidate.penalty * multiplier;
      }

      // Prefer dangerous cards that are safe to unload now.
      score += penaltyPriority(candidate) * 42;
      score += candidate.penalty * 28;

      // High zero-point cards are useful to shed when void, but don't destroy
      // a low-card suit structure without a reason.
      if (candidate.penalty == 0) {
        score += candidate.value * 5;
      }

      score += strategicCardValue(playerIndex, candidate);
      score += evaluateHandOutcomeChoice(playerIndex, candidate);
      score += evaluatePostPlayPosition(playerIndex, candidate) * 1.05;
      score += scoreGrandmasterDecision(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreFullHandSimulation(playerIndex, candidate, winning: false);
      score += scorePenaltyTransferTarget(playerIndex, candidate);

      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == playerIndex) continue;
        final int targetScore = players[opponent].score;
        if (targetScore >= 94) {
          score += knownOpponentPenaltyInSuit(candidate.suit, opponent) * 10;
        } else if (targetScore >= 88) {
          score += knownOpponentPenaltyInSuit(candidate.suit, opponent) * 6;
        }
      }

      // Preserve the last small card of a suit when it is strategically useful
      // for future control, unless the candidate is a major penalty.
      final int suitCount = bot.cards.where((c) => c.suit == candidate.suit).length;
      if (suitCount >= 3 && candidate.value <= 7 && candidate.penalty == 0) {
        score -= 80;
      }

      if (candidate.isSpadeQueen) score -= 1000;

      score += scoreStrategicSituation(
        playerIndex,
        candidate,
        leading: false,
        winning: false,
      );
      score += scoreBehavioralIntelligence(
        playerIndex,
        candidate,
        winning: false,
      );
      score += scoreInformationConfidence(
        playerIndex,
        candidate,
        winning: false,
      );
      score = balanceGrandmasterScore(score, candidate);


      if (score > bestScore ||



          (score == bestScore && isBetterBotTieBreak(candidate, best))) {



        bestScore = score;



        best = candidate;



      }
    }

    final CardModel chosen = maybeUseDifficultyCard(best, legalCards);
    return chosen;
  }

  int penaltyPriority(CardModel card) {
    if (card.isSpadeQueen) {
      return 4;
    }
    if (card.suit == 'Clubs' && card.rank == 'K') {
      return 3;
    }
    if (card.suit == 'Diamonds' && card.rank == 'J') {
      return 2;
    }
    if (card.suit == 'Hearts') {
      return 1;
    }
    return 0;
  }

  // Gives a small strategic bonus to leads that make an opponent near 100
  // more likely to be the future Hand winner/penalty collector.
  double scoreTargetingOpponent(int botIndex, String suit) {
    double score = 0;
    for (int i = 0; i < 4; i++) {
      if (i == botIndex) {
        continue;
      }
      if (players[i].score >= 88) {
        score += 1.0;
        if (voidSuitsByPlayer[i].contains(suit)) {
          score += 1.5;
        }
      }

      final List<CardModel> known = receivedCardsByPlayer[i] ??
          const <CardModel>[];
      for (final CardModel card in known) {
        if (card.suit == suit && card.penalty > 0) {
          score += penaltyPriority(card) * 0.35;
        }
      }
    }
    return score;
  }

  // ==========================================================
  // DEEP HAND OUTCOME PREDICTION
  // ==========================================================

  double currentHandPenaltyTotal() {
    int total = 0;
    for (final PlayedCard played in currentHand) {
      total += played.card.penalty;
    }
    return total.toDouble();
  }

  double scoreForWinningCurrentHand(
    int botIndex,
    CardModel candidate,
  ) {
    double score = 0;
    final double visiblePenalty = currentHandPenaltyTotal();

    // Winning an already penalty-heavy Hand is normally undesirable.
    score -= visiblePenalty * 34;

    // If the candidate itself carries penalty, add its likely cost. The
    // actual ♠Q protection is handled later by calculateHandPenalty(), but
    // the BOT should still treat ♠Q as a serious strategic threat before it
    // knows whether the eventual winner is protected by the 88-point rule.
    score -= candidate.penalty * 42;
    if (candidate.isSpadeQueen) {
      score -= 260;
    }
    if (candidate.suit == 'Clubs' && candidate.rank == 'K') {
      score -= 130;
    }
    if (candidate.suit == 'Diamonds' && candidate.rank == 'J') {
      score -= 80;
    }

    // However, denying a large penalty Hand to an opponent near 100 can be
    // worth taking a small amount ourselves.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) {
        continue;
      }
      final int opponentScore = players[opponent].score;
      if (opponentScore >= 94) {
        score += visiblePenalty * 13;
        if (visiblePenalty >= 4) {
          score += 24;
        }
      } else if (opponentScore >= 88) {
        score += visiblePenalty * 7;
      }
    }

    // Strongly reward winning only when it prevents a known dangerous card
    // from reaching a player who is close to elimination.
    final int currentWinner = determineCurrentWinner();
    if (currentWinner >= 0 && currentWinner != botIndex) {
      if (players[currentWinner].score >= 94) {
        score += visiblePenalty * 12;
      } else if (players[currentWinner].score >= 88) {
        score += visiblePenalty * 6;
      }
    }

    // A forced win with a high card should also be evaluated against the
    // BOT's remaining suit structure. Preserving low followers is useful.
    score += evaluateFutureSuitControl(botIndex, candidate) * 0.5;

    // In the late game, certainty is more valuable. If only a few cards of
    // the led suit remain unplayed, avoid a risky high winner unless the Hand
    // is strategically worth taking.
    final int unseen = unseenCardsOfSuit(candidate.suit);
    if (unseen <= 4 && visiblePenalty <= 2) {
      score -= candidate.value * 2.2;
    }

    return score;
  }

  double scorePenaltyTransferTarget(
    int botIndex,
    CardModel candidate,
  ) {
    double score = 0;
    final int currentWinner = determineCurrentWinner();

    // If the current winner is an opponent, throwing a penalty that loses to
    // that card is often exactly what the BOT wants.
    if (currentWinner >= 0 && currentWinner != botIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94) {
        score += candidate.penalty * 30;
      } else if (targetScore >= 88) {
        score += candidate.penalty * 18;
      } else {
        score += candidate.penalty * 5;
      }
    }

    // Known exchange memory makes a transfer even more valuable: if the
    // current winner is known to have received a dangerous card from the BOT,
    // preserve other safe cards and exploit that information when legal.
    if (currentWinner >= 0 && currentWinner != botIndex) {
      final List<CardModel> known =
          receivedCardsByPlayer[currentWinner] ?? const <CardModel>[];
      if (known.any((c) => c.penalty > 0 &&
          !playedCardsThisRound.any((p) => cardKey(p) == cardKey(c)))) {
        score += 14;
      }
    }

    return score;
  }

  CardModel maybeUseDifficultyCard(
    CardModel best,
    List<CardModel> candidates,
  ) {
    if (botDifficulty == BotDifficulty.hard || candidates.length <= 1) {
      return best;
    }

    final double chance =
        botDifficulty == BotDifficulty.easy ? 0.50 : 0.25;
    if (random.nextDouble() >= chance) {
      return best;
    }

    final List<CardModel> alternatives = candidates
        .where((card) => card != best)
        .toList();
    if (alternatives.isEmpty) {
      return best;
    }

    alternatives.shuffle(random);
    return alternatives.first;
  }

  // ==========================================================
  // STRATEGIC CARD OWNERSHIP ESTIMATE
  // ==========================================================

  bool botLikelyHasCard(int playerIndex, CardModel target) {
    if (players[playerIndex].cards.contains(target)) {
      return true;
    }

    final List<CardModel> received = receivedCardsByPlayer[playerIndex] ??
        const <CardModel>[];
    if (received.contains(target) && !playedCardsThisRound.contains(target)) {
      return true;
    }
    return false;
  }

  // ==========================================================
  // DETERMINE CURRENT WINNER
  // ==========================================================

  int determineCurrentWinner() {
    if (currentHand.isEmpty) {
      return -1;
    }

    String suit = currentHand.first.card.suit;

    PlayedCard winner = currentHand.first;

    for (PlayedCard played in currentHand) {
      if (
        played.card.suit == suit &&
        played.card.value > winner.card.value
      ) {
        winner = played;
      }
    }

    return winner.playerIndex;
  }

  // ==========================================================
  // CALCULATE HAND PENALTY
  // ==========================================================

  int calculateHandPenalty(
    int winnerIndex,
  ) {
    int totalPenalty = 0;

    // IMPORTANT:
    // ♠Q protection depends on score BEFORE this Hand
    // is added.
    bool queenProtected =
        players[winnerIndex].score >= 88;

    for (PlayedCard played in currentHand) {
      CardModel card = played.card;

      if (
        card.isSpadeQueen &&
        queenProtected
      ) {
        // ♠Q = 0.
        continue;
      }

      totalPenalty += card.penalty;
    }

    return totalPenalty;
  }

  // ==========================================================
  // HAND RESULT
  // ==========================================================

  // Hand-result popup removed for smoother gameplay.
  // The game now proceeds directly to the next Hand.

  // ==========================================================
  // COMPLETE HAND
  // ==========================================================

  Future<void> showChampionTrophy(int reached100Index) async {
    if (!mounted) return;

    final List<Player> rankedPlayers = List<Player>.from(players)
      ..sort((a, b) => a.score.compareTo(b.score));
    final Player champion = rankedPlayers.first;
    final List<Player> champions = rankedPlayers
        .where((player) => player.score == champion.score)
        .toList();
    final String championNames = champions.map((p) => p.name).join(' & ');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          title: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.65, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: const Text('🏆', style: TextStyle(fontSize: 64)),
              ),
              const SizedBox(height: 4),
              const Text('GAME OVER', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                champions.length == 1
                    ? '${champion.name} IS THE BREY CHAMPION!'
                    : 'BREY CHAMPIONS',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              Text(championNames, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text('Champion score: ${champion.score} points'),
              const SizedBox(height: 4),
              Text('Hands won: ${champion.handsWon}'),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700),
                  color: Colors.amber.withValues(alpha: 0.10),
                ),
                child: Text(
                  '${players[reached100Index].name} reached ${players[reached100Index].score} points.\nThe game has ended.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(_requestNewGame());
                },
                child: const Text('NEW GAME'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> completeHand() async {
    int winnerIndex =
        determineCurrentWinner();

    unawaited(_playFeedback(strongVibration: true));

    int handPenalty =
        calculateHandPenalty(winnerIndex);

    // Penalties are scored normally Hand by Hand. The ALL-35 rule is a
    // Round-level rule: if one player alone collects all 35 penalty points
    // across the complete Round, those 35 Round points are cancelled at
    // Round completion.
    players[winnerIndex].score += handPenalty;
    if (handPenalty > 0) {
      unawaited(_playFeedback(strongVibration: handPenalty >= 8));
    }
    roundPenaltyByPlayer[winnerIndex] =
        (roundPenaltyByPlayer[winnerIndex] ?? 0) + handPenalty;

    // V1.13: keep the highest score reached by the human during the
    // current game. It is stored permanently only when the game ends.
    if (players[0].score > _highestScoreReached) {
      _highestScoreReached = players[0].score;
    }

    players[winnerIndex].handsWon++;

    // ========================================================
    // GAME OVER AT 100 POINTS
    // ========================================================

    final bool reachedGameEnd = players[winnerIndex].score >= 100;
    if (reachedGameEnd) {
      players[winnerIndex].eliminated = true;
      gameOver = true;
      roundFinished = true;
     }

    // ========================================================
    // ♠Q COLLECTOR
    // ========================================================

    bool queenWasInThisHand =
        currentHand.any(
      (played) => played.card.isSpadeQueen,
    );

    if (queenWasInThisHand) {
      spadeQueenCollector = winnerIndex;
    }

    // ========================================================
    // MESSAGE
    // ========================================================

    // Do not place the completed-Hand summary in the upper message card.
    // The four played cards and winner animation already communicate the
    // result on the table.
    message = 'Hand $handNumber complete.';

    // Keep the four cards on the table and begin a short collection
    // animation toward the Hand winner. The scoring above has already
    // happened, so the animation is purely visual.
    if (mounted) {
      setState(() {
        handCollecting = true;
        collectingWinnerIndex = winnerIndex;
      });
    } else {
      handCollecting = true;
      collectingWinnerIndex = winnerIndex;
    }

    // No Hand-result popup: continue directly for smooth gameplay.
    if (!mounted) return;

    // ========================================================
    // GAME OVER / ROUND COMPLETION
    // ========================================================

    if (reachedGameEnd) {
      unawaited(_playFeedback(strongVibration: true));
      _recordCompletedGame(reached100Index: winnerIndex);
      Future.delayed(
        const Duration(milliseconds: 2000),
        () async {
          if (!mounted) return;
          setState(() {
            handCollecting = false;
            collectingWinnerIndex = null;
          });
          await showChampionTrophy(winnerIndex);
        },
      );
      return;
    }

    if (handNumber == 13) {
      Future.delayed(
        const Duration(milliseconds: 2000),
        () {
          if (mounted) {
            setState(() {
              handCollecting = false;
              collectingWinnerIndex = null;
            });
            unawaited(_playFeedback(strongVibration: true));
            finishRound();
          }
        },
      );

      return;
    }

    // ========================================================
    // NEXT HAND
    // ========================================================

    if (!_autoNextHand) {
      // Leave the result visible until the player explicitly continues.
      return;
    }

    final int transitionMs = _animationSpeed == 'fast' ? 1300 : 2350;
    Future.delayed(
      Duration(milliseconds: transitionMs),
      () {
        if (mounted) {
          startNextHand(winnerIndex);
        }
      },
    );
  }

  // ==========================================================
  // START NEXT HAND
  // ==========================================================

  void startNextHand(int winnerIndex) {
    if (!mounted || roundFinished || gameOver) {
      return;
    }

    setState(() {
      handCollecting = false;
      collectingWinnerIndex = null;
      currentHand.clear();
      ledSuit = null;
      handNumber++;

      // Winner leads next Hand.
      currentPlayerIndex = winnerIndex;
      message =
          '${players[currentPlayerIndex].name} leads Hand $handNumber.';
    });

    if (currentPlayerIndex != 0) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () {
          if (mounted) {
            playBotTurn();
          }
        },
      );
    }
  }

  // ==========================================================
  // FINISH ROUND
  // ==========================================================


  void finishRound() {
    // ========================================================
    // ALL 35 PENALTY POINTS IN ONE ROUND = 0
    // ========================================================

    // The complete Round contains 35 penalty points. If one player alone
    // collected all 35 during the Round, cancel those 35 points from that
    // player's total score. This rule applies across the Round, not to a
    // single Hand.
    final List<int> allThirtyFiveCollectors = roundPenaltyByPlayer.entries
        .where((entry) => entry.value == 35)
        .map((entry) => entry.key)
        .toList();

    if (allThirtyFiveCollectors.length == 1) {
      final int collectorIndex = allThirtyFiveCollectors.first;
      players[collectorIndex].score =
          max(0, players[collectorIndex].score - 35);
    }

    // ========================================================
    // ZERO HANDS WON = -5
    // SCORE NEVER BELOW ZERO
    // ========================================================

    for (Player player in players) {
      if (player.handsWon == 0) {
        player.score =
            max(0, player.score - 5);
      }
    }

    // ========================================================
    // LOWEST SCORE
    // ========================================================

    int lowestScore = players.first.score;

    for (Player player in players) {
      if (player.score < lowestScore) {
        lowestScore = player.score;
      }
    }

    List<Player> champions = players
        .where(
          (player) =>
              player.score == lowestScore,
        )
        .toList();

    // ========================================================
    // ROUND FINISHED
    // ========================================================

    roundFinished = true;

    if (champions.length == 1) {
      message =
          '${champions.first.name} is the BREY Champion with $lowestScore points!';
    } else {
      String names = champions
          .map((player) => player.name)
          .join(', ');

      message =
          'BREY Champions: $names with $lowestScore points!';
    }

    setState(() {});
  }

  // ==========================================================
  // START NEXT ROUND
  // ==========================================================

  Future<void> startNextRound() async {
    if (gameOver || dealingPhase || exchangePhase) {
      return;
    }

    if (spadeQueenCollector == null) {
      message =
          '♠Q collector was not found.';
      if (mounted) {
        setState(() {});
      }
      return;
    }

    roundNumber++;

    // ♠Q collector becomes dealer.
    dealerIndex = spadeQueenCollector!;

    // Reset Hands won for the new Round.
    for (Player player in players) {
      player.handsWon = 0;
    }

    // Leave the Round summary immediately and let dealRound() publish
    // the dealing screen after the dealer confirms SHUFFLE & DEAL.
    roundFinished = false;
    dealingPhase = false;
    exchangePhase = false;
    currentHand.clear();
    ledSuit = null;
    handCollecting = false;
    collectingWinnerIndex = null;

    if (mounted) {
      setState(() {});
    }

    await dealRound();
  }

  // ==========================================================
  // SORT HUMAN CARDS
  // ==========================================================

  List<CardModel> get sortedHumanCards {
    List<CardModel> cards =
        List<CardModel>.from(
      players[0].cards,
    );

    Map<String, int> suitOrder = {
      'Clubs': 0,
      'Diamonds': 1,
      'Hearts': 2,
      'Spades': 3,
    };

    cards.sort((a, b) {
      int suitResult =
          suitOrder[a.suit]!
              .compareTo(suitOrder[b.suit]!);

      if (suitResult != 0) {
        return suitResult;
      }

      return a.value.compareTo(b.value);
    });

    return cards;
  }

  // ==========================================================
  // CARD WIDGET
  // ==========================================================

  Duration _cardAnimationDuration(int normalMs) {
    if (!_cardAnimationEnabled) {
      return Duration.zero;
    }
    final int ms = _animationSpeed == 'fast'
        ? (normalMs * 0.55).round()
        : normalMs;
    return Duration(milliseconds: ms.clamp(0, 3000));
  }

  Future<void> _requestNewGame() async {
    startNewGame();
  }

  Widget buildCard(
    CardModel card, {
    required bool exchangeMode,
  }) {
    final bool selected = selectedExchangeCards.contains(card);

    final bool playableNow =
        gameStarted &&
        !exchangeMode &&
        !roundFinished &&
        currentPlayerIndex == 0 &&
        isLegalCard(0, card);

    final bool red =
        card.suit == 'Hearts' || card.suit == 'Diamonds';

    final Color suitColor =
        red ? const Color(0xffb42318) : const Color(0xff17202a);

    // Premium physical-card motion: selected cards rise clearly, while
    // playable cards get only a restrained hover lift.
    final double lift = selected
        ? -0.125
        : playableNow
            ? -0.060
            : 0.0;

    final double selectedGlow = selected ? 0.22 : (playableNow ? 0.08 : 0.0);

    final bool penaltyCard = card.penalty > 0;

    return RepaintBoundary(
      child: GestureDetector(
      onTap: () {
        if (exchangeMode) {
          toggleExchangeCard(card);
        } else {
          playHumanCard(card);
        }
      },
      child: AnimatedScale(
        scale: selected ? 1.055 : (playableNow ? 1.012 : 1.0),
        duration: selected ? _cardAnimationDuration(190) : Duration.zero,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: Offset(0, lift),
          duration: selected ? _cardAnimationDuration(210) : Duration.zero,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: selected ? _cardAnimationDuration(190) : Duration.zero,
            curve: Curves.easeOutCubic,
            width: 70,
            height: 102,
            margin: const EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xffffffff),
                  Color(0xfff5f2eb),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xffb58b2a)
                    : playableNow
                        ? const Color(0xffc8a45d)
                        : const Color(0xffd0cbc1),
                width: selected ? 2.5 : (playableNow ? 1.4 : 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: selected ? 0.28 : 0.15,
                  ),
                  blurRadius: selected ? 11 : 4,
                  spreadRadius: selected ? 1.2 : 0,
                  offset: const Offset(0, 4),
                ),
                if (selected)
                  BoxShadow(
                    color: const Color(0xffd4af63).withValues(
                      alpha: selectedGlow,
                    ),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Stack(
              children: [
                // Soft moving highlight makes the selected card feel lifted
                // without adding a flashy effect.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: selected ? 1.0 : 0.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.center,
                            colors: [
                              Colors.white.withValues(alpha: 0.30),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Very subtle inner frame for a more physical card feel.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: const Color(0xffe6e1d7),
                          width: 0.7,
                        ),
                      ),
                    ),
                  ),
                ),

                // Clean top-left index: rank only. The large center suit
                // remains the card's visual suit indicator.
                Positioned(
                  left: 8,
                  top: 6,
                  child: Text(
                    card.rank,
                    style: TextStyle(
                      fontSize: 17,
                      height: 0.95,
                      fontWeight: FontWeight.w900,
                      color: suitColor,
                    ),
                  ),
                ),

                // Large central suit mark.
                Center(
                  child: Text(
                    card.symbol,
                    style: TextStyle(
                      fontSize: selected ? 43 : 40,
                      height: 1,
                      color: suitColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // Penalty value is deliberately small so it does not
                // interfere with the traditional card face.
                if (penaltyCard)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Center(
                      child: Opacity(
                        opacity: selected ? 1.0 : 0.78,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: suitColor.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+${card.penalty}',
                            style: TextStyle(
                              color: suitColor,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Selection check animates in instead of appearing abruptly.
                Positioned(
                  right: 5,
                  top: 5,
                  child: AnimatedScale(
                    scale: selected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xffb58b2a),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ==========================================================
  // GAME MENU
  // ==========================================================

  void showGameMenu() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'BREY MENU',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('START NEW GAME'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  unawaited(_requestNewGame());
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('RULE BOOK'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  Future.delayed(
                    const Duration(milliseconds: 100),
                    showRuleBook,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded),
                title: const Text('BACK TO FRONT SCREEN'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  setState(() {
                    gameStarted = false;
                                   dealingPhase = false;
                    exchangePhase = false;
                    handCollecting = false;
                    collectingWinnerIndex = null;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // SCOREBOARD
  // ==========================================================

  Widget buildScoreboard() {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff182a27),
            Color(0xff0f1d1b),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffc8a45d).withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 6),
            color: Color(0x33000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xffc8a45d),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 17,
                    color: Color(0xffe0bd70),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BREY',
                        style: TextStyle(
                          color: Color(0xfff2d38b),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                        ),
                      ),
                      Text(
                        'SCOREBOARD',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    'ROUND $roundNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    'BOT ${botDifficulty.name.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Menu',
                  onPressed: showGameMenu,
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Container(
              height: 1,
              color: const Color(0xffc8a45d).withValues(alpha: 0.22),
            ),
            const SizedBox(height: 10),
            Row(
              children: players.map((player) {
                final bool danger = player.score >= 88;
                final bool eliminated = player.eliminated;

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: eliminated
                          ? Colors.red.withValues(alpha: 0.12)
                          : danger
                              ? Colors.amber.withValues(alpha: 0.10)
                              : Colors.white.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: eliminated
                            ? Colors.red.withValues(alpha: 0.55)
                            : danger
                                ? const Color(0xffd9ad52)
                                : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          player.isHuman
                              ? _playerAvatars[player.avatarIndex.clamp(0, _playerAvatars.length - 1).toInt()]['emoji']!
                              : _botAvatarForPlayer(player),
                          style: const TextStyle(fontSize: 23),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: player.isHuman
                                ? const Color(0xfff2d38b)
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${player.score}',
                          style: TextStyle(
                            color: eliminated
                                ? const Color(0xffff8d8d)
                                : danger
                                    ? const Color(0xffffd36e)
                                    : Colors.white,
                            fontSize: 23,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${player.handsWon} WON',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (danger && !eliminated)
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Text(
                              'DANGER',
                              style: TextStyle(
                                color: Color(0xffffd36e),
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        if (eliminated)
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Text(
                              'ELIMINATED',
                              style: TextStyle(
                                color: Color(0xffff8d8d),
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.0),
                ),
                Text(
                  'Lowest score wins',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 9,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // EXCHANGE PANEL
  // ==========================================================

  Widget buildExchangePanel() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              '4-CARD EXCHANGE',
              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Round $roundNumber',
              style: const TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Select exactly 4 cards.',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'You pass these cards to the player on your LEFT.',
              textAlign: TextAlign.center,
            ),

            const Text(
              'You receive 4 cards from the player on your RIGHT.',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              'Selected: ${selectedExchangeCards.length} / 4',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
                color:
                    selectedExchangeCards.length ==
                            4
                        ? Colors.green
                        : Colors.indigo,
              ),
            ),

            const SizedBox(height: 10),

            // Only the exchange cards scroll horizontally.
            // Swipe LEFT or RIGHT to see all 13 cards.
            SizedBox(
              width: double.infinity,
              height: 155,
              child: Scrollbar(
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: sortedHumanCards
                        .map(
                          (card) => buildCard(
                            card,
                            exchangeMode: true,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed:
                  selectedExchangeCards.length ==
                          4
                      ? confirmHumanExchange
                      : null,
              style:
                  ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              child: const Text(
                'PASS 4 CARDS',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              '♠Q rule: If you pass ♠Q and have another Spade, you must pass at least one other Spade with it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CURRENT HAND / TABLE
  // ==========================================================

  Widget buildPlayedCardTile(PlayedCard played) {
    final bool red =
        played.card.suit == 'Hearts' ||
        played.card.suit == 'Diamonds';

    final Color suitColor =
        red ? const Color(0xffb42318) : const Color(0xff17202a);

    // Each newly played card enters with a short lift-and-scale animation.
    return TweenAnimationBuilder<double>(
      key: ValueKey('${played.playerIndex}-${played.card.shortName}'),
      tween: Tween<double>(begin: 0.84, end: 1.0),
      duration: _cardAnimationDuration(320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        width: 72,
        height: 92,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xffffffff),
              Color(0xfff4f1e9),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xffd0cbc1),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 7,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(0xffe5e0d7),
                      width: 0.7,
                    ),
                  ),
                ),
              ),
            ),
            // Clean top-left index: rank only.
            Positioned(
              left: 7,
              top: 5,
              child: Text(
                played.card.rank,
                style: TextStyle(
                  fontSize: 16,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  color: suitColor,
                ),
              ),
            ),
            Center(
              child: Text(
                played.card.symbol,
                style: TextStyle(
                  fontSize: 31,
                  color: suitColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Positioned(
              left: 4,
              right: 4,
              bottom: 3,
              child: Text(
                players[played.playerIndex].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xff30302d),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTablePlayerLabel(
    int index, {
    required String position,
  }) {
    final player = players[index];
    final bool isTurn = currentPlayerIndex == index && !roundFinished;
    final bool isDealer = dealerIndex == index;

    // Keep player labels readable against both the dark BREY table and
    // the light card faces.  The label gets its own opaque-ish surface so
    // the player's name never relies on the background behind it for contrast.
    final Color labelBackground = isTurn
        ? const Color(0xff4a3a1d).withValues(alpha: 0.94)
        : const Color(0xff102c25).withValues(alpha: 0.94);
    final Color labelTextColor = isTurn
        ? const Color(0xffffe4a3)
        : const Color(0xfff4f1e8);
    final Color secondaryTextColor = isTurn
        ? const Color(0xffffd36e)
        : const Color(0xffd7d4ca);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTurn ? const Color(0xffe3c27a) : const Color(0xffd4af63).withValues(alpha: 0.34),
          width: isTurn ? 1.6 : 1,
        ),
        color: labelBackground,
        boxShadow: isTurn
            ? [
                BoxShadow(
                  color: const Color(0xffd4af63).withValues(alpha: 0.16),
                  blurRadius: 12,
                ),
              ]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.isHuman)
            Text(
              _playerAvatars[player.avatarIndex.clamp(0, _playerAvatars.length - 1).toInt()]['emoji']!,
              style: const TextStyle(fontSize: 17),
            )
          else
            Icon(
              position == 'bottom' ? Icons.account_circle_outlined : Icons.person_outline,
              size: 17,
              color: isTurn ? const Color(0xfff0d48e) : Colors.white70,
            ),
          const SizedBox(width: 5),
          Text(
            player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: labelTextColor,
              fontSize: 12,
              fontWeight: isTurn ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: 0.15,
            ),
          ),
          if (isDealer) ...[
            const SizedBox(width: 5),
            Text(
              'D',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (player.eliminated) ...[
            const SizedBox(width: 5),
            const Text(
              'OUT',
              style: TextStyle(
                color: Color(0xffffb4b4),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (isTurn) ...[const SizedBox(width: 5), const Icon(Icons.circle, size: 6, color: Color(0xffe3c27a))],
        ],
      ),
    );
  }

  Offset handCollectionOffsetFor(int playerIndex, int winnerIndex) {
    if (playerIndex == winnerIndex) {
      return const Offset(0, 0);
    }

    // Player positions on the table: 0 bottom, 1 right, 2 top, 3 left.
    // The offsets are expressed as fractions of the card slot size and are
    // intentionally modest so the cards appear to glide toward the winner.
    switch (winnerIndex) {
      case 0:
        switch (playerIndex) {
          case 1:
            return const Offset(-1.25, 0.55);
          case 2:
            return const Offset(0, 1.45);
          case 3:
            return const Offset(1.25, 0.55);
        }
        break;
      case 1:
        switch (playerIndex) {
          case 0:
            return const Offset(1.35, -0.60);
          case 2:
            return const Offset(1.10, 0.95);
          case 3:
            return const Offset(1.75, 0);
        }
        break;
      case 2:
        switch (playerIndex) {
          case 0:
            return const Offset(0, -1.45);
          case 1:
            return const Offset(-1.10, -0.95);
          case 3:
            return const Offset(1.10, -0.95);
        }
        break;
      case 3:
        switch (playerIndex) {
          case 0:
            return const Offset(-1.35, 0.60);
          case 1:
            return const Offset(-1.75, 0);
          case 2:
            return const Offset(-1.10, 0.95);
        }
        break;
    }

    return const Offset(0, 0);
  }

  Widget buildCurrentHand() {
    String ledSymbol = '';
    if (ledSuit != null) {
      switch (ledSuit) {
        case 'Hearts': ledSymbol = '♥'; break;
        case 'Diamonds': ledSymbol = '♦'; break;
        case 'Clubs': ledSymbol = '♣'; break;
        case 'Spades': ledSymbol = '♠'; break;
      }
    }

    Widget cardSlot(int playerIndex) {
      final played = currentHand.where((p) => p.playerIndex == playerIndex).toList();
      final playedCard = played.isEmpty ? null : played.first;

      final Widget emptySlot = Container(        width: 64,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.2,
          ),
        ),
        child: const Icon(
          Icons.style_outlined,
          color: Colors.white24,
          size: 22,
        ),
      );

      final Widget cardWidget = playedCard == null
          ? emptySlot
          : buildPlayedCardTile(playedCard);

      final bool isWinnerCard =
          handCollecting && collectingWinnerIndex == playerIndex;

      final Offset collectionTarget =
          collectingWinnerIndex == null
              ? const Offset(0, 0)
              : handCollectionOffsetFor(
                  playerIndex,
                  collectingWinnerIndex!,
                );

      Widget displayedCard = cardWidget;

      // Keep the normal table path completely static. The collection
      // animation is the only time these cards need an animation widget.
      // This prevents four animation controllers/tween states from being
      // rebuilt on every ordinary card play.
      if (handCollecting) {
        displayedCard = TweenAnimationBuilder<Offset>(
          tween: Tween<Offset>(
            begin: const Offset(0, 0),
            end: collectionTarget,
          ),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
          builder: (context, offset, child) {
            return Transform.translate(
              offset: Offset(offset.dx * 34, offset.dy * 32),
              child: Opacity(
                opacity: 0.18,
                child: Transform.scale(
                  scale: isWinnerCard ? 1.10 : 1.0,
                  child: child,
                ),
              ),
            );
          },
          child: cardWidget,
        );
      }

      return RepaintBoundary(
        child: SizedBox(
          width: 84,
          height: 98,
          child: Center(child: displayedCard),
        ),
      );
    }

    // Compact centre information so the four table positions always fit
    // comfortably on smaller phone screens.
    final center = Container(
      width: 132,
      height: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd4af63).withValues(alpha: 0.38)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff173f35).withValues(alpha: 0.92),
            const Color(0xff0c2c26).withValues(alpha: 0.92),
          ],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('BREY', style: TextStyle(color: Color(0xffe3c27a), fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 3)),
          const SizedBox(height: 2),
          if (handCollecting && collectingWinnerIndex != null)
            Text(
                '${players[collectingWinnerIndex!].name} WINS HAND',                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xfff0d48e),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              )
          else
            Text(
              'HAND $handNumber / 13',              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          const SizedBox(height: 4),
          if (ledSuit != null)
            Text(
              'LED  $ledSymbol',
              style: TextStyle(
                color: ledSuit == 'Hearts' || ledSuit == 'Diamonds'
                    ? const Color(0xffff9da8)
                    : const Color(0xfff2efe5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            )
          else
            const Text(
              'NO SUIT LED',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
              ),
            ),
          const SizedBox(height: 4),
          Text(
              '${currentHand.length} / 4 CARDS',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
        ],
      ),
    );

    return RepaintBoundary(
      child: Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff164d3e), Color(0xff0b3028), Color(0xff08251f)],
        ),
        border: Border.all(color: const Color(0xffc8a45d), width: 1.4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _BreyTablePatternPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.spa_outlined, color: Color(0xffd4af63), size: 16),
                      const SizedBox(width: 8),
                      const Text('BREY TABLE', style: TextStyle(color: Color(0xffe3c27a), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
                      const SizedBox(width: 8),
                      const Icon(Icons.spa_outlined, color: Color(0xffd4af63), size: 16),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('YOU  →  BOT 1  →  BOT 2  →  BOT 3', style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 9.5, letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  buildTablePlayerLabel(2, position: 'top'),
                  cardSlot(2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(child: cardSlot(3)),
                            buildTablePlayerLabel(3, position: 'left'),
                          ],
                        ),
                      ),
                      center,
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(child: cardSlot(1)),
                            buildTablePlayerLabel(1, position: 'right'),
                          ],
                        ),
                      ),                    ],
                  ),
                  cardSlot(0),
                  buildTablePlayerLabel(0, position: 'bottom'),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ==========================================================
  // ROUND RESULT PANEL
  // ==========================================================

  Widget buildRoundResultPanel() {
    final sortedPlayers = List<Player>.from(players)
      ..sort((a, b) => a.score.compareTo(b.score));

    final lowestScore = sortedPlayers.first.score;
    final champions = sortedPlayers
        .where((player) => player.score == lowestScore)
        .toList();

    // V1.4: The completed Round enters as a single calm reveal. This is
    // intentionally animation-only; all scores and game state were already
    // finalized by finishRound().
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Opacity(
          opacity: ((scale - 0.94) / 0.06).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'ROUND COMPLETE',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Round $roundNumber — Final Scores',
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),

              ...sortedPlayers.asMap().entries.map((entry) {
                final position = entry.key + 1;
                final player = entry.value;
                final isChampion = player.score == lowestScore;

                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (position * 70)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isChampion
                            ? Colors.amber.shade700
                            : Colors.black12,
                      ),
                      color: isChampion
                          ? Colors.amber.withValues(alpha: 0.12)
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '#$position',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${player.handsWon} Hands won',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: player.score),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedScore, child) {
                            return Text(
                              '$animatedScore',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: player.score >= 100
                                    ? Colors.red
                                    : Colors.black,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        const Text('pts'),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.94 + (0.06 * value),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Column(
                    children: [
                      Text(
                        champions.length == 1
                            ? '🏆 ${champions.first.name} IS THE BREY CHAMPION!'
                            : '🏆 BREY CHAMPIONS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (champions.length > 1) ...[
                        const SizedBox(height: 5),
                        Text(
                          champions.map((p) => p.name).join(', '),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Lowest score: $lowestScore points',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: startNextRound,
                child: const Text('START NEXT ROUND'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _requestNewGame,
                child: const Text('NEW GAME'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // ==========================================================
  // BREY RULE BOOK
  // ==========================================================

  Widget _ruleCardVisual({
    required String rank,
    required String suit,
    bool highlighted = false,
  }) {
    final bool red = suit == 'Hearts' || suit == 'Diamonds';
    final String symbol = suit == 'Hearts'
        ? '♥'
        : suit == 'Diamonds'
            ? '♦'
            : suit == 'Clubs'
                ? '♣'
                : '♠';

    return Container(
      width: 52,
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? const Color(0xffc8a45d)
              : Colors.black12,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank$symbol',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: red ? Colors.red.shade700 : Colors.black87,
        ),
      ),
    );
  }

  Widget _ruleVisual({
    required String title,
    required String explanation,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xfff7f1e4),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xffdcc58e),
        ),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Color(0xff172554),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.black87,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void showRuleBook() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 650,
              maxHeight: 700,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xff172554),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.menu_book_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'BREY RULE BOOK',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: ListView(
                      children: [
                        _ruleSection(
                          '1. OBJECTIVE',
                          'BREY is a 4-player penalty card game. Your goal is to finish with the lowest score. A player is eliminated after the Hand in which their score reaches 100 or more is scored, but they continue playing until the current Round finishes.',
                        ),

                        _ruleVisual(
                          title: 'THE 4 SUITS',
                          explanation: '♥ Hearts and ♦ Diamonds are red. ♣ Clubs and ♠ Spades are black.',
                          children: [
                            _ruleCardVisual(rank: '7', suit: 'Hearts'),
                            _ruleCardVisual(rank: 'J', suit: 'Diamonds'),
                            _ruleCardVisual(rank: 'K', suit: 'Clubs'),
                            _ruleCardVisual(rank: 'Q', suit: 'Spades'),
                          ],
                        ),

                        _ruleSection(
                          '2. THE DECK',
                          'A standard 52-card deck is used. There are 4 suits: ♥ Hearts, ♦ Diamonds, ♣ Clubs and ♠ Spades. Card strength is 2 < 3 < ... < 10 < J < Q < K < A.',
                        ),

                        _ruleSection(
                          '3. PENALTY CARDS',
                          'Every Heart = 1 point\n♦J = 4 points\n♣K = 6 points\n♠Q = 12 points\nAll other cards = 0 points\nThe complete deck contains 35 penalty points.',
                        ),

                        _ruleVisual(
                          title: 'PENALTY EXAMPLE',
                          explanation: 'These special cards give penalty points. Try not to collect them.',
                          children: [
                            _ruleCardVisual(rank: '5', suit: 'Hearts'),
                            const SizedBox(width: 5),
                            const Text('= 1', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            _ruleCardVisual(rank: 'J', suit: 'Diamonds'),
                            const SizedBox(width: 5),
                            const Text('= 4', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            _ruleCardVisual(rank: 'K', suit: 'Clubs'),
                            const SizedBox(width: 5),
                            const Text('= 6', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            _ruleCardVisual(rank: 'Q', suit: 'Spades'),
                            const SizedBox(width: 5),
                            const Text('= 12', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),

                        _ruleSection(
                          '4. ROUND & HAND',
                          'One Round consists of 13 Hands. Each Hand has one card played by each of the 4 players. All 52 cards are used during a Round.',
                        ),

                        _ruleSection(
                          '5. DEALING',
                          'A dealer is randomly selected for Round 1. Cards are dealt one at a time anticlockwise, starting with the dealer’s right-side player. Each player receives 13 cards.',
                        ),

                        _ruleVisual(
                          title: 'FOUR-CARD EXCHANGE',
                          explanation: 'Pass 4 cards to your LEFT. Receive 4 cards from your RIGHT.',
                          children: [
                            const Text('YOU', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            const Text('4 CARDS  ←', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            const Text('LEFT', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            const Text('RIGHT → 4 CARDS', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),

                        _ruleSection(
                          '6. FOUR-CARD EXCHANGE',
                          'After dealing, every player selects exactly 4 cards. You pass your 4 cards to the player on your LEFT and receive 4 cards from the player on your RIGHT. The exchange is simultaneous.',
                        ),

                        _ruleSection(
                          '7. ♠Q EXCHANGE RULE',
                          'If you pass ♠Q and have another Spade in your hand, at least one other Spade must also be passed with ♠Q. You may pass 2, 3 or 4 Spades including ♠Q. If ♠Q is your only Spade, it may be passed with any other 3 cards. If you keep ♠Q, you may pass any other 4 cards.',
                        ),

                        _ruleVisual(
                          title: 'FOLLOW THE LED SUIT',
                          explanation: '♦ is led. If you have a ♦, you must play a ♦. You cannot choose ♠ instead.',
                          children: [
                            _ruleCardVisual(rank: '8', suit: 'Diamonds', highlighted: true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('→', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            _ruleCardVisual(rank: 'K', suit: 'Diamonds', highlighted: true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('✓', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            _ruleCardVisual(rank: 'A', suit: 'Spades'),
                            const Text('  ✗', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),

                        _ruleSection(
                          '8. PLAYING A HAND',
                          'Play proceeds anticlockwise. There is no trump suit. The first card establishes the led suit. If you have a card of the led suit, you MUST follow suit. If you do not have the led suit, you may play another legal card. The highest card of the led suit wins the Hand.',
                        ),

                        _ruleSection(
                          '9. EVERY ROUND — FIRST HAND',
                          'The special restriction applies to Hand 1 of EVERY Round. The first card of Hand 1 of every Round must be a non-penalty ♣ or ♦. During this Hand, no penalty card may be played when a choice exists. If you cannot follow suit and have a non-penalty card, you must play a non-penalty card.',
                        ),

                        _ruleVisual(
                          title: 'FIRST HAND — SAFE OPENING',
                          explanation: 'Start with a non-penalty ♣ or ♦. For example, ♣7 is safe; ♠Q is a penalty card.',
                          children: [
                            _ruleCardVisual(rank: '7', suit: 'Clubs', highlighted: true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('✓', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            _ruleCardVisual(rank: 'Q', suit: 'Spades'),
                            const Text('  ✗', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),

                        _ruleSection(
                          '10. AFTER THE FIRST HAND',
                          'The special restriction ends after Hand 1 of each Round. In Hands 2–13 of every Round, if you cannot follow the led suit, any card is legal. The same first-hand restriction starts again when the next Round begins.',
                        ),

                        _ruleSection(
                          '11. TWO-CONSECUTIVE-LEAD RULE',
                          'Until ♠Q is played in the current Round, a player may lead the same suit in at most 2 consecutive Hands. A third consecutive lead of that same suit is not allowed. Leading a different suit resets the count. Once ♠Q is played, this restriction disappears for the rest of the Round.',
                        ),

                        _ruleSection(
                          '12. ♠Q — 88-POINT PROTECTION',
                          'The value of ♠Q depends on the Hand winner’s score BEFORE that Hand is scored. If the winner has less than 88 points, ♠Q = 12 points. If the winner has 88–99 points, ♠Q = 0 points. Other penalty cards in the same Hand still count normally.',
                        ),

                        _ruleVisual(
                          title: '♠Q PENALTY TRANSFER',
                          explanation: 'If you cannot follow suit and a penalty card must be played, ♠Q has priority when it is in your hand.',
                          children: [
                            _ruleCardVisual(rank: 'Q', suit: 'Spades', highlighted: true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text('→', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            const Text(
                              'HAND WINNER\ngets the ♠Q penalty',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),

                        _ruleSection(
                          '13. ♠Q BREY PENALTY-TRANSFER RULE',
                          'When you cannot follow the led suit and a penalty card must be played, ♠Q has first priority. If ♠Q is in your hand, you MUST give ♠Q to the Hand winner instead of giving ♣K, ♦J or a Heart. Normal follow-suit rules always take precedence. In Hand 1, the special non-penalty requirement still applies when a non-penalty card is available.',
                        ),

                        _ruleVisual(
                          title: 'NEW RULE — ALL 35 POINTS IN ONE ROUND',
                          explanation: 'If one player alone collects ALL 35 penalty points across the complete Round, all 35 of those Round penalty points are cancelled and that player gets 0 points from that Round penalty pool. The rule applies across the entire Round, not to a single Hand.',
                          children: [
                            _ruleCardVisual(rank: 'Q', suit: 'Spades', highlighted: true),
                            _ruleCardVisual(rank: 'K', suit: 'Clubs', highlighted: true),
                            _ruleCardVisual(rank: 'J', suit: 'Diamonds', highlighted: true),
                            _ruleCardVisual(rank: '2', suit: 'Hearts', highlighted: true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 7),
                              child: Text('→ 35 points\n→ 0 scored', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),

                        _ruleSection(
                          '14. SCORING',
                          'The player who wins a Hand collects the penalty points in that Hand. At the end of the Round, if one player alone has collected all 35 penalty points across Hands 1–13, those 35 Round penalty points are cancelled, so that player receives 0 points from those penalties for the Round.',
                        ),

                        _ruleVisual(
                          title: 'ZERO HANDS WON = −5',
                          explanation: 'At the end of a Round, a player who won no Hands gets 5 points removed. The score can never become negative.',
                          children: [
                            const Text('Score 5', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Text('  − 5  →  0', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 14),
                            const Text('Score 3', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Text('  − 5  →  0', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 14),
                            const Text('Score 12', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Text('  − 5  →  7', style: TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),

                        _ruleSection(
                          '15. ZERO HANDS ADJUSTMENT',
                          'If a player wins 0 Hands during a complete Round, 5 points are subtracted from their total score. If their score is 5 or less, their score becomes 0. It can never go below 0.',
                        ),

                        _ruleSection(
                          '16. GAME OVER & CHAMPION',
                          'The game ends immediately after a Hand is scored if any player reaches 100 or more points. The player or players with the lowest score at that moment are the BREY Champion(s). Ties for the lowest score are allowed. A trophy appears with the champion details.',
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ruleSection(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
          const SizedBox(height: 5),
          Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
        ],
      ),
    );
  }

  Widget _difficultyButton(BotDifficulty difficulty, String label) {
    final bool selected = botDifficulty == difficulty;

    return OutlinedButton(
      onPressed: () {
        setState(() {
          botDifficulty = difficulty;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xff172554)
            : Colors.white,
        foregroundColor: selected
            ? Colors.white
            : const Color(0xff172554),
        side: BorderSide(
          color: selected
              ? const Color(0xff172554)
              : const Color(0xff9ca3af),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ==========================================================
  // ANDROID BACK BUTTON — GAME MENU
  // ==========================================================

  Future<void> _showBackGameMenu() async {
    if (!mounted || _isBackGameMenuOpen) return;

    _isBackGameMenuOpen = true;

    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Leave game',
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return AlertDialog(
          title: const Text(
            'LEAVE GAME?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          content: const Text(
            'What would you like to do?',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext, 'new');
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('PLAY NEW GAME'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext, 'home');
                    },
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('HOME'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext, 'exit');
                    },
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('EXIT GAME'),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, 'cancel');
                  },
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          ],
        );
      },
    );

    _isBackGameMenuOpen = false;

    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'home') {
      setState(() {
        gameStarted = false;
           dealingPhase = false;
        exchangePhase = false;
        handCollecting = false;
        collectingWinnerIndex = null;
        roundFinished = false;
      });
      return;
    }

    if (action == 'new') {
      unawaited(_requestNewGame());
      return;
    }

    if (action == 'exit') {
      await SystemNavigator.pop();
    }
  }


  // ==========================================================
  // PLAYER GAME STATISTICS — V1.13
  // ==========================================================

  Future<void> _loadGameStatistics() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _gamesPlayed = prefs.getInt(_gamesPlayedStorageKey) ?? 0;
        _gamesWon = prefs.getInt(_gamesWonStorageKey) ?? 0;
        _gamesLost = prefs.getInt(_gamesLostStorageKey) ?? 0;
        _totalHandsPlayed = prefs.getInt(_totalHandsPlayedStorageKey) ?? 0;
        _totalHandsWon = prefs.getInt(_totalHandsWonStorageKey) ?? 0;
        _bestScore = prefs.getInt(_bestScoreStorageKey) ?? -1;
        _totalPenaltyPointsReceived =
            prefs.getInt(_totalPenaltyStorageKey) ?? 0;
        _highestScoreReached = prefs.getInt(_highestScoreStorageKey) ?? 0;
        _gameStatsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gameStatsLoaded = true;
      });
    }
  }

  Future<void> _saveGameStatistics() async {
    if (!_gameStatsLoaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_gamesPlayedStorageKey, _gamesPlayed);
      await prefs.setInt(_gamesWonStorageKey, _gamesWon);
      await prefs.setInt(_gamesLostStorageKey, _gamesLost);
      await prefs.setInt(_totalHandsPlayedStorageKey, _totalHandsPlayed);
      await prefs.setInt(_totalHandsWonStorageKey, _totalHandsWon);
      await prefs.setInt(_bestScoreStorageKey, _bestScore);
      await prefs.setInt(
        _totalPenaltyStorageKey,
        _totalPenaltyPointsReceived,
      );
      await prefs.setInt(_highestScoreStorageKey, _highestScoreReached);
    } catch (_) {
      // Statistics persistence must never interrupt gameplay.
    }
  }

  void _recordCompletedGame({required int reached100Index}) {
    if (_currentGameStatsRecorded || !_gameStatsLoaded || players.isEmpty) {
      return;
    }

    _currentGameStatsRecorded = true;

    final int finalHumanScore = players[0].score;
    final int lowestScore = players
        .map((player) => player.score)
        .reduce(min);
    final bool humanWon = finalHumanScore == lowestScore;

    _gamesPlayed++;
    if (humanWon) {
      _gamesWon++;
    } else {
      _gamesLost++;
    }

    // The game ends after the current Hand is scored, so handNumber is the
    // number of Hands actually completed in this game.
    _totalHandsPlayed += handNumber;
    _totalHandsWon += players[0].handsWon;

    if (_bestScore < 0 || finalHumanScore < _bestScore) {
      _bestScore = finalHumanScore;
    }

    // Every penalty point actually awarded to the human is reflected in
    // their score during a completed game. This also respects ♠Q protection.
    _totalPenaltyPointsReceived += players[0].score;

    if (finalHumanScore > _highestScoreReached) {
      _highestScoreReached = finalHumanScore;
    }

    _saveGameStatistics();
  }

  Future<void> _showUserDetails() async {
    if (!_gameStatsLoaded) return;

    final double winRate = _gamesPlayed == 0
        ? 0.0
        : (_gamesWon / _gamesPlayed) * 100.0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'USER DETAILS',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _playerAvatars[_selectedAvatarIndex]['emoji'] ?? '👤',
                  style: const TextStyle(fontSize: 58),
                ),
                const SizedBox(height: 6),
                Text(
                  _playerName.isEmpty ? 'YOU' : _playerName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                _statRow('Games Played', '$_gamesPlayed'),
                _statRow('Games Won', '$_gamesWon'),
                _statRow('Games Lost', '$_gamesLost'),
                _statRow('Win Percentage', '${winRate.toStringAsFixed(1)}%'),
                _statRow('Total Hands Played', '$_totalHandsPlayed'),
                _statRow('Total Hands Won', '$_totalHandsWon'),
                _statRow(
                  'Best Score',
                  _bestScore < 0 ? '—' : '$_bestScore',
                ),
                _statRow(
                  'Penalty Points Received',
                  '$_totalPenaltyPointsReceived',
                ),
                _statRow('Highest Score Reached', '$_highestScoreReached'),
              ],
            ),
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Future.delayed(
                      const Duration(milliseconds: 120),
                      _editPlayerProfile,
                    );
                  },
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('EDIT PROFILE'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CLOSE'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _editPlayerProfile() async {
    _profileNameController.text = _playerName;
    int editingAvatarIndex = _selectedAvatarIndex;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'EDIT PROFILE',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _profileNameController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 20,
                      decoration: const InputDecoration(
                        labelText: 'PLAYER NAME',
                        hintText: 'Enter your name',
                        prefixIcon: Icon(Icons.person_outline),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'CHOOSE YOUR CHARACTER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 9,
                      children: List<Widget>.generate(
                        _playerAvatars.length,
                        (index) {
                          final avatar = _playerAvatars[index];
                          final bool selected = editingAvatarIndex == index;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                editingAvatarIndex = index;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 82,
                              height: 100,
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xfffff7df)
                                    : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xffb58b2a)
                                      : Theme.of(context).dividerColor,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    avatar['emoji']!,
                                    style: const TextStyle(fontSize: 40),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    avatar['name']!,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () {
                    final String name = _profileNameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter your name.')),
                      );
                      return;
                    }
                    setState(() {
                      _playerName = name;
                      _selectedAvatarIndex = editingAvatarIndex;
                      profileCreated = true;
                    });
                    _savePlayerProfile();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    super.dispose();
  }

  // ==========================================================
  // PLAYER PROFILE — STEP B
  // Persistent profile storage.
  // ==========================================================

  Future<void> _loadPlayerProfile() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool created = prefs.getBool(_profileCreatedStorageKey) ?? false;
      final String savedName = prefs.getString(_profileNameStorageKey) ?? '';
      final int savedAvatar = prefs.getInt(_profileAvatarStorageKey) ?? 0;

      if (!mounted) return;
      setState(() {
        if (created && savedName.trim().isNotEmpty) {
          profileCreated = true;
          _playerName = savedName.trim();
          _selectedAvatarIndex = savedAvatar.clamp(0, _playerAvatars.length - 1).toInt();
        }
        _profileLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileLoaded = true;
      });
    }
  }

  Future<void> _savePlayerProfile() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profileCreatedStorageKey, true);
      await prefs.setString(_profileNameStorageKey, _playerName);
      await prefs.setInt(_profileAvatarStorageKey, _selectedAvatarIndex);
    } catch (_) {
      // Profile persistence must never prevent BREY from starting or playing.
    }
  }

  void _createPlayerProfile() {
    final String name = _profileNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name.')),
      );
      return;
    }

    setState(() {
      _playerName = name;
      profileCreated = true;
    });
    _savePlayerProfile();
  }

  Widget _profileAvatarCard(int index) {
    final avatar = _playerAvatars[index];
    final bool selected = _selectedAvatarIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAvatarIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 92,
        height: 112,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xfffff7df)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xffb58b2a)
                : const Color(0xffd5c9b0),
            width: selected ? 2.2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.13),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 180),
              child: Text(
                avatar['emoji']!,
                style: const TextStyle(fontSize: 47),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              avatar['name']!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xff6e5118)
                    : const Color(0xff665a48),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              avatar['gender']!,
              style: const TextStyle(
                fontSize: 8,
                color: Color(0xff8b7b62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerProfileSetup() {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool compact = constraints.maxHeight < 680;
            return Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xfff3ead7),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 520 ? 40 : 22,
                  vertical: compact ? 16 : 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        const Text(
                          'WELCOME TO BREY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 3.2,
                            color: Color(0xff17130d),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'CREATE YOUR PLAYER PROFILE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.7,
                            color: Color(0xff6b5a40),
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _profileNameController,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 20,
                          decoration: InputDecoration(
                            labelText: 'PLAYER NAME',
                            hintText: 'Enter your name',
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.78),
                            counterText: '',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xffc9b996),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xffc9b996),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xffa47b24),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 19),
                        const Text(
                          'CHOOSE YOUR CHARACTER',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.7,
                            color: Color(0xff5f513b),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 9,
                          runSpacing: 10,
                          children: List<Widget>.generate(
                            _playerAvatars.length,
                            _profileAvatarCard,
                          ),
                        ),
                        const SizedBox(height: 23),
                        SizedBox(
                          width: 330,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _createPlayerProfile,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text(
                              'CREATE PROFILE',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff17130d),
                              foregroundColor: const Color(0xfffff8e8),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0xffc29a45),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'You can change your profile later.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xff817258),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ==========================================================
  // VIBRATION FEEDBACK — V1.18
  // ==========================================================

  Future<void> _playFeedback({
    bool vibrate = true,
    bool strongVibration = false,
  }) async {
    if (!_vibrationEnabled || !vibrate) return;
    try {
      if (strongVibration) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  Future<void> _playIllegalMoveFeedback() async {
    await _playFeedback();
  }

  Future<void> _loadSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _vibrationEnabled = prefs.getBool(_settingsVibrationKey) ?? true;
        _appearanceMode = prefs.getString(_settingsAppearanceKey) ?? 'system';
        if (!_appearanceOptions.contains(_appearanceMode)) _appearanceMode = 'system';
        _cardAnimationEnabled = prefs.getBool(_settingsCardAnimationKey) ?? true;
        _animationSpeed = prefs.getString(_settingsAnimationSpeedKey) ?? 'normal';
        if (!_animationSpeedOptions.contains(_animationSpeed)) _animationSpeed = 'normal';
        _autoNextHand = prefs.getBool(_settingsAutoNextHandKey) ?? true;
        _beginnerHintsEnabled = prefs.getBool(_settingsHintsKey) ?? true;
        _ruleRemindersEnabled = prefs.getBool(_settingsRuleRemindersKey) ?? true;
        _keepScreenAwake = prefs.getBool(_settingsKeepAwakeKey) ?? true;
        _settingsLoaded = true;
      });
     } catch (_) {
      _settingsLoaded = true;
    }
  }

  static const List<String> _appearanceOptions = <String>[
    'system',
    'light',
    'dark',
  ];

  static const List<String> _animationSpeedOptions = <String>[
    'normal',
    'fast',
  ];

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_settingsVibrationKey, _vibrationEnabled);
      await prefs.setString(_settingsAppearanceKey, _appearanceMode);
      await prefs.setBool(_settingsCardAnimationKey, _cardAnimationEnabled);
      await prefs.setString(_settingsAnimationSpeedKey, _animationSpeed);
      await prefs.setBool(_settingsAutoNextHandKey, _autoNextHand);
      await prefs.setBool(_settingsHintsKey, _beginnerHintsEnabled);
      await prefs.setBool(_settingsRuleRemindersKey, _ruleRemindersEnabled);
      await prefs.setBool(_settingsKeepAwakeKey, _keepScreenAwake);
    } catch (_) {
      // Settings are convenience preferences; gameplay must continue.
    }
  }

  String _appearanceLabel(String value) {
    switch (value) {
      case 'light':
        return 'Light Mode';
      case 'dark':
        return 'Dark Mode';
      default:
        return 'System Default';
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void update(VoidCallback change) {
              setDialogState(change);
              setState(change);
              if (_appearanceMode.isNotEmpty) {
                widget.onAppearanceChanged?.call(_appearanceMode);
              }
                       _saveSettings();
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings_rounded),
                  SizedBox(width: 10),
                  Text('SETTINGS'),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _settingsSectionTitle('VIBRATION'),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vibration'),
                        subtitle: const Text('Touch and game feedback'),
                        value: _vibrationEnabled,
                        onChanged: (value) => update(() => _vibrationEnabled = value),
                      ),
                      const Divider(),
                      _settingsSectionTitle('APPEARANCE'),
                      DropdownButtonFormField<String>(
                        value: _appearanceMode,
                        decoration: const InputDecoration(
                          labelText: 'Theme',
                          border: OutlineInputBorder(),
                        ),
                        items: _appearanceOptions.map((value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(_appearanceLabel(value)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          update(() => _appearanceMode = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      _settingsSectionTitle('GAMEPLAY CONVENIENCE'),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Card Animation'),
                        value: _cardAnimationEnabled,
                        onChanged: (value) => update(() => _cardAnimationEnabled = value),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Animation Speed'),
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(value: 'normal', label: Text('Normal')),
                            ButtonSegment<String>(value: 'fast', label: Text('Fast')),
                          ],
                          selected: <String>{_animationSpeed},
                          onSelectionChanged: (selection) {
                            if (selection.isEmpty) return;
                            update(() => _animationSpeed = selection.first);
                          },
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto Next Hand'),
                        value: _autoNextHand,
                        onChanged: (value) => update(() => _autoNextHand = value),
                      ),
                      const Divider(),
                      _settingsSectionTitle('ASSISTANCE'),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Beginner Hints'),
                        value: _beginnerHintsEnabled,
                        onChanged: (value) => update(() => _beginnerHintsEnabled = value),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Rule Reminders'),
                        value: _ruleRemindersEnabled,
                        onChanged: (value) => update(() => _ruleRemindersEnabled = value),
                      ),
                      const Divider(),
                      _settingsSectionTitle('OTHER'),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Keep Screen Awake'),
                        subtitle: const Text('Saved preference; device-level screen wake is handled separately.'),
                        value: _keepScreenAwake,
                        onChanged: (value) => update(() => _keepScreenAwake = value),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.menu_book_rounded),
                        title: const Text('Rule Book'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          showRuleBook();
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('About BREY'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (aboutContext) => AlertDialog(
                              title: const Text('ABOUT BREY'),
                              content: const Text(
                                'BREY is a classic game of cards, risk & strategy.\n\n'
                                'Settings are saved on this device for convenience.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(aboutContext),
                                  child: const Text('CLOSE'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CLOSE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _settingsSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Color(0xff8a6a2b),
          ),
        ),
      ),
    );
  }

  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    // ========================================================
    // START SCREEN
    // ========================================================

    if (!_profileLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!profileCreated) {
      return _buildPlayerProfileSetup();
    }

    if (!gameStarted) {
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final w = constraints.maxWidth;
              final titleSize = (h * 0.20).clamp(58.0, 150.0);

              return Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xfff3ead7),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 8),

                      // BREY — same size, slimmer and more elegant.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'BREY',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 6,
                            color: const Color(0xff17130d),
                            height: 0.9,
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'A CLASSIC GAME OF CARDS, RISK & STRATEGY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.7,
                          color: Color(0xff5f513b),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Small classic divider.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 1,
                            color: const Color(0xffc29a45),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '✦',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xffa47b24),
                              ),
                            ),
                          ),
                          Container(
                            width: 46,
                            height: 1,
                            color: const Color(0xffc29a45),
                          ),
                        ],
                      ),

                      const Spacer(),

                      const Text(
                        '♠   ♥   ♦   ♣',
                        style: TextStyle(
                          fontSize: 25,
                          letterSpacing: 5,
                          color: Color(0xffa47b24),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'CHOOSE BOT LEVEL',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                          color: Color(0xff5f513b),
                        ),
                      ),

                      const SizedBox(height: 11),

                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          _difficultyButton(BotDifficulty.easy, 'EASY'),
                          _difficultyButton(BotDifficulty.medium, 'MEDIUM'),
                          _difficultyButton(BotDifficulty.hard, 'HARD'),
                        ],
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: w > 420 ? 340 : double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: _requestNewGame,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'START NEW GAME',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff17130d),
                            foregroundColor: const Color(0xfffff8e8),
                            elevation: 5,
                            shadowColor: const Color(0x44000000),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                              side: const BorderSide(
                                color: Color(0xffc29a45),
                                width: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: w > 420 ? 340 : double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _showUserDetails,
                          icon: const Icon(Icons.person_rounded, size: 19),
                          label: const Text(
                            'USER DETAILS',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.3,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff17130d),
                            side: const BorderSide(
                              color: Color(0xffa47b24),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      SizedBox(
                        width: w > 420 ? 340 : double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _showSettings,
                          icon: const Icon(Icons.settings_rounded, size: 19),
                          label: const Text(
                            'SETTINGS',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.3,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff17130d),
                            side: const BorderSide(
                              color: Color(0xffa47b24),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      SizedBox(
                        width: w > 420 ? 340 : double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: showRuleBook,
                          icon: const Icon(Icons.menu_book_rounded, size: 19),
                          label: const Text(
                            'RULE BOOK',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.3,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff17130d),
                            side: const BorderSide(
                              color: Color(0xffa47b24),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // ========================================================
    // V42.53 STABILITY TEST BASE
// No gameplay, AI, UI, or rule changes.
// GAME SCREEN
    // ========================================================

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showBackGameMenu();
        }
      },
      child: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // =================================================
              // SECTION 1 — SCOREBOARD
              // Hidden while shuffling/dealing so the dealing
              // animation gets the full screen area.
              // =================================================

              if (!dealingPhase) ...[
                buildScoreboard(),
                const SizedBox(height: 10),
              ],

              // =================================================
              // SECTION 2 — PLAY AREA
              // =================================================

              if (dealingPhase)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 520,
                    ),
                    child: buildDealingPanel(),
                  ),
                ),

              if (exchangePhase)
                buildExchangePanel(),

              if (!dealingPhase &&
                  !exchangePhase &&
                  !roundFinished) ...[
                buildCurrentHand(),

                if (handCollecting &&
                    !_autoNextHand &&
                    !gameOver &&
                    !roundFinished &&
                    collectingWinnerIndex != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => startNextHand(collectingWinnerIndex!),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text('CONTINUE TO HAND ${handNumber + 1}'),
                  ),
                ],

                const SizedBox(height: 10),

                Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.style),
                            const SizedBox(width: 6),
                            const Text(
                              'YOUR CARDS',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // ONLY THIS AREA scrolls horizontally.
                        SizedBox(
                          width: double.infinity,
                          height: (MediaQuery.sizeOf(context).width * 0.34)
                              .clamp(112.0, 145.0)
                              .toDouble(),
                          child: Scrollbar(
                            thumbVisibility: true,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: sortedHumanCards
                                    .map(
                                      (card) => buildCard(
                                        card,
                                        exchangeMode: false,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 5),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: currentPlayerIndex == 0
                                ? Colors.green.withValues(alpha: 0.12)
                                : Colors.indigo.withValues(alpha: 0.10),
                          ),
                          child: Text(
                            currentPlayerIndex == 0
                                ? 'YOUR TURN — SELECT A CARD'
                                : '${players[currentPlayerIndex].name} is playing...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: currentPlayerIndex == 0
                                  ? Colors.green[800]
                                  : Colors.indigo[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (roundFinished && !gameOver)
                buildRoundResultPanel(),

              const SizedBox(height: 20),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _BreyTablePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0xffd4af63).withValues(alpha: 0.045);

    // Keep the decorative pattern safely inside the table.
    final rect = Rect.fromLTWH(
      26,
      26,
      size.width - 52,
      size.height - 52,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(18),
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.68,
        height: size.height * 0.44,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


