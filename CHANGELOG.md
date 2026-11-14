# Changelog

## 0.6.2

- Make Click V2 setup resilient across iOS and other Bluetooth stacks by
  finding characteristics across all discovered services, treating sync-tx as
  optional, and preferring write-without-response for the activation sequence.
- Handle the controller's `0xFF 0x03` challenge on the async characteristic,
  where Click V2 hardware actually sends it.
- Report the exact failing connection stage to host applications.

## 0.6.1

- Preserve the distinction between an unavailable FTMS power field and a real
  zero-watt/coasting measurement in `OpenRoadFrame` and ride samples.

## 0.6.0

- Discover and connect both controllers in a Zwift Click V2 pair.
- Decode button edges, deduplicate the pair's mirrored frames, and expose a
  host-neutral controller event stream.
- Keep FTMS trainer, heart-rate, and Click V2 connections independent so a host
  can use all three accessories during the same ride.
- Release held buttons and disconnect every controller explicitly at ride end.

## 0.5.0

- Discover and connect standard Bluetooth Heart Rate Service devices,
  including Garmin watches in Broadcast Heart Rate mode and BLE straps.
- Decode both 8-bit and 16-bit Heart Rate Measurement packets.
- Expose heart-rate device, value, connection, and disconnect streams to host
  applications independently of the FTMS trainer connection.

## 0.4.1

- Stop active Bluetooth discovery before connecting to improve reliability on
  single-link trainers such as the Van Rysel D100.
- Disconnect cleanly after a failed FTMS setup so the trainer's Bluetooth slot
  is immediately available for a retry.

## 0.4.0

- `OpenRoad.pause()` now holds the virtual rider in place until `resume()`;
  previously the route position kept advancing while paused.
- `OpenRoad.stop()` ends the virtual ride while keeping the trainer connected.
- `OpenRoad.connectionUpdates` and `OpenRoad.connected` report when the
  trainer drops, so the host can pause and offer a reconnect.
- `OpenRoad.bluetoothOn()` lets the host explain a switched-off adapter
  instead of showing an empty scan.

## 0.3.0

- Add 24-speed OpenRoad virtual gearing for fixed-sprocket and Zwift Cog setups.
- Apply gear changes through standards-based FTMS simulation parameters.
- Expose effective trainer grade and current virtual gear to host applications.

## 0.2.0

- Add the pure OpenRoad power/gradient physics engine.
- Model rider and bike weight, CdA, rolling resistance, drivetrain loss, wind,
  and air density.
- Decode FTMS resistance and heart-rate data alongside speed, cadence, power.

## 0.1.0

- Parse GPX tracks and routes locally.
- Read speed, cadence, and power from Bluetooth FTMS Indoor Bike Data.
- Apply GPX gradient through FTMS Indoor Bike Simulation Parameters.
- Support the Van Rysel D100 and other standards-compliant FTMS trainers.
