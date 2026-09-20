import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// BREY V1.3.46 — PHASE 11: DETERMINISTIC LOOK-AHEAD / COMBINATION SEARCH

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
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BREY',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffc8a45d),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xffeef0ed),
        useMaterial3: true,

        // BREY premium button system: deep forest, warm ivory and restrained
        // antique-gold accents. This keeps buttons clearly separated from
        // the light game background without using bright/vibrant colours.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff182a27),
            foregroundColor: const Color(0xfffff8e8),
            disabledBackgroundColor: const Color(0xffddd8cc),
            disabledForegroundColor: const Color(0xff817b70),
            elevation: 4,
            shadowColor: const Color(0x55000000),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xffc8a45d),
                width: 1.1,
              ),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff182a27),
            backgroundColor: const Color(0x00ffffff),
            side: const BorderSide(
              color: Color(0xffa9853d),
              width: 1.2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xff765b27),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
        ),
      ),
      home: const BreyGame(),
    );
  }
}

// ============================================================
// GAME
// ============================================================

class BreyGame extends StatefulWidget {

  const BreyGame({
    super.key,
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

  // Completed Hands for the current Round. These snapshots power the
  // Round Summary so the player can review every Hand, every played card,
  // the Hand winner, and the actual penalty points collected.
  final List<List<PlayedCard>> completedRoundHands = <List<PlayedCard>>[];
  final List<int> completedRoundWinners = <int>[];
  final List<int> completedRoundPenalties = <int>[];

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
  bool _cardAnimationEnabled = true;
  String _animationSpeed = 'normal';
  bool _autoNextHand = true;
  bool _beginnerHintsEnabled = true;
  bool _ruleRemindersEnabled = true;
  bool _keepScreenAwake = true;

  static const String _settingsVibrationKey = 'brey_settings_vibration';
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

  // Prevent duplicate Hand-resolution callbacks from clearing a Hand twice.
  // A delayed BOT callback and the final card animation can otherwise race
  // around the fourth card and consume the next Hand's state.
  bool _handResolving = false;
  // Hard one-second lock between completed-Hand processing and the next Hand.
  bool _handTransitionDelay = false;

  // Single authoritative BOT runner. There must never be multiple delayed BOT
  // callbacks competing to play the same Hand.

  // Exactly one card from each of the four players must be played before
  // any Hand calculation is allowed to begin. This is the authoritative
  // per-Hand turn ledger and also blocks duplicate/stale BOT callbacks.
  final Set<int> _playersPlayedThisHand = <int>{};

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

  // Prevent delayed BOT callbacks from an old Hand from playing cards in a
  // new Hand after the previous Hand has been collected.
  int _botTurnGeneration = 0;
  bool _botTurnScheduled = false;
  int _botRecoveryAttempts = 0;

  // Selected BOT difficulty. The UI intentionally shows only the
  // difficulty names; the strength calibration is kept internal.
  BotDifficulty botDifficulty = BotDifficulty.medium;

  // Strategic memory for each BOT.
  final Map<int, List<CardModel>> passedCardsByPlayer = {};
  final Map<int, List<CardModel>> receivedCardsByPlayer = {};
  final List<CardModel> playedCardsThisRound = [];

  // ==========================================================
  // PHASE 12 — ADAPTIVE OPPONENT BEHAVIOR MEMORY
  // ==========================================================
  // Publicly observed tendencies only. These counters persist across Hands
  // so BOTs can adapt to repeated patterns without seeing hidden cards.
  final List<Map<String, int>> observedLeadSuitCount = [
    <String, int>{}, <String, int>{}, <String, int>{}, <String, int>{},
  ];
  final List<Map<String, int>> observedPenaltyDiscardBySuit = [
    <String, int>{}, <String, int>{}, <String, int>{}, <String, int>{},
  ];
  final List<int> observedHandsWon = [0, 0, 0, 0];
  final List<int> observedHandsPlayed = [0, 0, 0, 0];
  final List<int> observedPenaltyCardsPlayed = [0, 0, 0, 0];
  // Suit voids inferred from a player failing to follow a led suit.
  final List<Set<String>> voidSuitsByPlayer = [
    <String>{},
    <String>{},
    <String>{},
    <String>{},
  ];

  // Private exchange knowledge. Each viewer gets a separate ownership map.
  // A player may know where cards THEY passed went and which cards THEY
  // received, but never sees another player's private exchange cards.
  final Map<int, Map<String, int>> privateKnownCardOwnerByPlayer = {
    0: <String, int>{},
    1: <String, int>{},
    2: <String, int>{},
    3: <String, int>{},
  };

  // Publicly observed suit counts: cards of this suit already seen during
  // this Round. Used with void information to estimate what remains.
  final Map<String, int> playedSuitCounts = {
    'Hearts': 0,
    'Diamonds': 0,
    'Clubs': 0,
    'Spades': 0,
  };

  // ==========================================================
  // AUTHORITATIVE TABLE DIRECTIONS
  // ==========================================================
  //
  // BREY uses opposite directions for exchange and gameplay:
  //   CHOOSING / EXCHANGE: RIGHT (player - 1)
  //   CARD PLAY: LEFT (player + 1)
  //
  // Example when Player 0 is the dealer:
  //   EXCHANGE: YOU -> BOT 3 -> BOT 2 -> BOT 1 -> YOU
  //   PLAY:     BOT 1 -> BOT 2 -> BOT 3 -> YOU
  //
  // Keeping these mappings in one place prevents direction drift between
  // exchange, dealing, card play, and bot prediction.
  int playerOnLeft(int playerIndex) => (playerIndex + 1) % 4;

  int playerOnRight(int playerIndex) => (playerIndex + 3) % 4;

  // Authoritative BREY directions are kept exactly as implemented in the game engine.
  // UI wording should describe the player-visible LEFT pass and play order.
  int nextPlayerForPlay(int playerIndex) => playerOnLeft(playerIndex);

  // Legacy compatibility alias. Existing code may still call this name,
  // and it follows the authoritative CLOCKWISE gameplay direction.
  int nextPlayerClockwise(int playerIndex) => nextPlayerForPlay(playerIndex);

  // RULE 1 — VOID + ♠Q:
  // In Hands 2–13, if a player is void in the led suit and holds ♠Q,
  // ♠Q MUST be thrown. There is NO ♠Q lock rule.
  //
  // This method remains only because the play flow already calls it.
  // The actual legality rule is enforced authoritatively by isLegalCard().
    // BREY DIRECTION RULE:
  // Passing 4 cards: 1 -> 4 -> 3 -> 2 -> 1 (right / -1).
  // Playing cards:   1 -> 2 -> 3 -> 4 -> 1 (left / +1).


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

  // GLOBAL lead-suit rule:
  // the consecutive lead count belongs to the whole table, not to
  // individual players. After a suit is led twice consecutively,
  // nobody may lead that suit on the next Hand until another suit is led.
  String? globalConsecutiveLedSuit;
  int globalConsecutiveLedSuitCount = 0;

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

  Widget _hintFlow({
    required String title,
    required List<Widget> steps,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffd8c99f)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Color(0xff172554),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: steps,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintArrow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: Color(0xff172554),
        ),
      ),
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
                          _coloredSuitText(
                            message,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
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
    // Contextual teaching hint: show the explanation whenever the player
    // reaches this situation, not only the first time in the whole game.
    // The caller already triggers this only after an attempted illegal move,
    // so repeating it here gives a new player help exactly when it is needed.
    if (!mounted || (!_beginnerHintsEnabled && !_ruleRemindersEnabled)) return;

    // Each distinct rule hint is shown only once during the game session.
    // Once the player has learned a rule, do not interrupt them with the
    // same popup again; other rule situations can still show their own hint.
    if (_shownRuleHints.contains(key)) return;
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
        handNumber != 1 ||
        currentPlayerIndex != 0) {
      return;
    }

    _firstHandHintShown = true;

    await _showSmoothHint(
      title: 'FIRST HAND — EASY START',
      message:
          'Three things to remember in Hand 1:\n\n'
          '1. PLAYING goes RIGHT (CLOCKWISE): the player immediately after the dealer starts Hand 1. If YOU are the dealer: Bot 1 → Bot 2 → Bot 3 → You.\n'
          '2. If you have a safe ♣ or ♦, you must lead one of them. If you do not, any card except ♠Q may lead.\n'
          '3. If you cannot follow suit in Hand 1, play a non-penalty card when you have one.',
      scenario: _hintFlow(
        title: 'HAND 1 — DIRECTION + OPENING',
        steps: [
          Column(children: [
            const Text('PLAY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const Text('BOT 1 → BOT 2 → BOT 3 → YOU', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
            const Text("START FROM DEALER'S RIGHT", style: TextStyle(fontSize: 9)),
          ]),
          _hintArrow('→'),
          Column(children: [
            const Text('YOUR LEGAL LEAD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            _hintCard(rank: '7', suit: 'Clubs', highlighted: true),
            _coloredSuitText('SAFE ♣ / ♦', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          ]),
        ],
      ),
    );
  }

  // ==========================================================
  // V1.3.24 - FINAL COMPILE FIX: directions, Q legality, round-end flow, privacy, and rulebook
// No gameplay behavior is changed in this audit build.
// V42.56 STABILITY BASELINE CHECKS — REVERSED DIRECTION
  // ==========================================================

  void _runDirectionIntegrityChecks() {

    assert(playerOnLeft(0) == 1);
    assert(playerOnLeft(1) == 2);
    assert(playerOnLeft(2) == 3);
    assert(playerOnLeft(3) == 0);

    assert(nextPlayerForPlay(0) == 1);
    assert(nextPlayerForPlay(1) == 2);
    assert(nextPlayerForPlay(2) == 3);
    assert(nextPlayerForPlay(3) == 0);


    assert(playerOnLeft(0) == 1);
    assert(playerOnLeft(1) == 2);
    assert(playerOnLeft(2) == 3);
    assert(playerOnLeft(3) == 0);

    assert(playerOnRight(0) == 3);
    assert(playerOnRight(3) == 2);
    assert(playerOnRight(2) == 1);
    assert(playerOnRight(1) == 0);

    assert(nextPlayerForPlay(0) == 1);
    assert(nextPlayerForPlay(1) == 2);
    assert(nextPlayerForPlay(2) == 3);
    assert(nextPlayerForPlay(3) == 0);
  }

  // Verifies that no card has been lost or duplicated during gameplay.
  // This is intentionally read-only: it never changes game state.
  void _verifyCardConservation(String context) {
    final Set<String> seen = <String>{};
    int totalCards = 0;

    for (final Player player in players) {
      totalCards += player.cards.length;
      for (final CardModel card in player.cards) {
        final String key = cardKey(card);
        if (!seen.add(key)) {
          debugPrint('BREY CARD ERROR [$context]: duplicate card $key');
        }
      }
    }

    // playedCardsThisRound contains both cards currently on the table and
    // cards already collected. Therefore every physical card in the deck
    // must appear exactly once across player hands + this list.
    totalCards += playedCardsThisRound.length;

    for (final CardModel card in playedCardsThisRound) {
      final String key = cardKey(card);
      if (!seen.add(key)) {
        debugPrint('BREY CARD ERROR [$context]: duplicate played card $key');
      }
    }

    if (totalCards != 52 || seen.length != 52) {
      debugPrint(
        'BREY CARD ERROR [$context]: card conservation failed. '
        'total=$totalCards unique=${seen.length}',
      );
    }
  }

  void _runGameplayStabilityChecks() {
    _runDirectionIntegrityChecks();
    assert(() {
      // Each player can never hold more than 13 cards.
      for (final Player player in players) {
        assert(player.cards.length <= 13);
      }

      // A Hand can contain at most four played cards, and the turn ledger
      // must match the number of cards currently on the table.
      assert(currentHand.length <= 4);
      assert(_playersPlayedThisHand.length == currentHand.length);

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
  // START A NEW GAME
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
}
    globalConsecutiveLedSuit = null;
    globalConsecutiveLedSuitCount = 0;

    for (int i = 0; i < 4; i++) {
      roundPenaltyByPlayer[i] = 0;
    }

    currentHand.clear();
    _playersPlayedThisHand.clear();
    ledSuit = null;

    roundFinished = false;
    gameOver = false;
    exchangePhase = false;
    handCollecting = false;
    collectingWinnerIndex = null;
    _handResolving = false;
    _handTransitionDelay = false;
    dealingPhase = false;
    dealtCardCount = 0;
    dealingStartingPlayer = 0;
    _dealingGeneration++;

    selectedExchangeCards.clear();
    exchangeSelections.clear();

    passedCardsByPlayer.clear();
    receivedCardsByPlayer.clear();
    playedCardsThisRound.clear();
    clearPrivateExchangeKnowledge();
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
    clearPrivateExchangeKnowledge();
    playedSuitCounts.clear();
    playedSuitCounts.addAll({
      'Hearts': 0,
      'Diamonds': 0,
      'Clubs': 0,
      'Spades': 0,
    });
    resetVoidMemory();

    // The next player in the CLOCKWISE play direction starts Hand 1.
    int startingPlayer = playerOnLeft(dealerIndex);

    int playerIndex = startingPlayer;

    // Deal one card at a time using the authoritative playing direction.
    for (CardModel card in deck) {
      players[playerIndex].cards.add(card);

      playerIndex = nextPlayerForPlay(playerIndex);
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
    for (int i = 0; i < 4; i++) {
}
    globalConsecutiveLedSuit = null;
    globalConsecutiveLedSuitCount = 0;

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
    globalConsecutiveLedSuit = null;
    globalConsecutiveLedSuitCount = 0;
  }

  // ==========================================================
  // EXCHANGE CARD SELECTION
  // ==========================================================

  void toggleExchangeCard(CardModel card) {
    // Exchange card choosing has no popup hint. The exchange panel itself
    // already tells the player to choose 4 cards to pass to the LEFT.
    if (!exchangePhase) {
      return;
    }

    if (selectedExchangeCards.contains(card)) {
      selectedExchangeCards.remove(card);
      unawaited(_playFeedback());
    } else {
      if (selectedExchangeCards.length >= 4) {
        message = 'You can select a maximum of 4 cards.';
        setState(() {});
        return;
      }

      selectedExchangeCards.add(card);
      unawaited(_playFeedback());

      // Keep the ♠Q-specific exchange popup. There is no generic
      // choosing-card popup; this reminder appears only when ♠Q is selected.
      if (card.isSpadeQueen) {
        unawaited(_showRuleHintOnce(
          key: 'spade_queen_exchange',
          title: '♠Q EXCHANGE RULE',
          message:
              'If you pass ♠Q while you still have another Spade in your original hand, '
              'you must pass at least one additional Spade with it. If ♠Q is your only Spade, '
              'the other 3 cards may be any cards.',
        ));
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
          '♠Q rule: if you have another Spade, you must pass at least one additional Spade with ♠Q.';
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

  // ==========================================================
  // EXCHANGE AI — LEGAL 4-CARD PACKAGE ENGINE
  // ==========================================================

  // BREY exchange direction is LEFT (ANTI-CLOCKWISE).
  // Keep the authoritative direction helper from the rule engine.
  int exchangeTargetIndex(int botIndex) => playerOnRight(botIndex);

  double _exchangeCardDanger(CardModel card) {
    if (card.isSpadeQueen) return 1000.0;
    if (card.suit == 'Clubs' && card.rank == 'K') return 650.0;
    if (card.suit == 'Diamonds' && card.rank == 'J') return 450.0;
    if (card.suit == 'Hearts') return 55.0;
    return 0.0;
  }

  double _exchangeHighCardRisk(
    CardModel card,
    List<CardModel> hand,
  ) {
    if (card.penalty > 0 || card.value < 10) return 0.0;

    final int lowerSameSuit = hand.where(
      (CardModel other) =>
          other.suit == card.suit && other.value < card.value,
    ).length;

    if (lowerSameSuit == 0) return 360.0;
    if (lowerSameSuit == 1) return 180.0;
    if (lowerSameSuit == 2) return 70.0;
    return 20.0;
  }

  double _exchangeRemainingHandQuality(
    List<CardModel> original,
    List<CardModel> remaining,
  ) {
    double score = 0.0;
    const List<String> suits = <String>[
      'Clubs',
      'Diamonds',
      'Hearts',
      'Spades',
    ];

    for (final String suit in suits) {
      final List<CardModel> before = original
          .where((CardModel card) => card.suit == suit)
          .toList();
      final List<CardModel> after = remaining
          .where((CardModel card) => card.suit == suit)
          .toList();

      if (before.isNotEmpty && after.isEmpty) {
        final int penalty = before.fold<int>(
          0,
          (int sum, CardModel card) => sum + card.penalty,
        );
        score += before.length == 1 ? 260.0 : 150.0;
        score += penalty * 35.0;
      }

      final int lowCards = after
          .where((CardModel card) => card.value <= 7)
          .length;
      if (lowCards >= 3) {
        score += 110.0;
      } else if (lowCards == 2) {
        score += 65.0;
      } else if (lowCards == 0 && after.isNotEmpty) {
        score -= after.any((CardModel card) => card.penalty > 0)
            ? 130.0
            : 55.0;
      }

      if (after.length >= 2 &&
          after.every((CardModel card) => card.value <= 7)) {
        score += after.length * 22.0;
      }
    }

    return score;
  }

  double scoreStrategicExchange(
    int botIndex,
    List<CardModel> selection,
    List<CardModel> hand,
  ) {
    double score = 0.0;
    final int targetIndex = exchangeTargetIndex(botIndex);
    final int targetScore = players[targetIndex].score;
    final List<CardModel> remaining = List<CardModel>.from(hand)
      ..removeWhere((CardModel card) => selection.contains(card));

    // 1. Remove cards that are dangerous for the BOT.
    for (final CardModel card in selection) {
      score += _exchangeCardDanger(card);
      score += _exchangeHighCardRisk(card, hand);
    }

    // 2. Passing penalty to a player who is already near the game threshold
    // is strategically valuable. Only public score information is used.
    if (targetScore >= 94) {
      score += selection.fold<double>(
        0.0,
        (double sum, CardModel card) => sum + card.penalty * 30.0,
      );
    } else if (targetScore >= 88) {
      score += selection.fold<double>(
        0.0,
        (double sum, CardModel card) => sum + card.penalty * 18.0,
      );
    } else if (targetScore >= 70) {
      score += selection.fold<double>(
        0.0,
        (double sum, CardModel card) => sum + card.penalty * 7.0,
      );
    }

    // 3. Judge the resulting 9-card hand.
    score += _exchangeRemainingHandQuality(hand, remaining);

    // 4. ♠Q package evaluation. Legality is already enforced by the
    // authoritative isLegalExchangeSelection() function.
    final bool passesQueen = selection.any(
      (CardModel card) => card.isSpadeQueen,
    );
    final List<CardModel> originalSpades = hand
        .where((CardModel card) => card.suit == 'Spades')
        .toList();
    final List<CardModel> remainingSpades = remaining
        .where((CardModel card) => card.suit == 'Spades')
        .toList();

    if (passesQueen) {
      final int lowerSpadesRemaining = remainingSpades
          .where((CardModel card) => card.value < 12)
          .length;

      if (lowerSpadesRemaining >= 3) {
        score -= 500.0;
      } else if (lowerSpadesRemaining == 2) {
        score -= 230.0;
      } else if (lowerSpadesRemaining == 1) {
        score -= 50.0;
      }

      // If ♠Q is the only Spade, passing it creates a clean Spade void.
      if (originalSpades.length == 1) {
        score += 420.0;
      }
    }

    // Do not destroy several useful low Spades merely to create a void.
    if (remainingSpades.isEmpty && originalSpades.length >= 3) {
      final int lowSpades = originalSpades
          .where((CardModel card) => card.value <= 7)
          .length;
      if (lowSpades >= 2) {
        score -= 320.0;
      }
    }

    // 5. Preserve a controlled long low suit.
    const List<String> suits = <String>[
      'Clubs',
      'Diamonds',
      'Hearts',
      'Spades',
    ];
    for (final String suit in suits) {
      final List<CardModel> before = hand
          .where((CardModel card) => card.suit == suit)
          .toList();
      final List<CardModel> after = remaining
          .where((CardModel card) => card.suit == suit)
          .toList();

      if (before.length >= 4 &&
          before.where((CardModel card) => card.value <= 7).length >= 3 &&
          after.length < before.length) {
        score -= 240.0;
      }
    }

    // 6. In the late Round, immediate penalty removal matters more.
    if (isLateRound()) {
      score += selection.fold<double>(
        0.0,
        (double sum, CardModel card) => sum + card.penalty * 15.0,
      );
    }

    return score;
  }

  List<CardModel> chooseBotExchangeCards(Player bot) {
    final List<CardModel> hand = List<CardModel>.from(bot.cards);
    if (hand.length < 4) return <CardModel>[];

    final int botIndex = players.indexOf(bot);
    List<CardModel> bestSelection = <CardModel>[];
    double bestScore = -double.infinity;

    // C(13,4) = 715 maximum combinations. Evaluate every legal package.
    for (int a = 0; a < hand.length - 3; a++) {
      for (int b = a + 1; b < hand.length - 2; b++) {
        for (int c = b + 1; c < hand.length - 1; c++) {
          for (int d = c + 1; d < hand.length; d++) {
            final List<CardModel> selection = <CardModel>[
              hand[a],
              hand[b],
              hand[c],
              hand[d],
            ];

            // RULES FIRST: never score an illegal exchange package.
            if (!isLegalExchangeSelection(selection, hand)) {
              continue;
            }

            double score = scoreStrategicExchange(
              botIndex,
              selection,
              hand,
            );

            // Deterministic small tie-breaker only.
            score += selection.fold<double>(
              0.0,
              (double sum, CardModel card) => sum + card.penalty * 0.5,
            );

            if (score > bestScore) {
              bestScore = score;
              bestSelection = List<CardModel>.from(selection);
            }
          }
        }
      }
    }

    // Final legality gate.
    if (bestSelection.length == 4 &&
        isLegalExchangeSelection(bestSelection, hand)) {
      return bestSelection;
    }

    // Defensive fallback: return the first legal package.
    for (int a = 0; a < hand.length - 3; a++) {
      for (int b = a + 1; b < hand.length - 2; b++) {
        for (int c = b + 1; c < hand.length - 1; c++) {
          for (int d = c + 1; d < hand.length; d++) {
            final List<CardModel> selection = <CardModel>[
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

    return <CardModel>[];
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

      final List<CardModel> originalHand =
          List<CardModel>.from(players[i].cards);
      final List<CardModel> selected = exchangeSelections[i]!;

      // Every selected card must actually belong to the player's original
      // 13-card hand, and the locked ♠Q exchange rule applies to every player.
      if (selected.any((card) => !originalHand.contains(card)) ||
          !isLegalExchangeSelection(selected, originalHand)) {
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
    // Locked exchange mapping:
    // Player 0 → Player 3
    // Player 3 → Player 2
    // Player 2 → Player 1
    // Player 1 → Player 0
    // ========================================================

    for (int giver = 0; giver < 4; giver++) {
      int receiver = playerOnRight(giver);

      players[receiver].cards.addAll(
        passedCards[giver],
      );

      receivedCardsByPlayer[receiver] =
          List<CardModel>.from(passedCards[giver]);
    }

    // The exact exchanged cards are now known information.
    rememberOwnershipFromExchange();
    _verifyCardConservation('exchange complete');

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

    // The next player in the CLOCKWISE play direction starts Hand 1.
    // Any delayed BOT callback from a previous Round is now obsolete.
    _botTurnGeneration++;
    _botTurnScheduled = false;
    _botRecoveryAttempts = 0;
    currentPlayerIndex = playerOnLeft(dealerIndex);

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

    if (handNumber == 1 && currentPlayerIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstHandHint();
      });
    } else if (currentPlayerIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showHintForCurrentSituation());
      });
    }

    // If the starting player is a BOT,
    // let the BOT begin.
    if (currentPlayerIndex != 0) {
      _scheduleBotTurn();
    }
  }

  // ==========================================================
  // GLOBAL CONSECUTIVE LEAD-SUIT RULE
  // ==========================================================

  bool isGlobalLeadSuitBlocked(String suit) {
    if (spadeQueenPlayedThisRound) return false;
    return globalConsecutiveLedSuit == suit &&
        globalConsecutiveLedSuitCount >= 2;
  }

  // Returns the cards that are legal as a lead before applying the global
  // two-consecutive-lead restriction.
  List<CardModel> legalLeadCardsIgnoringGlobalBlock(int playerIndex) {
    final Player player = players[playerIndex];

    if (handNumber == 1) {
      final List<CardModel> safeClubsDiamonds = player.cards.where((card) {
        return (card.suit == 'Clubs' || card.suit == 'Diamonds') &&
            card.penalty == 0 &&
            !card.isSpadeQueen;
      }).toList();

      if (safeClubsDiamonds.isNotEmpty) {
        return safeClubsDiamonds;
      }

      return player.cards
          .where((card) => !card.isSpadeQueen)
          .toList();
    }

    // Hands 2–13: every card is a possible lead, subject only to the
    // global two-consecutive-lead restriction checked separately.
    return List<CardModel>.from(player.cards);
  }

  bool blockedSuitHasOnlyLegalLeadOptions(int playerIndex) {
    final List<CardModel> legal = legalLeadCardsIgnoringGlobalBlock(playerIndex);
    if (legal.isEmpty) return false;

    final String? blockedSuit = globalConsecutiveLedSuit;
    if (blockedSuit == null) return false;

    return legal.every((card) => card.suit == blockedSuit);
  }

  List<CardModel> filterGlobalLeadRule(
    List<CardModel> cards, {
    int? playerIndex,
  }) {
    if (spadeQueenPlayedThisRound ||
        globalConsecutiveLedSuit == null ||
        globalConsecutiveLedSuitCount < 2) {
      return List<CardModel>.from(cards);
    }

    final String blockedSuit = globalConsecutiveLedSuit!;
    final List<CardModel> alternatives =
        cards.where((card) => card.suit != blockedSuit).toList();

    if (alternatives.isNotEmpty) {
      return alternatives;
    }

    if (playerIndex != null &&
        blockedSuitHasOnlyLegalLeadOptions(playerIndex)) {
      return List<CardModel>.from(cards);
    }

    return alternatives;
  }

  void updateGlobalLeadSuit(String suit) {
    if (spadeQueenPlayedThisRound) return;

    if (globalConsecutiveLedSuit == suit) {
      globalConsecutiveLedSuitCount++;
    } else {
      globalConsecutiveLedSuit = suit;
      globalConsecutiveLedSuitCount = 1;
    }
  }

  bool isLegalCard(
    int playerIndex,
    CardModel card,
  ) {
    final Player player = players[playerIndex];

    if (!player.cards.contains(card)) {
      return false;
    }

    // --------------------------------------------------------
    // LEADING A HAND
    // --------------------------------------------------------
    if (currentHand.isEmpty) {
      final List<CardModel> legalLeads =
          legalLeadCardsIgnoringGlobalBlock(playerIndex);

      if (!legalLeads.contains(card)) {
        return false;
      }

      if (isGlobalLeadSuitBlocked(card.suit)) {
        return blockedSuitHasOnlyLegalLeadOptions(playerIndex);
      }

      return true;
    }

    // --------------------------------------------------------
    // FOLLOWING A LED SUIT
    // --------------------------------------------------------
    if (ledSuit != null) {
      // A player follows the led suit whenever they have a card of that
      // suit that is legal in the current Hand.
      //
      // Hand 1 is special: ♠Q is forbidden, so ♠Q does not count as a
      // legal card of the led suit.
      final bool hasLegalLedSuit = player.cards.any((candidate) {
        if (candidate.suit != ledSuit) {
          return false;
        }
        if (handNumber == 1 && candidate.isSpadeQueen) {
          return false;
        }
        return true;
      });

      if (hasLegalLedSuit) {
        // Must follow suit.
        if (card.suit != ledSuit) {
          return false;
        }
        // ♠Q remains forbidden in Hand 1.
        if (handNumber == 1 && card.isSpadeQueen) {
          return false;
        }
        return true;
      }

      // Hand 1: if void in the legally playable led suit, a non-penalty
      // card is mandatory when one exists. ♠Q is never legal in Hand 1.
      if (handNumber == 1) {
        final bool hasNonPenalty = player.cards.any(
          (candidate) =>
              !candidate.isSpadeQueen && candidate.penalty == 0,
        );

        if (hasNonPenalty) {
          return !card.isSpadeQueen && card.penalty == 0;
        }

        return !card.isSpadeQueen;
      }

      // HANDS 2–13 — NEW RULE:
      // If the player is void in the led suit and has ♠Q, ♠Q MUST be
      // thrown. No choice, no lock, and no A♠/K♠ unlock mechanism.
      if (card.isSpadeQueen) {
        return true;
      }

      final bool hasSpadeQueen = player.cards.any(
        (candidate) => candidate.isSpadeQueen,
      );

      if (hasSpadeQueen) {
        return false;
      }

      // No ♠Q: any other card may be discarded.
      return true;
    }

    return false;
  }

  String getIllegalMessage(
    int playerIndex,
    CardModel card,
  ) {
    if (currentHand.isEmpty && handNumber == 1) {
      final List<CardModel> safe =
          legalLeadCardsIgnoringGlobalBlock(playerIndex);
      if (safe.isNotEmpty &&
          safe.every((c) => c.suit == 'Spades')) {
        return '♠Q cannot be played in Hand 1.';
      }
      return 'Hand 1 must begin with a non-penalty ♣ or ♦ when available; otherwise any card except ♠Q may lead.';
    }

    if (currentHand.isEmpty && isGlobalLeadSuitBlocked(card.suit)) {
      return 'That suit is blocked because it was led in the previous two Hands. The restriction is overridden only when it is the leader’s only legal lead suit.';
    }

    if (ledSuit != null) {
      final bool hasLegalLedSuit = players[playerIndex].cards.any((candidate) {
        if (candidate.suit != ledSuit) return false;
        return !(handNumber == 1 && candidate.isSpadeQueen);
      });

      if (hasLegalLedSuit &&
          (card.suit != ledSuit ||
              (handNumber == 1 && card.isSpadeQueen))) {
        return 'You must follow the led suit with a legal card.';
      }

      if (!hasLegalLedSuit && handNumber == 1) {
        final bool hasNonPenalty = players[playerIndex].cards.any(
          (candidate) =>
              !candidate.isSpadeQueen && candidate.penalty == 0,
        );
        if (hasNonPenalty && (card.penalty > 0 || card.isSpadeQueen)) {
          return 'In Hand 1, if you cannot legally follow suit, you must play a non-penalty card when available.';
        }
        if (card.isSpadeQueen) {
          return '♠Q cannot be played in Hand 1.';
        }
      }

    }

    return 'That card cannot be played now.';
  }

  // Proactive teaching hint: whenever the human player becomes the
  // active player and a special rule determines what is legal, explain the
  // situation before they have to make an illegal attempt. Gameplay state is
  // never changed by this helper.
  Future<void> _showHintForCurrentSituation() async {
    if (!mounted ||
        !_beginnerHintsEnabled ||
        currentPlayerIndex != 0 ||
        exchangePhase ||
        roundFinished ||
        gameOver ||
        currentHand.length >= 4) {
      return;
    }

    // Hand 1 opening lead.
    if (handNumber == 1 && currentHand.isEmpty) {
      await _showRuleHintOnce(
        key: 'proactive_first_lead',
        title: 'HAND 1 — WHAT CAN I PLAY?',
        message:
            'You are leading Hand 1. Play a non-penalty ♣ or ♦ when available. '
            'If none is available, any card except ♠Q may lead.',
        scenario: _hintScenario(
          label: 'LEGAL OPENING',
          cards: [
            _hintCard(rank: '7', suit: 'Clubs', highlighted: true),
            _hintCard(rank: 'Q', suit: 'Spades'),
          ],
          arrow: '✓        ✗',
        ),
      );
      return;
    }

    // Must follow the led suit when a legal card of that suit exists.
    if (ledSuit != null &&
        players[0].cards.any((c) => c.suit == ledSuit)) {
      await _showRuleHintOnce(
        key: 'proactive_follow_suit',
        title: 'FOLLOW THE LED SUIT',
        message:
            'The led suit is $ledSuit. You have a card of that suit, so you must play it. '
            'Choose your best legal card from that suit.',
        scenario: _hintScenario(
          label: 'PLAY THE LED SUIT',
          cards: [
            _hintCard(rank: 'K', suit: ledSuit!, highlighted: true),
            _hintCard(rank: 'A', suit: 'Spades'),
          ],
          arrow: '✓        ✗',
        ),
      );
      return;
    }

    // Hand 1: void in led suit means discard a non-penalty card when possible.
    if (ledSuit != null &&
        !players[0].cards.any((c) => c.suit == ledSuit) &&
        handNumber == 1 &&
        players[0].cards.any((c) => c.penalty == 0 && !c.isSpadeQueen)) {
      await _showRuleHintOnce(
        key: 'proactive_hand_one_safe_discard',
        title: 'HAND 1 — CHOOSE A SAFE DISCARD',
        message:
            'You cannot follow the led suit. In Hand 1, play a non-penalty card '
            'when you have one. ♠Q is never legal in Hand 1.',
        scenario: _hintScenario(
          label: 'SAFE DISCARD',
          cards: [
            _hintCard(rank: '5', suit: 'Clubs', highlighted: true),
            _hintCard(rank: '5', suit: 'Hearts'),
          ],
          arrow: '✓        ✗',
        ),
      );
      return;
    }

    // Hands 2–13: if void in led suit and holding ♠Q, ♠Q is mandatory.
    if (ledSuit != null &&
        !players[0].cards.any((c) => c.suit == ledSuit) &&
        handNumber >= 2 &&
        players[0].cards.any((c) => c.isSpadeQueen)) {
      await _showRuleHintOnce(
        key: 'proactive_queen_transfer',
        title: '♠Q MUST BE PLAYED',
        message:
            'You have no card of the led suit and you hold ♠Q. In Hands 2–13, '
            'you must play ♠Q. This transfers the 12-point Queen penalty to the Hand winner.',
        scenario: _hintScenario(
          label: 'MANDATORY PLAY',
          cards: [
            _hintCard(rank: 'Q', suit: 'Spades', highlighted: true),
            _hintCard(rank: 'K', suit: 'Clubs'),
          ],
          arrow: 'PLAY ♠Q ✓',
        ),
      );
      return;
    }

    // Global consecutive-lead restriction: explain it before the player chooses.
    if (currentHand.isEmpty &&
        !spadeQueenPlayedThisRound &&
        globalConsecutiveLedSuit != null &&
        globalConsecutiveLedSuitCount >= 2 &&
        !blockedSuitHasOnlyLegalLeadOptions(0)) {
      await _showRuleHintOnce(
        key: 'proactive_lead_limit',
        title: 'CHANGE THE LEAD SUIT',
        message:
            'The suit ${globalConsecutiveLedSuit!} was led in the previous two Hands. '
            'Choose another legal suit for this Hand unless that blocked suit is your only legal lead.',
        scenario: _hintFlow(
          title: 'CHOOSE A DIFFERENT LEGAL SUIT',
          steps: [
            Column(children: [
              const Text('BLOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              _hintCard(rank: '6', suit: globalConsecutiveLedSuit!),
              const Text('✗', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
            _hintArrow('→'),
            Column(children: [
              const Text('TRY ANOTHER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              _hintCard(rank: '8', suit: 'Clubs', highlighted: true),
              const Text('✓', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
          ],
        ),
      );
    }
  }

  Future<void> _showHintForIllegalPlay(CardModel card) async {
    if (!mounted) return;

    if (handNumber == 1 && currentHand.isEmpty) {
      await _showRuleHintOnce(
        key: 'first_lead',
        title: 'START WITH A SAFE CARD',
        message:
            'In Hand 1, the dealer’s RIGHT-side player starts and play then moves RIGHT around the table. '
            'Lead a non-penalty ♣ or ♦ when one is available. '
            'If none is available, any card except ♠Q may lead.',
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
        scenario: _hintFlow(
          title: 'FOLLOW SUIT BEFORE STRATEGY',
          steps: [
            Column(
              children: [
                const Text('LED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                _hintCard(rank: '8', suit: 'Diamonds', highlighted: true),
              ],
            ),
            _hintArrow('→'),
            Column(
              children: [
                _coloredSuitText('YOU HAVE ♦', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                _hintCard(rank: 'K', suit: 'Diamonds', highlighted: true),
              ],
            ),
            _hintArrow('✓'),
            Column(
              children: [
                const Text('NOT LEGAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                _hintCard(rank: 'A', suit: 'Spades'),
                const Text('✗', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
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
        !card.isSpadeQueen) {
      await _showRuleHintOnce(
        key: 'queen_transfer',
        title: '♠Q TRANSFERS THE BREY PENALTY',
        message:
            'In Hands 2–13, if you have no card of the led suit and you hold ♠Q, '
            'you MUST play ♠Q. This sends the 12-point Queen penalty to the Hand winner. '
            'You cannot choose another penalty card instead.',
        scenario: _hintFlow(
          title: 'VOID IN LED SUIT → ♠Q MUST BE PLAYED',
          steps: [
            Column(
              children: [
                const Text('LED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                _hintCard(rank: '10', suit: 'Diamonds'),
              ],
            ),
            _hintArrow('→'),
            Column(
              children: [
                const Text('YOUR CARDS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Row(children: [
                  _hintCard(rank: 'Q', suit: 'Spades', highlighted: true),
                  _hintCard(rank: 'K', suit: 'Clubs'),
                ]),
              ],
            ),
            _hintArrow('→'),
            Column(
              children: [
                const Text('MUST PLAY ✓', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                _hintCard(rank: 'Q', suit: 'Spades', highlighted: true),
              ],
            ),
          ],
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
        scenario: _hintFlow(
          title: 'LEAD 1 → LEAD 2 → THIRD SAME-SUIT LEAD BLOCKED',
          steps: [
            Column(children: [
              const Text('HAND 1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              _hintCard(rank: '4', suit: card.suit),
              const Text('✓', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
            _hintArrow('→'),
            Column(children: [
              const Text('HAND 2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              _hintCard(rank: '8', suit: card.suit),
              const Text('✓', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
            _hintArrow('→'),
            Column(children: [
              const Text('HAND 3', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              _hintCard(rank: '6', suit: card.suit, highlighted: true),
              const Text('✗ CHANGE SUIT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
            ]),
          ],
        ),
      );
    }
  }

  // ==========================================================
  // HUMAN PLAY
  // ==========================================================

  void playHumanCard(CardModel card) {
    // Never accept another human tap while a Hand is being collected.
    // The fourth card already completed the Hand; allowing a tap during
    // the collection animation could remove a fifth card from the hand.
    if (!gameStarted ||
        exchangePhase ||
        roundFinished ||
        gameOver ||
        dealingPhase ||
        handCollecting ||
        _handResolving ||
        _handTransitionDelay ||
        currentHand.length >= 4) {
      return;
    }

    // Extra safety: the tapped card must still be physically present in
    // the human player's hand before any game-state mutation occurs.
    if (!players[0].cards.contains(card)) {
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
    _verifyCardConservation('HUMAN player 0 Hand $handNumber');

    if (mounted) {
      setState(() {});
    }

    // Start the single BOT state-machine only when the new turn actually
    // belongs to a BOT. No independent delayed callbacks are created here.
    if (currentPlayerIndex != 0 &&
        !exchangePhase &&
        !roundFinished &&
        !gameOver &&
        currentHand.length < 4) {
      _scheduleBotTurn();
    }
  }

  // ==========================================================
  // PLAY CARD
  // ==========================================================

  void playCard(
    int playerIndex,
    CardModel card,
  ) {
    // Absolute state guard: once four cards are on the table, the Hand is
    // complete and no fifth card may ever be removed from any player's hand.
    if (currentHand.length >= 4 || handCollecting || _handResolving || _handTransitionDelay) {
      return;
    }

    // A player may play only on their actual turn. This prevents an old
    // delayed BOT callback (or a repeated UI callback) from removing a
    // second card before the other players have completed the Hand.
    if (playerIndex != currentPlayerIndex) {
      return;
    }

    // Every player may contribute exactly one card to a Hand.
    if (_playersPlayedThisHand.contains(playerIndex)) {
      return;
    }

    if (!players[playerIndex].cards.contains(card)) {
      return;
    }

    // FINAL AUTHORITATIVE LEGALITY GATE. Human and BOT moves use exactly the
    // same rule engine. A strategy function can never remove an illegal card.
    if (!isLegalCard(playerIndex, card)) {
      return;
    }

    final bool wasLeading = currentHand.isEmpty;
    final String? suitBeforePlay = ledSuit;

    // ========================================================
    // FIRST CARD OF HAND = LEAD
    // ========================================================

    if (wasLeading) {
      ledSuit = card.suit;

      // Update the GLOBAL sequence after legality has been checked.
      updateGlobalLeadSuit(card.suit);

      if (lastLedSuitByPlayer[playerIndex] == card.suit) {
        consecutiveLeadCountByPlayer[playerIndex]++;
      } else {
        lastLedSuitByPlayer[playerIndex] = card.suit;
        consecutiveLeadCountByPlayer[playerIndex] = 1;
      }
    }

    // If a player failed to follow the led suit, we learn with certainty
    // that the player was void in that suit.
    if (!wasLeading &&
        suitBeforePlay != null &&
        card.suit != suitBeforePlay) {
      voidSuitsByPlayer[playerIndex].add(suitBeforePlay);
    }

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
    _playersPlayedThisHand.add(playerIndex);


    playedCardsThisRound.add(card);
    playedSuitCounts[card.suit] = (playedSuitCounts[card.suit] ?? 0) + 1;
    _recordObservedBehavior(playerIndex, card, wasLeading: wasLeading);
    removePubliclyPlayedCardFromPrivateKnowledge(card);

    // ========================================================
    // ♠Q PLAYED
    // ========================================================

    if (card.isSpadeQueen) {
      unawaited(_playFeedback(strongVibration: true));
      spadeQueenPlayedThisRound = true;

      // Once ♠Q has been played, the global two-consecutive-lead
      // restriction disappears for the rest of the Round.
      globalConsecutiveLedSuit = null;
      globalConsecutiveLedSuitCount = 0;
    }

    // ========================================================
    // HAND NOT COMPLETE
    // ========================================================

    if (currentHand.length < 4) {
      currentPlayerIndex = nextPlayerForPlay(playerIndex);

      message =
          '${players[currentPlayerIndex].name} to play.';

      _runGameplayStabilityChecks();
      if (currentPlayerIndex == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showHintForCurrentSituation());
        });
      }
      return;
    }

    // ========================================================
    // HAND COMPLETE
    // ========================================================
    // Never calculate a Hand from card count alone. All four distinct
    // players must have played exactly one card.
    if (currentHand.length != 4 || _playersPlayedThisHand.length != 4) {
      return;
    }

    _recordCompletedHandBehavior();
    _runGameplayStabilityChecks();
    unawaited(completeHand());
  }

  // ==========================================================
  // BOT TURN
  // ==========================================================

  // ==========================================================
  // SIMPLE BOT TURN ENGINE
  // ==========================================================
  // Exactly one BOT callback may be waiting at a time.
  // A callback is valid only if its generation still matches the current
  // game state. This prevents a BOT callback from an old Hand from ever
  // playing into a new Hand.
  void _scheduleBotTurn({int delayMs = 720}) {
    if (!mounted ||
        exchangePhase ||
        dealingPhase ||
        roundFinished ||
        gameOver ||
        handCollecting ||
        _handResolving ||
        _handTransitionDelay ||
        currentHand.length >= 4 ||
        currentPlayerIndex == 0 ||
        _botTurnScheduled) {
      return;
    }

    _botTurnScheduled = true;
    final int token = _botTurnGeneration;
    final int expectedHand = handNumber;
    final int expectedPlayer = currentPlayerIndex;

    Future.delayed(Duration(milliseconds: delayMs), () {
      _botTurnScheduled = false;

      // A new Hand/Round may have started while this callback was waiting.
      // The new state is responsible for scheduling its own BOT turn.
      if (!mounted ||
          token != _botTurnGeneration ||
          expectedHand != handNumber ||
          expectedPlayer != currentPlayerIndex) {
        return;
      }

      // Temporary transition states are recoverable. Do not silently abandon
      // a BOT turn; queue a retry against the same state generation.
      if (exchangePhase ||
          dealingPhase ||
          roundFinished ||
          gameOver ||
          handCollecting ||
          _handResolving ||
          _handTransitionDelay ||
          currentHand.length >= 4 ||
          currentPlayerIndex == 0) {
        _recoverBotTurnIfNeeded(token, expectedHand);
        return;
      }

      final int botIndex = currentPlayerIndex;
      final Player bot = players[botIndex];

      if (bot.cards.isEmpty || _playersPlayedThisHand.contains(botIndex)) {
        _recoverBotTurnIfNeeded(token, expectedHand);
        return;
      }

      try {
        // Always regenerate the legal set immediately before playing. This
        // prevents stale strategy state from ever blocking a BOT turn.
        List<CardModel> legalCards = bot.cards
            .where((card) => isLegalCard(botIndex, card))
            .toList();

        if (legalCards.isEmpty) {
          // Re-evaluate once from a fresh hand snapshot before giving up.
          legalCards = List<CardModel>.from(bot.cards)
              .where((card) => isLegalCard(botIndex, card))
              .toList();
        }

        if (legalCards.isEmpty) {
          debugPrint(
            'BREY BOT: no legal card for player $botIndex. Retrying turn.',
          );
          _recoverBotTurnIfNeeded(token, expectedHand);
          return;
        }

        CardModel chosen;
        try {
          chosen = chooseBotCard(botIndex, bot);
        } catch (error, stack) {
          // Strategy failure must never freeze the game. Fall back to the
          // first card from the already verified legal set.
          debugPrint('BREY BOT strategy error: $error');
          debugPrint('$stack');
          chosen = legalCards.first;
        }

        // Final legality fallback. If strategy returned anything stale or
        // illegal, immediately replace it with a verified legal card.
        if (!legalCards.any((c) => cardKey(c) == cardKey(chosen))) {
          chosen = legalCards.first;
        }

        final int beforeHand = currentHand.length;
        final int beforeCards = bot.cards.length;

        playCard(botIndex, chosen);

        final bool played =
            bot.cards.length == beforeCards - 1 &&
            currentHand.length == beforeHand + 1 &&
            _playersPlayedThisHand.contains(botIndex);

        if (!played) {
          // One immediate fresh legal-card attempt. This catches rare races
          // without starting a second BOT engine.
          final List<CardModel> retryLegal = bot.cards
              .where((card) => isLegalCard(botIndex, card))
              .toList();

          if (retryLegal.isNotEmpty &&
              currentPlayerIndex == botIndex &&
              currentHand.length < 4 &&
              !_playersPlayedThisHand.contains(botIndex)) {
            playCard(botIndex, retryLegal.first);
          }

          final bool retryPlayed =
              bot.cards.length == beforeCards - 1 &&
              currentHand.length == beforeHand + 1 &&
              _playersPlayedThisHand.contains(botIndex);

          if (!retryPlayed) {
            debugPrint(
              'BREY BOT: play rejected for player $botIndex. Recovering turn.',
            );
            _recoverBotTurnIfNeeded(token, expectedHand);
            return;
          }
        }

        _botRecoveryAttempts = 0;
        _verifyCardConservation('BOT player $botIndex Hand $handNumber');

        if (mounted) {
          setState(() {});
        }

        // The fourth card belongs to completeHand(). Never schedule another
        // BOT while the Hand is being resolved or collected.
        if (currentHand.length == 4 ||
            _handResolving ||
            _handTransitionDelay ||
            handCollecting) {
          return;
        }

        // Schedule the next BOT only from the state that actually exists
        // after this successful play. This is intentionally based on the
        // authoritative currentPlayerIndex, not the old expectedPlayer.
        // It prevents a valid BOT move from leaving the next BOT turn
        // unscheduled after a rapid state transition.
        if (currentHand.length < 4 &&
            !_handResolving &&
            !_handTransitionDelay &&
            !handCollecting &&
            currentPlayerIndex != 0 &&
            !roundFinished &&
            !gameOver) {
          _scheduleBotTurn(delayMs: 720);
        }
      } catch (error, stack) {
        // A defensive catch is essential: an exception inside a delayed
        // callback otherwise leaves the table waiting forever for a BOT.
        debugPrint('BREY BOT turn error for player $botIndex: $error');
        debugPrint('$stack');
        _recoverBotTurnIfNeeded(token, expectedHand);
      }
    });
  }

  void _recoverBotTurnIfNeeded(int token, int expectedHand) {
    if (!mounted ||
        token != _botTurnGeneration ||
        expectedHand != handNumber ||
        exchangePhase ||
        dealingPhase ||
        roundFinished ||
        gameOver ||
        currentHand.length >= 4 ||
        currentPlayerIndex == 0 ||
        _botTurnScheduled) {
      return;
    }

    // Recovery is deliberately not capped at a small number. A transient
    // animation/state race must never leave a BOT permanently stuck. The
    // normal successful play resets this counter to zero.
    _botRecoveryAttempts++;

    final int retryDelay = _botRecoveryAttempts <= 2 ? 120 : 250;

    // Mark the recovery callback as the pending BOT turn immediately. This
    // closes a small race where another state callback could observe no
    // scheduled BOT and start a second recovery chain.
    _botTurnScheduled = true;

    Future.delayed(Duration(milliseconds: retryDelay), () {
      _botTurnScheduled = false;

      if (!mounted || token != _botTurnGeneration) return;
      if (currentPlayerIndex == 0 ||
          currentHand.length >= 4 ||
          roundFinished ||
          gameOver ||
          handCollecting ||
          _handResolving ||
          _handTransitionDelay) {
        // If this was only a temporary transition, the normal transition
        // completion will schedule the next BOT turn.
        return;
      }

      _scheduleBotTurn(delayMs: 0);
    });
  }

  // Compatibility wrapper for older call sites. It does not create a second
  // engine; it simply asks the same scheduler to perform the next BOT move.
  void playBotTurn() {
    if (_botTurnScheduled) return;
    _scheduleBotTurn();
  }

  String cardKey(CardModel card) => '${card.suit}|${card.rank}';

  void clearPrivateExchangeKnowledge() {
    for (final Map<String, int> knowledge in privateKnownCardOwnerByPlayer.values) {
      knowledge.clear();
    }
  }

  void removePubliclyPlayedCardFromPrivateKnowledge(CardModel card) {
    final String key = cardKey(card);
    for (final Map<String, int> knowledge in privateKnownCardOwnerByPlayer.values) {
      knowledge.remove(key);
    }
  }

  int? knownOwnerForPlayer(int viewerIndex, String key) {
    return privateKnownCardOwnerByPlayer[viewerIndex]?[key];
  }

  void rememberOwnershipFromExchange() {
    clearPrivateExchangeKnowledge();

    // Each player knows:
    // 1. the destination of the four cards THEY passed (to their LEFT);
    // 2. the four cards THEY received (from their LEFT).
    // No player is given another player's exchange information.
    for (int viewer = 0; viewer < 4; viewer++) {
      final int receiver = playerOnRight(viewer);
      final List<CardModel> passed =
          passedCardsByPlayer[viewer] ?? const <CardModel>[];
      for (final CardModel card in passed) {
        privateKnownCardOwnerByPlayer[viewer]![cardKey(card)] = receiver;
      }

      final List<CardModel> received =
          receivedCardsByPlayer[viewer] ?? const <CardModel>[];
      for (final CardModel card in received) {
        privateKnownCardOwnerByPlayer[viewer]![cardKey(card)] = viewer;
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
    String suit, {
    int? viewerIndex,
  }) {
    final int viewer = viewerIndex ?? currentPlayerIndex;
    final Map<String, int> knowledge =
        privateKnownCardOwnerByPlayer[viewer] ?? const <String, int>{};

    return knowledge.entries.any((entry) {
      if (entry.value != opponent) return false;
      final List<String> parts = entry.key.split('|');
      if (parts.length != 2 || parts[0] != suit) return false;
      final CardModel? card = _findCardByKey(entry.key);
      return card != null &&
          card.penalty > 0 &&
          !playedCardsThisRound.any(
            (played) => cardKey(played) == entry.key,
          );
    });
  }

  int countKnownCardsOfSuitForOpponent(
    int opponent,
    String suit, {
    int? viewerIndex,
  }) {
    final int viewer = viewerIndex ?? currentPlayerIndex;
    final Map<String, int> knowledge =
        privateKnownCardOwnerByPlayer[viewer] ?? const <String, int>{};

    return knowledge.entries.where((entry) {
      if (entry.value != opponent) return false;
      final List<String> parts = entry.key.split('|');
      return parts.length == 2 &&
          parts[0] == suit &&
          !playedCardsThisRound.any(
            (played) => cardKey(played) == entry.key,
          );
    }).length;
  }

  CardModel? _findCardByKey(String key) {
    final List<String> parts = key.split('|');
    if (parts.length != 2) return null;
    final List<CardModel> deck = createDeck();
    for (final CardModel card in deck) {
      if (cardKey(card) == key) return card;
    }
    return null;
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
      final bool knownWithOpponent = knownOwnerForPlayer(botIndex, key) != null &&
          knownOwnerForPlayer(botIndex, key) != botIndex;

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
    return null;
  }

  int knownOpponentPenaltyInSuit(
    String suit,
    int exceptPlayer, {
    int? viewerIndex,
  }) {
    final int viewer = viewerIndex ?? currentPlayerIndex;
    final Map<String, int> knowledge =
        privateKnownCardOwnerByPlayer[viewer] ?? const <String, int>{};

    int total = 0;
    for (final entry in knowledge.entries) {
      if (entry.value == exceptPlayer) continue;
      final List<String> parts = entry.key.split('|');
      if (parts.length != 2 || parts[0] != suit) continue;
      final CardModel? card = _findCardByKey(entry.key);
      if (card != null &&
          card.penalty > 0 &&
          !playedCardsThisRound.any(
            (played) => cardKey(played) == entry.key,
          )) {
        total++;
      }
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

  // ==========================================================
  // 200% ATTACKING ENGINE — RULE-SAFE PUBLIC INFORMATION LAYER
  // ==========================================================
  // This layer coordinates penalty hunting, score pressure, card counting,
  // void attacks, ♠Q forcing, trap hands, penalty transfer, multi-Hand
  // planning, self-preservation and end-Round pressure.
  // IMPORTANT: it never reads an opponent's hidden hand directly. It uses
  // only public plays, public voids, and legitimate private exchange
  // knowledge belonging to the BOT itself.

  int attackScoreBand(int score) {
    if (score >= 100) return 4;
    if (score >= 88) return 3;
    if (score >= 60) return 2;
    return 1;
  }

  double attackPressureMultiplier(int score) {
    switch (attackScoreBand(score)) {
      case 4: return 2.40;
      case 3: return 2.00;
      case 2: return 1.25;
      default: return 1.00;
    }
  }

  // Human-target aggression is deliberately stronger at every BOT level.
  // The BOT still evaluates only legal cards; this changes strategic priority,
  // not the BREY rule engine.
  double humanAttackMultiplier() {
    // The human is always the primary target. Even EASY uses the same
    // attack philosophy; difficulty changes execution quality, not target.
    switch (botDifficulty) {
      case BotDifficulty.easy:
        return 2.00;
      case BotDifficulty.medium:
        return 2.40;
      case BotDifficulty.hard:
        return 5.50;
    }
  }

  // ==========================================================
  // PHASE 2 — OPPONENT SCORE ATTACK
  // ==========================================================
  // This layer explicitly selects the highest-pressure opponent from
  // PUBLIC cumulative scores. It does not inspect hidden opponent hands.
  // It only biases an already-legal candidate; legality remains authoritative.
  int opponentScoreAttackTarget(int botIndex) {
    // The human player is the intentional primary target for every BOT.
    // BOT 0 is the human itself, so it falls back to the normal highest-score
    // opponent logic when this helper is used for that player.
    if (botIndex != 0) return 0;

    int target = -1;
    int targetScore = -1;
    for (int opponent = 0; opponent < players.length; opponent++) {
      if (opponent == botIndex) continue;
      final int score = players[opponent].score;
      if (score > targetScore ||
          (score == targetScore && target >= 0 && opponent < target)) {
        target = opponent;
        targetScore = score;
      }
    }
    return target;
  }

  double opponentScoreAttackPriority(int botIndex, int opponent) {
    if (opponent < 0 || opponent >= players.length || opponent == botIndex) {
      return 0.0;
    }
    final int targetScore = players[opponent].score;
    double base;
    switch (attackScoreBand(targetScore)) {
      case 4: base = 180.0; break;
      case 3: base = 120.0; break;
      case 2: base = 55.0; break;
      default: base = 10.0; break;
    }

    // Player 0 is the human. Every BOT intentionally gives the human a
    // stronger strategic weight than the other opponents.
    if (opponent == 0) {
      base *= humanAttackMultiplier();
    }
    return base;
  }

  double scoreOpponentScoreAttack(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    if (candidate.penalty > 0 && winning) return 0.0;

    final int target = opponentScoreAttackTarget(botIndex);
    if (target < 0) return 0.0;

    final double priority = opponentScoreAttackPriority(botIndex, target);
    final bool targetVoid = voidSuitsByPlayer[target].contains(candidate.suit);
    double score = 0.0;

    // A score attack is strongest when the candidate creates a legitimate
    // transfer opportunity against the highest-pressure target.
    if (leading && targetVoid) {
      score += priority;
    } else if (leading) {
      score += priority * 0.30;
    }

    // If the target is already winning a loaded Hand, preserving that winner
    // can transfer visible penalty points without assuming hidden cards.
    if (!leading && determineCurrentWinner() == target && !winning) {
      score += currentHandPenaltyTotal() * (priority >= 120.0 ? 8.0 : 4.0);
    }

    // Public/private-legitimate ownership confidence can strengthen an attack,
    // but never creates knowledge by itself.
    for (final CardModel dangerous in createDeck()) {
      if (dangerous.penalty <= 0 || !isCardStillUnseen(dangerous)) continue;
      final double confidence = cardOwnershipConfidence(
        botIndex,
        dangerous,
        target,
      );
      if (confidence <= 0) continue;
      if (targetVoid || dangerous.suit == candidate.suit) {
        score += confidence * dangerous.penalty *
            (attackScoreBand(players[target].score) >= 3 ? 2.5 : 1.0);
      }
    }

    // Self-preservation overrides aggressive score pressure when the BOT is
    // itself close to the threshold and the move has no concrete target signal.
    final int botScore = players[botIndex].score;
    if (botScore >= 100) {
      score *= 0.45;
    } else if (botScore >= 94) {
      score *= 0.65;
    } else if (botScore >= 88) {
      score *= 0.82;
    }

    if (target == opponentScoreAttackTarget(botIndex) &&
        players[target].score >= 100) {
      score += 35.0;
    }

    // Explicitly reinforce the human as the primary attack target.
    if (target == 0) {
      score *= humanAttackMultiplier();
    }

    return score.clamp(0.0, 650.0).toDouble();
  }

  double penaltyHuntingTargetScore(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    // ==========================================================
    // PHASE 1 — PENALTY HUNTING
    // ==========================================================
    // This layer answers one question only:
    //
    //   "How much can this legal move help place penalty points on
    //    an opponent instead of on the BOT?"
    //
    // It never changes legality and never reads an opponent's hidden hand.
    // Ownership is estimated only from public cards, public voids and the
    // BOT's legitimate private knowledge.
    if (candidate.penalty > 0) return 0.0;

    double score = 0.0;
    final int botScore = players[botIndex].score;
    final int currentWinner = currentHand.isEmpty ? -1 : determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();

    // A dangerous target becomes progressively more valuable as their score
    // approaches / passes the game threshold.
    double targetMultiplier(int targetScore) {
      if (targetScore >= 100) return 4.0;
      if (targetScore >= 94) return 3.5;
      if (targetScore >= 88) return 3.0;
      if (targetScore >= 60) return 1.8;
      return 1.0;
    }

    // Estimate how many penalty points a target could plausibly receive from
    // this suit lead. For a known void, the target can potentially discard a
    // penalty card of ANY suit. For a non-void target, only penalty cards of
    // the led suit can normally win the trick.
    double transferablePenaltyForTarget(int opponent) {
      double transferable = 0.0;
      final bool targetVoid = voidSuitsByPlayer[opponent]
          .contains(candidate.suit);

      if (targetVoid) {
        for (final CardModel dangerous in createDeck()) {
          if (dangerous.penalty <= 0 ||
              !isCardStillUnseen(dangerous) ||
              dangerous.suit == candidate.suit) {
            continue;
          }
          final double confidence = cardOwnershipConfidence(
            botIndex,
            dangerous,
            opponent,
          );
          transferable += confidence * dangerous.penalty;
        }
      } else {
        for (final CardModel dangerous
            in remainingUnseenSuitCards(candidate.suit)) {
          if (dangerous.penalty <= 0 || dangerous.value <= candidate.value) {
            continue;
          }
          final double confidence = cardOwnershipConfidence(
            botIndex,
            dangerous,
            opponent,
          );
          transferable += confidence * dangerous.penalty;
        }
      }

      return transferable;
    }

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int targetScore = players[opponent].score;
      double pressure = targetMultiplier(targetScore);
      if (opponent == 0) {
        pressure *= humanAttackMultiplier();
      }
      final bool targetVoid = voidSuitsByPlayer[opponent]
          .contains(candidate.suit);
      final double transferable = transferablePenaltyForTarget(opponent);

      if (transferable <= 0.0) continue;

      // A known void is the strongest attack because the target is forced to
      // discard something when this suit is led/followed.
      if (leading && targetVoid) {
        score += transferable * 12.0 * pressure;
      } else if (leading) {
        score += transferable * 4.0 * pressure;
      }

      // If this opponent is already winning the current Hand, preserving
      // their winning position can deliberately transfer the visible penalty
      // already sitting on the table to them.
      if (!leading && currentWinner == opponent && !winning) {
        score += visiblePenalty * 10.0 * pressure;
      }

      // If the target is near 100, explicitly reward a move that keeps the
      // loaded Hand pointed toward them.
      if (targetScore >= 88) {
        score += transferable * (targetScore >= 94 ? 8.0 : 4.0);
        if (currentWinner == opponent && visiblePenalty > 0) {
          score += visiblePenalty * (targetScore >= 94 ? 18.0 : 10.0);
        }
      }
    }

    // Self-preservation is part of penalty hunting. A BOT near 100 should
    // not receive a large attack bonus merely because an opponent is also
    // dangerous; the target must provide a genuinely strong transfer signal.
    if (botScore >= 100) {
      score *= 0.55;
    } else if (botScore >= 94) {
      score *= 0.70;
    } else if (botScore >= 88) {
      score *= 0.85;
    }

    // Penalty hunting becomes more urgent in the final four Hands, but only
    // after the legitimate transfer opportunity has been established.
    if (isLateRound()) {
      score *= 1.0 + ((handNumber - 9).clamp(0, 4) * 0.18);
    }

    return score.clamp(-250.0, 500.0).toDouble();
  }

  double scoreVoidAttackAndQueenDump(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    double score = 0;
    final CardModel queen = createDeck().firstWhere(
      (card) => card.isSpadeQueen,
    );

    if (!isCardStillUnseen(queen) || spadeQueenPlayedThisRound) return 0;

    // The new BREY rule makes ♠Q mandatory when a player is void in the led
    // suit. Therefore a suit lead into a known void is a potential Queen trap
    // whenever public information still allows that void player to own ♠Q.
    if (leading) {
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == botIndex) continue;
        if (!voidSuitsByPlayer[opponent].contains(candidate.suit)) continue;

        final double qConfidence = cardOwnershipConfidence(
          botIndex,
          queen,
          opponent,
        );
        if (qConfidence <= 0) continue;

        final double pressure = attackPressureMultiplier(players[opponent].score);
        score += qConfidence * 150.0 * pressure;
        if (players[opponent].score >= 88) score += qConfidence * 90.0;
      }
    }

    // If the BOT itself owns ♠Q, this layer becomes self-preservation rather
    // than an attack. A void opponent can still be attacked, but never by
    // pretending the BOT knows who owns the Queen.
    if (players[botIndex].cards.any((c) => c.isSpadeQueen) && candidate.isSpadeQueen) {
      score -= 220;
    }

    return winning ? score * 0.35 : score;
  }

  double scoreTrapAndSelfPreservation(
    int botIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    double score = 0;
    final double visiblePenalty = currentHandPenaltyTotal();
    final int currentWinner = determineCurrentWinner();
    final int botScore = players[botIndex].score;

    // Trap Hand: when another player is already winning a loaded Hand, losing
    // can be deliberately valuable because that player collects the penalty.
    if (!winning && currentWinner >= 0 && currentWinner != botIndex) {
      final int targetScore = players[currentWinner].score;
      if (visiblePenalty >= 6) {
        score += 35;
        if (targetScore >= 88) score += 30;
        if (targetScore >= 94) score += 45;
      }
    }

    // Preserve control when the current Hand is clean and the candidate is a
    // major high card; do not sacrifice a future winning structure for style.
    if (winning && visiblePenalty == 0 && candidate.penalty == 0 && candidate.value >= 12) {
      score -= 25;
    }

    // Self-preservation gets stronger as the BOT itself approaches 100.
    if (botScore >= 94) {
      if (winning && visiblePenalty > 0) score -= visiblePenalty * 14;
      if (!winning && candidate.penalty > 0) score += candidate.penalty * 8;
    } else if (botScore >= 88) {
      if (winning && visiblePenalty >= 6) score -= visiblePenalty * 8;
    }

    return score;
  }

  double scoreEndRoundAttack(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    if (handNumber < 10) return 0;

    double score = 0;
    final int handsLeft = max(0, 14 - handNumber);
    final int botScore = players[botIndex].score;

    // Hands 10–13: penalty transfer becomes progressively more urgent.
    final double endPressure = 1.0 + ((4 - min(handsLeft, 4)) * 0.45);
    if (candidate.penalty > 0 && !winning) {
      score += candidate.penalty * 10.0 * endPressure;
    }

    if (leading && candidate.penalty == 0 && candidate.value <= 8) {
      score += 8.0 * endPressure;
    }

    // A BOT already near 100 should attack only when the target is also under
    // severe pressure; otherwise immediate self-preservation wins.
    if (botScore >= 94) {
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == botIndex) continue;
        if (players[opponent].score >= 88) {
          score += candidate.penalty * 5.0 * endPressure;
        }
      }
      if (winning && currentHandPenaltyTotal() > 0) {
        score -= currentHandPenaltyTotal() * 8.0 * endPressure;
      }
    }

    return score;
  }

  // ==========================================================
  // PHASE 4 — VOID ATTACK
  // ==========================================================
  // Public-information-only void attack.
  //
  // A void is confirmed only when a player has publicly failed to follow
  // the led suit. This layer never inspects hidden opponent hands.
  //
  // The score is deliberately a decision bonus only. Legal-card generation
  // remains authoritative and this layer cannot make an illegal card legal.

  double scorePhase4VoidAttack(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    double score = 0.0;

    // A lead is the main way to exploit a publicly confirmed void.
    if (leading) {
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == botIndex) continue;

        if (!voidSuitsByPlayer[opponent].contains(candidate.suit)) {
          continue;
        }

        final int opponentScore = players[opponent].score;
        double pressure = attackPressureMultiplier(opponentScore);
        if (opponent == 0) {
          pressure *= humanAttackMultiplier();
        }

        // A known void gives the opponent an opportunity to discard a card
        // from another suit. Count only penalty cards that are still unseen
        // and for which the BOT has legitimate ownership confidence.
        double transferValue = 0.0;
        for (final CardModel dangerous in createDeck()) {
          if (dangerous.penalty <= 0 || !isCardStillUnseen(dangerous)) {
            continue;
          }

          final double confidence = cardOwnershipConfidence(
            botIndex,
            dangerous,
            opponent,
          );

          transferValue += confidence * dangerous.penalty;
        }

        if (transferValue <= 0.0) continue;

        // Stronger pressure for opponents already in the danger bands.
        score += transferValue * (12.0 + pressure * 5.0);

        // A void that is also a confirmed Queen-transfer opportunity is
        // particularly valuable under the current BREY ♠Q rule.
        final CardModel queen = createDeck().firstWhere(
          (card) => card.isSpadeQueen,
        );
        if (!spadeQueenPlayedThisRound && isCardStillUnseen(queen)) {
          final double qConfidence = cardOwnershipConfidence(
            botIndex,
            queen,
            opponent,
          );
          if (qConfidence > 0.0) {
            score += qConfidence * 75.0 * pressure;
          }
        }
      }
    }

    // Following a suit: if the current winner is a known void player in the
    // led suit, preserving that winner can keep penalty transfer alive.
    if (!leading && !winning && currentHand.isNotEmpty) {
      final int currentWinner = determineCurrentWinner();

      if (currentWinner >= 0 && currentWinner != botIndex) {
        final String ledSuit = currentHand.first.card.suit;

        if (voidSuitsByPlayer[currentWinner].contains(ledSuit)) {
          final double pressure =
              attackPressureMultiplier(players[currentWinner].score);
          score += currentHandPenaltyTotal() * 4.0 * pressure;
        }
      }
    }

    // Self-preservation: a high-score BOT should not chase a void attack
    // when doing so creates significant immediate penalty exposure.
    final int botScore = players[botIndex].score;
    if (botScore >= 100) {
      score *= 0.45;
    } else if (botScore >= 94) {
      score *= 0.65;
    } else if (botScore >= 88) {
      score *= 0.82;
    }

    // Never let this strategic layer overwhelm the legality engine.
    // Human-target opportunities receive the stronger difficulty-scaled weight
    // through the pressure multiplier above.
    return score.clamp(-150.0, 700.0).toDouble();
  }

  // ==========================================================
  // PHASE 5 — ♠Q ATTACK
  // ==========================================================
  // Predict ♠Q location only from legitimate information: public plays,
  // confirmed voids and the BOT's own private exchange knowledge.
  // Never inspect or assume a hidden opponent hand.

  double scorePhase5SpadeQueenAttack(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    if (spadeQueenPlayedThisRound) return 0.0;

    final CardModel queen = createDeck().firstWhere(
      (card) => card.isSpadeQueen,
    );

    if (!isCardStillUnseen(queen)) return 0.0;

    double score = 0.0;

    // A lead into a confirmed void is the primary Queen-attack mechanism.
    // Under the locked BREY rule, a void player holding ♠Q must throw it.
    if (leading) {
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == botIndex) continue;
        if (!voidSuitsByPlayer[opponent].contains(candidate.suit)) continue;

        final double confidence = cardOwnershipConfidence(
          botIndex,
          queen,
          opponent,
        );
        if (confidence <= 0.0) continue;

        double pressure =
            attackPressureMultiplier(players[opponent].score);
        if (opponent == 0) {
          pressure *= humanAttackMultiplier();
        }

        score += confidence * 210.0 * pressure;

        if (players[opponent].score >= 88) {
          score += confidence * 90.0;
        }

        if (players[opponent].score >= 100) {
          score += confidence * 60.0;
        }
      }
    }

    // If the BOT itself owns ♠Q, avoid exposing it unless legality requires it.
    if (players[botIndex].cards.any((c) => c.isSpadeQueen)) {
      if (candidate.isSpadeQueen) {
        score -= 260.0;
      }

      final int ownSpades =
          players[botIndex].cards.where((c) => c.suit == 'Spades').length;
      if (ownSpades <= 2 && leading && candidate.suit == 'Spades') {
        score += 18.0;
      }
    }

    // If private knowledge legitimately identifies the Queen's owner, attack
    // that player's confirmed void directly.
    final int? knownQueenOwner =
        knownOwnerForPlayer(botIndex, cardKey(queen));
    if (knownQueenOwner != null &&
        knownQueenOwner != botIndex &&
        knownQueenOwner >= 0 &&
        knownQueenOwner < players.length &&
        leading &&
        voidSuitsByPlayer[knownQueenOwner].contains(candidate.suit)) {
      score += 260.0 *
          attackPressureMultiplier(players[knownQueenOwner].score);
    }

    // Queen attack is less important when this card already wins the Hand.
    if (winning) score *= 0.45;

    final int botScore = players[botIndex].score;
    if (botScore >= 100) {
      score *= 0.45;
    } else if (botScore >= 94) {
      score *= 0.65;
    } else if (botScore >= 88) {
      score *= 0.82;
    }

    return score.clamp(-250.0, 550.0).toDouble();
  }

  // ==========================================================
  // HUMAN TARGET — 200% DIRECT ATTACK
  // ==========================================================
  // Every BOT deliberately treats the human player (index 0) as the primary
  // attack target. This does NOT reveal hidden human cards: it uses only
  // public score state, public void information, the current Hand, and the
  // BOT's legitimate card-ownership knowledge. The legal-card engine remains
  // authoritative, so aggression can only select from legal moves.
  double scoreHumanAttack200Percent(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    if (botIndex == 0) return 0.0;

    const int humanIndex = 0;
    final int humanScore = players[humanIndex].score;
    final bool humanVoid =
        voidSuitsByPlayer[humanIndex].contains(candidate.suit);
    final int currentWinner = determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();

    // The attack intensifies as the human approaches the game threshold.
    double pressure;
    if (humanScore >= 100) {
      pressure = 4.0;
    } else if (humanScore >= 94) {
      pressure = 3.5;
    } else if (humanScore >= 88) {
      pressure = 3.0;
    } else if (humanScore >= 60) {
      pressure = 2.0;
    } else {
      pressure = 1.5;
    }

    double score = 0.0;

    // ZERO-POINT PREVENTION: whenever the current Hand already contains
    // penalty cards and the human is currently winning, strongly prefer a
    // legal move that makes the human lose the Hand or keeps the Hand pointed
    // at the human when a penalty can be transferred to them. This is still
    // rule-safe: it never invents a hidden human card or chooses an illegal
    // move.
    if (!leading && currentWinner == humanIndex && visiblePenalty > 0) {
      score += 900.0 * pressure;
      if (candidate.penalty > 0 && !winning) {
        score += candidate.penalty * 140.0 * pressure;
      }
    }

    // Primary attack: lead a suit the human has publicly been shown to be
    // void in, creating a legal penalty-discard opportunity.
    if (leading && humanVoid) {
      score += 260.0 * pressure;
      score += knownOpponentPenaltyInSuit(candidate.suit, humanIndex) *
          24.0 * pressure;
    } else if (leading) {
      score += knownOpponentPenaltyInSuit(candidate.suit, humanIndex) *
          10.0 * pressure;
    }

    // If the human is already winning a loaded Hand, keep that Hand pointed
    // at them whenever the BOT can legally lose the current trick.
    if (!leading && currentWinner == humanIndex && !winning) {
      score += visiblePenalty * 55.0 * pressure;
      if (candidate.penalty > 0) {
        score += candidate.penalty * 75.0 * pressure;
      }
    }

    // A known human-owned penalty card in the candidate's suit is an especially
    // strong public-information attack signal. Never assume an unknown card.
    final int knownPenalty =
        knownOpponentPenaltyInSuit(candidate.suit, humanIndex);
    if (knownPenalty > 0) {
      score += knownPenalty * 18.0 * pressure;
    }

    // With a human near 100, prioritize moves that make them collect visible
    // penalties rather than merely improving a neutral position.
    if (humanScore >= 88) {
      if (currentWinner == humanIndex && visiblePenalty > 0 && !winning) {
        score += visiblePenalty * 45.0 * pressure;
      }
      if (candidate.penalty > 0 && currentWinner == humanIndex && !winning) {
        score += candidate.penalty * 90.0 * pressure;
      }
    }

    // Never reward the BOT for taking the penalty itself merely because it is
    // aggressive. The existing winner/self-preservation layers remain in force.
    if (winning && candidate.penalty > 0) {
      score -= candidate.penalty * 35.0;
    }

    return score.clamp(0.0, 1800.0).toDouble();
  }

  // HARD MODE — MAXIMUM HUMAN PRESSURE
  //
  // Hard mode does not cheat and does not bypass BREY legality. It simply
  // gives the existing strategic engines a much stronger human-targeting
  // priority. This keeps card counting, void attacks, penalty transfer,
  // Queen attacks, self-preservation and look-ahead intact while making the
  // Hard bots extremely difficult to beat.
  double scoreHardHumanLock(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    if (botDifficulty != BotDifficulty.hard || botIndex == 0) return 0.0;

    const int humanIndex = 0;
    final int humanScore = players[humanIndex].score;
    final int currentWinner = determineCurrentWinner();
    final double handPenalty = currentHandPenaltyTotal();
    final bool humanVoid =
        voidSuitsByPlayer[humanIndex].contains(candidate.suit);

    double score = 0.0;

    // Hard mode strongly prefers legal plays that attack a publicly known
    // human void. This is especially valuable when the suit carries penalty.
    if (leading && humanVoid) {
      score += 1800.0;
      score += knownOpponentPenaltyInSuit(candidate.suit, humanIndex) * 180.0;
    }

    // If the human is currently winning a loaded Hand, make every legal
    // non-winning opportunity to keep the Hand on the human extremely valuable.
    if (!leading && currentWinner == humanIndex && handPenalty > 0 && !winning) {
      score += 2600.0 + handPenalty * 220.0;
      if (candidate.penalty > 0) {
        score += candidate.penalty * 260.0;
      }
    }

    // When the human has a high cumulative score, concentrate even more on
    // transferring visible penalties to them rather than taking them ourselves.
    if (humanScore >= 60) {
      score += handPenalty * 45.0;
      if (candidate.penalty > 0 && currentWinner == humanIndex && !winning) {
        score += candidate.penalty * 180.0;
      }
    }

    // Never force a BOT to take a loaded Hand merely for aggression. The
    // existing strategic/self-preservation layers remain authoritative.
    if (winning && candidate.penalty > 0) {
      score -= candidate.penalty * 110.0;
    }

    return score.clamp(-1200.0, 6500.0).toDouble();
  }

  double scoreAttack200Percent(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    double score = 0;

    // HARD MODE human-lock layer is added first so the existing strategy
    // engines remain active underneath it rather than being replaced.
    score += scoreHardHumanLock(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // PRIMARY TARGET — human player (index 0).
    // This is intentionally stronger than generic opponent pressure.
    score += scoreHumanAttack200Percent(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // PHASE 2 — explicit opponent score attack.
    score += scoreOpponentScoreAttack(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // 1–2. Penalty hunting + existing score pressure.
    score += penaltyHuntingTargetScore(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // 3. Card counting: prefer attacks that are actually supported by the
    // remaining-card state rather than by a raw face-value assumption.
    score += scoreAdvancedCardCounting(
      botIndex,
      candidate,
      leading: leading,
    ) * 0.75;
    score += scoreExactCardCounting(
      botIndex,
      candidate,
      winning: winning,
      leading: leading,
    ) * 0.70;

    // PHASE 3 — stronger counted-card decision layer.
    // This remains subordinate to legality and the existing attack systems.
    score += scorePhase3CardCounting(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // PHASE 4 — public-information void attack.
    score += scorePhase4VoidAttack(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // PHASE 5 — ♠Q attack using legitimate information only.
    score += scorePhase5SpadeQueenAttack(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // 4–5. Void attack and the new mandatory-♠Q dump rule.
    score += scoreVoidAttackAndQueenDump(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // 6. Trap Hands + 9. Self-preservation.
    score += scoreTrapAndSelfPreservation(
      botIndex,
      candidate,
      winning: winning,
    );

    // PHASE 7 — deliberate penalty transfer attack.
    score += scorePhase7PenaltyTransferAttack(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // Existing penalty-transfer intelligence remains active as a second layer.
    score += scorePenaltyTransferTarget(botIndex, candidate) * 1.25;

    // 8. Multi-Hand planning / future position.
    score += scoreMultiHandPlanning(
      botIndex,
      candidate,
      winning: winning,
    ) * 1.15;
    score += evaluatePostPlayPosition(botIndex, candidate) * 0.55;

    // 10. Hands 10–13.
    score += scoreEndRoundAttack(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // PHASE 12 — adaptive opponent behavior.
    score += scorePhase12AdaptiveBehavior(
      botIndex,
      candidate,
      leading: leading,
      winning: winning,
    );

    // Final score-band pressure: the closer an opponent is to 100, the more
    // strongly a legal transfer is preferred. This never changes legality.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      final int targetScore = players[opponent].score;
      final double multiplier = attackPressureMultiplier(targetScore);
      if (targetScore >= 88 && candidate.penalty > 0 && !winning) {
        score += candidate.penalty * 4.0 * multiplier;
      }
    }

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

      final Map<String, int> knowledge =
          privateKnownCardOwnerByPlayer[botIndex] ?? const <String, int>{};
      for (final entry in knowledge.entries) {
        if (entry.value != opponent) continue;
        final CardModel? known = _findCardByKey(entry.key);
        if (known != null && known.suit == card.suit && known.penalty > 0 &&
            !playedCardsThisRound.any((p) => cardKey(p) == entry.key)) {
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

    // 200% attacking coordinator. This is deliberately added after the
    // specialist layers so it arbitrates their signals rather than replacing
    // the existing BREY strategy.
    score += scoreAttack200Percent(
      botIndex,
      card,
      leading: leading,
      winning: forcedWinner,
    );

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

// ==========================================================
// BOT DIRECTION CONTRACT
// ==========================================================
// Exchange strategy evaluates the player on the RIGHT because every BOT
// passes its selected four cards to the LEFT and receives four from the RIGHT.
// Gameplay strategy evaluates turn order using nextPlayerForPlay(), which
// moves LEFT. Therefore when the human is the dealer the first Hand is:
// BOT 1 -> BOT 2 -> BOT 3 -> YOU.
// This direction is part of the BREY rules, not a visual/UI convention.

CardModel chooseBotCard(
    int playerIndex,
    Player bot,
  ) {
    // ==========================================================
    // RULE #1 — RULES FIRST, DECISION SECOND
    // ==========================================================
    // No intelligence function is allowed to decide from the raw hand.
    // First build the authoritative legal-card set using the complete BREY
    // rule engine. This protects follow-suit, Hand 1 restrictions, ♠Q locks,
    // global lead restrictions, and all other legality rules.
    final List<CardModel> legalCards = bot.cards
        .where((card) => isLegalCard(playerIndex, card))
        .toList();

    if (legalCards.isEmpty) {
      // Invalid state: return a card only so the caller can log/reject it.
      // playCard() has the final authoritative legality gate.
      return bot.cards.first;
    }

    if (currentHand.isEmpty) {
      return chooseBotLeadCard(playerIndex, bot);
    }

    final String suit = ledSuit!;
    final List<CardModel> sameSuit = legalCards
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

  // ==========================================================
  // ♠Q PREDICTION — PUBLIC INFORMATION ONLY
  // ==========================================================
  //
  // Estimate where an unseen ♠Q could still be without assuming hidden
  // opponent cards. Known ownership is used only from the bot's private
  // knowledge map; played cards and public void information further reduce
  // the set of plausible owners.
  double scoreSpadeQueenPrediction(
    int playerIndex,
    CardModel candidate,
  ) {
    double score = 0;
    final CardModel queen = createDeck().firstWhere(
      (card) => card.isSpadeQueen,
    );

    // If the Queen is already public, there is no remaining Queen threat.
    if (!isCardStillUnseen(queen)) {
      return 0;
    }

    final Player bot = players[playerIndex];
    final bool botOwnsQueen = bot.cards.any(
      (card) => card.isSpadeQueen,
    );

    // A bot holding the Queen has direct responsibility for its future risk.
    if (botOwnsQueen) {
      if (candidate.isSpadeQueen) {
        score += isLateRound() ? 70 : 34;
      } else if (isLateRound()) {
        score += 12;
      }
    }

    final Map<String, int> knowledge =
        privateKnownCardOwnerByPlayer[playerIndex] ??
            const <String, int>{};
    final int? knownOwner = knowledge[cardKey(queen)];

    // If this bot has legitimate private knowledge of the Queen's owner,
    // increase the value of decisions that exploit that known state.
    if (knownOwner != null && knownOwner != playerIndex) {
      final int ownerScore = players[knownOwner].score;
      if (ownerScore >= 94) {
        score += candidate.suit == 'Spades' ? 24 : 8;
      } else if (ownerScore >= 88) {
        score += candidate.suit == 'Spades' ? 14 : 4;
      }
    }

    // Public void information tells us which opponents can no longer hold
    // the Queen in an unseen state. This is probability reduction, not
    // omniscient ownership inference.
    int possibleOpponents = 0;
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == playerIndex) continue;
      if (knownOwner != null && knownOwner != opponent) continue;
      if (voidSuitsByPlayer[opponent].contains('Spades')) continue;
      possibleOpponents++;
    }

    if (knownOwner == null && possibleOpponents == 1) {
      // The Queen's possible public location has narrowed substantially.
      if (candidate.suit == 'Spades') {
        score += 18;
      }
    } else if (knownOwner == null && possibleOpponents == 2) {
      if (candidate.suit == 'Spades') {
        score += 8;
      }
    }

    return score;
  }

  double evaluateQueenRisk(int playerIndex, CardModel card) {
    if (!card.isSpadeQueen) return 0;

    double score = scoreSpadeQueenPrediction(playerIndex, card);
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
  // DELIBERATE PENALTY CAPTURE — TAKE A SMALL LOSS TO AVOID A
  // MORE DANGEROUS FUTURE PENALTY
  // ==========================================================

  double scoreDeliberatePenaltyCapture(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
  }) {
    if (!winning || candidate.penalty <= 0) return 0;

    final Player bot = players[playerIndex];
    double score = 0;

    final List<CardModel> remaining = bot.cards
        .where((c) => cardKey(c) != cardKey(candidate))
        .toList();

    final int remainingPenalty = remaining.fold<int>(
      0,
      (sum, card) => sum + card.penalty,
    );
    final bool stillHasQueen = remaining.any((c) => c.isSpadeQueen);
    final bool stillHasClubKing = remaining.any(
      (c) => c.suit == 'Clubs' && c.rank == 'K',
    );
    final bool stillHasDiamondJack = remaining.any(
      (c) => c.suit == 'Diamonds' && c.rank == 'J',
    );

    // The central idea: when we can take a small penalty now, doing so can
    // be better than carrying it into a later Hand where we may be forced to
    // take a larger penalty. This is especially useful when the bot still
    // carries a major penalty card.
    if (candidate.penalty <= 4 && stillHasQueen) {
      score += 72;
    } else if (candidate.penalty <= 6 && stillHasQueen) {
      score += 46;
    }

    if (candidate.penalty <= 4 && stillHasClubKing) {
      score += 34;
    }

    if (candidate.penalty <= 4 && stillHasDiamondJack) {
      score += 18;
    }

    // A small controlled loss is more attractive when the rest of the hand
    // still contains several penalty points that could become difficult to
    // unload later.
    if (candidate.penalty <= 4 && remainingPenalty >= 12) {
      score += 28;
    } else if (candidate.penalty <= 6 && remainingPenalty >= 8) {
      score += 14;
    }

    // Never let this rule encourage taking ♠Q itself. Queen handling remains
    // a separate, much stronger strategic decision.
    if (candidate.isSpadeQueen) {
      score -= 160;
    }

    // A light current Hand makes a small deliberate penalty easier to accept.
    final double handPenalty = currentHandPenaltyTotal();
    if (handPenalty <= 2 && candidate.penalty <= 4) {
      score += 18;
    } else if (handPenalty >= 8) {
      score -= 22;
    }

    // In the final Hands, controlled disposal of a small penalty becomes
    // increasingly valuable because there are fewer chances to escape it.
    if (isLateRound() && candidate.penalty <= 6) {
      score += 26;
    }

    // If a dangerous opponent is currently winning, do not overuse this rule:
    // it can be better to let that opponent collect the Hand than to take it
    // ourselves. Existing opponent-targeting scores handle that situation.
    final int currentWinner = determineCurrentWinner();
    if (currentWinner >= 0 && currentWinner != playerIndex) {
      final int targetScore = players[currentWinner].score;
      if (targetScore >= 94) {
        score -= candidate.penalty * 7;
      } else if (targetScore >= 88) {
        score -= candidate.penalty * 4;
      }
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
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int firstOpponentAfterBot =
          nextPlayerForPlay(botIndex);
      final bool opponentIsNext =
          opponent == nextPlayerForPlay(currentPlayerIndex);
      final bool opponentIsLast = currentHand.length == 2 &&
          opponent == firstOpponentAfterBot;

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
  // ADVANCED VOID ATTACK
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
    for (final entry in privateKnownCardOwnerByPlayer[playerIndex]!.entries) {
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

  // ==========================================================
  // PHASE 3 — CARD COUNTING
  // ==========================================================
  // Converts public card history into a stronger, rule-safe estimate of
  // which cards can still threaten or safely support the BOT's move.
  // IMPORTANT: this layer never reads an opponent's hidden hand. It uses
  // only cards already played, the BOT's own hand, public voids, and the
  // BOT's legitimate private exchange knowledge.
  double scorePhase3CardCounting(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    double score = 0.0;

    final List<CardModel> unseenSuit = remainingUnseenSuitCards(candidate.suit);
    final List<CardModel> higherUnseen = unseenSuit
        .where((card) => card.value > candidate.value)
        .toList();

    // ----------------------------------------------------------
    // 1. EXACT PUBLIC REMAINDER
    // ----------------------------------------------------------
    // Every publicly played card removes one possibility from the deck.
    // A candidate with no higher unseen card is a counted top card.
    if (higherUnseen.isEmpty) {
      score += winning ? 42.0 : 24.0;
    } else {
      score -= higherUnseen.length * (winning ? 3.5 : 1.5);
    }

    // ----------------------------------------------------------
    // 2. HIGH-CARD THREAT COUNT
    // ----------------------------------------------------------
    int forcedOpponentThreats = 0;
    int knownOpponentThreats = 0;

    for (final CardModel higher in higherUnseen) {
      final List<int> owners = possibleOwnersForCard(botIndex, higher);

      // A unique opponent owner means the threat is counted with certainty.
      if (owners.length == 1 && owners.first != botIndex) {
        forcedOpponentThreats++;
      }

      final int? knownOwner = knownOwnerForPlayer(
        botIndex,
        cardKey(higher),
      );
      if (knownOwner != null && knownOwner != botIndex) {
        knownOpponentThreats++;
      }
    }

    if (winning) {
      score -= forcedOpponentThreats * 16.0;
      score -= knownOpponentThreats * 6.0;
    } else {
      // When the BOT wants to lose, a counted higher opponent card is useful
      // because it makes the loss more predictable rather than accidental.
      score += forcedOpponentThreats * 9.0;
      score += knownOpponentThreats * 3.0;
    }

    // ----------------------------------------------------------
    // 3. COUNTED SAFETY BY SUIT EXHAUSTION
    // ----------------------------------------------------------
    final int remainingInSuit = unseenSuit.length;
    final int playedInSuit = playedSuitCounts[candidate.suit] ?? 0;

    if (remainingInSuit <= 2) {
      score += 28.0;
    } else if (remainingInSuit <= 4) {
      score += 16.0;
    } else if (remainingInSuit <= 6) {
      score += 7.0;
    }

    // A suit with many publicly exposed cards is more predictable than a
    // fresh suit. This bonus is deliberately capped to avoid overpowering
    // the core BREY strategic layers.
    score += min(playedInSuit, 8) * 1.5;

    // ----------------------------------------------------------
    // 4. COUNTED PENALTY LOCATION
    // ----------------------------------------------------------
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int opponentScore = players[opponent].score;
      final double pressure = opponentScore >= 100
          ? 3.0
          : opponentScore >= 94
              ? 2.5
              : opponentScore >= 88
                  ? 2.0
                  : opponentScore >= 60
                      ? 1.25
                      : 1.0;

      for (final CardModel penaltyCard in unseenSuit) {
        if (penaltyCard.penalty <= 0) continue;

        final double confidence = cardOwnershipConfidence(
          botIndex,
          penaltyCard,
          opponent,
        );
        if (confidence <= 0.0) continue;

        // Counted penalty ownership is useful when deciding whether this
        // suit should be attacked against a dangerous opponent.
        score += confidence * penaltyCard.penalty * pressure *
            (leading ? 2.2 : 0.8);
      }
    }

    // ----------------------------------------------------------
    // 5. VOID-AWARE COUNTING
    // ----------------------------------------------------------
    if (leading) {
      int confirmedVoids = 0;
      for (int opponent = 0; opponent < 4; opponent++) {
        if (opponent == botIndex) continue;
        if (voidSuitsByPlayer[opponent].contains(candidate.suit)) {
          confirmedVoids++;
        }
      }

      // A confirmed void means one more owner is removed from consideration
      // for every unseen card of this suit, making the count substantially
      // more informative.
      score += confirmedVoids * 13.0;
    }

    // ----------------------------------------------------------
    // 6. LEAD CONTROL VS. FUTURE VOID CREATION
    // ----------------------------------------------------------
    final int botSuitCount = players[botIndex]
        .cards
        .where((card) => card.suit == candidate.suit)
        .length;

    if (leading && botSuitCount == 1 && candidate.penalty == 0) {
      score += 18.0;
    }

    // Preserve a counted low exit when it is likely to remain useful.
    if (!leading && candidate.value <= 7 && candidate.penalty == 0 &&
        remainingInSuit >= 5) {
      score += 8.0;
    }

    // ----------------------------------------------------------
    // 7. SELF-RISK CAP
    // ----------------------------------------------------------
    // Counting should improve decisions, not override BREY self-preservation.
    final int botScore = players[botIndex].score;
    if (botScore >= 100) {
      score *= 0.70;
    } else if (botScore >= 94) {
      score *= 0.82;
    } else if (botScore >= 88) {
      score *= 0.92;
    }

    return score.clamp(-180.0, 180.0).toDouble();
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
  // PHASE 11 — DETERMINISTIC LOOK-AHEAD / COMBINATION SEARCH
  // ==========================================================
  //
  // This layer does not inspect hidden opponent hands.  It builds a
  // public-information possibility set from unseen cards, known ownership,
  // known voids and the cards already on the table.  It then evaluates every
  // deterministic branch in a bounded search tree.  The branch set is kept
  // deliberately small enough for a real-time card game while still forcing
  // the BOT to compare future outcomes instead of judging a card in isolation.

  List<CardModel> _phase11PossibleResponses(
    int botIndex,
    int playerIndex,
    List<PlayedCard> simulated,
  ) {
    final Set<String> seen = <String>{
      ...playedCardsThisRound.map(cardKey),
      ...simulated.map((played) => cardKey(played.card)),
      ...players[botIndex].cards.map(cardKey),
    };

    final Map<String, int> known =
        privateKnownCardOwnerByPlayer[botIndex] ?? const <String, int>{};

    final List<CardModel> possible = createDeck().where((card) {
      final String key = cardKey(card);
      if (seen.contains(key)) return false;
      final int? owner = known[key];
      if (owner != null && owner != playerIndex) return false;
      if (handNumber == 1 && card.isSpadeQueen) return false;
      return true;
    }).toList();

    // Deterministic branch compression: retain the strategically distinct
    // extremes and penalty cards rather than sampling randomly.
    final List<CardModel> selected = <CardModel>[];
    void add(CardModel? card) {
      if (card == null) return;
      if (selected.any((c) => cardKey(c) == cardKey(card))) return;
      selected.add(card);
    }

    final List<CardModel> suitCards = ledSuit == null
        ? <CardModel>[]
        : possible.where((c) => c.suit == ledSuit).toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    add(suitCards.isNotEmpty ? suitCards.first : null);
    add(suitCards.isNotEmpty ? suitCards.last : null);

    final List<CardModel> penaltyCards = possible
        .where((c) => c.penalty > 0)
        .toList()
      ..sort((a, b) {
        final int p = b.penalty.compareTo(a.penalty);
        if (p != 0) return p;
        return b.value.compareTo(a.value);
      });
    add(penaltyCards.isNotEmpty ? penaltyCards.first : null);

    // ♠Q is always strategically distinct when it is still unseen.
    for (final CardModel card in possible) {
      if (card.isSpadeQueen) {
        add(card);
        break;
      }
    }

    // Keep one additional low card as a controlled safe-discard branch.
    final List<CardModel> low = possible.where((c) => c.penalty == 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    add(low.isNotEmpty ? low.first : null);

    return selected.take(5).toList();
  }

  double _phase11TerminalValue(
    int botIndex,
    List<PlayedCard> simulated,
  ) {
    if (simulated.isEmpty || ledSuit == null) return 0;

    final String suit = ledSuit!;
    PlayedCard winner = simulated.first;
    for (final PlayedCard played in simulated) {
      if (played.card.suit == suit &&
          (winner.card.suit != suit || played.card.value > winner.card.value)) {
        winner = played;
      }
    }

    final int penalty = simulated.fold<int>(
      0,
      (sum, played) => sum + played.card.penalty,
    );

    double value = 0;
    if (winner.playerIndex == botIndex) {
      value += penalty == 0 ? 70 : -penalty * 5.0;
      value += 28; // control of the next lead
    } else {
      final int targetScore = players[winner.playerIndex].score;
      if (targetScore >= 94) {
        value += penalty * 9.0;
      } else if (targetScore >= 88) {
        value += penalty * 5.0;
      } else {
        value -= penalty * 1.5;
      }
    }

    return value;
  }

  double _phase11Search(
    int botIndex,
    List<PlayedCard> simulated,
    int nextPlayer,
    int depth,
  ) {
    if (simulated.length >= 4 || depth <= 0) {
      return _phase11TerminalValue(botIndex, simulated);
    }

    final List<CardModel> responses = _phase11PossibleResponses(
      botIndex,
      nextPlayer,
      simulated,
    );
    if (responses.isEmpty) {
      return _phase11TerminalValue(botIndex, simulated);
    }

    double bestForBot = -double.infinity;
    double worstForBot = double.infinity;

    for (final CardModel response in responses) {
      final List<PlayedCard> next = List<PlayedCard>.from(simulated)
        ..add(PlayedCard(playerIndex: nextPlayer, card: response));

      final int nextPlayerIndex = (nextPlayer + 1) % 4;
      final double branch = _phase11Search(
        botIndex,
        next,
        nextPlayerIndex,
        depth - 1,
      );
      if (branch > bestForBot) bestForBot = branch;
      if (branch < worstForBot) worstForBot = branch;
    }

    // Opponents are not assumed to cooperate.  Blend the best public
    // possibility with the worst credible possibility so the BOT does not
    // select a move that only looks good under one convenient continuation.
    return bestForBot * 0.35 + worstForBot * 0.65;
  }

  double scorePhase11DeterministicLookAhead(
    int botIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    if (currentHand.length >= 4) return 0;

    final List<PlayedCard> simulated = List<PlayedCard>.from(currentHand)
      ..add(PlayedCard(playerIndex: botIndex, card: candidate));

    // At most three unseen turns remain after the BOT's current play.
    final int depth = min(3, 4 - simulated.length);
    if (depth <= 0) {
      return _phase11TerminalValue(botIndex, simulated);
    }

    final int nextPlayer = (botIndex + 1) % 4;
    double score = _phase11Search(
      botIndex,
      simulated,
      nextPlayer,
      depth,
    );

    // If the candidate is already winning, future control has additional
    // value. If it is losing, reward preserving the ability to unload safely.
    if (winning) score += 8;
    if (!winning && candidate.penalty == 0) score += 5;
    if (leading && candidate.penalty > 0) score -= candidate.penalty * 2.0;

    return score.clamp(-180.0, 180.0).toDouble();
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

    // Multi-Hand look-ahead: evaluate the quality of the BOT's remaining
    // hand after this candidate is played. This is deterministic and is
    // deliberately based only on the BOT's own visible cards plus public
    // information. The engine prefers moves that leave several useful
    // low-card exits, short suits, and penalty-free future options.
    final List<CardModel> remainingAfterPlay = bot.cards
        .where((c) => c != candidate)
        .toList();
    final int safeRemaining =
        remainingAfterPlay.where((c) => c.penalty == 0).length;
    final int lowRemaining =
        remainingAfterPlay.where((c) => c.penalty == 0 && c.value <= 7).length;

    if (remainingHands >= 3) {
      score += safeRemaining * 1.5;
      score += lowRemaining * 2.5;
    }

    // Preserve suit flexibility for future leads/follows.
    final Set<String> futureSuits =
        remainingAfterPlay.map((c) => c.suit).toSet();
    if (remainingHands >= 4 && futureSuits.length >= 3) {
      score += 6;
    }
    if (remainingHands >= 5 && futureSuits.length == 4) {
      score += 5;
    }

    // Avoid leaving a single very dangerous penalty card when there is no
    // known transfer route.
    final int futurePenaltyCards =
        remainingAfterPlay.where((c) => c.penalty > 0).length;
    if (futurePenaltyCards == 1 && remainingHands >= 3) {
      final CardModel lastPenalty =
          remainingAfterPlay.firstWhere((c) => c.penalty > 0);
      score -= lastPenalty.penalty * 2.0;
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
  void _recordObservedBehavior(int playerIndex, CardModel card, {
    required bool wasLeading,
  }) {
    if (playerIndex < 0 || playerIndex >= 4) return;

    observedHandsPlayed[playerIndex]++;
    if (wasLeading) {
      final Map<String, int> counts = observedLeadSuitCount[playerIndex];
      counts[card.suit] = (counts[card.suit] ?? 0) + 1;
    }

    if (card.penalty > 0 && !wasLeading) {
      observedPenaltyCardsPlayed[playerIndex]++;
      final Map<String, int> counts =
          observedPenaltyDiscardBySuit[playerIndex];
      counts[card.suit] = (counts[card.suit] ?? 0) + 1;
    }
  }

  void _recordCompletedHandBehavior() {
    if (currentHand.length != 4) return;
    final int winner = determineCurrentWinner();
    if (winner >= 0 && winner < 4) {
      observedHandsWon[winner]++;
    }
  }

  double scorePhase12AdaptiveBehavior(
    int botIndex,
    CardModel candidate, {
    required bool winning,
    bool leading = false,
  }) {
    double score = 0;

    // With little evidence, keep this layer deliberately weak.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final int played = observedHandsPlayed[opponent];
      if (played < 3) continue;

      if (leading) {
        final int suitLeads =
            observedLeadSuitCount[opponent][candidate.suit] ?? 0;
        final double leadRate = suitLeads / played;

        // A repeatedly preferred lead becomes predictable. Attack it only
        // when the public history gives enough evidence.
        if (leadRate >= 0.55) {
          score += 5.0 + (leadRate - 0.55) * 18.0;
        }

        // If the opponent has repeatedly discarded penalties in this suit,
        // leading it can create a useful pressure point when that behavior
        // is also supported by current public void information.
        final int penaltyDiscards =
            observedPenaltyDiscardBySuit[opponent][candidate.suit] ?? 0;
        if (penaltyDiscards >= 2 &&
            voidSuitsByPlayer[opponent].contains(candidate.suit)) {
          score += min(28.0, penaltyDiscards * 7.0);
        }
      } else if (candidate.penalty > 0) {
        final int dumps =
            observedPenaltyDiscardBySuit[opponent][candidate.suit] ?? 0;
        if (dumps >= 2) {
          score += min(18.0, dumps * 4.0);
        }
      }
    }

    // Do not let behavioral history override an already strong winning move.
    if (winning) score *= 0.65;
    return score.clamp(-80.0, 100.0).toDouble();
  }

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
  // the Round: penalty concentration, 88+ protection, suit exhaustion,
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
    // 1. Protect players in the 88+ protection from ♠Q.
    // --------------------------------------------------------
    if (currentWinner >= 0 && currentWinner != playerIndex) {
      final int target = players[currentWinner].score;
      if (target >= 88) {
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
      final int? knownOwner = knownOwnerForPlayer(botIndex, cardKey(card));
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

    final int? knownOwner = knownOwnerForPlayer(botIndex, cardKey(card));
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
    List<CardModel> legalCards = bot.cards
        .where((card) => isLegalCard(playerIndex, card))
        .toList();

    // Explicitly apply the GLOBAL lead rule to bot planning as well.
    // This prevents the strategy engine from selecting a blocked suit.
    if (currentHand.isEmpty) {
      legalCards = filterGlobalLeadRule(legalCards, playerIndex: playerIndex);
    }

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
      return legalCards.first;
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
      score += scorePhase11DeterministicLookAhead(
        playerIndex, candidate, winning: false, leading: true,
      );
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
      // Actively search for the highest penalty still held by an opponent.
      // If the bot is near elimination, the same search falls through to
      // the next-largest transferable penalty instead.
      score += scorePenaltyTargetingLead(playerIndex, candidate) * 2.0;
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
      score += scoreSpadeQueenPrediction(playerIndex, candidate);

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

    return best;
  }


  // ==========================================================
  // PENALTY TARGETING — MAKE OPPONENTS TAKE DANGEROUS CARDS
  // ==========================================================
  //
  // The bot actively looks for the largest penalty card that is still
  // available.  If an opponent owns that card and the bot has a lower card
  // of the same suit, leading that lower card can give the penalty card an
  // opportunity to win the Hand.
  //
  // Priority:
  //   ♠Q = 12
  //   ♣K = 6
  //   ♦J = 4
  //   ♥ cards = 1 each
  //
  // If the bot itself is in the danger zone (94+), it does not deliberately
  // target a penalty card that could come back to the bot.  It searches the
  // next-largest safe penalty target instead.
  double scorePenaltyTargetingLead(
    int playerIndex,
    CardModel candidate,
  ) {
    // Privacy-safe penalty hunting. The old implementation inspected every
    // opponent's hidden hand directly; this version uses only public voids,
    // public play history and the BOT's legitimate private knowledge.
    if (candidate.penalty > 0) return 0;

    double score = 0;
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == playerIndex) continue;

      final int targetScore = players[opponent].score;
      final double pressure = attackPressureMultiplier(targetScore);
      final bool targetVoid = voidSuitsByPlayer[opponent]
          .contains(candidate.suit);

      int transferValue = 0;
      for (final CardModel card in remainingUnseenSuitCards(candidate.suit)) {
        if (card.penalty <= 0) continue;
        final double confidence = cardOwnershipConfidence(
          playerIndex,
          card,
          opponent,
        );
        transferValue += (confidence * card.penalty).round();
      }

      if (targetVoid) {
        score += transferValue * 8.0 * pressure;
        if (targetScore >= 88) score += transferValue * 4.0 * pressure;
      }

      // A lead that makes a dangerous opponent a plausible winner is useful,
      // but it is intentionally probabilistic when ownership is unknown.
      if (targetScore >= 88) {
        score += transferValue * 2.0 * pressure;
      }
    }

    return score;
  }

  // ==========================================================
  // ADAPTIVE LEAD SCORING
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

    // Prefer short suits because they can create future voids.
    if (suitCards.length == 1) {
      score += 34;
    } else if (suitCards.length == 2) {
      score += 16;
    } else if (suitCards.length >= 5) {
      score -= 10;
    }

    // Prefer safe low leads.
    if (candidate.value <= 5 && candidate.penalty == 0) {
      score += 22;
    }
    if (candidate.value >= 12) {
      score -= 24;
    }

    // Use only PUBLIC void information here. We must not inspect hidden
    // opponent cards when making an adaptive lead decision.
    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == playerIndex) continue;
      if (!voidSuitsByPlayer[opponent].contains(candidate.suit)) continue;

      final int targetScore = players[opponent].score;
      if (targetScore >= 94) {
        score += 32;
      } else if (targetScore >= 88) {
        score += 20;
      } else if (targetScore >= 60) {
        score += 12;
      } else {
        score += 8;
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

    // ♠Q TRANSFER:
    // If K♠ or A♠ is already on the table and ♠Q is legally playable, the bot
    // may choose it as a strategic penalty transfer. The authoritative
    // legality engine remains the final gate under the current no-lock rules.
    if (ledSuit == 'Spades' && currentWinningValue >= 13) {
      final List<CardModel> queens =
          sameSuit.where((card) => card.isSpadeQueen).toList();
      if (queens.isNotEmpty && isLegalCard(playerIndex, queens.first)) {
        return queens.first;
      }
    }

    final List<CardModel> losing = sameSuit
        .where((c) => c.value < currentWinningValue)
        .toList();

    // ======================================================
    // HARD PENALTY-TRANSFER PRIORITY
    // ======================================================
    // If an opponent is currently winning the led suit, and this BOT can
    // legally follow with a penalty card that is guaranteed to lose, unload
    // the penalty now. This is the concrete BREY transfer behavior: for
    // example, K♦ on the table + J♦ in the BOT hand => play J♦ (4 points),
    // rather than unnecessarily throwing a zero-point Diamond.
    //
    // This is still rules-first: every candidate below has already passed
    // isLegalCard(), and a penalty that would WIN the Hand is not forced.
    final List<CardModel> safePenaltyTransfers = losing
        .where((c) => c.penalty > 0 && isLegalCard(playerIndex, c))
        .toList();

    if (safePenaltyTransfers.isNotEmpty) {
      CardModel bestPenalty = safePenaltyTransfers.first;
      double bestPenaltyScore = -double.infinity;
      for (final CardModel candidate in safePenaltyTransfers) {
        double penaltyScore = scorePenaltyHuntMemory(playerIndex, candidate, losing: true);
        penaltyScore += candidate.penalty * 8.0;
        penaltyScore += candidate.value * 0.25;
        if (penaltyScore > bestPenaltyScore ||
            (penaltyScore == bestPenaltyScore && isBetterBotTieBreak(candidate, bestPenalty))) {
          bestPenaltyScore = penaltyScore;
          bestPenalty = candidate;
        }
      }
      return bestPenalty;
    }

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
        score += scorePhase11DeterministicLookAhead(
          playerIndex, candidate, winning: false,
        );
        score += scoreRemainingCardMemory(
          playerIndex,
          candidate,
          winning: false,
        );
        score += evaluateQueenRisk(playerIndex, candidate);
        score += scoreSpadeQueenPrediction(playerIndex, candidate);
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

      return best;
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
      // The bot is already forced to win this Hand.
      // Penalty-unloading bonuses belong primarily to safe-discard situations;
      // they must not make a high penalty winner attractive merely because it
      // is a dangerous card. The winning-card branch will explicitly minimize
      // unnecessary penalty/control cost below.
      score += scorePenaltyTiming(
        playerIndex,
        candidate,
        winning: true,
      ) * 0.20;
      score += scoreDeliberatePenaltyCapture(
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
      score += scorePhase11DeterministicLookAhead(
        playerIndex, candidate, winning: true,
      );
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
      //
      // This is intentionally a stronger preference than the generic
      // penalty-unloading bonus: once every legal card wins, a larger card
      // must have a concrete strategic reason to overcome this cost.
      score -= candidate.value * 9;
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

    return best;
  }

  // ==========================================================
  // BOT DISCARD / BREY TRANSFER — USE THE BEST TARGET
  // ==========================================================

  // ==========================================================
  // BREY PENALTY HUNTING — EXCHANGE MEMORY + PUBLIC CARD COUNTING
  // ==========================================================
  bool _wasReceivedFromRightPlayer(int botIndex, CardModel card) {
    // Exchange moves LEFT (anti-clockwise), so a BOT receives from its RIGHT neighbour.
    final int rightPlayer = playerOnRight(botIndex);
    final String key = cardKey(card);
    final List<CardModel> received =
        receivedCardsByPlayer[botIndex] ?? const <CardModel>[];
    final List<CardModel> rightPassed =
        passedCardsByPlayer[rightPlayer] ?? const <CardModel>[];
    return received.any((c) => cardKey(c) == key) &&
        rightPassed.any((c) => cardKey(c) == key);
  }

  int _publicUnplayedHigherCardsInSuit(CardModel card) {
    int count = 0;
    for (final CardModel unseen in remainingUnseenSuitCards(card.suit)) {
      if (unseen.value > card.value) count++;
    }
    return count;
  }

  double scorePenaltyHuntMemory(int botIndex, CardModel candidate, {required bool losing}) {
    if (candidate.penalty <= 0 || !losing) return 0;
    double score = 0;
    final int currentWinner = determineCurrentWinner();
    final int rightPlayer = playerOnRight(botIndex);
    if (_wasReceivedFromRightPlayer(botIndex, candidate)) {
      score += 180 + candidate.penalty * 55;
      if (currentWinner == rightPlayer) score += 320 + candidate.penalty * 90;
    }
    if (currentWinner >= 0 && currentWinner != botIndex) {
      final int targetScore = players[currentWinner].score;
      score += candidate.penalty * (targetScore >= 94 ? 110 : targetScore >= 88 ? 72 : 30);
      if (currentWinner == rightPlayer) score += 90 + candidate.penalty * 35;
    }
    score += _publicUnplayedHigherCardsInSuit(candidate) * 12.0;
    score += candidate.penalty * 24;
    score += candidate.value * 1.5;
    return score;
  }

  CardModel chooseSmartDiscardCard(
    int playerIndex,
    Player bot,
  ) {
    final List<CardModel> legalCards = bot.cards
        .where((card) => isLegalCard(playerIndex, card))
        .toList();

    if (legalCards.isEmpty) return bot.cards.first;

    // When void in the led suit, dump the largest legal penalty whenever
    // possible. ♠Q remains governed by the authoritative legality engine.
    final List<CardModel> legalPenaltyCards = legalCards
        .where((c) => c.penalty > 0)
        .toList();
    if (legalPenaltyCards.isNotEmpty) {
      legalPenaltyCards.sort((a, b) {
        final int penaltyCompare = b.penalty.compareTo(a.penalty);
        if (penaltyCompare != 0) return penaltyCompare;
        return b.value.compareTo(a.value);
      });
      return legalPenaltyCards.first;
    }

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
      score += scorePenaltyHuntMemory(playerIndex, candidate, losing: true);
      score += scoreSpadeQueenPrediction(playerIndex, candidate);

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

    return best;
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

      final Map<String, int> knowledge =
          privateKnownCardOwnerByPlayer[botIndex] ?? const <String, int>{};
      for (final entry in knowledge.entries) {
        if (entry.value != i) continue;
        final CardModel? card = _findCardByKey(entry.key);
        if (card != null && card.suit == suit && card.penalty > 0 &&
            !playedCardsThisRound.any((p) => cardKey(p) == entry.key)) {
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
      if (knownDangerousCardWithOpponent(
        currentWinner,
        ledSuit ?? candidate.suit,
        viewerIndex: botIndex,
      )) {
        score += 14;
      }
    }

    return score;
  }

  // ==========================================================
  // PHASE 7 — PENALTY TRANSFER ATTACK
  // ==========================================================
  // Convert a loaded Hand into a deliberate transfer opportunity.
  // This layer uses only public Hand state, public scores and the BOT's
  // currently legal candidate. It never inspects hidden opponent cards.
  // Legal-card generation remains authoritative.
  double scorePhase7PenaltyTransferAttack(
    int botIndex,
    CardModel candidate, {
    required bool leading,
    required bool winning,
  }) {
    double score = 0.0;
    if (candidate.penalty <= 0) return 0.0;

    final int currentWinner = determineCurrentWinner();
    final double visiblePenalty = currentHandPenaltyTotal();
    final int botScore = players[botIndex].score;

    // Once an opponent is already winning, a legal penalty that still loses
    // the Hand is a direct transfer rather than a penalty taken by the BOT.
    if (!leading && currentWinner >= 0 && currentWinner != botIndex && !winning) {
      final int targetScore = players[currentWinner].score;
      double pressure = 1.0;
      if (targetScore >= 100) {
        pressure = 2.20;
      } else if (targetScore >= 94) {
        pressure = 1.85;
      } else if (targetScore >= 88) {
        pressure = 1.50;
      }

      score += candidate.penalty * 18.0 * pressure;
      score += visiblePenalty * 4.0 * pressure;

      // The closer the BOT is to the danger threshold, the more valuable it
      // is to transfer the penalty away instead of becoming the winner.
      if (botScore >= 94) {
        score += candidate.penalty * 14.0;
      } else if (botScore >= 88) {
        score += candidate.penalty * 8.0;
      }
    }

    // If the BOT is leading, avoid deliberately creating a penalty-winning
    // Hand unless the Hand is already loaded enough to justify it.
    if (leading && winning) {
      if (visiblePenalty >= 6) {
        score -= candidate.penalty * (botScore >= 94 ? 22.0 : 10.0);
      } else {
        score -= candidate.penalty * 7.0;
      }
    }

    // A clean Hand is a poor place to expose a penalty card. Preserve it for
    // a later transfer opportunity when no public target exists.
    if (visiblePenalty == 0 && currentWinner < 0) {
      score -= candidate.penalty * 4.0;
    }

    return score.clamp(-220.0, 420.0).toDouble();
  }

  // Deterministic final selector.
  // The BOT must never replace a calculated best move with a random card.
  // Every caller has already evaluated every legal candidate through the
  // strategic engine; this method exists only for compatibility with the
  // existing difficulty-routing calls.
  //
  // Difficulty may change how much intelligence is enabled elsewhere, but
  // it must NEVER introduce random card selection.
  // ==========================================================
  // DETERMINISTIC MASTER DECISION POLICY
  // ==========================================================
  // ALL intelligence phases use the same deterministic policy. Every legal
  // candidate is scored before this method is reached. Difficulty NEVER
  // injects randomness into card selection. This compatibility method simply
  // returns the already-evaluated best candidate.
  CardModel maybeUseDifficultyCard(
    CardModel best,
    List<CardModel> candidates,
  ) {
    return best;
  }

  // ==========================================================
  // STRATEGIC CARD OWNERSHIP ESTIMATE
  // ==========================================================

  bool botLikelyHasCard(int playerIndex, CardModel target) {
    if (players[playerIndex].cards.contains(target)) {
      return true;
    }

    final int viewer = currentPlayerIndex;
    if (playerIndex == viewer) {
      return players[playerIndex].cards.contains(target);
    }
    final int? owner = knownOwnerForPlayer(viewer, cardKey(target));
    return owner == playerIndex &&
        !playedCardsThisRound.any(
          (played) => cardKey(played) == cardKey(target),
        );
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
    // Resolve a completed Hand exactly once. This is critical because bot
    // timers and the human turn can both schedule work near the fourth card.
    if (!mounted || roundFinished || gameOver || _handResolving || currentHand.length != 4) {
      return;
    }

    _handResolving = true;
    _botTurnGeneration++;

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
    //
    // Hands 1–12 may end the game immediately after Hand scoring.
    // Hand 13 is different: its complete Round-end processing must
    // happen before the final 100+ check.
    final bool reachedGameEndAfterHand =
        handNumber < 13 && players[winnerIndex].score >= 100;

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

    // Save a complete snapshot before the table cards are cleared.
    // This is later shown in the Round Summary below the score list.
    completedRoundHands.add(List<PlayedCard>.from(currentHand));
    completedRoundWinners.add(winnerIndex);
    completedRoundPenalties.add(handPenalty);

    // Do not place the completed-Hand summary in the upper message card.
    // The four played cards and winner animation already communicate the
    // result on the table.
    message = 'Hand $handNumber complete.';

    // ========================================================
    // HAND PROCESSING COMPLETE — SIMPLE, STABLE TRANSITION
    // ========================================================
    // Do NOT run a long collection animation here. The scoring, winner
    // calculation, penalty accounting, and round-history snapshot are all
    // already complete above. Keeping the table animation out of the state
    // transition prevents delayed animation callbacks from racing with the
    // next Hand and accidentally consuming/clearing cards.
    //
    // The completed Hand is removed from the table immediately, then the
    // game remains locked for exactly 1 second. Only after that second may
    // the next Hand begin and a card be played.
    // IMPORTANT: keep all four cards on the BREY table for the complete-Hand
    // display interval.  Previously currentHand.clear() happened in the same
    // state transition that scored the Hand. Flutter could therefore rebuild
    // the table before the fourth/last card was ever painted.
    //
    // Scoring is already finished at this point, but the physical table must
    // remain untouched until the one-second transition lock expires. No BOT
    // can play during this period because _handTransitionDelay is true.
    if (mounted) {
      setState(() {
        handCollecting = false;
        collectingWinnerIndex = winnerIndex;
        _handTransitionDelay = true;
      });
    } else {
      handCollecting = false;
      collectingWinnerIndex = winnerIndex;
      _handTransitionDelay = true;
    }

    // Keep the completed four-card table visible for one full second before
    // clearing it. This is the ONLY place where a completed Hand is cleared.
    // Keeping the cards here also guarantees the last player's card gets a
    // real Flutter frame to render.
    _handResolving = false;

    if (!mounted) return;

    // ========================================================
    // GAME OVER / ROUND COMPLETION
    // ========================================================

    if (handNumber == 13) {
      // Hand 13 must ALWAYS complete Round-end processing before
      // checking whether anyone has reached 100+.
      Future.delayed(
        const Duration(seconds: 1),
        () async {
          if (!mounted) return;
          setState(() {
            currentHand.clear();
            _playersPlayedThisHand.clear();
            handCollecting = false;
            collectingWinnerIndex = null;
          });
          unawaited(_playFeedback(strongVibration: true));
          await finishRound();
        },
      );
      return;
    }

    if (reachedGameEndAfterHand) {
      players[winnerIndex].eliminated = true;
      gameOver = true;
      roundFinished = true;
      unawaited(_playFeedback(strongVibration: true));
      _recordCompletedGame(reached100Index: winnerIndex);
      Future.delayed(
        const Duration(seconds: 1),
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

    // ========================================================
    // NEXT HAND
    // ========================================================

    if (!_autoNextHand) {
      // Leave the result visible until the player explicitly continues.
      return;
    }

    // EXACTLY 1 SECOND SAFETY WINDOW
    // All calculations and state changes above are finished before this
    // delay begins. No player is allowed to play during this window.
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted || roundFinished || gameOver) return;

    // The completed Hand has now been visible for the full transition
    // interval. Clear the four table cards only immediately before creating
    // the next Hand, never at the moment the fourth card is played.
    setState(() {
      currentHand.clear();
      _playersPlayedThisHand.clear();
      collectingWinnerIndex = null;
      handCollecting = false;
      _handTransitionDelay = false;
    });

    startNextHand(winnerIndex);
  }

  // ==========================================================
  // START NEXT HAND
  // ==========================================================

  void startNextHand(int winnerIndex) {
    if (!mounted || roundFinished || gameOver) {
      return;
    }

    // Start a fresh BOT-turn generation for this Hand.
    _botTurnGeneration++;
    _botTurnScheduled = false;
    _botRecoveryAttempts = 0;

    setState(() {
      _handTransitionDelay = false;
      handCollecting = false;
      collectingWinnerIndex = null;
      _handResolving = false;
      currentHand.clear();
      _playersPlayedThisHand.clear();
      ledSuit = null;
      handNumber++;

      // Winner leads next Hand.
      currentPlayerIndex = winnerIndex;
      message =
          '${players[currentPlayerIndex].name} leads Hand $handNumber.';
    });

    if (currentPlayerIndex != 0) {
      _scheduleBotTurn();
    }
  }

  // ==========================================================
  // FINISH ROUND
  // ==========================================================


  Future<void> finishRound() async {
    // ========================================================
    // ALL 35 PENALTY POINTS IN ONE ROUND = 0
    // ========================================================
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
    // ========================================================
    for (final Player player in players) {
      if (player.handsWon == 0) {
        player.score = max(0, player.score - 5);
      }
      player.score = max(0, player.score);
    }

    // ========================================================
    // FINAL GAME-END CHECK
    // ========================================================
    //
    // This is the FIRST point at which Hand 13 is allowed to end
    // the game. The final winner is determined only after all Round-
    // end score adjustments above have been applied.
    final List<int> reached100 = <int>[];
    for (int i = 0; i < players.length; i++) {
      if (players[i].score >= 100) {
        reached100.add(i);
      }
    }

    roundFinished = true;

    if (reached100.isNotEmpty) {
      gameOver = true;

      for (final int index in reached100) {
        players[index].eliminated = true;
      }

      final int reached100Index = reached100.first;
      _recordCompletedGame(reached100Index: reached100Index);

      if (mounted) {
        setState(() {});
      }

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await showChampionTrophy(reached100Index);
      return;
    }

    // No game end: this is only a Round summary, NOT the final
    // BREY championship result.
    message = 'Round $roundNumber complete. Lowest score: '
        '${players.map((p) => p.score).reduce(min)} points.';

    // Round-specific runtime state is reset here. Cumulative scores,
    // next dealer/♠Q collector, and game-level settings are preserved.
    // Keep completedRoundHands until START NEXT ROUND so the summary remains
    // visible to the player.
    currentHand.clear();
    ledSuit = null;
    handCollecting = false;
    collectingWinnerIndex = null;
    _handResolving = false;
    resetVoidMemory();
    resetLeadTracking();
    spadeQueenPlayedThisRound = false;
    globalConsecutiveLedSuit = null;
    globalConsecutiveLedSuitCount = 0;
    for (int i = 0; i < 4; i++) {
}
    roundPenaltyByPlayer.updateAll((key, value) => 0);
    passedCardsByPlayer.clear();
    receivedCardsByPlayer.clear();
    clearPrivateExchangeKnowledge();

    if (mounted) {
      setState(() {});
    }
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
    _firstHandHintShown = false;

    // ♠Q collector becomes dealer.
    dealerIndex = spadeQueenCollector!;

    // Reset Hands won for the new Round.
    for (Player player in players) {
      player.handsWon = 0;
    }

    // The previous Round Summary is no longer needed once the next Round
    // starts.
    completedRoundHands.clear();
    completedRoundWinners.clear();
    completedRoundPenalties.clear();

    // Leave the Round summary immediately and let dealRound() publish
    // the dealing screen after the dealer confirms SHUFFLE & DEAL.
    roundFinished = false;
    dealingPhase = false;
    exchangePhase = false;
    currentHand.clear();
    ledSuit = null;
    handCollecting = false;
    collectingWinnerIndex = null;
    _handResolving = false;

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
    VoidCallback? onExchangeSelectionChanged,
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
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool compactPhone = screenWidth < 360;
    final double cardWidth = compactPhone ? 64 : 70;
    final double cardHeight = compactPhone ? 94 : 102;

    return RepaintBoundary(
      child: GestureDetector(
      onTap: () {
        if (exchangeMode) {
          toggleExchangeCard(card);
          onExchangeSelectionChanged?.call();
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
            width: cardWidth,
            height: cardHeight,
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
                title: const Text('START A NEW GAME'),
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

  // ==========================================================
  // ELEGANT EXCHANGE CARD PICKER
  // ==========================================================

  Future<void> showExchangeCardPicker() async {
    if (!exchangePhase || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final int selectedCount = selectedExchangeCards.length;
            final bool readyToPass = selectedCount == 4;



            void passCards() {
              if (selectedExchangeCards.length != 4) {
                message = 'Please select exactly 4 cards.';
                dialogSetState(() {});
                setState(() {});
                return;
              }

              if (!isLegalExchangeSelection(
                selectedExchangeCards,
                players[0].cards,
              )) {
                message =
                    '♠Q rule: if you have another Spade, select at least one more Spade with ♠Q.';
                dialogSetState(() {});
                setState(() {});
                return;
              }

              Navigator.of(dialogContext).pop();
              confirmHumanExchange();
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 22,
              ),
              backgroundColor: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double availableWidth = constraints.maxWidth;
                  final int columns = availableWidth >= 560
                      ? 7
                      : availableWidth >= 430
                          ? 6
                          : 4;

                  return Container(
                    constraints: const BoxConstraints(
                      maxWidth: 680,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfffaf8f2),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xffc8a45d),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.86,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          // Elegant header.
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xff182a27),
                                  border: Border.all(
                                    color: const Color(0xffc8a45d),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.style_rounded,
                                  color: Color(0xffe0bd70),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'CHOOSE 4 CARDS',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.1,
                                        color: Color(0xff182a27),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Select the cards you want to pass LEFT.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xff6c6a63),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: readyToPass
                                  ? const Color(0xffe7f3ea)
                                  : const Color(0xfff1eee6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: readyToPass
                                    ? const Color(0xff79a982)
                                    : const Color(0xffd6d0c3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  readyToPass
                                      ? Icons.check_circle_rounded
                                      : Icons.touch_app_rounded,
                                  size: 17,
                                  color: readyToPass
                                      ? const Color(0xff39734a)
                                      : const Color(0xff7d6a3d),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    readyToPass
                                        ? 'Ready — 4 cards selected.'
                                        : 'Tap cards to select them. You need exactly 4.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: readyToPass
                                          ? const Color(0xff315d3c)
                                          : const Color(0xff625a4c),
                                    ),
                                  ),
                                ),
                                Text(
                                  '$selectedCount / 4',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: readyToPass
                                        ? const Color(0xff39734a)
                                        : const Color(0xff182a27),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // The entire dialog is now one scrollable surface.
                          // This prevents the fixed header from sitting over the
                          // first card rows after scrolling, so every card remains
                          // fully visible AND tappable.
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.only(
                              top: 12,
                              bottom: 12,
                              left: 4,
                              right: 4,
                            ),
                            itemCount: sortedHumanCards.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisExtent: 124,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 0,
                            ),
                            itemBuilder: (context, index) {
                              final CardModel card = sortedHumanCards[index];
                              return Center(
                                child: buildCard(
                                  card,
                                  exchangeMode: true,
                                  onExchangeSelectionChanged: () {
                                    dialogSetState(() {});
                                  },
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 8),

                          Row(
                            children: [
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: Color(0xff8a6b32),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  'Your 4 selected cards will be passed to the player on your LEFT.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff6c6a63),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: selectedCount == 0
                                    ? null
                                    : () {
                                        selectedExchangeCards.clear();
                                        dialogSetState(() {});
                                        setState(() {});
                                      },
                                child: const Text('CLEAR'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 5),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: readyToPass ? passCards : null,
                              icon: const Icon(Icons.send_rounded, size: 18),
                              label: const Text(
                                'PASS 4 CARDS & ENTER GAME',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xff182a27),
                                foregroundColor: const Color(0xfffff8e8),
                                disabledBackgroundColor: const Color(0xffddd8cc),
                                disabledForegroundColor: const Color(0xff817b70),
                                elevation: 5,
                                shadowColor: const Color(0x55000000),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                  side: const BorderSide(
                                    color: Color(0xffc8a45d),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 7),

                          const Text(
                            '♠Q: If you pass ♠Q while another Spade remains in your hand, select at least one more Spade with it.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xff77736b),
                              height: 1.3,
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
            );
          },
        );
      },
    );
  }

  Widget buildExchangePanel() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              '4-CARD EXCHANGE',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Round $roundNumber',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose 4 cards to pass to the player on your LEFT.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'You will receive 4 cards from the player on your RIGHT.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'DIRECTION: CHOOSE LEFT  •  PLAY RIGHT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                color: Color(0xff806a38),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfff3f0e8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xffd6d0c3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.touch_app_rounded,
                    color: Color(0xff806a38),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Your 13 cards will appear together in a selection window.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${selectedExchangeCards.length}/4',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xff182a27),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: showExchangeCardPicker,
                icon: const Icon(Icons.style_rounded),
                label: Text(
                  selectedExchangeCards.isEmpty
                      ? 'CHOOSE CARDS'
                      : 'EDIT SELECTED CARDS',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff182a27),
                  foregroundColor: const Color(0xfffff8e8),
                  elevation: 6,
                  shadowColor: const Color(0x66000000),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: const BorderSide(
                      color: Color(0xffc8a45d),
                      width: 1.3,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '♠Q rule: If you pass ♠Q and have another Spade, you must pass at least one other Spade with it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
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
      duration: _cardAnimationDuration(480),
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

      final double tableWidth = MediaQuery.sizeOf(context).width;
      final bool compactTable = tableWidth < 360;
      final double slotWidth = compactTable ? 70 : 84;
      final double slotHeight = compactTable ? 88 : 98;

      final Widget emptySlot = Container(        width: slotWidth - 6,
        height: slotHeight - 14,
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
          width: slotWidth,
          height: slotHeight,
          child: Center(child: displayedCard),
        ),
      );
    }

    // Compact centre information so the four table positions always fit
    // comfortably on smaller phone screens.
    final double tableWidth = MediaQuery.sizeOf(context).width;
    final bool compactTable = tableWidth < 360;
    final double centerWidth = compactTable ? 112 : 132;
    final double centerHeight = compactTable ? 98 : 112;

    final center = Container(
      width: centerWidth,
      height: centerHeight,
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
                '${players[collectingWinnerIndex!].name} WINS THE HAND',                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xfff0d48e),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              )
          else
            Text(
              'HAND $handNumber OF 13',              style: const TextStyle(
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
              '${currentHand.length} OF 4 CARDS',
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
              padding: EdgeInsets.fromLTRB(
                compactTable ? 6 : 12,
                compactTable ? 9 : 14,
                compactTable ? 6 : 12,
                compactTable ? 8 : 12,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.spa_outlined, color: Color(0xffd4af63), size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: const Text('BREY TABLE', style: TextStyle(color: Color(0xffe3c27a), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.spa_outlined, color: Color(0xffd4af63), size: 16),
                    ],
                  ),
                  SizedBox(height: compactTable ? 1 : 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('YOU  →  BOT 1  →  BOT 2  →  BOT 3', style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 9.5, letterSpacing: 1.1)),
                  ),
                  SizedBox(height: compactTable ? 2 : 4),
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

  Widget _buildRoundHandSummary() {
    if (completedRoundHands.isEmpty) {
      return const SizedBox.shrink();
    }

    final int totalPenalty =
        completedRoundPenalties.fold<int>(0, (a, b) => a + b);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xfff8f7f3),
        border: Border.all(color: const Color(0xffd7d2c8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'HAND SUMMARY',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$totalPenalty pts',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...List<Widget>.generate(completedRoundHands.length, (index) {
            final List<PlayedCard> plays = completedRoundHands[index];
            final int winnerIndex = completedRoundWinners[index];
            final int penalty = completedRoundPenalties[index];
            final String cards = plays
                .map((played) => '${played.card.rank}${played.card.symbol}')
                .join(' ');
            final String winnerName = players[winnerIndex].name;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                'H${index + 1}  •  $cards  •  $winnerName won  •  ${penalty == 0 ? '0' : '+$penalty'} pts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

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
                                '${player.handsWon} Hands Won',
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

              _buildRoundHandSummary(),

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

  // ==========================================================
  // BREY RULE BOOK — VISUAL EDITION
  // ==========================================================

  TextSpan _coloredSuitSpan(String value, {TextStyle? baseStyle}) {
    final List<InlineSpan> spans = <InlineSpan>[];
    final RegExp suitPattern = RegExp(r'[♠♥♦♣]');
    int start = 0;
    for (final Match match in suitPattern.allMatches(value)) {
      if (match.start > start) {
        spans.add(TextSpan(text: value.substring(start, match.start), style: baseStyle));
      }
      final String suit = match.group(0)!;
      final Color suitColor = suit == '♥' || suit == '♦'
          ? const Color(0xffd32f2f)
          : const Color(0xff111827);
      spans.add(TextSpan(
        text: suit,
        style: (baseStyle ?? const TextStyle()).copyWith(
          color: suitColor,
          fontWeight: FontWeight.w900,
        ),
      ));
      start = match.end;
    }
    if (start < value.length) {
      spans.add(TextSpan(text: value.substring(start), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  Widget _coloredSuitText(
    String value, {
    TextStyle? style,
    TextAlign textAlign = TextAlign.left,
  }) {
    return RichText(
      textAlign: textAlign,
      text: _coloredSuitSpan(value, baseStyle: style),
    );
  }

  Color _ruleSuitColor(String suit) {
    return (suit == '♥' || suit == '♦')
        ? const Color(0xffd32f2f)
        : const Color(0xff111827);
  }

  Widget _ruleCard(String rank, String suit, {bool highlighted = false}) {
    return Container(
      width: 48,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? const Color(0xffb58b2a)
              : const Color(0xffd7d2c8),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank$suit',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: _ruleSuitColor(suit),
        ),
      ),
    );
  }

  Widget _ruleBadge(String text, {bool good = true}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: good ? const Color(0xffeaf7ee) : const Color(0xffffeeee),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: good ? const Color(0xff9ac9a5) : const Color(0xffe1aaaa),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            good ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 15,
            color: good ? const Color(0xff2e7d32) : const Color(0xffb3261e),
          ),
          const SizedBox(width: 4),
          _coloredSuitText(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: good ? const Color(0xff245b32) : const Color(0xff8b2020),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleVisualSection({
    required String number,
    required String title,
    required String explanation,
    required List<Widget> visual,
    IconData icon = Icons.menu_book_rounded,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xfffffdf8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xffded7c8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xffb58b2a),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 19, color: const Color(0xff165b43)),
              const SizedBox(width: 6),
              Expanded(
                child: _coloredSuitText(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff174c3b),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
            decoration: BoxDecoration(
              color: const Color(0xfff5f0e4),
              borderRadius: BorderRadius.circular(11),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: visual,
              ),
            ),
          ),
          const SizedBox(height: 9),
          _coloredSuitText(
            explanation,
            textAlign: TextAlign.left,
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

  Widget _ruleArrow({bool down = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Icon(
        down ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded,
        size: 20,
        color: const Color(0xff2e7d32),
      ),
    );
  }

  void showRuleBook() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xfff5f0e4),
          insetPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff123f31), Color(0xff1d6049)],
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xffb58b2a), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.menu_book_rounded, color: Color(0xffffe7a3), size: 27),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BREY — GAME RULES',
                                style: TextStyle(
                                  color: Color(0xffffe7a3),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Quick • Clear • Visual',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 2, bottom: 3),
                      children: [
                        _ruleVisualSection(
                          number: '1',
                          title: 'Quick Objective',
                          icon: Icons.flag_rounded,
                          visual: [
                            _ruleCard('10', '♥'),
                            _ruleCard('J', '♦'),
                            _ruleCard('K', '♣'),
                            _ruleCard('Q', '♠', highlighted: true),
                          ],
                          explanation: 'Collect as few penalty points as possible. The game ends at 100+ points; the lowest final score wins.',
                        ),
                        _ruleVisualSection(
                          number: '2',
                          title: 'Exchange 4 Cards',
                          icon: Icons.swap_horiz_rounded,
                          visual: [
                            const Icon(Icons.person_rounded, size: 27, color: Color(0xff172554)),
                            _ruleArrow(),
                            _ruleCard('4', '♣'),
                            _ruleCard('7', '♦'),
                            _ruleCard('J', '♥'),
                            _ruleCard('Q', '♠'),
                            _ruleArrow(),
                            const Text('LEFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xff2e7d32))),
                          ],
                          explanation: 'Choose exactly 4 cards from your original 13-card hand and pass them to your LEFT. If you pass ♠Q while another original ♠ remains, pass at least one more ♠. If ♠Q is your only ♠, the other 3 cards may be any cards.',
                        ),
                        _ruleVisualSection(
                          number: '3',
                          title: 'Hand 1 Is Special',
                          icon: Icons.looks_one_rounded,
                          visual: [
                            _ruleCard('7', '♣', highlighted: true),
                            _ruleCard('4', '♦', highlighted: true),
                            _ruleBadge('SAFE LEAD'),
                            _ruleBadge('♠Q', good: false),
                          ],
                          explanation: 'The leader must lead a non-penalty ♣ or ♦ when available. If none is available, any card except ♠Q may lead. If you cannot follow suit, play a non-penalty card when possible; otherwise play any legal card except ♠Q.',
                        ),
                        _ruleVisualSection(
                          number: '4',
                          title: 'Follow Suit + ♠Q Rule',
                          icon: Icons.rule_rounded,
                          visual: [
                            _ruleCard('7', '♥', highlighted: true),
                            _ruleArrow(),
                            _ruleCard('K', '♥', highlighted: true),
                            _ruleBadge('MUST FOLLOW'),
                            _ruleArrow(),
                            _ruleCard('Q', '♠', highlighted: true),
                          ],
                          explanation: 'If you have the led suit, you MUST follow it. In Hands 2–13, if you are void in the led suit and hold ♠Q, you MUST play ♠Q. Otherwise, any legal discard may be played.',
                        ),
                        _ruleVisualSection(
                          number: '5',
                          title: 'Who Wins the Hand?',
                          icon: Icons.emoji_events_rounded,
                          visual: [
                            _ruleCard('4', '♠'),
                            _ruleCard('9', '♠'),
                            _ruleCard('Q', '♠', highlighted: true),
                            _ruleArrow(),
                            const Icon(Icons.emoji_events_rounded, size: 28, color: Color(0xffb58b2a)),
                          ],
                          explanation: 'The highest card of the led suit wins the Hand. The winner takes all 4 played cards and their penalty points, then leads the next Hand.',
                        ),
                        _ruleVisualSection(
                          number: '6',
                          title: 'Know the Penalty Cards',
                          icon: Icons.warning_amber_rounded,
                          visual: [
                            _ruleCard('J', '♦'),
                            const Text('4', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            _ruleCard('K', '♣'),
                            const Text('6', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            _ruleCard('Q', '♠'),
                            const Text('12', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            _ruleCard('2', '♥'),
                            const Text('1 each', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                          ],
                          explanation: 'Current BREY scoring: ♦J = 4 points, ♣K = 6 points, ♠Q = 12 points normally, and each ♥ = 1 point. If the game protects/scores ♠Q as 0, it contributes 0.',
                        ),
                        _ruleVisualSection(
                          number: '7',
                          title: 'Two-Hand Lead Limit',
                          icon: Icons.block_rounded,
                          visual: [
                            _ruleCard('5', '♦', highlighted: true),
                            _ruleArrow(),
                            _ruleCard('K', '♦', highlighted: true),
                            _ruleArrow(),
                            _ruleCard('7', '♦'),
                            const SizedBox(width: 4),
                            _ruleBadge('BLOCKED NEXT', good: false),
                          ],
                          explanation: 'If the same suit is led in two consecutive Hands, that suit cannot be led in the next Hand when another legal lead exists. If ♠Q has already been played in the Round, this restriction ends for the rest of that Round.',
                        ),
                        _ruleVisualSection(
                          number: '8',
                          title: 'Round-End Rules',
                          icon: Icons.calculate_rounded,
                          visual: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xffffeeee),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: const Color(0xffe1aaaa)),
                              ),
                              child: const Text('35 EXACT → CANCEL', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xff8b2020))),
                            ),
                            _ruleArrow(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xffeaf7ee),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: const Color(0xff9ac9a5)),
                              ),
                              child: const Text('0 HANDS → −5', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xff245b32))),
                            ),
                          ],
                          explanation: 'After all 13 Hands, if one player has exactly 35 actual Round penalty points, those 35 are cancelled. A player who won 0 Hands gets −5 points. Scores cannot go below 0.',
                        ),
                        _ruleVisualSection(
                          number: '9',
                          title: 'Next Round & Game End',
                          icon: Icons.flag_circle_rounded,
                          visual: [
                            _ruleCard('Q', '♠', highlighted: true),
                            _ruleArrow(),
                            const Icon(Icons.person_rounded, size: 27, color: Color(0xff172554)),
                            _ruleArrow(),
                            const Text('NEXT DEALER', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xff174c3b))),
                            _ruleArrow(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xfff5e8c8),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Text('100+ → END', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xff6d4c1f))),
                            ),
                          ],
                          explanation: 'The player who collected ♠Q becomes the next dealer. A score of 100 or more ends the game after the required scoring stage. The player or players with the lowest final cumulative score win.',
                        ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xff174c3b),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: const Color(0xffb58b2a), width: 1.2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.lightbulb_rounded, color: Color(0xffffe7a3), size: 20),
                                  SizedBox(width: 7),
                                  Text('EASY MEMORY', style: TextStyle(color: Color(0xffffe7a3), fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.7)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _coloredSuitText(
                                'FOLLOW SUIT → HAND 1 IS SPECIAL → VOID + ♠Q (HANDS 2–13) = PLAY ♠Q → HIGHEST LED SUIT WINS → WINNER TAKES PENALTIES → EXACT 35 = CANCEL → 0 HANDS = −5 → ♠Q COLLECTOR DEALS NEXT → 100+ ENDS GAME.',
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.45, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff8e8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xffd9c69a)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.tips_and_updates_rounded, size: 20, color: Color(0xff8a6a2b)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'If a card is illegal, the on-screen hint explains the rule you need right now.',
                                  style: TextStyle(fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w700, color: Color(0xff5f513b)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
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
      barrierLabel: 'Leave Game',
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
                    label: const Text('PLAY A NEW GAME'),
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
            'PLAYER DETAILS',
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

  static const List<String> _animationSpeedOptions = <String>[
    'normal',
    'fast',
  ];

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_settingsVibrationKey, _vibrationEnabled);
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
  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void update(VoidCallback change) {
              setDialogState(change);
              setState(change);
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
                            ButtonSegment<String>(value: 'normal', label: Text('Relaxed')),
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
                        title: const Text('Automatically Start the Next Hand'),
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
                        title: const Text('Keep the Screen Awake'),
                        subtitle: const Text('This preference is saved; device-level screen wake is handled separately.'),
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
                                'BREY is a classic card game of risk and strategy.\n\n'
                                'Settings are saved on this device for your convenience.',
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
                        'A CLASSIC CARD GAME OF RISK AND STRATEGY',
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
                            'START A NEW GAME',
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
                            'PLAYER DETAILS',
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
                                : '${players[currentPlayerIndex].name} is playing…',
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
