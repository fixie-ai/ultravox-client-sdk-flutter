## 0.0.1

* Initial implementation.

## 0.0.2

* Add support for experimental messages.

## 0.0.3

* Add mute/unmute support.
* Break apart state into separate notifiers.
* Update example app to take advantage of both (plus sendText).

## 0.0.4

* Changed implementation of mute/unmute. It's now `micMuted` and `speakerMuted`
* Added functions for toggling mute of mic (`toggleMicMuted()`) and speaker (`toggleSpeakerMuted()`)

## 0.0.5

* Add client-implemented tools

# 0.0.6

* Add ability to set the output medium.

# 0.0.7

* Start informing the server of the client version and API version.
* Use simplifed `transcript` messages.
* Expose `sendData` and `dataMessageNotifier` for bleeding edge use cases.
* Update dependencies.

# 0.0.8

* Send large data messages over our websocket instead of the WebRTC data channel to avoid dropped UDP packets.
