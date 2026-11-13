# Changelog

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
