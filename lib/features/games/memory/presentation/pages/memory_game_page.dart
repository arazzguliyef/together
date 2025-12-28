import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'dart:math';

class MemoryGamePage extends StatefulWidget {
  final String connectionId;
  final String currentUserId;

  const MemoryGamePage({
    super.key,
    required this.connectionId,
    required this.currentUserId,
  });

  @override
  State<MemoryGamePage> createState() => _MemoryGamePageState();
}

class _MemoryGamePageState extends State<MemoryGamePage> {
  // Game State
  Map<String, dynamic>? _gameState;
  StreamSubscription<List<Map<String, dynamic>>>? _gameStream;
  bool _isLoading = true;
  bool _isProcessing = false; // To prevent double taps locally or while processing mismatch
  
  // Assests (Emojis for cards) - 18 pairs
  static const List<String> _emojis = [
    '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', 
    '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', 
    '🥭', '🍍', '🥥', '🥝', '🍅', '🥑'
  ];

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void dispose() {
    _gameStream?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    try {
      final existingGame = await Supabase.instance.client
          .from('memory_games')
          .select()
          .eq('connection_id', widget.connectionId)
          .maybeSingle();

      if (existingGame == null) {
        final connection = await Supabase.instance.client
            .from('connections')
            .select()
            .eq('id', widget.connectionId)
            .single();

        // Create new board
        final board = _generateBoard();
        
        // Player 1 starts
        await Supabase.instance.client.from('memory_games').insert({
          'connection_id': widget.connectionId,
          'player1_id': connection['requester_id'],
          'player2_id': connection['receiver_id'],
          'current_turn': connection['requester_id'],
          'starting_player': connection['requester_id'],
          'board': board,
          'flipped_indices': [],
        });
      }
    } catch (e) {
      debugPrint('Error initializing Memory: $e');
    }

    _gameStream = Supabase.instance.client
        .from('memory_games')
        .stream(primaryKey: ['id'])
        .eq('connection_id', widget.connectionId)
        .listen((data) {
          if (data.isNotEmpty) {
            _handleGameUpdate(data.first);
          }
        });
  }
  
  List<Map<String, dynamic>> _generateBoard() {
    List<String> deck = [..._emojis, ..._emojis]; // 18 * 2 = 36 cards
    deck.shuffle(Random());
    
    return List.generate(36, (index) => {
      'id': index,
      'value': deck[index],
      'isMatched': false,
      'isFlipped': false,
    });
  }

  void _handleGameUpdate(Map<String, dynamic> newState) {
    if (!mounted) return;
    
    setState(() {
      _gameState = newState;
      _isLoading = false;
    });

    // Check game over
    if (newState['winner_id'] != null) {
      _showGameOverDialog(winnerId: newState['winner_id']);
    } else {
      // Check if there are 2 flipped cards that are NOT matched, which means we might need to process a mismatch flip-back
      // But wait! logic for flip-back should be handled by the client that made the move.
      // If I am the current turn player, and I see 2 cards flipped in 'flipped_indices', I check logic.
    }
  }

  Future<void> _onCardTap(int index) async {
    if (_gameState == null || _isProcessing) return;
    
    // Check turn
    if (_gameState!['current_turn'] != widget.currentUserId) return;

    // Create mutable copies for optimistic update
    final Map<String, dynamic> currentState = Map<String, dynamic>.from(_gameState!);
    final List<dynamic> board = List.from(currentState['board']);
    
    // Check if card is valid
    if (board[index]['isMatched'] || board[index]['isFlipped']) return;

    final List<dynamic> flippedIndices = List.from(currentState['flipped_indices'] ?? []);
    
    // Check limit
    if (flippedIndices.length >= 2) return;

    _isProcessing = true; // Block immediately

    // Apply Optimistic Update
    final newCard = Map<String, dynamic>.from(board[index]);
    newCard['isFlipped'] = true;
    board[index] = newCard;
    
    flippedIndices.add(index);
    
    currentState['board'] = board;
    currentState['flipped_indices'] = flippedIndices;

    setState(() {
      _gameState = currentState;
    });

    // Update DB
    try {
      await Supabase.instance.client.from('memory_games').update({
        'board': board,
        'flipped_indices': flippedIndices,
      }).eq('id', _gameState!['id']);
      
      // Logic for 2 cards
      if (flippedIndices.length == 2) {
        await _handleTwoCardsFlipped(flippedIndices, board);
      } else {
        _isProcessing = false; // Allow second card
      }
      
    } catch (e) {
      debugPrint("Error msg: $e");
      _isProcessing = false;
      // Optionally revert state here, or wait for stream to fix it
    }
  }
  
  Future<void> _handleTwoCardsFlipped(List<dynamic> indices, List<dynamic> board) async {
    final idx1 = indices[0] as int;
    final idx2 = indices[1] as int;
    
    final card1 = board[idx1];
    final card2 = board[idx2];
    
    final isMatch = card1['value'] == card2['value'];
    
    if (isMatch) {
      // MATCH!
      // Mark matched, clear flipped, keep turn, increment score
      await Future.delayed(const Duration(milliseconds: 500)); // Short delay to enjoy match
      
      board[idx1]['isMatched'] = true;
      board[idx2]['isMatched'] = true;
      // Keep isFlipped true for visual, or standard is usually keep them face up.
      
      final isP1 = (_gameState!['player1_id'] == widget.currentUserId);
      int p1Score = _gameState!['player1_score'];
      int p2Score = _gameState!['player2_score'];
      
      if (isP1) p1Score++; else p2Score++;
      
      // Check win condition
      final allMatched = board.every((c) => c['isMatched'] == true);
      String? winnerId;
      
      if (allMatched) {
        if (p1Score > p2Score) winnerId = _gameState!['player1_id'];
        else if (p2Score > p1Score) winnerId = _gameState!['player2_id'];
        else {
             // Tie? Special handling? Usually treat as tie or draw.
             // But DB expects UUID for winner_id. Let's create an is_draw field later or reuse logic.
             // For now simplest: Null winner but game over logic in UI handles scores.
             // Or update 'winner_id' if score > other.
             // The table schema has winner_id.
        }
      }

      await Supabase.instance.client.from('memory_games').update({
        'board': board,
        'flipped_indices': [], // Clear flipped
        'player1_score': p1Score,
        'player2_score': p2Score,
        'winner_id': winnerId, // Only set if game over
      }).eq('id', _gameState!['id']);
      
      _isProcessing = false;

    } else {
      // NO MATCH
      // Wait, then flip back, switch turn
      await Future.delayed(const Duration(seconds: 1)); // Wait 1 sec to see cards
      
      board[idx1]['isFlipped'] = false;
      board[idx2]['isFlipped'] = false;
      
      final nextTurn = (_gameState!['current_turn'] == _gameState!['player1_id'])
          ? _gameState!['player2_id']
          : _gameState!['player1_id'];
          
      await Supabase.instance.client.from('memory_games').update({
        'board': board,
        'flipped_indices': [],
        'current_turn': nextTurn,
      }).eq('id', _gameState!['id']);
      
      _isProcessing = false;
    }
  }

  void _showGameOverDialog({String? winnerId}) async {
    // If scores are equal, winnerId might be null or handled as tie
    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    final myScore = isP1 ? _gameState!['player1_score'] : _gameState!['player2_score'];
    final opScore = isP1 ? _gameState!['player2_score'] : _gameState!['player1_score'];
    
    String title;
    String content;
    Color color;
    
    if (winnerId == null && myScore == opScore) {
       title = 'Berabere!';
       content = 'Dostluk kazandı!';
       color = Colors.orange;
    } else {
       final isMe = winnerId == widget.currentUserId;
       title = isMe ? 'Kazandın!' : 'Kaybettin!';
       content = isMe ? 'Harika hafıza!' : 'Bir dahaki sefere...';
       color = isMe ? Colors.green : Colors.red;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: Text('$content\nSkor: $myScore - $opScore', textAlign: TextAlign.center),
      ),
    );

    // WINNER starts next game
    // If I am the winner (or P1 in case of tie/draw logic default), I reset after 3s
    bool shouldReset = (winnerId == widget.currentUserId) || (winnerId == null && isP1);
    
    if (shouldReset) {
      await Future.delayed(const Duration(seconds: 4));
      _resetGame();
    }
  }
  
  Future<void> _resetGame() async {
    final nextStarter = (_gameState!['winner_id'] != null) 
        ? _gameState!['winner_id']
        : _gameState!['starting_player']; // Or keep same starter? usually winner starts.

    final newBoard = _generateBoard();
    
    try {
      await Supabase.instance.client.from('memory_games').update({
        'board': newBoard,
        'player1_score': 0,
        'player2_score': 0,
        'flipped_indices': [],
        'winner_id': null,
        'current_turn': nextStarter,
        'starting_player': nextStarter,
      }).eq('id', _gameState!['id']);
    } catch (e) {
      debugPrint('Reset error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _gameState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    final myScore = isP1 ? _gameState!['player1_score'] : _gameState!['player2_score'];
    final opScore = isP1 ? _gameState!['player2_score'] : _gameState!['player1_score'];
    final isMyTurn = _gameState!['current_turn'] == widget.currentUserId;
    
    final List<dynamic> boardData = _gameState!['board'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Hafıza Oyunu', style: GoogleFonts.dancingScript(fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE91E63)),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
             // Score Board
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPlayerInfo(isMe: true, score: myScore as int, turn: isMyTurn),
                 const Text("VS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey)),
                _buildPlayerInfo(isMe: false, score: opScore as int, turn: !isMyTurn),
              ],
            ),
            const SizedBox(height: 16),
            
            // Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 0.85,
                ),
                itemCount: boardData.length,
                itemBuilder: (context, index) {
                  return _buildCard(index, boardData[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlayerInfo({required bool isMe, required int score, required bool turn}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: turn ? const Color(0xFFFFF0F5) : Colors.transparent,
        border: turn ? Border.all(color: const Color(0xFFFF4081), width: 2) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(isMe ? "Sen" : "Rakip", style: TextStyle(fontWeight: FontWeight.bold, color: turn ? const Color(0xFFE91E63) : Colors.grey)),
          Text("$score", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A142F))),
        ],
      ),
    ); // Removed .animate().scale() to avoid constant animation reset on setState
  }

  Widget _buildCard(int index, Map<String, dynamic> cardData) {
    final isFlipped = cardData['isFlipped'] == true;
    final isMatched = cardData['isMatched'] == true;
    final value = cardData['value'] as String;
    
    return GestureDetector(
      onTap: () => _onCardTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: (isFlipped || isMatched) ? Colors.white : const Color(0xFFE91E63),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF80AB).withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: (isFlipped || isMatched)
              ? Text(value, style: const TextStyle(fontSize: 32)).animate().scale(duration: 200.ms)
              : const Icon(Icons.question_mark_rounded, color: Colors.white70, size: 20),
        ),
      ),
    );
  }
}
