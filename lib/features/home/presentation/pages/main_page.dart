import 'package:flutter/material.dart';
import 'package:twogether/features/games/presentation/pages/games_page.dart';
import 'package:twogether/features/notes/presentation/pages/notes_page.dart';
import 'package:twogether/features/profile/presentation/pages/profile_page.dart';
import 'package:flutter_animate/flutter_animate.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 1; // Default to Games (Center)

  final List<Widget> _pages = const [
    NotesPage(),
    GamesPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'main_fab',
        onPressed: () => _onItemTapped(1),
        backgroundColor: const Color(0xFFE91E63),
        elevation: 8,
        shape: const CircleBorder(),
        child: Icon(
          Icons.sports_esports_rounded,
          size: 32,
          color: _selectedIndex == 1 ? Colors.white : Colors.white.withOpacity(0.8),
        ),
      ).animate(target: _selectedIndex == 1 ? 1 : 0).scale(
        begin: const Offset(1.0, 1.0),
        end: const Offset(1.1, 1.1),
        duration: 200.ms,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: Colors.white,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(
                  Icons.edit_note_rounded,
                  size: 28,
                  color: _selectedIndex == 0 ? const Color(0xFFE91E63) : Colors.grey,
                ),
                onPressed: () => _onItemTapped(0),
                tooltip: 'Günlük Notlar',
              ),
              const SizedBox(width: 48), // Spacer for FAB
              IconButton(
                icon: Icon(
                  Icons.person_rounded,
                  size: 28,
                  color: _selectedIndex == 2 ? const Color(0xFFE91E63) : Colors.grey,
                ),
                onPressed: () => _onItemTapped(2),
                tooltip: 'Profil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
