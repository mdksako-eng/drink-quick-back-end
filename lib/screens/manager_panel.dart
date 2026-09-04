// screens/manager_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../utils/helpers.dart';
import '../config/api_config.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:drinks_calculator_fixed/services/secure_storage_service.dart';

class ManagerPanel extends StatefulWidget {
  const ManagerPanel({Key? key}) : super(key: key);

  @override
  State<ManagerPanel> createState() => _ManagerPanelState();
}

class _ManagerPanelState extends State<ManagerPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isCreating = false;

  List<Map<String, dynamic>> _activeStaff = [];
  List<Map<String, dynamic>> _blockedStaff = [];

  Map<String, dynamic> _stats = {
    'totalStaff': 0,
    'activeStaff': 0,
    'blockedStaff': 0
  };

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _securityAnswer1Controller = TextEditingController();
  final _securityAnswer2Controller = TextEditingController();

  // Theme support
  String _primaryColorHex = '#667EEA';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadThemeSettings();
    _loadStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _securityAnswer1Controller.dispose();
    _securityAnswer2Controller.dispose();
    super.dispose();
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _primaryColorHex = prefs.getString('primary_color') ?? '#667EEA';
    });
  }

  Color get _primaryColor =>
      Color(int.parse(_primaryColorHex.replaceFirst('#', '0xFF')));

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.id ?? '';
      final token = await SecureStorageService.getSessionToken();
        // Fetch ALL company users (Managers + Staff). The backend filters by
        // company for Managers; Administrators get every user.
        final response = await http.get(
          Uri.parse(ApiConfig.usersUrl),
        headers: {
          'Content-Type': 'application/json',
          'user-id': userId,
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final users = List<Map<String, dynamic>>.from(data['data']['users']);
          setState(() {
            _activeStaff = users.where((u) => u['isActive'] == true).toList();
            _blockedStaff = users.where((u) => u['isActive'] == false).toList();
            _stats = {
              'totalStaff': users.length,
              'activeStaff': _activeStaff.length,
              'blockedStaff': _blockedStaff.length,
            };
          });
        }
      }
    } catch (e) {
      Helpers.showToast('Error loading staff: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _createStaff() async {
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      Helpers.showToast('Please fill all fields');
      return;
    }

    setState(() => _isCreating = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id ?? '';
    final token = await SecureStorageService.getSessionToken();

    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.createStaff),
            headers: {
              'Content-Type': 'application/json',
              'user-id': userId,
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'username': _usernameController.text.trim(),
              'email': _emailController.text.trim(),
              'password': _passwordController.text,
              'securityQuestions': {
                'question1': _securityAnswer1Controller.text.trim(),
                'question2': _securityAnswer2Controller.text.trim(),
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 201 || data['status'] == 'success') {
        _clearForm();
        await _loadStaff();
        Navigator.pop(context);
        Helpers.showToast('Staff created!');
      } else {
        Helpers.showToast(data['message'] ?? 'Failed');
      }
    } catch (e) {
      Helpers.showToast('Error: $e');
    }

    setState(() => _isCreating = false);
  }

  Future<void> _blockStaff(Map<String, dynamic> staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block Staff'),
        content: Text('Block ${staff['username']}?\n\nThey cannot login.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Block')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.blockUser(staff['id'])),
          headers: {'Content-Type': 'application/json'},
        );
        if (response.statusCode == 200) {
          await _loadStaff();
          Helpers.showToast('Blocked');
        }
      } catch (e) {
        Helpers.showToast('Error: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockStaff(Map<String, dynamic> staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock Staff'),
        content: Text('Allow ${staff['username']} to login?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Unblock')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.unblockUser(staff['id'])),
          headers: {'Content-Type': 'application/json'},
        );
        if (response.statusCode == 200) {
          await _loadStaff();
          Helpers.showToast('Unblocked');
        }
      } catch (e) {
        Helpers.showToast('Error: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _usernameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _securityAnswer1Controller.clear();
    _securityAnswer2Controller.clear();
  }

  void _showCreateDialog() {
    bool showPass = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child:
                            const Icon(Icons.person_add, color: Colors.orange)),
                    const SizedBox(width: 12),
                    const Text('Create New Staff',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Staff will belong to your company',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username *',
                      prefixIcon: const Icon(Icons.person),
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: _primaryColor, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      prefixIcon: const Icon(Icons.email),
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: _primaryColor, width: 2)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: !showPass,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                          icon: Icon(showPass
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setModalState(() => showPass = !showPass)),
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: _primaryColor, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Security Questions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _securityAnswer1Controller,
                    decoration: InputDecoration(
                      labelText: "What was your first pet's name?",
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: _primaryColor, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _securityAnswer2Controller,
                    decoration: InputDecoration(
                      labelText: 'What city were you born in?',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: _primaryColor, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isCreating ? null : _createStaff,
                        icon: _isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.person_add),
                        label:
                            Text(_isCreating ? 'Creating...' : 'Create Staff'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      )),
                  const SizedBox(height: 10),
                ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isManager = authProvider.user?.role.toLowerCase() == 'manager';

    final role = authProvider.user?.role.toLowerCase() ?? '';
    final isAdmin = role == 'administrator' || role == 'admin';

    if (!isManager && !isAdmin) {
      return Scaffold(
        appBar: AppBar(
            title: const Text('Access Denied'), backgroundColor: Colors.red),
        body: const Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock, size: 80, color: Colors.red),
          SizedBox(height: 20),
          Text('Manager Access Required',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ])),
      );
    }

    return GestureDetector(
      onTap: () => LockService().resetTimer(),
      onPanDown: (_) => LockService().resetTimer(),
      onScaleStart: (_) => LockService().resetTimer(),
      onLongPress: () => LockService().resetTimer(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff Management'),
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStaff)
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people, size: 18),
                const SizedBox(width: 6),
                Text('Active (${_activeStaff.length})')
              ])),
              Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.block, size: 18),
                const SizedBox(width: 6),
                Text('Blocked (${_blockedStaff.length})')
              ])),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateDialog,
          backgroundColor: _primaryColor,
          icon: const Icon(Icons.person_add),
          label: const Text('Add Staff'),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryColor, _primaryColor.withValues(alpha: 0.7)],
            ),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.business,
                            color: _primaryColor, size: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              'Welcome, ${authProvider.user?.username ?? 'Manager'}!',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Manage your company staff',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                        ])),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: _primaryColor,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text('MANAGER',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold))),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _statCard('Total Staff', '${_stats['totalStaff']}',
                    Icons.people, Colors.blue),
                const SizedBox(width: 10),
                _statCard('Active', '${_stats['activeStaff']}',
                    Icons.check_circle, Colors.green),
                const SizedBox(width: 10),
                _statCard('Blocked', '${_stats['blockedStaff']}', Icons.block,
                    Colors.red),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 5,
                  child: _isLoading
                      ? Center(
                          child:
                              CircularProgressIndicator(color: _primaryColor))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildStaffList(_activeStaff, true),
                            _buildStaffList(_blockedStaff, false)
                          ],
                        ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
          elevation: 3,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 8),
                Text(value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text(title,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center),
              ]))),
    );
  }

  Widget _buildStaffList(List<Map<String, dynamic>> staff, bool isActive) {
    if (staff.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(isActive ? Icons.people_outline : Icons.block,
            size: 60, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(isActive ? 'No active staff' : 'No blocked staff',
            style: TextStyle(fontSize: 16, color: Colors.grey[500])),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: staff.length,
      itemBuilder: (context, index) {
        final s = staff[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive ? _primaryColor : Colors.grey,
              child: Text((s['username'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Row(children: [
              Expanded(
                  child: Text(s['username'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w500))),
              if (s['id'].toString() ==
                  Provider.of<AuthProvider>(context, listen: false)
                      .user
                      ?.id
                      .toString())
                const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('You',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold))),
            ]),
            subtitle: Row(children: [
              Flexible(
                  child: Text(s['email'] ?? '',
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (s['role']?.toString().toLowerCase() == 'manager')
                      ? Colors.orange.withOpacity(0.15)
                      : Colors.blueGrey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s['role'] ?? 'Staff',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: (s['role']?.toString().toLowerCase() == 'manager')
                        ? Colors.orange.shade800
                        : Colors.blueGrey.shade700,
                  ),
                ),
              ),
            ]),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'block') _blockStaff(s);
                if (action == 'unblock') _unblockStaff(s);
              },
              itemBuilder: (ctx) => [
                if (isActive)
                  const PopupMenuItem(
                      value: 'block',
                      child: Row(children: [
                        Icon(Icons.block, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        const Text('Block')
                      ])),
                if (!isActive)
                  const PopupMenuItem(
                      value: 'unblock',
                      child: Row(children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        const Text('Unblock')
                      ])),
              ],
            ),
          ),
        );
      },
    );
  }
}
