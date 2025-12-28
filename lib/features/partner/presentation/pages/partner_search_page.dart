import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class PartnerSearchPage extends StatefulWidget {
  const PartnerSearchPage({super.key});

  @override
  State<PartnerSearchPage> createState() => _PartnerSearchPageState();
}

class _PartnerSearchPageState extends State<PartnerSearchPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  Map<String, dynamic>? _currentPartner;
  String? _connectionId;
  bool _isLoading = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (_currentUserId == null) return;
    await Future.wait([
      _fetchIncomingRequests(),
      _fetchCurrentPartner(),
    ]);
  }

  Future<void> _fetchCurrentPartner() async {
    try {
      final response = await Supabase.instance.client
          .from('connections')
          .select('*, requester:profiles!requester_id(*), receiver:profiles!receiver_id(*)')
          .or('requester_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId')
          .eq('status', 'accepted')
          .maybeSingle();

      if (mounted) {
        if (response != null) {
          final isRequester = response['requester_id'] == _currentUserId;
          setState(() {
            _currentPartner = isRequester ? response['receiver'] : response['requester'];
            _connectionId = response['id'];
          });
        } else {
          setState(() {
            _currentPartner = null;
            _connectionId = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching partner: $e');
    }
  }

  Future<void> _disconnectPartner() async {
    if (_connectionId == null) return;

    try {
      await Supabase.instance.client
          .from('connections')
          .delete()
          .eq('id', _connectionId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Partner bağlantısı kesildi.')),
        );
        _fetchCurrentPartner();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlantı kesme hatası: $e')),
        );
      }
    }
  }

  Future<void> _fetchIncomingRequests() async {
    if (_currentUserId == null) return;
    
    try {
      final response = await Supabase.instance.client
          .from('connections')
          .select('*, sender:profiles!requester_id(*)')
          .eq('receiver_id', _currentUserId!)
          .eq('status', 'pending');
      
      if (mounted) {
        setState(() {
          _incomingRequests = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Simple search by email for now
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .ilike('email', '%$query%')
          .neq('id', _currentUserId as Object); // Don't show myself

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arama hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendRequest(String targetUserId) async {
    try {
      await Supabase.instance.client.from('connections').insert({
        'requester_id': _currentUserId,
        'receiver_id': targetUserId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arkadaşlık isteği gönderildi!')),
        );
        // Refresh search results to maybe show different status if valid
        _searchUsers(_searchController.text);
      }
    } catch (e) {
      if (mounted) {
         // Check for duplicate key error (already requested)
        if (e.toString().contains('duplicate key')) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İstek zaten gönderildi veya zaten bağlısınız.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('İstek gönderme hatası: $e')),
          );
        }
      }
    }
  }

  Future<void> _respondToRequest(String connectionId, bool accept) async {
    try {
      await Supabase.instance.client.from('connections').update({
        'status': accept ? 'accepted' : 'rejected',
      }).eq('id', connectionId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'Partner bağlandı!' : 'İstek reddedildi.')),
        );
        _fetchIncomingRequests();
        _fetchCurrentPartner(); // Update current partner if accepted
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yanıt verme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Partner Yönetimi',
          style: GoogleFonts.dancingScript(
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFE91E63)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Partner Section
              if (_currentPartner != null) ...[
                Text(
                  'Partnerin',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFE91E63),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 35,
                              backgroundColor: Color(0xFFFF4081),
                              child: Icon(Icons.favorite, size: 35, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentPartner!['email'] ?? 'Partner',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'Sonsuza Kadar Beraber',
                                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Partnerden Ayrıl?'),
                                    content: const Text('Partnerinle bağlantını kesmek istediğine emin misin? Tekrar bağlanana kadar oyunlara erişemezsin.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('İptal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _disconnectPartner();
                                        },
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('Ayrıl'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_remove, color: Colors.red),
                              tooltip: 'Partnerden Ayrıl',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
              ] else ...[
                 // Search Bar - Only show if NO partner
                Text(
                  'Yeni Partner Bul',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF4A142F),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'E-posta ile ara...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchUsers('');
                      },
                    ),
                  ),
                  onSubmitted: _searchUsers,
                ),
                const SizedBox(height: 24),
    
                // Search Results Section
                if (_searchResults.isNotEmpty) ...[
                  Text(
                    'Arama Sonuçları',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF4A142F),
                        fontWeight: FontWeight.bold,
                      ),
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.grey,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(user['email'] ?? 'Bilinmeyen'),
                            trailing: ElevatedButton(
                              onPressed: () => _sendRequest(user['id']),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Text('Bağlan'),
                            ),
                          ),
                        );
                      },
                    ),
                ] else if (_isLoading) ...[
                    const Center(child: CircularProgressIndicator())
                ]
              ],

              // Incoming Requests Section - Always show pending requests just in case (e.g. while disconnected)
              if (_incomingRequests.isNotEmpty && _currentPartner == null) ...[
                const SizedBox(height: 24),
                Text(
                  'Gelen İstekler',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFE91E63),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _incomingRequests.length,
                  itemBuilder: (context, index) {
                    final request = _incomingRequests[index];
                    final sender = request['sender'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE91E63),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(sender['email'] ?? 'Bilinmeyen'),
                        subtitle: const Text('Seninle bağlanmak istiyor'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () => _respondToRequest(request['id'], true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () => _respondToRequest(request['id'], false),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

