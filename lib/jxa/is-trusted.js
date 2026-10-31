// Prints whether the app running this has Accessibility access, which
// pressing keys needs. Run with: osascript -l JavaScript is-trusted.js

ObjC.import("ApplicationServices");

$.AXIsProcessTrusted();
