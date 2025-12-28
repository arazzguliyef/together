import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';

class RockPaperScissorsPage extends StatefulWidget {
  final String connectionId;
  final String currentUserId;

  const RockPaperScissorsPage({
    super.key,
    required this.connectionId,
    required this.currentUserId,
  });

  @override
  State<RockPaperScissorsPage> createState() => _RockPaperScissorsPageState();
}

class _RockPaperScissorsPageState extends State<RockPaperScissorsPage> {
  // Game state
  Map<String, dynamic>? _gameState;
  StreamSubscription<List<Map<String, dynamic>>>? _gameStream;
  bool _isLoading = true;
  String? _resultMessage;

  // Assets or Icons for moves
  final Map<String, IconData> _moveIcons = {
    'rock': Icons.landscape_rounded, // Best approximate for rock
    'paper': Icons.note_rounded,
    'scissors': Icons.cut_rounded,
  };

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
    // 1. Check if game exists, if not create it
    try {
      final existingGame = await Supabase.instance.client
          .from('rps_games')
          .select()
          .eq('connection_id', widget.connectionId)
          .maybeSingle();

      if (existingGame == null) {
        // Fetch connection details to know who is who (optional, but good for id assignment)
        final connection = await Supabase.instance.client
            .from('connections')
            .select()
            .eq('id', widget.connectionId)
            .single();

        await Supabase.instance.client.from('rps_games').insert({
          'connection_id': widget.connectionId,
          'player1_id': connection['requester_id'],
          'player2_id': connection['receiver_id'],
        });
      }
    } catch (e) {
      debugPrint('Error initializing game: $e');
    }

    // 2. Subscribe to game changes
    _gameStream = Supabase.instance.client
        .from('rps_games')
        .stream(primaryKey: ['id'])
        .eq('connection_id', widget.connectionId)
        .listen((data) {
          if (data.isNotEmpty) {
            _handleGameUpdate(data.first);
          }
        });
  }

  bool _isDialogShowing = false;

  void _handleGameUpdate(Map<String, dynamic> newState) async {
    // Check if it's a reset (new round)
    if (newState['player1_move'] == null && newState['player2_move'] == null) {
       if (_isDialogShowing) {
         if (mounted && Navigator.canPop(context)) {
           Navigator.pop(context);
         }
         _isDialogShowing = false;
       }
    }

    setState(() {
      _gameState = newState;
      _isLoading = false;
    });

    final p1Move = _gameState!['player1_move'];
    final p2Move = _gameState!['player2_move'];

    // Check if both played AND we are not already showing a result
    if (p1Move != null && p2Move != null && !_isDialogShowing) {
      // Determine winner
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay for UX
      _determineRoundWinner(p1Move, p2Move);
    }
  }

  void _determineRoundWinner(String p1Move, String p2Move) async {
    final p1Id = _gameState!['player1_id'];
    
    // Logic: p1 vs p2
    final isImP1 = widget.currentUserId == p1Id;
    final myMove = isImP1 ? p1Move : p2Move;
    final opponentMove = isImP1 ? p2Move : p1Move;

    String result = '';
    bool iWon = false;
    bool tie = false;

    if (myMove == opponentMove) {
      result = 'Berabere!';
      tie = true;
    } else {
      if ((myMove == 'rock' && opponentMove == 'scissors') ||
          (myMove == 'paper' && opponentMove == 'rock') ||
          (myMove == 'scissors' && opponentMove == 'paper')) {
        result = 'Kazandın!';
        iWon = true;
      } else {
        result = 'Kaybettin!';
      }
    }

    setState(() {
      _resultMessage = result;
    });

    // Show result dialog
    if (mounted) {
       _isDialogShowing = true;
       showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(result, textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text("Sen"),
                      Icon(_moveIcons[myMove], size: 40, color: const Color(0xFFE91E63)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text("Rakip"),
                      Icon(_moveIcons[opponentMove], size: 40, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Only Player 1 updates the database to reset the round
    if (widget.currentUserId == p1Id) {
      await Future.delayed(const Duration(seconds: 3)); // Wait for users to see result
      
      int p1Score = _gameState!['player1_score'] ?? 0;
      int p2Score = _gameState!['player2_score'] ?? 0;

      if (!tie) {
        if (iWon) { // I am P1 and I won
          p1Score++;
        } else { // I am P1 and I lost
          p2Score++;
        }
      }

      try {
        await Supabase.instance.client.from('rps_games').update({
          'player1_move': null,
          'player2_move': null,
          'player1_score': p1Score,
          'player2_score': p2Score,
        }).eq('id', _gameState!['id']);
      } catch (e) {
        debugPrint("Error resetting game: $e");
      }
    }
  }

  Future<void> _makeMove(String move) async {
    if (_gameState == null) return;

    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    
    // Optimistic update
    setState(() {
      final updatedState = Map<String, dynamic>.from(_gameState!);
      updatedState[isP1 ? 'player1_move' : 'player2_move'] = move;
      _gameState = updatedState;
    });
    
    try {
      await Supabase.instance.client.from('rps_games').update({
        isP1 ? 'player1_move' : 'player2_move': move,
      }).eq('id', _gameState!['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error making move: $e')),
        );
        // Revert optimistic update if needed? 
        // For simplicity, we assume success or user retries. 
        // Real stream update would fix it eventually if failed but that's complex.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _gameState == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isP1 = widget.currentUserId == _gameState!['player1_id'];
    final myScore = isP1 ? _gameState!['player1_score'] : _gameState!['player2_score'];
    final opponentScore = isP1 ? _gameState!['player2_score'] : _gameState!['player1_score'];
    
    final myMove = isP1 ? _gameState!['player1_move'] : _gameState!['player2_move'];
    final opponentMove = isP1 ? _gameState!['player2_move'] : _gameState!['player1_move'];

    final opponentReady = opponentMove != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE91E63)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Taş-Kağıt-Makas',
                    style: GoogleFonts.dancingScript(
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFF80AB)),
                    ),
                    child: Text(
                      '$myScore - $opponentScore',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: const Color(0xFFE91E63),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Opponent Area (Big Box)
            Column(
              children: [
                Text(
                  'Rakip',
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: opponentReady ? const Color(0xFF69F0AE) : const Color(0xFFFFCCBC), // Green if ready, Pink/Orange if not
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      opponentReady ? Icons.check_circle_outline : Icons.pending_outlined,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ).animate(target: opponentReady ? 1 : 0).shimmer(duration: 1.seconds, color: Colors.white54),
              ],
            ),

            const Spacer(),

            // My Area
            Column(
              children: [
                if (myMove != null) ...[
                   Text(
                    'Seçimin',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  // Showing my selected move
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _moveIcons[myMove],
                      size: 40,
                      color: const Color(0xFFE91E63),
                    ),
                  ),
                  const SizedBox(height: 32),
                ] else ...[
                   Text(
                    'Hamleni Seç',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMoveButton('rock', 'Taş'),
                      _buildMoveButton('paper', 'Kağıt'),
                      _buildMoveButton('scissors', 'Makas'),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveButton(String move, String label) {
    return GestureDetector(
      onTap: () => _makeMove(move),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF80AB).withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE91E63).withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _moveIcons[move],
              size: 32,
              color: const Color(0xFFE91E63),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: const Color(0xFF4A142F),
            ),
          ),
        ],
      ),
    ).animate().scale(duration: 200.ms, curve: Curves.easeOut);
  }
}
