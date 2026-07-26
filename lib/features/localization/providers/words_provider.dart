import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum AppLanguage {
  english('en', 'English', 'English'),
  tamil('ta', 'Tamil', 'தமிழ்'),
  malayalam('ml', 'Malayalam', 'മലയാളം'),
  telugu('te', 'Telugu', 'తెలుగు'),
  hindi('hi', 'Hindi', 'हिंदी');

  final String code;
  final String englishName;
  final String nativeName;

  const AppLanguage(this.code, this.englishName, this.nativeName);
}

class LocaleNotifier extends StateNotifier<AppLanguage> {
  static const String _boxName = 'sessionBox';
  static const String _key = 'languageCode';

  LocaleNotifier() : super(AppLanguage.english) {
    _loadSavedLanguage();
  }

  void _loadSavedLanguage() {
    try {
      final box = Hive.box(_boxName);
      final savedCode = box.get(_key, defaultValue: 'en').toString();
      state = AppLanguage.values.firstWhere(
        (lang) => lang.code == savedCode,
        orElse: () => AppLanguage.english,
      );
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    try {
      final box = Hive.box(_boxName);
      await box.put(_key, language.code);
    } catch (_) {}
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
  return LocaleNotifier();
});

class Words {
  static final Map<AppLanguage, Map<String, String>> _localizedValues = {
    AppLanguage.english: {
      'app_title': 'ARISERS',
      'dashboard': 'Dashboard',
      'schedulers': 'Schedulers',
      'cyclic_timer': 'Cyclic Timer',
      'data_logs': 'Data Logs',
      'settings': 'Settings',
      'language': 'Language',
      'reconfig_device': 'Reconfigure Device (Bluetooth)',
      'logout': 'Logout',
      'logout_confirm': 'Are you sure you want to log out?',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'device_online': 'Device Online',
      'device_offline': 'Device Offline',
      'motor_1': 'Motor 1',
      'motor_2': 'Motor 2',
      'start_pulse': 'Start Pulse',
      'stop_pulse': 'Stop Pulse',
      'r_voltage': 'R Voltage',
      'y_voltage': 'Y Voltage',
      'b_voltage': 'B Voltage',
      'r_current': 'R Current',
      'y_current': 'Y Current',
      'b_current': 'B Current',
      'frequency': 'Frequency',
      'phase_sequence': 'Sequence',
      'fault_status': 'Fault Status',
      'no_fault': 'No fault',
      'add_schedule': 'Add Schedule',
      'on_time': 'ON Time',
      'off_time': 'OFF Time',
      'select_motor': 'Select Motor',
      'active': 'Active',
      'inactive': 'Inactive',
      'run_time_min': 'Run Time (Minutes)',
      'pause_time_min': 'Pause Time (Minutes)',
      'total_cycles': 'Total Cycles',
      'start_cycle': 'Start Cycle',
      'stop_cycle': 'Stop Cycle',
      'cycle_running': 'Cycle Running',
      'cycle_paused': 'Cycle Paused',
      'cycle_completed': 'Cycle Completed',
      'clear_logs': 'Clear Logs',
      'no_logs': 'No logs recorded yet',
      'trigger_manual': 'Manual',
      'trigger_schedule': 'Scheduler',
      'trigger_cyclic': 'Cyclic',
      'trigger_trip': 'Safety Trip',
    },
    AppLanguage.tamil: {
      'app_title': 'அரைசர்ஸ்',
      'dashboard': 'முகப்பு',
      'schedulers': 'நேர அட்டவணை',
      'cyclic_timer': 'சுழற்சி நேரம்',
      'data_logs': 'தரவு பதிவுகள்',
      'settings': 'அமைப்புகள்',
      'language': 'மொழி',
      'reconfig_device': 'ப்ளூடூத் இணைப்பு மாற்றம்',
      'logout': 'வெளியேறு',
      'logout_confirm': 'நிச்சயமாக வெளியேற விரும்புகிறீர்களா?',
      'cancel': 'ரத்து செய்',
      'confirm': 'உறுதி செய்',
      'device_online': 'கருவி இணைக்கப்பட்டுள்ளது',
      'device_offline': 'கருவி இணைக்கப்படவில்லை',
      'motor_1': 'மோட்டார் 1',
      'motor_2': 'மோட்டார் 2',
      'start_pulse': 'இயக்கு',
      'stop_pulse': 'நிறுத்து',
      'r_voltage': 'R மின்னழுத்தம்',
      'y_voltage': 'Y மின்னழுத்தம்',
      'b_voltage': 'B மின்னழுத்தம்',
      'r_current': 'R மின்னோட்டம்',
      'y_current': 'Y மின்னோட்டம்',
      'b_current': 'B மின்னோட்டம்',
      'frequency': 'அதிர்வெண்',
      'phase_sequence': 'வரிசை',
      'fault_status': 'பிழை நிலை',
      'no_fault': 'பிழை இல்லை',
      'add_schedule': 'அட்டவணை சேர்',
      'on_time': 'இயங்கும் நேரம்',
      'off_time': 'நிற்கும் நேரம்',
      'select_motor': 'மோட்டார் தேர்வு',
      'active': 'செயலில் உள்ளது',
      'inactive': 'செயலில் இல்லை',
      'run_time_min': 'இயங்கும் நேரம் (நிமிடம்)',
      'pause_time_min': 'நிற்கும் நேரம் (நிமிடம்)',
      'total_cycles': 'மொத்த சுழற்சிகள்',
      'start_cycle': 'சுழற்சி தொடங்கு',
      'stop_cycle': 'சுழற்சி நிறுத்து',
      'cycle_running': 'சுழற்சி இயங்குகிறது',
      'cycle_paused': 'சுழற்சி இடைநிறுத்தம்',
      'cycle_completed': 'சுழற்சி முடிந்தது',
      'clear_logs': 'பதிவுகளை அழி',
      'no_logs': 'பதிவுகள் எதுவும் இல்லை',
      'trigger_manual': 'கையேடு',
      'trigger_schedule': 'அட்டவணை',
      'trigger_cyclic': 'சுழற்சி',
      'trigger_trip': 'பாதுகாப்பு நிறுத்தம்',
    },
    AppLanguage.malayalam: {
      'app_title': 'അറൈസേഴ്സ്',
      'dashboard': 'ഹോം',
      'schedulers': 'ഷെഡ്യൂളുകൾ',
      'cyclic_timer': 'സൈക്ലിക് ടൈമർ',
      'data_logs': 'ഡാറ്റ ലോഗുകൾ',
      'settings': 'സജ്ജീകരണങ്ങൾ',
      'language': 'ഭാഷ',
      'reconfig_device': 'ബ്ലൂടൂത്ത് റീകൺഫിഗർ',
      'logout': 'ലോഗ് ഔട്ട്',
      'logout_confirm': 'തീർച്ചയായും ലോഗ് ഔട്ട് ചെയ്യണമെന്നുണ്ടോ?',
      'cancel': 'റദ്ദാക്കുക',
      'confirm': 'ഉറപ്പാക്കുക',
      'device_online': 'ഉപകരണം ഓൺലൈൻ',
      'device_offline': 'ഉപകരണം ഓഫ്ലൈൻ',
      'motor_1': 'മോട്ടോർ 1',
      'motor_2': 'മോട്ടോർ 2',
      'start_pulse': 'സ്റ്റാർട്ട്',
      'stop_pulse': 'സ്റ്റോപ്പ്',
      'r_voltage': 'R വോൾട്ടേജ്',
      'y_voltage': 'Y വോൾട്ടേജ്',
      'b_voltage': 'B വോൾട്ടേജ്',
      'r_current': 'R കറന്റ്',
      'y_current': 'Y കറന്റ്',
      'b_current': 'B കറന്റ്',
      'frequency': 'ഫ്രീക്വൻസി',
      'phase_sequence': 'സീക്വൻസ്',
      'fault_status': 'ഫോൾട്ട് സ്റ്റാറ്റസ്',
      'no_fault': 'ഫോൾട്ടുകൾ ഇല്ല',
      'add_schedule': 'ഷെഡ്യൂൾ ചേർക്കുക',
      'on_time': 'ഓൺ സമയം',
      'off_time': 'ഓഫ് സമയം',
      'select_motor': 'മോട്ടോർ തിരഞ്ഞെടുക്കുക',
      'active': 'ആക്ടീവ്',
      'inactive': 'ഇൻആക്ടീവ്',
      'run_time_min': 'റൺ സമയം (മിനിറ്റ്)',
      'pause_time_min': 'പോസ് സമയം (മിനിറ്റ്)',
      'total_cycles': 'ആകെ സൈക്കിളുകൾ',
      'start_cycle': 'സൈക്കിൾ ആരംഭിക്കുക',
      'stop_cycle': 'സൈക്കിൾ നിർത്തുക',
      'cycle_running': 'സൈക്കിൾ ഓടുന്നു',
      'cycle_paused': 'സൈക്കിൾ നിർത്തിവെച്ചു',
      'cycle_completed': 'സൈക്കിൾ പൂർത്തിയായി',
      'clear_logs': 'ലോഗുകൾ മായ്ക്കുക',
      'no_logs': 'ലോഗുകൾ ലഭ്യമല്ല',
      'trigger_manual': 'മാനുവൽ',
      'trigger_schedule': 'ഷെഡ്യൂൾ',
      'trigger_cyclic': 'സൈക്ലിക്',
      'trigger_trip': 'സേഫ്റ്റി ട്രിപ്പ്',
    },
    AppLanguage.telugu: {
      'app_title': 'అరైజర్స్',
      'dashboard': 'డాష్‌బోర్డ్',
      'schedulers': 'షెడ్యూలర్‌లు',
      'cyclic_timer': 'సైక్లిక్ టైమర్',
      'data_logs': 'డేటా లాగ్‌లు',
      'settings': 'సెట్టింగ్‌లు',
      'language': 'భాష',
      'reconfig_device': 'బ్లూటూత్ కాన్ఫిగరేషన్',
      'logout': 'లాగ్ అవుట్',
      'logout_confirm': 'మీరు ఖచ్చితంగా లాగ్ అవుట్ చేయాలనుకుంటున్నారా?',
      'cancel': 'రద్దు చేయి',
      'confirm': 'సరే',
      'device_online': 'పరికరం ఆన్‌లైన్',
      'device_offline': 'పరికరం ఆఫ్‌లైన్',
      'motor_1': 'మోటార్ 1',
      'motor_2': 'మోటార్ 2',
      'start_pulse': 'ప్రారంభించు',
      'stop_pulse': 'ఆపివేయి',
      'r_voltage': 'R వోల్టేజ్',
      'y_voltage': 'Y వోల్టేజ్',
      'b_voltage': 'B వోల్టేజ్',
      'r_current': 'R కరెంట్',
      'y_current': 'Y కరెంట్',
      'b_current': 'B కరెంట్',
      'frequency': 'ఫ్రీక్వెన్సీ',
      'phase_sequence': 'క్రమం',
      'fault_status': 'ఫాల్ట్ స్థితి',
      'no_fault': 'ఏ ఫాల్ట్ లేదు',
      'add_schedule': 'షెడ్యూల్ జోడించు',
      'on_time': 'ఆన్ సమయం',
      'off_time': 'ఆఫ్ సమయం',
      'select_motor': 'మోటార్ ఎంచుకోండి',
      'active': 'యాక్టివ్',
      'inactive': 'ఇన్యాక్టివ్',
      'run_time_min': 'రన్ సమయం (నిమిషాలు)',
      'pause_time_min': 'పాజ్ సమయం (నిమిషాలు)',
      'total_cycles': 'మొత్తం సైకిళ్లు',
      'start_cycle': 'సైకిల్ ప్రారంభించు',
      'stop_cycle': 'సైకిల్ ఆపివేయి',
      'cycle_running': 'సైకిల్ రన్ అవుతోంది',
      'cycle_paused': 'సైకిల్ పాజ్ చేయబడింది',
      'cycle_completed': 'సైకిల్ పూర్తయింది',
      'clear_logs': 'లాగ్‌లను క్లియర్ చేయి',
      'no_logs': 'డేటా లాగ్‌లు లేవు',
      'trigger_manual': 'మాన్యువల్',
      'trigger_schedule': 'షెడ్యూలర్',
      'trigger_cyclic': 'సైక్లిక్',
      'trigger_trip': 'సేఫ్టీ ట్రిప్',
    },
    AppLanguage.hindi: {
      'app_title': 'अराइजर्स',
      'dashboard': 'डैशबोर्ड',
      'schedulers': 'शेड्यूलर',
      'cyclic_timer': 'साइकिल टाइमर',
      'data_logs': 'डेटा लॉग',
      'settings': 'सेटिंग्स',
      'language': 'भाषा',
      'reconfig_device': 'ब्लूटूथ डिवाइस पुनः कॉन्फ़िगर',
      'logout': 'लॉग आउट',
      'logout_confirm': 'क्या आप निश्चित रूप से लॉग आउट करना चाहते हैं?',
      'cancel': 'रद्द करें',
      'confirm': 'पुष्टि करें',
      'device_online': 'डिवाइस ऑनलाइन',
      'device_offline': 'डिवाइस ऑफ़लाइन',
      'motor_1': 'मोटर 1',
      'motor_2': 'मोटर 2',
      'start_pulse': 'चालू करें',
      'stop_pulse': 'बंद करें',
      'r_voltage': 'R वोल्टेज',
      'y_voltage': 'Y वोल्टेज',
      'b_voltage': 'B वोल्टेज',
      'r_current': 'R करंट',
      'y_current': 'Y करंट',
      'b_current': 'B करंट',
      'frequency': 'फ्रीक्वेंसी',
      'phase_sequence': 'अनुक्रम',
      'fault_status': 'फॉल्ट स्थिति',
      'no_fault': 'कोई फॉल्ट नहीं',
      'add_schedule': 'शेड्यूल जोड़ें',
      'on_time': 'चालू समय',
      'off_time': 'बंद समय',
      'select_motor': 'मोटर चुनें',
      'active': 'सक्रिय',
      'inactive': 'निष्क्रिय',
      'run_time_min': 'चालू अवधि (मिनट)',
      'pause_time_min': 'विराम अवधि (मिनट)',
      'total_cycles': 'कुल चक्र',
      'start_cycle': 'चक्र शुरू करें',
      'stop_cycle': 'चक्र रोकें',
      'cycle_running': 'चक्र चल रहा है',
      'cycle_paused': 'चक्र रुका हुआ है',
      'cycle_completed': 'चक्र पूरा हुआ',
      'clear_logs': 'लॉग साफ़ करें',
      'no_logs': 'कोई लॉग उपलब्ध नहीं',
      'trigger_manual': 'मैनुअल',
      'trigger_schedule': 'शेड्यूलर',
      'trigger_cyclic': 'साइकिल',
      'trigger_trip': 'सुरक्षा ट्रिप',
    },
  };

  Map<String, String> get english => _localizedValues[AppLanguage.english]!;

  static String get(String key, AppLanguage language) {
    return _localizedValues[language]?[key] ??
        _localizedValues[AppLanguage.english]?[key] ??
        key;
  }
}

final wordsProvider = Provider((ref) => Words());
