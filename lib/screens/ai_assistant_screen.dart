// screens/ai_assistant_screen.dart
import 'dart:convert';
import 'dart:io';
import '../utils/i18n.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/providers/plan_provider.dart';
import '../widgets/upgrade_required.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:drinks_calculator_fixed/providers/drink_provider.dart';
import 'package:drinks_calculator_fixed/providers/inventory_provider.dart';
import 'package:drinks_calculator_fixed/services/voice_service.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';
import 'package:drinks_calculator_fixed/utils/expiry_alert_helper.dart';
import 'package:drinks_calculator_fixed/utils/forecast_helper.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/services/groq_service.dart';
import 'package:drinks_calculator_fixed/screens/calculator_screen.dart';
import 'package:drinks_calculator_fixed/services/order_bridge.dart';
import 'package:drinks_calculator_fixed/services/lock_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:drinks_calculator_fixed/utils/ai_order_parser.dart';
import 'package:drinks_calculator_fixed/widgets/ai_thinking_indicator.dart';

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
  bool _isReadingImage = false;

  /// True while the mic should reopen after each spoken sentence.
  bool _voiceContinuous = false;
  String _loadingLabel = '';
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
          .map((m) => {
                'text': m['text'],
                'isUser': m['isUser'],
                // Keep the lightweight markers so a restored chat still shows
                // the photo (native) and which messages were spoken.
                if (m['kind'] != null) 'kind': m['kind'],
                if (m['imagePath'] != null) 'imagePath': m['imagePath'],
              })
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
    // Never leave the mic open behind a closed screen.
    _voiceContinuous = false;
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
    _showToast(t('ai_copiedToClipboard'));
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
        title: Text(t('ai_editTitle')),
        content: TextField(
          controller: editController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: t('ai_editYourMessage'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('ai_cancel'))),
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
            child: Text(t('ai_sendEditedBtn')),
          ),
        ],
      ),
    );
  }

  void _goToCalculator() {
    if (_pendingOrder.isEmpty) {
      _showToast(t('ai_noPendingOrder'), isError: true);
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

    _showToast(t('ai_itemsTransferred').replaceAll('@count', '${_pendingOrder.length}'));
    
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
      // Tapping the mic while it listens ends the conversation.
      _voiceContinuous = false;
      await _voiceService.stopListening();
      setState(() { _isListening = false; _voiceStatus = ''; });
      return;
    }

    setState(() { _isLoading = true; _voiceStatus = t('ai_initializing'); });
    _scrollToBottom();

    final initialized = await _voiceService.initialize();
    setState(() => _isLoading = false);

    if (!initialized) {
      _showToast(t('ai_speechNotAvailable'), isError: true);
      setState(() => _voiceStatus = '');
      return;
    }

    // Continuous mode: after each sentence the mic reopens by itself, so the user
    // can order several drinks in a row without tapping again. It stops when they
    // tap the mic, say "stop", or leave the screen.
    _voiceContinuous = true;
    await _startVoiceListening();
  }

  /// Opens the mic once (used both for the first tap and for auto-restart).
  Future<void> _startVoiceListening() async {
    if (!mounted || !_voiceContinuous) return;
    setState(() { _isListening = true; _voiceStatus = t('ai_listening'); });
    _scrollToBottom();

    await _voiceService.startListening(
      // Live feedback: the words appear while the sentence is being spoken.
      onPartial: (partial) {
        if (!mounted) return;
        setState(() => _voiceStatus =
            '${t('ai_listening')} "…$partial"');
      },
      onResult: (text) async {
        final heard = text.trim();
        setState(() {
          _isListening = false;
          // Show the transcript in quotes so it is clearly what the assistant
          // heard, matching the copy used in the chat bubble.
          _voiceStatus = t('ai_heard').replaceAll('@text', '"$heard"');
        });
        _processVoiceCommand(heard);

        // Keep the conversation going unless the user asked to stop.
        if (_voiceContinuous && !_isStopPhrase(heard)) {
          await Future.delayed(const Duration(milliseconds: 700));
          await _startVoiceListening();
        } else {
          _voiceContinuous = false;
        }
      },
      onError: (error) {
        setState(() {
          _isListening = false;
          _voiceContinuous = false;
          _voiceStatus = 'Error: $error';
        });
      },
    );
  }

  /// True when the spoken sentence asks to stop listening (EN or FR).
  bool _isStopPhrase(String text) {
    final lower = text.toLowerCase().trim();
    const stops = [
      'stop listening',
      'stop',
      'cancel',
      'pause',
      'arrête',
      'arrete',
      'stop écoute',
      'annuler',
      'terminé',
      'termine',
    ];
    return stops.any((s) => lower == s || lower.endsWith(' $s'));
  }

  /// 📷 Reads a photo of an order (handwritten note, receipt, screenshot, menu)
  /// and turns the detected drinks into a pending order ready for the calculator.
  Future<void> _analyzeImage(ImageSource source) async {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final drinks = drinkProvider.customDrinks;

    try {
      //  The camera needs the runtime permission on Android/iOS/macOS. On the
      // web there is no runtime permission API, so the browser prompt is used
      // and we must not block the picker.
      if (source == ImageSource.camera && !kIsWeb) {
        try {
          final status = await Permission.camera.request();
          if (!status.isGranted) {
            if (mounted) _showToast(t('ai_cameraDenied'), isError: true);
            return;
          }
        } catch (_) {
          // Platform without a runtime permission API — let the picker decide.
        }
      }

      // 📉 Keep the photo small: the AI only needs the drink names, and a smaller
      // image is faster and never hits a server body limit. 1024px / q60 lands
      // around 80-200 KB.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 60,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      debugPrint('🖼️ Sending ${(bytes.length / 1024).toStringAsFixed(0)} KB '
          'to the AI vision endpoint');
      final base64Image = base64Encode(bytes);

      setState(() {
        _isReadingImage = true;
        _loadingLabel = t('ai_readingImage');
      });
      _messages.add({
        'text': t('ai_imageSent'),
        'isUser': true,
        'kind': 'image',
        // Show the actual photo in the chat (Gemini-style). Native keeps a file
        // path that survives restarts; web keeps the bytes for the session.
        if (!kIsWeb && picked.path.isNotEmpty) 'imagePath': picked.path,
        if (kIsWeb) 'imageBase64': base64Image,
      });
      _scrollToBottom();
      _persistMemory();

      final response = await _groqService.analyzeImage(
        base64Image: base64Image,
        drinks: drinks.map((d) => d.name).toList(),
        prompt: _pendingOrder.isEmpty
            ? ''
            : 'The order already contains ${_pendingOrder.map((i) => '${i['quantity']}x ${(i['drink'] as Drink).name}').join(', ')}.',
      );

      // Any drinks the vision model recognised are added to the pending order.
      final matched = AIOrderParser.matchLines(
        AIOrderParser.extractOrderLines(response),
        drinks,
      );
      setState(() {
        _isReadingImage = false;
        for (final line in matched) {
          _addToOrderSilently(line.drink, line.quantity);
        }
        final visible = AIOrderParser.stripOrderBlock(response);
        _messages.add({
          'text': matched.isEmpty
              ? visible
              : '$visible\n\n✅ ${t('ai_addedItems').replaceAll('@items', matched.map((m) => '${m.quantity}x ${m.drink.name}').join(', '))}',
          'isUser': false,
        });
      });
      _persistMemory();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isReadingImage = false);
        _showToast('${t('ai_imageFailed')}: $e', isError: true);
      }
    }
  }

  /// Lets the user choose camera or gallery before analysing.
  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(t('ai_takePhoto')),
            onTap: () {
              Navigator.pop(ctx);
              _analyzeImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(t('ai_chooseImage')),
            onTap: () {
              Navigator.pop(ctx);
              _analyzeImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _processVoiceCommand(String text) {
    final command = VoiceService.parseCommand(text);

    _messages.add({
      'text': '"$text"',
      'isUser': true,
      // Spoken commands are real chat messages: they are shown with a mic badge
      // and persisted, exactly like typed ones (they used to be lost on restart).
      'kind': 'voice',
    });
    _scrollToBottom();

    switch (command.type) {
      case VoiceCommandType.add:
        // 🎙️ Handles several items in one breath ("2 beer and a soda") and
        // fuzzy names ("mutzi" → Mutzig).
        _handleOrderText(text);
        break;

      case VoiceCommandType.clear:
        setState(() => _pendingOrder.clear());
        _messages.add({'text': t('ai_orderClearedLong'), 'isUser': false});
        if (_voiceFeedbackEnabled) _voiceService.speak(t('ai_orderClearedShort'));
        break;

      case VoiceCommandType.finalize:
        if (_pendingOrder.isNotEmpty) _goToCalculator();
        else _showToast(t('ai_noOrderFinalize'), isError: true);
        break;

      default:
        if (command.drinkName != null) {
          _handleOrderText(text);
        } else {
          _messages.add({'text': t('ai_trySaying'), 'isUser': false});
        }
        break;
    }

    setState(() {});
    _persistMemory(); // 💾 spoken commands survive a restart too
    _clearVoiceStatus();
    _scrollToBottom();
  }

  /// Parses an order phrase, matches it against the inventory and adds every
  /// line to the pending order. Returns the number of items added.
  int _handleOrderText(String text, {bool announce = true}) {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final drinks = drinkProvider.customDrinks;

    final requests = AIOrderParser.parseOrderLines(text, inventory: drinks);
    final matched = AIOrderParser.matchLines(requests, drinks);

    if (matched.isEmpty) {
      final unknown = requests.isNotEmpty
          ? requests.map((r) => r.name).join(', ')
          : text.trim();
      _messages.add({
        'text': t('ai_drinkNotFoundSimple').replaceAll('@name', unknown),
        'isUser': false,
      });
      if (_voiceFeedbackEnabled) _voiceService.speak(t('ai_drinkNotFoundShort'));
      return 0;
    }

    setState(() {
      for (final line in matched) {
        _addToOrderSilently(line.drink, line.quantity);
      }
    });

    // 📉 Warn when the request exceeds what is in stock (still added so the
    // manager can decide, mirroring the calculator's behaviour).
    final shortages = matched
        .where((m) => m.drink.currentStock < m.quantity)
        .map((m) => '${m.drink.name} (${m.drink.currentStock})')
        .toList();

    final summary = matched
        .map((m) => '${m.quantity}x ${m.drink.name}')
        .join(', ');
    final total = CurrencyHelper.format(_getOrderTotal());

    if (announce) {
      _messages.add({
        'text': '${t('ai_addedItems').replaceAll('@items', summary)}\n'
            '${t('ai_orderTotal')}: $total'
            '${shortages.isEmpty ? '' : '\n⚠️ ${t('ai_lowStockWarning').replaceAll('@items', shortages.join(', '))}'}',
        'isUser': false,
      });
      if (_voiceFeedbackEnabled) {
        _voiceService.speak(
          t('ai_addedToOrder')
              .replaceAll('@count', '${matched.fold<int>(0, (s, m) => s + m.quantity)}')
              .replaceAll('@name', matched.map((m) => m.drink.name).join(', ')),
        );
      }
    }
    _scrollToBottom();
    return matched.length;
  }

  /// Same as [_addToOrder] but without chat/voice feedback (used in bulk).
  void _addToOrderSilently(Drink drink, int quantity) {
    final existingIndex =
        _pendingOrder.indexWhere((item) => (item['drink'] as Drink).id == drink.id);
    if (existingIndex != -1) {
      _pendingOrder[existingIndex]['quantity'] += quantity;
    } else {
      _pendingOrder.add({'drink': drink, 'quantity': quantity});
    }
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
    setState(() {
      _isLoading = true;
      _loadingLabel = t('ai_thinking');
    });
    final response = await _getAIResponseAsync(userMessage);
    setState(() {
      _messages.add({'text': response, 'isUser': false});
      _isLoading = false;
      _loadingLabel = '';
    });
    _persistMemory(); // 💾 remember across restarts
    _scrollToBottom();
  }

  Future<String> _getAIResponseAsync(String message) async {
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final drinks = drinkProvider.customDrinks;
    final lowerMessage = message.toLowerCase();

    // 🧠 Order intent — handled locally with the smart parser (multi-item, fuzzy)
    // so ordering never depends on the network.
    final orderIntent = RegExp(
      r'\b(order|add|buy|get|give|bring|want|need|take)\b',
      caseSensitive: false,
    ).hasMatch(lowerMessage);
    if (orderIntent) {
      final added = _handleOrderText(message, announce: false);
      if (added > 0) {
        final summary = _pendingOrder
            .map((item) =>
                '${item['quantity']}x ${(item['drink'] as Drink).name}')
            .join(', ');
        return '${t('ai_addedItems').replaceAll('@items', summary)}\n'
            '${t('ai_orderTotal')}: ${CurrencyHelper.format(_getOrderTotal())}\n'
            '${t('ai_sendToCalculatorHint')}';
      }
      // Nothing matched — fall through so the AI can clarify.
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

    // ⏰ Batches expiring within 30 days + expected demand, so the assistant can
    // push soon-to-expire stock and offer bundles instead of letting it spoil.
    String expiryContext = '';
    try {
      final inventoryProvider =
          Provider.of<InventoryProvider>(context, listen: false);
      final forecast = computeForecast(
        transactions: inventoryProvider.transactions,
        inventory: inventoryProvider.inventoryItems,
      );
      final alerts = computeExpiryAlerts(drinks: drinks, forecast: forecast);
      if (alerts.isNotEmpty) {
        expiryContext = '\nEXPIRING SOON (within 30 days, with expected demand):\n' +
            alerts
                .take(8)
                .map((a) =>
                    '${a.drinkName}: ${a.isExpired ? 'EXPIRED' : '${a.daysLeft} days left'} | '
                    'stock: ${a.currentStock} | expected demand (7 days): ${a.forecastDemand.toStringAsFixed(1)}'
                    '${a.recommendedOrder > 0 ? ' | suggested order: ${a.recommendedOrder}' : ''}')
                .join('\n');
      }
    } catch (_) {}
    
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
You are Drink Quick Cal AI - smart, friendly and concise. Answer in under 100 words.
You are also the shop's ordering assistant: the user's order is added to the
calculator automatically when you emit a machine-readable line.

INVENTORY (name: price | stock | profit):
$drinkDetails
$expiryContext
$orderContext
$conversationContext

USER: $message

Rules:
- Recommend drinks from the inventory above and quote real prices/stock.
- If the inventory block above lists EXPIRING SOON items, mention which ones
  should be sold first and suggest a promotion or bundle for them.
- If the user wants to order/buy/add anything, finish your reply with one line:
ORDER_JSON: [{"name":"<exact drink name as written above>","qty":<number>}]
  Include every requested drink in that single line, and never invent drinks
  that are not in the inventory.
- If the user is not ordering, do NOT output ORDER_JSON.
- Be helpful, suggest alternatives and ask follow-ups naturally.
''';

    try {
      final response = await _groqService.getResponse(prompt);

      // 🛒 The reply may carry an ORDER_JSON block — apply it directly to the
      // pending order so it is one tap away from the calculator.
      final lines = AIOrderParser.extractOrderLines(response);
      if (lines.isNotEmpty) {
        final matched = AIOrderParser.matchLines(lines, drinks);
        if (matched.isNotEmpty) {
          setState(() {
            for (final line in matched) {
              _addToOrderSilently(line.drink, line.quantity);
            }
          });
        }
      }

      final visible = AIOrderParser.stripOrderBlock(response);
      final historyText = visible.isEmpty ? response : visible;
      _conversationHistory.add({'role': 'assistant', 'content': historyText});
      if (_conversationHistory.length > 20) {
        _conversationHistory = _conversationHistory.sublist(_conversationHistory.length - 20);
      }
      return historyText;
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
    final storedTtsLocale = prefs.getString('speech_language') ?? 'en-US';
    setState(() {
      _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      _speechLanguage =
          storedTtsLocale.toLowerCase().startsWith('fr') ? 'fr-FR' : 'en-US';
      _voiceGender = prefs.getString('voice_gender') ?? 'female';
    });
    // Apply immediately so the very first spoken reply uses the right voice.
    await _voiceService.applyVoiceSettings(
      language: _speechLanguage,
      gender: _voiceGender,
      rate: _speechRate,
      persist: false,
    );
  }

  Future<void> _saveVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_feedback', _voiceFeedbackEnabled);
    await VoiceService.setVoiceEnabled(_voiceFeedbackEnabled); //  global key
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setString('speech_language', _speechLanguage);
    await prefs.setString('voice_gender', _voiceGender);
    // 🗣️ Push language + gender to the engine (works for EN and FR).
    await _voiceService.applyVoiceSettings(
      language: _speechLanguage,
      gender: _voiceGender,
      rate: _speechRate,
      persist: false,
    );
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
    _showToast(t('ai_chatCleared'));
  }

  void _showAboutAI() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('ai_aboutTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drink Quick Cal AI', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(t('ai_featureOrder')),
            Text(t('ai_featureStock')),
            Text(t('ai_featurePrice')),
            Text(t('ai_featureVoice')),
            Text(t('ai_featureRecommend')),
            SizedBox(height: 12),
            Text(t('ai_poweredBy'), style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('ai_close'))),
        ],
      ),
    );
  }

  void _showVoiceSettings() {
    double tempRate = _speechRate;
    String tempGender = _voiceGender;
    String tempLanguage = _speechLanguage;

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 380;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isSmall ? 12 : 24,
            vertical: 24,
          ),
          // 📱 scrollable so the dialog never overflows on small phones
          scrollable: true,
          title: Text(t('ai_voiceSettingsTitle')),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              minWidth: isSmall ? 240 : 300,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('ai_voiceFeedbackSwitch')),
                  subtitle: Text(_voiceFeedbackEnabled
                      ? t('ai_onState')
                      : t('ai_offState')),
                  value: _voiceFeedbackEnabled,
                  onChanged: (value) {
                    setDialogState(() {});
                    setState(() {
                      _voiceFeedbackEnabled = value;
                      VoiceService.setVoiceEnabled(value); // 🌐 whole app
                      if (!value) _voiceService.stopSpeaking();
                    });
                  },
                ),
                const Divider(),

                // 🌍 Language (voice + recognition) — EN and FR supported.
                Text(t('ai_voiceLanguageTitle'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(t('ai_languageEnglish')),
                      selected: tempLanguage.startsWith('en'),
                      onSelected: (_) =>
                          setDialogState(() => tempLanguage = 'en-US'),
                    ),
                    ChoiceChip(
                      label: Text(t('ai_languageFrench')),
                      selected: tempLanguage.startsWith('fr'),
                      onSelected: (_) =>
                          setDialogState(() => tempLanguage = 'fr-FR'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 🗣️ Male / female voice — works in both languages.
                Text(t('ai_voiceGenderTitle'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(t('ai_femaleOpt')),
                      selected: tempGender == 'female',
                      onSelected: (_) =>
                          setDialogState(() => tempGender = 'female'),
                    ),
                    ChoiceChip(
                      label: Text(t('ai_maleOpt')),
                      selected: tempGender == 'male',
                      onSelected: (_) =>
                          setDialogState(() => tempGender = 'male'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(t('ai_speechSpeedLabel'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: tempRate,
                  min: 0.25,
                  max: 1.0,
                  divisions: 3,
                  label: '${(tempRate * 100).toInt()}%',
                  onChanged: (value) => setDialogState(() => tempRate = value),
                ),

                // 🔊 Try the selected combination right away.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: Text(t('ai_testVoice')),
                    onPressed: () async {
                      await _voiceService.applyVoiceSettings(
                        language: tempLanguage,
                        gender: tempGender,
                        rate: tempRate,
                        persist: false,
                      );
                      await _voiceService.stopSpeaking();
                      await _voiceService.speak(t('ai_voiceTestSentence'));
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('ai_cancel'))),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _speechRate = tempRate;
                  _voiceGender = tempGender;
                  _speechLanguage = tempLanguage;
                });
                _saveVoiceSettings();
                Navigator.pop(context);
                _showToast(t('ai_voiceSettingsSaved'));
              },
              child: Text(t('ai_saveBtn')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<PlanProvider>().canAccess('ai')) {
      return const UpgradeRequiredView();
    }
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
        title: Text(t('b3_aiAssistant')),
        foregroundColor: Colors.white,
        backgroundColor: theme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChat,
            tooltip: t('b3_clearChat'),
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
              PopupMenuItem(value: 'voice_settings', child: Text(t('ai_voiceSettings'))),
              PopupMenuItem(value: 'about', child: Text(t('ai_aboutAI'))),
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
            // Loading indicator — professional animated "AI is thinking" pill
            if (_isLoading || _isReadingImage)
              Container(
                width: double.infinity,
                color: Colors.black26,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: AiThinkingIndicator(
                  label: _loadingLabel.isNotEmpty
                      ? _loadingLabel
                      : (_isReadingImage ? t('ai_readingImage') : t('ai_thinking')),
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
                  return _buildMessageBubble(msg, theme, isMobile);
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
                      _buildChip(t('ai_orderBeer'), isMobile),
                      const SizedBox(width: 6),
                      _buildChip(t('ai_checkPrices'), isMobile),
                      const SizedBox(width: 6),
                      _buildChip(t('ai_stockLevels'), isMobile),
                      const SizedBox(width: 6),
                      _buildChip(t('ai_recommend'), isMobile),
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
                    _buildChip(t('ai_orderBeer'), isMobile),
                    _buildChip(t('ai_checkPrices'), isMobile),
                    _buildChip(t('ai_stockLevels'), isMobile),
                    _buildChip(t('ai_recommend'), isMobile),
                    _buildChip(t('ai_clearOrder'), isMobile),
                    _buildChip(t('ai_checkout'), isMobile),
                  ],
                ),
              ),
            
            // 🛒 Pending order bar — one tap to send everything to the calculator.
            if (_pendingOrder.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: theme.colorScheme.secondaryContainer,
                child: Row(children: [
                  const Icon(Icons.shopping_cart_checkout, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_pendingOrder.fold<int>(0, (s, i) => s + (i['quantity'] as int))} '
                      '${t('ai_itemsInOrder')} · ${CurrencyHelper.format(_getOrderTotal())}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _pendingOrder.clear()),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(t('ai_clearOrderShort')),
                  ),
                  ElevatedButton.icon(
                    onPressed: _goToCalculator,
                    icon: const Icon(Icons.send, size: 16),
                    label: Text(t('ai_toCalculator')),
                  ),
                ]),
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
                  // 📷 Analyse a photo of an order (camera or gallery).
                  GestureDetector(
                    onTap: _isReadingImage ? null : _showImageSourceSheet,
                    child: Container(
                      width: isMobile ? 44 : 48,
                      height: isMobile ? 44 : 48,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: theme.primaryColor,
                        size: isMobile ? 20 : 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: t('ai_askMe'),
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

  /// Renders a chat image: native reads the saved file, web uses the in-memory
  /// bytes. Falls back to a neutral placeholder when neither is available (or the
  /// file was cleaned up by the OS).
  Widget _buildChatImage(String? path, String? base64) {
    if (path != null && path.isNotEmpty && !kIsWeb) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _chatImagePlaceholder(),
          );
        }
      } catch (_) {}
    }
    if (base64 != null && base64.isNotEmpty) {
      try {
        return Image.memory(base64Decode(base64), fit: BoxFit.contain);
      } catch (_) {}
    }
    return _chatImagePlaceholder();
  }

  Widget _chatImagePlaceholder() => Container(
        height: 80,
        width: 130,
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.08),
        child: const Icon(Icons.image_outlined, color: Colors.white70),
      );

  Widget _buildMessageBubble(
      Map<String, dynamic> msg, ThemeData theme, bool isMobile) {
    final text = (msg['text'] as String?) ?? '';
    final isUser = msg['isUser'] == true;
    final imagePath = msg['imagePath'] as String?;
    final imageBase64 = msg['imageBase64'] as String?;
    final kind = msg['kind'] as String?;
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
                  // 📷 The snapped photo, shown right in the conversation like
                  // Gemini does (tap-through not needed — it is the reference).
                  if (imagePath != null || imageBase64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _buildChatImage(imagePath, imageBase64),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (kind == 'voice')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.mic,
                            size: 12,
                            color: isUser ? Colors.white70 : theme.hintColor),
                        const SizedBox(width: 4),
                        Text(
                          t('ai_voiceCommand'),
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  isUser ? Colors.white70 : theme.hintColor),
                        ),
                      ]),
                    ),
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