import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class Schedule {
  final String time;
  final String action;
  final String day;
  bool executed;

  Schedule({
    required this.time,
    required this.action,
    required this.day,
    this.executed = false,
  });

  Map<String, dynamic> toJson() =>
      {'time': time, 'action': action, 'day': day, 'executed': executed};

  static Schedule fromJson(Map<String, dynamic> json) => Schedule(
        time: json['time'],
        action: json['action'],
        day: json['day'] ?? 'Monday',
        executed: json['executed'] ?? false,
      );
}

class SmokeEvent {
  final String timestamp;
  final bool detected;

  SmokeEvent({required this.timestamp, required this.detected});

  Map<String, dynamic> toJson() =>
      {'timestamp': timestamp, 'detected': detected};

  static SmokeEvent fromJson(Map<String, dynamic> json) => SmokeEvent(
        timestamp: json['timestamp'],
        detected: json['detected'],
      );
}

class WeatherData {
  final String main;
  final String description;
  final double temperature;
  final int humidity;
  final double windSpeed;

  WeatherData({
    required this.main,
    required this.description,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
  });
}

class AppState with ChangeNotifier {
  bool _isWindowOpen = false;
  WeatherData? weatherData;
  bool _gasDetected = false;
  bool _rainDetected = false;
  bool? _lastGasDetected;
  bool? _lastRainDetected;
  List<Schedule> _schedules = [];
  final List<SmokeEvent> _smokeEvents = [];
  String _city = 'Paris';
  String? _lastWeatherMain;
  String? _lastScheduleDay;
  bool _isInitialized = false;
  bool _hasFirebaseAccess = false;

  late final FlutterLocalNotificationsPlugin _notificationsPlugin;
  DatabaseReference? _dbRef;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseAnalytics _analytics;
  Timer? _scheduleTimer;
  StreamSubscription<User?>? _authStateSubscription;

  AppState() {
    developer.log('Initializing AppState...', name: 'AppState', level: 700);
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    _analytics = FirebaseAnalytics.instance;
    notifyListeners();
    _initializeAsync();
  }

  bool get isWindowOpen => _isWindowOpen;
  bool get gasDetected => _gasDetected;
  bool get rainDetected => _rainDetected;
  List<Schedule> get schedules => _schedules;
  List<SmokeEvent> get smokeEvents => _smokeEvents;
  String get city => _city;
  bool get isInitialized => _isInitialized;
  bool get hasFirebaseAccess => _hasFirebaseAccess;

  Future<void> _initializeAsync() async {
    developer.log('Starting async initialization...',
        name: 'AppState', level: 700);
    try {
      developer.log('Step 1: Initializing notifications...',
          name: 'AppState', level: 700);
      await _initializeNotifications();
      developer.log('Notifications initialized', name: 'AppState', level: 700);

      developer.log('Step 2: Loading city...', name: 'AppState', level: 700);
      await _loadCity();
      developer.log('City loaded: $_city', name: 'AppState', level: 700);

      developer.log('Step 3: Loading schedules in background...',
          name: 'AppState', level: 700);
      await _loadSchedules();
      developer.log('Schedules loaded: $_schedules',
          name: 'AppState', level: 700);

      developer.log('Step 4: Fetching weather in background...',
          name: 'AppState', level: 700);
      await fetchWeather();
      developer.log('Weather fetched: ${weatherData?.main}',
          name: 'AppState', level: 700);

      developer.log('Step 5: Starting auth listener...',
          name: 'AppState', level: 700);
      await _startAuthListener();
      developer.log('Step 6: Starting schedule timer...',
          name: 'AppState', level: 700);
      _startScheduleTimer();
      developer.log('Auth listener and schedule timer started',
          name: 'AppState', level: 700);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      developer.log('Async initialization failed: $e',
          name: 'AppState', level: 1000);
      _isInitialized = true;
      notifyListeners();
    }
  }

  static Future<List<Schedule>> _loadSchedulesIsolate(
      String? scheduleJson) async {
    developer.log('Loading schedules in isolate...',
        name: 'AppState', level: 700);
    if (scheduleJson == null) {
      return [];
    }
    final List<dynamic> decoded = jsonDecode(scheduleJson);
    final schedules = decoded.map((json) => Schedule.fromJson(json)).toList();
    developer.log('Loaded schedules in isolate: $schedules',
        name: 'AppState', level: 700);
    return schedules;
  }

  Future<void> _startAuthListener() async {
    developer.log('Starting auth listener...', name: 'AppState', level: 700);
    _authStateSubscription = _auth.authStateChanges().listen(
      (User? user) async {
        if (user != null) {
          developer.log('User authenticated: ${user.uid}',
              name: 'AppState', level: 700);
          _hasFirebaseAccess = true;
          _dbRef = FirebaseDatabase.instance.ref();
          _initializeFirebaseListeners();
          await _fetchInitialFirebaseData();

          await _analytics.logLogin(loginMethod: 'email_password');
          developer.log('Logged login event for user: ${user.uid}',
              name: 'AppState', level: 700);
        } else {
          developer.log('User not authenticated', name: 'AppState', level: 700);
          _hasFirebaseAccess = false;
          _isWindowOpen = false;
          _gasDetected = false;
          _rainDetected = false;
          _lastGasDetected = null;
          _lastRainDetected = null;
          _isInitialized = true;
          notifyListeners();
        }
      },
      onError: (error) {
        developer.log('Auth state listener error: $error',
            name: 'AppState', level: 1000);
        _hasFirebaseAccess = false;
        _isInitialized = true;
        notifyListeners();
      },
    );
  }

  void _startScheduleTimer() {
    developer.log('Starting schedule timer...', name: 'AppState', level: 700);
    _scheduleTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkSchedules();
    });
  }

  void _checkSchedules() {
    final now = DateTime.now();
    final currentTime = DateFormat('HH:mm').format(now);
    final currentDay = DateFormat('EEEE').format(now);

    developer.log('Checking schedules at $currentTime on $currentDay',
        name: 'AppState', level: 700);

    if (_lastScheduleDay != currentDay) {
      for (var schedule in _schedules) {
        schedule.executed = false;
      }
      _lastScheduleDay = currentDay;
      _saveSchedules();
    }

    for (var schedule in _schedules) {
      if (!schedule.executed &&
          schedule.time == currentTime &&
          schedule.day == currentDay) {
        developer.log(
            'Executing schedule: ${schedule.day} at ${schedule.time} - ${schedule.action}',
            name: 'AppState',
            level: 700);
        if (schedule.action == 'Open' && !_isWindowOpen) {
          toggleWindow();
          developer.log('Window opened by schedule',
              name: 'AppState', level: 700);
        } else if (schedule.action == 'Close' && _isWindowOpen) {
          toggleWindow();
          developer.log('Window closed by schedule',
              name: 'AppState', level: 700);
        } else {
          developer.log(
              'No action taken: Window already in desired state (${_isWindowOpen ? "Open" : "Closed"})',
              name: 'AppState',
              level: 700);
        }
        schedule.executed = true;
        _saveSchedules();
        notifyListeners();
      }
    }
  }

  Future<void> _initializeNotifications() async {
    developer.log('Initializing notifications...',
        name: 'AppState', level: 700);
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      bool? granted = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (granted == true) {
        await _notificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            developer.log('Notification tapped: ${response.payload}',
                name: 'AppState', level: 700);
            _analytics.logEvent(
              name: 'notification_interaction',
              parameters: {
                'payload': response.payload ?? 'unknown',
              },
            );
            developer.log(
                'Logged notification_interaction event with payload: ${response.payload}',
                name: 'AppState',
                level: 700);
          },
        );
        developer.log('Notifications initialized successfully',
            name: 'AppState', level: 700);
      } else {
        developer.log('Notification permissions not granted',
            name: 'AppState', level: 700);
      }
    } catch (e) {
      developer.log('Failed to initialize notifications: $e',
          name: 'AppState', level: 1000);
    }
  }

  Future<void> _fetchInitialFirebaseData() async {
    developer.log('Fetching initial Firebase data...',
        name: 'AppState', level: 700);
    if (!_hasFirebaseAccess || _dbRef == null) {
      developer.log(
          'Cannot fetch initial Firebase data: User not authenticated or Firebase not initialized',
          name: 'AppState',
          level: 700);
      _isInitialized = true;
      notifyListeners();
      return;
    }

    try {
      developer.log('Fetching window state...', name: 'AppState', level: 700);
      final windowSnapshot = await _dbRef!
          .child('window/state')
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Timed out fetching window state');
      });
      if (windowSnapshot.exists && windowSnapshot.value is bool) {
        _isWindowOpen = windowSnapshot.value as bool;
        developer.log(
            'Initial window state: ${_isWindowOpen ? "Open" : "Closed"}',
            name: 'AppState',
            level: 700);
      } else {
        developer.log('Invalid or missing window/state data',
            name: 'AppState', level: 700);
        _isWindowOpen = false;
      }

      developer.log('Fetching gas sensor data...',
          name: 'AppState', level: 700);
      final gasSnapshot = await _dbRef!
          .child('sensor/gas')
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Timed out fetching gas sensor data');
      });
      if (gasSnapshot.exists && gasSnapshot.value is String) {
        _gasDetected = (gasSnapshot.value as String) == '1';
        _lastGasDetected = _gasDetected;
        developer.log('Initial gas state: $_gasDetected',
            name: 'AppState', level: 700);
      } else {
        developer.log('Invalid or missing sensor/gas data',
            name: 'AppState', level: 700);
        _gasDetected = false;
      }

      developer.log('Fetching rain sensor data...',
          name: 'AppState', level: 700);
      final rainSnapshot = await _dbRef!
          .child('sensor/rain')
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Timed out fetching rain sensor data');
      });
      if (rainSnapshot.exists && rainSnapshot.value is String) {
        _rainDetected = (rainSnapshot.value as String) == '1';
        _lastRainDetected = _rainDetected;
        developer.log('Initial rain state: $_rainDetected',
            name: 'AppState', level: 700);
      } else {
        developer.log('Invalid or missing sensor/rain data',
            name: 'AppState', level: 700);
        _rainDetected = false;
      }

      developer.log('Firebase data fetched successfully',
          name: 'AppState', level: 700);
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      developer.log('Error fetching initial Firebase data: $e',
          name: 'AppState', level: 1000);
      _hasFirebaseAccess = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  void _initializeFirebaseListeners() {
    developer.log('Initializing Firebase listeners...',
        name: 'AppState', level: 700);
    if (!_hasFirebaseAccess || _dbRef == null) {
      developer.log(
          'Cannot initialize Firebase listeners: User not authenticated or Firebase not initialized',
          name: 'AppState',
          level: 700);
      return;
    }

    developer.log('Setting up window/state listener...',
        name: 'AppState', level: 700);
    _dbRef!.child('window/state').onValue.listen(
      (event) {
        final value = event.snapshot.value;
        if (value is bool) {
          if (value != _isWindowOpen) {
            _isWindowOpen = value;
            developer.log(
                'Window state updated via Firebase: ${_isWindowOpen ? "Open" : "Closed"}',
                name: 'AppState',
                level: 700);
            _analytics.logEvent(
              name: 'window_state_change',
              parameters: {
                'state': _isWindowOpen ? 'open' : 'closed',
                'source': 'firebase_listener',
              },
            );
            developer.log(
                'Logged window_state_change event: ${_isWindowOpen ? "open" : "closed"}',
                name: 'AppState',
                level: 700);
            notifyListeners();
          }
        } else {
          developer.log('Invalid window/state value: $value (expected bool)',
              name: 'AppState', level: 700);
        }
      },
      onError: (error) {
        developer.log('Error listening to window/state: $error',
            name: 'AppState', level: 1000);
        _hasFirebaseAccess = false;
        notifyListeners();
      },
    );

    developer.log('Setting up sensor/gas listener...',
        name: 'AppState', level: 700);
    _dbRef!.child('sensor/gas').onValue.listen(
      (event) {
        final value = event.snapshot.value;
        if (value is String) {
          final newGasDetected = value == '1';
          if (_gasDetected != newGasDetected) {
            _gasDetected = newGasDetected;
            _smokeEvents.add(SmokeEvent(
              timestamp: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
              detected: _gasDetected,
            ));
            if (_lastGasDetected == null || _lastGasDetected != _gasDetected) {
              if (_gasDetected) {
                _isWindowOpen = true;
                toggleWindow();
                _showNotification('Gas Alert', 'Gas detected! Window opened.',
                    'smoke_detected');
              } else {
                _showNotification('Gas Cleared',
                    'Gas cleared. Situation normal.', 'smoke_cleared');
              }
              _analytics.logEvent(
                name: 'gas_detection',
                parameters: {
                  'detected': _gasDetected,
                },
              );
              developer.log(
                  'Logged gas_detection event: detected=$_gasDetected',
                  name: 'AppState',
                  level: 700);
            }
            _lastGasDetected = _gasDetected;
            notifyListeners();
          }
        } else {
          developer.log('Invalid sensor/gas value: $value (expected string)',
              name: 'AppState', level: 700);
        }
      },
      onError: (error) {
        developer.log('Error listening to sensor/gas: $error',
            name: 'AppState', level: 1000);
        _hasFirebaseAccess = false;
        notifyListeners();
      },
    );

    developer.log('Setting up sensor/rain listener...',
        name: 'AppState', level: 700);
    _dbRef!.child('sensor/rain').onValue.listen(
      (event) {
        final value = event.snapshot.value;
        if (value is String) {
          final newRainDetected = value == '1';
          if (_rainDetected != newRainDetected) {
            _rainDetected = newRainDetected;
            if (_lastRainDetected == null ||
                _lastRainDetected != _rainDetected) {
              if (_rainDetected) {
                _isWindowOpen = false;
                toggleWindow();
                _showNotification('Rain Alert', 'Rain detected! Window closed.',
                    'rain_detected');
              } else {
                _showNotification('Rain Cleared',
                    'Rain cleared. Situation normal.', 'rain_cleared');
              }
              _analytics.logEvent(
                name: 'rain_detection',
                parameters: {
                  'detected': _rainDetected,
                },
              );
              developer.log(
                  'Logged rain_detection event: detected=$_rainDetected',
                  name: 'AppState',
                  level: 700);
            }
            _lastRainDetected = _rainDetected;
            notifyListeners();
          }
        } else {
          developer.log('Invalid sensor/rain value: $value (expected string)',
              name: 'AppState', level: 700);
        }
      },
      onError: (error) {
        developer.log('Error listening to sensor/rain: $error',
            name: 'AppState', level: 1000);
        _hasFirebaseAccess = false;
        notifyListeners();
      },
    );
  }

  Future<void> _showNotification(
      String title, String body, String payload) async {
    developer.log('Showing notification: $title - $body',
        name: 'AppState', level: 700);
    try {
      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch % 10000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'weather_smoke_channel',
            'Weather and Smoke Alerts',
            channelDescription:
                'Notifications for weather changes and smoke detection',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
      developer.log('Notification shown successfully',
          name: 'AppState', level: 700);
      await _analytics.logEvent(
        name: 'notification_shown',
        parameters: {
          'title': title,
          'payload': payload,
        },
      );
      developer.log('Logged notification_shown event: $title',
          name: 'AppState', level: 700);
    } catch (e) {
      developer.log('Failed to show notification: $e',
          name: 'AppState', level: 1000);
    }
  }

  Future<void> _loadCity() async {
    developer.log('Loading city from SharedPreferences...',
        name: 'AppState', level: 700);
    try {
      final prefs = await SharedPreferences.getInstance();
      _city = prefs.getString('city') ?? 'Tunis';
      developer.log('City loaded: $_city', name: 'AppState', level: 700);
      await fetchWeather();
    } catch (e) {
      developer.log('Failed to load city: $e', name: 'AppState', level: 1000);
      _city = 'Tunis';
      await fetchWeather();
    }
    notifyListeners();
  }

  Future<void> setCity(String newCity) async {
    developer.log('Setting city to: $newCity', name: 'AppState', level: 700);
    try {
      _city = newCity;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('city', newCity);
      await fetchWeather();
      notifyListeners();
    } catch (e) {
      developer.log('Failed to set city: $e', name: 'AppState', level: 1000);
      notifyListeners();
    }
  }

  Future<void> fetchWeather() async {
    const apiKey = '27f4f6a0bd0f142a5d60869b5535c23f';
    final url = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?q=$_city&appid=$apiKey&units=metric');

    developer.log('Fetching weather for $_city', name: 'AppState', level: 700);
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      developer.log(
          'Weather API response: ${response.statusCode} ${response.body}',
          name: 'AppState',
          level: 700);

      if (response.statusCode == 200) {
        final data = await compute(jsonDecode, response.body);
        final newWeatherData = WeatherData(
          main: data['weather'][0]['main'],
          description: data['weather'][0]['description'],
          temperature: data['main']['temp'].toDouble(),
          humidity: data['main']['humidity'],
          windSpeed: data['wind']['speed'].toDouble(),
        );

        if (_lastWeatherMain == 'Clear' &&
            ['Rain', 'Thunderstorm', 'Drizzle'].contains(newWeatherData.main)) {
          _isWindowOpen = false;
          toggleWindow();
          await _showNotification(
            'Weather Alert',
            'Weather changed from sunny to ${newWeatherData.description} in $_city',
            'weather_change',
          );
        }

        _lastWeatherMain = newWeatherData.main;
        weatherData = newWeatherData;
      } else {
        developer.log('Weather API failed with status: ${response.statusCode}',
            name: 'AppState', level: 700);
        weatherData = WeatherData(
          main: 'Error',
          description: 'Failed to fetch weather (Code: ${response.statusCode})',
          temperature: 0,
          humidity: 0,
          windSpeed: 0,
        );
      }
    } catch (e) {
      developer.log('Weather fetch error: $e', name: 'AppState', level: 1000);
      weatherData = WeatherData(
        main: 'Error',
        description: 'Error fetching weather: $e',
        temperature: 0,
        humidity: 0,
        windSpeed: 0,
      );
    }
    notifyListeners();
  }

  void toggleWindow() {
    if (!_hasFirebaseAccess || _dbRef == null) {
      developer.log(
          'Cannot toggle window: User not authenticated or Firebase not initialized',
          name: 'AppState',
          level: 700);
      return;
    }

    _isWindowOpen = !_isWindowOpen;
    developer.log('Toggling window to: ${_isWindowOpen ? "Open" : "Closed"}',
        name: 'AppState', level: 700);

    _dbRef!.child('window/state').set(_isWindowOpen).catchError((error) {
      developer.log('Firebase write failed for window/state: $error',
          name: 'AppState', level: 1000);
      _isWindowOpen = !_isWindowOpen;
      _hasFirebaseAccess = false;
      notifyListeners();
    }).whenComplete(() {
      developer.log('Window state updated in Firebase: $_isWindowOpen',
          name: 'AppState', level: 700);
      _analytics.logEvent(
        name: 'window_state_change',
        parameters: {
          'state': _isWindowOpen ? 'open' : 'closed',
          'source': 'manual_toggle',
        },
      );
      developer.log(
          'Logged window_state_change event: ${_isWindowOpen ? "open" : "closed"}',
          name: 'AppState',
          level: 700);
      notifyListeners();
    });
  }

  Future<void> addSchedule(String time, String action, String day) async {
    developer.log('Adding schedule: $day at $time - $action',
        name: 'AppState', level: 700);
    try {
      DateFormat('HH:mm').parse(time);
      _schedules.add(Schedule(time: time, action: action, day: day));
      await _saveSchedules();
      notifyListeners();
    } catch (e) {
      developer.log(
          'Failed to add schedule: Invalid time format $time, error: $e',
          name: 'AppState',
          level: 1000);
      throw Exception('Invalid time format: $time');
    }
  }

  Future<void> removeSchedule(int index) async {
    if (index >= 0 && index < _schedules.length) {
      final removedSchedule = _schedules[index];
      _schedules.removeAt(index);
      await _saveSchedules();
      developer.log(
          'Removed schedule: ${removedSchedule.day} at ${removedSchedule.time}',
          name: 'AppState',
          level: 700);
      notifyListeners();
    }
  }

  Future<void> _saveSchedules() async {
    developer.log('Saving schedules...', name: 'AppState', level: 700);
    try {
      final prefs = await SharedPreferences.getInstance();
      final scheduleJson = _schedules.map((s) => s.toJson()).toList();
      await prefs.setString('schedules', jsonEncode(scheduleJson));
      developer.log('Saved schedules to SharedPreferences: $scheduleJson',
          name: 'AppState', level: 700);
    } catch (e) {
      developer.log('Failed to save schedules: $e',
          name: 'AppState', level: 1000);
      throw Exception('Failed to save schedules: $e');
    }
  }

  Future<void> _loadSchedules() async {
    developer.log('Loading schedules from SharedPreferences...',
        name: 'AppState', level: 700);
    try {
      final prefs = await SharedPreferences.getInstance();
      final scheduleJson = prefs.getString('schedules');
      _schedules = await compute(_loadSchedulesIsolate, scheduleJson);
      developer.log('Loaded schedules: $_schedules',
          name: 'AppState', level: 700);
      notifyListeners();
    } catch (e) {
      developer.log('Failed to load schedules: $e',
          name: 'AppState', level: 1000);
      _schedules = [];
      notifyListeners();
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    developer.log('Attempting sign-in with email: $email',
        name: 'AppState', level: 700);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      developer.log('Sign-in successful for email: $email',
          name: 'AppState', level: 700);
    } catch (e) {
      developer.log('Sign-in failed: $e', name: 'AppState', level: 1000);
      rethrow;
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    developer.log('Attempting sign-up with email: $email',
        name: 'AppState', level: 700);
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      developer.log('Sign-up successful for email: $email',
          name: 'AppState', level: 700);
    } catch (e) {
      developer.log('Sign-up failed: $e', name: 'AppState', level: 1000);
      rethrow;
    }
  }

  Future<void> signOut() async {
    developer.log('Signing out...', name: 'AppState', level: 700);
    try {
      await _auth.signOut();
      developer.log('User signed out successfully',
          name: 'AppState', level: 700);
      _hasFirebaseAccess = false;
      _isInitialized = false;
      _schedules.clear();
      _smokeEvents.clear();
      notifyListeners();
      await _analytics.logEvent(
        name: 'sign_out',
        parameters: {
          'method': 'email_password',
        },
      );
      developer.log('Logged sign_out event', name: 'AppState', level: 700);
    } catch (e) {
      developer.log('Sign-out failed: $e', name: 'AppState', level: 1000);
      throw Exception('Sign-out failed: $e');
    }
  }

  void clearSchedules() {
    developer.log('Clearing all schedules...', name: 'AppState', level: 700);
    _schedules.clear();
    _saveSchedules();
    notifyListeners();
  }

  @override
  void dispose() {
    developer.log('Disposing AppState...', name: 'AppState', level: 700);
    _scheduleTimer?.cancel();
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
