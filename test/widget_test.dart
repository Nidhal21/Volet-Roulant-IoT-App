// ignore_for_file: cast_from_null_always_fails

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:weather_icons/weather_icons.dart';
import 'package:volet_roulant_app/providers/app_state.dart';
import 'package:volet_roulant_app/main.dart';

class MockAppState extends Mock implements AppState {
  final List<Schedule> _schedules = [];

  @override
  bool get isWindowOpen => super.noSuchMethod(
        Invocation.getter(#isWindowOpen),
        returnValue: false,
      ) as bool;

  @override
  WeatherData? get weatherData => super.noSuchMethod(
        Invocation.getter(#weatherData),
        returnValue: null,
      ) as WeatherData?;

  @override
  bool get gasDetected => super.noSuchMethod(
        Invocation.getter(#gasDetected),
        returnValue: false,
      ) as bool;

  @override
  bool get rainDetected => super.noSuchMethod(
        Invocation.getter(#rainDetected),
        returnValue: false,
      ) as bool;

  @override
  List<Schedule> get schedules => _schedules;

  @override
  String get city => super.noSuchMethod(
        Invocation.getter(#city),
        returnValue: '',
      ) as String;

  @override
  void toggleWindow() => super.noSuchMethod(
        Invocation.method(#toggleWindow, []),
        returnValueForMissingStub: null,
      );

  @override
  Future<void> addSchedule(String time, String action, String day) =>
      super.noSuchMethod(
        Invocation.method(#addSchedule, [time, action, day]),
        returnValue: Future.value(),
      ) as Future<void>;
}

void main() {
  late MockAppState mockAppState;

  setUp(() {
    mockAppState = MockAppState();

    // Stub getters.
    when(mockAppState.isWindowOpen).thenReturn(true);
    when(mockAppState.weatherData).thenReturn(
      WeatherData(
        main: 'Clear',
        description: 'clear sky',
        temperature: 20.0,
        humidity: 60,
        windSpeed: 3.0,
      ),
    );
    when(mockAppState.city).thenReturn('Paris');
    when(mockAppState.gasDetected).thenReturn(false);
    when(mockAppState.rainDetected).thenReturn(false);
    when(mockAppState.schedules).thenReturn(mockAppState._schedules);

    // Stub toggleWindow.
    when(mockAppState.toggleWindow()).thenAnswer((_) {
      final currentState = mockAppState.isWindowOpen;
      when(mockAppState.isWindowOpen).thenReturn(!currentState);
      return;
    });

    // Stub addSchedule.
    when(mockAppState.addSchedule(any as String, any as String, any as String)).thenAnswer((invocation) async {
      final time = invocation.positionalArguments[0] as String;
      final action = invocation.positionalArguments[1] as String;
      final day = invocation.positionalArguments[2] as String;
      mockAppState._schedules.add(Schedule(time: time, action: action, day: day));
      when(mockAppState.schedules).thenReturn(mockAppState._schedules);
      return;
    });
  });

  testWidgets(
      'HomePage displays weather details, window status, gas and rain status, and toggle button works',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => mockAppState,
        child: const MyApp(),
      ),
    );

    // Test UI elements.
    expect(find.text('Volet Roulant Hub'), findsOneWidget);
    expect(find.text('Clear Sky'), findsOneWidget);
    expect(find.text('Temp: 20.0°C'), findsOneWidget);
    expect(find.text('Humidity: 60%'), findsOneWidget);
    expect(find.text('Wind: 3.0 m/s'), findsOneWidget);
    expect(find.byIcon(WeatherIcons.day_sunny), findsOneWidget);
    expect(find.text('Window: Open'), findsOneWidget);
    expect(find.text('Gas: Clear'), findsOneWidget);
    expect(find.text('Rain: Clear'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    // Test toggle button.
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Window: Closed'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Window Closed'), findsOneWidget);
  });

  testWidgets('HomePage navigation to Details page and schedule display',
      (WidgetTester tester) async {
    // Add a mock schedule.
    when(mockAppState.schedules)
        .thenReturn([Schedule(time: '08:00', action: 'Open', day: 'Monday')]);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => mockAppState,
        child: const MyApp(),
      ),
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Control Center'), findsOneWidget);
    expect(find.text('Schedules'), findsOneWidget);
    expect(find.text('Monday at 08:00'), findsOneWidget);
    expect(find.text('Weather in Paris'), findsNothing);
    expect(find.byIcon(WeatherIcons.day_sunny), findsNothing);
  });

  testWidgets('HomePage adds schedule via dialog', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => mockAppState,
        child: const MyApp(),
      ),
    );

    // Tap the scheduling card to select time.
    await tester.tap(find.text('Select Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // Confirm time in TimePicker
    await tester.pumpAndSettle();

    // Select a day.
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();

    // Select an action.
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();

    // Add the schedule.
    await tester.tap(find.text('Schedule Now'));
    await tester.pumpAndSettle();

    // Verify the schedule is added.
    expect(find.text('Scheduled to Open on Monday at 08:00'), findsOneWidget);

    // Navigate to Details page to verify.
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Monday at 08:00'), findsOneWidget);
  });
}

// Mock Schedule class
class Schedule {
  final String time;
  final String action;
  final String day;

  Schedule({required this.time, required this.action, required this.day});

  @override
  String toString() => '$day at $time - $action';
}