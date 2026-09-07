// screens/admin_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../utils/helpers.dart';
import '../config/api_config.dart';
import '../utils/i18n.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({Key? key}) : super(key: key);

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String _adminToken = '';
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _activeUsers = [];
  List<Map<String, dynamic>> _blockedUsers = [];
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _customers = [];
  
  Map<String, dynamic> _stats = {
    'totalUsers': 0, 'activeUsers': 0, 'blockedUsers': 0,
    'admins': 0, 'managers': 0, 'staff': 0, 'customers': 0,
  };
  
  final TextEditingController _passwordController = TextEditingController();
  String _searchQuery = '';
  String _filterRole = 'All';
  
  // Theme support
  String _primaryColorHex = '#667EEA';
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadThemeSettings();
    _checkAdminAccess();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _primaryColorHex = prefs.getString('primary_color') ?? '#667EEA';
      _themeMode = ThemeMode.values[prefs.getInt('theme_mode') ?? 0];
    });
  }

  Color get _primaryColor => Color(int.parse(_primaryColorHex.replaceFirst('#', '0xFF')));

  Future<void> _checkAdminAccess() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPasswordDialog());
    }
  }

  Future<void> _showPasswordDialog() async {
    _passwordController.clear();
    
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(children: [
          Icon(Icons.admin_panel_settings, size: 60, color: _primaryColor),
          const SizedBox(height: 12),
          Text(t('admin_authTitle'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('admin_enterPasswordHint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 20),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('password'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.lock_outline),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _passwordController.text),
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: Text(t('verify'), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.verifyPassword(result)) {
        setState(() => _isAuthenticated = true);
        _adminToken = result;
        await _loadUsers();
        Helpers.showToast(t('admin_granted'));
      } else {
        Helpers.showToast(t('admin_wrongPassword'));
        _showPasswordDialog();
      }
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.usersUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final usersList = data['data']['users'];
          if (usersList is List && usersList.isNotEmpty) {
            _processUsers(usersList);
            return;
          }
        }
      }
      _setEmptyUsers();
    } catch (e) {
      _setEmptyUsers();
    }
    
    setState(() => _isLoading = false);
  }

  void _processUsers(List<dynamic> users) {
    final userList = users.map((u) => {
      'id': u['_id']?.toString() ?? u['id']?.toString() ?? '',
      'username': u['username']?.toString() ?? 'Unknown',
      'email': u['email']?.toString() ?? '',
      'role': u['role']?.toString() ?? 'Customer',
      'isActive': u['isActive'] ?? true,
      'companyId': u['companyId'] ?? u['company_id'],
      'createdAt': u['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
    }).toList();
    
    setState(() {
      _allUsers = userList;
      _activeUsers = userList.where((u) => u['isActive'] == true).toList();
      _blockedUsers = userList.where((u) => u['isActive'] == false).toList();
      _admins = userList.where((u) => u['role'] == 'Administrator' || u['role'] == 'Admin').toList();
      _managers = userList.where((u) => u['role'] == 'Manager').toList();
      _staffList = userList.where((u) => u['role'] == 'Staff').toList();
      _customers = userList.where((u) => u['role'] == 'Customer').toList();
      _stats = {
        'totalUsers': userList.length,
        'activeUsers': _activeUsers.length,
        'blockedUsers': _blockedUsers.length,
        'admins': _admins.length,
        'managers': _managers.length,
        'staff': _staffList.length,
        'customers': _customers.length,
      };
      _isLoading = false;
    });
  }

  void _setEmptyUsers() {
    setState(() {
      _allUsers = []; _activeUsers = []; _blockedUsers = [];
      _admins = []; _managers = []; _staffList = []; _customers = [];
      _stats = {'totalUsers': 0, 'activeUsers': 0, 'blockedUsers': 0, 'admins': 0, 'managers': 0, 'staff': 0, 'customers': 0};
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _getFilteredUsers(List<Map<String, dynamic>> users) {
    return users.where((u) {
      final matchSearch = _searchQuery.isEmpty ||
          (u['username']?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (u['email']?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final matchRole = _filterRole == 'All' || u['role'] == _filterRole || (u['role'] == 'Administrator' && _filterRole == 'Admin');
      return matchSearch && matchRole;
    }).toList();
  }

  Future<void> _blockUser(Map<String, dynamic> user) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user?.id == user['id']) { Helpers.showToast(t('admin_cannotBlockSelf')); return; }
    if (user['role'] == 'Administrator' || user['role'] == 'Admin') { Helpers.showToast(t('admin_cannotBlockAdmin')); return; }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_blockUser')),
        content: Text('${t('admin_blockUser')} ${user['username']}?\n\n${t('admin_blockBody')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text(t('admin_blockUser'))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.blockUser(user['id'])),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          Helpers.showToast('${user['username']} ${t('admin_blockedToast')}');
          await _loadUsers();
        }
      } catch (e) { Helpers.showToast('Error: $e'); }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_unblockUser')),
        content: Text('${t('admin_unblockBody').replaceAll('@u', user['username'] ?? '')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: Text(t('admin_unblockUser'))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(ApiConfig.unblockUser(user['id'])),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          Helpers.showToast('${user['username']} ${t('admin_unblockedToast')}');
          await _loadUsers();
        }
      } catch (e) { Helpers.showToast('Error: $e'); }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user?.id == user['id']) { Helpers.showToast(t('admin_cannotDeleteSelf')); return; }
    if (user['role'] == 'Administrator' || user['role'] == 'Admin') { Helpers.showToast(t('admin_cannotDeleteAdmin')); return; }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_deleteUser')),
        content: Text('${t('admin_deletePermanent')} ${user['username']}?\n\n${t('admin_cannotUndo')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text(t('admin_deleteForever'))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final response = await http.delete(
          Uri.parse(ApiConfig.deleteUser(user['id'])),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_adminToken',
          },
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          Helpers.showToast('${user['username']} ${t('admin_deletedToast')}');
          await _loadUsers();
        }
      } catch (e) { Helpers.showToast('Error: $e'); }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeRole(Map<String, dynamic> user) async {
    final roles = ['Administrator', 'Manager', 'Staff', 'Customer'];
    String? newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t('admin_changeRole')} ${user['username']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: roles.map((r) => ListTile(
          title: Text(r),
          leading: Radio<String>(
            value: r, 
            groupValue: user['role'], 
            activeColor: _primaryColor,
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
        )).toList()),
      ),
    );

    if (newRole != null && newRole != user['role']) {
      setState(() => _isLoading = true);
      try {
        final response = await http.put(
          Uri.parse(ApiConfig.updateUser(user['id'])),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_adminToken',
          },
          body: json.encode({'role': newRole}),
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          Helpers.showToast('${t('admin_roleChanged')} $newRole');
          await _loadUsers();
        }
      } catch (e) { Helpers.showToast('Error: $e'); }
      setState(() => _isLoading = false);
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'Administrator': return Colors.red;
      case 'Admin': return Colors.red;
      case 'Manager': return Colors.orange;
      case 'Staff': return Colors.blue;
      case 'Customer': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _formatDate(String? date) {
    if (date == null) return 'Unknown';
    try { return DateTime.parse(date).toString().split(' ')[0]; } catch (e) { return date.split('T')[0]; }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (!authProvider.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(t('admin_accessDenied')), backgroundColor: Colors.red),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.block, size: 80, color: Colors.red),
          SizedBox(height: 20),
          Text(t('admin_adminAccessRequired'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ])),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text(t('admin_title')), backgroundColor: _primaryColor),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 20),
          Text(t('admin_authRequired'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ElevatedButton.icon(onPressed: _showPasswordDialog, icon: const Icon(Icons.lock_open), label: Text(t('admin_enterPassword')), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor)),
        ])),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('admin_title')),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => setState(() => _isAuthenticated = false)),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.people, size: 18), const SizedBox(width: 6), Text('${t('admin_activeTab')} (${_activeUsers.length})')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.block, size: 18), const SizedBox(width: 6), Text('${t('admin_blockedTab')} (${_blockedUsers.length})')])),
          ],
        ),
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
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.admin_panel_settings, color: _primaryColor, size: 30)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${t('admin_welcome')} ${authProvider.user?.username ?? t('role_Admin')}!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(12)), child: Text(t('admin_adminBadge'), style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              _statCard(t('admin_statTotal'), '${_stats['totalUsers']}', Icons.people, Colors.blue),
              _statCard(t('admin_activeTab'), '${_stats['activeUsers']}', Icons.check_circle, Colors.green),
              _statCard(t('admin_blockedTab'), '${_stats['blockedUsers']}', Icons.block, Colors.red),
              _statCard(t('admin_statAdmins'), '${_stats['admins']}', Icons.admin_panel_settings, _primaryColor),
              _statCard(t('admin_statManagers'), '${_stats['managers']}', Icons.business, Colors.orange),
              _statCard(t('admin_statStaff'), '${_stats['staff']}', Icons.badge, Colors.blue),
            ])),
          ),
          const SizedBox(height: 12),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(flex: 3, child: TextField(
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                decoration: InputDecoration(
                  hintText: t('admin_search'),
                  hintStyle: TextStyle(color: Theme.of(context).hintColor),
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).hintColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _primaryColor, width: 2),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterRole,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).cardColor,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 13,
                    ),
                    items: ['All', 'Administrator', 'Manager', 'Staff', 'Customer'].map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(t('role_' + r), style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      )),
                    )).toList(),
                    onChanged: (v) => setState(() => _filterRole = v!),
                  ),
                ),
              )),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                elevation: 5,
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _primaryColor))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildUserList(_getFilteredUsers(_activeUsers)),
                          _buildUserList(_getFilteredUsers(_blockedUsers)),
                        ],
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(elevation: 3, child: Container(width: 90, padding: const EdgeInsets.all(10), child: Column(children: [
      Icon(icon, size: 22, color: color), const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
    ])));
  }

  Widget _buildUserList(List<Map<String, dynamic>> users) {
    if (users.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.people_outline, size: 60, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(t('admin_noUsers'), style: TextStyle(fontSize: 16, color: Colors.grey[500])),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final isActive = user['isActive'] == true;
        final role = user['role'] ?? 'Customer';
        final roleColor = _getRoleColor(role);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: CircleAvatar(backgroundColor: roleColor, child: Text((user['username'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            title: Row(children: [
              Expanded(child: Text(user['username'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w500))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: roleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(t('role_' + role), style: TextStyle(fontSize: 10, color: roleColor, fontWeight: FontWeight.bold))),
            ]),
            subtitle: Text(user['email'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Divider(), const SizedBox(height: 4),
                  Row(children: [Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]), const SizedBox(width: 6), Text('${t('admin_joined')} ${_formatDate(user['createdAt'])}', style: TextStyle(fontSize: 12, color: Colors.grey[600]))]),
                  if (user['companyId'] != null) ...[const SizedBox(height: 4), Row(children: [Icon(Icons.business, size: 14, color: Colors.grey[500]), const SizedBox(width: 6), Text('${t('admin_company')} ${user['companyId']}', style: TextStyle(fontSize: 12, color: Colors.grey[600]))])],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => isActive ? _blockUser(user) : _unblockUser(user),
                      icon: Icon(isActive ? Icons.block : Icons.check_circle, size: 16),
                      label: Text(isActive ? t('b3_block') : t('b3_unblock')),
                      style: OutlinedButton.styleFrom(foregroundColor: isActive ? Colors.red : Colors.green, side: BorderSide(color: isActive ? Colors.red : Colors.green), padding: const EdgeInsets.symmetric(vertical: 8)),
                    )),
                    const SizedBox(width: 4),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _changeRole(user),
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(t('admin_roleLabel')),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange), padding: const EdgeInsets.symmetric(vertical: 8)),
                    )),
                    if (role != 'Administrator' && role != 'Admin') ...[
                      const SizedBox(width: 4),
                      Expanded(child: ElevatedButton.icon(
                        onPressed: () => _deleteUser(user),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 8)),
                        icon: const Icon(Icons.delete_forever, color: Colors.white, size: 16),
                        label: Text(t('admin_del'), style: TextStyle(color: Colors.white, fontSize: 12)),
                      )),
                    ],
                  ]),
                  const SizedBox(height: 4),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
