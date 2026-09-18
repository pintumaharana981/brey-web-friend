// BREY V1.2.11 — Penalty Targeting Intelligence
import 'dart:async';
import 'dart:convert';
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

  List<CardModel> cards = [];

  int score = 0;
  int handsWon = 0;
  bool eliminated = false;

  Player({
    required this.name,
    required this.isHuman,
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

class BreyApp extends StatelessWidget {
  const BreyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BREY',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xffeef0ed),
      ),
      home: const BreyGame(),
    );
  }
}

// ============================================================
// GAME
// ============================================================

class BreyGame extends StatefulWidget {
  const BreyGame({super.key});

  @override
  State<BreyGame> createState() => _BreyGameState();
}

class _BreyGameState extends State<BreyGame> {
  @override
  void initState() {
    super.initState();
    _loadAdaptiveLearning();
  }

  Future<void> _loadAdaptiveLearning() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? raw = prefs.getString(_learningStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((dynamic playerKey, dynamic values) {
            final int? playerIndex = int.tryParse(playerKey.toString());
            if (playerIndex == null || playerIndex < 1 || playerIndex > 3) return;
            if (values is! Map) return;

            final Map<String, double> memory = <String, double>{};
            values.forEach((dynamic signature, dynamic value) {
              final double? number = double.tryParse(value.toString());
              if (number == null || !number.isFinite) return;
              memory[signature.toString()] =
                  number.clamp(-8.0, 8.0).toDouble();
            });
            learnedDecisionWeights[playerIndex] = memory;
          });
        }
      }

      // V42.50: restore the compact card-pattern memory so learned
      // patterns survive app restarts instead of disappearing with the
      // current BREY session.
      final String? patternRaw = prefs.getString(_learningPatternStorageKey);
      if (patternRaw != null && patternRaw.isNotEmpty) {
        final dynamic patternDecoded = jsonDecode(patternRaw);
        if (patternDecoded is Map) {
          patternDecoded.forEach((dynamic signature, dynamic value) {
            final double? number = double.tryParse(value.toString());
            if (number == null || !number.isFinite) return;
            _learningPatternMemory[signature.toString()] =
                number.clamp(-8.0, 8.0).toDouble();
          });
        }
      }

      final String? styleRaw = prefs.getString(_playerStyleStorageKey);
      if (styleRaw != null && styleRaw.isNotEmpty) {
        final dynamic styleDecoded = jsonDecode(styleRaw);
        if (styleDecoded is Map) {
          styleDecoded.forEach((dynamic signature, dynamic value) {
            final double? number = double.tryParse(value.toString());
            if (number == null || !number.isFinite) return;
            playerStyleWeights[signature.toString()] =
                number.clamp(-8.0, 8.0).toDouble();
          });
        }
      }

      final String? opponentRaw =
          prefs.getString(_opponentBehaviorStorageKey);
      if (opponentRaw != null && opponentRaw.isNotEmpty) {
        final dynamic opponentDecoded = jsonDecode(opponentRaw);
        if (opponentDecoded is Map) {
          opponentDecoded.forEach((dynamic playerKey, dynamic values) {
            final int? playerIndex = int.tryParse(playerKey.toString());
            if (playerIndex == null || playerIndex < 1 || playerIndex > 3) {
              return;
            }
            if (values is! Map) return;
            final Map<String, double> memory = <String, double>{};
            values.forEach((dynamic signature, dynamic value) {
              final double? number = double.tryParse(value.toString());
              if (number == null || !number.isFinite) return;
              memory[signature.toString()] =
                  number.clamp(-8.0, 8.0).toDouble();
            });
            opponentBehaviorWeights[playerIndex] = memory;
          });
        }
      }
      final String? gameRaw = prefs.getString(_gameOutcomeStorageKey);
      if (gameRaw != null && gameRaw.isNotEmpty) {
        final dynamic gameDecoded = jsonDecode(gameRaw);
        if (gameDecoded is Map) {
          gameDecoded.forEach((dynamic key, dynamic value) {
            final int? index = int.tryParse(key.toString());
            final double? number = double.tryParse(value.toString());
            if (index == null || index < 1 || index > 3) return;
            if (number == null || !number.isFinite) return;
            gameOutcomeWeights[index] = number.clamp(-8.0, 8.0).toDouble();
          });
        }
      }

      // V42.45: load how many completed Rounds have informed each BOT's
      // game-level model. Confidence grows gradually instead of allowing a
      // small number of games to dominate the BOT's established strategy.
      final String? experienceRaw =
          prefs.getString(_gameOutcomeExperienceStorageKey);
      if (experienceRaw != null && experienceRaw.isNotEmpty) {
        final dynamic experienceDecoded = jsonDecode(experienceRaw);
        if (experienceDecoded is Map) {
          experienceDecoded.forEach((dynamic key, dynamic value) {
            final int? index = int.tryParse(key.toString());
            final int? count = int.tryParse(value.toString());
            if (index == null || index < 1 || index > 3) return;
            if (count == null || count < 0) return;
            gameOutcomeExperience[index] = count.clamp(0, 200);
          });
        }
      }

    } catch (_) {
      // Persistence must never prevent BREY from starting.
    } finally {
      _learningLoaded = true;
    }
  }

  Future<void> _saveAdaptiveLearning() async {
    if (!_learningLoaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, Map<String, double>> data = <String, Map<String, double>>{};
      learnedDecisionWeights.forEach((int playerIndex, Map<String, double> memory) {
        data[playerIndex.toString()] = Map<String, double>.from(memory);
      });
      await prefs.setString(_learningStorageKey, jsonEncode(data));
      await prefs.setString(
        _learningPatternStorageKey,
        jsonEncode(_learningPatternMemory),
      );
      await prefs.setString(
        _playerStyleStorageKey,
        jsonEncode(playerStyleWeights),
      );
      final Map<String, Map<String, double>> opponentData =
          <String, Map<String, double>>{};
      opponentBehaviorWeights.forEach(
        (int playerIndex, Map<String, double> memory) {
          opponentData[playerIndex.toString()] =
              Map<String, double>.from(memory);
        },
      );
      await prefs.setString(
        _opponentBehaviorStorageKey,
        jsonEncode(opponentData),
      );
      final Map<String, double> gameData = <String, double>{};
      gameOutcomeWeights.forEach((int index, double value) {
        gameData[index.toString()] = value;
      });
      await prefs.setString(_gameOutcomeStorageKey, jsonEncode(gameData));
      final Map<String, int> experienceData = <String, int>{};
      gameOutcomeExperience.forEach((int index, int count) {
        experienceData[index.toString()] = count;
      });
      await prefs.setString(
        _gameOutcomeExperienceStorageKey,
        jsonEncode(experienceData),
      );
    } catch (_) {
      // Gameplay continues normally if persistence is unavailable.
    }
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

  // Hand-completion animation state. Cards remain visible while they
  // smoothly collect toward the winner before the next Hand begins.
  bool handCollecting = false;
  int? collectingWinnerIndex;

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

  // ==========================================================
  // ADAPTIVE LEARNING MEMORY
  // ==========================================================

  // Learns only from public game outcomes. These weights stay alive while
  // the app is open, so the BOT can adapt across Hands and Games without
  // reading hidden opponent cards or changing the game rules.
  final Map<int, Map<String, double>> learnedDecisionWeights = {};
  final Map<int, List<String>> lastBotDecisionSignatures =
      <int, List<String>>{};

  // V42.41: model the human player's public playing style.
  final Map<String, double> playerStyleWeights = <String, double>{};
  final List<String> _humanHandDecisionSignatures = <String>[];

  // V42.42: each opponent gets a separate public-behavior model. The BOT
  // learns only from cards that opponent actually played.
  final Map<int, Map<String, double>> opponentBehaviorWeights =
      <int, Map<String, double>>{};
  final Map<int, List<String>> _opponentHandDecisionSignatures =
      <int, List<String>>{};

  // V42.47: bounded memory of card-choice outcomes. Keys use suit:value.
  // The map is intentionally lightweight and starts empty.
  final Map<String, double> _learningPatternMemory = <String, double>{};

  // Persistent adaptive memory. Only bounded learning weights are stored.
  static const String _learningStorageKey = 'brey_adaptive_learning_v42_40';
  static const String _playerStyleStorageKey = 'brey_player_style_v42_41';
  static const String _opponentBehaviorStorageKey =
      'brey_opponent_behavior_v42_42';
  // V42.50: persistent storage for the V42.47+ pattern-memory layer.
  static const String _learningPatternStorageKey =
      'brey_learning_pattern_memory_v42_50';
  bool _learningLoaded = false;
  final Map<int, double> gameOutcomeWeights = <int, double>{};
  // V42.45: number of completed Rounds used to train each BOT's game-level
  // outcome model. This is confidence metadata, not a gameplay rule.
  final Map<int, int> gameOutcomeExperience = <int, int>{};
  static const String _gameOutcomeStorageKey = 'brey_game_outcome_learning_v42_44';
  static const String _gameOutcomeExperienceStorageKey =
      'brey_game_outcome_experience_v42_45';

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
            color: Colors.black54,
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
      transitionDuration: const Duration(milliseconds: 220),
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
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            message,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.35,
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.94,
              end: 1.0,
            ).animate(curved),
            child: child,
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
    if (!mounted || _shownRuleHints.contains(key)) return;

    _shownRuleHints.add(key);

    await _showSmoothHint(
      title: title,
      message: message,
      scenario: scenario,
    );
  }

  Future<void> _showFirstHandHint() async {
    if (!mounted ||
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
        name: 'YOU',
        isHuman: true,
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

    // Random dealer for Round 1.
    dealerIndex = random.nextInt(4);

    currentPlayerIndex = 0;

    spadeQueenCollector = null;
    spadeQueenPlayedThisRound = false;

    currentHand.clear();
    ledSuit = null;

    roundFinished = false;
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
    lastBotDecisionSignatures.clear();

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
    message = 'Dealing cards...';
    _runDealingAnimation(generation);
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

    message =
        'Select exactly 4 cards to pass to the player on your LEFT.';
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
            const Text(
              'DEALING THE ROUND',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Round $roundNumber • 52 cards',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
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
                    : '$dealtCardCount / 52 cards dealt',                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
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
    } else {
      if (selectedExchangeCards.length >= 4) {
        message = 'You can select only 4 cards.';
        setState(() {});
        return;
      }

      selectedExchangeCards.add(card);
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

    exchangePhase = false;

    selectedExchangeCards.clear();
    exchangeSelections.clear();

    currentHand.clear();
    ledSuit = null;

    // Dealer's right-side player starts Hand 1.
    currentPlayerIndex =
        (dealerIndex + 1) % 4;

    message =
        'Exchange complete. Hand 1 begins.';

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
      setState(() {});
      _showHintForIllegalPlay(card);
      return;
    }

    observeHumanDecision(card, leading: currentHand.isEmpty);
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

    // Remove card from player's hand.
    players[playerIndex].cards.remove(card);

    // Add to current Hand.
    currentHand.add(
      PlayedCard(
        playerIndex: playerIndex,
        card: card,
      ),
    );

    // V42.42: record BOT behavior only after the card is publicly played.
    if (playerIndex >= 1 && playerIndex <= 3) {
      observeOpponentDecision(
        playerIndex,
        card,
        leading: currentHand.length == 1,
      );
    }

    playedCardsThisRound.add(card);
    playedSuitCounts[card.suit] = (playedSuitCounts[card.suit] ?? 0) + 1;
    knownCardOwner.remove(cardKey(card));

    // ========================================================
    // ♠Q PLAYED
    // ========================================================

    if (card.isSpadeQueen) {
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
    completeHand();
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

  String learningSignature(
    CardModel card, {
    required bool winning,
    required bool leading,
  }) {
    final String mode = leading
        ? 'lead'
        : (winning ? 'win' : 'lose');
    final int valueBucket = card.value <= 5
        ? 0
        : card.value <= 9
            ? 1
            : card.value <= 12
                ? 2
                : 3;
    final int penaltyBucket = card.penalty == 0
        ? 0
        : card.penalty <= 2
            ? 1
            : card.penalty <= 6
                ? 2
                : 3;
    return '$mode|${card.suit}|v$valueBucket|p$penaltyBucket';
  }

  double scoreLearnedExperience(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
    required bool leading,
  }) {
    if (!_learningLoaded) return 0.0;
    final Map<String, double> memory =
        learnedDecisionWeights[playerIndex] ?? const <String, double>{};
    final String signature = learningSignature(
      candidate,
      winning: winning,
      leading: leading,
    );
    return memory[signature] ?? 0.0;
  }

  void rememberBotDecision(
    int playerIndex,
    CardModel card, {
    required bool winning,
    required bool leading,
  }) {
    lastBotDecisionSignatures
        .putIfAbsent(playerIndex, () => <String>[])
        .add(
          learningSignature(
            card,
            winning: winning,
            leading: leading,
          ),
        );
  }

  void learnFromCompletedHand(int winnerIndex, int handPenalty) {
    for (int playerIndex = 1; playerIndex < 4; playerIndex++) {
      final List<String>? signatures = lastBotDecisionSignatures[playerIndex];
      if (signatures == null || signatures.isEmpty) continue;

      final Map<String, double> memory =
          learnedDecisionWeights.putIfAbsent(
        playerIndex,
        () => <String, double>{},
      );

      final bool won = winnerIndex == playerIndex;
      // Every public BOT decision in the Hand contributes to learning. The
      // previous learner remembered only the final decision, which meant most
      // of the Hand was discarded as training data.
      double reward;
      if (won) {
        reward = handPenalty == 0
            ? 1.8
            : -(handPenalty.clamp(0, 35) / 7.0);
      } else {
        reward = handPenalty == 0 ? 0.4 : 0.9;
      }

      // Repeatedly playing the same decision pattern in one Hand should not
      // multiply its learning signal without limit. Count each signature once
      // per Hand, then apply the bounded update.
      final Set<String> uniqueSignatures = signatures.toSet();
      final double perDecisionReward = reward /
          sqrt(uniqueSignatures.length.toDouble().clamp(1.0, 4.0));

      for (final String signature in uniqueSignatures) {
        final double oldValue = memory[signature] ?? 0.0;
        // Small bounded updates prevent one unusual Hand from dominating the
        // BOT's established strategy.
        final double learningRate = adaptiveLearningRate(playerIndex);
        final double updated =
            (oldValue * (1.0 - learningRate)) +
            (perDecisionReward * learningRate);
        memory[signature] = updated.clamp(-8.0, 8.0).toDouble();

        // V42.49: also maintain a compact pattern-memory layer. This uses the
        // same decision signature, so it can be activated directly during
        // future card selection without depending on an exact card value.
        final double oldPattern = _learningPatternMemory[signature] ?? 0.0;
        _learningPatternMemory[signature] =
            ((oldPattern * 0.92) + (perDecisionReward * 0.08))
                .clamp(-8.0, 8.0)
                .toDouble();
      }
    }

    lastBotDecisionSignatures.clear();
    _saveAdaptiveLearning();
  }

    String playerStyleSignature(CardModel card, {required bool leading}) {
    final int valueBucket = card.value <= 5 ? 0 : (card.value <= 9 ? 1 : 2);
    final int penaltyBucket =
        card.penalty == 0 ? 0 : (card.penalty <= 2 ? 1 : 2);
    return '${leading ? 'lead' : 'follow'}|${card.suit}|v$valueBucket|p$penaltyBucket';
  }

  void observeHumanDecision(CardModel card, {required bool leading}) {
    _humanHandDecisionSignatures.add(
      playerStyleSignature(card, leading: leading),
    );
  }

  double scorePlayerStylePrediction(
    CardModel candidate, {
    required bool leading,
  }) {
    if (!_learningLoaded) return 0.0;
    final String signature =
        playerStyleSignature(candidate, leading: leading);
    return (playerStyleWeights[signature] ?? 0.0).clamp(-8.0, 8.0).toDouble();
  }

  void learnHumanPlayingStyle(int winnerIndex, int handPenalty) {
    if (_humanHandDecisionSignatures.isEmpty) return;

    final bool humanWon = winnerIndex == 0;
    final double outcome = humanWon
        ? (handPenalty == 0 ? 1.4 : -1.0)
        : (handPenalty >= 8 ? -1.4 : 0.7);

    for (final String signature in _humanHandDecisionSignatures) {
      final double oldValue = playerStyleWeights[signature] ?? 0.0;
      final double learningRate = adaptiveLearningRate(1);
      final double updated =
          (oldValue * (1.0 - learningRate)) + (outcome * learningRate);
      playerStyleWeights[signature] = updated.clamp(-8.0, 8.0).toDouble();
    }

    _humanHandDecisionSignatures.clear();
    _saveAdaptiveLearning();
  }

  String opponentBehaviorSignature(
    CardModel card, {
    required bool leading,
  }) {
    final int valueBucket = card.value <= 5
        ? 0
        : card.value <= 9
            ? 1
            : card.value <= 12
                ? 2
                : 3;
    final int penaltyBucket = card.penalty == 0
        ? 0
        : card.penalty <= 2
            ? 1
            : card.penalty <= 6
                ? 2
                : 3;
    return '${leading ? 'lead' : 'follow'}|${card.suit}|v$valueBucket|p$penaltyBucket';
  }

  void observeOpponentDecision(
    int opponentIndex,
    CardModel card, {
    required bool leading,
  }) {
    _opponentHandDecisionSignatures
        .putIfAbsent(opponentIndex, () => <String>[])
        .add(opponentBehaviorSignature(card, leading: leading));
  }

  double scoreOpponentBehaviorPrediction(
    int botIndex,
    CardModel candidate, {
    required bool leading,
  }) {
    if (!_learningLoaded) return 0.0;

    double score = 0.0;
    for (int opponent = 1; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;
      final Map<String, double> memory =
          opponentBehaviorWeights[opponent] ?? const <String, double>{};
      final String signature =
          opponentBehaviorSignature(candidate, leading: leading);
      final double learned = memory[signature] ?? 0.0;

      // A positive learned value means this opponent has historically made
      // this type of public decision in favorable outcomes for themselves.
      // When leading, slightly favor suits where a strong opponent pattern
      // suggests they are comfortable; this makes the model predictive rather
      // than simply rewarding imitation.
      if (leading && candidate.suit == 'Spades') {
        score -= learned * 0.35;
      } else {
        score += learned * 0.18;
      }
    }
    return score.clamp(-6.0, 6.0).toDouble();
  }

  void learnOpponentBehavior(int winnerIndex, int handPenalty) {
    if (_opponentHandDecisionSignatures.isEmpty) return;

    _opponentHandDecisionSignatures.forEach(
      (int opponentIndex, List<String> signatures) {
        if (signatures.isEmpty) return;
        final Map<String, double> memory = opponentBehaviorWeights
            .putIfAbsent(opponentIndex, () => <String, double>{});
        final bool opponentWon = winnerIndex == opponentIndex;
        final double outcome = opponentWon
            ? (handPenalty == 0 ? 1.2 : -0.8)
            : (handPenalty >= 8 ? -0.7 : 0.5);

        for (final String signature in signatures) {
          final double oldValue = memory[signature] ?? 0.0;
          final double learningRate = adaptiveLearningRate(opponentIndex);
          final double updated =
              (oldValue * (1.0 - learningRate)) +
              (outcome * learningRate);
          memory[signature] = updated.clamp(-8.0, 8.0).toDouble();
        }
      },
    );

    _opponentHandDecisionSignatures.clear();
    _saveAdaptiveLearning();
  }

  double adaptiveLearningRate(int playerIndex) {
    final int experience = gameOutcomeExperience[playerIndex] ?? 0;
    // Start conservatively, then learn faster once the BOT has accumulated
    // enough completed-Round evidence. Cap the rate so new outcomes never
    // overwrite established strategy too aggressively.
    return (0.035 + (experience.clamp(0, 20) / 20.0) * 0.045)
        .clamp(0.035, 0.08)
        .toDouble();
  }

  double scoreLearningPatternMemory(int botIndex, CardModel card, {
    required bool winning,
    required bool leading,
  }) {
    if (!_learningLoaded) return 0.0;

    final int experience = gameOutcomeExperience[botIndex] ?? 0;
    final double confidence = (experience / 10.0).clamp(0.0, 1.0);
    if (confidence == 0.0) return 0.0;

    final String key = learningSignature(
      card,
      winning: winning,
      leading: leading,
    );
    // Keep this influence deliberately small: learned patterns refine the
    // strategic engine rather than replacing its rule-based reasoning.
    return ((_learningPatternMemory[key] ?? 0.0) * confidence * 1.25)
        .clamp(-6.0, 6.0)
        .toDouble();
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

      // V1.2.11: actively search known opponent penalty targets. This layer
      // is strongest for major penalties and becomes more important at 94+.
      score += scorePenaltyTargetingLead(playerIndex, candidate);

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
      score += scorePlayerStylePrediction(
        candidate,
        leading: true,
      ) * 1.5;
      score += scoreOpponentBehaviorPrediction(
        playerIndex,
        candidate,
        leading: true,
      );
      score += scoreLearningPatternMemory(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      );
      score += scoreLearnedExperience(
        playerIndex,
        candidate,
        winning: false,
        leading: true,
      ) * 6.0;
      score += scoreGameLevelLearning(
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
    rememberBotDecision(
      playerIndex,
      chosen,
      winning: false,
      leading: true,
    );
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
      score += scorePlayerStylePrediction(
        candidate,
        leading: false,
      ) * 1.5;
      score += scoreOpponentBehaviorPrediction(
        playerIndex,
        candidate,
        leading: false,
      );
      score += scoreLearningPatternMemory(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      );
      score += scoreLearningPatternMemory(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      );
      score += scoreLearnedExperience(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      ) * 6.0;
      score += scoreGameLevelLearning(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      );
      score = balanceGrandmasterScore(score, candidate);


        if (score > bestScore ||



            (score == bestScore && isBetterBotTieBreak(candidate, best))) {



          bestScore = score;



          best = candidate;



        }
      }

      final CardModel chosen = maybeUseDifficultyCard(best, losing);
      rememberBotDecision(
        playerIndex,
        chosen,
        winning: false,
        leading: false,
      );
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
      score += scorePlayerStylePrediction(
        candidate,
        leading: false,
      ) * 1.5;
      score += scoreOpponentBehaviorPrediction(
        playerIndex,
        candidate,
        leading: false,
      );
      score += scoreLearningPatternMemory(
        playerIndex,
        candidate,
        winning: true,
        leading: false,
      );
      score += scoreLearnedExperience(
        playerIndex,
        candidate,
        winning: true,
        leading: false,
      ) * 6.0;
      score += scoreGameLevelLearning(
        playerIndex,
        candidate,
        winning: true,
        leading: false,
      );
      score = balanceGrandmasterScore(score, candidate);


      if (score > bestScore ||



          (score == bestScore && isBetterBotTieBreak(candidate, best))) {



        bestScore = score;



        best = candidate;



      }
    }

    final CardModel chosen = maybeUseDifficultyCard(best, sameSuit);
    rememberBotDecision(
      playerIndex,
      chosen,
      winning: true,
      leading: false,
    );
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
      score += scorePlayerStylePrediction(
        candidate,
        leading: false,
      ) * 1.5;
      score += scoreOpponentBehaviorPrediction(
        playerIndex,
        candidate,
        leading: false,
      );
      score += scoreLearnedExperience(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      ) * 6.0;
      score += scoreGameLevelLearning(
        playerIndex,
        candidate,
        winning: false,
        leading: false,
      );
      score = balanceGrandmasterScore(score, candidate);


      if (score > bestScore ||



          (score == bestScore && isBetterBotTieBreak(candidate, best))) {



        bestScore = score;



        best = candidate;



      }
    }

    final CardModel chosen = maybeUseDifficultyCard(best, legalCards);
    rememberBotDecision(
      playerIndex,
      chosen,
      winning: false,
      leading: false,
    );
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
  // V1.2.11 PENALTY TARGETING INTELLIGENCE
  // ==========================================================

  // Returns the known, unplayed penalty cards held by an opponent.
  // The BOT only uses information it can legitimately know (for example,
  // cards revealed through the exchange), never hidden cards in an opponent's
  // hand. Highest-value penalties are considered first.
  List<CardModel> knownPenaltyTargetsForOpponent(int opponent) {
    final List<CardModel> targets =
        (receivedCardsByPlayer[opponent] ?? const <CardModel>[])
            .where((card) =>
                card.penalty > 0 &&
                !playedCardsThisRound.any(
                  (played) => cardKey(played) == cardKey(card),
                ))
            .toList();

    targets.sort((a, b) {
      final int penaltyCompare = b.penalty.compareTo(a.penalty);
      if (penaltyCompare != 0) return penaltyCompare;
      return b.value.compareTo(a.value);
    });

    return targets;
  }

  // Checks whether a target penalty card can reasonably become the winner if
  // this BOT leads a smaller card of the same suit. A known higher card makes
  // the transfer unsafe. Unknown higher cards reduce confidence but do not
  // automatically reject the idea.
  double scorePenaltyTargetLead(
    int botIndex,
    CardModel leadCard, {
    required CardModel target,
    required int opponent,
  }) {
    if (leadCard.suit != target.suit || leadCard.value >= target.value) {
      return -40;
    }

    double score = 0;

    // A known higher card held by another player means the target cannot be
    // expected to win reliably. Treat that target as unsafe.
    bool knownHigherCard = false;
    for (int player = 0; player < 4; player++) {
      if (player == botIndex || player == opponent) continue;

      final List<CardModel> known =
          receivedCardsByPlayer[player] ?? const <CardModel>[];
      if (known.any((card) =>
          card.suit == target.suit &&
          card.value > target.value &&
          !playedCardsThisRound.any(
            (played) => cardKey(played) == cardKey(card),
          ))) {
        knownHigherCard = true;
        break;
      }
    }

    if (knownHigherCard) {
      return -28;
    }

    final int higherUnseen =
        cardsHigherThanInUnseen(target.suit, target.value, botIndex);

    // No higher unseen card gives us the strongest confidence. If higher
    // cards are still unseen, keep the target viable but reduce its value.
    final double safetyFactor = higherUnseen == 0
        ? 1.0
        : 1.0 / (1.0 + higherUnseen * 0.45);

    score += target.penalty * 28.0 * safetyFactor;
    score += penaltyPriority(target) * 16.0 * safetyFactor;

    // A very small lead is preferable because it leaves the target with more
    // room to become the winning card without unnecessarily spending control.
    score += max(0, target.value - leadCard.value) * 0.8;

    // When the opponent is close to elimination, routing a major penalty to
    // that opponent is especially valuable.
    if (players[opponent].score >= 94) {
      score += target.penalty * 22.0 * safetyFactor;
    } else if (players[opponent].score >= 88) {
      score += target.penalty * 12.0 * safetyFactor;
    }

    // In danger mode, prefer a reasonably safe penalty-routing opportunity
    // over an ordinary lead. This is still subordinate to legality.
    if (players[botIndex].score >= 94) {
      score += target.penalty * 18.0 * safetyFactor;
    }

    return score;
  }

  // Searches penalty targets in the required order:
  // Q♠ (12), K♣ (6), J♦ (4), then Hearts (1 each). If the largest target is
  // not safely transferable, the next target is considered instead.
  double scorePenaltyTargetingLead(
    int botIndex,
    CardModel leadCard,
  ) {
    double bestScore = 0;

    for (int opponent = 0; opponent < 4; opponent++) {
      if (opponent == botIndex) continue;

      final List<CardModel> targets = knownPenaltyTargetsForOpponent(opponent);
      if (targets.isEmpty()) continue;

      for (final CardModel target in targets) {
        if (leadCard.suit != target.suit || leadCard.value >= target.value) {
          continue;
        }

        final double targetScore = scorePenaltyTargetLead(
          botIndex,
          leadCard,
          target: target,
          opponent: opponent,
        );

        // Unsafe targets are deliberately skipped so the engine can move to
        // the next-largest known penalty instead of forcing a bad lead.
        if (targetScore <= 0) continue;

        bestScore = max(bestScore, targetScore);
      }
    }

    return bestScore;
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
  // COMPLETE HAND
  // ==========================================================

  void completeHand() {
    int winnerIndex =
        determineCurrentWinner();

    int handPenalty =
        calculateHandPenalty(winnerIndex);

    // If one player collects every penalty point in the Hand,
    // that Hand scores 0 points for that player.
    // The complete deck contains 35 penalty points.
    final int scoreForHand =
        handPenalty == 35 ? 0 : handPenalty;

    players[winnerIndex].score +=
        scoreForHand;

    players[winnerIndex].handsWon++;

    // Let every BOT learn from the public result of this Hand. The learner
    // never sees hidden opponent cards; it only updates from the actual
    // winner and penalty outcome.
    learnFromCompletedHand(winnerIndex, handPenalty);
    learnHumanPlayingStyle(winnerIndex, handPenalty);
    learnOpponentBehavior(winnerIndex, handPenalty);

    // ========================================================
    // ELIMINATION AFTER HAND IS SCORED
    // ========================================================

    if (
      players[winnerIndex].score >= 100
    ) {
      players[winnerIndex].eliminated = true;
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

    String cardsText = currentHand
        .map(
          (played) =>
              '${players[played.playerIndex].name}: ${played.card.shortName}',
        )
        .join('   ');

    message =
        '${players[winnerIndex].name} won Hand $handNumber and received $handPenalty points.\n$cardsText';

    // Keep the four cards on the table and begin a short collection
    // animation toward the Hand winner. The scoring above has already
    // happened, so the animation is purely visual.
    handCollecting = true;
    collectingWinnerIndex = winnerIndex;

    // ========================================================
    // ROUND ALWAYS COMPLETES 13 HANDS
    // ========================================================

    if (handNumber == 13) {
      Future.delayed(
        const Duration(milliseconds: 2350),
        () {
          if (mounted) {
            handCollecting = false;
            collectingWinnerIndex = null;
            finishRound();
          }
        },
      );

      return;
    }

    // ========================================================
    // NEXT HAND
    // ========================================================

    Future.delayed(
      const Duration(milliseconds: 2350),
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
    handCollecting = false;
    collectingWinnerIndex = null;
    currentHand.clear();
    ledSuit = null;

    handNumber++;

    // Winner leads next Hand.
    currentPlayerIndex = winnerIndex;

    message =
        '${players[currentPlayerIndex].name} leads Hand $handNumber.';

    setState(() {});

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

  void learnFromCompletedRound() {
    if (!_learningLoaded) return;

    int lowestScore = players.first.score;
    for (final Player player in players) {
      if (player.score < lowestScore) lowestScore = player.score;
    }

    // V42.46: calibrate learning by final Round rank instead of treating
    // every non-winning result as equally bad. A narrow second-place finish
    // should teach a different lesson from a distant fourth-place finish.
    final List<int> rankedBotIndices = [1, 2, 3]
      ..sort((int a, int b) =>
          players[a].score.compareTo(players[b].score));

    for (int playerIndex = 1; playerIndex < 4; playerIndex++) {
      // One completed Round supplies one additional public outcome sample.
      // Keep the count bounded so persistence remains tiny and stable.
      gameOutcomeExperience[playerIndex] =
          ((gameOutcomeExperience[playerIndex] ?? 0) + 1).clamp(0, 200);

      final int score = players[playerIndex].score;
      final int rank = rankedBotIndices.indexOf(playerIndex);
      final double rankOutcome = switch (rank) {
        0 => 1.0,
        1 => 0.25,
        2 => -0.50,
        _ => -1.0,
      };
      final double scoreGap =
          ((score - lowestScore).clamp(0, 35) / 35.0);
      final double outcome = rank == 0
          ? 1.0
          : (rankOutcome - (scoreGap * 0.35)).clamp(-1.0, 1.0);
      final double oldValue = gameOutcomeWeights[playerIndex] ?? 0.0;
      gameOutcomeWeights[playerIndex] =
          ((oldValue * 0.90) + (outcome * 0.10)).clamp(-8.0, 8.0).toDouble();

      final Map<String, double> memory =
          learnedDecisionWeights[playerIndex] ?? <String, double>{};
      final double calibration = gameOutcomeWeights[playerIndex]! * 0.01;
      memory.updateAll((String key, double value) =>
          (value + calibration).clamp(-8.0, 8.0).toDouble());
      learnedDecisionWeights[playerIndex] = memory;
    }

    _saveAdaptiveLearning();
  }

  double scoreGameLevelLearning(
    int playerIndex,
    CardModel candidate, {
    required bool winning,
    required bool leading,
  }) {
    if (!_learningLoaded) return 0.0;

    final double gameWeight = gameOutcomeWeights[playerIndex] ?? 0.0;
    if (gameWeight == 0.0) return 0.0;

    // V42.45: confidence ramps in gradually. A BOT with only one or two
    // completed Rounds should not suddenly rewrite its strategy because of
    // one unusual result. The model becomes fully trusted after 10 Rounds.
    final int experience = gameOutcomeExperience[playerIndex] ?? 0;
    final double confidence = (experience / 10.0).clamp(0.0, 1.0);
    if (confidence == 0.0) return 0.0;

    final double learned = scoreLearnedExperience(
      playerIndex,
      candidate,
      winning: winning,
      leading: leading,
    );

    final double multiplier = 1.0 + (gameWeight * 0.05 * confidence);
    return learned * (multiplier - 1.0);
  }


  void finishRound() {
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

    // V42.44: learn from the complete Round result.
    learnFromCompletedRound();

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

  void startNextRound() {
    if (spadeQueenCollector == null) {
      message =
          '♠Q collector was not found.';
      setState(() {});
      return;
    }

    roundNumber++;

    // ♠Q collector becomes dealer.
    dealerIndex = spadeQueenCollector!;

    // Reset Hands won for the new Round.
    for (Player player in players) {
      player.handsWon = 0;
    }

    roundFinished = false;

    dealRound();

    setState(() {});
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

  Widget buildCard(
    CardModel card, {
    required bool exchangeMode,
  }) {
    final bool selected =
        selectedExchangeCards.contains(card);

    // During normal play, lift every card that is currently legal.
    // This gives the player an immediate visual cue about what can
    // be played without changing the underlying game rules.
    final bool playableNow =
        gameStarted &&
        !exchangeMode &&
        !roundFinished &&
        currentPlayerIndex == 0 &&
        isLegalCard(0, card);

    final bool red =
        card.suit == 'Hearts' ||
        card.suit == 'Diamonds';

    final Color suitColor =
        red ? const Color(0xffb42318) : const Color(0xff17202a);

    final double lift =
        selected
            ? -0.11
            : playableNow
                ? -0.055
                : 0.0;

    return GestureDetector(
      onTap: () {
        if (exchangeMode) {
          toggleExchangeCard(card);
        } else {
          playHumanCard(card);
        }
      },
      child: AnimatedScale(
        scale: selected ? 1.055 : (playableNow ? 1.01 : 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: Offset(0, lift),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
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
                  Color(0xfff7f5f0),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xffb58b2a)
                    : const Color(0xffd7d2c8),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: selected ? 0.24 : 0.14,
                  ),
                  blurRadius: selected ? 10 : 6,
                  spreadRadius: selected ? 1 : 0,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Simple classic card face: rank at top-left.
                Positioned(
                  left: 8,
                  top: 7,
                  child: Text(
                    card.rank,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: suitColor,
                    ),
                  ),
                ),

                // One single suit symbol in the centre.
                Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: selected ? 43 : 40,
                      height: 1,
                      color: suitColor,
                      fontWeight: FontWeight.w500,
                    ),
                    child: Text(card.symbol),
                  ),
                ),

                // Smooth selection indicator.
                Positioned(
                  right: 5,
                  top: 5,
                  child: AnimatedScale(
                    scale: selected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutBack,
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
                  startNewGame();
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
                          player.name == 'YOU' ? 'YOU' : player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: player.name == 'YOU'
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
    bool red = played.card.suit == 'Hearts' ||
        played.card.suit == 'Diamonds';

    return Container(
      width: 72,
      height: 92,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26),
        boxShadow: const [
          BoxShadow(
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            players[played.playerIndex].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            played.card.rank,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: red ? Colors.red : Colors.black,
            ),
          ),
          Text(
            played.card.symbol,
            style: TextStyle(
              fontSize: 24,
              color: red ? Colors.red : Colors.black,
            ),
          ),
        ],
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTurn ? const Color(0xffe3c27a) : Colors.white.withValues(alpha: 0.18),
          width: isTurn ? 1.6 : 1,
        ),
        color: isTurn ? const Color(0xffd4af63).withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.13),
        boxShadow: isTurn ? [BoxShadow(color: const Color(0xffd4af63).withValues(alpha: 0.14), blurRadius: 12)] : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(position == 'bottom' ? Icons.account_circle_outlined : Icons.person_outline, size: 17, color: isTurn ? const Color(0xfff0d48e) : Colors.white70),
          const SizedBox(width: 5),
          Text(player.name, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: isTurn ? FontWeight.w800 : FontWeight.w600)),
          if (isDealer) ...[const SizedBox(width: 5), const Text('D', style: TextStyle(color: Color(0xffe3c27a), fontSize: 10, fontWeight: FontWeight.w800))],
          if (player.eliminated) ...[const SizedBox(width: 5), const Text('OUT', style: TextStyle(color: Color(0xffffb4b4), fontSize: 9, fontWeight: FontWeight.w800))],
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

      return SizedBox(
        width: 84,
        height: 98,
        child: Center(
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(
              begin: const Offset(0, 0),
              end: handCollecting
                  ? collectionTarget
                  : const Offset(0, 0),
            ),
            duration: const Duration(milliseconds: 1800),
            curve: Curves.easeInOutCubic,
            builder: (context, offset, child) {
              return Transform.translate(
                offset: Offset(offset.dx * 34, offset.dy * 32),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 1800),
                  curve: Curves.easeInCubic,
                  opacity: handCollecting ? 0.18 : 1.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutBack,
                    scale: isWinnerCard ? 1.10 : 1.0,
                    child: child,
                  ),
                ),
              );
            },
            child: cardWidget,
          ),
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
            Text('LED  $ledSymbol', style: TextStyle(color: ledSuit == 'Hearts' || ledSuit == 'Diamonds' ? const Color(0xffffc4c4) : Colors.white70, fontSize: 10, fontWeight: FontWeight.w600))
          else
            const Text('NO SUIT LED', style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 0.7)),
          const SizedBox(height: 4),
          Text(
              '${currentHand.length} / 4 CARDS',              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 0.8,
              ),
            ),
        ],
      ),
    );

    return Container(        margin: const EdgeInsets.symmetric(vertical: 2),
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

    return Card(
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

              return Container(
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
                    Text(
                      '${player.score}',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: player.score >= 100
                            ? Colors.red
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('pts'),
                  ],
                ),
              );
            }),

            const SizedBox(height: 8),
            Container(
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
              onPressed: startNewGame,
              child: const Text('NEW GAME'),
            ),
          ],
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
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
                      const Expanded(
                        child: Text(
                          'BREY RULE BOOK',
                          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
                          title: 'NEW RULE — ALL 35 POINTS IN ONE HAND',
                          explanation: 'If one player collects ALL 35 penalty points in a single Hand, that player gets 0 points for that Hand. This is a special reward for taking all the penalties at once.',
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
                          'The player who wins a Hand collects all penalty points in that Hand. SPECIAL RULE: if that player collects all 35 penalty points in one Hand, the Hand gives them 0 points instead of 35.',
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
                          '16. ELIMINATION & CHAMPION',
                          'A player reaching 100 or more points is eliminated after that Hand is scored. They continue playing normally until the Round ends. More than one player can be eliminated in the same Round. After all 13 Hands, the player or players with the lowest final score are the BREY Champion(s). Ties for the lowest score are allowed.',
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
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: Color(0xff172554))),
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

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
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
      startNewGame();
      return;
    }

    if (action == 'exit') {
      await SystemNavigator.pop();
    }
  }

  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    // ========================================================
    // START SCREEN
    // ========================================================

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
                          onPressed: startNewGame,
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

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

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

              if (roundFinished)
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


