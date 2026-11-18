package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Cocoa
#import <Cocoa/Cocoa.h>

// An invisible window still renders and runs timers, which a hidden or
// minimized one does not, so the page keeps loading as it scrolls. It floats
// above other windows and follows the user between spaces, because the system
// also pauses a page whose window is fully covered or on another space.
static void windowInvisible(void *w) {
	NSWindow *win = (NSWindow *)w;
	[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
	[win setAlphaValue:0.0];
	[win setIgnoresMouseEvents:YES];
	[win setLevel:NSFloatingWindowLevel];
	[win setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
		NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorFullScreenAuxiliary];
	[win orderFrontRegardless];
}

static void windowVisible(void *w) {
	NSWindow *win = (NSWindow *)w;
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[win setAlphaValue:1.0];
	[win setIgnoresMouseEvents:NO];
	[win setLevel:NSNormalWindowLevel];
	[win setCollectionBehavior:NSWindowCollectionBehaviorDefault];
	[win center];
	[win makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}
*/
import "C"

import "unsafe"

func windowInvisible(w unsafe.Pointer) { C.windowInvisible(w) }
func windowVisible(w unsafe.Pointer)   { C.windowVisible(w) }
