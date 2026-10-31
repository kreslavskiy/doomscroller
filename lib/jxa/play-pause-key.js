// Presses the media play/pause key. Run with: osascript -l JavaScript play-pause-key.js
//
// F8 on a Mac keyboard sends this system-defined event (NX_KEYTYPE_PLAY, 16)
// rather than a key press, and macOS hands it to whatever is playing. A plain
// F8 key code would reach the page instead, which ignores it.
// Throws without Accessibility access, since the event would be dropped silently.

ObjC.import("Cocoa");
ObjC.import("ApplicationServices");

if (!$.AXIsProcessTrusted()) throw "no Accessibility access";

[0xa, 0xb].forEach(function (upDown) {  // key down, then key up
  $.CGEventPost(0, $.NSEvent.otherEventWithTypeLocationModifierFlagsTimestampWindowNumberContextSubtypeData1Data2(
    14, {x: 0, y: 0}, upDown << 8, 0, 0, $(), 8, (16 << 16) | (upDown << 8), -1).CGEvent);
});
