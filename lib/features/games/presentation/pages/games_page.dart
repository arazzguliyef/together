import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:twogether/features/partner/presentation/pages/partner_search_page.dart';
import 'package:twogether/features/games/rps/presentation/pages/rock_paper_scissors_page.dart';
import 'package:twogether/features/games/tictactoe/presentation/pages/tic_tac_toe_page.dart';
import 'package:twogether/features/games/memory/presentation/pages/memory_game_page.dart';
import 'package:twogether/features/games/card/presentation/pages/card_game_page.dart';
import 'package:twogether/features/games/word_chain/presentation/pages/word_chain_game_page.dart';

class GameData {
  final String title;
  final IconData icon;
  final Color color;

  const GameData({
    required this.title,
    required this.icon,
    required this.color,
  });
}

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  bool _isLoading = true;
  bool _hasPartner = false;
  String? _connectionId;

  static const List<GameData> games = [
    GameData(
      title: 'Taş Kağıt Makas',
      icon: Icons.cut_rounded,
      color: Color(0xFFFF80AB),
    ),
    GameData(
      title: 'Tic-Tac-Toe',
      icon: Icons.grid_3x3_rounded,
      color: Color(0xFFFF4081),
    ),
    GameData(
      title: 'Kart Savaşı',
      icon: Icons.style_rounded,
      color: Color(0xFFF50057),
    ),
    GameData(
      title: 'Hafıza Oyunu',
      icon: Icons.memory_rounded,
      color: Color(0xFFC51162),
    ),
    GameData(
      title: 'Sonun Başlangıcı', // Mysterious game
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF880E4F),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkPartnerStatus();
  }

  Future<void> _checkPartnerStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('connections')
          .select()
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted')
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasPartner = response != null;
          _connectionId = response != null ? response['id'] : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking partner: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPartner) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Oyunlar',
            style: GoogleFonts.dancingScript(
              fontWeight: FontWeight.bold,
              fontSize: 32,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.heart_broken_rounded,
                  size: 100,
                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                const SizedBox(height: 24),
                Text(
                  'Partnerinle Bağlan',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF4A142F),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Oyunları oynayabilmek için önce partnerinle eşleşmen gerekiyor.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PartnerSearchPage()),
                    ).then((_) => _checkPartnerStatus()); // Re-check on return
                  },
                  icon: const Icon(Icons.person_search_rounded),
                  label: const Text('Partner Bul'),
                ).animate().shimmer(delay: 1.seconds, duration: 2.seconds),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Oyunlar',
          style: GoogleFonts.dancingScript(
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) {
            final game = games[index];
            return _GameCard(
              game: game,
              index: index,
              onTap: () {
                if (game.title == 'Taş Kağıt Makas') {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RockPaperScissorsPage(
                        connectionId: _connectionId!,
                        currentUserId: Supabase.instance.client.auth.currentUser!.id,
                      ),
                    ),
                  );
                } else if (game.title == 'Tic-Tac-Toe') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TicTacToePage(
                        connectionId: _connectionId!,
                        currentUserId: Supabase.instance.client.auth.currentUser!.id,
                      ),
                    ),
                  );
                } else if (game.title == 'Hafıza Oyunu') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MemoryGamePage(
                        connectionId: _connectionId!,
                        currentUserId: Supabase.instance.client.auth.currentUser!.id,
                      ),
                    ),
                  );
                } else if (game.title == 'Kart Savaşı') {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CardGamePage(
                        connectionId: _connectionId!,
                        currentUserId: Supabase.instance.client.auth.currentUser!.id,
                      ),
                    ),
                  );
                } else if (game.title == 'Sonun Başlangıcı') {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WordChainGamePage(
                        connectionId: _connectionId!,
                        currentUserId: Supabase.instance.client.auth.currentUser!.id,
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${game.title} yakında eklenecek!')),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameData game;
  final int index;
  final VoidCallback onTap;

  const _GameCard({
    required this.game,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: game.color.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: game.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  game.icon,
                  size: 40,
                  color: game.color,
                ),
              ).animate(target: 1).scale(duration: 300.ms, curve: Curves.easeOut),
              const SizedBox(height: 16),
              Text(
                game.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: const Color(0xFF4A142F),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (100 * index).ms).slideY(begin: 0.2, end: 0);
  }
}

