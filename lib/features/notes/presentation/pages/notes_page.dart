import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:twogether/features/notes/presentation/widgets/drawing_pad.dart';
import 'package:twogether/features/notes/presentation/widgets/note_card.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  Stream<List<Map<String, dynamic>>>? _notesStream;
  String? _connectionId;

  @override
  void initState() {
    super.initState();
    _setupNotes();
  }

  Future<void> _setupNotes() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('connections')
          .select('id')
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted')
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _connectionId = response['id'];
        });

        _notesStream = Supabase.instance.client
            .from('daily_notes')
            .stream(primaryKey: ['id'])
            .eq('connection_id', _connectionId!)
            .order('created_at', ascending: false)
            .limit(50)
            .map((data) {
              final deadline = DateTime.now().subtract(const Duration(hours: 24));
              return data.where((note) {
                final createdAt = DateTime.tryParse(note['created_at'].toString());
                return createdAt != null && createdAt.isAfter(deadline);
              }).toList();
            });
      }
    } catch (e) {
      debugPrint('Notes setup error: $e');
    }
  }

  Future<void> _addNote() async {
    if (_connectionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı kimliği mevcut değil. Not eklenemiyor.')),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddNoteDialog(connectionId: _connectionId!),
    );
  }

  Future<void> _deleteNote(dynamic noteId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notu Sil'),
        content: const Text('Bu notu silmek istediğine emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('daily_notes').delete().eq('id', noteId);
      // Force refresh the stream/page as requested
      if (mounted) {
         _setupNotes();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connectionId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_border, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text("Partnerinle bağlanınca\nburası notlarla dolacak!", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Günlük Notlar',
          style: GoogleFonts.dancingScript(
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF0F0F0), // Slight grey/corkboard bg
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notes_fab',
        onPressed: _addNote,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Not Ekle'),
        backgroundColor: const Color(0xFFE91E63),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF3E0), // PapayaWhip equivalent
                Color(0xFFFCE4EC), // MistyRose equivalent
              ]
          )
        ),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _notesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final notes = snapshot.data ?? [];
            if (notes.isEmpty) {
              return Center(
                child: Text(
                  "Henüz not yok.\nİlk notunu (veya çizimini) bırak!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dancingScript(fontSize: 24, color: Colors.black54),
                ).animate().fade().scale(),
              );
            }

            // Masonry-like Grid
            return GridView.builder(
              padding: const EdgeInsets.all(16).copyWith(bottom: 80),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0, // Square notes
              ),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final isMe = note['author_id'] == Supabase.instance.client.auth.currentUser?.id;
                
                return NoteCard(
                  key: ValueKey(note['id']),
                  note: note,
                  onDelete: isMe ? () => _deleteNote(note['id']) : null,
                ).animate(key: ValueKey(note['id'])).fade().slideY(begin: 0.1, end: 0, delay: Duration(milliseconds: index * 50));
              },
            );
          },
        ),
      ),
    );
  }
}

class _AddNoteDialog extends StatefulWidget {
  final String connectionId;
  const _AddNoteDialog({required this.connectionId});

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  List<Map<String, dynamic>> _currentDrawing = [];
  bool _isSending = false;
  
  // Colors for background
  final List<int> _colors = [
    0xFFFFF9C4, // Yellow
    0xFFFFCC80, // Orange
    0xFFB2DFDB, // Teal
    0xFFF8BBD0, // Pink
    0xFFE1BEE7, // Purple
    0xFFFFFFFF, // White
  ];
  int _selectedColor = 0xFFFFF9C4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _submit() async {
    final isDrawing = _tabController.index == 1;
    final content = isDrawing ? _currentDrawing : _textController.text.trim();
    
    // Validation
    if (isDrawing) {
       if (_currentDrawing.isEmpty) return;
    } else {
       if ((content as String).isEmpty) return;
    }

    setState(() => _isSending = true);
    
    try {
      await Supabase.instance.client.from('daily_notes').insert({
        'connection_id': widget.connectionId,
        'author_id': Supabase.instance.client.auth.currentUser!.id,
        'type': isDrawing ? 'drawing' : 'text',
        'content': isDrawing ? content : content, // Auto handles JSON conversion usually? No, DB expects JSON type.
        'bg_color': _selectedColor,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.text_fields), text: 'Yazı'),
                Tab(icon: Icon(Icons.draw), text: 'Çizim'),
              ],
              labelColor: const Color(0xFFE91E63),
              indicatorColor: const Color(0xFFE91E63),
            ),
            const SizedBox(height: 16),
            
            // Content Area
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe to enable drawing
                children: [
                  // Text Input
                   Container(
                     decoration: BoxDecoration(
                        color: Color(_selectedColor),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]
                     ),
                     padding: const EdgeInsets.all(16),
                     child: TextField(
                       controller: _textController,
                       maxLines: null,
                       autofocus: true,
                       decoration: const InputDecoration(
                         border: InputBorder.none,
                         hintText: 'Bir şeyler yaz...',
                       ),
                       style: GoogleFonts.permanentMarker(fontSize: 20),
                     ),
                   ),
                   
                  // Drawing Input
                  DrawingPad(
                    onDrawingChanged: (data) {
                      _currentDrawing = data;
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Color Selector
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                itemBuilder: (context, index) {
                  final color = _colors[index];
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 36, height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Colors.black, width: 2) : Border.all(color: Colors.grey.shade300),
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 20, color: Colors.black54) : null,
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: _isSending ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE91E63)),
                  child: _isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Yapıştır'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
