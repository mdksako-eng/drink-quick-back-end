import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global language service for EN/FR support.
/// Usage in widgets: `t('signIn')`
class LanguageService {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  static const String en = 'en';
  static const String fr = 'fr';

  final ValueNotifier<String> language = ValueNotifier<String>(en);
  bool _loaded = false;

  bool get isFrench => language.value == fr;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      language.value = prefs.getString('app_language') ?? en;
    } catch (_) {}
  }

  Future<void> setLanguage(String code) async {
    language.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', code);
    } catch (_) {}
  }

  void toggle() => setLanguage(isFrench ? en : fr);
}

/// Translate [key] into the current language, falling back to English,
/// then to the key itself if missing.

const Map<String, String> _en = {
  // Auth
  'appName': 'Drink Quick Cal',
  'signIn': 'Sign In',
  'signUp': 'Create Account',
  'createAccount': 'Create Account',
  'welcomeBack': 'Welcome back',
  'email': 'Email',
  'username': 'Username',
  'password': 'Password',
  'confirmPassword': 'Confirm Password',
  'phone': 'Phone',
  'login': 'Login',
  'loggingIn': 'Logging in...',
  'creatingAccount': 'Creating account...',
  'forgotPassword': 'Forgot Password?',
  'haveAccount': 'Already have an account? Sign In',
  'noAccount': "Don't have an account? Create Account",
  'sendCode': 'Send Code',
  'verifyCode': 'Verify Code',
  'resendCode': 'Resend Code',
  'enterCode': 'Enter verification code',
  'registerAsBusiness': 'Register as Business (Manager)',
  'joinCompany': 'Join an existing company',
  'createNewCompany': 'Create a new company',
  'companyName': 'Company Name',
  'companyCode': 'Company Code',
  'companyAddress': 'Company Address',
  'inviteCode': 'Company Invite Code',
  'termsAgree': 'I agree to the Terms of Service and Privacy Policy',
  // Drawer
  'home': 'Home',
  'settings': 'Settings',
  'inventory': 'Inventory',
  'orders': 'Orders',
  'notifications': 'Notifications',
  'logout': 'Logout',
  'staffManagement': 'Staff Management',
  'drinkManagement': 'Drink Management',
  'reports': 'Reports',
  'language': 'Language',
  'english': 'English',
  'french': 'Français',
  'privacyPolicy': 'Privacy Policy',
  'termsOfService': 'Terms',
  // Common actions
  'save': 'Save',
  'cancel': 'Cancel',
  'delete': 'Delete',
  'edit': 'Edit',
  'close': 'Close',
  'ok': 'OK',
  'yes': 'Yes',
  'no': 'No',
  'retry': 'Retry',
  'confirm': 'Confirm',
  'search': 'Search',
  'loading': 'Loading...',
  'error': 'Error',
  'success': 'Success',
  'total': 'Total',
  'quantity': 'Quantity',
  'price': 'Price',
  'amount': 'Amount',
  'date': 'Date',
  'approve': 'Approve',
  'reject': 'Reject',
  'blocked': 'Blocked',
  'active': 'Active',
  // Lock screen
  'sessionTerminated': 'Session Terminated',
  // Notifications screen
  'noNotificationsYet': 'No notifications yet',
  'unreadCount': 'unread',
  'markAllRead': 'Mark all read',
  'clearAll': 'Clear all',
  // Side slider / invoices
  'invoices': 'Invoices',
  'items': 'Items',
  'revenue': 'Revenue',
  'searchByOrderId': 'Search by Order ID...',
  'clearSearch': 'Clear search',
  'today': 'Today',
  'thisWeek': 'This Week',
  'thisMonth': 'This Month',
  'allTime': 'All Time',
  'recent': 'Recent',
  'oldest': 'Oldest',
  'highAmount': 'High Amount',
  'lowAmount': 'Low Amount',
  'activate': 'Activate',
  'deactivate': 'Deactivate',
  // Calculator / sales
  'addToOrder': 'Add to Order',
  'orderSummary': 'Order Summary',
  'selectedDrinks': 'SELECTED DRINKS',
  'selectDrinksAbove': 'Select drinks above',
  'noDrinksSelected': 'No drinks selected',
  'finalizePurchase': 'Finalize Purchase',
  'removeAll': 'Remove all',
  'customerInformation': 'Customer Information',
  'customerName': 'Customer Name',
  'enterCustomerName': 'Enter customer name',
  'pleaseEnterCustomerName': 'Please enter customer name',
  'pleaseEnterCustomerPhone': 'Please enter customer phone number',
  'customerNameRequired': 'Customer name is required',
  'paymentDetails': 'Payment Details',
  'paymentMethod': 'Payment Method',
  'cash': 'Cash',
  'processingPayment': 'Processing Payment',
  'paymentSuccessful': 'Payment Successful',
  'paymentFailed': 'Payment Failed',
  'insufficientPayment': 'Insufficient payment',
  'paymentNotCompleted': 'Payment was not completed by customer',
  'previewInvoice': 'Preview Invoice',
  'invoiceHistory': 'Invoice History',
  'manageDrinks': 'Manage Drinks',
  'adminPanel': 'Admin Panel',
  'noDrinkFound': 'No drink found, kindly add drink',
  'noDrinksFound': 'No drinks found, kindly add drinks',
  'noOrderToDisplay': 'No order to display',
  'outOfStock': 'OUT OF STOCK',
  'confirmLogout': 'Confirm Logout',
  'continue': 'Continue',
  'tryAgain': 'Try Again',
  'checkStatus': 'Check Status',
  'passwordRequired': 'Password Required',
  'enterLoginPassword': 'Enter your login password to continue',
  'enterPassword': 'Enter password',
  'welcome': 'Welcome',
  'verify': 'Verify',
};

const Map<String, String> _fr = {
  // Auth
  'appName': 'Drink Quick Cal',
  'signIn': 'Se connecter',
  'signUp': 'Créer un compte',
  'createAccount': 'Créer un compte',
  'welcomeBack': 'Bon retour',
  'email': 'E-mail',
  'username': "Nom d'utilisateur",
  'password': 'Mot de passe',
  'confirmPassword': 'Confirmer le mot de passe',
  'phone': 'Téléphone',
  'login': 'Connexion',
  'loggingIn': 'Connexion en cours...',
  'creatingAccount': 'Création du compte...',
  'forgotPassword': 'Mot de passe oublié ?',
  'haveAccount': "Vous avez déjà un compte ? Se connecter",
  'noAccount': "Pas de compte ? Créer un compte",
  'sendCode': 'Envoyer le code',
  'verifyCode': 'Vérifier le code',
  'resendCode': 'Renvoyer le code',
  'enterCode': 'Entrez le code de vérification',
  'registerAsBusiness': "S'inscrire comme entreprise (Gérant)",
  'joinCompany': "Rejoindre une entreprise existante",
  'createNewCompany': 'Créer une nouvelle entreprise',
  'companyName': "Nom de l'entreprise",
  'companyCode': "Code de l'entreprise",
  'active': 'Actif',
  // Calculator / sales
  'addToOrder': 'Ajouter à la commande',
  'orderSummary': 'Résumé de la commande',
  'selectedDrinks': 'BOISSONS SÉLECTIONNÉES',
  'selectDrinksAbove': 'Sélectionnez des boissons ci-dessus',
  'noDrinksSelected': 'Aucune boisson sélectionnée',
  'finalizePurchase': "Finaliser l'achat",
  'removeAll': 'Tout retirer',
  'clearAll': 'Tout effacer',
  'customerInformation': 'Informations du client',
  'customerName': 'Nom du client',
  'enterCustomerName': 'Entrez le nom du client',
  'pleaseEnterCustomerName': 'Veuillez entrer le nom du client',
  'pleaseEnterCustomerPhone': 'Veuillez entrer le numéro de téléphone du client',
  'customerNameRequired': 'Le nom du client est requis',
  'paymentDetails': 'Détails du paiement',
  'paymentMethod': 'Mode de paiement',
  'cash': 'Espèces',
  'processingPayment': 'Paiement en cours',
  'paymentSuccessful': 'Paiement réussi',
  'paymentFailed': 'Échec du paiement',
  'insufficientPayment': 'Paiement insuffisant',
  'paymentNotCompleted': 'Paiement non finalisé par le client',
  'previewInvoice': 'Aperçu de la facture',
  'invoiceHistory': 'Historique des factures',
  'manageDrinks': 'Gérer les boissons',
  'adminPanel': 'Panneau admin',
  'noDrinkFound': 'Aucune boisson trouvée, veuillez en ajouter',
  'noDrinksFound': 'Aucune boisson trouvée, veuillez en ajouter',
  'noOrderToDisplay': 'Aucune commande à afficher',
  'outOfStock': 'RUPTURE DE STOCK',
  'confirmLogout': 'Confirmer la déconnexion',
  'continue': 'Continuer',
  'tryAgain': 'Réessayer',
  'checkStatus': 'Vérifier le statut',
  'passwordRequired': 'Mot de passe requis',
  'enterLoginPassword': 'Entrez votre mot de passe pour continuer',
  'enterPassword': 'Entrez le mot de passe',
  'welcome': 'Bienvenue',
  'verify': 'Vérifier',
  'companyAddress': "Adresse de l'entreprise",
  'inviteCode': "Code d'invitation",
  'termsAgree': "J'accepte les Conditions d'utilisation et la Politique de confidentialité",
  // Drawer
  'home': 'Accueil',
  'settings': 'Paramètres',
  'inventory': 'Stock',
  'orders': 'Commandes',
  'notifications': 'Notifications',
  'logout': 'Déconnexion',
  'staffManagement': 'Gestion du personnel',
  'drinkManagement': 'Gestion des boissons',
  'reports': 'Rapports',
  'language': 'Langue',
  'english': 'English',
  'french': 'Français',
  'privacyPolicy': 'Confidentialité',
  'termsOfService': 'Conditions',
  // Common actions
  'save': 'Enregistrer',
  'cancel': 'Annuler',
  'delete': 'Supprimer',
  'edit': 'Modifier',
  'close': 'Fermer',
  'ok': 'OK',
  'yes': 'Oui',
  'no': 'Non',
  'retry': 'Réessayer',
  'confirm': 'Confirmer',
  'search': 'Rechercher',
  'loading': 'Chargement...',
  'error': 'Erreur',
  'success': 'Succès',
  'total': 'Total',
  'quantity': 'Quantité',
  'price': 'Prix',
  'amount': 'Montant',
  'date': 'Date',
  'approve': 'Approuver',
  'reject': 'Rejeter',
  'blocked': 'Bloqué',
  // Lock screen
  'sessionTerminated': 'Session terminée',
  // Notifications screen
  'noNotificationsYet': 'Aucune notification pour le moment',
  'unreadCount': 'non lues',
  'markAllRead': 'Tout marquer comme lu',
  // Side slider / invoices
  'invoices': 'Factures',
  'items': 'Articles',
  'revenue': 'Revenus',
  'searchByOrderId': 'Rechercher par ID de commande...',
  'clearSearch': 'Effacer la recherche',
  'today': "Aujourd'hui",
  'thisWeek': 'Cette semaine',
  'thisMonth': 'Ce mois',
  'allTime': 'Tout',
  'recent': 'Récent',
  'oldest': 'Plus ancien',
  'highAmount': 'Montant élevé',
  'lowAmount': 'Montant faible',
  'activate': 'Activer',
  'deactivate': 'Désactiver',
};

String t(String key) {
  final lang = LanguageService.instance.language.value;
  if (lang == LanguageService.fr && _fr.containsKey(key)) return _fr[key]!;
  if (_en.containsKey(key)) return _en[key]!;
  return key;
}
