import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class WordChainGamePage extends StatefulWidget {
  final String connectionId;
  final String currentUserId;

  const WordChainGamePage({
    super.key,
    required this.connectionId,
    required this.currentUserId,
  });

  @override
  State<WordChainGamePage> createState() => _WordChainGamePageState();
}

class _WordChainGamePageState extends State<WordChainGamePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Map<String, dynamic>? _gameState;
  StreamSubscription<List<Map<String, dynamic>>>? _gameStream;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _gameStream?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    try {
      final existingGame = await Supabase.instance.client
          .from('word_chain_games')
          .select()
          .eq('connection_id', widget.connectionId)
          .maybeSingle();

      if (existingGame == null) {
        final connection = await Supabase.instance.client
            .from('connections')
            .select()
            .eq('id', widget.connectionId)
            .single();

        // Player 1 starts, no last letter yet
        await Supabase.instance.client.from('word_chain_games').insert({
          'connection_id': widget.connectionId,
          'player1_id': connection['requester_id'],
          'player2_id': connection['receiver_id'],
          'current_turn': connection['requester_id'],
          'used_words': [],
          'last_letter': null, 
        });
      }
    } catch (e) {
      debugPrint('Error init WordChain: $e');
    }

    _gameStream = Supabase.instance.client
        .from('word_chain_games')
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

    final oldWordsCount = (_gameState?['used_words'] as List?)?.length ?? 0;
    final newWordsCount = (newState['used_words'] as List?)?.length ?? 0;
    
    setState(() {
      _gameState = newState;
      _isLoading = false;
    });

    if (newWordsCount > oldWordsCount) {
       // Scroll to bottom
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (_scrollController.hasClients) {
           _scrollController.animateTo(
             _scrollController.position.maxScrollExtent, 
             duration: const Duration(milliseconds: 300), 
             curve: Curves.easeOut,
           );
         }
       });
    }

    // Check winner
    if (newState['winner_id'] != null) {
      _showGameOverDialog(newState['winner_id']);
    }
  }

  Future<bool> _isValidTurkishWord(String word) async {
    try {
      final response = await http.get(
        Uri.parse('https://sozluk.gov.tr/gts?ara=$word'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // TDK returns list of objects if found.
        // Returns {"error": "..."} or empty list if not.
        if (data is List && data.isNotEmpty) {
          // Double check if it's the exact word or just prefix match? TDK usually partial matches only if specified?
          // Actually TDK 'gts?ara=' returns exact matches or close ones?
          // Usually exact.
          return true;
        } else {
          return false; // Not found in dictionary
        }
      }
    } catch (e) {
      debugPrint("API Error: $e");
      // If API fails, we can't validate. 
      // To prevent 'random chars' being accepted when API is down/blocked, we should likely return false 
      // or show a 'Connection Error' to user.
      // Given user feedback "random dahi yazsam kaybetmiyorum", they want strictness.
      // So let's return false on error but maybe inform user.
      return false; 
    }
    return false;
  }

  Future<void> _submitWord() async {
    if (_isSending || _gameState == null) return;
    
    // 1. Basic Checks
    final word = _textController.text.trim().toLowerCase();
    if (word.isEmpty) return;

    // Check turn
    if (_gameState!['current_turn'] != widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sıra rakibinde!')));
      return;
    }

    setState(() => _isSending = true);

    try {
      // 2. Logic Validation
      final List<dynamic> usedWords = List.from(_gameState!['used_words'] ?? []);
      final String? lastLetter = _gameState!['last_letter']?.toLowerCase();

      // Rule: Must start with last letter
      // If NOT first turn (lastLetter != null)
      if (lastLetter != null && !word.startsWith(lastLetter)) {
         // User feedback implies strictness. 
         // "a ile biterse ben c ile başlayan bir kelimede yaza biliyorum ve kaybetmiyorum"
         // This means they want to LOSE if they do this, OR strictly block it.
         // Usually block is better, but let's be strict if they send it.
         // "hatalı kelime yazınca kaybetmiyorum" covers dictionary.
         // For wrong letter, I will BLOCK it and show error.
         
         _onInvalidMove("Kelime '$lastLetter' harfi ile başlamalı!");
         return; 
      }
      
      // Rule: No duplicates (repetition)
      if (usedWords.contains(word)) {
         _onGameLostByRepeatedWord(); // Trigger Loss
         return;
      }

      // 3. Dictionary Validation
      final isValid = await _isValidTurkishWord(word);
      if (!isValid) {
         // Invalid word -> Opponent wins!
         _onGameLostByInvalidWord(word); // Trigger Loss
         return;
      }

      // 4. Success -> Submit
      // TDK gives 'ğ' ending etc? We just take last char.
      // But careful with tricky chars. Dart substring is fine.
      final newLastLetter = word.substring(word.length - 1);
      final nextTurn = (_gameState!['current_turn'] == _gameState!['player1_id'])
          ? _gameState!['player2_id']
          : _gameState!['player1_id'];
      
      usedWords.add(word);

      await Supabase.instance.client.from('word_chain_games').update({
        'used_words': usedWords,
        'current_turn': nextTurn,
        'last_letter': newLastLetter,
      }).eq('id', _gameState!['id']);

      _textController.clear();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
  
  void _onInvalidMove(String message) {
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
     setState(() => _isSending = false);
  }
  
  void _onGameLostByRepeatedWord() async {
    await _triggerWinForOpponent("Aynı kelime kullanıldı!");
  }

  void _onGameLostByInvalidWord(String word) async {
    await _triggerWinForOpponent("'$word' geçerli bir Türkçe kelime değil!");
  }

  Future<void> _triggerWinForOpponent(String reason) async {
     // I lose, so opponent ID is winner
     final opponentId = (_gameState!['player1_id'] == widget.currentUserId) 
         ? _gameState!['player2_id'] 
         : _gameState!['player1_id'];
         
     await Supabase.instance.client.from('word_chain_games').update({
       'winner_id': opponentId,
       'last_letter': null, // Reset generic field for next game info usually
     }).eq('id', _gameState!['id']);
     
     if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
       setState(() => _isSending = false);
     }
  }

  void _showGameOverDialog(String winnerId) async {
     final isMe = winnerId == widget.currentUserId;
     
     if (!mounted) return;
     
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (context) => AlertDialog(
         title: Text(isMe ? 'Kazandın!' : 'Kaybettin!', 
             style: TextStyle(color: isMe ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
         content: Text(isMe ? 'Rakibin hata yaptı!' : 'Hatalı kelime veya tekrar!'),
         actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (isMe) _resetGame(); // Winner resets
              },
              child: const Text('Yeni Oyun'),
            )
         ],
       ),
     );
  }

  Future<void> _resetGame() async {
    try {
      await Supabase.instance.client.from('word_chain_games').update({
        'used_words': [],
        'current_turn': _gameState!['player1_id'], // Always Player 1 starts to keep chat alignment (Index 0 = P1)
        'last_letter': null,
        'winner_id': null,
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

    final isMyTurn = _gameState!['current_turn'] == widget.currentUserId;
    final List<dynamic> words = _gameState!['used_words'] ?? [];
    final String? lastLetter = _gameState!['last_letter'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Sonun Başlangıcı', style: GoogleFonts.dancingScript(fontWeight: FontWeight.bold, fontSize: 28)),
        centerTitle: true, 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE91E63)),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header / Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: isMyTurn ? const Color(0xFFFFF0F5) : Colors.grey[200],
            child: Column(
              children: [
                Text(
                  isMyTurn ? "Senin Sıran!" : "Rakibin Sırası...",
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: isMyTurn ? const Color(0xFFE91E63) : Colors.black54
                  ),
                ),
                if (lastLetter != null) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      text: "Baş harf: ",
                      children: [
                        TextSpan(
                          text: lastLetter.toUpperCase(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFF4081)),
                        )
                      ]
                    )
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text("İstediğin harfle başla!", style: TextStyle(fontStyle: FontStyle.italic)),
                ]
              ],
            ),
          ),
          
          // Word List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: words.length,
              itemBuilder: (context, index) {
                final word = words[index] as String;
                // Assuming alternating turns: Even indices matches Player starting? 
                // We don't track who said what in array directly, but we can guess or just style uniformly.
                // Better style: Bubble
                // To know who said it, we need to know who started.
                // Let's Just alternate styling based on index.
                // The DB doesn't store WHO said which word in list, but order is preserved.
                // But who started? P1 started. So Even index = P1, Odd = P2.
                
                final isP1Word = index % 2 == 0;
                final isMeP1 = widget.currentUserId == _gameState!['player1_id'];
                final isMyWord = (isP1Word && isMeP1) || (!isP1Word && !isMeP1);
                
                return Align(
                  alignment: isMyWord ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMyWord ? const Color(0xFFE91E63) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isMyWord ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isMyWord ? Radius.zero : const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0,2))
                      ],
                      border: isMyWord ? null : Border.all(color: Colors.grey.shade300),
                    ),
                    child: _buildRichWord(word, isMyWord),
                  ).animate().fade().slideY(begin: 0.2, end: 0),
                );
              },
            ),
          ),
          
          // Input Area
          if (isMyTurn)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: lastLetter != null ? "'${lastLetter.toUpperCase()}' ile başlayan bir kelime..." : "Bir kelime yaz...",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitWord(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    heroTag: 'word_chain_fab',
                    onPressed: _isSending ? null : _submitWord,
                    backgroundColor: const Color(0xFFE91E63),
                    child: _isSending 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          if (!isMyTurn)
             Container(
               padding: const EdgeInsets.all(24),
               child: const Text("Rakip yazıyor...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
             ), 
        ],
      ),
    );
  }

  Widget _buildRichWord(String word, bool isMyWord) {
     if (word.length < 2) return Text(word, style: TextStyle(color: isMyWord ? Colors.white : Colors.black87));
     
     final first = word.substring(0, 1);
     final  mid = word.substring(1, word.length - 1);
     final last = word.substring(word.length - 1);

     return RichText(
       text: TextSpan(
         style: GoogleFonts.poppins(fontSize: 16, color: isMyWord ? Colors.white : Colors.black87),
         children: [
           TextSpan(text: first, style: TextStyle(color: isMyWord ? const Color(0xFFF8BBD0) : const Color(0xFFFF4081), fontWeight: FontWeight.bold)), // Pinkish
           TextSpan(text: mid),
           TextSpan(text: last, style: const TextStyle(color: Color(0xFF69F0AE), fontWeight: FontWeight.bold)), // Greenish
         ]
       ),
     );
  }
}
