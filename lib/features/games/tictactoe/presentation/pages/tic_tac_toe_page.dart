import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';

class TicTacToePage extends StatefulWidget {
  final String connectionId;
  final String currentUserId;

  const TicTacToePage({
    super.key,
    required this.connectionId,
    required this.currentUserId,
  });

  @override
  State<TicTacToePage> createState() => _TicTacToePageState();
}

class _TicTacToePageState extends State<TicTacToePage> {
  // Game State
  Map<String, dynamic>? _gameState;
  StreamSubscription<List<Map<String, dynamic>>>? _gameStream;
  bool _isLoading = true;
  bool _isDialogShowing = false;
  
  // Board helpers
  final List<String> _localBoard = List.filled(9, '');

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
          .from('tictactoe_games')
          .select()
          .eq('connection_id', widget.connectionId)
          .maybeSingle();

      if (existingGame == null) {
        final connection = await Supabase.instance.client
            .from('connections')
            .select()
            .eq('id', widget.connectionId)
            .single();

        // Player 1 starts
        await Supabase.instance.client.from('tictactoe_games').insert({
          'connection_id': widget.connectionId,
          'player1_id': connection['requester_id'],
          'player2_id': connection['receiver_id'],
          'current_turn': connection['requester_id'], // Player 1 starts
          'board': List.filled(9, ''),
        });
      }
    } catch (e) {
      debugPrint('Error initializing TTT: $e');
    }

    _gameStream = Supabase.instance.client
        .from('tictactoe_games')
        .stream(primaryKey: ['id'])
        .eq('connection_id', widget.connectionId)
        .listen((data) {
          if (data.isNotEmpty) {
            _handleGameUpdate(data.first);
          }
        });
  }

  void _handleGameUpdate(Map<String, dynamic> newState) {
    if (!mounted) return;

    // Sync local board
    final remoteBoard = List<String>.from(newState['board']);
    
    // Check for Reset conditions (if remote board is empty but we are showing dialog or local is full)
    final isRemoteEmpty = remoteBoard.every((element) => element.isEmpty);
    
    if (isRemoteEmpty && _isDialogShowing) {
       if (Navigator.canPop(context)) Navigator.pop(context);
       _isDialogShowing = false;
    }

    setState(() {
      _gameState = newState;
      _isLoading = false;
      for (int i = 0; i < 9; i++) {
        _localBoard[i] = remoteBoard[i];
      }
    });

    // Check game over state from DB
    if (!_isDialogShowing) {
      if (newState['winner_id'] != null) {
        _showGameOverDialog(winnerId: newState['winner_id']);
      } else if (newState['is_draw'] == true) {
        _showGameOverDialog(isDraw: true);
      }
    }
  }

  Future<void> _onCellTapped(int index) async {
    if (_gameState == null || _gameState!['winner_id'] != null || _gameState!['is_draw'] == true) return;
    
    // Check turn
    if (_gameState!['current_turn'] != widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıra rakibinde!'), duration: Duration(milliseconds: 500)),
      );
      return;
    }

    // Check if empty
    if (_localBoard[index].isNotEmpty) return;

    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    final symbol = isP1 ? 'X' : 'O';

    // Optimistic Update
    setState(() {
      _localBoard[index] = symbol;
    });

    // Check Win/Draw Logic locally to update DB immediately
    final winnerId = _checkWin(_localBoard) ? widget.currentUserId : null;
    final isDraw = winnerId == null && !_localBoard.contains('');
    final nextTurn = winnerId != null || isDraw 
        ? null 
        : (isP1 ? _gameState!['player2_id'] : _gameState!['player1_id']);
    
    int p1Score = _gameState!['player1_score'] ?? 0;
    int p2Score = _gameState!['player2_score'] ?? 0;
    
    if (winnerId != null) {
      if (winnerId == _gameState!['player1_id']) p1Score++;
      else p2Score++;
    }

    try {
      final updateData = {
        'board': _localBoard,
        'current_turn': nextTurn,
        'winner_id': winnerId,
        'is_draw': isDraw,
        'player1_score': p1Score,
        'player2_score': p2Score,
      };

      await Supabase.instance.client
          .from('tictactoe_games')
          .update(updateData)
          .eq('id', _gameState!['id']);
          
    } catch (e) {
      debugPrint('Error msg: $e');
      // Revert if error? (complex to handle perfectly without reload, but realtime usually fixes it)
    }
  }

  bool _checkWin(List<String> board) {
    const wins = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // Rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // Cols
      [0, 4, 8], [2, 4, 6]             // Diagonals
    ];

    for (var win in wins) {
      if (board[win[0]].isNotEmpty &&
          board[win[0]] == board[win[1]] &&
          board[win[1]] == board[win[2]]) {
        return true;
      }
    }
    return false;
  }

  void _showGameOverDialog({String? winnerId, bool isDraw = false}) async {
    _isDialogShowing = true;
    
    String title;
    String content;
    Color color;

    if (isDraw) {
      title = 'Berabere!';
      content = 'Dostluk kazandı :)';
      color = Colors.orange;
    } else {
      final isMe = winnerId == widget.currentUserId;
      title = isMe ? 'Kazandın!' : 'Kaybettin!';
      content = isMe ? 'Tebrikler!' : 'Belki bir dahaki sefere...';
      color = isMe ? Colors.green : Colors.red;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: Text(content, textAlign: TextAlign.center),
        actions: [
          // Only show reset button if I am the one who won or it's draw (to avoid double clicks, simple rule: P1 resets)
          // Actually any player can initiate reset is fine, but lets restrict to "Any player tap to play gain"
          // We can just show a countdown or auto reset.
          // Let's do auto-reset after 3 seconds by the person who triggered the win update? 
          // No, safer if the Client who IS Player 1 resets it.
        ],
      ),
    );

    // Auto reset logic
    if (widget.currentUserId == _gameState!['player1_id']) {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        _resetGame();
      }
    }
  }

  Future<void> _resetGame() async {
    // Reset board, winner, draw. Keep scores. Next turn logic: loser starts? or alternating?
    // Simple: Winner starts? Or Player 1 starts? 
    // Let's make Player 1 start for simplicity or alternate.
    // Let's set turn to Player 1 always for now or swap if we stored who started last.
    
    // To make it fair, let's say the Loser starts the next game.
    // If draw, previous start player starts? Too complex state.
    // Let's just set turn to Player 1 for now.
    
    try {
      await Supabase.instance.client.from('tictactoe_games').update({
        'board': List.filled(9, ''),
        'winner_id': null,
        'is_draw': false,
        'current_turn': _gameState!['winner_id'] ?? _gameState!['player1_id'], // Winner starts next, or P1
      }).eq('id', _gameState!['id']);
    } catch (e) {
       debugPrint('Error resetting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _gameState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    final mySymbol = isP1 ? 'X' : 'O';
    final myScore = isP1 ? _gameState!['player1_score'] : _gameState!['player2_score'];
    final opponentScore = isP1 ? _gameState!['player2_score'] : _gameState!['player1_score'];
    final isMyTurn = _gameState!['current_turn'] == widget.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Tic-Tac-Toe', style: GoogleFonts.dancingScript(fontWeight: FontWeight.bold, fontSize: 28)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE91E63)),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Score Board
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 _buildPlayerInfo(isMe: true, score: myScore as int, symbol: mySymbol),
                 const SizedBox(width: 32),
                 const Text("VS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.grey)),
                 const SizedBox(width: 32),
                 _buildPlayerInfo(isMe: false, score: opponentScore as int, symbol: mySymbol == 'X' ? 'O' : 'X'),
              ],
            ),
            const SizedBox(height: 32),
            
            // Turn Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: isMyTurn ? const Color(0xFFE91E63) : Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isMyTurn ? "Senin Sıran!" : "Rakibin Sırası",
                style: TextStyle(
                  color: isMyTurn ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ).animate(target: isMyTurn ? 1 : 0).shimmer(),
            
            const Spacer(),
            
            // Game Grid
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  return _buildGridCell(index);
                },
              ),
            ),
            
            const Spacer(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfo({required bool isMe, required int score, required String symbol}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isMe ? const Color(0xFFE91E63) : Colors.grey,
          child: Text(symbol, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        const SizedBox(height: 8),
        Text(isMe ? "Sen" : "Rakip", style: const TextStyle(fontWeight: FontWeight.bold)),
        Text("$score", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A142F))),
      ],
    );
  }

  Widget _buildGridCell(int index) {
    final value = _localBoard[index];
    final isX = value == 'X';
    
    return GestureDetector(
      onTap: () => _onCellTapped(index),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: value.isNotEmpty
              ? Text(
                  value,
                  style: GoogleFonts.permanentMarker(
                    fontSize: 48,
                    color: isX ? const Color(0xFFE91E63) : const Color(0xFF2196F3),
                  ),
                ).animate().scale(duration: 200.ms, curve: Curves.easeOutBack)
              : null,
        ),
      ),
    );
  }
}
