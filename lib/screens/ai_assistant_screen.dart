// screens/ai_assistant_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/services/voice_service.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/services/groq_service.dart';
import 'package:drinks_calculator_fixed/screens/calculator_screen.dart';
import 'package:drinks_calculator_fixed/services/order_bridge.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({Key? key}) : super(key: key);

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final VoiceService _voiceService = VoiceService();
  final GroqService _groqService = GroqService();
  
  bool _isListening = false;
  bool _isLoading = false;
  String _voiceStatus = '';
  bool _voiceFeedbackEnabled = true;
  double _speechRate = 0.5;
  String _speechLanguage = 'en-US';
  String _voiceGender = 'female';
  List<Map<String, String>> _conversationHistory = [];
  List<Map<String, dynamic>> _pendingOrder = [];
  String _pendingCustomerName = '';

  @override
  void initState() {
    super.initState();
    _restoreState();
    _loadVoicePreferences();
  }

  /// 🧠 Restores conversation memory + voice settings from previous sessions.
  Future<void> _restoreState() async {
    await VoiceService.loadVoiceEnabled();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMessages = prefs.getString('ai_chat_messages');
      final savedHistory = prefs.getString('ai_conversation_history');
      if (!mounted) return;
      setState(() {
        // Sync the AI screen's voice toggle with the GLOBAL app voice switch.
        _voiceFeedbackEnabled = VoiceService.voiceEnabled;
        if (savedHistory != null && savedHistory.isNotEmpty) {
          final list = jsonDecode(savedHistory) as List<dynamic>;
          _conversationHistory = list
              .map((e) => Map<String, String>.from(e as Map))
              .toList();
        }
        if (savedMessages != null && savedMessages.isNotEmpty) {
          final list = jsonDecode(savedMessages) as List<dynamic>;
          _messages.addAll(list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
        }
        if (_messages.isEmpty) _addWelcomeMessage();
      });
    } catch (e) {
      _addWelcomeMessage();
    }
    _scrollToBottom();
  }

  /// 💾 Persists chat + memory so the AI remembers across app restarts.
  Future<void> _persistMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatForStorage = _messages
          .map((m) => {'text': m['text'], 'isUser': m['isUser']})
          .toList();
      await prefs.setString('ai_chat_messages', jsonEncode(chatForStorage));
      await prefs.setString(
          'ai_conversation_history', jsonEncode(_conversationHistory));
    } catch (e) {
      debugPrint('⚠️ AI memory persist failed: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
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

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showToast('Copied to clipboard');
  }

  void _shareResponse(String text) async {
    await Share.share(text, subject: 'AI Assistant Response');
  }

  void _editUserMessage(Map<String, dynamic> message, String originalText) {
    final TextEditingController editController = TextEditingController(text: originalText);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newText = editController.text.trim();
              if (newText.isNotEmpty) {
                setState(() {
                  final index = _messages.indexWhere((msg) => msg == message);
                  if (index != -1) _messages.removeAt(index);
                });
                _messageController.text = newText;
                _sendMessage();
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Send Edited'),
          ),
        ],
      ),
    );
  }

  void _goToCalculator() {
    if (_pendingOrder.isEmpty) {
      _showToast('No pending order. Type "order 2 beer" first.', isError: true);
      return;
    }

    final orderBridge = OrderBridge();
    orderBridge.clearOrder();

    for (final item in _pendingOrder) {
      orderBridge.addDrink(item['drink'] as Drink, item['quantity'] as int);
    }

    if (_pendingCustomerName.isNotEmpty) {
      orderBridge.setCustomerName(_pendingCustomerName);
    }

    _showToast('${_pendingOrder.length} item(s) transferred to checkout');
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CalculatorScreen()),
        ).then((_) {
          _pendingOrder.clear();
          _pendingCustomerName = '';
        });
      }
    });
  }

  void _addWelcomeMessage() {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final drinks = drinkProvider.customDrinks;
    final drinkList = drinks.isNotEmpty
        ? drinks.take(5).map((d) => '• ${d.name} - ${CurrencyHelper.format(d.price)}').join('\n')
        : 'No drinks added yet';

    _messages.add({
      'text': "Hello! I'm your AI Drink Assistant.\n\n"
          "I can help you with:\n"
          "• Place Orders - Type 'order 2 beer'\n"
          "• Check Prices - Ask 'price of top'\n"
          "• Stock Levels - Ask 'stock of mutzig'\n"
          "• Voice Commands - Tap the mic button\n"
          "• Recommendations - Ask 'what should I drink'\n\n"
          "${drinks.isNotEmpty ? 'Available Drinks:\n$drinkList' : 'No drinks added yet'}",
      'isUser': false,
    });
  }

  Future<void> _toggleVoiceCommand() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() { _isListening = false; _voiceStatus = ''; });
      return;
    }

    setState(() { _isLoading = true; _voiceStatus = 'Initializing...'; });
    _scrollToBottom();

    final initialized = await _voiceService.initialize();
    setState(() => _isLoading = false);

    if (!initialized) {
      _showToast('Speech recognition not available', isError: true);
      setState(() => _voiceStatus = '');
      return;
    }

    setState(() { _isListening = true; _voiceStatus = 'Listening...'; });
    _scrollToBottom();

    await _voiceService.startListening(
      onResult: (text) {
        setState(() { _isListening = false; _voiceStatus = 'Heard: "$text"'; });
        _processVoiceCommand(text);
      },
      onError: (error) {
        setState(() { _isListening = false; _voiceStatus = 'Error: $error'; });
      },
    );
  }

  void _processVoiceCommand(String text) {
    final command = VoiceService.parseCommand(text);
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);

    _messages.add({'text': '"$text"', 'isUser': true});
    _scrollToBottom();

    switch (command.type) {
      case VoiceCommandType.add:
        if (command.drinkName != null) {
          final drinks = drinkProvider.customDrinks;
          final matchedDrink = drinks.where((d) => 
            d.name.toLowerCase().contains(command.drinkName!.toLowerCase())
          ).firstOrNull;

          if (matchedDrink != null) {
            _addToOrder(matchedDrink, command.quantity);
          } else {
            _messages.add({
              'text': 'Drink "${command.drinkName}" not found.',
              'isUser': false,
            });
            if (_voiceFeedbackEnabled) _voiceService.speak('Drink not found');
          }
        }
        break;

      case VoiceCommandType.clear:
        setState(() { _pendingOrder.clear(); });
        _messages.add({'text': 'Order cleared. Ready for new order.', 'isUser': false});
        if (_voiceFeedbackEnabled) _voiceService.speak('Order cleared');
        break;

      case VoiceCommandType.finalize:
        if (_pendingOrder.isNotEmpty) _goToCalculator();
        else _showToast('No order to finalize', isError: true);
        break;

      default:
        _messages.add({
          'text': 'Try saying: "Add 2 beer", "Clear all", or "Search for Fanta"',
          'isUser': false,
        });
        break;
    }

    setState(() {});
    _clearVoiceStatus();
    _scrollToBottom();
  }

  void _addToOrder(Drink drink, int quantity) {
    setState(() {
      final existingIndex = _pendingOrder.indexWhere((item) => 
        (item['drink'] as Drink).id == drink.id
      );
      
      if (existingIndex != -1) {
        _pendingOrder[existingIndex]['quantity'] += quantity;
      } else {
        _pendingOrder.add({'drink': drink, 'quantity': quantity});
      }
    });
    
    final total = _getOrderTotal();
    final responseText = 'Added ${quantity}x ${drink.name}. Total: ${CurrencyHelper.format(total)}. Add more or checkout?';
    
    _messages.add({'text': responseText, 'isUser': false});
    _conversationHistory.add({'role': 'assistant', 'content': responseText});
    if (_voiceFeedbackEnabled) _voiceService.speak('Added ${quantity} ${drink.name}');
    _scrollToBottom();
  }

  double _getOrderTotal() {
    return _pendingOrder.fold<double>(0, (sum, item) => 
      sum + ((item['drink'] as Drink).price * (item['quantity'] as int))
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _messages.add({'text': message, 'isUser': true});
      _messageController.clear();
    });
    _scrollToBottom();
    _conversationHistory.add({'role': 'user', 'content': message});
    
    Future.delayed(const Duration(milliseconds: 500), () => _generateAIResponse(message));
  }

  void _generateAIResponse(String userMessage) async {
    setState(() => _isLoading = true);
    final response = await _getAIResponseAsync(userMessage);
    setState(() {
      _messages.add({'text': response, 'isUser': false});
      _isLoading = false;
    });
    _persistMemory(); // 💾 remember across restarts
    _scrollToBottom();
  }

  Future<String> _getAIResponseAsync(String message) async {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final drinks = drinkProvider.customDrinks;
    final lowerMessage = message.toLowerCase();
    
    // Parse order commands
    final orderMatch = RegExp(r'(?:order|buy|add|get)\s+(\d+)\s+(.+)', caseSensitive: false)
        .firstMatch(lowerMessage);
    if (orderMatch != null) {
      final quantity = int.tryParse(orderMatch.group(1) ?? '1') ?? 1;
      final drinkName = orderMatch.group(2)?.trim() ?? '';
      final matchedDrink = drinks.where((d) => 
        d.name.toLowerCase().contains(drinkName.toLowerCase())
      ).firstOrNull;
      
      if (matchedDrink != null) {
        if (matchedDrink.currentStock >= quantity) {
          _addToOrder(matchedDrink, quantity);
          return 'Processing your order...';
        } else {
          return 'Insufficient stock! ${matchedDrink.name} only has ${matchedDrink.currentStock} left.';
        }
      } else {
        final suggestions = drinks.where((d) => 
          d.name.toLowerCase().contains(drinkName.substring(0, 3))
        ).take(3).map((d) => d.name).join(', ');
        return '"$drinkName" not found. Did you mean: $suggestions?';
      }
    }
    
    // Checkout command
    if (lowerMessage.contains('checkout') || lowerMessage.contains('proceed') || 
        lowerMessage == 'yes' || lowerMessage == 'ok' || lowerMessage == 'y') {
      if (_pendingOrder.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _goToCalculator());
        return 'Taking you to checkout with ${_pendingOrder.length} item(s), total ${CurrencyHelper.format(_getOrderTotal())}.';
      } else {
        return 'No orders to checkout. Place an order first like "order 2 beer".';
      }
    }
    
    // Clear command
    if (lowerMessage.contains('clear') || lowerMessage.contains('reset')) {
      setState(() { _pendingOrder.clear(); });
      return 'Order cleared. Ready for new orders!';
    }
    
    // Check stock command
    if (lowerMessage.contains('stock') || lowerMessage.contains('available')) {
      final drinkName = lowerMessage.replaceAll(RegExp(r'stock|available|of'), '').trim();
      if (drinkName.isNotEmpty) {
        final drink = drinks.where((d) => d.name.toLowerCase().contains(drinkName)).firstOrNull;
        if (drink != null) {
          return '${drink.name}: ${drink.currentStock} ${drink.unit}(s) available. Minimum stock: ${drink.minimumLevel}.';
        }
      }
      final stockList = drinks.map((d) => '• ${d.name}: ${d.currentStock} ${d.unit}(s)').join('\n');
      return 'Current Stock:\n$stockList';
    }
    
    // Price check
    if (lowerMessage.contains('price') || lowerMessage.contains('cost')) {
      final drinkName = lowerMessage.replaceAll(RegExp(r'price|cost|of|how much'), '').trim();
      if (drinkName.isNotEmpty) {
        final drink = drinks.where((d) => d.name.toLowerCase().contains(drinkName)).firstOrNull;
        if (drink != null) {
          final profit = drink.price - drink.purchasePrice;
          return '${drink.name}: ${CurrencyHelper.format(drink.price)} each\n'
                 'Cost: ${CurrencyHelper.format(drink.purchasePrice)}\n'
                 'Profit: ${CurrencyHelper.format(profit)} per unit';
        }
      }
      final priceList = drinks.map((d) => '• ${d.name}: ${CurrencyHelper.format(d.price)}').join('\n');
      return 'Price List:\n$priceList';
    }
    
    // Recommendations
    if (lowerMessage.contains('recommend') || lowerMessage.contains('suggest')) {
      final topDrinks = drinks.where((d) => d.currentStock > 5).take(3);
      if (topDrinks.isNotEmpty) {
        return 'Recommendations:\n${topDrinks.map((d) => '• ${d.name} - ${CurrencyHelper.format(d.price)} (${d.currentStock} in stock)').join('\n')}';
      }
      return 'Check out our available drinks above.';
    }
    
    // Smart AI response for other queries
    if (drinks.isEmpty) {
      return "No drinks in inventory. Please add drinks in Drink Management first!";
    }

    final drinkDetails = drinks.map((d) {
      final profit = d.price - d.purchasePrice;
      return '${d.name}: ${CurrencyHelper.format(d.price)} | Stock: ${d.currentStock} | Profit: ${CurrencyHelper.format(profit)}';
    }).join('\n');
    
    String conversationContext = '';
    if (_conversationHistory.isNotEmpty) {
      // 🧠 Full recent memory (last 10 turns) so the AI remembers the conversation
      final recent = _conversationHistory.length > 10
          ? _conversationHistory.sublist(_conversationHistory.length - 10)
          : _conversationHistory;
      conversationContext = '\nCONVERSATION MEMORY (oldest first):\n${recent.map((m) => '${m['role']}: ${m['content']}').join('\n')}';
    }
    
    String orderContext = '';
    if (_pendingOrder.isNotEmpty) {
      orderContext = '\nCurrent Order Total: ${CurrencyHelper.format(_getOrderTotal())} (${_pendingOrder.length} items)';
    }
    
    final prompt = '''
You are Drink Quick Cal AI - smart, friendly, concise. Answer in under 100 words.

INVENTORY:
$drinkDetails
$orderContext
$conversationContext

USER: $message

Be helpful. Suggest drinks. Ask follow-ups naturally.
''';

    try {
      final response = await _groqService.getResponse(prompt);
      _conversationHistory.add({'role': 'assistant', 'content': response});
      if (_conversationHistory.length > 20) {
        _conversationHistory = _conversationHistory.sublist(_conversationHistory.length - 20);
      }
      return response;
    } catch (e) {
      return "Sorry, I'm having trouble connecting. Please try again.";
    }
  }

  void _quickSuggestion(String text) {
    _messageController.text = text;
    _sendMessage();
  }

  /// Loads speech rate / language / gender preferences (voice on/off is
  /// handled globally by `VoiceService.loadVoiceEnabled` in _restoreState).
  Future<void> _loadVoicePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      _speechLanguage = prefs.getString('speech_language') ?? 'en-US';
      _voiceGender = prefs.getString('voice_gender') ?? 'female';
    });
  }

  Future<void> _saveVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_feedback', _voiceFeedbackEnabled);
    await VoiceService.setVoiceEnabled(_voiceFeedbackEnabled); // 🌐 global key
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setString('speech_language', _speechLanguage);
    await prefs.setString('voice_gender', _voiceGender);
  }

  void _clearVoiceStatus() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _voiceStatus = '');
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _conversationHistory.clear();
      _pendingOrder.clear();
      _addWelcomeMessage();
    });
    _persistMemory(); // 💾 clear stored memory too
    _showToast('Chat cleared');
  }

  void _showAboutAI() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About AI Assistant'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drink Quick Cal AI', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Smart order placement'),
            Text('• Real-time stock checks'),
            Text('• Price & profit analysis'),
            Text('• Voice commands supported'),
            Text('• Recommendations engine'),
            SizedBox(height: 12),
            Text('Powered by Groq AI', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showVoiceSettings() {
    double tempRate = _speechRate;
    String tempGender = _voiceGender;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Voice Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Voice Feedback'),
                subtitle: Text(_voiceFeedbackEnabled ? 'On' : 'Off'),
                value: _voiceFeedbackEnabled,
                onChanged: (value) {
                  setDialogState(() {});
                  setState(() {
        _voiceFeedbackEnabled = value;
        VoiceService.setVoiceEnabled(value); // 🌐 toggles voice for the WHOLE app
        if (!value) _voiceService.stopSpeaking(); // cut off any speech mid-sentence
      });
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Voice Gender'),
                subtitle: Text(tempGender == 'male' ? 'Male' : 'Female'),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'female', label: Text('Female')),
                    ButtonSegment(value: 'male', label: Text('Male')),
                  ],
                  selected: {tempGender},
                  onSelectionChanged: (set) => setDialogState(() => tempGender = set.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Speech Speed'),
                    Slider(
                      value: tempRate,
                      min: 0.25,
                      max: 1.0,
                      divisions: 3,
                      label: '${(tempRate * 100).toInt()}%',
                      onChanged: (value) => setDialogState(() => tempRate = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _speechRate = tempRate;
                  _voiceGender = tempGender;
                });
                _voiceService.updateSpeechSettings(rate: _speechRate);
                _voiceService.setVoiceGender(_voiceGender);
                _saveVoiceSettings();
                Navigator.pop(context);
                _showToast('Voice settings saved');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    return  GestureDetector(
    onTap: () => LockService().resetTimer(),
    onPanDown: (_) => LockService().resetTimer(),
    onScaleStart: (_) => LockService().resetTimer(),
    onLongPress: () => LockService().resetTimer(),
    behavior: HitTestBehavior.translucent,
    child:Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        foregroundColor: Colors.white,
        backgroundColor: theme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChat,
            tooltip: 'Clear Chat',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              switch (value) {
                case 'voice_settings': _showVoiceSettings(); break;
                case 'about': _showAboutAI(); break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'voice_settings', child: Text('Voice Settings')),
              const PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)],
          ),
        ),
        child: Column(
          children: [
            // Loading indicator
            if (_isLoading)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('AI is thinking...', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            
            // Voice status
            if (_voiceStatus.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                color: _isListening ? Colors.red : Colors.black87,
                child: Row(
                  children: [
                    if (_isListening) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_voiceStatus, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  ],
                ),
              ),
            
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(
                    msg['text'] as String,
                    msg['isUser'] as bool,
                    theme,
                    isMobile,
                  );
                },
              ),
            ),
            
            // Quick suggestions - responsive
            if (isMobile)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip('Order beer', isMobile),
                      const SizedBox(width: 6),
                      _buildChip('Check prices', isMobile),
                      const SizedBox(width: 6),
                      _buildChip('Stock levels', isMobile),
                      const SizedBox(width: 6),
                      _buildChip('Recommend', isMobile),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 16, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildChip('Order beer', isMobile),
                    _buildChip('Check prices', isMobile),
                    _buildChip('Stock levels', isMobile),
                    _buildChip('Recommend', isMobile),
                    _buildChip('Clear order', isMobile),
                    _buildChip('Checkout', isMobile),
                  ],
                ),
              ),
            
            // Input bar
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              color: theme.cardColor,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _toggleVoiceCommand,
                    child: Container(
                      width: isMobile ? 44 : 48,
                      height: isMobile ? 44 : 48,
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.red : theme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: isMobile ? 20 : 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : 20,
                          vertical: isMobile ? 12 : 14,
                        ),
                      ),
                      style: TextStyle(fontSize: isMobile ? 14 : 15),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: theme.primaryColor,
                    radius: isMobile ? 20 : 22,
                    child: IconButton(
                      icon: Icon(Icons.send, color: Colors.white, size: isMobile ? 18 : 20),
                      onPressed: _sendMessage,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser, ThemeData theme, bool isMobile) {
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: isMobile ? 28 : 32,
              height: isMobile ? 28 : 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [theme.primaryColor, Colors.purple]),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(width: isMobile ? 6 : 8),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              constraints: BoxConstraints(
                maxWidth: screenWidth * (isMobile ? 0.75 : 0.7),
              ),
              decoration: BoxDecoration(
                color: isUser ? theme.primaryColor : (isDark ? Colors.grey[800] : Colors.white),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    text,
                    style: TextStyle(
                      color: isUser ? Colors.white : theme.textTheme.bodyLarge?.color,
                      fontSize: isMobile ? 13 : 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _copyToClipboard(text),
                        child: Icon(Icons.copy, size: isMobile ? 12 : 14, color: isUser ? Colors.white70 : Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _shareResponse(text),
                        child: Icon(Icons.share, size: isMobile ? 12 : 14, color: isUser ? Colors.white70 : Colors.grey),
                      ),
                      if (isUser) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _editUserMessage({'text': text, 'isUser': true}, text),
                          child: Icon(Icons.edit, size: isMobile ? 12 : 14, color: isUser ? Colors.white70 : Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            SizedBox(width: isMobile ? 6 : 8),
            CircleAvatar(
              radius: isMobile ? 14 : 16,
              backgroundColor: theme.primaryColor,
              child: Icon(Icons.person, size: isMobile ? 12 : 14, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool isMobile) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  
  return FilterChip(
    label: Text(
      label, 
      style: TextStyle(
        fontSize: isMobile ? 11 : 12,
        color: isDark ? Colors.white : theme.primaryColor,  // ← Fix: Dynamic text color
      ),
    ),
    onSelected: (_) => _quickSuggestion(label),
    backgroundColor: isDark 
        ? Colors.white.withValues(alpha: 0.2) 
        : theme.primaryColor.withValues(alpha: 0.1),  // ← Fix: Light background for light theme
    selectedColor: Colors.green,
    checkmarkColor: Colors.white,
    padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 4 : 6),
  );
}
}