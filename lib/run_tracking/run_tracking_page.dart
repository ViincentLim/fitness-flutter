import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class RunTrackingPage extends StatefulWidget {
  const RunTrackingPage({Key? key}) : super(key: key);

  @override
  State<RunTrackingPage> createState() => RunTrackingPageState();
}

enum ActivityState { NOT_STARTED, RUNNING, PAUSED, STOPPED }

class RunTrackingPageState extends State<RunTrackingPage>
    with TickerProviderStateMixin {
  // final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? _mapController;
  StreamSubscription<LocationData>? _locationListener;
  late Timer _periodicUpdateTimer;

  // TODO use shared pref to recall
  double latitude = 0;
  double longitude = 0;

  double zoom = 20;
  late LatLng startLocation = LatLng(latitude, longitude);
  LatLng? previousLocation;
  LatLng? currentLocation;
  double distanceTravelled = 0;

  bool _isTracking = false;

  // List<List<LatLng>> paths = [];
  final List<List<LatLng>> _paths = [];
  final Stopwatch _stopwatch = Stopwatch();
  // List<List<int>> pathsTiming = [];

  final Completer<void> _locationSetUp = Completer();

  ActivityState _activityState =
      ActivityState.NOT_STARTED; // NOT STARTED, RUNNING, PAUSED, STOPPED

  // todo move this to an inner widget?? along with TickerProviderStateMixin
  late final AnimationController _playButtonAnimationController =
      AnimationController(
    vsync: this,
    duration: const Duration(
      milliseconds: 800,
    ),
  );

  // late final Animation<double> _playButtonAnimation = CurvedAnimation(parent: _playButtonAnimationController, curve: Curves.ease);

  @override
  void initState() {
    autoUpdateLocation(); // rename this func ??
    _periodicUpdateTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    _periodicUpdateTimer.cancel();
    // TODO: implement dispose
    _mapController?.dispose();
    _playButtonAnimationController.dispose();
    _locationListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          GoogleMap(
            zoomControlsEnabled: false,
            polylines: {
              ..._paths.map((e) => Polyline(
                  width: 5,
                  points: e,
                  polylineId: PolylineId(e.hashCode.toString())))
            },
            initialCameraPosition: CameraPosition(
              target: currentLocation ?? startLocation,
              zoom: zoom,
            ),
            markers: {
              Marker(
                markerId: const MarkerId("source"),
                position: currentLocation ?? startLocation,
              ),
              // const Marker(
              //   markerId: MarkerId("source"),
              //   position: sourceLocation,
              // ),
              // const Marker(
              //   markerId: MarkerId("destination"),
              //   position: destination,
              // ),
            },
            onMapCreated: (mapController) {
              _mapController = mapController;
            },
          ),
          Container(
            color: Colors.white,
            height: 150,
            child: Column(
              children: [
                SizedBox(
                  height: 100,
                  child: Flex(
                    direction: Axis.horizontal,
                    children: [
                      StatisticTile(stat: (distanceTravelled/1000).toStringAsFixed(2), label: "km"),
                      StatisticTile(stat: durationToString(_stopwatch.elapsed), label: "time"),
                      StatisticTile(stat: distanceTravelled > 0 ? (durationToString(Duration(microseconds: _stopwatch.elapsedMicroseconds~/(distanceTravelled/1000)))) : "-", label: "min/km"),
                    ]
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // todo: animate the stop button inserting (AnimatedList?)
                    if (_activityState != ActivityState.NOT_STARTED)
                      IconButton(
                          onPressed: stopRun,
                          icon: const Icon(Icons.stop_rounded)),
                    IconButton(
                        onPressed: () {
                          switch (_activityState) {
                            case ActivityState.NOT_STARTED:
                              startRun();
                              break;
                            case ActivityState.RUNNING:
                              pauseRun();
                              break;
                            case ActivityState.PAUSED:
                              resumeRun();
                              break;
                            default:
                              break;
                            // case ActivityState.STOPPED:
                            //   break;
                          }
                        },
                        icon: AnimatedIcon(
                          icon: AnimatedIcons.play_pause,
                          progress: _playButtonAnimationController,
                        ))
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  String durationToString(Duration duration) {
    return "${duration.inHours.remainder(60)}:${duration.inMinutes.remainder(60).toString().padLeft(2, "0")}:${duration.inSeconds.remainder(60).toString().padLeft(2, "0")}";
  }

  double calculateDistanceInMetre(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  void startRun() async {
    _stopwatch.start();
    await _locationSetUp.future;
    _activityState = ActivityState.RUNNING;
    _playButtonAnimationController.forward();
    previousLocation = currentLocation;
    distanceTravelled = 0;
    _isTracking = true;
    _paths.add([]);
    setState(() {});
  }

  void resumeRun() {
    _stopwatch.start();
    _activityState = ActivityState.RUNNING;
    _playButtonAnimationController.forward();
    previousLocation = currentLocation;
    // distanceTravelled = 0;
    _isTracking = true;
    _paths.add([]);
  }

  void pauseRun() {
    _stopwatch.stop();
    _activityState = ActivityState.PAUSED;
    _playButtonAnimationController.reverse();
    // previousLocation = currentLocation;
    // distanceTravelled = 0;
    _isTracking = false;
  }

  void stopRun() {
    _stopwatch.stop();
    _activityState = ActivityState.STOPPED;
    // todo:
    // previousLocation = currentLocation;
    // distanceTravelled = 0;
    _isTracking = false;
    // todo: go to end page
  }

  void autoUpdateLocation() async {
    // TODO consider moving to geolocator or use try catch due to errors
    const int gpsUncertainty = 3;

    var location = Location();
    // if ((await location.hasPermission()) == PermissionStatus.denied) {
    //   await location.requestPermission();
    // }
    while (!await location.serviceEnabled()) {
      await location.requestService();
    }
    // while ((await location.hasPermission()) == PermissionStatus.denied) {
    //   await location.requestPermission();
    // }
    var locationData = await location.getLocation();
    await location.changeSettings(accuracy: LocationAccuracy.high);
    // await location.enableBackgroundMode(enable: true);
    if (!await location.isBackgroundModeEnabled()) {
      do {
        // const AlertDialog(title: Text("You need to allow the app to access location all the time (in background) to proceed"),);
        await showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text(
                'You need to allow the app to access location all the time (in background) to proceed'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, 'OK'),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        // await location.enableBackgroundMode();
      } while (!await location.enableBackgroundMode(enable: true));
    }
    latitude = locationData.latitude!;
    longitude = locationData.longitude!;
    currentLocation = LatLng(latitude, longitude);
    _locationSetUp.complete();
    // _mapController?.animateCamera(CameraUpdate.zoomBy(zoom));

    _locationListener ??=
        location.onLocationChanged.listen((locationData) async {
      latitude = locationData.latitude!;
      longitude = locationData.longitude!;

      currentLocation = LatLng(latitude, longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLng(currentLocation!));

      // When app is tracking run (run started or resumed, not paused or stopped)
      if (_isTracking) {
        double deltaDistance = calculateDistanceInMetre(
            previousLocation?.latitude,
            previousLocation?.longitude,
            currentLocation?.latitude,
            currentLocation?.longitude);

        bool isSignificantChange = deltaDistance > gpsUncertainty;
        if (isSignificantChange) {
          _paths.last.add(currentLocation!);
          distanceTravelled += deltaDistance;
          previousLocation = currentLocation;
          // setState(() {});
        }
      }
      // setState(() {});
    });
  }
}

class StatisticTile extends StatelessWidget {
  const StatisticTile({Key? key, required this.stat, required this.label}) : super(key: key);

  final String stat;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListTile(
        title: Text(
          stat,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(label, textAlign: TextAlign.center,),
      ),
    );
  }
}
