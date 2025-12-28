import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twogether/features/partner/presentation/pages/partner_search_page.dart';
import 'package:twogether/features/profile/presentation/pages/settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _partnerEmail;

  @override
  void initState() {
    super.initState();
    _fetchPartner();
  }

  Future<void> _fetchPartner() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('connections')
          .select('*, requester:profiles!requester_id(email), receiver:profiles!receiver_id(email)')
          .or('requester_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted')
          .maybeSingle();

      if (mounted) {
        if (response != null) {
          final isRequester = response['requester_id'] == userId;
          final partnerData = isRequester ? response['receiver'] : response['requester'];
          setState(() {
            _partnerEmail = partnerData['email'];
          });
        } else {
          setState(() {
            _partnerEmail = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching partner: $e');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unknown User';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profil',
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
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFFFF4081),
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              email,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 32),
            ListTile(
              leading: const Icon(Icons.favorite, color: Color(0xFFE91E63)),
              title: const Text('Partnerim'),
              subtitle: _partnerEmail != null 
                ? Text(_partnerEmail!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                : const Text('Henüz eklenmedi'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PartnerSearchPage()),
                ).then((_) => _fetchPartner()); // Refresh on return
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFFE91E63)),
              title: const Text('Ayarlar'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Çıkış Yap'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
