// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animated_background/animated_background.dart';
import 'package:weather_icons/weather_icons.dart';
import 'package:volet_roulant_app/providers/app_state.dart';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _voiceText = 'Tap to Speak';
  TimeOfDay? _selectedTime;
  String _selectedDay = 'Monday';
  String _selectedAction = 'Open';
  bool _isScheduling = false;

  final List<String> _openSynonyms = [
    'open', 'raise', 'up', 'lift', 'start', 'begin',
  ];
  final List<String> _closeSynonyms = [
    'close', 'lower', 'down', 'shut', 'stop', 'end',
  ];
  final List<String> _daysOfWeek = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  void _startListening(AppState appState) async {
    if (!appState.hasFirebaseAccess) {
      setState(() => _voiceText = 'Please sign in to use voice commands');
      return;
    }
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          developer.log('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
              _voiceText = 'Tap to Speak';
            });
          }
        },
        onError: (error) {
          developer.log('Speech error: $error');
          setState(() {
            _isListening = false;
            _voiceText = 'Error: Try Again';
          });
        },
      );
      if (available) {
        setState(() {
          _isListening = true;
          _voiceText = 'Listening...';
        });
        Vibration.vibrate(duration: 200);
        _speech.listen(
          onResult: (result) {
            developer.log('Recognized: ${result.recognizedWords}, Final: ${result.finalResult}');
            setState(() {
              _voiceText = result.recognizedWords.isEmpty
                  ? 'Listening...'
                  : result.recognizedWords;
              if (result.finalResult) {
                _processCommand(appState, result.recognizedWords);
              }
            });
          },
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 5),
          partialResults: true,
        );
      } else {
        setState(() {
          _isListening = false;
          _voiceText = 'Speech Not Available';
        });
      }
    } else {
      _speech.stop();
      setState(() {
        _isListening = false;
        _voiceText = 'Tap to Speak';
      });
    }
  }

  void _processCommand(AppState appState, String command) {
    if (!appState.hasFirebaseAccess) {
      setState(() => _voiceText = 'Please sign in to use commands');
      return;
    }

    command = command.toLowerCase().trim();
    developer.log('Processing command: $command');

    RegExp scheduleRegex = RegExp(
      r'(open|close)\b(?:.*\bon\s+(\w+))?.*\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b',
      caseSensitive: false,
    );
    var match = scheduleRegex.firstMatch(command);
    if (match != null) {
      String action = match.group(1)!;
      String? day = match.group(2);
      String hour = match.group(3)!;
      String? minutes = match.group(4) ?? '00';
      String? period = match.group(5);

      developer.log('Schedule match: action=$action, day=$day, hour=$hour, minutes=$minutes, period=$period');

      String scheduledDay = day != null && _daysOfWeek.contains(day.toLowerCase())
          ? day.capitalize()
          : DateFormat('EEEE').format(DateTime.now());
      developer.log('No day specified, defaulting to: $scheduledDay');

      int hourInt = int.parse(hour);
      if (period != null) {
        if (period == 'pm' && hourInt != 12) hourInt += 12;
        if (period == 'am' && hourInt == 12) hourInt = 0;
      } else if (hourInt < 0 || hourInt > 23) {
        setState(() => _voiceText = 'Invalid hour: $hour');
        return;
      }
      String formattedTime = '${hourInt.toString().padLeft(2, '0')}:$minutes';

      try {
        DateFormat('HH:mm').parse(formattedTime);
        setState(() => _isScheduling = true);
        appState.addSchedule(formattedTime, action.capitalize(), scheduledDay).then((_) {
          setState(() {
            _isScheduling = false;
            _voiceText = 'Scheduled to $action on $scheduledDay at $formattedTime';
          });
          Vibration.vibrate(duration: 200);
        }).catchError((e) {
          setState(() {
            _isScheduling = false;
            _voiceText = 'Error scheduling: $e';
          });
        });
      } catch (e) {
        setState(() {
          _isScheduling = false;
          _voiceText = 'Invalid time format: $formattedTime';
        });
      }
      return;
    }

    bool isOpenCommand = _openSynonyms.any((synonym) => command.contains(synonym)) ||
        command.contains('open the window');
    bool isCloseCommand = _closeSynonyms.any((synonym) => command.contains(synonym)) ||
        command.contains('close the window');

    if (isOpenCommand && !isCloseCommand) {
      if (!appState.isWindowOpen) {
        appState.toggleWindow();
        setState(() => _voiceText = 'Window Opened Successfully');
        Vibration.vibrate(duration: 200);
      } else {
        setState(() => _voiceText = 'Window Already Open');
      }
    } else if (isCloseCommand && !isOpenCommand) {
      if (appState.isWindowOpen) {
        appState.toggleWindow();
        setState(() => _voiceText = 'Window Closed Successfully');
        Vibration.vibrate(duration: 200);
      } else {
        setState(() => _voiceText = 'Window Already Closed');
      }
    } else {
      setState(() => _voiceText = 'Unknown Command: $command');
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _addSchedule(AppState appState) {
    if (!appState.hasFirebaseAccess) {
      setState(() => _voiceText = 'Please sign in to schedule');
      return;
    }

    if (_selectedTime != null) {
      final formattedTime = DateFormat('HH:mm').format(
        DateTime(2023, 1, 1, _selectedTime!.hour, _selectedTime!.minute),
      );
      setState(() => _isScheduling = true);
      appState.addSchedule(formattedTime, _selectedAction, _selectedDay).then((_) {
        setState(() {
          _isScheduling = false;
          _voiceText = 'Scheduled to $_selectedAction on $_selectedDay at $formattedTime';
          _selectedTime = null;
        });
        Vibration.vibrate(duration: 200);
      }).catchError((e) {
        setState(() {
          _isScheduling = false;
          _voiceText = 'Error scheduling: $e';
        });
      });
    } else {
      setState(() => _voiceText = 'Please select a time');
    }
  }

  Future<bool> _confirmDeleteSchedule(BuildContext context, String scheduleDetails) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade900, Colors.teal.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.shade400.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Delete Schedule',
                    style: GoogleFonts.orbitron(
                      fontSize: 22,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Are you sure you want to delete this schedule?\n$scheduleDetails',
                    style: GoogleFonts.orbitron(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context, false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.orbitron(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.redAccent, Colors.red.shade700],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            'Delete',
                            style: GoogleFonts.orbitron(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).scale(),
          ),
        ) ??
        false;
  }

  IconData _getWeatherIcon(String main) {
    switch (main.toLowerCase()) {
      case 'clear':
        return WeatherIcons.day_sunny;
      case 'clouds':
        return WeatherIcons.cloudy;
      case 'rain':
        return WeatherIcons.rain;
      case 'snow':
        return WeatherIcons.snow;
      case 'thunderstorm':
        return WeatherIcons.thunderstorm;
      case 'mist':
      case 'fog':
        return WeatherIcons.fog;
      default:
        return WeatherIcons.na;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    if (!appState.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Volet Roulant Hub',
          style: GoogleFonts.orbitron(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
            tooltip: 'Profile',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                developer.log('Attempting to sign out...', name: 'HomePage');
                await appState.signOut();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              } catch (e) {
                developer.log('Sign-out failed: $e', name: 'HomePage', level: 1000);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sign-out failed: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: AnimatedBackground(
        behaviour: RandomParticleBehaviour(
          options: const ParticleOptions(
            baseColor: Colors.teal,
            spawnMinSpeed: 5.0,
            spawnMaxSpeed: 15.0,
            spawnMaxRadius: 2.0,
            particleCount: 20,
          ),
        ),
        vsync: this,
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [Colors.black.withOpacity(0.3), const Color(0xFF121212)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade900, Colors.teal.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.shade400.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 3,
                          offset: const Offset(3, 3),
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          spreadRadius: 3,
                          offset: Offset(-3, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                appState.weatherData != null
                                    ? appState.weatherData!.description.capitalize()
                                    : 'Weather: Loading...',
                                style: GoogleFonts.orbitron(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.teal),
                              onPressed: () async {
                                await appState.fetchWeather();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Refreshing weather...'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              tooltip: 'Refresh Weather',
                            ),
                          ],
                        ),
                        if (appState.weatherData != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Temp: ${appState.weatherData!.temperature.toStringAsFixed(1)}°C',
                                style: GoogleFonts.orbitron(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              Icon(
                                appState.weatherData != null
                                    ? _getWeatherIcon(appState.weatherData!.main)
                                    : WeatherIcons.na,
                                color: Colors.teal.shade200,
                                size: 24,
                              ),
                            ],
                          ),
                          Text(
                            'Humidity: ${appState.weatherData!.humidity}%',
                            style: GoogleFonts.orbitron(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            'Wind: ${appState.weatherData!.windSpeed} m/s',
                            style: GoogleFonts.orbitron(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Window: ${appState.isWindowOpen ? "Open" : "Closed"}',
                              style: GoogleFonts.orbitron(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                            Icon(
                              appState.isWindowOpen
                                  ? Icons.window
                                  : Icons.window_outlined,
                              color: Colors.teal.shade200,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Gas: ${appState.gasDetected ? "Detected" : "Clear"}',
                              style: GoogleFonts.orbitron(
                                fontSize: 14,
                                color: appState.gasDetected
                                    ? Colors.redAccent
                                    : Colors.white70,
                              ),
                            ),
                            Icon(
                              appState.gasDetected
                                  ? Icons.warning
                                  : Icons.check_circle,
                              color: appState.gasDetected
                                  ? Colors.redAccent
                                  : Colors.teal.shade200,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Rain: ${appState.rainDetected ? "Detected" : "Clear"}',
                              style: GoogleFonts.orbitron(
                                fontSize: 14,
                                color: appState.rainDetected
                                    ? Colors.redAccent
                                    : Colors.white70,
                              ),
                            ),
                            Icon(
                              appState.rainDetected
                                  ? Icons.warning
                                  : Icons.check_circle,
                              color: appState.rainDetected
                                  ? Colors.redAccent
                                  : Colors.teal.shade200,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => _startListening(appState),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          width: _isListening ? 200 : 180,
                          height: _isListening ? 200 : 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.teal.shade400
                                    .withOpacity(_isListening ? 0.2 : 0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: _isListening ? 150 : 140,
                          height: _isListening ? 150 : 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade400,
                                Colors.cyan.shade300,
                                Colors.blue.shade600,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.shade400
                                    .withOpacity(_isListening ? 0.5 : 0.3),
                                blurRadius: _isListening ? 20 : 12,
                                spreadRadius: _isListening ? 8 : 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _voiceText,
                    style: GoogleFonts.orbitron(
                      fontSize: 18,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                      shadows: [
                        Shadow(
                          color: Colors.teal.shade400.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFloatingButton(
                        text: appState.isWindowOpen ? 'Close' : 'Open',
                        icon: appState.isWindowOpen ? Icons.close : Icons.open_in_new,
                        onTap: () {
                          developer.log('Button pressed: ${appState.isWindowOpen ? "Closing" : "Opening"}');
                          if (appState.hasFirebaseAccess) {
                            appState.toggleWindow();
                            setState(() => _voiceText = appState.isWindowOpen
                                ? 'Window Opened'
                                : 'Window Closed');
                            Vibration.vibrate(duration: 100);
                          } else {
                            setState(() => _voiceText = 'Please sign in to toggle');
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildFloatingButton(
                        text: 'Schedule',
                        icon: Icons.calendar_today,
                        onTap: () => Navigator.pushNamed(context, '/details'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade800, Colors.teal.shade500],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.shade400.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 3,
                          offset: const Offset(3, 3),
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 10,
                          spreadRadius: 3,
                          offset: Offset(-3, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Schedule Window',
                          style: GoogleFonts.orbitron(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.teal.shade300.withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _selectTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedTime == null
                                      ? 'Select Time'
                                      : _selectedTime!.format(context),
                                  style: GoogleFonts.orbitron(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                                Icon(Icons.access_time, color: Colors.teal.shade200, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedDay,
                          decoration: InputDecoration(
                            labelText: 'Day',
                            labelStyle: GoogleFonts.orbitron(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.teal.shade700.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor: Colors.teal.shade900,
                          style: GoogleFonts.orbitron(color: Colors.white),
                          items: _daysOfWeek.map((String day) {
                            return DropdownMenuItem<String>(
                              value: day,
                              child: Text(day),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedDay = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedAction,
                          decoration: InputDecoration(
                            labelText: 'Action',
                            labelStyle: GoogleFonts.orbitron(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.teal.shade700.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor: Colors.teal.shade900,
                          style: GoogleFonts.orbitron(color: Colors.white),
                          items: ['Open', 'Close'].map((String action) {
                            return DropdownMenuItem<String>(
                              value: action,
                              child: Text(action),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedAction = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: GestureDetector(
                            onTap: _isScheduling || !appState.hasFirebaseAccess
                                ? null
                                : () => _addSchedule(appState),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _isScheduling || !appState.hasFirebaseAccess
                                      ? [Colors.grey.shade600, Colors.grey.shade400]
                                      : [Colors.teal.shade500, Colors.cyan.shade300],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.teal.shade400.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _isScheduling
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.schedule, color: Colors.white, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isScheduling ? 'Scheduling...' : 'Schedule Now',
                                    style: GoogleFonts.orbitron(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (appState.schedules.isNotEmpty) ...[
                          const Text(
                            'Existing Schedules',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 120,
                            child: ListView.builder(
                              itemCount: appState.schedules.length,
                              itemBuilder: (context, index) {
                                final schedule = appState.schedules[index];
                                return Card(
                                  color: const Color(0xFF1A1A1A),
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade400,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${schedule.day} at ${schedule.time}',
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${schedule.action} ${schedule.executed ? "(Executed)" : "(Pending)"}',
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 12,
                                                  color: schedule.executed ? Colors.greenAccent : Colors.white70,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            final scheduleDetails =
                                                '${schedule.day} at ${schedule.time} - ${schedule.action}';
                                            final confirmed =
                                                await _confirmDeleteSchedule(context, scheduleDetails);
                                            if (confirmed) {
                                              appState.removeSchedule(index);
                                              Vibration.vibrate(duration: 100);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Schedule deleted: $scheduleDetails',
                                                    style: GoogleFonts.orbitron(color: Colors.white),
                                                  ),
                                                  backgroundColor: Colors.redAccent,
                                                  duration: const Duration(seconds: 2),
                                                ),
                                              );
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.redAccent, Colors.red.shade700],
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.delete,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingButton({
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade400, Colors.cyan.shade300],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.shade400.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                text,
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}