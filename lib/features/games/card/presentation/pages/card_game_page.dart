import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CardGamePage extends StatefulWidget {
  final String connectionId;
  final String currentUserId;

  const CardGamePage({
    super.key,
    required this.connectionId,
    required this.currentUserId,
  });

  @override
  State<CardGamePage> createState() => _CardGamePageState();
}

class _CardGamePageState extends State<CardGamePage> {
  String? _gameId;
  Map<String, dynamic>? _gameState;
  StreamSubscription? _gameSubscription;
  bool _isProcessingMove = false;
  
  // Animation State
  String? _roundWinnerId; 
  bool _showRoundResult = false;
  bool _isDealing = false;
  List<Widget> _dealingWidgets = [];
  
  static const String _tieUUID = '00000000-0000-0000-0000-000000000000';

  final List<String> _fullDeck = [
    '2', '3', '4', '5', '6', '7', '8', '9', '10', 'vale', 'kız', 'papaz', 'as'
  ];

  final Map<String, int> _cardPower = {
    '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, 
    '8': 8, '9': 9, '10': 10, 'vale': 11, 'kız': 12, 'papaz': 13, 'as': 14
  };

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    try {
      final existingGame = await Supabase.instance.client
          .from('card_games')
          .select()
          .or('player1_id.eq.${widget.currentUserId},player2_id.eq.${widget.currentUserId}')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingGame != null && existingGame['winner_id'] == null) {
        _gameId = existingGame['id'];
      } else {
        await _createGame();
      }

      if (_gameId != null) {
        _subscribeToGame(_gameId!);
      }
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _createGame() async {
    try {
      final conn = await Supabase.instance.client
          .from('connections')
          .select()
          .eq('id', widget.connectionId)
          .single();
          
      final p1 = conn['requester_id'];
      final p2 = conn['receiver_id'];
      
      List<String> fullDeck52 = [];
      for(var card in _fullDeck) {
        for(int i=0; i<4; i++) fullDeck52.add(card);
      }
      fullDeck52.shuffle();
      
      final p1Hand = fullDeck52.take(4).toList();
      final p2Hand = fullDeck52.skip(4).take(4).toList();
      
      final res = await Supabase.instance.client.from('card_games').insert({
        'player1_id': p1,
        'player2_id': p2,
        'player1_hand': p1Hand,
        'player2_hand': p2Hand,
        'current_turn': p1, 
        'round_count': 1,
        'scores': {'player1': 0, 'player2': 0}, // Explicit init
      }).select().single();
      
      _gameId = res['id'];
    } catch (e) {
      debugPrint("Create Game Error: $e");
    }
  }

  void _subscribeToGame(String gameId) {
    _gameSubscription = Supabase.instance.client
        .from('card_games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .listen((data) {
          if (data.isNotEmpty) {
            final newState = data.first;
            
            // Check for Game Reset triggered by "Tekrar Oyna"
            if (_gameState != null && 
                _gameState!['winner_id'] != null && 
                newState['winner_id'] == null && 
                newState['round_count'] == 1) {
              _playDealingAnimation();
            }

            _checkForRoundCompletion(newState);
            if (mounted) {
              setState(() {
                _gameState = newState;
              });
            }
          }
        });
  }

  void _playDealingAnimation() async {
    setState(() {
      _isDealing = true;
      _dealingWidgets = [];
    });
    
    // Create 8 cards at center initially
    List<Widget> tempWidgets = [];
    for(int i=0; i<8; i++) {
      tempWidgets.add(
         AnimatedPositioned(
           key: ValueKey('deal_$i'),
           duration: const Duration(milliseconds: 500),
           curve: Curves.easeOutBack,
           left: MediaQuery.of(context).size.width / 2 - 35, // Centered (card width ~70)
           top: MediaQuery.of(context).size.height / 2 - 50,
           child: Image.asset('assets/images/arka.png', width: 70),
         )
      );
    }
    setState(() => _dealingWidgets = tempWidgets);
    
    // Animate them one by one
    // Target positions:
    // Me (Bottom): Approx bottom: 50, left: center
    // Opp (Top): Approx top: -20, left: center
    
    // Order: One to me, One to Opp
    // If I am P1: 0->Me, 1->Opp
    // If I am P2: 0->Opp, 1->Me
    // This strictly implies "Me" gets one, "Opp" gets one visually.
    
    final bool amIP1 = _isPlayer1();
    
    for (int i=0; i<8; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Determine target
        // even i -> First dealt -> goes to P1
        // odd i -> Second dealt -> goes to P2
        
        bool cardForP1 = (i % 2 == 0);
        bool cardIsMine = (amIP1 && cardForP1) || (!amIP1 && !cardForP1);
        
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        // Spread them out slightly in hand
        double offsetX = (i ~/ 2) * 20.0 - 40.0; 

        double targetLeft = (screenWidth / 2) - 35 + offsetX;
        double targetTop;
        
        if (cardIsMine) {
           targetTop = screenHeight - 150; // Near bottom
        } else {
           targetTop = 50; // Near top
        }

        setState(() {
          _dealingWidgets[i] = AnimatedPositioned(
             key: ValueKey('deal_$i'),
             duration: const Duration(milliseconds: 600),
             curve: Curves.easeOutCubic,
             left: targetLeft,
             top: targetTop,
             child: Image.asset('assets/images/arka.png', width: 70)
                 .animate()
                 .scale(end: const Offset(1, 1)), // Ensure scale
          );
        });
    }
    
    await Future.delayed(const Duration(milliseconds: 600));
    
    if (mounted) {
      setState(() {
        _isDealing = false;
        _dealingWidgets = [];
      });
    }
  }

  void _checkForRoundCompletion(Map<String, dynamic> newState) {
    // ... logic same as before
    final roundCards = newState['current_round_cards'] as Map;
    if (roundCards.length == 2 && _roundWinnerId == null) {
        _performRoundEvaluation(newState);
    }
    if (_gameState != null && newState['round_count'] > _gameState!['round_count']) {
       setState(() {
         _roundWinnerId = null;
         _showRoundResult = false;
       });
    }
  }

  Future<void> _playCard(String card, int index) async {
    if (_isProcessingMove) return;
    if (_gameState == null) return;
    
    // VALIDATIONS
    if (_gameState!['winner_id'] != null) return;
    
    // Turn check: If it's my turn OR I haven't played yet in this round (async handling)
    // But strictly: Only play if current_turn is ME.
    // Exception: If both played, wait.
    if (_gameState!['current_turn'] != widget.currentUserId) {
      // Small edge case: If opponent played and switched turn to me, I can play.
      return;
    }
    
    final currentRoundCards = Map<String, dynamic>.from(_gameState!['current_round_cards']);
    // If I already played, block.
    if (currentRoundCards.containsKey(widget.currentUserId)) return;

    setState(() => _isProcessingMove = true);

    try {
      List<dynamic> myHand = List.from(_isPlayer1() ? _gameState!['player1_hand'] : _gameState!['player2_hand']);
      myHand.removeAt(index);

      currentRoundCards[widget.currentUserId] = card;
      
      // LOGIC:
      // If opponent also played (cards.length == 2), we DO NOT change current_turn.
      // We leave it as is (or keep it as me) because the round is effectively over.
      // The listener will trigger evaluation.
      // If opponent hasn't played, we switch turn to them.
      
      String? nextTurn = _gameState!['current_turn'];
      
      if (currentRoundCards.length < 2) {
        // Switch turn
        nextTurn = (widget.currentUserId == _gameState!['player1_id']) 
            ? _gameState!['player2_id'] 
            : _gameState!['player1_id'];
      }
      
      // If cards == 2, we keep 'nextTurn' as is (my ID) or doesn't matter, 
      // because listener checks cards.length. 
      // Important: Don't set it to 'evaluating' (UUID error).

      await Supabase.instance.client.from('card_games').update({
        _isPlayer1() ? 'player1_hand' : 'player2_hand': myHand,
        'current_round_cards': currentRoundCards,
        'current_turn': nextTurn,
      }).eq('id', _gameId!);
      
    } catch (e) {
      debugPrint('Play error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hata oluştu, tekrar dene.')));
    } finally {
      setState(() => _isProcessingMove = false);
    }
  }
  
  void _performRoundEvaluation(Map<String, dynamic> game) async {
     try {
       final roundCards = game['current_round_cards'];
       
       if (!roundCards.containsKey(game['player1_id']) || !roundCards.containsKey(game['player2_id'])) return;

       final c1 = roundCards[game['player1_id']];
       final c2 = roundCards[game['player2_id']];
       
       final val1 = _cardPower[c1]!;
       final val2 = _cardPower[c2]!;
       
       String? localWinner;
       if (val1 > val2) localWinner = game['player1_id'];
       else if (val2 > val1) localWinner = game['player2_id'];
       
       if (mounted) {
         setState(() {
           _roundWinnerId = localWinner;
           _showRoundResult = true;
         });
       }
       
       // Authority: The player who HAS THE TURN (active user) handles the update.
       // Because we didn't switch turn when 2nd card was played, current_turn == Last Player.
       if (widget.currentUserId == game['current_turn']) {
           await Future.delayed(const Duration(seconds: 3));
          
           Map<String, dynamic> scores = Map.from(game['scores'] ?? {'player1': 0, 'player2': 0});
           if (val1 > val2) scores['player1'] = (scores['player1'] ?? 0) + 1;
           else if (val2 > val1) scores['player2'] = (scores['player2'] ?? 0) + 1;
           
           int nextRound = game['round_count'] + 1;
           String? gameWinnerId;
           
           if (nextRound > 4) {
             final s1 = scores['player1'];
             final s2 = scores['player2'];
             if (s1 > s2) gameWinnerId = game['player1_id'];
             else if (s2 > s1) gameWinnerId = game['player2_id'];
             else gameWinnerId = null; // Tie case: Winner remains null, but round > 4
           }
           
           final nextTurn = localWinner ?? game['player1_id'];

           await Supabase.instance.client.from('card_games').update({
             'scores': scores,
             'current_round_cards': {},
             'round_count': nextRound,
             'current_turn': nextTurn,
             'winner_id': gameWinnerId,
           }).eq('id', game['id']);
       }
     } catch (e) {
       debugPrint("Evaluation Error: $e");
     }
  }

  Future<void> _resetGame() async {
     List<String> fullDeck52 = [];
     for(var card in _fullDeck) {
       for(int i=0; i<4; i++) fullDeck52.add(card);
     }
     fullDeck52.shuffle();
     
     final p1Hand = fullDeck52.take(4).toList();
     final p2Hand = fullDeck52.skip(4).take(4).toList();

     await Supabase.instance.client.from('card_games').update({
       'player1_hand': p1Hand,
       'player2_hand': p2Hand,
       'current_round_cards': {},
       'scores': {'player1': 0, 'player2': 0},
       'round_count': 1,
       'winner_id': null,
       'current_turn': _gameState!['player1_id'], 
     }).eq('id', _gameId!);
     
     setState(() {
       _roundWinnerId = null;
       _showRoundResult = false;
     });
  }

  bool _isPlayer1() => _gameState != null && _gameState!['player1_id'] == widget.currentUserId;

  @override
  Widget build(BuildContext context) {
    if (_gameState == null) {
      return const Scaffold(backgroundColor: Color(0xFF1A4D2E), body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    // HANDS
    final rawP1Hand = _gameState!['player1_hand'] ?? [];
    final rawP2Hand = _gameState!['player2_hand'] ?? [];
    
    final myHand = List<String>.from(_isPlayer1() ? rawP1Hand : rawP2Hand);
    final oppHand = List<String>.from(!_isPlayer1() ? rawP1Hand : rawP2Hand);
    
    // SCORES
    final scores = _gameState!['scores'] ?? {'player1': 0, 'player2': 0};
    final myScore = _isPlayer1() ? (scores['player1'] ?? 0) : (scores['player2'] ?? 0);
    final oppScore = !_isPlayer1() ? (scores['player1'] ?? 0) : (scores['player2'] ?? 0);
    
    // CARDS ON TABLE
    final roundCards = _gameState!['current_round_cards'] ?? {};
    final myPlayedCard = roundCards[widget.currentUserId];
    
    final p1Id = _gameState!['player1_id'];
    final p2Id = _gameState!['player2_id'];
    final oppId = !_isPlayer1() ? p1Id : p2Id;
    final oppPlayedCard = roundCards[oppId];
    
    final winnerId = _gameState!['winner_id'];
    final int roundCount = _gameState!['round_count'] ?? 1;
    final bool isGameOver = (winnerId != null) || (roundCount > 4);

    final dbSaysMyTurn = _gameState!['current_turn'] == widget.currentUserId;
    final iPlayed = roundCards.containsKey(widget.currentUserId);
    final isMyTurn = dbSaysMyTurn && !iPlayed && !isGameOver;

    final roundComplete = roundCards.length == 2;
    
    final bool iWonRound = _roundWinnerId == widget.currentUserId;
    final bool oppWonRound = _roundWinnerId == oppId;

    return Scaffold(
      backgroundColor: const Color(0xFF1A4D2E),
      appBar: AppBar(
        title: Text('Kart Savaşı - Round ${roundCount > 4 ? 4 : roundCount}/4', style: GoogleFonts.poppins(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Opponent Hand (Top)
          Positioned(
            top: -60,
            left: 0, right: 0,
            child: AnimatedOpacity(
               duration: const Duration(milliseconds: 300),
               opacity: _isDealing ? 0 : 1,
               child: SizedBox(
                  height: 160,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: List.generate(oppHand.length, (index) {
                        final angle = (index - (oppHand.length - 1) / 2) * 0.1;
                        return Transform.translate(
                          offset: Offset(index * 20.0 - (oppHand.length * 10), 0),
                          child: Transform.rotate(
                            angle: angle, 
                            child: Image.asset('assets/images/arka.png', width: 70),
                          ),
                        );
                      }),
                    ),
                  ),
               ),
            ),
          ),
          
          // Opponent Score
          Positioned(
            top: 60, right: 20,
            child: _ScoreBadge(score: oppScore, isMe: false, isHighlight: oppWonRound),
          ),

          // My Score
          Positioned(
            bottom: 230, right: 20,
            child: _ScoreBadge(score: myScore, isMe: true, isHighlight: iWonRound),
          ),
          
          // Battle Area
          Stack(
            children: [
               if (oppPlayedCard != null)
                 AnimatedAlign(
                   duration: const Duration(milliseconds: 600),
                   curve: Curves.easeInOutBack,
                   alignment: _roundWinnerId != null 
                        ? (iWonRound ? Alignment.bottomRight : Alignment.topRight) 
                        : const Alignment(-0.35, -0.2), 
                   child: _BattleCard(cardName: oppPlayedCard)
                     .animate(target: _roundWinnerId != null ? 1 : 0)
                     .scale(end: const Offset(0.5, 0.5)) 
                     .fadeOut(delay: 500.ms),
                 ),
                 
               if (myPlayedCard != null)
                 AnimatedAlign(
                   duration: const Duration(milliseconds: 600),
                   curve: Curves.easeInOutBack,
                   alignment: _roundWinnerId != null 
                        ? (iWonRound ? Alignment.bottomRight : Alignment.topRight) 
                        : const Alignment(0.35, 0.2), 
                   child: _BattleCard(cardName: myPlayedCard)
                     .animate(target: _roundWinnerId != null ? 1 : 0)
                     .scale(end: const Offset(0.5, 0.5))
                     .fadeOut(delay: 500.ms),
                 ),
            ],
          ),

          // Dealing Animation Overlay
          if (_isDealing)
             Stack(children: _dealingWidgets),

          // Status Text
          Center(
             child: Text(
               isGameOver 
                 ? (winnerId != null 
                      ? (winnerId == widget.currentUserId ? "Kazandın! 🎉" : "Kaybettin 😔")
                      : "Berabere!")
                 : (_roundWinnerId != null 
                     ? (iWonRound ? "Bu eli sen aldın!" : "Bu eli eşin aldı!")
                     : (isMyTurn 
                         ? "Sıra Sende" 
                         : (roundComplete ? "Sonuçlar..." : "Eşin Bekleniyor..."))),
               style: GoogleFonts.poppins(
                 color: Colors.white,
                 fontSize: 24,
                 fontWeight: FontWeight.bold,
                 shadows: [const Shadow(blurRadius: 10, color: Colors.black)]
               ),
             ).animate(target: _roundWinnerId != null ? 1 : 0).scale(duration: 400.ms, curve: Curves.elasticOut),
          ),

          // My Hand (Bottom)
          Positioned(
            bottom: 10,
            left: 0, right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isDealing ? 0 : 1,
              child: SizedBox(
                height: 220, // Increased to prevent clipping
                child: Center(
                  child: Stack(
                     alignment: Alignment.center,
                     children: List.generate(myHand.length, (index) {
                       final card = myHand[index];
                       final angle = (index - (myHand.length - 1) / 2) * 0.15;
                       final offsetX = (index - (myHand.length - 1) / 2) * 45.0; 
                       final offsetY = (index - (myHand.length - 1) / 2).abs() * 15.0; 
            
                       return AnimatedPositioned(
                         duration: const Duration(milliseconds: 300),
                         left: (MediaQuery.of(context).size.width / 2) + offsetX - 50, 
                         bottom: 50 - offsetY + (isMyTurn ? 30 : 0),
                         child: GestureDetector(
                           onTap: () => isMyTurn ? _playCard(card, index) : null,
                           child: Transform.rotate(
                             angle: angle,
                             child: _PlayerCard(cardName: card, isSelected: isMyTurn),
                           ),
                         ),
                       );
                     }),
                  ),
                ),
              ),
            ),
          ),
          
          if (isGameOver)
             Positioned.fill(
               child: Container(
                 color: Colors.black54,
                 child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          winnerId != null 
                            ? (winnerId == widget.currentUserId ? "Tebrikler Aşkım!" : "Oyun Bitti")
                            : "Dostluk Kazandı!",
                          style: GoogleFonts.dancingScript(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _resetGame,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE91E63), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                          child: const Text("Tekrar Oyna", style: TextStyle(fontSize: 20)),
                        )
                      ],
                    ),
                 ),
               ).animate().fadeIn(),
             )
        ],
      ),
    );

  }
}

class _BattleCard extends StatelessWidget {
  final String cardName;
  const _BattleCard({required this.cardName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 85, // Reduced from 100
      height: 125, // Reduced from 150
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/images/$cardName.png', fit: BoxFit.contain), 
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final String cardName;
  final bool isSelected;
  const _PlayerCard({required this.cardName, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 85, // Reduced from 95
      height: 125, // Reduced from 140
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: isSelected ? Border.all(color: Colors.yellowAccent, width: 4) : Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4), 
            blurRadius: 8, 
            offset: const Offset(2, 4)
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset('assets/images/$cardName.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final bool isMe;
  final bool isHighlight;

  const _ScoreBadge({required this.score, required this.isMe, required this.isHighlight});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      // ...
      decoration: BoxDecoration(
        color: isHighlight ? Colors.amber : Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white30),
        boxShadow: isHighlight ? [const BoxShadow(color: Colors.amber, blurRadius: 10)] : []
      ),
      child: Text(
        '${isMe ? "Ben" : "Eşin"}: $score',
        style: TextStyle(color: isHighlight ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}
